variable "ssh_public_key" {
  type = string
}

variable "ssh_username" {
  type = string
}

variable "controller_name" {
  type    = string
  default = "kayobe-aio"
}

variable "controller_image" {
  type    = string
  default = "Rocky10"
}

variable "controller_interface" {
  type    = string
  default = "eth0"
}

variable "controller_flavor" {
  type = string
}

variable "baremetal_flavor" {
  type = string
}

variable "baremetal_network" {
  type = string
}

variable "controller_volume_size" {
  type    = number
  default = 50
}

variable "controller_tags" {
  type    = list(string)
  default = []
}

variable "baremetal_count" {
  type    = number
  default = 2
}

locals {
  image_is_uuid = length(regexall("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.controller_image)) > 0
}

data "openstack_images_image_v2" "image" {
  name        = var.controller_image
  most_recent = true
  count = local.image_is_uuid ? 0 : 1
}

resource "openstack_compute_instance_v2" "controller" {
  name         = var.controller_name
  flavor_name  = var.controller_flavor
  config_drive = true
  user_data    = templatefile("templates/userdata.cfg.tpl", {ssh_public_key = file(var.ssh_public_key)})
  security_groups = ["kayobe-runner"]
  network = [
    name = stackhpc-ipv4-vlan
  ]
  network = [
    name = stackhpc-ipv4-geneve
    access_network = true
  ]

  block_device {
    uuid                  = local.image_is_uuid ? var.controller_image: data.openstack_images_image_v2.image[0].id
    source_type           = "image"
    volume_size           = var.controller_volume_size
    boot_index            = 0
    destination_type      = "volume"
    delete_on_termination = true
  }

  tags = var.controller_tags
}

# Wait for the instance to be accessible via SSH before progressing.
resource "null_resource" "controller" {
  provisioner "remote-exec" {
    connection {
      host = openstack_compute_instance_v2.controller.access_ip_v4
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

resource "openstack_compute_instance_v2" "baremetal" {
  name         = format("%s-compute-%02d", var.prefix, count.index + 1)
  flavor_name  = var.baremetal_flavor
  image_name   = var.controller_image
  config_drive = true
  user_data    = templatefile("templates/userdata.cfg.tpl", {ssh_public_key = file(var.ssh_public_key)})

  count        = var.baremetal_count
  network {
    name = var.baremetal_network
  }

  timeouts {
    create = "90m"
  }
  tags = var.instance_tags
}
