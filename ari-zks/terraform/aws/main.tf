terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# -----------------------------------------------------------------------------
# Nom auto-généré (unicité garantie sur AWS)
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
  app_name = "ari-zks-${random_id.app_suffix.hex}"
  # Clé Fernet : base64 url-safe AVEC padding (b64_url n'a pas de padding)
  encryption_key       = var.encryption_key != "" ? var.encryption_key : replace(replace(random_id.encryption_key[0].b64_std, "+", "-"), "/", "_")
  revolv_shared_secret = var.revolv_shared_secret != "" ? var.revolv_shared_secret : random_id.revolv_shared_secret[0].hex
  az                   = "${var.region}a"

  # Hostnames HTTPS : domaine fourni, sinon sslip.io (DNS wildcard résolvant vers l'IP)
  host = var.domain != "" ? var.domain : "${replace(aws_lightsail_static_ip.main.ip_address, ".", "-")}.sslip.io"

  # Configuration écrite sur l'instance (un fichier par valeur, lisible par root uniquement)
  config = {
    container_image      = var.container_image
    registry_username    = var.registry_username
    registry_password    = var.registry_password
    encryption_key       = local.encryption_key
    revolv_shared_secret = local.revolv_shared_secret
  }
}

# -----------------------------------------------------------------------------
# IP statique (incluse dans le prix de l'instance tant qu'elle est attachée)
# -----------------------------------------------------------------------------

resource "aws_lightsail_static_ip" "main" {
  name = local.app_name
}

# -----------------------------------------------------------------------------
# Disque de données — SQLite + certificats, survit au remplacement de l'instance
# -----------------------------------------------------------------------------

resource "aws_lightsail_disk" "data" {
  name              = "${local.app_name}-data"
  size_in_gb        = var.data_disk_size
  availability_zone = local.az
}

# -----------------------------------------------------------------------------
# Clé SSH (optionnelle, sinon clé par défaut Lightsail de la région)
# -----------------------------------------------------------------------------

resource "aws_lightsail_key_pair" "main" {
  count      = var.ssh_public_key != "" ? 1 : 0
  name       = local.app_name
  public_key = var.ssh_public_key
}

# -----------------------------------------------------------------------------
# Instance Lightsail — Docker : Private + Public + Caddy (HTTPS)
# -----------------------------------------------------------------------------

resource "aws_lightsail_instance" "main" {
  name              = local.app_name
  availability_zone = local.az
  blueprint_id      = "amazon_linux_2023"
  bundle_id         = var.bundle_id
  ip_address_type   = "ipv4"
  key_pair_name     = var.ssh_public_key != "" ? aws_lightsail_key_pair.main[0].name : null

  # Toute modification recrée l'instance ; les données restent sur le disque Lightsail
  user_data = templatefile("${path.module}/templates/user_data.sh.tftpl", {
    config        = local.config
    deploy_script = file("${path.module}/templates/deploy.sh")
    caddyfile = templatefile("${path.module}/templates/Caddyfile.tftpl", {
      host                  = local.host
      private_allowed_cidrs = var.private_allowed_cidrs
    })
  })
}

resource "aws_lightsail_disk_attachment" "data" {
  disk_name     = aws_lightsail_disk.data.name
  instance_name = aws_lightsail_instance.main.name
  disk_path     = "/dev/xvdf"
}

resource "aws_lightsail_static_ip_attachment" "main" {
  static_ip_name = aws_lightsail_static_ip.main.name
  instance_name  = aws_lightsail_instance.main.name
}

# HTTP (challenge ACME + redirection) et HTTPS ouverts ; SSH limité à la console
# Lightsail (lightsail-connect) et aux IPs de ssh_allowed_cidrs
resource "aws_lightsail_instance_public_ports" "main" {
  instance_name = aws_lightsail_instance.main.name

  port_info {
    protocol  = "tcp"
    from_port = 80
    to_port   = 80
    cidrs     = ["0.0.0.0/0"]
  }

  port_info {
    protocol  = "tcp"
    from_port = 443
    to_port   = 443
    cidrs     = ["0.0.0.0/0"]
  }

  port_info {
    protocol  = "tcp"
    from_port = 22
    to_port   = 22
    # Liste toujours explicite : le comportement de Lightsail sans cidrs n'est pas documenté
    cidrs             = length(var.ssh_allowed_cidrs) > 0 ? var.ssh_allowed_cidrs : ["127.0.0.1/32"]
    cidr_list_aliases = ["lightsail-connect"]
  }
}
