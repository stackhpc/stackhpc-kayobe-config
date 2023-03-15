=====
Usage
=====

How to consume this configuration
=================================

This configuration is not a complete Kayobe configuration, rather it should be
treated as a base, in place of the `upstream kayobe-config
<https://opendev.org/openstack/kayobe-config>`__. Indeed, this repository is
based on the upstream kayobe-config, with some opinionated configuration
changes applied.

Since this repository makes changes to the base configuration, it works best
when used with Kayobe's :kayobe-doc:`multiple environments
<multiple-environments>` feature.

This configuration should be consumed using the `StackHPC Kayobe fork
<https://github.com/stackhpc/kayobe/tree/stackhpc/yoga>`__, which includes
backported support for Ansible collections.

New deployments
---------------

If starting a new deployment, clone this repository as the starting point for
your configuration:

.. parsed-literal::

   git clone https://github.com/stackhpc/stackhpc-kayobe-config -b |current_release_git_branch_name|

Existing deployments
--------------------

If migrating an existing deployment to StackHPC Kayobe configuration, you will
need to merge the changes in this repository into your repository:

.. parsed-literal::

   git remote add stackhpc https://github.com/stackhpc/stackhpc-kayobe-config
   git fetch stackhpc
   git merge stackhpc/|current_release_git_branch_name|

Updating
--------

This base configuration will be updated over time, to update repository
versions, container image tags, and other configuration. Deployments may
consume these updates by merging in the changes with their local
configuration:

.. parsed-literal::

   git fetch stackhpc
   git merge stackhpc/|current_release_git_branch_name|

The intention is to avoid merge conflicts where possible, but there may be
cases where this is difficult. We are open to discussion on how best to
approach this on both sides.
