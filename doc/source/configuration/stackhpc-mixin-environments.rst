.. _stackhpc-mixin-environments:

===========================
StackHPC Mixin Environments
===========================

StackHPC Kayobe configuration provides a set of mixin environments, which can
be used to apply configuration in modular way.  These provide a mechanism where
users can opt into new sets of configuration mid-cycle, at a time of the their
choosing, and thereby facilitate gradual adoption of new features.  Config may
be moved into the the base configuration for the next major release.

For more information about Kayobe environments, please see the `upstream Kayobe
documentation
<https://docs.openstack.org/kayobe/latest/multiple-environments.html#defining-kayobe-environments>`__.

.. note::

   To override settings in mixin environments, you will need to define the
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
