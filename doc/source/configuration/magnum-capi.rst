=========================
Magnum Cluster API Driver
=========================

Prequisites for deploying the CAPI driver in magnum:

Management Cluster
===================
The CAPI driver relies on a management cluster to manage tenant kubernetes clusters.
The easiest way to get one is by deploying [this](https://github.com/stackhpc/azimuth-config/tree/feature/capi-mgmt-config) branch of azimuth-config, and look at the `capi-mgmt-example` environment.


Ensure that you have set `capi_cluster_apiserver_floating_ip: true`, as the management cluster will need an externally accessible IP.

Kayobe Config
==============
Ensure that your kayobe-config branch is up to date on stackhpc/yoga.

Copy the kubeconfig found at `kubeconfig-capi-mgmt-<your-environment>.yaml` to your kayobe environment (e.g. `<your-environment>/kolla/config/magnum/kubeconfig`.

Ensure that your magnum.conf has the following set:
```
[nova_client]
endpoint_type = publicURL
```

Control Plane
==============
Ensure that the nodes (either control plane nodes or dedicated network nodes) that you are running the magnum containers on have internet connectivity (so that the magnum containers can reach the IP listed in the kubeconfig).

Magnum Templates
================

(openstack-config reference templates to be added shortly)


