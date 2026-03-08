output "vmss" {
  description = "The created VMSS resource (linux/windows)."
  value = local.is_linux ? azurerm_linux_virtual_machine_scale_set.this["this"] : azurerm_windows_virtual_machine_scale_set.this["this"]
}

output "vmss_id" {
  value = local.is_linux ? azurerm_linux_virtual_machine_scale_set.this["this"].id : azurerm_windows_virtual_machine_scale_set.this["this"].id
}

output "vmss_name" {
  value = local.vmss_name
}

output "gallery" {
  description = "Shared Image Gallery artifacts (if enabled)."
  value = local.gallery_enabled ? {
    gallery_name = local.sig_gallery_name
    image_name   = local.sig_image_name
    gallery_id   = try(azurerm_shared_image_gallery.this["this"].id, null)
    image_id     = try(azurerm_shared_image.this["this"].id, null)
  } : null
}

output "autoscale" {
  description = "Autoscale setting (if enabled)."
  value = local.autoscale_enabled ? {
    id   = azurerm_monitor_autoscale_setting.this["this"].id
    name = azurerm_monitor_autoscale_setting.this["this"].name
  } : null
}