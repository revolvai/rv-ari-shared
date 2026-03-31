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
  encryption_key       = var.encryption_key != "" ? var.encryption_key : random_id.encryption_key[0].b64_url
  revolv_shared_secret = var.revolv_shared_secret != "" ? var.revolv_shared_secret : random_id.revolv_shared_secret[0].hex
  mount_path           = "/app/data"

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
  ])
  service            = each.value
  disable_on_destroy = false
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
      image = var.container_image

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

  depends_on = [google_storage_bucket_iam_member.cloud_run_storage]
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
      image = var.container_image

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

  depends_on = [google_storage_bucket_iam_member.cloud_run_storage]
}

# Accès public non authentifié sur le service Public
resource "google_cloud_run_v2_service_iam_member" "public_invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.public.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
