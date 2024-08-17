==========
Monitoring
==========

Monitoring Configuration
========================

StackHPC kayobe config includes a reference monitoring and alerting stack based
on Prometheus, Alertmanager, Grafana, Fluentd, OpenSearch & OpenSearch
Dashboards. These services by default come enabled and configured.

Monitoring hosts, usually the controllers, should be added to the monitoring
group. The group definition can be applied in various different places. For
example, this configuration could be added to etc/kayobe/inventory/groups:

.. code-block:: yaml

    [monitoring:children]
    controllers

Central OpenSearch cluster collects OpenStack logs, with an option to receive
operating system logs too. In order to enable this, execute custom playbook
after deployment:

.. code-block:: console

    cd $KAYOBE_CONFIG_PATH
    kayobe playbook run ansible/rsyslog.yml

`Prometheus <https://prometheus.io/>`__ comes with a comprehensive set of
metrics gathered from enabled exporters; every exporter's data is visualised
by at least one `Grafana <https://grafana.com>`__ dashboard. Standard set of
alerting rules is present as well.

While the default configuration often works out of the box, there
are some tunables which can be customised to adapt the configuration to a
particular deployment's needs.

The configuration options can be found in
``etc/kayobe/stackhpc-monitoring.yml``:

.. literalinclude:: ../../../etc/kayobe/stackhpc-monitoring.yml
   :language: yaml

SMART Drive Monitoring
======================

StackHPC kayobe config also includes drive monitoring for spinning disks and
NVME's.

By default, node exporter doesn't provide SMART metrics, hence we make use
of 2 scripts (one for NVME’s and one for spinning drives), which are run by
a cronjob, to output the metrics and we use node exporter's Textfile collector
to report the metrics output by the scripts to Prometheus. These metrics can
then be visualised in Grafana with the bundled dashboard.

After pulling in the latest changes into your local kayobe config, reconfigure
Prometheus and Grafana

.. code-block:: console

    kayobe overcloud service reconfigure -kt grafana,prometheus

(Note: If you run into an error when reconfiguring Grafana, it could be due to
`this <https://bugs.launchpad.net/kolla-ansible/+bug/1997984>`__ bug and at
present, the workaround is to go into each node running Grafana and manually
restart the process with ``systemctl restart kolla-grafana-container.service``
and then try the reconfigure command again.)

Once the reconfigure has completed you can now run the custom playbook which
copies over the scripts and sets up the cron jobs to start SMART monitoring
on the overcloud hosts:

.. code-block:: console

    (kayobe) [stack@node ~]$ cd etc/kayobe
    (kayobe) [stack@node kayobe]$ kayobe playbook run ansible/smartmon-tools.yml

SMART reporting should now be enabled along with a Prometheus alert for
unhealthy disks and a Grafana dashboard called ``Hardware Overview``.

Alertmanager and Slack
======================

StackHPC Kayobe configuration comes bundled with an array of alerts but does not
enable any receivers for notifications by default. Various receivers can be
configured for Alertmanager. Slack is currently the most common.

To set up a receiver, create a ``prometheus-alertmanager.yml`` file under
``etc/kayobe/kolla/config/prometheus/``. An example config is stored in this
directory. The example configuration uses two Slack channels. One channel
receives all alerts while the other only receives alerts tagged as critical. It
also adds a silence button to temporarily mute alerts. To use the example in a
deployment, you will need to generate two webhook URLs, one for each channel.

To generate a slack webhook, `create a new app
<https://api.slack.com/apps/new>`__ in the workspace you want to add alerts to.
From the Features page, toggle Activate incoming webhooks on. Click Add new
webhook to workspace. Pick a channel that the app will post to, then click
Authorise. You only need one app to generate both webhooks.

Both URLs should be encrypted using ansible vault, as they give anyone access to
your slack channels. The standard practice is to store them in
``kayobe/secrets.yml`` as:

.. code-block:: yaml

    secrets_slack_notification_channel_url: <some_webhook_url>
    secrets_slack_critical_notification_channel_url: <some_other_webhook_url>

These should then be set as the ``slack_api_url`` and ``api_url`` for the
regular and critical alerts channels respectively. Both slack channel names will
need to be set, and the proxy URL sould be set or removed.

If you want to add an alerting rule, there are many good examples of alerts are
available `here <https://awesome-prometheus-alerts.grep.to/>`__. They simply
need to be added to one of the ``*.rules`` files in the prometheus configuration
directory.

Ceph Monitoring
===============

There is code in the globals.yml file to extract the ceph mgr nodes from the
mgrs group and list them as the endpoints for prometheus. Additionally,
depending on your configuration, you may need set the
``kolla_enable_prometheus_ceph_mgr_exporter`` variable to ``true`` in order to
enable the ceph mgr exporter.

.. _os-capacity:

OpenStack Capacity
==================

OpenStack Capacity allows you to see how much space you have available
in your cloud. StackHPC Kayobe Config will deploy OpenStack Capacity
by default on a service deploy, this can be disabled by setting
``stackhpc_enable_os_capacity`` to false.

OpenStack Capacity is deployed automatically using a service deploy hook
with the generated kolla-ansible admin credentials, you can override these
by setting the authentication url, username, password, project name and
project domain name in ``stackhpc-monitoring.yml``:

