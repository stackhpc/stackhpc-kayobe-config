.. _stackhpc-mixin-environments:

===========================
StackHPC Mixin Environments
===========================

The StackHPC Kayobe configuration uses mixin environments for modular
configuration. Users can opt into these mid-cycle to gradually adopt new
features. Mixin environments may be merged into the base configuration in later
major releases.

For more information about Kayobe environments, please see the `upstream Kayobe
documentation
<https://docs.openstack.org/kayobe/latest/multiple-environments.html#defining-kayobe-environments>`__.

.. note::

   To override settings in mixin environments, you will need to define
   overrides in an environment that inherits from that one, rather than in the
   base configuration.

.. _mixin-baremetal:

baremetal
---------

.. include:: ../../../etc/kayobe/environments/baremetal/README.rst

.. _mixin-baremetal-policy:

baremetal-policy
----------------

.. include:: ../../../etc/kayobe/environments/baremetal-policy/README.rst
