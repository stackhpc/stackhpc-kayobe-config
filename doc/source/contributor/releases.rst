===========================
StackHPC OpenStack Releases
===========================

StackHPC Kayobe Configuration provides tagged releases to ensure stability and consistency
in deployments. These releases are created by following the workflow below and are processed
by SKC release managers. Currently, this workflow only supports ``stackhpc/2026.1`` (Gazpacho).

The specification for StackHPC OpenStack releases is defined in the ``stackhpc-specs`` repository.
https://github.com/stackhpc/stackhpc-specs/blob/main/release-train/skc-regular-releases.rst

Release cadence
===============

StackHPC OpenStack will have a new release at least every 3 months. Release candidates may
be branched up to 3 weeks before release to ensure sufficient testing. Essential bug and security
fixes may be backported to stable if required.

Release candidate
=================

``stackhpc-rc/<current_release>`` is the release candidate branch. This branch is deleted following
a stable release merge. To branch a release candidate; run the ``stackhpc-release.yml`` CI workflow.
This will create a merge request targeting ``stackhpc-dev/<current_release>`` into
``stackhpc-rc/<current_release>``.

Release Train
-------------

After a release candidate is branched, Relase Train needs to be prepared for the upcoming release.
Currently, toil work for preparing Release Train (Syncing new packages, building host/container/etc images)
is manual. This will be replaced with a CI workflow in the future.

Syncing package repositories
^^^^^^^^^^^^^^^^^^^^^^^^^^^^

In the ``stackhpc-release-train`` repository; run a full package sync (``package-sync.yml``) with Ark.
Following package repos being synced, run the promotion workflow to make the packages avaible from Ark
(``package-promote.yml``). To get an updated package repository versions for SKC run ``package-update.yml``,
then commit this to the development branch.

More information on Release Train workflows is available in the ``stackhpc-release-train`` repository:
https://github.com/stackhpc/stackhpc-release-train/blob/main/docs/usage/content-workflows.md#syncing-package-repositories

DOCA
^^^^

It's likely that with the latest package sync, a newer kernel version will be available. To ensure
DOCA compatibility with the available kernel version, run the ``package-build-ofed.yml`` workflow.
Commit the new DOCA releases to development in ``pulp-repo-versions.yml``.

IPA
^^^

To build new IPA images from the latest package sync; run the ``ipa-image-build.yml`` and
``ipa-image-promote.yml`` workflows. Commit the new IPA release to development in ``pulp-ipa-image-versions.yml``.

Amphora
^^^^^^^

To build new Amphora images from the latest package sync; run the ``amphora-image-build.yml`` and
``amphora-image-promote.yml`` workflows. Commit the new IPA release to the development branch in
``stackhpc.yml`` as ``stackhpc_amphora_image_version``.

Host images
^^^^^^^^^^^

To build new host images from the latest package sync; run the ``overcloud-host-image-build.yml`` and
``overcloud-host-image-promote.yml`` workflows. Commit the new host image releases to the development branch in
``pulp-host-image-versions.yml``.

Container images
^^^^^^^^^^^^^^^^

A full Kolla container image rebuild is required for a new release. (Note: Ensure hotfix or backport images
in ``kolla-image-tags.yml`` aren't overwritten unless the patched image is either not needed or is available
in upstream or downstream ``stackhpc/<current_release>`` fork sources).

Run a full ``stackhpc-container-image-build.yml`` workflow to ensure new images are built. New images shouldn't
be promoted until multinode testing is completed and the release candidate is merged.

Multinode testing
-----------------

Multinode testing should be completed before a release candidate is merged. To begin a multinode
test; run the ``stackhpc-multinode.yml`` workflow with default options. More extensive multinode
testing should be done following release candiate merge including: Ubuntu testing; ML2/OVS testing;
upgrades etc.

Stable release
==============

Following sufficient testing of a release candidate (usually 2-3 weeks) a stable release can be made.
Run the ``stackhpc-release.yml`` workflow to create a merge request of RC ``stackhpc-rc/current_release>``
targeting stable ``stackhpc/<current_release>``.

Ensure all CI passes and a release manager reviews before merging. It's encouraged to repeat a basic multinode
test to ensure testing consistency before merging. Once merged, the ``stackhpc-rc/<current_release>`` branch
can be deleted.

Currently releases are created manually following a merge. A release manager should use the GitHub
release tool to create a new tagged release, and the automatic release notes tool to populate the
release notes with a changelog.
