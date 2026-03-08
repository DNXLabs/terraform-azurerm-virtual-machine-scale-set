# terraform-azurerm-virtual-machine-scale-set

Terraform module for creating and managing Azure Virtual Machine Scale Sets (Linux and Windows) with support for autoscaling, Shared Image Gallery, custom data, managed identities, and optional diagnostic settings.

This module supports both Linux and Windows VMSS through a unified interface, with SSH key or password authentication for Linux and password authentication for Windows.

## Features

- **Dual OS Support**: Create Linux or Windows VMSS from a single module
- **Autoscaling**: CPU-based autoscale rules with configurable scale out/in policies
- **Shared Image Gallery**: Optional gallery and image definition creation for CI/CD pipelines
- **Custom Data / Cloud-Init**: Pass cloud-init scripts (Linux) or custom data (Windows)
- **Marketplace & Custom Images**: Support for both marketplace image references and custom image IDs
- **Managed Identity**: SystemAssigned, UserAssigned, or combined identity support
- **Security Types**: Standard, TrustedLaunch, or ConfidentialVM configurations
- **Accelerated Networking**: Optional NIC-level accelerated networking
- **Upgrade Modes**: Manual, Automatic, or Rolling upgrade modes
- **Diagnostic Settings**: Optional Azure Monitor integration
- **Resource Group Flexibility**: Create new or use existing resource groups
- **Tagging Strategy**: Built-in default tagging with custom tag support

## Usage

### Example 1 — Non-Prod (Linux VMSS with SSH Key)

A simple Linux VMSS for development with SSH key authentication and no autoscale.

```hcl
module "vmss" {
  source = "./modules/vmss"

  name = "mycompany-dev-aue-app"

  resource_group = {
    create   = false
    name     = "rg-mycompany-dev-aue-app-001"
    location = "australiaeast"
  }

  tags = {
    project     = "my-app"
    environment = "development"
  }

  subnet_id = "/subscriptions/xxxx/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-dev/subnets/snet-app"

  vmss = {
    os_type        = "linux"
    sku            = "Standard_B2s"
    instances      = 2
    admin_username = "azureadmin"
    ssh_public_key = file("~/.ssh/id_rsa.pub")
    upgrade_mode   = "Manual"
  }

  image = {
    source_image_reference = {
      publisher = "Canonical"
      offer     = "ubuntu-24_04-lts"
      sku       = "server"
      version   = "latest"
    }
  }

  autoscale = {
    enabled = false
  }
}
```

### Example 2 — Production (Windows VMSS with Autoscale and Gallery)

A production Windows VMSS with autoscaling, shared image gallery, and diagnostics.

```hcl
module "vmss" {
  source = "./modules/vmss"

  name = "contoso-prod-aue-web"

  resource_group = {
    create   = true
    name     = "rg-contoso-prod-aue-web-001"
    location = "australiaeast"
  }

  tags = {
    project     = "web-platform"
    environment = "production"
    compliance  = "soc2"
  }

  subnet_id = "/subscriptions/xxxx/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-prod/subnets/snet-web"

  vmss = {
    os_type        = "windows"
    sku            = "Standard_D4s_v5"
    instances      = 3
    admin_username = "winadmin"
    upgrade_mode   = "Rolling"

    identity = {
      type = "SystemAssigned"
    }

    enable_accelerated_networking = true
    secure_boot_enabled           = false
    vtpm_enabled                  = false
  }

  admin_password = module.vmss_password.value

  image = {
    source_image_reference = {
      publisher = "MicrosoftWindowsServer"
      offer     = "WindowsServer"
      sku       = "2022-datacenter-g2"
      version   = "latest"
    }
  }

  autoscale = {
    enabled = true

    capacity = {
      min     = 2
      default = 3
      max     = 10
    }

    cpu_rules = {
      scale_out = {
        threshold    = 70
        direction    = "Increase"
        change_count = 1
        cooldown     = "PT5M"
      }
      scale_in = {
        threshold    = 20
        direction    = "Decrease"
        change_count = 1
        cooldown     = "PT10M"
      }
    }
  }

  gallery = {
    enabled                 = true
    create_gallery          = true
    create_image_definition = true
  }

  diagnostics = {
    enabled                    = true
    log_analytics_workspace_id = "/subscriptions/xxxx/resourceGroups/rg-monitor/providers/Microsoft.OperationalInsights/workspaces/law-prod"
  }
}
```

