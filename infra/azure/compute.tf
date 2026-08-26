resource "azurerm_linux_virtual_machine" "runtime" {
  name                            = local.name_prefix
  computer_name                   = "escqrs"
  location                        = azurerm_resource_group.runtime.location
  resource_group_name             = azurerm_resource_group.runtime.name
  size                            = var.vm_size
  admin_username                  = var.admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.runtime.id]
  secure_boot_enabled             = true
  vtpm_enabled                    = true
  custom_data = base64encode(templatefile("${path.module}/templates/cloud-init.sh.tftpl", {
    acme_email      = var.acme_email
    buildx_sha256   = var.buildx_sha256
    buildx_version  = var.buildx_version
    compose_version = var.compose_version
    public_host     = azurerm_public_ip.runtime.fqdn
    repository_ref  = var.repository_ref
    repository_url  = var.repository_url
  }))

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_ssh_public_key
  }

  os_disk {
    name                 = "${local.name_prefix}-os"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = var.os_disk_size_gib
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  boot_diagnostics {}

  identity {
    type = "SystemAssigned"
  }

  tags = local.tags

  depends_on = [
    azurerm_network_interface_security_group_association.runtime,
    azurerm_network_security_rule.http,
    azurerm_network_security_rule.https,
  ]
}
