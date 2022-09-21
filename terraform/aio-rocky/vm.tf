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

variable "gitlab_token" {
  type = string
}

variable "rocky_image_version" {
  type = string
  default = "20220921T115104-c8dd7e0"
}

variable "use_local_image" {
  type = bool
  default = false
}

variable aio_rocky_vm_user {
  type = string
  default = "cloud-user"
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

variable aio_rocky_interface {
  type = string
  default = "ens3"
}

locals {
  fqdn = "kayobe-aio-rocky-8"
}

resource "openstack_images_image_v2" "rocky_image" {
  # TODO. Don't upload if already exists
  count = var.use_local_image ? 0 : 1
  name             = "rocky-linux-${var.rocky_image_version}"
  image_source_url = "https://gitlab.com/api/v4/projects/25160749/packages/generic/rocky-linux/${var.rocky_image_version}/rocky-linux-${var.rocky_image_version}.qcow2"
  container_format = "bare"
  disk_format      = "qcow2"
  image_source_username = "gitlab-ci-token"
  image_source_password  = var.gitlab_token
  lifecycle {
    ignore_changes = all
  }
}

data "openstack_images_image_v2" "rocky_image" {
  name  = var.use_local_image ? var.rocky_image_version : "rocky-linux-${var.rocky_image_version}"
  most_recent = true
  depends_on = [
    openstack_images_image_v2.rocky_image
  ]
}

data "openstack_networking_subnet_v2" "network" {
  name = var.aio_rocky_vm_subnet
}

resource "openstack_compute_instance_v2" "kayobe-aio" {
  name            = var.vm_name
  image_id        = data.openstack_images_image_v2.rocky_image.id
  flavor_name     = var.aio_rocky_vm_flavor
  key_pair        = var.aio_rocky_vm_keypair
  config_drive    = true
  user_data       = templatefile("templates/userdata.cfg.tpl", { fqdn = local.fqdn })
  network {
    name = var.aio_rocky_vm_network
  }

  dynamic "block_device" {
      for_each = var.boot_from_volume ? ["create"] : []
      content {
        uuid                  = data.openstack_images_image_v2.rocky_image.id
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
      user     = var.aio_rocky_vm_user
      private_key = file(var.ssh_private_key)
      # /tmp is noexec
      script_path = "/home/${var.aio_rocky_vm_user}/check-ssh-online"
    }
  }

}
