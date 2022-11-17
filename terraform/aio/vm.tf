variable "ssh_public_key" {
  type = string
}

variable "ssh_private_key" {
  type = string
}

variable "aio_vm_name" {
  type    = string
  default = "kayobe-aio"
}

variable "aio_vm_image" {
  type    = string
  default = "CentOS-stream8"
}

variable "aio_vm_user" {
  type = string
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

data "openstack_images_image_v2" "image" {
  name        = var.aio_vm_image
  most_recent = true
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
    uuid                  = data.openstack_images_image_v2.image.id
    source_type           = "image"
    volume_size           = 100
    boot_index            = 0
    destination_type      = "volume"
    delete_on_termination = true
  }

  provisioner "file" {
    source      = "scripts/configure-local-networking.sh"
    destination = "/home/${var.aio_vm_user}/configure-local-networking.sh"
    connection {
      type        = "ssh"
      host        = self.access_ip_v4
      user        = var.aio_vm_user
      private_key = file(var.ssh_private_key)
    }
  }

  provisioner "remote-exec" {
    inline = [
      "sudo bash /home/${var.aio_vm_user}/configure-local-networking.sh"
    ]

    connection {
      type        = "ssh"
      host        = self.access_ip_v4
      user        = var.aio_vm_user
      private_key = file(var.ssh_private_key)
      # /tmp is noexec when using stackhpc LVM layout
      script_path = "/home/${var.aio_vm_user}/.configure-local-networking"
    }

  }

}
