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


Manila
======
The Multinode environment supports Manila with the CephFS native backend, but it
is not enabled by default. To enable it, set the following in
``/etc/kayobe/environments/ci-multinode/kolla.yml``:

.. code-block:: yaml

      kolla_enable_manila: true
      kolla_enable_manila_backend_cephfs: true

And re-run ``kayobe overcloud service deploy`` if you are working on an existing
deployment.

To test it, you will need two virtual machines. Cirros does not support the Ceph
kernel client, so you will need to use a different image. Any regular Linux
distribution should work. As an example, we will use Ubuntu 20.04.

Download the image locally:

.. code-block:: bash

      wget http://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64.img

Upload the image to Glance:

.. code-block:: bash

      openstack image create --container-format bare --disk-format qcow2 --file focal-server-cloudimg-amd64.img Ubuntu-20.04 --progress

Create a keypair:

.. code-block:: bash

      openstack keypair create --private-key ~/.ssh/id_rsa id_rsa

Create two virtual machines from the image:

.. code-block:: bash

      openstack server create --flavor m1.small --image Ubuntu-20.04 --key-name id_rsa --network admin-tenant ubuntu-client-1
      openstack server create --flavor m1.small --image Ubuntu-20.04 --key-name id_rsa --network admin-tenant ubuntu-client-2

Wait until the instances are active. It is worth noting that this process can
take a while, especially if the overcloud is deployed to virtual machines. You
can monitor the progress with the following command:

.. code-block:: bash

      watch openstack server list

Once they are active, create two floating IPs:

.. code-block:: bash

      openstack floating ip create external
      openstack floating ip create external

Associate the floating IPs to the instances:

.. code-block:: bash

      openstack server add floating ip ubuntu-client-1 <floating-ip-1>
      openstack server add floating ip ubuntu-client-2 <floating-ip-2>


Then SSH into each instance and install the Ceph client:

.. code-block:: bash

      sudo apt update
      sudo apt install -y ceph-common


Back on the host, install the Manila client:

.. code-block:: bash

      sudo dnf install -y python-manilaclient

Then create a share type and share:

.. code-block:: bash

      manila type-create cephfs-type false --is_public true
      manila type-key cephfs-type set vendor_name=Ceph storage_protocol=CEPHFS
      manila create --name test-share --share-type cephfs-type CephFS 2

Wait until the share is available:

.. code-block:: bash

      manila list

Then allow access to the shares to two users:

.. code-block:: bash

      manila access-allow test-share cephx alice
      manila access-allow test-share cephx bob

Show the access list to make sure the state of both entries is ``active`` and
take note of the access keys:

.. code-block:: bash

      manila access-list test-share

And take note of the path to the share:

.. code-block:: bash

      manila share-export-location-list test-share

SSH into the first instance, create a directory for the share, and mount it:

.. code-block:: bash

      mkdir testdir
      sudo mount -t ceph {path} -o name=alice,secret='{access_key}' testdir

Where the path is the path to the share from the previous step, and the secret
is the access key for the user alice.

Then create a file in the share:

.. code-block:: bash

      sudo touch testdir/testfile

SSH into the second instance, create a directory for the share, and mount it:

.. code-block:: bash

      mkdir testdir
      sudo mount -t ceph {path} -o name=bob,secret='{access_key}' testdir

Where the path is the same as before, and the secret is the access key for the
user bob.

Then check that the file created in the first instance is visible in the second
instance:

.. code-block:: bash

      ls testdir

If it shows the test file then the share is working correctly.
