====
Swap
====

Support for :kayobe-doc:`managing swap files and devices
<configuration/reference/hosts.html#swap>` was added to Kayobe in the Zed
release. The custom playbook described below is retained for backwards
compatibility but may be removed in a future release.

StackHPC Kayobe configuration provides a ``swap.yml`` custom playbook that may
be used to configure a swap device.

The following variables may be used to configure the playbook:

``swap_group``
  Host pattern against which to target the playbook. Default is ``overcloud``.
``swap_device``
  Name of the swap device to configure. Default is ``/dev/rootvg/lv_swap`` to
  match the standard :ref:`host image configuration <host-images>`.

This playbook may be used as a host configure post hook, e.g. for overcloud
hosts:

.. code-block:: console

   mkdir -p ${KAYOBE_CONFIG_PATH}/hooks/overcloud-host-configure/post.d
   cd ${KAYOBE_CONFIG_PATH}/hooks/overcloud-host-configure/post.d
   ln -s ../../../ansible/swap.yml 10-swap.yml
