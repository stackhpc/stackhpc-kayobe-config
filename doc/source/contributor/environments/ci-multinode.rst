==========================
Multinode Test Environment
==========================

.. warning::

    This guide was written for the Yoga release and has not been validated for
    Caracal. Proceed with caution.

The ``ci-multinode`` environment provides a Kayobe configuration for multi-node
clouds to be used for test and development purposes. It is designed to be used
in combination with the `terraform-kayobe-multinode
<https://github.com/stackhpc/terraform-kayobe-multinode>`__ repository. Follow
the instructions in terraform-kayobe-multinode to deploy a cluster using this
configuration. This documentation covers configuration of additional services
beyond the defaults. This includes:

* Manila
* Magnum
* Wazuh

.. seealso::

   On-demand and nightly GitHub Actions workflows workflow using this
   environment are described :ref:`here <testing-multinode>`.

Manila
======
The Multinode environment supports Manila with the CephFS native backend, but it
is not enabled by default. To enable it, set the following in
``etc/kayobe/environments/ci-multinode/kolla.yml``:

.. code-block:: yaml

      kolla_enable_manila: true
      kolla_enable_manila_backend_cephfs_native: true

If you are working on an existing deployment, you need to do the following first.

1. Create CephFS pools: ``kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/cephadm-pools.yml``
2. Create cephx key for Manila: ``kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/cephadm-keys.yml``
3. Run Manila related Ceph commands: ``kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/cephadm-commands-post.yml``
4. Gather Ceph configuration and keyring for Manila: ``kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/cephadm-gather-keys.yml``
5. Configure Storage network on Seed node: ``kayobe seed host configure -t network,ip-allocation,snat``

Then, run ``kayobe overcloud service deploy`` to deploy Manila.

To test it, you will need two virtual machines. Cirros does not support the Ceph
kernel client, so you will need to use a different image. Any regular Linux
distribution should work. As an example, this guide will use Ubuntu 22.04.

Download the image locally:

.. code-block:: bash

      wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img

Upload the image to Glance:

.. code-block:: bash

      openstack image create --container-format bare --disk-format qcow2 --file jammy-server-cloudimg-amd64.img Ubuntu-22.04 --progress

Create a keypair:

.. code-block:: bash

      openstack keypair create --private-key ~/.ssh/id_rsa id_rsa

Create two virtual machines from the image:

.. code-block:: bash

      openstack server create --flavor m1.small --image Ubuntu-22.04 --key-name id_rsa --network admin-tenant ubuntu-client-1
      openstack server create --flavor m1.small --image Ubuntu-22.04 --key-name id_rsa --network admin-tenant ubuntu-client-2

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

      pip install python-manilaclient

Then create a share type and share:

.. code-block:: bash

      openstack share type create cephfs-type false --public true
      openstack share type set cephfs-type --extra-specs vendor_name=Ceph, storage_protocol=CEPHFS
      openstack share create --name test-share --share-type cephfs-type --public true CephFS 2

Wait until the share is available:

.. code-block:: bash

      openstack share list

Then allow access to the shares to two users:

.. code-block:: bash

      openstack share access create test-share cephx alice
      openstack share access create test-share cephx bob

Show the access list to make sure the state of both entries is ``active`` and
take note of the access keys:

.. code-block:: bash

      openstack share access list test-share

And take note of the path to the share:

.. code-block:: bash

      openstack share export location list test-share

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

Magnum
======

The Multinode environment has Magnum enabled by default. To test it, you will
need to create a Kubernetes cluster. It is recommended that you use the
specified Fedora 35 image, as others may not work. Download the image locally,
then extract it and upload it to glance:

.. code-block:: bash

      wget https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/35.20220410.3.1/x86_64/fedora-coreos-35.20220410.3.1-openstack.x86_64.qcow2.xz
      unxz fedora-coreos-35.20220410.3.1-openstack.x86_64.qcow2.xz
      openstack image create --container-format bare --disk-format qcow2 --property os_distro='fedora-coreos' --property os_version='35' --file fedora-coreos-35.20220410.3.1-openstack.x86_64.qcow2 fedora-coreos-35 --progress

Create a keypair:

.. code-block:: bash

      openstack keypair create --private-key ~/.ssh/id_rsa id_rsa

Install the Magnum, Heat, and Octavia clients:

.. code-block:: bash

      pip install python-magnumclient
      pip install python-heatclient
      pip install python-octaviaclient

Create a cluster template:

.. code-block:: bash

      openstack coe cluster template create test-template --image fedora-coreos-35 --external-network external --labels etcd_volume_size=8,boot_volume_size=50,cloud_provider_enabled=true,heat_container_agent_tag=wallaby-stable-1,kube_tag=v1.23.6,cloud_provider_tag=v1.23.1,monitoring_enabled=true,auto_scaling_enabled=true,auto_healing_enabled=true,auto_healing_controller=magnum-auto-healer,magnum_auto_healer_tag=v1.23.0.1-shpc,etcd_tag=v3.5.4,master_lb_floating_ip_enabled=true,cinder_csi_enabled=true,container_infra_prefix=ghcr.io/stackhpc/,min_node_count=1,max_node_count=50,octavia_lb_algorithm=SOURCE_IP_PORT,octavia_provider=ovn --dns-nameserver 8.8.8.8 --flavor m1.medium --master-flavor m1.medium --network-driver calico --volume-driver cinder --docker-storage-driver overlay2 --floating-ip-enabled --master-lb-enabled --coe kubernetes

