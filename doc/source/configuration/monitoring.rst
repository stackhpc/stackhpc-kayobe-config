===========
Monitoring
===========

Monitoring Configuration
========================

StackHPC kayobe config includes a reference monitoring stack based on
Prometheus. Whilst this often works out of the box, there are some tunables
which can be customised to adapt the configuration to a particular deployment.

The configuration options can be found in
``etc/kayobe/stackhpc-monitoring.yml``:

.. literalinclude:: ../../../etc/kayobe/stackhpc-monitoring.yml
   :language: yaml

SMART Drive Monitoring
=======================
StackHPC kayobe config also includes drive monitoring for spinning disks and NVME's. 
After pulling in the latest changes into your local kayobe config, reconfigure prometheus and Grafana

.. code-block:: console

    kayobe overcloud service reconfigure -kt grafana,prometheus

(Note: If you run into an error when reconfiguring Grafana, it could be due to `this <https://bugs.launchpad.net/kolla-ansible/+bug/1997984>`__ bug and at present, the workaround is to go into each node running Grafana and manually restart the process with ``docker restart grafana`` and then try the reconfigure command again.) 

Once the reconfigure has completed you can now run the custom playbook:

.. code-block:: console

    (kayobe) [stack@node ~]$ cd etc/kayobe
    (kayobe) [stack@node kayobe]$ kayobe playbook run ansible/smartmontools.yml

SMART reporting should now be enabled along with a prometheus alert for unhealthy disks and a Grafana dashboard called ``Hardware Overview``. 


