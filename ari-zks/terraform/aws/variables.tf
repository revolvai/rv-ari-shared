variable "region" {
  description = "Région AWS (Lightsail)"
  type        = string
  default     = "eu-west-1"
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

variable "bundle_id" {
  description = "Plan Lightsail (nano_3_0 = 0.5 Go / $5, micro_3_0 = 1 Go / $7, small_3_0 = 2 Go / $12)"
  type        = string
  default     = "micro_3_0"
}

variable "data_disk_size" {
  description = "Taille du disque de données en Go (minimum 8)"
  type        = number
  default     = 8
}

variable "domain" {
  description = "Domaine des instances (public.<domain>, private.<domain>), avec un enregistrement DNS wildcard vers l'IP. Vide = <ip>.sslip.io."
  type        = string
  default     = ""
}

variable "private_allowed_cidrs" {
  description = "CIDRs autorisés à joindre l'instance Private. Vide = accessible uniquement via tunnel SSH."
  type        = list(string)
  default     = []
}

variable "ssh_public_key" {
  description = "Clé publique SSH pour l'utilisateur ec2-user. Vide = clé par défaut Lightsail de la région."
  type        = string
  default     = ""
}

variable "ssh_allowed_cidrs" {
  description = "CIDRs autorisés en SSH, en plus du SSH navigateur de la console Lightsail"
  type        = list(string)
  default     = []
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
