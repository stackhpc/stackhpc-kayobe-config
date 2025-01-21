====
OFED
====

Warning: Experimental workflow subject to change

The Nvidia DOCA framework is distributed as part of StackHPC Release Train for OFED driver support,
this repository is synced into Ark as part of the Release Train worfkflows, however to ensure 
compatibility with Release Train packages, we are required to build OFED modules with support for
the latest Release Train kernel.

Workflow
========

The workflow uses workflow_dispatch to manually request an OFED build, which will deploy a builder
VM, apply kayobe config to the builder, upgrade the kernel, reboot, then run two Ansible playbooks
for building and uploading OFED modules to Ark.

Pre-requisites
--------------

Before building OFED packages, the workflow will ensure that:

* A full distro-sync has taken place, ensuring the kernel is upgraded.

* The bootloader has been configured to use the latest kernel (reset-bls-entries.yml)

* noexec is disabled in the temporary logical volume.

build-ofed
----------

Currently we only support building Rocky Linux 9 OFED kerenl module packages.

The Build OFED module workflow will check that the filesystem is configured (noexec disabled)
to allow the DOCA build script to run. The workflow will also install any necessary dependencies
for the module build.

The build script will output a ``doca-kernel-repo`` RPM which contains all kernel modules built
as part of the workflow. When this RPM is installed, the repofile is created pointing to the
modules in `/usr/share/doca-host-<doca-version>/Modules/<kernel-version>/` on the host.

push-ofed
---------

As mentioned above, the DOCA repository is synced into the `doca` repository in Ark. This workflow
will upload the ``doca-kernel-repo`` RPM to a seperate repository named `doca-modules`. The version
for this repository is set in `pulp-repo-versions.yml` and is disabled for local pulp syncs by
default.

Install process
===============

Pre-requisites
--------------

* Ensure the OFED hosts are upgraded with the latest packages in the point release.

* The bootloader has been configured to use the latest kernel (reset-bls-entries.yml)

install-doca
------------

A playbook is provided to install DOCA on hosts in the `mlnx` group. Ensure this group
is configured to include the hosts you wish to install DOCA on. To run the install
playbook:

.. code-block:: console

    kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/install-doca.yml
