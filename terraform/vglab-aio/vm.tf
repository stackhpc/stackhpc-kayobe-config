
variable "ssh_private_key" {
   type = string
   default = "~/.ssh/id_rsa"
}

variable vm_name {
  type = string
  default = "kayobe-aio"
}

data "openstack_images_image_v2" "image" {
  name        = "CentOS8.3-cloud"
  most_recent = true
}

data "openstack_networking_subnet_v2" "network" {
  name = "stackhpc-ipv4-geneve-subnet"
}

resource "openstack_compute_instance_v2" "kayobe-aio" {
  name            = var.vm_name
  flavor_name     = "general.v1.large"
  key_pair        = "gitlab-runner"
  config_drive    = true
  user_data        = file("templates/userdata.cfg.tpl")
  network {
    name = "stackhpc-ipv4-geneve"
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
    destination = "/home/centos/configure-local-networking.sh"

    connection {
      type     = "ssh"
      host     = self.access_ip_v4
      user     = "centos"
      private_key = file(var.ssh_private_key)
    }
  }

  provisioner "remote-exec" {
  inline = [
      "sudo bash /home/centos/configure-local-networking.sh"
   ]

    connection {
      type     = "ssh"
      host     = self.access_ip_v4
      user     = "centos"
      private_key = file(var.ssh_private_key)
    }

  }
}


