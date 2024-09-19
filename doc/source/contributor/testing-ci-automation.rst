========================
Testing, CI & Automation
========================

CI hosting clouds
=================

Several GitHub Actions workflows run on public runners, but some require
private runners. For these, we use a CI hosting cloud.

Leafcloud
---------

`Leafcloud <https://www.leaf.cloud/>`_ is currently the only supported cloud
for hosting CI workloads.

Workloads run in the ``stackhpc-ci`` project, and CI workflows authenticate
using a ci+skc@stackhpc.com user account. This is an alias for the
`ci@stackhpc.com Google group
<https://groups.google.com/a/stackhpc.com/g/ci>`_, which may be subscribed to
by multiple StackHPC Engineers. Credentials for this account should be shared
amongst a few StackHPC Engineers.

An autoscaling `Actions Runner Controller (ARC)
<https://stackhpc.github.io/stackhpc-release-train/operations/github/#github-actions-runner-controller-arc>`_
cluster also lives in the ``stackhpc-ci`` project, and runs several jobs that
require access to the cloud or benefit from data-locality with Ark.

SMS Lab
-------

SMS lab will soon be added as a supported CI hosting cloud.  Several
considerations must be made when porting CI to Leafcloud.

Many of our CI and other workflows require access to large volumes of data
stored in Ark. This includes package repositories, container images, disk
images, etc. Naively accessing this data from SMS lab will result in high
Internet usage and slow jobs. The previous incarnation of SMS lab hosted a
"Test Pulp" instance that acted as a local mirror of package repositories and
container images. This worked, but required explicit syncing with Ark when
content is updated, and was a bit brittle.

For SMS lab 2.0, we propose a different approach. Package repository data is
smaller than container images, but we might still benefit from the use of a
Squid caching proxy. For container images we will use a `Docker registry mirror
<https://docs.docker.com/docker-hub/mirror/>`_ as a pull-through cache.

Container and host image build jobs require significant data uploads, and may
still need to run on Leafcloud to avoid long delays while transferring data to
Ark.

CI for pull requests (PRs)
==========================

Continuous Integration (CI) is used within StackHPC Kayobe Configuration to
perform various tests against pull requests. The top-level workflow is in
``.github/workflows/stackhpc-pull-request.yml``. It includes the following
jobs:

``check-changes``
  Determines which other jobs need to run, based on files that are changed in
  the PR. The ``.github/path-filters.yml`` file contains the paths.
``Tox pep8 with Python 3.10``
  Runs the Tox ``pep8`` environment.
``Tox releasenotes with Python 3.10``
  Builds the release notes using the Tox ``releasenotes`` environment. The
  separate release notes are not really used - rather they are integrated into
  the main documentation.
``Tox docs with Python 3.10``
  Builds the documentation using the Tox ``docs`` environment.
``Build Kayobe Image``
  Builds a Kayobe container image for the pull request and pushes it to GHCR.
  Uses the ``.github/workflows/stackhpc-build-kayobe-image.yml`` reusable
  workflow.
``Check container image tags``
  Checks that:

  - the image to container mapping in ``tools/kolla-images.py`` matches Kolla
    Ansible.
  - the container tag hierarchy in ``tools/kolla-images.py`` matches Kolla
    Ansible.
  - the container image tags defined in ``etc/kayobe/kolla-image-tags.yml`` are
    present in the ``stackhpc-dev`` namespace in Ark.

  Uses the ``.github/workflows/stackhpc-check-tags.yml`` reusable workflow,
  which runs the ``etc/kayobe/ansible/check-tags.yml`` and
  ``etc/kayobe/ansible/check-kolla-images-py.yml`` playbooks.
``aio [upgrade] (<OS> <neutron plugin>)``
  Runs an all-in-one OpenStack deployment test.
  Various jobs are run using different parameters.
  Uses the ``.github/workflows/stackhpc-all-in-one.yml`` reusable workflow.
  See :ref:`below <testing-ci-aio>` for further details.

.. _testing-ci-aio:

All in one testing
------------------

The ``.github/workflows/stackhpc-all-in-one.yml`` reusable workflow accepts
various parameters, and the following are used to create a test matrix for PRs:

  - Operating System (Rocky 9, Ubuntu Jammy)
  - Neutron plugin (OVS, OVN)
  - Upgrade or no upgrade

