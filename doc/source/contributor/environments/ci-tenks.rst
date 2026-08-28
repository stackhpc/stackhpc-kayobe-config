==========
ci-tenks
==========

The ``ci-tenks`` Kayobe environment is used to test seed services.
It is currently a work in progress.

The environment is deployed using `automated-deployment.sh`. It bootstraps
localhost as a hypervisor for a seed and one controller instance. The seed
provisions the controller with Bifrost.

It currently tests:

* Seed hypervisor host configuration
* Seed VM provisioning
* Seed host configuration
* Pulp deployment
* Pulp container syncing (one container - Bifrost)
* Bifrost overcloud provisioning

In the future it could test:

* Pulp package syncing
* Overcloud host configuration, pulling packages from a local Pulp
* Upgrades (Host OS and OpenStack)
* Multi-node OpenStack deployments

   * Multiple controllers
   * Multiple compute nodes (and live migration)
   * Multiple storage nodes (Ceph)

These extensions depend on more SMS hypervisor capacity and improved sync times
for the local Pulp instance.

Prerequisites
=============

* A Rocky Linux 9, Rocky Linux 10, or Ubuntu Noble 24.04 host
* 16GB of memory
* 4 cores
* No LVM

Setup
=====

The environment is designed to run in CI, however can also be deployed
manually.

Access the host via SSH. You may wish to start a ``tmux`` session.

Download the setup script:

.. parsed-literal::

   curl -LO https://raw.githubusercontent.com/stackhpc/stackhpc-kayobe-config/stackhpc/2025.1/etc/kayobe/environments/ci-tenks/automated-deployment.sh

Change the permissions on the script:

.. parsed-literal::

   sudo chmod +x automated-deployment.sh

Acquire the Ansible Vault password for this repository, and store a
copy at ``~/vault-pw``.

.. note::

   The vault password is currently the same as for the ``ci-aio``
   environment.

Run the setup script:

.. parsed-literal::

   ./automated-deployment.sh
