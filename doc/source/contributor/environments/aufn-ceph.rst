=================================
A universe from nothing with Ceph
=================================

This environment creates a Universe-from-nothing_-style deployment of Kayobe consisting of multiple 'virtual baremetal nodes' running as VMs on a single physical hypervisor.

.. _Universe-from-nothing: https://github.com/stackhpc/a-universe-from-nothing

Prerequisites
=============

* a baremetal node with at least 64GB of RAM running CentOS Stream 8 (or Ubuntu)

* access to the test pulp server on SMS lab

Setup
=====

---

**Note**: The steps detailed below are combined into a convenient script which is packaged with this repo at ``etc/kayobe/environments/aufn-ceph/a-universe-from-nothing.sh``. For an automated deployment, this script can simply be copied to the baremetal host and then executed as ``bash ~/a-universe-from-nothing.sh``.

---

To begin the manual setup, access the baremetal node via SSH and install some basic dependencies.

CentOS or Rocky:

.. parsed-literal::

   sudo dnf install -y gcc python3-devel

Ubuntu:

.. parsed-literal::

    sudo apt update
    sudo apt -y install gcc libffi-dev python3-dev python-is-python3


As a workaround for SMS lab's lack of DNS, add the following lines to ``/etc/hosts`` of the baremetal node:

.. parsed-literal::

    10.0.0.34 pelican pelican.service.compute.sms-lab.cloud
    10.205.3.187 pulp-server pulp-server.internal.sms-cloud

Configure the system firewall and security settings:

.. parsed-literal::

    # Disable the firewall.
    sudo systemctl is-enabled firewalld && sudo systemctl stop firewalld && sudo systemctl disable firewalld

    # Disable SELinux both immediately and permanently.
    if $(which setenforce 2>/dev/null >/dev/null); then
        sudo setenforce 0
        sudo sed -i 's/^SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
    fi

    # Prevent sudo from performing DNS queries.
    echo 'Defaults	!fqdn' | sudo tee /etc/sudoers.d/no-fqdn

Clone the Kayobe, Kayobe configuration (this one) and Tenks repositories:

.. parsed-literal::

   cd
   mkdir -p src
   pushd src
   git clone https://github.com/stackhpc/kayobe.git -b |current_release_git_branch_name|
   git clone https://github.com/stackhpc/stackhpc-kayobe-config -b |current_release_git_branch_name| kayobe-config
   pushd kayobe
   git clone https://opendev.org/openstack/tenks.git
   popd
   popd

Create a virtual environment and install Kayobe:

.. parsed-literal::

   cd
   mkdir -p venvs
   pushd venvs
   python3 -m venv kayobe
   source kayobe/bin/activate
   pip install -U pip
   pip install ../src/kayobe
   popd


Installation
============

The following commands activate the correct kayobe environment and prepare the Ansible control host:

.. parsed-literal::

   pushd ~/src/kayobe-config
   source kayobe-env --environment aufn-ceph
   $KAYOBE_CONFIG_PATH/environments/aufn-ceph/configure-local-networking.sh
   kayobe control host bootstrap

Deployment
==========

Next, configure the seed VM:

.. parsed-literal::

    kayobe seed hypervisor host configure
    kayobe seed vm provision
    kayobe seed host configure

Once the seed vm is provisioned, deploy a local pulp server on the seed and then re-add the relevant local networking configuration since ``service deploy`` restarts the networking interface:

.. parsed-literal::

    kayobe seed service deploy --tags seed-deploy-containers --kolla-tags none
    $KAYOBE_CONFIG_PATH/environments/aufn-ceph/configure-local-networking.sh

Once the local pulp server is deployed, we need to add the address of SMS lab test pulp to the local pulp container:

.. parsed-literal::

    ssh stack@192.168.33.5
    docker exec pulp sh -c 'echo "10.205.3.187 pulp-server pulp-server.internal.sms-cloud" | tee -a /etc/hosts'
    exit

We can now sync the contents of the local pulp server with that of SMS test pulp and then complete the seed VM setup:

.. parsed-literal::

    kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp-repo-sync.yml
    kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp-repo-publish.yml
    kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp-container-sync.yml
    kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp-container-publish.yml
    kayobe seed service deploy

With the seed VM configured, we use Tenks_ to deploy an additional set of VMs on the same baremetal node and configure them as 'virual baremetal' hosts in order to replicate a true multi-node kayobe deployment within a single node.

.. _Tenks: https://github.com/stackhpc/tenks

.. parsed-literal::

    export TENKS_CONFIG_PATH=$KAYOBE_CONFIG_PATH/environments/aufn-ceph/tenks.yml
    export KAYOBE_CONFIG_SOURCE_PATH=~/src/kayobe-config
    export KAYOBE_VENV_PATH=~/venvs/kayobe
    pushd ~/src/kayobe
    ./dev/tenks-deploy-overcloud.sh ./tenks
    popd

These nodes can then be provisioned as overcloud control, compute and storage hosts with

.. parsed-literal::

    kayobe overcloud inventory discover
    kayobe overcloud hardware inspect
    kayobe overcloud provision
    kayobe overcloud host configure
    kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/cephadm.yml
    kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/cephadm-gather-keys.yml
    kayobe overcloud container image pull
    kayobe overcloud service deploy
    source $KOLLA_CONFIG_PATH/public-openrc.sh
    kayobe overcloud post configure
    source $KOLLA_CONFIG_PATH/public-openrc.sh

Finally, we create the bare minimum cloud infrastructure (networks, images, flavors etc.) by running the following shell script.

.. parsed-literal::

    $KAYOBE_CONFIG_PATH/environments/aufn-ceph/configure-openstack.sh ~

This completes the deployment process.


Testing
=======

We can deploy a test VM to ensure that our 'universe' is up and running by first creating a python virtual environment with the OpenStack CLI installed.

.. parsed-literal::

    python3 -m venv ~/openstack-env
    source ~/openstack-env/bin/activate
    pip install -U pip
    pip install python-openstackclient

We then use the CLI to create a keypair, floating IP and test VM:

.. parsed-literal::

    openstack keypair create --public-key ~/.ssh/id_rsa.pub mykey
    openstack server create --key-name mykey --flavor m1.tiny --image cirros --network admin-tenant test-vm-1
    openstack floating ip create external
    openstack server add floating ip test-vm-1 `openstack floating ip list -c ID -f value`
    openstack server list

which will create a VM named ``test-vm-1`` with a Cirros OS image and a default login password of 'gocubsgo'.