The workflow runs on an autoscaling `Actions Runner Controller (ARC)
<https://stackhpc.github.io/stackhpc-release-train/operations/github/#github-actions-runner-controller-arc>`_
cluster, and the GitHub runner acts as both a Terraform client and an Ansible
control host. Kayobe is executed using kayobe-automation within another
container, using the Kayobe container image built in the ``Build Kayobe Image``
job.

The workflow performs the following high-level steps:

#. Deploy a VM on an OpenStack cloud using the `aio
   <https://github.com/stackhpc/stackhpc-kayobe-config/tree/stackhpc/2023.1/terraform/aio>`_
   Terraform configuration.
#. Deploy OpenStack in the VM using Kayobe and the :doc:`ci-aio
   <environments/ci-aio>` environment. If this is an upgrade job, the previous
   OpenStack release is deployed.
#. Register test resources in the cloud under test (images, flavors, networks,
   subnets, routers, etc.).
#. If this is an upgrade job, upgrade the cloud under test to the target
   release.
#. Run Tempest and `StackHPC OpenStack Tests
   <https://github.com/stackhpc/stackhpc-openstack-tests>`_ to test the cloud.
#. Collect diagnostic information.
#. Upload results as an artifact.
#. Destroy the VM using Terraform.

In order to create VMs on the cloud hosting the CI, we need a few things:

- an OpenStack project with sufficient quota to run CI jobs for several PRs
  concurrently
- an OpenStack user account
- a ``clouds.yaml`` file
- an application credential to authenticate with the cloud
- a flavor for the VM (minimum 8GiB RAM)
- a set of images for the VM
- a network and subnet for the VM
- SSH connectivity from the GitHub runner to the VM
- access from the VM to the Internet

This information is provided to GitHub Actions using `secrets
<https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions>`_
and `variables
<https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/store-information-in-variables>`_.
`GitHub environments
<https://docs.github.com/actions/deployment/targeting-different-environments/using-environments-for-deployment>`_
are used to allow running jobs on different clouds.

``KAYOBE_VAULT_PASSWORD`` is a repository-scoped GitHub secret containing the
Ansible Vault password for the ``ci-aio`` Kayobe environment.

The following GitHub secrets are defined in each GitHub environment:

- ``CLOUDS_YAML``
- ``OS_APPLICATION_CREDENTIAL_ID``
- ``OS_APPLICATION_CREDENTIAL_SECRET``

The following GitHub variables are defined in each GitHub environment:

- ``AIO_FLAVOR``
- ``AIO_NETWORK``
- ``AIO_SUBNET``
- ``OS_CLOUD``

Glance images for all-in-one VMs are not configured using GitHub variables.
Instead we use the overcloud host images that are built and uploaded to Ark.
These are also uploaded to clouds running CI, with well-known names using the
versions defined in ``etc/kayobe/pulp-host-image-versions.yml``.

.. _ci-promotion:

Promotion
=========

The ``.github/workflows/stackhpc-promote.yml`` workflow runs on a push to any
release branch of StackHPC Kayobe Configuration. It triggers other workflows in
StackHPC Release Train to promote the `package repositories
<https://stackhpc.github.io/stackhpc-release-train/usage/content-workflows/#promoting-package-repositories>`_
and `container images
<https://stackhpc.github.io/stackhpc-release-train/usage/content-workflows/#promoting-container-images-zed-release-onwards>`_
referenced in the configuration.

The standard GitHub API token available in the workflow (``GITHUB_TOKEN``) is
not allowed to trigger a workflow in another repository. To do this, we use a
`fine-grained PAT token
<https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens>`_
owned by the ``stackhpc-ci`` GitHub user. This token has read/write permissions
on actions for the ``stackhpc/stackhpc-release-train`` repository. The token is
stored as the ``STACKHPC_RELEASE_TRAIN_TOKEN`` GitHub secret in the StackHPC
Kayobe Configuration repository. The token expires periodically and must be
regenerated, after which the secret must be updated.

Tag and release
===============

The ``.github/workflows/tag-and-release.yml`` workflow runs on a push to any
release branch of StackHPC Kayobe Configuration. It generates a Git tag and
an accompanying GitHub release. See also the `Release Train documentation
<https://stackhpc.github.io/stackhpc-release-train/usage/source-code-ci/#tag-release>`__.

CI cleanup
==========

The ``.github/workflows/stackhpc-ci-cleanup.yml`` workflow runs periodically
(currently every 2 hours). It checks for all-in-one CI VMs older than 3 hours
and deletes them, to avoid excess cloud resource consumption.

