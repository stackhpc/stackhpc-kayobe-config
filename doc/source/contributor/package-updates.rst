=============================
Package and Container Updates
=============================

This section describes the Release Train process of creating new package repository snapshots and updating the container images to use these new packages. It includes instructions on the recommended way to test these updates, using the multinode test environment.

Preparations
============

1. Before building images, you should check for any outstanding PRs into the earliest supported release. Below are the links for the 2024.1 (Caracal) branches.

 kayobe-config: https://github.com/stackhpc/stackhpc-kayobe-config/pulls?q=is%3Apr+is%3Aopen+base%3Astackhpc%2F2024.1

 kolla: https://github.com/stackhpc/kolla/pulls?q=is%3Apr+is%3Aopen+base%3Astackhpc%2F2024.1

 kolla-ansible: https://github.com/stackhpc/kolla-ansible/pulls?q=is%3Apr+is%3Aopen+base%3Astackhpc%2F2024.1

 You should also check any referenced source trees in etc/kayobe/kolla.yml.

 e.g: https://github.com/stackhpc/stackhpc-kayobe-config/blob/68026c4b2e605fcb0e60786ad438b32a74a50a13/etc/kayobe/kolla.yml#L113-L143

2. Follow the workflows documented `here <https://stackhpc.github.io/stackhpc-release-train/usage/content-howto/#update-package-repositories>`_. Sync the package repositories. Then, for each release:

* Make sure the nightly sync of package repositories has succeeded.

* Update the Kayobe package repository versions.

* Build and push Kolla container images.

* Open a draft PR into ``stackhpc-kayobe-config`` with the updated container image tags.

* Test.

* Review the PR. Once approved, promote the container images before then merging the PR.

The rest of this document describes the final "test" stage.

Testing
=======

The following steps describe the process to test the new package and container repositories. See the subsections beneath for further explanations.

1. Build two multinode environments for OVS and OVN, both on the earliest supported release.

2. Run tests on current package versions as a baseline.

3. Upgrade host packages.

4. Upgrade containers.

5. Run tests again with the new packages.

6. Request reviews for your proposed PR to bring in the new packages.

7. Promote these packages before merging the PR, but after the CI checks have passed.

8. Upgrade OpenStack to the next release.

9.  Repeat steps 2 and 4-7. (Step 3 is skipped as the host packages will be shared across these releases.)

10. Repeat 8 and 9 for any further releases.

Creating the multinode environments
-----------------------------------

The `Multinode deployment workflow <https://github.com/stackhpc/stackhpc-kayobe-config/actions/workflows/stackhpc-multinode.yml>`_ can be used to automatically test changes.

To manually test the changes, there is a comprehensive guide to set up a Multinode environment with Terraform, found here: https://github.com/stackhpc/terraform-kayobe-multinode. There are some things to note:

* OVN is enabled by default, you should override it under ``etc/kayobe/environments/ci-multinode/kolla.yml kolla_enable_ovn: false`` for the OVS multinode environment.

* Remember to set a different ``vxlan_vni`` for each.

* Before starting any tests, run ``dnf distro-sync -y`` on each host to ensure you are using the same snapshots as in the release train. Option ``-y`` is used to prevent hosts hang waiting for the confirmation input. You can do this using the following commands:

   .. code-block:: console

      kayobe seed host command run -b --command "dnf distro-sync -y"
      kayobe overcloud host command run -b --command "dnf distro-sync -y"

* This may have installed a new kernel version. If so, you will need to reboot the overcloud hosts. You can check the installed kernels and the currently running kernel with the following commands. If the latest listed version is not running, you will need to reboot.

.. code-block:: console

   kayobe seed host command run -b --show-output --command "dnf list installed kernel"
   kayobe seed host command run -b --show-output --command "uname -a"

   kayobe playbook run --limit seed,overcloud $KAYOBE_CONFIG_PATH/ansible/reboot.yml

* The tempest tests run automatically at the end of the multinode deployment script. If you have the time, it is worth fixing any failing tests you can so that there is greater coverage for the package updates. (Also remember to propose these fixes in the relevant repos where applicable.)

Upgrading host packages
-----------------------

Checkout the new kayobe-config branch (from the draft PR):

.. code-block:: console

   cd $KAYOBE_CONFIG_ROOT
   git fetch
   git checkout <branch-name>

For Rocky Linux 9, bump the snapshot versions in /etc/yum/repos.d with:

