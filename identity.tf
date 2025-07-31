resource "azurerm_user_assigned_identity" "this" {
  count               = var.ssl_enable ? 1 : 0
  provider            = azurerm.hub
  name                = var.uami_name
  resource_group_name = var.vnet_rg
  location            = var.location
}

resource "azurerm_role_assignment" "identity" {
  count        = var.ssl_enable ? 1 : 0
  principal_id = azurerm_user_assigned_identity.this[0].principal_id
  scope        = data.azurerm_key_vault.main.id

  role_definition_name = "Key Vault Secrets User"
}