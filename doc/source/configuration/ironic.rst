======
Ironic
======

Cleaning
========

Storage
-------

Hardware assisted secure erase, i.e the ``erase_devices`` clean step, is
enabled by default. This is normally dependent on the `Hardware Manager
<https://docs.openstack.org/ironic-python-agent/latest/contributor/hardware_managers.html>`__
in use. For example, when using the GenericHardwareManager the priority would
be 10, whereas if using the `ProliantHardwareManager
<https://docs.openstack.org/ironic/latest/admin/drivers/ilo.html#disk-erase-support>`__
it would be 0. The idea is that we will prevent the catastrophic case where
data could be leaked to another tenant; forcing you to have to explicitly relax
this setting if this is a risk you want to take. This can be customised by
editing the following variables:

.. code-block::
    :caption: $KAYOBE_CONFIG_PATH/kolla/config/ironic/ironic-conductor.conf

    [deploy]
    erase_devices_priority=10
    erase_devices_metadata_priority=0

See `Ironic documentation
<https://docs.openstack.org/ironic/latest/admin/cleaning.html>`__ for more
details.
