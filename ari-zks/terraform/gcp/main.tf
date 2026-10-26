terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# -----------------------------------------------------------------------------
# Nom auto-généré (unicité garantie sur GCP)
# -----------------------------------------------------------------------------

resource "random_id" "app_suffix" {
  byte_length = 4
}

# -----------------------------------------------------------------------------
# Secrets auto-générés si non fournis
# -----------------------------------------------------------------------------

resource "random_id" "encryption_key" {
  count       = var.encryption_key == "" ? 1 : 0
  byte_length = 32
}

resource "random_id" "revolv_shared_secret" {
  count       = var.revolv_shared_secret == "" ? 1 : 0
  byte_length = 32
}

locals {
  app_name             = "ari-zks-${random_id.app_suffix.hex}"
  # Clé Fernet : base64 url-safe AVEC padding (b64_url n'a pas de padding)
  encryption_key       = var.encryption_key != "" ? var.encryption_key : replace(replace(random_id.encryption_key[0].b64_std, "+", "-"), "/", "_")
  revolv_shared_secret = var.revolv_shared_secret != "" ? var.revolv_shared_secret : random_id.revolv_shared_secret[0].hex
  mount_path           = "/app/data"

  # Extraire le registry server depuis l'image (ex: registry.io/image:tag -> registry.io)
  registry_server = split("/", var.container_image)[0]
  # Nom de l'image sans le registry (ex: registry.io/image:tag -> image:tag)
  image_name_only = join("/", slice(split("/", var.container_image), 1, length(split("/", var.container_image))))
  # Image servie par le dépôt distant Artifact Registry (Cloud Run ne peut pas puller un registry privé externe)
  artifact_image = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.revolv.repository_id}/${local.image_name_only}"

  env_common = [
    { name = "ENV",                  value = "gcp" },
    { name = "ENCRYPTION_KEY",       value = local.encryption_key },
    { name = "REVOLV_SHARED_SECRET", value = local.revolv_shared_secret },
    { name = "DATABASE_URL",         value = "sqlite:////app/data/data.db" },
    { name = "PORT",                 value = "8000" },
  ]
}

# -----------------------------------------------------------------------------
# APIs GCP requises
# -----------------------------------------------------------------------------

resource "google_project_service" "apis" {
  for_each = toset([
    "run.googleapis.com",
    "storage.googleapis.com",
    "artifactregistry.googleapis.com",
    "secretmanager.googleapis.com",
  ])
  service            = each.value
  disable_on_destroy = false
}

# -----------------------------------------------------------------------------
# Artifact Registry — dépôt distant (proxy) vers le registry Revolv
# -----------------------------------------------------------------------------

data "google_project" "current" {}

resource "google_secret_manager_secret" "registry_password" {
  secret_id = "${local.app_name}-registry-password"

  replication {
    auto {}
  }

  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "registry_password" {
  secret      = google_secret_manager_secret.registry_password.id
  secret_data = var.registry_password
}

resource "google_artifact_registry_repository" "revolv" {
  repository_id = "${local.app_name}-revolv"
  location      = var.region
  format        = "DOCKER"
  mode          = "REMOTE_REPOSITORY"

  remote_repository_config {
    description = "Proxy vers ${local.registry_server}"

    docker_repository {
      custom_repository {
        uri = "https://${local.registry_server}"
      }
    }

    upstream_credentials {
      username_password_credentials {
        username                = var.registry_username
        password_secret_version = google_secret_manager_secret_version.registry_password.name
      }
    }
  }

  depends_on = [google_project_service.apis]
}

# Le service agent Artifact Registry doit lire le mot de passe du registry
resource "google_secret_manager_secret_iam_member" "artifact_registry_agent" {
  secret_id = google_secret_manager_secret.registry_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-artifactregistry.iam.gserviceaccount.com"

  # Le service agent est créé avec le premier dépôt
  depends_on = [google_artifact_registry_repository.revolv]
}

# -----------------------------------------------------------------------------
# GCS Bucket — volume partagé entre les deux services Cloud Run
# -----------------------------------------------------------------------------

resource "google_storage_bucket" "shared_data" {
  name          = "${local.app_name}-data"
  location      = var.region
  force_destroy = true

  depends_on = [google_project_service.apis]
}

# Accès lecture/écriture pour le compte de service Cloud Run par défaut
data "google_compute_default_service_account" "default" {}

resource "google_storage_bucket_iam_member" "cloud_run_storage" {
  bucket = google_storage_bucket.shared_data.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${data.google_compute_default_service_account.default.email}"
}

# -----------------------------------------------------------------------------
# Cloud Run — instance Private
# -----------------------------------------------------------------------------

resource "google_cloud_run_v2_service" "private" {
  name     = "private-${local.app_name}"
  location = var.region

  template {
    volumes {
      name = "shared-storage"
      gcs {
        bucket    = google_storage_bucket.shared_data.name
        read_only = false
      }
    }

    containers {
      image = local.artifact_image

      dynamic "env" {
        for_each = local.env_common
        content {
          name  = env.value.name
          value = env.value.value
        }
      }
      env {
        name  = "INSTANCE_ID"
        value = "private"
      }
      env {
        name  = "ALLOW_PRIVATE_ACCESS"
        value = "true"
      }

      volume_mounts {
        name       = "shared-storage"
        mount_path = local.mount_path
      }

      ports { container_port = 8000 }
    }
  }

  depends_on = [
    google_storage_bucket_iam_member.cloud_run_storage,
    google_secret_manager_secret_iam_member.artifact_registry_agent,
  ]
}

# -----------------------------------------------------------------------------
# Cloud Run — instance Public
# -----------------------------------------------------------------------------

resource "google_cloud_run_v2_service" "public" {
  name     = "public-${local.app_name}"
  location = var.region

  template {
    volumes {
      name = "shared-storage"
      gcs {
        bucket    = google_storage_bucket.shared_data.name
        read_only = false
      }
    }

    containers {
      image = local.artifact_image

      dynamic "env" {
        for_each = local.env_common
        content {
          name  = env.value.name
          value = env.value.value
        }
      }
      env {
        name  = "INSTANCE_ID"
        value = "public"
      }
      env {
        name  = "ALLOW_PRIVATE_ACCESS"
        value = "false"
      }

      volume_mounts {
        name       = "shared-storage"
        mount_path = local.mount_path
      }

      ports { container_port = 8000 }
    }
  }

  depends_on = [
    google_storage_bucket_iam_member.cloud_run_storage,
    google_secret_manager_secret_iam_member.artifact_registry_agent,
  ]
}

# Accès public non authentifié sur le service Public
resource "google_cloud_run_v2_service_iam_member" "public_invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.public.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
