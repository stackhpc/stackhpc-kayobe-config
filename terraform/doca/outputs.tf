output "access_ip_v4" {
  value = openstack_compute_instance_v2.kayobe-aio.access_ip_v4
}

output "access_cidr" {
  value = data.openstack_networking_subnet_v2.network.cidr
}

output "access_gw" {
  value = data.openstack_networking_subnet_v2.network.gateway_ip
}

output "access_interface" {
  value = var.controller_interface
}

resource "local_file" "admin_networks" {
  content = templatefile(
    "${path.module}/templates/admin-oc-networks.tpl",
    {
      access_cidr      = data.openstack_networking_subnet_v2.network.cidr
      compute_hostname = openstack_compute_instance_v2.baremetal.*.name
      compute          = openstack_compute_instance_v2.baremetal.*.access_ip_v4
      aio              = openstack_compute_instance_v2.controller.access_ip_v4
    }
  )
  filename        = "ansible/files/admin-oc-networks.yml"
  file_permission = "0644"
}
