resource "azurerm_resource_group" "this" {
  for_each = var.resource_group.create ? { "this" = var.resource_group } : {}
  name     = each.value.name
  location = each.value.location
  tags     = local.tags
}

resource "azurerm_shared_image_gallery" "this" {
  for_each            = local.sig_should_create_gallery ? { "this" = true } : {}
  name                = local.sig_gallery_name
  resource_group_name = local.rg_name
  location            = local.rg_loc
  description         = try(var.gallery.description, "Managed by Terraform")
  tags                = local.tags
}

resource "azurerm_shared_image" "this" {
  for_each            = local.sig_should_create_image_definition ? { "this" = true } : {}
  name                = local.sig_image_name
  gallery_name        = local.sig_should_create_gallery ? azurerm_shared_image_gallery.this["this"].name : local.sig_gallery_name
  resource_group_name = local.rg_name
  location            = local.rg_loc
  os_type             = local.is_linux ? "Linux" : "Windows"

  identifier {
    publisher = "managed"
    offer     = "generic"
    sku       = local.is_linux ? "linux" : "windows"
  }

  tags = local.tags
}

resource "azurerm_linux_virtual_machine_scale_set" "this" {
  for_each            = local.is_linux ? { "this" = var.vmss } : {}
  name                = local.vmss_name
  resource_group_name = local.rg_name
  location            = local.rg_loc

  sku       = each.value.sku
  instances = try(each.value.instances, 1)

  admin_username = each.value.admin_username
  custom_data    = local.custom_data

  disable_password_authentication = local.linux_disable_password_auth
  admin_password                  = var.admin_password

  dynamic "admin_ssh_key" {
    for_each = local.has_ssh_key ? [1] : []
    content {
      username   = each.value.admin_username
      public_key = local.ssh_public_key
    }
  }

  upgrade_mode = try(each.value.upgrade_mode, "Manual")

  dynamic "identity" {
    for_each = try(each.value.identity, null) != null ? [each.value.identity] : []
    content {
      type         = identity.value.type
      identity_ids = try(identity.value.identity_ids, null)
    }
  }

  secure_boot_enabled = try(each.value.secure_boot_enabled, false)
  vtpm_enabled        = try(each.value.vtpm_enabled, false)

  zones = try(each.value.zones, null)

  os_disk {
    storage_account_type = try(each.value.os_disk.storage_account_type, "Standard_LRS")
    caching              = try(each.value.os_disk.caching, "ReadWrite")
  }

  network_interface {
    name    = local.nic_name
    primary = true

    enable_accelerated_networking = try(each.value.enable_accelerated_networking, false)

    ip_configuration {
      name      = "ipconfig1"
      primary   = true
      subnet_id = var.subnet_id
    }
  }

  # Image selection (SIG version OR marketplace)
  dynamic "source_image_reference" {
    for_each = local.use_source_image_id ? [] : (local.image_ref != null ? [local.image_ref] : [])
    content {
      publisher = source_image_reference.value.publisher
      offer     = source_image_reference.value.offer
      sku       = source_image_reference.value.sku
      version   = source_image_reference.value.version
    }
  }

  source_image_id = local.use_source_image_id ? var.image.source_image_id : null

  lifecycle {
    ignore_changes = [
      custom_data,
      source_image_id,
      source_image_reference,
    ]
  }

  tags = local.tags
}

