resource "azurerm_web_application_firewall_policy" "waf_policy" {
  count               = var.waf_managed_rules != null || var.waf_custom_rules != null ? 1 : 0
  name                = "${var.waf_policy_name}-${var.env}"
  resource_group_name = var.vnet_rg
  location            = var.location

  policy_settings {
    enabled            = var.enable_waf
    mode               = var.waf_mode
    request_body_check = true
  }

  dynamic "managed_rules" {
    for_each = var.waf_managed_rules != null ? var.waf_managed_rules : []

    content {
      managed_rule_set {
        type    = managed_rules.value.type
        version = managed_rules.value.version
        dynamic "rule_group_override" {
          for_each = managed_rules.value.rule_group_override

          content {
            rule_group_name = rule_group_override.value.rule_group_name
            dynamic "rule" {
              for_each = rule_group_override.value.rule

              content {
                id      = rule.value.id
                enabled = rule.value.enabled
                action  = rule.value.action
              }
            }
          }
        }
      }
    }
  }
  dynamic "custom_rules" {
    for_each = var.waf_custom_rules != null ? var.waf_custom_rules : []

    content {
      name      = custom_rules.value.name
      priority  = custom_rules.value.priority
      rule_type = custom_rules.value.rule_type

      dynamic "match_conditions" {
        for_each = custom_rules.value.match_conditions

        content {
          dynamic "match_variables" {
            for_each = match_conditions.value.match_variables

            content {
              variable_name = match_variables.value.variable_name
              selector      = lookup(match_variables.value, "selector", null)
            }
          }

          operator           = match_conditions.value.operator
          negation_condition = match_conditions.value.negation_condition
          match_values       = match_conditions.value.match_values
        }
      }

      action = custom_rules.value.action
    }
  }
}