.. code-block:: yaml

    stackhpc_os_capacity_auth_url: <keystone_auth_url>
    stackhpc_os_capacity_username: <openstack_username>
    stackhpc_os_capacity_password: <openstack_password_encrypted_with_vault>
    stackhpc_os_capacity_project_name: <openstack_project_name>
    stackhpc_os_capacity_domain_name: <openstack_project_domain_name>
    stackhpc_os_capacity_openstack_region_name: <openstack_region_name>

Additionally, you should ensure these credentials have the correct permissions
for the exporter.

If you are deploying in a cloud with internal TLS, you may be required
to provide a CA certificate for the OpenStack Capacity exporter if your
certificate is not signed by a trusted CA. For example, to use a CA certificate
named ``vault.crt`` that is also added to the Kolla containers:

.. code-block:: yaml

    stackhpc_os_capacity_openstack_cacert: "{{ kayobe_env_config_path }}/kolla/certificates/ca/vault.crt"

Alternatively, to disable certificate verification for the OpenStack Capacity
exporter:

.. code-block:: yaml

    stackhpc_os_capacity_openstack_verify: false

If you've modified your credentials, you will need to re-deploy OpenStack Capacity
using the ``deploy-os-capacity-exporter.yml`` Ansible playbook
via Kayobe.

.. code-block:: console

    kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/deploy-os-capacity-exporter.yml

If you notice ``HaproxyServerDown`` or ``HaproxyBackendDown`` prometheus
alerts after deployment it's likely the os_exporter secrets have not been
set correctly, double check you have entered the correct authentication
information appropiate to your cloud and re-deploy.

Friendly Network Names
=======================
For operators that prefer to see descriptive or friendly interface names the
following play can be run. This takes network names as defined in kayobe and
relabels the devices/interfaces in Prometheus to make use of these names.

**Check considerations and known limitations to see if this is suitable in any
given environment before applying.**

This reuses existing fields to provide good compatibility with existing
dashboards and alerts.

To enable the change:

.. code-block:: console

    kayobe playbook run etc/kayobe/ansible/prometheus-network-names.yml
    kayobe overcloud service reconfigure --kt prometheus

This first generates a template based on the prometheus.yml.j2
``etc/kayobe/ansible/`` and which is further templated for use with
kolla-ansible.
This is then rolled out via service reconfigure.


This helps Prometheus provide insights that can be more easily understood by
those without an intimate understanding of a given site. Prometheus Node
Exporter and cAdvisor both provide network statistics using the
interface/device names. This play causes Prometheus to relabel these fields to
human readable names based on the networks as defined in kayobe
e.g. bond1.1838 may become storage_network.

The default labels are preserved with the prefix ``original_``.

* For node_exporter, ``device`` is then used for network names, while
  ``original_device`` is used for the interface itself.
* For cAdvisor, ``interface`` is used for network names, and
  ``original_interface`` is used to preserve the interface name.

:Known-Limitations/Considerations/Requirements:

Before enabling this feature, the implications must be discussed with the
customer. The following are key considerations for that conversation:

* Only network names defined within kayobe are within scope.
* Tenant network interfaces, including SR-IOV are not considered or modified.
* Only the interface directly attributed to a network will be relabelled.
  This may be a bond, a vlan tagged sub-interface, or both.
  The parent bond, or bond members are not relabelled unless they are
  captured within a distinct defined network.
* Modified entries will be within existing labels. This may be breaking for
  anything that expects the original structure, including custom dashboards,
  alerting, billing, etc.
* After applying, there will be inconsistency in the time-series db for the
  duration of the retention period i.e until previously ingested entries
  expire.
  The metrics gathered prior to applying these modifications will be unaltered,
  with all new metrics using the new structure.
* The interface names and their purpose must be consistent and unique within
  the environment. i.e if eth0 is defined as admin_interface on one node, no
  other node can include a different network definition using eth0.
  This does not apply in the case when both devices are bond members.
  e.g. bond0 on a controller has eth0 and eth1 as members. bond1 on a compute
  uses eth0 and eth1 as members. This is not problematic as it is only
  the bond itself that is relabelled.

Redfish exporter
================

Redfish exporter will query the overcloud BMCs via their redfish interfaces
to produce various metrics relating to the hardware, and system health.

To configure the exporter, adjust the variables in
``$KAYOBE_CONFIG_PATH/stackhpc-monitoring.yml`` to use appropriate values:

.. code-block:: yaml

    # Whether the redfish exporter is enabled.
    stackhpc_enable_redfish_exporter: true

    # Redfish exporter credentials
    redfish_exporter_default_username: "{{ ipmi_username }}"
    redfish_exporter_default_password: "{{ ipmi_password }}"

    # The address of the BMC that is queried by redfish exporter for metrics.
    redfish_exporter_target_address: "{{ ipmi_address }}"

Deploy the exporter on the seed:

.. code-block:: console

    kayobe seed service deploy -t seed-deploy-containers -kt none

It is required that you re-configure the Prometheus, Grafana
services following deployment, to do this run the following Kayobe command.

.. code-block:: console

    kayobe overcloud service reconfigure -kt grafana,prometheus
