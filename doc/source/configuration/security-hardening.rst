==================
Security Hardening
==================

CIS Benchmark Hardening
-----------------------

The roles from the `Ansible-Lockdown <https://github.com/ansible-lockdown>`_
project are used to harden hosts in accordance with the CIS benchmark criteria.
It won't get your benchmark score to 100%, but should provide a significant
improvement over an unhardened system. A typical score would be 70%.

The following operating systems are supported:

- Ubuntu 22.04
- Rocky 9

Configuration
--------------

Some overrides to the role defaults are provided in
``$KAYOBE_CONFIG_PATH/inventory/group_vars/overcloud/cis``. These may not be
suitable for all deployments and so some fine tuning may be required. For
instance, you may want different rules on a network node compared to a
controller. It is best to consult the upstream role documentation for details
about what each variable does. The documentation can be found here:

- `Ubuntu 22.04 <https://github.com/ansible-lockdown/UBUNTU22-CIS>`__
- `Rocky 9 <https://github.com/ansible-lockdown/RHEL9-CIS>`__

Running the playbooks
---------------------

.. note::

  The hosts may need rebooting to fully pick up all of the changes. The CIS
  roles will warn you when this needs to be done, but the actual reboot is left
  as a manual operation to allow you to select a convenient time. Generally, if
  you are applying the hardening for the first time, then you will need to
  reboot.

As there is potential for unintended side effects when applying the hardening
playbooks, the playbooks are not currently enabled by default. It is recommended
that they are first applied to a representative staging environment to determine
whether or not workloads or API requests are affected by any configuration changes.

.. code-block:: console

    kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/cis.yml

Targetting additional hosts
---------------------------

The ``cis.yml`` playbook targets hosts in the ``cis-hardening`` group. By
default this includes the ``overcloud`` group. You can adjust this group
to suit your needs, e.g to add the seed VM:

.. code-block:: yaml
  :caption: $KAYOBE_CONFIG_PATH/inventory/groups

  [cis-hardening:children]
  overcloud
  seed

Enabling the host configure hook
--------------------------------

A hook is pre-installed but its execution is guarded by the
``stackhpc_enable_cis_benchmark_hardening_hook`` configuration option.
If you want the hardening playbooks to run automatically, as part of
host configure, simply set this flag to ``true``:

.. code-block:: yaml
  :caption: $KAYOBE_CONFIG_PATH/stackhpc.yml

    stackhpc_enable_cis_benchmark_hardening_hook: true

Alternatively, this can be toggled on a per-environment basis by
setting it in an environment specific config file, or even on
targeted hosts by using group or host vars.
