==========================
Multinode Test Environment
==========================

Set up hosts
============
1. Create four baremetal instances with a centos 8 stream LVM image, and a
   Centos 8 stream vm
2. SSH into each baremetal and run ``sudo chown -R centos:.`` in the home
   directory, then add the lines::

      10.0.0.34 pelican pelican.service.compute.sms-lab.cloud
      10.205.3.187 pulp-server pulp-server.internal.sms-cloud

   to ``/etc/hosts`` (if you're waiting on them starting up, you can progress
   until ``kayobe overcloud host configure`` without this step)

Basic Kayobe Setup
==================
1. SSH into the VM
2. ``sudo dnf install -y python3-virtualenv``
3. ``mkdir src`` and ``cd src``
4. Clone https://github.com/stackhpc/stackhpc-kayobe-config.git, then checkout
   commit f31df6256f1b1fea99c84547d44f06c4cb74b161
5. ``cd ..`` and ``mkdir venvs``
6. ``virtualenv venvs/kayobe`` and source ``venvs/kayobe/bin/activate``
7. ``pip install -U pip``
8. ``pip install ./src/kayobe``
9. Acquire the Ansible Vault password for this repository, and store a copy at
   ``~/vault-pw``
10. ``export KAYOBE_VAULT_PASSWORD=$(cat ~/vault-pw)``

Config changes
==============
1. In etc/kayobe/ansible/requirements.yml remove version from vxlan
2. In etc/kayobe/ansible/configure-vxlan.yml, change the group of
   vxlan_interfaces so that the last octet is different e.g. 224.0.0.15
3. Also under vxlan_interfaces, add vni:x where x is between 500 and 1000
4. Also under vxlan_interfaces, check vxlan_dstport is not 4789 (this causes
   conflicts, change to 4790)
5. In /etc/kayobe/environments/ci-multinode/tf-networks.yml, edit admin_ips so
   that the compute and controller IPs line up with the
   instances that were created earlier, remove the other IPs for seed and
   cephOSD
6. In /etc/kayobe/environments/ci-multinode/network-allocation.yml, remove all
   the entries and just assign ``aio_ips:`` an empty set ``[]``
7. In etc/kayobe/environments/ci-multinode/inventory/hosts, remove the seed
8. run stackhpc-kayobe-config/etc/kayobe/ansible/growroot.yml (if this fails,
   manually increase the partition size on each host)

Final steps
===========
1. ``source kayobe-env --environment ci-aio``
2. Run ``kayobe overcloud host configure``
3. Run ``kayobe overcloud service deploy``
