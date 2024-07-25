======================================
Running Tempest with Kayobe Automation
======================================

Overview
========

This document describes how to configure and run `Tempest
<https://docs.openstack.org/tempest/latest/>`_ using `kayobe-automation
<https://github.com/stackhpc/kayobe-automation>`_ from the ``.automation``
submodule included with ``stackhpc-kayobe-config``.

The best way of running Tempest is to use CI/CD workflows. Before proceeding,
consider whether it would be possible to use/set up a CI/CD workflow instead.
For more information, see the :doc:`CI/CD workflows page
</configuration/ci-cd>`.

The following guide will assume all commands are run from your
``kayobe-config`` root and the environment has been configured to run Kayobe
commands unless stated otherwise.

Prerequisites
=============

Installing Docker
-----------------

``kayobe-automation`` runs in a container on the Ansible control host. This
means that Docker must be installed on the Ansible control host if it is not
already.

.. warning::

    Docker can cause networking issues when it is installed. By default, it
    will create a bridge and change ``iptables`` rules. These can be disabled
    by setting the following in ``/etc/docker/daemon.json``:

    .. code-block:: json

        {
            "bridge": "none",
            "iptables": false
        }

    The bridge is the most common cause of issues and is *usually* safe to
    disable. Disabling the ``iptables`` rules will break any GitHub actions
    runners running on the host.

To install Docker on Ubuntu:

.. code-block:: bash

    # Add Docker's official GPG key:
    sudo apt-get update
    sudo apt-get install ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    # Add the repository to Apt sources:
    echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

Installing Docker on Rocky:

.. code-block:: bash

    sudo dnf install -y dnf-utils
    sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    sudo dnf install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

Ensure Docker is running & enabled:

.. code-block:: bash

    sudo systemctl start docker
    sudo systemctl enable docker

The Docker ``buildx`` plugin must be installed. If you are using an existing
installation of docker, you may need to install it with:

.. code-block:: bash

    sudo dnf/apt install docker-buildx-plugin
    sudo docker buildx install
    # or if that fails:
    sudo docker plugin install buildx

Building a Kayobe container
---------------------------

Build a Kayobe automation image:

.. code-block:: bash

    git submodule init
    git submodule update
    # If running on Ubuntu, the fact cache can confuse Kayobe in the Rocky-based container
    mv etc/kayobe/facts{,-old}
    sudo DOCKER_BUILDKIT=1 docker build --network host --build-arg BASE_IMAGE=rockylinux:9 --file .automation/docker/kayobe/Dockerfile --tag kayobe:latest .

Configuration
=============

Kayobe automation configuration files are stored in the ``.automation.conf/``
directory. It contains:

- A script used to export environment variables for meta configuration of
  Tempest - ``.automation.conf/config.sh``.
- Tempest configuration override files, stored in ``.automation.conf/tempest/``
  and conventionally named ``tempest.overrides.conf`` or
  ``tempest-<environment>.overrides.conf``.
- Tempest load lists, stored in ``.automation.conf/tempest/load-lists``.
- Tempest skip lists, stored in ``.automation.conf/tempest/skip-lists``.

config.sh
---------

``config.sh`` is a mandatory shell script, primarily used to export environment
variables for the meta configuration of Tempest.

See:
https://github.com/stackhpc/docker-rally/blob/master/bin/rally-verify-wrapper.sh
for a full list of Tempest parameters that can be overridden.

The most common variables to override are:

- ``TEMPEST_CONCURRENCY`` - The maximum number of tests to run in parallel at
  one time. Higher values are faster but increase the risk of timeouts. 1-2 is
  safest in CI/Tenks/Multinode/AIO etc. 8-32 is typical in production. Default
  value is 2.
- ``KAYOBE_AUTOMATION_TEMPEST_LOADLIST``: the filename of a load list in the
  ``load-lists`` directory. Default value is ``default`` (symlink to refstack).
- ``KAYOBE_AUTOMATION_TEMPEST_SKIPLIST``: the filename of a load list in the
  ``skip-lists`` directory. Default value is unset.
