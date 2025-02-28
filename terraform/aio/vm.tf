variable "ssh_public_key" {
  type = string
}

variable "ssh_username" {
  type = string
}

variable "aio_vm_name" {
  type    = string
  default = "kayobe-aio"
}

variable "aio_vm_image" {
  type    = string
  default = "Rocky9"
}

variable "aio_vm_interface" {
  type = string
  default = "eth0"
}

variable "aio_vm_flavor" {
  type = string
}

variable "aio_vm_network" {
  type = string
}

variable "aio_vm_subnet" {
  type = string
}

variable "aio_vm_volume_size" {
  type = number
  default = 50
}

variable "aio_vm_tags" {
  type = list(string)
  default = []
}

locals {
  image_is_uuid = length(regexall("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.aio_vm_image)) > 0
}

data "openstack_images_image_v2" "image" {
  name        = var.aio_vm_image
  most_recent = true
  count = local.image_is_uuid ? 0 : 1
}

data "openstack_networking_subnet_v2" "network" {
  name = var.aio_vm_subnet
}

resource "openstack_compute_instance_v2" "kayobe-aio" {
  name         = var.aio_vm_name
  flavor_name  = var.aio_vm_flavor
  config_drive = true
  user_data    = templatefile("templates/userdata.cfg.tpl", {ssh_public_key = file(var.ssh_public_key)})
  network {
    name = var.aio_vm_network
  }

  block_device {
    uuid                  = local.image_is_uuid ? var.aio_vm_image: data.openstack_images_image_v2.image[0].id
    source_type           = "image"
    volume_size           = var.aio_vm_volume_size
    boot_index            = 0
    destination_type      = "volume"
    delete_on_termination = true
  }

  tags = var.aio_vm_tags
}

# Wait for the instance to be accessible via SSH before progressing.
resource "null_resource" "kayobe-aio" {
  provisioner "remote-exec" {
    connection {
      host = openstack_compute_instance_v2.kayobe-aio.access_ip_v4
      user = var.ssh_username
      private_key = file("id_rsa")
      # Terraform will run the start script from /tmp by default. For the
      # current images, /tmp is noexec, so the path must be changed
      script_path = "/home/${var.ssh_username}/start.sh"
    }

    inline = [
      "#!/bin/sh",
      "echo 'connected!'"
      ]
  }
}
