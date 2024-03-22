Policy for a baremetaluser role
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

When deploying Slurm on baremetal nodes, it is typical to select a specific
baremetal node, and give it the expected hostname. We allow this via a tweak to
Nova policy.

Similarly, it is common that the IP address has to match the expected one for
the given node. We tweak neutron policy to allow fixed IPs, even when we do
not own the network.

We should never use the admin role to do these operations, as it has far too
much privilege.

Consuming this environment
^^^^^^^^^^^^^^^^^^^^^^^^^^

Add the ``baremetal-policy`` environment to your  ``.kayobe-environment`` file:

.. code-block:: yaml
   :caption: $KAYOBE_CONFIG_PATH/$KAYOBE_ENVIRONMENT/.kayobe-environment

   dependencies:
     - baremetal-policy

Redeploy Neutron, and Nova:

.. code-block:: console

   kayobe overcloud service deploy -kt neutron,nova
