
variable "ssh_private_key" {
   type = string
   default = "~/.ssh/id_rsa"
}

variable vm_name {
  type = string
  default = "kayobe-aio"
}

data "openstack_networking_subnet_v2" "network" {
  name = "stackhpc-ipv4-geneve-subnet"
}

resource "openstack_compute_instance_v2" "kayobe-aio" {
  name            = var.vm_name
  image_name      = "CentOS8.3-cloud"
  flavor_name     = "general.v1.large"
  key_pair        = "gitlab-runner"
  config_drive    = true
  user_data        = file("templates/userdata.cfg.tpl")
  network {
    name = "stackhpc-ipv4-geneve"
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


