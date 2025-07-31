data "azurerm_client_config" "current" {}

data "azurerm_key_vault" "main" {
  provider            = azurerm.kv
  name                = var.vault_name
  resource_group_name = var.key_vault_resource_group
}

data "azurerm_key_vault_secret" "certificate" {
  provider     = azurerm.kv
  name         = var.ssl_certificate_name != null ? var.ssl_certificate_name : "null"
  key_vault_id = data.azurerm_key_vault.main.id
}