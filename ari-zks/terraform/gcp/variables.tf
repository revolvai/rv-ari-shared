variable "project_id" {
  description = "ID du projet GCP"
  type        = string
}

variable "region" {
  description = "Région GCP"
  type        = string
  default     = "europe-west1"
}

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
