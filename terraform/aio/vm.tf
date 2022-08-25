variable "ssh_private_key" {
   type = string
   default = "~/.ssh/id_rsa"
}

variable vm_name {
  type = string
  default = "kayobe-aio-stream8"
}

variable boot_from_volume {
  type = bool
  default = true
}

variable aio_stream8_vm_image {
  type = string
  default = "CentOS-stream8"
}

variable aio_stream8_vm_keypair {
  type = string
  default = "gitlab-runner"
}

variable aio_stream8_vm_flavor {
  type = string
  default = "general.v1.large"
}

variable aio_stream8_vm_network {
  type = string
  default = "stackhpc-ipv4-geneve"
}

variable aio_stream8_vm_subnet {
  type = string
  default = "stackhpc-ipv4-geneve-subnet"
}

locals {
  fqdn = "kayobe-aio-centos-8s'
}

data "openstack_images_image_v2" "image" {
  name        = var.aio_stream8_vm_image
  most_recent = true
}

data "openstack_networking_subnet_v2" "network" {
  name = var.aio_stream8_vm_subnet
}

resource "openstack_compute_instance_v2" "kayobe-aio-stream8" {
  name            = var.vm_name
  image_id        = data.openstack_images_image_v2.image.id
  flavor_name     = var.aio_stream8_vm_flavor
  key_pair        = var.aio_stream8_vm_keypair
  config_drive    = true
  user_data       = templatefile("templates/userdata.cfg.tpl", { fqdn = local.fqdn })
  network {
    name = var.aio_stream8_vm_network
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

  provisioner "remote-exec" {
    inline = [
        "echo SSH online"
    ]
    connection {
        type     = "ssh"
        host     = self.access_ip_v4
        user     = "centos"
        private_key = file(var.ssh_private_key)
    }
  }

}
