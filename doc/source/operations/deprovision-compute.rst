# 1. Check the hypervisor

openstack compute service list --host <node>
openstack server list --all-projects --host <node>

# 2. Put it into maintenance mode:
source ~/<your_checkout>/src/kayobe-config/etc/kolla/public-openrc.sh
kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/maintenance/nova-compute-disable.yml --limit <node> -e disabled_reason="decommission <ticket>"

# or use openstack cli
openstack compute service set --disable --disable-reason "decommission <ticket>" <node> nova-compute

# 3. Drain the node

kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/maintenance/nova-compute-drain.yml --limit <node>

# the playbook only handles --status ACTIVE, so clear the rest by hand
openstack server list --all-projects --host <node> --status SHUTOFF
openstack server list --all-projects --host <node> --status PAUSED
openstack server list --all-projects --host <node> --status ERROR
# cold migrate each one
openstack server migrate <id> --wait

# 4. Confirm it's empty
# on to-be-decommissioned node
docker exec nova_libvirt virsh list --all

# 5. Destroy containers and systemd units

sudo systemctl disable --now $(systemctl list-units 'kolla*' --all --plain --no-legend | awk '{print $1}')
docker stop $(docker ps -aq); docker rm $(docker ps -aq)

6. Remove it from the control plane

# only now, with nothing running - delete any of these while its container is up
# and it re-registers, the OVN metadata agent especially (Chassis_Private derived)
openstack compute service delete <service-id>
# If present openstack resource provider list --name <node>
openstack resource provider delete <uuid>
# Get list of net agents openstack network agent list --host <node>
openstack network agent delete <agent-id>
3 On a controller check if chassis exists and delete sudo docker exec ovn_sb_db ovn-sbctl --no-leader-only --columns=chassis_name,ip,type list Encap
sudo docker exec ovn_sb_db ovn-sbctl --no-leader-only chassis-del <node>

7. Remove it from Kayobe and monitoring

# until this runs, Prometheus keeps scraping its exporters and haproxy/fluentd
# keep referencing it
grep -rn '<node>' $KAYOBE_CONFIG_PATH/
# remove it from etc/kayobe/inventory/overcloud and any group vars, then:
kayobe overcloud service reconfigure --kolla-limit controllers,monitoring

8. Deprovision the hardware

# from the seed - undeploy wipes and returns it to 'available'
sudo docker exec -it bifrost_deploy bash -c 'export OS_CLOUD=bifrost; openstack baremetal node undeploy <node>'

# only if it is leaving the estate entirely - also drops it from Bifrost
sudo docker exec -it bifrost_deploy bash -c 'export OS_CLOUD=bifrost; openstack baremetal node delete <node>'

kayobe overcloud inventory discover

9. Verification

sudo docker exec rabbitmq rabbitmqctl list_connections --silent peer_host | sort -u
sudo docker exec ovn_sb_db ovn-sbctl --no-leader-only --columns=chassis_name,ip,type list Encap
openstack compute service list
openstack network agent list