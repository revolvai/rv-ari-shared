output "app_name" {
  description = "Nom de l'application (utile si auto-généré)"
  value       = local.app_name
}

output "webapp_private_url" {
  description = "URL de la Web App Private"
  value       = "https://${azurerm_linux_web_app.private.default_hostname}"
}

output "webapp_public_url" {
  description = "URL de la Web App Public"
  value       = "https://${azurerm_linux_web_app.public.default_hostname}"
}

output "storage_account_name" {
  description = "Nom du Storage Account"
  value       = azurerm_storage_account.main.name
}

output "file_share_name" {
  description = "Nom du File Share partagé"
  value       = azurerm_storage_share.shared_data.name
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
    # Logs Web App Private:
    az webapp log tail --name ${azurerm_linux_web_app.private.name} --resource-group ${var.resource_group_name}

    # Logs Web App Public:
    az webapp log tail --name ${azurerm_linux_web_app.public.name} --resource-group ${var.resource_group_name}

    # Restart:
    az webapp restart --name ${azurerm_linux_web_app.private.name} --resource-group ${var.resource_group_name}
    az webapp restart --name ${azurerm_linux_web_app.public.name} --resource-group ${var.resource_group_name}

    # Afficher les secrets:
    terraform output -raw encryption_key
    terraform output -raw revolv_shared_secret
  EOT
}
