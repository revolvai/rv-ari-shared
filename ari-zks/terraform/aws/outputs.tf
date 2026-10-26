output "app_name" {
  description = "Nom de l'application (auto-généré)"
  value       = local.app_name
}

output "service_private_url" {
  description = "URL de l'instance Private (accessible depuis private_allowed_cidrs)"
  value       = "https://private.${local.host}"
}

output "service_public_url" {
  description = "URL de l'instance Public"
  value       = "https://public.${local.host}"
}

output "public_ip" {
  description = "IP statique (cible DNS si un domaine est utilisé)"
  value       = aws_lightsail_static_ip.main.ip_address
}

output "encryption_key" {
  description = "Clé de chiffrement (sensible)"
  value       = local.encryption_key
  sensitive   = true
}

output "revolv_shared_secret" {
  description = "Secret partagé Revolv (sensible)"
  value       = local.revolv_shared_secret
  sensitive   = true
}

output "useful_commands" {
  description = "Commandes utiles post-déploiement"
  value       = <<-EOT
    # Shell : SSH navigateur depuis la console Lightsail (instance ${aws_lightsail_instance.main.name}), ou :
    ssh ec2-user@${aws_lightsail_static_ip.main.ip_address}

    # Logs (sur l'instance):
    sudo docker logs -f private
    sudo docker logs -f public

    # Redéployer (re-pull de l'image, ou nouvelle image en argument):
    ssh ec2-user@${aws_lightsail_static_ip.main.ip_address} sudo /opt/ari-zks/deploy.sh
    ssh ec2-user@${aws_lightsail_static_ip.main.ip_address} sudo /opt/ari-zks/deploy.sh ${var.container_image}

    # Accès à l'instance Private via tunnel SSH (http://localhost:8001):
    ssh -N -L 8001:127.0.0.1:8001 ec2-user@${aws_lightsail_static_ip.main.ip_address}

    # Afficher les secrets:
    terraform output -raw encryption_key
    terraform output -raw revolv_shared_secret
  EOT
}
