#!/bin/bash

# Fail over octavia loadbalancers to the latest amphora image.

set -ex

expected_image=$(openstack image show amphora-x64-haproxy.qcow2 -f value -c id)

openstack loadbalancer amphora list --status ALLOCATED -f value -c id | while read a; do
  image=$(openstack loadbalancer amphora show $a -f value -c image_id)
  if [[ $image != "None" ]] && [[ $image != $expected_image ]]; then
    lb_id=$(openstack loadbalancer amphora show $a -f value -c loadbalancer_id)
    echo "Failing over loadbalancer $lb_id (amphora $a)"
    if ! openstack loadbalancer failover $lb_id --wait; then
      echo "Failed failing over loadbalancer $lb_id"
    fi
  fi
done
