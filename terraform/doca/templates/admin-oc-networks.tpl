---
admin_oc_cidr: ${ access_cidr }
admin_oc_allocation_pool_start: 0.0.0.0
admin_oc_allocation_pool_end: 0.0.0.0
admin_oc_bootproto: dhcp

admin_oc_ips:
  controller0: ${ aio_addr }
  %{ for hostname, addr in zipmap(compute_hostname, compute) ~}
    ${ hostname }: ${ addr }
  %{ endfor ~}
