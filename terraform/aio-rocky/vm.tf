variable "ssh_private_key" {
   type = string
   default = "~/.ssh/id_rsa"
}

variable vm_name {
  type = string
  default = "kayobe-rocky-aio"
}

variable boot_from_volume {
  type = bool
  default = true
}

variable aio_rocky_vm_image {
  type = string
  default = "Rocky-8-GenericCloud-8.5-20211114.2.x86_64"
}

variable aio_rocky_vm_keypair {
  type = string
  default = "gitlab-runner"
}

variable aio_rocky_vm_flavor {
  type = string
  default = "general.v1.large"
}

variable aio_rocky_vm_network {
  type = string
  default = "stackhpc-ipv4-geneve"
}

variable aio_rocky_vm_subnet {
  type = string
  default = "stackhpc-ipv4-geneve-subnet"
}

data "openstack_images_image_v2" "image" {
  name        = var.aio_rocky_vm_image
  most_recent = true
}

data "openstack_networking_subnet_v2" "network" {
  name = var.aio_rocky_vm_subnet
}

resource "openstack_compute_instance_v2" "kayobe-aio" {
  name            = var.vm_name
  image_id        = data.openstack_images_image_v2.image.id
  flavor_name     = var.aio_rocky_vm_flavor
  key_pair        = var.aio_rocky_vm_keypair
  config_drive    = true
  user_data        = file("templates/userdata.cfg.tpl")
  network {
    name = var.aio_rocky_vm_network
  }

  dynamic "block_device" {
      for_each = var.boot_from_volume ? ["create"] : []
      content {
        uuid                  = data.openstack_images_image_v2.image.id
        source_type           = "image"
        volume_size           = 100
        boot_index            = 0
        destination_type      = "volume"
        delete_on_termination = true
      }
  }

  provisioner "file" {
    source      = "scripts/configure-local-networking.sh"
    destination = "/home/rocky/configure-local-networking.sh"

    connection {
      type     = "ssh"
      host     = self.access_ip_v4
      user     = "rocky"
      private_key = file(var.ssh_private_key)
    }
  }

  provisioner "remote-exec" {
  inline = [
      "sudo bash /home/rocky/configure-local-networking.sh"
   ]

    connection {
      type     = "ssh"
      host     = self.access_ip_v4
      user     = "rocky"
      private_key = file(var.ssh_private_key)
    }

  }
}
