========================
Monitoring Configuration
========================

StackHPC kayobe config includes a reference monitoring stack based on
Prometheus. Whilst this often works out of the box, there are some tunables
which can be customised to adapt the configuration to a particular deployment.

The configuration options can be found in
``etc/kayobe/stackhpc-monitoring.yml``:

.. literalinclude:: ../../../etc/kayobe/stackhpc-monitoring.yml
   :language: yaml