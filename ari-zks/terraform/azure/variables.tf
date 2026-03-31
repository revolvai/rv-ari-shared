
variable "container_image" {
  description = "Image Docker complète (ex: revolvregistry.azurecr.io/ari-zks:latest)"
  type        = string
}

variable "registry_username" {
  description = "Nom d'utilisateur du container registry"
  type        = string
  sensitive   = true
}

variable "registry_password" {
  description = "Mot de passe du container registry"
  type        = string
  sensitive   = true
}

variable "resource_group_name" {
  description = "Nom du Resource Group Azure"
  type        = string
  default     = "ari-zks-rg"
}

variable "location" {
  description = "Région Azure"
  type        = string
  default     = "westeurope"
}

variable "encryption_key" {
  description = "Clé de chiffrement de l'application (générée automatiquement si non fournie)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "revolv_shared_secret" {
  description = "Secret partagé Revolv (généré automatiquement si non fourni)"
  type        = string
  sensitive   = true
  default     = ""
}
