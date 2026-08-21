# CI-Tenks Kayobe Environment

This Kayobe environment is designed for use in CI, primarily to test Seed
service deployment and Bifrost provisioning. It is currently a work in
progress.

The environment is deployed using the `automated-deployment.sh` script. This
script bootstraps the localhost as a hypervisor for a Seed and one Controller
instance. The Seed provisions the Controller using Bifrost.

### Current Tests

The environment currently tests the following:

* Seed Hypervisor host configuration
* Seed VM provisioning
* Seed host configuration
* Pulp deployment
* Pulp container syncing (one container - Bifrost)
* Bifrost Overcloud provisioning

### Future Enhancements

Potential future tests include:

* Pulp package syncing
* Overcloud host configuration, pulling packages from a local Pulp instance
* Full openstack service deployment (AIO or otherwise)
* Upgrades (Host OS and OpenStack)
* Multi-node OpenStack deployments:
  * Multiple Controllers
  * Multiple Compute nodes (including live migration)
  * Multiple Storage nodes (e.g., Ceph)

These enhancements depend on increased SMS hypervisor capacity and improved
synchronization times for the local Pulp instance.