.. code-block:: console

   kayobe seed host configure -t dnf
   kayobe overcloud host configure -t dnf

Install new packages:

.. code-block:: console

   kayobe overcloud host package update --packages "*"

Perform a rolling reboot of hosts:

.. note::
   In the Multinode environment, the seed-hypervisor cannot access control
   plane instances with the Openstack client. To use Openstack client, connect
   to the Seed instance via SSH first. For authentication, use scp to copy
   ``public-openrc.sh`` to the Seed

.. code-block:: console

   # Check your hypervisor hostname
   (seed) openstack hypervisor list

   # Reboot controller instances and zeroth compute instance
   (seed-hypervisor) export ANSIBLE_SERIAL=1
   (seed-hypervisor) kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/reboot.yml --limit controllers
   (seed-hypervisor) kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/reboot.yml --limit compute[0]

   # Test live migration
   (seed) openstack server create --image cirros --flavor m1.tiny --network external --hypervisor-hostname <Your Hypervisor Hostname> --os-compute-api-version 2.74 server1
   (seed) openstack server migrate --live-migration server1
   (seed) watch openstack server show server1

   (seed-hypervisor) kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/reboot.yml --limit compute[1]

   # Try and migrate back
   (seed) openstack server migrate --live-migration server1
   (seed) watch openstack server show server1

Upgrading containers within a release
-------------------------------------

Checkout the new kayobe-config branch (from the draft PR):

.. code-block:: console

   cd $KAYOBE_CONFIG_ROOT
   git fetch
   git checkout <branch-name>

Deploy the services, once the new tags are set in the kayobe_config:

.. code-block:: console

   kayobe overcloud service deploy

Upgrading OpenStack to the next release in a multinode environment
------------------------------------------------------------------

.. warning::

    This guide was written for the Wallaby release and has not been validated
    for Caracal. Proceed with caution.

As this is not a full production system, only a reduced number of steps need to be followed to upgrade to a new release. Below describes these steps, with ``stackhpc/wallaby`` as the starting branch:

.. code-block:: console

   cd <base_path>/src/kayobe-config/
   git fetch
   git checkout -b xena_uber_merge
   git merge origin/stackhpc/xena

   source <base_path>/venvs/kayobe/bin/activate
   cd <base_patch>/src/kayobe
   git checkout stackhpc/xena
   git fetch
   pip install -U ~/src/kayobe

   kayobe control host upgrade
   kayobe overcloud host upgrade

   kayobe overcloud container image pull

   ---Optional
   kayobe overcloud service configuration save --output-dir config/wallaby
   kayobe overcloud service configuration generate --node-config-dir /tmp/kolla-xena-config
   kayobe overcloud service configuration save --output-dir config/xena --node-config-dir /tmp/kolla-xena-config
   kayobe overcloud host command run --command 'rm -rf /tmp/kolla-xena-config' --become
   # Check the diff between the old and new configs
   ---

   kayobe overcloud service upgrade

Tests
-----

Tempest
#######

Run tempest, you can then perform the other tests while it runs. Once complete, check if any tests are failing.

As of February 2023, only one test was expected to fail. This may no longer be the case, so any additional failures are worth exploring.

.. code-block:: console

   tempest.scenario.test_network_basic_ops.TestNetworkBasicOps.test_port_security_macspoofing_port

Poke around horizon
###################

Perform some basic operations such as spawning VMs or attaching/detaching volumes and check that each page works correctly.

Monitoring
##########

Check for any ERROR log messages in Kibana.

Check that the Grafana dashboards are all populated with data.

Check that there are no active alerts.

Check that there are no flapping alerts.

Octavia (OVN only)
##################

You will need to add an Ubuntu image and create a keypair.

.. code-block:: console

   wget http://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64.img

   openstack image create \
       --progress \
       --container-format bare \
       --disk-format qcow2 \
       --file focal-server-cloudimg-amd64.img \
       Ubuntu-20.04

   openstack keypair create --private-key ~/.ssh/os-admin os-admin

Then run Octavia test script:

https://gist.github.com/MoteHue/ee5990bddea0677f54d8bb93d307aa71#file-octavia_test-sh


Attempt to build OFED against the latest kernel in ARK
######################################################

Note that this only needs to be performed once.

.. code-block:: console

   kayobe overcloud host configure -t dnf
   kayobe overcloud host package update --packages "*"

Then run the OFED test script on one of the upgraded overcloud hosts:

https://gist.github.com/cityofships/b4883ee19f75d14534f04115892b8465


