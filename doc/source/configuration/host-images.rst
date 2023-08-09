.. _host-images:

===========
Host Images
===========

Pulling host images
===================

StackHPC provides pre-built overcloud host images through Ark, which can be
consumed using the configuration provided by this repository.

When configured, an image will be downloaded to the seed during the
``kayobe seed service deploy`` step, and subsequently deployed using bifrost
with ``kayobe overcloud provision``.

To use these images, set ``stackhpc_download_overcloud_host_images`` to true
in ``etc/kayobe/stackhpc-overcloud-host-images.yml``.

Currently, images exist for the following operating systems:

* CentOS 8 Stream
* Rocky Linux 8
* Rocky Linux 9
* Ubuntu Focal 20.04
* Ubuntu Jammy 22.04

The image to download is selected automatically using the ``os_distribution``
and ``os_release`` variables. These images are versioned and a variable for
each OS is stored in ``pulp-host-image-versions.yml``.

This content requires the same set of credentials as is used for other
release train content.

The Ark pulp credentials issued by StackHPC should be configured in
``etc/kayobe/pulp.yml``, using Ansible Vault to encrypt the password:

.. code-block:: yaml

   stackhpc_release_pulp_username: <username>
   stackhpc_release_pulp_password: <password>

Building host images
====================

StackHPC Kayobe configuration provides configuration for some standard
overcloud host images, built using the :kayobe-doc:`overcloud DIB
<configuration/reference/overcloud-dib.html>` functionality of Kayobe.

The overcloud DIB configuration is provided in
``etc/kayobe/stackhpc-overcloud-dib.yml``. It is not used by default, and must
be actively opted into. This can be done as follows:

.. code-block:: yaml
   :caption: ``etc/kayobe/overcloud-dib.yml``

   overcloud_dib_build_host_images: true

   overcloud_dib_host_images:
     - "{{ stackhpc_overcloud_dib_host_image }}"

The image name is configured via ``stackhpc_overcloud_dib_name``, and is
``deployment_image`` by default.

The list of DIB elements is configured via ``stackhpc_overcloud_dib_elements``.
The default value depends on the ``os_distribution`` variable. See the YAML
file for details.

The DIB environment variables are configured via
``stackhpc_overcloud_dib_env_vars``. See the YAML file for details.

A list of packages to install is configured via
``stackhpc_overcloud_dib_packages``.

By default, a UEFI-compatible image is built that uses separate LVM volumes for
different mount points. This is done to pass Centre for Internet Security (CIS)
partition benchmarks. The block device YAML configuration is configured via
``stackhpc_overcloud_dib_block_device_config_uefi_lvm``.

The 3 partitions are:

* p0: EFI ESP bootloader
* p1: EFI BSP
* p2: LVM PV (``rootpv``)

The LVM Logical Volumes are:

============== ================== =========
LV             Mount point        Size (GB)
============== ================== =========
``lv_root``    ``/``              5G
``lv_tmp``     ``/tmp``           1G
``lv_var``     ``/var``           1G
``lv_var_tmp`` ``/var/tmp``       1G
``lv_log``     ``/var/log``       1G
``lv_audit``   ``/var/log/audit`` 128M
``lv_home``    ``/home``          128M
============== ================== =========

A compatible LVM configuration is provided, and covered in :ref:`lvm`.
The Logical Volumes in the image are defined with small sizes, with the
intention that they will be grown after provisioning.

For RedHat family distributions, Dracut modules are configured via
``stackhpc_overcloud_dib_dracut_enabled_modules_default_config``.
