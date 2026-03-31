output "app_name" {
  description = "Nom de l'application (auto-généré)"
  value       = local.app_name
}

output "service_private_url" {
  description = "URL du service Cloud Run Private"
  value       = google_cloud_run_v2_service.private.uri
}

output "service_public_url" {
  description = "URL du service Cloud Run Public"
  value       = google_cloud_run_v2_service.public.uri
}

output "filestore_ip" {
  description = "IP du Filestore NFS"
  value       = google_filestore_instance.main.netwozks[0].ip_addresses[0]
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
  value = <<-EOT
    # Logs Cloud Run Private:
    gcloud run services logs read ${google_cloud_run_v2_service.private.name} --region ${var.region}

    # Logs Cloud Run Public:
    gcloud run services logs read ${google_cloud_run_v2_service.public.name} --region ${var.region}

    # Redéployer (nouvelle révision):
    gcloud run services update ${google_cloud_run_v2_service.private.name} --region ${var.region}
    gcloud run services update ${google_cloud_run_v2_service.public.name} --region ${var.region}

    # Afficher les secrets:
    terraform output -raw encryption_key
    terraform output -raw revolv_shared_secret
  EOT
}
