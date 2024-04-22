==========
CloudKitty
==========

Configuring in kayobe-config
============================

By default, CloudKitty uses Gnocchi and Ceilometer as the collector and fetcher
backends. Unless the system has a specific reason not to, we recommend instead
using Prometheus as the backend for both. The following instructions explain
how to do this.

Enable CloudKitty and disable InfluxDB, as we are using OpenSearch as the
storage backend. Set the following in ``kolla.yml``:

.. code-block:: yaml

  kolla_enable_cloudkitty: true
  # Explicitly disable influxdb as we are using OpenSearch as the CloudKitty backend
  kolla_enable_influxdb: false

Set Prometheus as the backend for both the collector and fetcher, and Elasticsearch as the
storage backend. Note that this is patched in our fork of CloudKitty to also
work with OpenSearch. Proper support is still pending in Kolla-Ansible `here
<https://review.opendev.org/c/openstack/kolla-ansible/+/898555>`__. Set the
following in ``kolla/globals.yml``:

.. code-block:: yaml

  cloudkitty_collector_backend: prometheus
  cloudkitty_fetcher_backend: prometheus
  cloudkitty_storage_backend: elasticsearch

If you have TLS enabled, you will also need to set the cafile for Prometheus
and Elasticsearch. Set the following in ``kolla/globals.yml``, and make sure
that ``openstack_cacert`` is appropriately set as a Kayobe variable too. It
defaults to ``openstack_cacert: "{{ lookup('env', 'OS_CACERT') }}"``, but you
may prefer to set the path explicitly.

.. code-block:: yaml

  cloudkitty_prometheus_cafile: "{{ openstack_cacert }}"
  cloudkitty_elasticsearch_cafile: "{{ openstack_cacert }}"

The default collection period is one hour, which is likely too long for your
system. CloudKitty will charge for the entire period if any usage is seen
within this timeframe. This means that even just one minute will be counted as
an hour's usage. It is recommended to change this to a lower number, such as
ten minutes. When using Prometheus as the collector, you need to change the
scope_key to match the metrics provided by the Prometheus OpenStack Exporter.
Set the following in ``kolla/config/cloudkitty.conf``:

.. code-block:: console

  [collect]
  scope_key = tenant_id
  period = 600

You will need to configure which metrics CloudKitty should track. The following
example, set in ``kolla/config/cloudkitty/metrics.yml``, will track for VM flavors and
the total utilised volume.

.. code-block:: yaml

  metrics:
    openstack_nova_server_status:
      alt_name: instance
      groupby:
        - uuid
        - user_id
        - tenant_id
      metadata:
        - flavor_id
        - name
      mutate: MAP
      mutate_map:
        0.0: 1.0  # ACTIVE
        11.0: 1.0 # SHUTOFF
        12.0: 1.0 # SUSPENDED
        16.0: 1.0 # PAUSED
      unit: instance
    openstack_cinder_limits_volume_used_gb:
      alt_name: storage
      unit: GiB
      groupby:
        - tenant_id

TODO: Should we explain how to handle OpenStack exporter metrics relabelling,
for the case where a system may have had Monasca deployed in the past?

Post-configuration with openstack-config
========================================

This is an example `openstack-config
<https://github.com/stackhpc/openstack-config>`__ setup to create mappings for
the metrics configured above. Note that the costs are scaled for the ten minute
collection period, e.g. a flavor with 1 VCPU will cost 1 unit per hour.

.. code-block:: yaml

  # Map flavors based on VCPUs
  openstack_ratings_hashmap_field_mappings:
    - service: instance
        name: flavor_id
        mappings:
        - value: '1' # tiny compute flavor (1 vcpu) with an OpenStack flavor ID of 1
            cost: 0.1666666666666666
            type: flat
        - value: '2' # small compute flavor (2 vcpus) with an OpenStack flavor ID of 2
            cost: 0.3333333333333333
            type: flat
        - value: '3' # medium compute flavor (3 vcpus) with an OpenStack flavor ID of 3
            cost: 0.5
            type: flat
        - value: '4' # large compute flavor (4 vcpus) with an OpenStack flavor ID of 4
            cost: 0.6666666666666666
            type: flat
        - value: '5' # xlarge compute flavor (8 vcpus) with an OpenStack flavor ID of 5
            cost: 1.3333333333333333
            type: flat
        - value: '6' # tiny 2 compute flavor (2 vcpus) with an OpenStack flavor ID of 6
            cost: 0.3333333333333333
            type: flat

  # Map volumes based on GB
  openstack_ratings_hashmap_service_mappings:
  - service: storage
    cost: 0.16666666666666666
    type: flat

See the `OpenStack CloudKitty Ratings role
<https://github.com/stackhpc/ansible-collection-openstack/tree/main/roles/os_ratings>`__
for more details.
