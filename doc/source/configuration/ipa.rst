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

You can also override the distribution version pulled in during deployment,
to do this you can change ``stackhpc_ipa_image_version`` to be the opposite
distribution. For example, the case of switching to Ubuntu 22.04 on a Rocky 9
cloud:

.. code-block:: yaml

    stackhpc_ipa_image_version: "{{ stackhpc_ubuntu_jammy_ipa_image_version }}"