.. _testing-container-images:

Container images
================

The ``.github/workflows/stackhpc-container-image-build.yml`` workflow runs on
demand, and is used to build Kolla container images. The process for building
images and updating the configuration to use them is described in the `Release
Train documentation
<https://stackhpc.github.io/stackhpc-release-train/usage/content-howto/#update-kolla-container-images>`__.

The workflow runs as a matrix, with a job for each supported container OS
distribution.  The workflow runs on an autoscaling `Actions Runner Controller
(ARC)
<https://stackhpc.github.io/stackhpc-release-train/operations/github/#github-actions-runner-controller-arc>`_
cluster, and the GitHub runner acts as both the Ansible control host and
container image build host.

A Pulp authentication proxy container is deployed on the runner that provides
unauthenticated access to the package repositories in Ark. This avoids leaking
Ark credentials into the built container images.

Once built, images are scanned for vulnerabilities using `Trivy
<https://trivy.dev/>`_. Any critical vulnerabilities will break the build,
unless the ``push-dirty`` input is true.

If the ``push`` input is true, images are pushed to Ark, and a `container sync
<https://stackhpc.github.io/stackhpc-release-train/usage/content-workflows/#syncing-container-images>`_
workflow is triggered in the StackHPC Release Train repository. See
:ref:`here <ci-promotion>` for information on triggering workflows in another repository.

An artifact containing image build logs is uploaded on completion.

.. _testing-host-images:

Overcloud host images
=====================

The ``.github/workflows/overcloud-host-image-build.yml`` workflow runs on
demand, and is used to build overcloud host images.

The workflow runs as a single job, building each supported container OS
distribution sequentially.  The workflow runs on an autoscaling `Actions Runner
Controller (ARC)
<https://stackhpc.github.io/stackhpc-release-train/operations/github/#github-actions-runner-controller-arc>`_
cluster, and the GitHub runner acts as both a Terraform client and an Ansible
control host. Similarly to the all-in-one CI testing, Terraform is used to
create a VM on a cloud that is then used for building images.

The following steps are taken for each supported image:

#. Build an image using Kayobe
#. Upload the image to Ark
#. Upload the image to clouds hosting CI

At the end of the job, build logs are uploaded as an artifact and the VM is
destroyed.

In order to create a VM on the cloud hosting the CI, we need a few things:

- an OpenStack project with sufficient quota to run at least one build VM
- an OpenStack user account
- a ``clouds.yaml`` file
- an application credential to authenticate with the cloud
- a flavor for the VM (minimum 8GiB RAM)
- a Rocky Linux 9 image for the VM
- a network and subnet for the VM
- SSH connectivity from the GitHub runner to the VM
- access from the VM to the Internet

This information is provided to GitHub Actions using `secrets
<https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions>`_
and `variables
<https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/store-information-in-variables>`_.
`GitHub environments
<https://docs.github.com/actions/deployment/targeting-different-environments/using-environments-for-deployment>`_
are used to allow running jobs on different clouds.

``KAYOBE_VAULT_PASSWORD`` is a repository-scoped GitHub secret containing the
Ansible Vault password for the ``ci-builder`` Kayobe environment.

The following GitHub secrets are defined in each GitHub environment:

- ``CLOUDS_YAML``
- ``OS_APPLICATION_CREDENTIAL_ID``
- ``OS_APPLICATION_CREDENTIAL_SECRET``

The following GitHub variables are defined in each GitHub environment:

- ``HOST_IMAGE_BUILD_FLAVOR``
- ``HOST_IMAGE_BUILD_IMAGE``
- ``HOST_IMAGE_BUILD_NETWORK``
- ``HOST_IMAGE_BUILD_SUBNET``
- ``OS_CLOUD``

The ``.github/workflows/overcloud-host-image-promote.yml`` workflow runs on
demand and is used to promote overcloud host images. Unlike package
repositories and container images, host image promotion is still an manual
step.

The ``.github/workflows/overcloud-host-image-upload.yml`` workflow runs on
demand and is used to upload images to clouds hosting CI. It is mainly used
when this step failed in a previous host image build job.

.. _testing-multinode:

Multinode test clusters
=======================

The ``.github/workflows/stackhpc-multinode.yml`` workflow runs on demand and is
used to create a multinode test cluster. The
``.github/workflows/stackhpc-multinode-periodic.yml`` workflow runs
periodically (currently nightly) and runs a random test configuration
(generated by ``.github/workflows/multinode-inputs.py``).

