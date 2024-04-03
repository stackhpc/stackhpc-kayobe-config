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

As there is potential for unintended side effects when applying the hardening
playbooks, the playbooks are not currently enabled by default. It is recommended
that they are first applied to a representative staging environment to determine
whether or not workloads or API requests are affected by any configuration changes.

.. code-block:: console

    kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/cis.yml

