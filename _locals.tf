locals {
  prefix = var.name

  default_tags = {
    name      = var.name
    managedBy = "terraform"
  }

  tags = merge(local.default_tags, var.tags)

  rg_name = var.resource_group.create ? azurerm_resource_group.this["this"].name     : data.azurerm_resource_group.existing[0].name
  rg_loc  = var.resource_group.create ? azurerm_resource_group.this["this"].location : (try(var.resource_group.location, null) != null ? var.resource_group.location : data.azurerm_resource_group.existing[0].location)

  vm_type_prefix = local.is_linux ? "lnx" : "win"
  # VMSS name rules: lowercase letters, numbers, hyphen; <= 63 chars
  base_vmss_name_raw = "vmss-${local.vm_type_prefix}-${local.prefix}-${try(var.vmss.name_suffix, "001")}"
  base_vmss_name     = substr(replace(lower(local.base_vmss_name_raw), "/[^0-9a-z-]/", "-"), 0, 63)
  vmss_name          = coalesce(try(var.vmss.name, null), local.base_vmss_name)

  is_linux   = lower(var.vmss.os_type) == "linux"
  is_windows = lower(var.vmss.os_type) == "windows"

  # SSH public key
  ssh_public_key_raw  = try(var.vmss.ssh_public_key, null)
  ssh_public_key      = try(trimspace(tostring(local.ssh_public_key_raw)), "")
  has_ssh_key         = local.is_linux && length(local.ssh_public_key) > 0

  # Linux auth: if SSH key is provided disable password authentication
  linux_disable_password_auth = local.has_ssh_key
  linux_admin_password        = local.has_ssh_key ? null : try(var.vmss.admin_password, null)

  # custom_data (base64)
  custom_data = var.user_data != null ? base64encode(var.user_data) : null

  # Image selection
  use_source_image_id = try(var.image.source_image_id, null) != null
  image_ref           = try(var.image.source_image_reference, null)

  # Shared Image Gallery (optional)
  gallery_enabled = try(var.gallery.enabled, false)

  # SIG naming rules: only alphanumeric, '.' and '_' (no hyphen)
  sig_gallery_name_raw = coalesce(try(var.gallery.gallery_name, null), "sig_${local.prefix}")
  sig_gallery_name     = substr(replace(replace(local.sig_gallery_name_raw, "-", "_"), "/[^0-9A-Za-z._]/", "_"), 0, 80)

  sig_image_name_raw = coalesce(try(var.gallery.image_name, null), "img_${local.prefix}_${try(var.vmss.name_suffix, "001")}")
  sig_image_name     = substr(replace(replace(local.sig_image_name_raw, "-", "_"), "/[^0-9A-Za-z._]/", "_"), 0, 80)

  sig_should_create_gallery          = local.gallery_enabled && try(var.gallery.create_gallery, true)
  sig_should_create_image_definition = local.gallery_enabled && try(var.gallery.create_image_definition, true)

  # Autoscale
  autoscale_enabled = try(var.autoscale.enabled, false)

  autoscale_name = substr(
    replace(lower("as-${local.vmss_name}-${try(var.autoscale.name_suffix, "cpu")}"), "/[^0-9a-z-]/", "-"),
    0,
    80
  )

  # Windows computer_name_prefix: max 9 chars
  windows_cnp_default  = substr(replace(lower(local.prefix), "/[^0-9a-z]/", ""), 0, 9)
  computer_name_prefix = local.is_windows ? coalesce(try(var.vmss.computer_name_prefix, null), local.windows_cnp_default) : null

  # VMSS ID (used by autoscale target)
  vmss_id = local.is_linux ? azurerm_linux_virtual_machine_scale_set.this["this"].id : azurerm_windows_virtual_machine_scale_set.this["this"].id

  nic_name = "nic-vmss-${local.vm_type_prefix}-${local.prefix}-${try(var.vmss.name_suffix, "001")}"
  pip_name = "pip-vmss-${local.vm_type_prefix}-${local.prefix}-${try(var.vmss.name_suffix, "001")}"

  diag_enabled = try(var.diagnostics.enabled, false) && (try(var.diagnostics.log_analytics_workspace_id, null) != null || try(var.diagnostics.storage_account_id, null) != null || try(var.diagnostics.eventhub_authorization_rule_id, null) != null)
}