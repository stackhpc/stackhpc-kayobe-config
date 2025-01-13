====
OFED
====

Warning: Experimental workflow subject to change

This section documents the workflow for building OFED packages for Release train integration.

The workflow builds the OFED kernel modules against the latest available kernel in Release train
(as configured in SKC) and compiles them into RPM packages to be uploaded to Ark. Addtionally,
this workflow downloads the userspace OFED packages from the Nvidia repository and uploads these
to Ark.

Workflow
========

The workflow uses workflow_dispatch to manually request an OFED build, which will deploy a builder
VM, apply kayobe config to the builder, upgrade the kernel, reboot, then run two Ansible playbooks
for building and uploading OFED to Ark.

Pre-requisites
--------------

Before building OFED packages, the workflow will ensure that:

* A full distro-sync has taken place, ensuring the kernel is upgraded.

* The bootloader has been configured to use the latest kernel

* noexec is disabled in the temporary logical volume.

build-ofed
----------

Currently we only support building Rocky Linux 9 OFED packages.

In order to setup OFED, we're required to build kernel modules for the OFED drivers as
the kernels we provide in release train are unsupported by OFED. To accomplish this we
will need to use the doca-kernel-support from the doca-extra repository.

We will need to instll dependencies in order to build the OFED kernel modules, and these
are installed at the beginning of the build playbook. We also install base and appstream
dependencies of userspace OFED packages here, this is intended to stop these dependencies
being pulled in later when we download the OFED packages from the doca-host repository.

At the end of the playbook following the kernel module build, the OFED userspace packages
are downloaded from the upstream repository in order to upload these to Ark.

push-ofed
---------

As we're not syncing OFED from any upstream source, and are instead creating our own
repository of custom packages, we will be required to setup the Pulp distribution/publication
and upload the content directly to Ark. This playbook uses the Pulp CLI to upload the RPMs
to Ark.
