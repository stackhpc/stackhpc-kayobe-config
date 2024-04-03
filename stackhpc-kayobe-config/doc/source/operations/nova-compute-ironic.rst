===================
Nova Compute Ironic
===================

This section describes the deployment of the OpenStack Nova Compute
Ironic service. The Nova Compute Ironic service is used to integrate
OpenStack Ironic into Nova as a 'hypervisor' driver. The end users of Nova
can then deploy and manage baremetal hardware, in a similar way to VMs.

High Availability (HA)
======================

The OpenStack Nova Compute service is designed to be installed once on every
hypervisor in an OpenStack deployment. In this configuration, it makes little
sense to run additional service instances. Even if you wanted to, it's not
supported by design. This pattern breaks down with the Ironic baremetal
service, which must run on the OpenStack control plane. It is not feasible
to have a 1:1 mapping of Nova Compute Ironic services to baremetal nodes.

The obvious HA solution is to run multiple instances of Nova Compute Ironic
on the control plane, so that if one fails, the others can take over. However,
due to assumptions long baked into the Nova source code, this is not trivial.
The HA feature provided by the Nova Compute Ironic service has proven to be
unstable, and the direction upstream is to switch to an active/passive
solution [1].

However, challenges still exist with the active/passive solution. Since the
Nova Compute Ironic HA feature is 'always on', one must ensure that only a
single instance (per Ironic conductor group) is ever running. It is not
possible to simply put multiple service instances behind HAProxy and use the
active/passive mode.

Such problems are commonly solved with a technology such as Pacemaker, or in
the modern world, with a container orchestration engine such as Kubernetes.
Kolla Ansible provides neither, because in general it doesn't need to. Its
goal is simplicity.

The interim solution is to therefore run a single Nova Compute Ironic
service. If the service goes down, remedial action must be taken before
Ironic nodes can be managed. In many environments the loss of the Ironic
API for short periods is acceptable, providing that it can be easily
resurrected. The purpose of this document is to faciliate that.

.. note::

  The new sharding mode is not covered here and it is assumed that you are
  not using it. See [1] for further information. This will be updated in
  the future.

Optimal configuration of Nova Compute Ironic
============================================

Determine the current configuration for the site. How many Nova Compute
Ironic instances are running on the control plane?

.. code-block:: console

  $ openstack compute service list

Typically you will see either three or one. By default the host will
marked with a postfix, eg. ``controller1-ironic``. If you find more than
one, you will need to remove some instances. You must complete the
following section.

Moving from multiple Nova Compute Instances to a single instance
----------------------------------------------------------------

1. Decide where the single instance should run. This should normally be
   one of the three OpenStack control plane hosts. For convention, pick
   the first one, unless you can think of a good reason not to. Once you
   have chosen, set the following variable in ``etc/kayobe/nova.yml``.
   Here we have picked ``controller1``.

  .. code-block:: yaml

    kolla_nova_compute_ironic_host: controller1

2. Ensure that you have organised a maintenance window, during which
   there will be no Ironic operations. You will be breaking the Ironic
   API.

3. Perform a database backup.

  .. code-block:: console

    $ kayobe overcloud database backup -vvv

  Check the output of the command, and locate the backup files.

4. Identify baremetal nodes associated with Nova Compute Ironic instances
   that will be removed. You don't need to do anything with these
   specifically, it's just for reference later. For example:

  .. code-block:: console

    $ openstack baremetal node list --long -c "Instance Info" | grep controller3-ironic | wc -l
    61
    $ openstack baremetal node list --long -c "Instance Info" | grep controller2-ironic | wc -l
    35
    $ openstack baremetal node list --long -c "Instance Info" | grep controller1-ironic | wc -l
    55

5. Disable the redundant Nova Compute Ironic services:

  .. code-block:: console

    $ openstack compute service set controller3-ironic nova-compute --disable
    $ openstack compute service set controller2-ironic nova-compute --disable

6. Delete the redundant Nova Compute Ironic services. You will need the service
   ID. For example:

  .. code-block:: console

    $ ID=$(openstack compute service list | grep foo | awk '{print $2}')
    $ openstack compute service delete --os-compute-api-version 2.53 $ID

  In older releases, you may hit a bug where the service can't be deleted if it
  is not managing any instances. In this case just move on and leave the service
  disabled. Eg.

  .. code-block:: console

    $ openstack compute service delete  --os-compute-api-version 2.53 c993b57e-f60c-4652-8328-5fb0e17c99c0
    Failed to delete compute service with ID 'c993b57e-f60c-4652-8328-5fb0e17c99c0': HttpException: 500: Server Error for url:
    https://acme.pl-2.internal.hpc.is:8774/v2.1/os-services/c993b57e-f60c-4652-8328-5fb0e17c99c0, Unexpected API Error.
    Please report this at http://bugs.launchpad.net/nova/ and attach the Nova API log if possible.

7. Remove the Docker containers for the redundant Nova Compute Ironic services:

  .. code-block:: console

    $ ssh controller2 sudo docker rm -f nova_compute_ironic
    $ ssh controller3 sudo docker rm -f nova_compute_ironic

