resource "azurerm_application_gateway" "this" {
  name                = var.app_gateway_name
  resource_group_name = var.vnet_rg
  location            = var.location
  zones               = var.enable_multiple_availability_zones == true ? ["1", "2", "3"] : []
  firewall_policy_id  = var.enable_waf ? azurerm_web_application_firewall_policy.waf_policy[0].id : null

  count = length(var.frontends) != 0 ? 1 : 0

  sku {
    name = var.enable_waf == true ? "WAF_v2" : "Standard_v2"
    tier = var.enable_waf == true ? "WAF_v2" : "Standard_v2"
  }

  autoscale_configuration {
    min_capacity = var.min_capacity
    max_capacity = var.max_capacity
  }

  gateway_ip_configuration {
    name      = "gateway"
    subnet_id = var.subnet_id
  }

  frontend_port {
    name = "http"
    port = 80
  }

  dynamic "frontend_port" {
    for_each = var.ssl_enable ? [1] : []
    content {
      name = "https"
      port = 443
    }
  }

  frontend_ip_configuration {
    name                 = "appGwPublicFrontendIp"
    public_ip_address_id = azurerm_public_ip.app_gw[0].id
  }

  frontend_ip_configuration {
    name                          = "appGwPrivateFrontendIp"
    subnet_id                     = var.subnet_id
    private_ip_address            = var.private_ip_address
    private_ip_address_allocation = "Static"
  }

  dynamic "backend_address_pool" {
    for_each = [for app in var.frontends : {
      name  = app.name
      fqdns = lookup(app, "backend_fqdn", [])
    }]

    content {
      name         = backend_address_pool.value.name
      ip_addresses = var.destinations != [] ? var.destinations : []
      fqdns        = backend_address_pool.value.fqdns != [] ? backend_address_pool.value.fqdns : []
    }
  }

  dynamic "probe" {
    for_each = [for app in var.frontends : {
      name = app.name
      host = lookup(app, "host_name", lookup(app, "custom_domain", ""))
      path = lookup(app, "health_path", "/health/liveness")
    }]

    content {
      interval            = 20
      name                = probe.value.name
      host                = probe.value.host
      path                = probe.value.path
      protocol            = var.ssl_enable ? "Https" : "Http"
      timeout             = 15
      unhealthy_threshold = 3
    }
  }

  dynamic "backend_http_settings" {
    for_each = [for app in var.frontends : {
      name                  = app.name
      cookie_based_affinity = try(title(app.appgw_cookie_based_affinity), "Disabled")
      host_name             = try(app.host_name, null)
    }]

    content {
      name                  = backend_http_settings.value.name
      probe_name            = backend_http_settings.value.name
      cookie_based_affinity = backend_http_settings.value.cookie_based_affinity
      port                  = var.ssl_enable ? 443 : 80
      protocol              = var.ssl_enable ? "Https" : "Http"
      request_timeout       = 30
      host_name             = var.ssl_enable ? backend_http_settings.value.host_name : null
    }
  }

  dynamic "identity" {
    for_each = var.ssl_enable ? [1] : []
    content {
      identity_ids = [azurerm_user_assigned_identity.this[0].id]
      type         = "UserAssigned"
    }
  }

  dynamic "ssl_certificate" {
    for_each = var.ssl_enable ? [1] : []
    content {
      name                = var.ssl_certificate_name
      key_vault_secret_id = data.azurerm_key_vault_secret.certificate.versionless_id
    }
  }

  dynamic "http_listener" {
    for_each = !var.ssl_enable ? [for app in var.frontends : {
      name          = app.name
      custom_domain = app.custom_domain
    }] : []

    content {
      name                           = http_listener.value.name
      frontend_ip_configuration_name = "appGwPrivateFrontendIp"
      frontend_port_name             = "http"
      protocol                       = "Http"
      host_name                      = http_listener.value.custom_domain
    }
  }

  dynamic "http_listener" {
    for_each = var.ssl_enable ? [for app in var.frontends : {
      name          = app.name
      custom_domain = app.custom_domain
    }] : []

    content {
      name                           = http_listener.value.name
      frontend_ip_configuration_name = "appGwPublicFrontendIp"
      frontend_port_name             = "https"
      protocol                       = "Https"
      host_name                      = http_listener.value.custom_domain
      ssl_certificate_name           = var.ssl_certificate_name
    }
  }

  dynamic "request_routing_rule" {
    for_each = [for i, app in var.frontends : {
      name     = app.name
      priority = ((i + 1) * 10)
    }]

    content {
      name                       = request_routing_rule.value.name
      rule_type                  = "Basic"
      priority                   = request_routing_rule.value.priority
      http_listener_name         = request_routing_rule.value.name
      backend_address_pool_name  = request_routing_rule.value.name
      backend_http_settings_name = request_routing_rule.value.name
      rewrite_rule_set_name      = local.x_fwded_proto_ruleset
    }
  }

  rewrite_rule_set {
    name = local.x_fwded_proto_ruleset

    rewrite_rule {
      name          = local.x_fwded_proto_ruleset
      rule_sequence = 100

      request_header_configuration {
        header_name  = "X-Forwarded-Proto"
        header_value = "https"
      }

      request_header_configuration {
        header_name  = "X-Forwarded-Port"
        header_value = "443"
      }

      request_header_configuration {
        header_name  = "X-Forwarded-For"
        header_value = "{var_add_x_forwarded_for_proxy}"
      }
    }
  }
}

resource "azurerm_public_ip" "app_gw" {
  count = length(var.frontends) != 0 ? 1 : 0

  name                = var.pip_name
  location            = var.location
  resource_group_name = var.vnet_rg
  sku                 = "Standard"
  allocation_method   = "Static"
  zones               = var.enable_multiple_availability_zones == true ? ["1", "2", "3"] : []
}