### Using YAML Variables

Create a `vars/identity.yaml` file:

```yaml
azure:
  subscription_id: "afb35bd4-145f-4a15-889e-5da052d030ce"
  location: australiaeast

network_lookup:
  resource_group_name: "rg-managed-services-lab-aue-stg-001"
  vnet_name: "vnet-managed-services-lab-aue-stg-001"

identity:
  vmss:
    web-servers:
      naming:
        org: managed-services
        env: lab
        region: aue
        workload: stg

      resource_group:
        create: false
        name: rg-managed-services-lab-aue-stg-001
        location: australiaeast

      subnet_name: snet-stg-app

      vmss:
        os_type: linux
        sku: Standard_B2s
        instances: 2
        admin_username: azureadmin
        upgrade_mode: Manual
        identity:
          type: SystemAssigned

      image:
        source_image_reference:
          publisher: Canonical
          offer: ubuntu-24_04-lts
          sku: server
          version: latest

      autoscale:
        enabled: true
        capacity:
          min: 1
          default: 2
          max: 4
        cpu_rules:
          scale_out:
            threshold: 75
            direction: Increase
            change_count: 1
            cooldown: PT5M
          scale_in:
            threshold: 25
            direction: Decrease
            change_count: 1
            cooldown: PT10M

      password:
        name: vmss-web-password
        type: password
        length: 32

      gallery:
        enabled: false
```

Then use in your Terraform:

```hcl
locals {
  workspace = yamldecode(file("vars/${terraform.workspace}.yaml"))
}

data "azurerm_subnet" "vmss" {
  for_each = try(local.workspace.identity.vmss, {})

  name                 = each.value.subnet_name
  virtual_network_name = local.workspace.network_lookup.vnet_name
  resource_group_name  = local.workspace.network_lookup.resource_group_name
}

module "vmss_passwords" {
  for_each = { for k, v in try(local.workspace.identity.vmss, {}) : k => v if try(v.password, null) != null }

  source = "./modules/password"

  name                    = each.value.password.name
  key_vault_name          = module.keyvault["main"].key_vault.name
  key_vault_resource_group = module.keyvault["main"].resource_group_name

  type   = try(each.value.password.type, "password")
  length = try(each.value.password.length, 32)
}

module "vmss" {
  for_each = try(local.workspace.identity.vmss, {})

  source = "./modules/vmss"

  name           = "${each.value.naming.org}-${each.value.naming.env}-${each.value.naming.region}-${each.value.naming.workload}"
  resource_group = each.value.resource_group
  tags           = try(each.value.tags, {})

  subnet_id = data.azurerm_subnet.vmss[each.key].id

  vmss           = each.value.vmss
  image          = try(each.value.image, null)
  admin_password = try(module.vmss_passwords[each.key].value, null)
  user_data      = try(each.value.user_data, null)
  autoscale      = try(each.value.autoscale, { enabled = false })
  gallery        = try(each.value.gallery, { enabled = false })
  diagnostics    = try(each.value.diagnostics, {})
}
```

## Autoscale Configuration

### CPU-Based Auto Scaling

```hcl
autoscale = {
  enabled = true

  capacity = {
    min     = 2      # Minimum instances
    default = 3      # Default instance count
    max     = 10     # Maximum instances
  }

  cpu_rules = {
    scale_out = {
      threshold    = 70    # Scale out when CPU > 70%
      direction    = "Increase"
      change_count = 1     # Add 1 instance
      cooldown     = "PT5M"
    }
    scale_in = {
      threshold    = 20    # Scale in when CPU < 20%
      direction    = "Decrease"
      change_count = 1     # Remove 1 instance
      cooldown     = "PT10M"
    }
  }
}
```

