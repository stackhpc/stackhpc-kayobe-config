.. _ipa:

=========================
Ironic Python Agent (IPA)
=========================

Release Train IPA
=================

StackHPC provides prebuilt Ironic Python Agent (IPA) images in Release Train
through Ark.

These images are built in CI using a GitHub workflow and are configured in this
repository. See :kayobe-doc:`Kayobe documentation
<configuration/reference/ironic-python-agent.html>` for more details on IPA.

Release Train IPA images are used by Bifrost and Overcloud Ironic by default in
the StackHPC Kayobe Configuration, and are pulled in to the Ironic Inspector
when running ``kayobe seed service deploy`` for Bifrost or ``kayobe overcloud
post configure`` for Overcloud Ironic. This behaviour can be disabled in
`stackhpc-ipa-images.yml`:

.. code-block:: yaml

    stackhpc_ipa_image_bifrost_enabled: false
    stackhpc_ipa_image_overcloud_enabled: false

You can also select the architecture of the IPA images pulled in during
deployment:

.. code-block:: yaml

    stackhpc_ipa_arch: aarch64

The supported values are ``amd64`` and ``aarch64``. Rocky Linux 9 uses
``stackhpc_rocky_9_ipa_image_version`` for ``amd64`` and
``stackhpc_rocky_9_ipa_image_version_aarch64`` for ``aarch64``, similarly
Rocky Linux 10 uses ``stackhpc_rocky_10_ipa_image_version`` for ``amd64`` and
``stackhpc_rocky_10_ipa_image_version_aarch64`` for ``aarch64``.

You can also override the distribution version pulled in during deployment. For
example, the case of switching to Ubuntu 24.04 on a Rocky 9 cloud:

.. code-block:: yaml

    stackhpc_ipa_image_version: "{{ stackhpc_ubuntu_noble_ipa_image_version }}"
