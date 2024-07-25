==========
ci-builder
==========

The ``ci-builder`` Kayobe environment is used to build Kolla container images.
Images are built using package repositories in the StackHPC Ark Pulp service,
and pushed there once built.

.. warning::

    This guide was written for the Yoga release and has not been validated for
    Caracal. Proceed with caution.

In general it is preferable to use the `container image build CI workflow
<https://github.com/stackhpc/stackhpc-kayobe-config/actions/workflows/stackhpc-container-image-build.yml>`_
to build container images, but this manual approach may be useful in some
cases.

Prerequisites
=============

* a Rocky Linux 9 or Ubuntu Jammy 22.04 host

Setup
=====

Access the host via SSH. You may wish to start a ``tmux`` session.

If using an LVM-based image, extend the ``lv_home`` and ``lv_tmp`` logical
volumes.

.. parsed-literal::

   sudo pvresize $(sudo pvs --noheadings | head -n 1 | awk '{print $1}')
   sudo lvextend -L 4G /dev/rootvg/lv_home -r
   sudo lvextend -L 4G /dev/rootvg/lv_tmp -r

Install package dependencies.

On Rocky Linux:

.. parsed-literal::

   sudo dnf install -y git

On Ubuntu:

.. parsed-literal::

   sudo apt update
   sudo apt install -y gcc git libffi-dev python3-dev python-is-python3 python3-venv

Clone the Kayobe and Kayobe configuration repositories (this one):

.. parsed-literal::

   cd
   mkdir -p src
   pushd src
   git clone https://github.com/stackhpc/kayobe.git -b |current_release_git_branch_name|
   git clone https://github.com/stackhpc/stackhpc-kayobe-config -b |current_release_git_branch_name| kayobe-config
   popd

Create a virtual environment and install Kayobe:

.. parsed-literal::

   cd
   mkdir -p venvs
   pushd venvs
   python3 -m venv kayobe
   source kayobe/bin/activate
   pip install -U pip
   pip install ../src/kayobe
   popd

Add initial network configuration:

.. parsed-literal::

   sudo ip l add breth1 type bridge
   sudo ip l set breth1 up
   sudo ip a add 192.168.33.3/24 dev breth1
   sudo ip l add dummy1 type dummy
   sudo ip l set dummy1 up
   sudo ip l set dummy1 master breth1

On Ubuntu systems, persist the running network configuration.

.. parsed-literal::

   sudo cp /run/systemd/network/* /etc/systemd/network

Installation
============

Acquire the Ansible Vault password for this repository, and store a copy at
``~/vault-pw``.

The following commands install Kayobe and its dependencies, and prepare the
Ansible control host.

.. parsed-literal::

   export KAYOBE_VAULT_PASSWORD=$(cat ~/vault-pw)
   pushd ~/venvs/kayobe
   source bin/activate
   popd
   pushd ~/src/kayobe-config
   source kayobe-env --environment ci-builder
   kayobe control host bootstrap

Deployment
==========

If using an LVM-based image, uncomment the ``seed_lvm_groups`` variable in
``etc/kayobe/environments/ci-builder/seed.yml``.

If using an LVM-based image, grow the root volume group.

.. parsed-literal::

   kayobe playbook run etc/kayobe/ansible/growroot.yml -e growroot_group=seed

On Ubuntu systems, purge the command-not-found package.

.. parsed-literal::

   kayobe playbook run etc/kayobe/ansible/purge-command-not-found.yml

Next, configure the host OS & services.

.. parsed-literal::

   kayobe seed host configure

.. _authenticating-pulp-proxy:

Authenticating Pulp proxy
-------------------------

If you are building against authenticated package repositories such as those in
`Ark <https://ark.stackhpc.com>`_, you will need to provide secure access to
the repositories without leaking credentials into the built images or their
metadata.  This is typically not the case for a client-local Pulp, which
provides unauthenticated read-only access to the repositories on a trusted
network.

Docker provides `build
secrets <https://docs.docker.com/build/building/secrets/>`_, but these must be
explicitly requested for each RUN statement, making them challenging to use in
Kolla.

StackHPC Kayobe Configuration provides support for deploying an authenticating
Pulp proxy that injects an HTTP basic auth header into requests that it
proxies. Because this proxy bypasses Pulp's authentication, it must not be
exposed to any untrusted environment.

Ensure that ``localhost`` is resolvable if Docker bridge networking is
disabled. This may be achieved by adding the following to ``/etc/hosts``:

.. parsed-literal::

   127.0.0.1 localhost

To deploy the proxy:

.. parsed-literal::

   kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp-auth-proxy.yml

Building images
===============

At this point you are ready to build and push some container images.

.. parsed-literal::

   kayobe seed container image build --push
   kayobe overcloud container image build --push

If using an :ref:`authenticating Pulp proxy <authenticating-pulp-proxy>`,
append ``-e stackhpc_repo_mirror_auth_proxy_enabled=true`` to these commands.

The container images are tagged as |current_release|-<distribution>-<datetime>.
Check ``tag`` in ``/opt/kayobe/etc/kolla/kolla-build.conf`` or run ``docker
image ls`` to see the tag of the new images.

To build images for a different base distribution, set ``-e
kolla_base_distro=<distro>``.

To build images using a specific tag, set ``-e kolla_tag=<tag>``.

Using the new images
====================

To use the new images, edit
``~/src/kayobe-config/etc/kayobe/kolla-image-tags.yml`` to reference the tag.
