=========================
Magnum Cluster API Driver
=========================
A new driver for magnum has been written. It is an alternative to heat (as heat gets phased out due to maintenance burden) that allows the definition of clusters as Kubernetes CRDs as opposed to heat templates. The two are compatible and can both be active on the same deployment, and the decision of which driver is used for a given template depends on certain parameters inferred from the template. For the new driver, these are `{'server_type' : 'vm', 'os' : 'ubuntu', 'coe': kubernetes'}`.
Drivers can be enabled and disabled via the `disabled_drivers` parameter of `[drivers]` under `magnum.conf`.

Prerequisites for deploying the CAPI driver in magnum:

Management Cluster
===================
The CAPI driver relies on a management Kubernetes cluster, installed inside the cloud, to manage tenant Kubernetes clusters.
The easiest way to get one is by deploying `this <https://github.com/stackhpc/azimuth-config/tree/feature/capi-mgmt-config>`__ branch of azimuth-config, and look at the `capi-mgmt-example` environment. Refer to the `azimuth-config wiki <https://stackhpc.github.io/azimuth-config/>`__ for detailed steps on how to deploy.

Ensure that you have set `capi_cluster_apiserver_floating_ip: true`, as the management cluster will need an externally accessible IP. The external network this corresponds to is whatever you have set `azimuth_capi_operator_external_network_id` to. This network needs to be reachable from wherever the magnum container is running.

It's preferable that most Day 2 ops be done via a `CD Pipeline <https://stackhpc.github.io/azimuth-config/deployment/automation/>`__.

Kayobe Config
==============
Ensure that your kayobe-config branch is up to date on stackhpc/yoga.

Copy the kubeconfig found at `kubeconfig-capi-mgmt-<your-az-environment>.yaml` to your kayobe environment (e.g. `<your-skc-environment>/kolla/config/magnum/kubeconfig`. It is highly likely you'll want to add this file to ansible vault.

Ensure that your magnum.conf has the following set:

.. code-block:: yaml

    [nova_client]
    endpoint_type = publicURL


This is used to generate the application credential config injected into the tenant Kubernetes clusters, such that it is usable from within an OpenStack project, so you can't use the "internal API" end point here.

Control Plane
==============
Ensure that the nodes (either controllers or dedicated network hosts) that you are running the magnum containers on have connectivity to the network on which your management cluster has a floating IP (so that the magnum containers can reach the IP listed in the kubeconfig).

Magnum Templates
================

`azimuth-images <https://github.com/stackhpc/azimuth-images>`__ builds the required Ubuntu Kubernetes images, and `capi-helm-charts <https://github.com/stackhpc/capi-helm-charts/blob/main/.github/workflows/test.yaml>`__ CI runs conformance tests on each image built.

Magnum templates can be deployed using `openstack-config <https://github.com/stackhpc/openstack-config>`__. Typically, you would create a fork `<environment>-config` of this repository, move the resources defined in `examples/capi-templates-images.yml` into `etc/openstack-config/openstack-config.yml`, and then follow the instructions in the readme to deploy these.


