==========
Monitoring
==========

Monitoring Configuration
========================

StackHPC kayobe config includes a reference monitoring stack based on
Prometheus. Whilst this often works out of the box, there are some tunables
which can be customised to adapt the configuration to a particular deployment.

The configuration options can be found in
``etc/kayobe/stackhpc-monitoring.yml``:

.. literalinclude:: ../../../etc/kayobe/stackhpc-monitoring.yml
   :language: yaml

In order to enable stock monitoring configuration within a particular
environment, create the following symbolic links:

.. code-block:: console

    cd $KAYOBE_CONFIG_PATH
    ln -s kolla/config/grafana/ environments/$KAYOBE_ENVIRONMENT/kolla/config/
    ln -s kolla/config/prometheus/ environments/$KAYOBE_ENVIRONMENT/kolla/config/

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
