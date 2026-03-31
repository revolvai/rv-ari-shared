terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# -----------------------------------------------------------------------------
# Nom de l'application toujours auto-généré (unicité garantie sur Azure)
# -----------------------------------------------------------------------------

resource "random_id" "app_suffix" {
  byte_length = 4 # 8 caractères hex
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

  # Noms des ressources dérivés du app_name
  webapp_private_name    = "private-${local.app_name}"
  webapp_public_name     = "public-${local.app_name}"
  app_service_plan_name  = "${local.app_name}-plan"
  # Storage: lowercase alphanum, max 24 chars
  storage_account_name   = substr(replace(lower("${local.app_name}storage"), "-", ""), 0, 24)
  file_share_name        = "shared-data"
  mount_path             = "/app/data"

  # Extraire le registry server depuis l'image (ex: registry.io/image:tag -> registry.io)
  registry_server = split("/", var.container_image)[0]
  # Nom de l'image sans le registry (ex: registry.io/image:tag -> image:tag)
  image_name_only = join("/", slice(split("/", var.container_image), 1, length(split("/", var.container_image))))

  app_settings_common = {
    WEBSITES_PORT        = "8000"
    ENV                  = "azure"
    ENCRYPTION_KEY       = local.encryption_key
    REVOLV_SHARED_SECRET = local.revolv_shared_secret
    DATABASE_URL         = "sqlite:////app/data/data.db"
  }
}

# -----------------------------------------------------------------------------
# Resource Group
# -----------------------------------------------------------------------------

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
}

# -----------------------------------------------------------------------------
# Storage Account + File Share
# -----------------------------------------------------------------------------

resource "azurerm_storage_account" "main" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
}

resource "azurerm_storage_share" "shared_data" {
  name                 = local.file_share_name
  storage_account_name = azurerm_storage_account.main.name
  quota                = 5
}

# -----------------------------------------------------------------------------
# App Service Plan (Linux containers)
# -----------------------------------------------------------------------------

resource "azurerm_service_plan" "main" {
  name                = local.app_service_plan_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = "B1"
}

# -----------------------------------------------------------------------------
# Web App Private
# -----------------------------------------------------------------------------

resource "azurerm_linux_web_app" "private" {
  name                = local.webapp_private_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.main.id

  site_config {
    container_registry_use_managed_identity = false

    application_stack {
      docker_image_name        = local.image_name_only
      docker_registry_url      = "https://${local.registry_server}"
      docker_registry_username = var.registry_username
      docker_registry_password = var.registry_password
    }
  }

  app_settings = merge(local.app_settings_common, {
    INSTANCE_ID          = "private"
    ALLOW_PRIVATE_ACCESS = "true"
  })

  storage_account {
    name         = "shared-storage"
    type         = "AzureFiles"
    account_name = azurerm_storage_account.main.name
    share_name   = azurerm_storage_share.shared_data.name
    access_key   = azurerm_storage_account.main.primary_access_key
    mount_path   = local.mount_path
  }
}

# -----------------------------------------------------------------------------
# Web App Public
# -----------------------------------------------------------------------------

resource "azurerm_linux_web_app" "public" {
  name                = local.webapp_public_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.main.id

  site_config {
    container_registry_use_managed_identity = false

    application_stack {
      docker_image_name        = local.image_name_only
      docker_registry_url      = "https://${local.registry_server}"
      docker_registry_username = var.registry_username
      docker_registry_password = var.registry_password
    }
  }

  app_settings = merge(local.app_settings_common, {
    INSTANCE_ID          = "public"
    ALLOW_PRIVATE_ACCESS = "false"
  })

  storage_account {
    name         = "shared-storage"
    type         = "AzureFiles"
    account_name = azurerm_storage_account.main.name
    share_name   = azurerm_storage_share.shared_data.name
    access_key   = azurerm_storage_account.main.primary_access_key
    mount_path   = local.mount_path
  }
}