## Shared Image Gallery

The module can optionally create a Shared Image Gallery and Image Definition for CI/CD pipeline integration:

```hcl
gallery = {
  enabled                 = true
  create_gallery          = true   # Create new gallery
  create_image_definition = true   # Create image definition
  gallery_name            = "sig_contoso_prod"  # Optional override
  image_name              = "img_web_server"    # Optional override
}
```

## Upgrade Modes

| Mode | Description | Use Case |
|------|-------------|----------|
| `Manual` | Instances upgraded manually | Full control over rollouts |
| `Automatic` | Instances upgraded automatically | Non-critical workloads |
| `Rolling` | Gradual rolling upgrade | Zero-downtime deployments |

## Naming Convention

Resources are named using the prefix pattern: `{name}`

Example:
- Linux VMSS: `vmss-{name}-001`
- Windows VMSS: `vmss-{name}-001`
- NIC: `nic-vmss-{name}-001`
- Autoscale: `as-vmss-{name}-001-cpu`
- Gallery: `sig_{name_sanitized}`
- Image: `img_{name_sanitized}`

## Outputs

| Name | Description |
|------|-------------|
| `vmss` | Full VMSS resource object (linux or windows) |
| `vmss_id` | VMSS resource ID |
| `vmss_name` | VMSS name |
| `gallery` | Shared Image Gallery info (if enabled): gallery_name, image_name, IDs |
| `autoscale` | Autoscale setting info (if enabled): id, name |

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.6.0 |
| azurerm | >= 4.0.0 |

## Providers

| Name | Version |
|------|---------|
| azurerm | >= 4.0.0 |

## Inputs

| Name | Description | Type | Required |
|------|-------------|------|----------|
| `name` | Resource name prefix for all resources | string | yes |
| `resource_group` | Resource group configuration | object | yes |
| `subnet_id` | Subnet ID for VMSS NIC attachment | string | yes |
| `vmss` | VMSS configuration (OS type, SKU, instances, identity) | object | yes |
| `tags` | Extra tags merged with default tags | map(string) | no |
| `image` | Image configuration (marketplace or custom image ID) | object | no |
| `admin_password` | VMSS admin password (sensitive) | string | no |
| `user_data` | Cloud-init (Linux) or custom data (Windows), base64 encoded | string | no |
| `autoscale` | Autoscale settings | object | no |
| `gallery` | Shared Image Gallery configuration | object | no |
| `diagnostics` | Azure Monitor diagnostic settings | object | no |

### Detailed Input Specifications

#### vmss

```hcl
object({
  os_type     = string  # linux | windows
  name        = optional(string)
  name_suffix = optional(string, "001")

  sku       = string           # e.g., Standard_B2s, Standard_D4s_v5
  instances = optional(number, 1)

  admin_username       = string
  computer_name_prefix = optional(string)
  ssh_public_key       = optional(string)  # Linux only

  upgrade_mode = optional(string, "Manual")  # Manual | Automatic | Rolling

  identity = optional(object({
    type         = string
    identity_ids = optional(list(string))
  }), {
    type = "SystemAssigned"
  })

  enable_accelerated_networking = optional(bool, false)

  security_type       = optional(string, "Standard")
  secure_boot_enabled = optional(bool, false)
  vtpm_enabled        = optional(bool, false)
})
```

#### image

```hcl
object({
  source_image_id = optional(string)  # SIG version ID

  source_image_reference = optional(object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  }))
})
```

#### autoscale

```hcl
object({
  enabled     = bool
  name_suffix = optional(string, "cpu")

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
      threshold    = number
      direction    = string
      change_count = number
      cooldown     = optional(string, "PT5M")
    })
    scale_in = object({
      threshold    = number
      direction    = string
      change_count = number
      cooldown     = optional(string, "PT10M")
    })
  }))
})
```

## License

Apache 2.0 Licensed. See LICENSE for full details.

## Authors

Module managed by DNX Solutions.

## Contributing

Please read CONTRIBUTING.md for details on our code of conduct and the process for submitting pull requests.
