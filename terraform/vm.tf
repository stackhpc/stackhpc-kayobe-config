
data "openstack_networking_subnet_v2" "network" {
  name = "ilab"
}

resource "openstack_compute_instance_v2" "kayobe-aio" {
  name            = "kayobe-aio"
  image_name      = "CentOS-8-GenericCloud-8.3.2011-20201204.2.x86_64"
  flavor_name     = "optimised.v1.large"
  key_pair        = "ilab_sclt100"
  config_drive    = true
  user_data        = file("templates/userdata.cfg.tpl")
  network {
    name = data.openstack_networking_subnet_v2.network.name
  }

  provisioner "file" {
    source      = "scripts/configure-local-networking.sh"
    destination = "/home/centos/configure-local-networking.sh"

    connection {
      type     = "ssh"
      host     = self.access_ip_v4
      user     = "centos"
      private_key = file("~/.ssh/id_rsa")
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
      private_key = file("~/.ssh/id_rsa")
    }

  }
}


