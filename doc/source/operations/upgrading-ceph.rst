==============
Upgrading Ceph
==============

This section describes show to upgrade from one version of Ceph to another.
The Ceph upgrade procedure is described :ceph-doc:`here <cephadm/upgrade>`.

The Ceph release series is not strictly dependent upon the StackHPC OpenStack
release, however this configuration does define a default Ceph release series
and container image tag. The default release series is currently |ceph_series|.

Prerequisites
=============

Before starting the upgrade, ensure any appropriate prerequisites are
satisfied. These will be specific to each deployment, but here are some
suggestions:

* Ensure that expected test suites are passing, e.g. Tempest.
* Resolve any Prometheus alerts.
* Check for unexpected ``ERROR`` or ``CRITICAL`` messages in OpenSearch
  Dashboard.
* Check Grafana dashboards.

Consider whether the Ceph cluster needs to be upgraded within or outside of a
maintenance/change window.

Preparation
===========

Ensure that the local Kayobe configuration environment is up to date.

If you wish to use a different Ceph release series, set
``cephadm_ceph_release``.

If you wish to use different Ceph container image tags, set the following
variables:

* ``cephadm_image_tag`` (`tags <https://quay.io/repository/ceph/ceph?tab=tags&tag=latest>`__)
* ``cephadm_haproxy_image_tag`` (`tags <https://quay.io/repository/ceph/haproxy?tab=tags&tag=latest>`__)
* ``cephadm_keepalived_image_tag`` (`tags <https://quay.io/repository/ceph/keepalived?tab=tags&tag=latest>`__)

Be sure to use a tag that `matches the release series
<https://docs.ceph.com/en/latest/releases/>`__.

Upgrading Host Packages
=======================

Prior to upgrading the Ceph storage cluster, it may be desirable to upgrade
system packages on the hosts.

Note that these commands do not affect packages installed in containers, only
those installed on the host.

In order to avoid downtime, it is important to control how package updates are
rolled out. In general, Ceph monitor hosts should be updated *one by one*. For
Ceph OSD hosts it may be possible to update packages in batches of hosts,
provided there is sufficient capacity to maintain data availability.

For each host or batch of hosts, perform the following steps.

Place the host or batch of hosts into maintenance mode:

.. code-block:: console

   kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/ceph-enter-maintenance.yml -l <host>

To update all eligible packages, use ``*``, escaping if necessary:

.. code-block:: console

   kayobe overcloud host package update --packages "*" --limit <host>

If the kernel has been upgraded, reboot the host or batch of hosts to pick up
the change. While running this playbook, consider setting ``ANSIBLE_SERIAL`` to
the maximum number of hosts that can safely reboot concurrently.

.. code-block:: console

   kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/reboot.yml -l <host>

Remove the host or batch of hosts from maintenance mode:

.. code-block:: console

   kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/ceph-exit-maintenance.yml -l <host>

Wait for Ceph health to return to ``HEALTH_OK``:

.. code-block:: console

   ceph -s

Wait for Prometheus alerts and errors in OpenSearch Dashboard to resolve, or
address them.

Once happy that the system has been restored to full health, move onto the next
host or batch or hosts.

Sync container images
=====================

If using the local Pulp server to host Ceph images
(``stackhpc_sync_ceph_images`` is ``true``), sync the new Ceph images into the
local Pulp:

.. code-block:: console

   kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp-container-{sync,publish}.yml -e stackhpc_pulp_images_kolla_filter=none

Upgrade Ceph services
=====================

Start the upgrade. If using the local Pulp server to host Ceph images:

.. code-block:: console

   sudo cephadm shell -- ceph orch upgrade start --image <registry>/ceph/ceph:<tag>

Otherwise:

.. code-block:: console

   sudo cephadm shell -- ceph orch upgrade start --image quay.io/ceph/ceph:<tag>

The tag should match the ``cephadm_image_tag`` variable set in `preparation
<#preparation>`_. The registry should be the address and port of the local Pulp
server.

Check the update status:

.. code-block:: console

   ceph orch upgrade status

Wait for Ceph health to return to ``HEALTH_OK``:

.. code-block:: console

   ceph -s

Watch the cephadm logs:

.. code-block:: console

   ceph -W cephadm

Upgrade Cephadm
===============

Update the Cephadm package:

.. code-block:: console

   kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/cephadm-deploy.yml -e cephadm_package_update=true

Testing
=======

At this point it is recommended to perform a thorough test of the system to
catch any unexpected issues. This may include:

* Check Prometheus, OpenSearch Dashboards and Grafana
* Smoke tests
* All applicable tempest tests
* Horizon UI inspection

Cleaning up
===========

Prune unused container images:

.. code-block:: console

   kayobe overcloud host command run -b --command "docker image prune -a -f" -l ceph
