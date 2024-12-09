.. _ipa:

=========================
Ironic Python Agent (IPA)
=========================

Release Train IPA
=================

StackHPC provides built Ironic Python Agent (IPA) images in Release Train
through Ark.

These images are built in a CI using a Kayobe workflow :kayobe-doc:
`Kayobe documentation <configuration/reference/ironic-python-agent.html>`
and are configured in this repository.

Release Train IPA is used by Bifrost and Overcloud Ironic by default in
StackHPC Kayobe Configuration, and is pulled in to Inspector when running
``kayobe seed service deploy`` for Bifrost or ``kayobe overcloud post configure``
for Ironic. This behaviour can be disabled in `stackhpc-ipa-images.yml`:

.. code-block:: yaml

    stackhpc_ipa_image_bifrost_enabled: false
    stackhpc_ipa_image_overcloud_enabled: false

You can also override the distribution version pulled in during deployment,
to do this you can change ``stackhpc_ipa_image_version`` to be the opposite
distribution. For example, the case of switching to Ubuntu 22.04 on a Rocky 9
cloud:

.. code-block:: yaml

    stackhpc_ipa_image_version: "{{ stackhpc_ubuntu_jammy_ipa_image_version }}"
