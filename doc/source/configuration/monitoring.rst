==========
Monitoring
==========

Monitoring Configuration
========================

StackHPC kayobe config includes a reference monitoring and alerting stack based
on Prometheus, Alertmanager, Grafana, Fluentd, Elasticsearch & Kibana. These
services by default come enabled and configured.

Monitoring hosts, usually the controllers, should be added to the monitoring
group. The group definition can be applied in various different places. For
example, this configuration could be added to etc/kayobe/inventory/groups:

.. code-block:: yaml

    [monitoring:children]
    controllers

Central Elasticsearch cluster collects OpenStack logs, with an option to receive
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

In order to enable stock monitoring configuration within a particular
environment, create the following symbolic links:

.. code-block:: console

    cd $KAYOBE_CONFIG_PATH
    ln -s ../../../../kolla/config/grafana/ environments/$KAYOBE_ENVIRONMENT/kolla/config/
    ln -s ../../../../kolla/config/prometheus/ environments/$KAYOBE_ENVIRONMENT/kolla/config/

and commit them to the config repository.

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
restart the process with ``docker restart grafana`` and then try the reconfigure
command again.)

Once the reconfigure has completed you can now run the custom playbook which
copies over the scripts and sets up the cron jobs to start SMART monitoring
on the overcloud hosts:

.. code-block:: console

    (kayobe) [stack@node ~]$ cd etc/kayobe
    (kayobe) [stack@node kayobe]$ kayobe playbook run ansible/smartmontools.yml

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