resource "azurerm_windows_virtual_machine_scale_set" "this" {
  for_each            = local.is_windows ? { "this" = var.vmss } : {}
  name                = local.vmss_name
  resource_group_name = local.rg_name
  location            = local.rg_loc

  sku       = each.value.sku
  instances = try(each.value.instances, 1)

  admin_username = each.value.admin_username
  admin_password = var.admin_password

  custom_data          = local.custom_data
  computer_name_prefix = local.computer_name_prefix

  upgrade_mode = try(each.value.upgrade_mode, "Manual")

  dynamic "identity" {
    for_each = try(each.value.identity, null) != null ? [each.value.identity] : []
    content {
      type         = identity.value.type
      identity_ids = try(identity.value.identity_ids, null)
    }
  }

  secure_boot_enabled = try(each.value.secure_boot_enabled, false)
  vtpm_enabled        = try(each.value.vtpm_enabled, false)

  zones = try(each.value.zones, null)

  os_disk {
    storage_account_type = try(each.value.os_disk.storage_account_type, "Standard_LRS")
    caching              = try(each.value.os_disk.caching, "ReadWrite")
  }

  network_interface {
    name    = local.nic_name
    primary = true

    enable_accelerated_networking = try(each.value.enable_accelerated_networking, false)

    ip_configuration {
      name      = "ipconfig1"
      primary   = true
      subnet_id = var.subnet_id
    }
  }

  dynamic "source_image_reference" {
    for_each = local.use_source_image_id ? [] : (local.image_ref != null ? [local.image_ref] : [])
    content {
      publisher = source_image_reference.value.publisher
      offer     = source_image_reference.value.offer
      sku       = source_image_reference.value.sku
      version   = source_image_reference.value.version
    }
  }

  source_image_id = local.use_source_image_id ? var.image.source_image_id : null

  lifecycle {
    ignore_changes = [
      custom_data,
      source_image_id,
      source_image_reference,
    ]
  }

  tags = local.tags
}

resource "azurerm_monitor_autoscale_setting" "this" {
  for_each = try(var.autoscale.enabled, false) ? { "this" = true } : {}

  name                = "as-${local.vmss_name}-${try(var.autoscale.name_suffix, "cpu")}"
  resource_group_name = local.rg_name
  location            = local.rg_loc

  target_resource_id = local.vmss_id

  profile {
    name = "cpu"

    capacity {
      minimum = tostring(try(var.autoscale.capacity.min, 1))
      default = tostring(try(var.autoscale.capacity.default, 1))
      maximum = tostring(try(var.autoscale.capacity.max, 2))
    }

    # Scale Out (Increase)
    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = local.vmss_id

        time_grain       = "PT1M"
        statistic        = "Average"
        time_window      = "PT5M"
        time_aggregation = "Average"

        operator  = "GreaterThan"
        threshold = try(var.autoscale.cpu_rules.scale_out.threshold, 70)
      }

      scale_action {
        direction = try(var.autoscale.cpu_rules.scale_out.direction, "Increase")
        type      = "ChangeCount"
        value     = tostring(try(var.autoscale.cpu_rules.scale_out.change_count, 1))
        cooldown  = try(var.autoscale.cpu_rules.scale_out.cooldown, "PT5M")
      }
    }

    # Scale In (Decrease)
    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = local.vmss_id

        time_grain       = "PT1M"
        statistic        = "Average"
        time_window      = "PT10M"
        time_aggregation = "Average"

        operator  = "LessThan"
        threshold = try(var.autoscale.cpu_rules.scale_in.threshold, 20)
      }

      scale_action {
        direction = try(var.autoscale.cpu_rules.scale_in.direction, "Decrease")
        type      = "ChangeCount"
        value     = tostring(try(var.autoscale.cpu_rules.scale_in.change_count, 1))
        cooldown  = try(var.autoscale.cpu_rules.scale_in.cooldown, "PT10M")
      }
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "vmss_linux" {
  for_each = (local.diag_enabled && local.is_linux) ? { "this" = true } : {}

  name                           = "diag-${local.vmss_name}"
  target_resource_id             = azurerm_linux_virtual_machine_scale_set.this["this"].id
  log_analytics_workspace_id     = try(var.diagnostics.log_analytics_workspace_id, null)
  storage_account_id             = try(var.diagnostics.storage_account_id, null)
  eventhub_authorization_rule_id = try(var.diagnostics.eventhub_authorization_rule_id, null)

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "vmss_windows" {
  for_each = (local.diag_enabled && local.is_windows) ? { "this" = true } : {}

  name                           = "diag-${local.vmss_name}"
  target_resource_id             = azurerm_windows_virtual_machine_scale_set.this["this"].id
  log_analytics_workspace_id     = try(var.diagnostics.log_analytics_workspace_id, null)
  storage_account_id             = try(var.diagnostics.storage_account_id, null)
  eventhub_authorization_rule_id = try(var.diagnostics.eventhub_authorization_rule_id, null)

  enabled_metric {
    category = "AllMetrics"
  }
}
