# Custom Ansible assets

## Cephadm

The Cephadm custom playbook wraps around Ansible Cephadm collection
(https://galaxy.ansible.com/stackhpc/cephadm) and provides means to
create or modify Ceph cluster deployments. Supported features are:
- creating a new cluster from scratch (RedHat/Debian family distros supported)
- creating pools, users, CRUSH rules and EC profiles
- modifying the OSD spec after initial deployment
- destroying the cluster.

The collection assumes a set of host and group entries in Ansible's inventory,
usually in a separate file dedicated to Ceph setup, e.g.
`$KAYOBE_CONFIG_PATH/inventory/ceph`.

Typically we execpt the follow groups:
- ceph (parent for all ceph nodes)
- mons
- mgrs
- osds
- rgws

Necessary variables for using the collection are located in a single file
`$KAYOBE_CONFIG_PATH/inventory/group_vars/ceph`. It is usually convenient to reuse some
of the variables that are already present in Kayobe configuration.

Applying the configuration is as easy as running:
`kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/cephadm.yml`.