Create a cluster:

.. code-block:: bash

      openstack coe cluster create --cluster-template test-template --keypair id_rsa --master-count 1 --node-count 1 --floating-ip-enabled test-cluster

This command will take a while to complete. You can monitor the progress with
the following command:

.. code-block:: bash

      watch "openstack --insecure coe cluster list ; openstack --insecure stack list ; openstack --insecure server list"

Once the cluster is created, you can SSH into the master node and check that
there are no failed containers:

.. code-block:: bash

      ssh core@{master-ip}

List the podman and docker containers:

.. code-block:: bash

      sudo docker ps
      sudo podman ps

If there are any failed containers, you can check the logs with the following
commands:

.. code-block:: bash

      sudo docker logs {container-id}
      sudo podman logs {container-id}

Or look at the logs under ``/var/log``. In particular, pay close attention to
``/var/log/heat-config`` on the master and
``/var/log/kolla/{magnum,heat,neutron}/*`` on the controllers.

Otherwise, the ``state`` of the cluster should eventually become
``CREATE_COMPLETE`` and the ``health_status`` should be ``HEALTHY``.

You can interact with the cluster using ``kubectl``. The instructions for
installing ``kubectl`` are available `here
<https://kubernetes.io/docs/tasks/tools/install-kubectl/>`_. You can then
configure ``kubectl`` to use the cluster, and check that the pods are all
running:

.. code-block:: bash

      openstack coe cluster config test-cluster --dir $PWD
      export KUBECONFIG=$PWD/config
      kubectl get pods -A

Finally, you can optionally use sonobuoy to run a complete set of Kubernetes
conformance tests.

Find the latest release of sonobuoy on their `github releases page
<https://github.com/vmware-tanzu/sonobuoy/releases>`_. Then download it with wget, e.g.:

.. code-block:: bash

      wget https://github.com/vmware-tanzu/sonobuoy/releases/download/v0.56.16/sonobuoy_0.56.16_linux_amd64.tar.gz

Extract it with tar:

.. code-block:: bash

      tar -xvf sonobuoy_0.56.16_linux_amd64.tar.gz

And run it:

.. code-block:: bash

      ./sonobuoy run --wait

This will take a while to complete. Once it is done you can check the results
with:

.. code-block:: bash

      results=$(./sonobuoy retrieve)
      ./sonobuoy results $results

There are various other options for sonobuoy, see the `documentation
<https://sonobuoy.io/docs/>`_ for more details.

Wazuh
======

Adding Wazuh to a new deployment
--------------------------------

Wazuh is supported but not deployed by default. If you are using the standard
[StackHPC multinode
terraform](https://github.com/stackhpc/terraform-kayobe-multinode), there is a
``deploy_wazuh`` terraform variable that will add it to the automated setup.

Adding Wazuh to an existing deployment
--------------------------------------

Create an additional VM with the same basic configuration (key, image, flavour
etc.) as the existing deployment.

Add the IP and hostname to ``/etc/hosts`` on the ansible control host.

Add the hostname to the ``[wazuh-manager]`` group in
``$KAYOBE_CONFIG_PATH/environments/ci-multinode/inventory/hosts``.

Add the host to the ``[infra-vms]`` group, either directly or by making the
``wazuh-manager`` group a child group of ``infra-vms``.

Create the following directory structure:
``$KAYOBE_CONFIG_PATH/hooks/infra-vm-host-configure/pre.d/``

Either copy or symlink in the growroot, networking, and vxlan playbooks as
shown in ``$KAYOBE_CONFIG_PATH/hooks/seed-host-configure/pre.d/``.

Configure the Wazuh manager VM:

.. code-block:: bash

      kayobe infra vm host configure

Create and encrypt the Wazuh secrets

.. code-block:: bash

      kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/wazuh-secrets.yml
      ansible-vault encrypt --vault-password-file ~/vault.password  $KAYOBE_CONFIG_PATH/environments/ci-multinode/wazuh-secrets.yml

Run the Wazuh manager and agent deployment playbooks:

.. code-block:: bash

      kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/wazuh-manager.yml
      kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/wazuh-agent.yml

Wazuh should now be fully deployed. To test the service, you can use sshuttle
or some other forwarding protocol to access the Wazuh dashboard.

.. code-block:: bash

      sshuttle -r <wazuh-manager-hostname> <wazuh-manager-ip>

The above example assumes an SSH configuration that allows access with
``ssh <wazuh-manager-hostname>``.

Open ``https://<wazuh-manager-ip>/`` in a web browser, and you should see a
login screen.

The default username is ``admin`` and the password is the
``opendistro_admin_password`` which can be found in ``wazuh-secrets.yml`` e.g.

.. code-block:: bash

      ansible-vault view $KAYOBE_CONFIG_PATH/environments/ci-multinode/wazuh-secrets.yml --vault-password-file ~/vault.password | grep opendistro_admin_password

If the deployment has been successful, you should be able to see a Wazuh agent
for each host in your deployment (aside from the Wazuh manager itself).
