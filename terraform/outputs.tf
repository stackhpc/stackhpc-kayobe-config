resource "local_file" "aio-terraform-vars" {
 content  = templatefile("${path.module}/templates/aio-terraform-vars.yml.tpl",
                          {
                            "access_ip_v4": openstack_compute_instance_v2.kayobe-aio.access_ip_v4
                            "access_cidr": data.openstack_networking_subnet_v2.network.cidr
                            "access_gw": data.openstack_networking_subnet_v2.network.gateway_ip
                          },
                          )
  filename = "${path.module}/../etc/kayobe/environments/aio/aio-terraform-vars.yml"
  file_permission = "0660"
}

resource "local_file" "aio-network-allocation" {
 content  = templatefile("${path.module}/templates/network-allocation.yml.tpl",
                          {
                            "access_ip_v4": openstack_compute_instance_v2.kayobe-aio.access_ip_v4
                          },
                          )
  filename = "${path.module}/../etc/kayobe/environments/aio/network-allocation.yml"
  file_permission = "0660"
}
