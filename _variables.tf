variable "name" {
  description = "Resource name prefix used for all resources in this module."
  type        = string
}

variable "resource_group" {
  description = "Create or use an existing resource group."
  type = object({
    create   = bool
    name     = string
    location = optional(string)
  })
}

variable "tags" {
  description = "Extra tags merged with default tags."
  type        = map(string)
  default     = {}
}

variable "diagnostics" {
  description = "Optional Azure Monitor diagnostic settings."
  type = object({
    enabled                        = optional(bool, false)
    log_analytics_workspace_id     = optional(string)
    storage_account_id             = optional(string)
    eventhub_authorization_rule_id = optional(string)
  })
  default = {}
}

variable "subnet_id" {
  description = "Subnet ID where the VMSS NICs will be attached."
  type        = string
}

variable "vmss" {
  description = "VM Scale Set configuration."
  type = object({
    os_type     = string # linux | windows
    name        = optional(string)

    sku       = string
    instances = optional(number, 1)

    admin_username       = string
    computer_name_prefix = optional(string)

    ssh_public_key = optional(string) # Required for Linux (when not using password auth)

    upgrade_mode = optional(string, "Manual") # Manual | Automatic | Rolling

    # Identity
    identity = optional(object({
      type         = string                 # SystemAssigned | UserAssigned | SystemAssigned, UserAssigned
      identity_ids = optional(list(string)) # for UserAssigned
    }), {
      type = "SystemAssigned"
    })

    # Networking
    enable_accelerated_networking      = optional(bool, false)
    load_balancer_backend_address_pool_ids = optional(list(string))
    application_gateway_backend_address_pool_ids = optional(list(string))

    # Security
    security_type       = optional(string, "Standard") # Standard | TrustedLaunch | ConfidentialVM
    secure_boot_enabled = optional(bool, false)
    vtpm_enabled        = optional(bool, false)
  })
}

variable "image" {
  description = "Image configuration. Use either source_image_id (SIG version ID) OR source_image_reference (Marketplace)."
  type = object({
    source_image_id = optional(string)

    source_image_reference = optional(object({
      publisher = string
      offer     = string
      sku       = string
      version   = string
    }))
  })
  default = null
}

variable "user_data" {
  description = "Cloud-init (Linux) or custom data (Windows). Stored as base64 custom_data in VMSS."
  type        = string
  default     = null
}

variable "autoscale" {
  description = "Autoscale settings for the VMSS."
  type = object({
    enabled     = bool

    capacity = optional(object({
      min     = number
      default = number
      max     = number
    }), {
      min     = 1
      default = 1
      max     = 2
    })

    cpu_rules = optional(object({
      scale_out = object({
        threshold    = number # e.g. 70
        direction    = string # Increase
        change_count = number # e.g. 1
        cooldown     = optional(string, "PT5M")
      })
      scale_in = object({
        threshold    = number # e.g. 20
        direction    = string # Decrease
        change_count = number # e.g. 1
        cooldown     = optional(string, "PT10M")
      })
    }))
  })
  default = {
    enabled = false
  }
}

variable "admin_password" {
  description = "VMSS admin password."
  type        = string
  default     = null
  sensitive   = true
}

variable "gallery" {
  description = "Shared Image Gallery + Image Definition (generic placeholders for pipelines)."
  type = object({
    enabled = bool

    create_gallery          = optional(bool, true)
    create_image_definition = optional(bool, true)

    gallery_name = optional(string)
    image_name   = optional(string)

    description = optional(string, "Managed by Terraform")
  })
  default = {
    enabled = false
  }
}