- ``TEMPEST_OPENRC``: The **contents** of an ``openrc.sh`` file, to be used by
  Tempest to create resources on the cloud. Default is to read in the contents
  of ``etc/kolla/public-openrc.sh``.

tempest.overrides.conf
----------------------

Tempest uses a configuration file to define which tests are run and how to run
them. A full sample configuration file can be found `here
<https://docs.openstack.org/tempest/latest/sampleconf.html>`_. Sensible
defaults exist for all values and in most situations, a blank
``*overrides.conf`` file will successfully run many tests. It will however also
skip many tests which may otherwise be appropriate to run.

`Shakespeare <https://github.com/stackhpc/shakespeare>`_ is a tool for
generating Tempest configuration files. It contains elements for different
cloud features, which can be combined to template out a detailed configuration
file. This is the best-practice approach.

Below is an example of a manually generated file including many of the most
common overrides. It makes many assumptions about the environment, so make sure
you understand all the options before applying them.

.. NOTE(upgrade): Microversions change for each release
.. code-block:: ini

    [openstack]
    # Use a StackHPC-built image without a default password.
    img_url=https://github.com/stackhpc/cirros/releases/download/20231206/cirros-d231206-x86_64-disk.img

    [auth]
    # Expect unlimited quotas for CPU cores and RAM
    compute_quotas = cores:-1,ram:-1

    [compute]
    # Required for migration testing
    min_compute_nodes = 2
    # Required to test some API features
    min_microversion = 2.1
    max_microversion = 2.95
    # Flavors for creating test servers and server resize. The ``alt`` flavor should be larger.
    flavor_ref = <flavor UUID>
    flavor_ref_alt = <different flavor UUID>
    volume_multiattach = true

    [compute-feature-enabled]
    # Required for migration testing
    resize = true
    live_migration = true
    block_migration_for_live_migration = false
    volume_backed_live_migration = true

    [placement]
    min_microversion = 1.0
    max_microversion = 1.39

    [volume]
    storage_protocol = ceph
    # Required to test some API features
    min_microversion = 3.0
    max_microversion = 3.70

Tempest configuration override files are stored in
``.automation.conf/tempest/``. The default file used is
``tempest.overrides.conf`` or ``tempest-<environment>.overrides.conf``
depending on whether a Kayobe environment is enabled. This can be changed by
setting ``KAYOBE_AUTOMATION_TEMPEST_CONF_OVERRIDES`` to a different file path.
An ``overrides.conf`` file must be supplied, even if it is blank.

Load Lists
----------

Load lists are a newline-separated list of tests to run. They are stored in
``.automation.conf/tempest/load-lists/``. The directory contains three objects
by default:

- ``tempest-full`` - A complete list of all possible tests.
- ``platform.2022.11-test-list.txt`` - A reduced list of tests to match the
  `Refstack <https://docs.opendev.org/openinfra/refstack/latest/>`_ standard.
- ``default`` - A symlink to ``platform.2022.11-test-list.txt``.

Test lists can be selected by changing ``KAYOBE_AUTOMATION_TEMPEST_LOADLIST``
in ``config.sh``. The default value is ``default``, which symlinks to
``platform.2022.11-test-list.txt``.

A common use case is to use the ``failed-tests`` list output from a previous
Tempest run as a load list, to retry the failed tests after making changes.

Skip Lists
----------

Skip lists are a newline-separated list of tests to Skip. They are stored in
``.automation.conf/tempest/skip-lists/``. Each line consists of a pattern to
match against test names, and a string explaining why the test is being
skipped e.g.

.. code-block::

    tempest.scenario.test_network_basic_ops.TestNetworkBasicOps.test_subnet_details.*: "Cirros image doesn't have /var/run/udhcpc.eth0.pid"

There is no requirement for a skip list, and none is selected by default. A
skip list can be selected by setting ``KAYOBE_AUTOMATION_TEMPEST_SKIPLIST`` in
``config.sh``.

Tempest runner
--------------

While the Kayobe automation container is always deployed to the ansible control
host, the Tempest container is deployed to the host in the ``tempest_runner``
group, which can be any host in the Kayobe inventory. The group should only
ever contain one host. The seed is usually used as the tempest runner however
it is also common to use the Ansible control host or an infrastructure VM. The
main requirement of the host is that it can reach the OpenStack API.

