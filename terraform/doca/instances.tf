module "aio" {
  source "../aio"
}

resource "openstack_compute_instance_v2" "baremetal" {
  name         = format("%s-compute-%02d", var.prefix, count.index + 1)
  flavor_name  = var.multinode_flavor
  key_pair     = resource.openstack_compute_keypair_v2.keypair.name
  image_name   = var.multinode_image
  config_drive = true
  user_data    = file("templates/userdata.cfg.tpl")
  count        = var.compute_count
  network {
    name = var.multinode_vm_network
  }
  dynamic "block_device" {
    for_each = var.compute_disk_size > 0 ? [1] : []
    content {
      uuid                  = data.openstack_images_image_v2.multinode_image.id
      source_type           = "image"
      volume_size           = var.compute_disk_size
      boot_index            = 0
      destination_type      = "volume"
      delete_on_termination = true
      volume_type = var.volume_type == "" ? null : var.volume_type
    }
  }
  timeouts {
    create = "90m"
  }
  tags = var.instance_tags
}