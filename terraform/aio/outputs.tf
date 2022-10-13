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
  value = var.aio_vm_interface
}