Both workflows use a `reusable workflow
<https://github.com/stackhpc/stackhpc-openstack-gh-workflows/blob/main/.github/workflows/multinode.yml>`_
in the StackHPC OpenStack GitHub Workflows repository. Note that since this
workflow is in a different repository and we reference it with a tag, changes
to the reusable workflow are not picked up until the tag is bumped.

The workflow runs on an autoscaling `Actions Runner Controller (ARC)
<https://stackhpc.github.io/stackhpc-release-train/operations/github/#github-actions-runner-controller-arc>`_
cluster, and the GitHub runner acts as a Terraform client.  Kayobe is executed
on another VM that acts as the Ansible control host.

The workflow performs the following high-level steps:

#. Deploy a set of VMs on an OpenStack cloud using the `Terraform Kayobe
   Multinode <https://github.com/stackhpc/terraform-kayobe-multinode/>`_
   Terraform configuration.
#. Configure one of the VMs as an Ansible control host for Kayobe.
#. Deploy OpenStack in the other VMs using Kayobe and the :doc:`ci-multinode
   <environments/ci-multinode>` environment. If this is an upgrade job, the
   previous OpenStack release is deployed.
#. Register test resources in the cloud under test (images, flavors, networks,
   subnets, routers, etc.).
#. Run Tempest and `StackHPC OpenStack Tests
   <https://github.com/stackhpc/stackhpc-openstack-tests>`__ to test the cloud.
#. If this is an upgrade job, upgrade the cloud under test to the target
   release.
#. Run Tempest and `StackHPC OpenStack Tests
   <https://github.com/stackhpc/stackhpc-openstack-tests>`__ to test the cloud.
#. Collect diagnostic information.
#. Upload results as an artifact.
#. Destroy the VMs using Terraform.
#. For nightly jobs, send a Slack alert to ``#release-train-alerts`` on
   failure.

In order to create VMs on the cloud hosting the CI, we need a few things:

- an OpenStack project with sufficient quota to create several clusters
  concurrently
- an OpenStack user account
- a ``clouds.yaml`` file
- an application credential to authenticate with the cloud
- flavors for each type of VM
- a set of images for the VMs
- a network and subnet for the VMs
- a floating IP pool or external network for the Ansible control host (optional)
- SSH connectivity from the GitHub runner to the Ansible control host VM
- access from the VMs to the Internet

This information is provided to GitHub Actions using `secrets
<https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions>`_
and `variables
<https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/store-information-in-variables>`_.
`GitHub environments
<https://docs.github.com/actions/deployment/targeting-different-environments/using-environments-for-deployment>`_
are used to allow running jobs on different clouds.

``KAYOBE_VAULT_PASSWORD_CI_MULTINODE`` is a repository-scoped GitHub secret
containing the Ansible Vault password for the ``ci-multinode`` Kayobe
environment.

The following GitHub secrets are defined in each GitHub environment:

- ``CLOUDS_YAML``
- ``OS_APPLICATION_CREDENTIAL_ID``
- ``OS_APPLICATION_CREDENTIAL_SECRET``

The following GitHub variables are defined in each GitHub environment:

- ``MULTINODE_ANSIBLE_CONTROL_VM_FLAVOR``
- ``MULTINODE_FIP_POOL``
- ``MULTINODE_FLAVOR``
- ``MULTINODE_INFRA_VM_FLAVOR``
- ``MULTINODE_NETWORK``
- ``MULTINODE_SEED_VM_FLAVOR``
- ``MULTINODE_STORAGE_FLAVOR``
- ``MULTINODE_SUBNET``
- ``OS_CLOUD``

Glance images for multinode VMs are not configured using GitHub variables.
Instead we use the overcloud host images that are built and uploaded to Ark.
These are also uploaded to clouds running CI, with well-known names using the
versions defined in ``etc/kayobe/pulp-host-image-versions.yml``.

For multinode clusters created on demand, it is possible to pause the workflow
execution on certain conditions and gain access to the cluster for a limited
period of time. This can be used to interact with the system to investigate
faults, debug, etc. To do this, use the ``break_on`` and ``break_duration``
workflow inputs.

Slack alerts
============

Slack alerts are sent when certain automatically-triggered workflows fail.  See
the `Release Train documentation
<https://stackhpc.github.io/stackhpc-release-train/usage/notifications/>`__ for
more details.