8. Ensure that all Ironic nodes are using the single remaining Nova Compute
   Ironic instance. Eg. Baremetal nodes in use by compute instances will not
   fail over to the remaining Nova Compute Ironic service. Here, the active
   service is running on ``controller1``:

  .. code-block:: console

    $ ssh controller1
    $ sudo docker exec -it mariadb mysql -u nova -p$(sudo grep 'mysql+pymysql://nova:' /etc/kolla/nova-api/nova.conf | awk -F'[:,@]' '{print $3}')
    $ MariaDB [(none)]> use nova;

  Proceed with caution. It is good practise to update one record first:

  .. code-block:: console

    $ MariaDB [nova]> update instances set host='controller1-ironic' where uuid=0 and host='controller3-ironic' limit 1;
      Query OK, 1 row affected (0.002 sec)
      Rows matched: 1  Changed: 1  Warnings: 0

  At this stage you should go back to step 4 and check that the numbers have
  changed as expected. When you are happy, update remaining records for all
  services which have been removed:

  .. code-block:: console

    $ MariaDB [nova]> update instances set host='controller1-ironic' where deleted=0 and host='controller3-ironic';
      Query OK, 59 rows affected (0.009 sec)
      Rows matched: 59  Changed: 59  Warnings: 0
    $ MariaDB [nova]> update instances set host='controller1-ironic' where deleted=0 and host='controller2-ironic';
      Query OK, 35 rows affected (0.003 sec)
      Rows matched: 35  Changed: 35  Warnings: 0

9. Repeat step 4. Verify that all Ironic nodes are using the single remaining
   Nova Compute Ironic instance.


Making it easy to re-deploy Nova Compute Ironic
-----------------------------------------------

In the previous section we saw that at any given time, a baremetal node is
associated with a single Nova Compute Ironic instance. At this stage, assuming
that you have diligently followed the instructions, you are in the situation
where all Ironic baremetal nodes are managed by a single Nova Compute Ironic
instance. If this service goes down, you will not be able to manage /any/
baremetal nodes.

By default, the single remaining Nova Compute Ironic instance will be named
after the host on which it is deployed. The host name is passed to the Nova
Compute Ironic instance via the default section of the ``nova.conf`` file,
using the field: ``host``.

If you wish to re-deploy this instance, for example because the original host
was permanently mangled in the World Server Throwing Championship [2], you
must ensure that the new instance has the same name as the old one. Simply
setting ``kolla_nova_compute_ironic_host`` to another controller and
re-deploying the service is not enough; the new instance will be named after
the new host.

To work around this you should set the ``host`` field in ``nova.conf`` to a
constant, such that the new Nova Compute Ironic instance comes up with the
same name as the one it replaces.

For example, if the original instance resides on ``controller1``, then set the
following in ``etc/kayobe/nova.yml``:

.. code-block:: yaml

  kolla_nova_compute_ironic_static_host_name: controller1-ironic

Note that an ``-ironic`` postfix is added to the hostname. This comes from
a convention in Kolla Ansible. It is worth making this change ahead of time,
even if you don't need to immediately re-deploy the service.

It is also possible to use an arbitrary ``host`` name, but you will need
to edit the database again. That is an optional exercise left for the reader.
See [1] for further details.

.. note::

  There is a bug when overriding the host name in Kolla Ansible, where it
  is currently assumed that it will be set to the actual hostname + an
  -ironic postfix. The service will come up correctly, but Kolla Ansible
  will not detect it. See here:
  https://bugs.launchpad.net/kolla-ansible/+bug/2056571

Re-deploying Nova Compute Ironic
--------------------------------

The decision to re-deploy Nova Compute Ironic to another host should only be
taken if there is a strong reason to do so. The objective is to minimise
the chance of the old instance starting up alongside the new one. If the
original host has been re-imaged, or physically replaced there is no risk.
However, if the original host has been taken down for non-destructive
maintenance, it is better to avoid re-deploying the service if the end users
can tolerate the wait. If you are forced to re-deploy the service, knowing
that the original instance may start when the host comes back online, you
must plan accordingly. For example, by booting the original host in maintenance
mode and removing the old service before it can start, or by stopping the
new instance before the original one comes back up, and then reverting the
config to move it to the new host.

There are essentially two scenarios for re-deploying Nova Compute Ironic.
These are described in the following sub-sections:

Current host is accessible
~~~~~~~~~~~~~~~~~~~~~~~~~~

Adjust the ``kolla_nova_compute_ironic_host`` variable to point to the
new host, eg.

.. code-block:: diff

  +kolla_nova_compute_ironic_host: controller2
  -kolla_nova_compute_ironic_host: controller1

Remove the old container:

.. code-block:: console

  $ ssh controller1 sudo docker rm -f nova_compute_ironic

Deploy the new service:

.. code-block:: console

  $ kayobe overcloud service deploy -kl controller2 -l controller2 -kt nova

Verify that the new service appears as 'up' and 'enabled':

.. code-block:: console

  $ openstack compute service list

Current host is not accessible
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

In this case you will need to remove the inaccessible host from the inventory.
For example, in ``etc/kayobe/inventory/hosts``, remove ``controller1`` from
the ``controllers`` group.

Adjust the ``kolla_nova_compute_ironic_host`` variable to point to the
new host, eg.

.. code-block:: diff

  +kolla_nova_compute_ironic_host: controller2
  -kolla_nova_compute_ironic_host: controller1

Deploy the new service:

.. code-block:: console

  $ kayobe overcloud service reconfigure -kl controller2 -l controller2 -kt nova

Verify that the new service appears as 'up' and 'enabled':

.. code-block:: console

  $ openstack compute service list

.. note::

  It is important to stop the original service from starting up again. It is
  up to you to prevent this.

.. note::

  Once merged, the work on 'Kayobe reliability' may allow this step to run
  without modifying the inventory to remove the broken host.

[1] https://specs.openstack.org/openstack/nova-specs/specs/2024.1/approved/ironic-shards.html#migrate-from-peer-list-to-shard-key
[2] https://www.cloudfest.com/world-server-throwing-championship