.. _tempest-cacert:

Tempest CA certificate
----------------------

If your public OpenStack API uses TLS with a Certificate Authority (CA) that is
not trusted by the Python CA trust store, it may be necessary to add a CA
certificate to the trust store in the container that runs Tempest. This can be
done by defining a ``tempest_cacert`` Ansible variable to a path containing the
CA certificate. You may wish to use ``kayobe_config_path`` or
``kayobe_env_config_path`` to be agnostic to the path where kayobe-config is
mounted within the container. For example:

.. code-block:: yaml
   :caption: ``etc/kayobe/tempest.yml``

   # Add the Vault CA certificate to the rally container when running tempest.
   tempest_cacert: "{{ kayobe_env_config_path }}/kolla/certificates/ca/vault.crt"

Running Tempest
===============

Kayobe automation will need to SSH to the Tempest runner (even if they are on
the same host), so requires an SSH key exported as
``KAYOBE_AUTOMATION_SSH_PRIVATE_KEY`` e.g.

.. code-block:: bash

    export KAYOBE_AUTOMATION_SSH_PRIVATE_KEY=$(cat ~/.ssh/id_rsa)

Tempest outputs will be sent to the ``tempest-artifacts/`` directory. Create
one if it does not exist.

.. code-block:: bash

    mkdir tempest-artifacts

The contents of ``tempest-artifacts`` will be overwritten. Ensure any previous
test results have been copied away.

The Tempest playbook is invoked through the Kayobe container using this
command from the base of the ``kayobe-config`` directory:

.. code-block:: bash

    sudo -E docker run --name kayobe-automation --detach -it --rm --network host \
    -v $(pwd):/stack/kayobe-automation-env/src/kayobe-config -v $(pwd)/tempest-artifacts:/stack/tempest-artifacts \
    -e KAYOBE_ENVIRONMENT -e KAYOBE_VAULT_PASSWORD -e KAYOBE_AUTOMATION_SSH_PRIVATE_KEY kayobe:latest \
    /stack/kayobe-automation-env/src/kayobe-config/.automation/pipeline/tempest.sh -e ansible_user=stack

By default, ``no_log`` is set to stop credentials from leaking. This can be
disabled by adding ``-e rally_no_sensitive_log=false`` to the end.

To follow the progress of the Kayobe automation container, either remove
``--detach`` from the above command, or follow the docker logs of the
``kayobe`` container.

To follow the progress of the Tempest tests themselves, follow the logs of the
``tempest`` container on the ``tempest_runner`` host.

.. code-block:: bash

    ssh <tempest-runner>
    sudo docker logs -f tempest

Tempest will keep running until completion if the ``kayobe`` container is
stopped. The ``tempest`` container must be stopped manually. Doing so will
however stop test resources (such as networks, images, and VMs) from being
automatically cleaned up. They must instead be manually removed. They should be
clearly labeled with either rally or tempest in the name, often alongside some
randomly generated string.

Outputs
-------

Tempest outputs will be sent to the ``tempest-artifacts/`` directory. It
contain the following artifacts:

- ``docker.log`` - The logs from the ``tempest`` docker container
- ``failed-tests`` - A simple list of tests that failed
- ``rally-junit.xml`` - An XML file listing all tests in the test list and
  their status (skipped/succeeded/failed). Usually not useful.
- ``rally-verify-report.html`` - An HTML page with all test results including
  an error trace for failed tests. It is often best to ``scp`` this file back
  to your local machine to view it. This is the most user-friendly way to view
  the test results, however can be awkward to host.
- ``rally-verify-report.json`` - A JSON blob with all test results including an
  error trace for failed tests. It contains all the same data as the HTML
  report but without formatting.
- ``stderr.log`` - The stderr log. Usually not useful.
- ``stdout.log`` - The stdout log. Usually not useful.
- ``tempest-load-list`` - The load list that Tempest was invoked with.
- ``tempest.log`` - Detailed logs from Tempest. Contains more data than the
  ``verify`` reports, but can be difficult to parse. Useful for tracing specific
  errors.
