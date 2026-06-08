===
aio
===

This environment deploys an all-in-one converged control/compute cloud for
testing.

There are two ways to set up the environment. The automated setup script
automates the manual setup steps below, and is recommended for most users.
The manual setup steps are provided for reference, and for users who wish to
make changes to the setup process.

.. seealso::

   All-in-one GitHub CI testing inherits from this environment and is described
   :ref:`here <testing-ci-aio>`.

Prerequisites
=============

* a Rocky Linux 9/10 or Ubuntu Noble 24.04 host
* Credentials for the StackHPC release pulp: ``ark.stackhpc.com``

Automated Setup
===============

Access the host via SSH. You may wish to start a ``tmux`` session.

Download the setup script:

.. parsed-literal::

   curl -LO https://raw.githubusercontent.com/stackhpc/stackhpc-kayobe-config/stackhpc/2025.1/etc/kayobe/environments/aio/automated-setup.sh

Change the permissions on the script:

.. parsed-literal::

   sudo chmod +x automated-setup.sh

Create two files, ``~/release_pulp_username``, and ``~/release_pulp_password``,
and add your credentials in plaintext to each of these files.

.. note::

    By default, the ``stackhpc`` container namespace will be used. This is the
    namespace for all released content. To use unreleased content, edit the
    ``automated-setup.sh`` script and set  ``KAYOBE_CONFIG_EDIT_PAUSE`` to
    ``true``. Then, when the script pauses, change ``kolla_docker_namespace``
    to ``stackhpc-dev`` in ``release-train.yml``. This requires special
    credentials that are authorised for the dev namespace.

Run the setup script:

.. parsed-literal::

   ./automated-setup.sh deploy_full

The script will pull the current version of Kayobe and this repository, and
then run the manual setup steps below. The script can be easily edited with the
following options:

* ``BASE_PATH`` (default: ``~``) - Directory to deploy from. The directory must
  exist before running the script.
* ``KAYOBE_BRANCH`` (default: ``stackhpc/2025.1``) - The branch of Kayobe
  source code to use.
* ``KAYOBE_CONFIG_BRANCH`` (default: ``stackhpc/2025.1``) - The branch of
  ``stackhpc-kayobe-config`` to use.
* ``KAYOBE_AIO_LVM`` (default: ``true``) - Whether the image uses LVM.
* ``KAYOBE_CONFIG_EDIT_PAUSE`` (default: ``false``) - Option to pause
  deployment after cloning the kayobe-config branch, so the environment can be
  customised before continuing.
* ``AIO_RUN_TEMPEST`` (default: ``false``) - Whether to run Tempest Refstack
  after deployment instead of the default VM smoke test.
* ``USE_OVS`` (default: ``false``) - Whether to disable OVN and deploy using
  OVS instead.

Ironic
======

.. note::

   These instructions have not been validated for some time. Proceed with
   caution.

For a control plane with Ironic enabled, a "bare metal" instance can be
deployed after the main deployment has finished. We can use the Tenks project
to create fake bare metal nodes.

Clone the tenks repository:

.. parsed-literal::

   cd ~/src/kayobe
   git clone https://opendev.org/openstack/tenks.git

Optionally, edit the Tenks configuration file,
``~/src/kayobe/dev/tenks-deploy-config-compute.yml``.

Run the ``dev/tenks-deploy-compute.sh`` script to deploy Tenks:

.. parsed-literal::

   cd ~/src/kayobe
   export KAYOBE_CONFIG_SOURCE_PATH=~/src/kayobe-config
   export KAYOBE_VENV_PATH=~/venvs/kayobe
   ./dev/tenks-deploy-compute.sh ./tenks/

Check that Tenks has created VMs called tk0 and tk1:

.. parsed-literal::

   sudo virsh list --all

Verify that VirtualBMC is running:

.. parsed-literal::

   ~/tenks-venv/bin/vbmc list

We are now ready to run the ``dev/overcloud-test-baremetal.sh`` script. This
will run the ``init-runonce`` setup script provided by Kolla Ansible that
registers images, networks, flavors etc. It will then deploy a bare metal
server instance, and delete it once it becomes active:

.. parsed-literal::

   ./dev/overcloud-test-baremetal.sh

The machines and networking created by Tenks can be cleaned up via
``dev/tenks-teardown-compute.sh``:

.. parsed-literal::

   ./dev/tenks-teardown-compute.sh ./tenks
