#!/bin/bash

############################################
# STACKHPC-KAYOBE-CONFIG TENKS ENV VERSION #
############################################

# Cheat script for a full deployment.
# This should be used for testing only.

set -eu

BASE_PATH=~
KAYOBE_BRANCH=stackhpc/2025.1
KAYOBE_CONFIG_BRANCH=stackhpc/2025.1
KAYOBE_ENVIRONMENT=ci-tenks

# if [[ ! -f $BASE_PATH/vault-pw && ! $KAYOBE_VAULT_PASSWORD ]]; then
#     echo "Vault password file not found at $BASE_PATH/vault-pw"
#     exit 1
# fi

# # Install git and tmux.
# if $(which dnf 2>/dev/null >/dev/null); then
#     sudo dnf -y install git tmux
# else
#     sudo apt update
#     sudo apt -y install git tmux gcc libffi-dev python3-dev python-is-python3 python3-pip python3.12-venv
# fi

# export KAYOBE_VAULT_PASSWORD=$(cat $BASE_PATH/vault-pw)

# Disable the firewall.
sudo systemctl is-enabled firewalld && sudo systemctl stop firewalld && sudo systemctl disable firewalld || true

# Disable SELinux both immediately and permanently.
if $(which setenforce 2>/dev/null >/dev/null); then
    sudo setenforce 0
    sudo sed -i 's/^SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
fi

# Prevent sudo from performing DNS queries.
echo 'Defaults !fqdn' | sudo tee /etc/sudoers.d/no-fqdn

# Clone repositories
cd $BASE_PATH
mkdir -p src
pushd src
[[ -d kayobe ]] || git clone https://github.com/stackhpc/kayobe.git -b $KAYOBE_BRANCH
[[ -d kayobe-config ]] || git clone https://github.com/stackhpc/stackhpc-kayobe-config kayobe-config -b $KAYOBE_CONFIG_BRANCH
[[ -d kayobe/tenks ]] || (cd kayobe && git clone https://opendev.org/openstack/tenks.git)
popd

# # Create Kayobe virtualenv
# mkdir -p venvs
# pushd venvs
# if [[ ! -d kayobe ]]; then
#     python3.12 -m venv kayobe
# fi
# # NOTE: Virtualenv's activate and deactivate scripts reference an
# # unbound variable.
# set +u
# source kayobe/bin/activate
# set -u
# pip install -U pip
# pip install -r ../src/kayobe-config/requirements.txt
# popd

# Activate environment
# pushd $BASE_PATH/src/kayobe-config
# source kayobe-env --environment $KAYOBE_ENVIRONMENT

# Configure host networking (bridge, routes & firewall)
sudo $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/configure-local-networking.sh

# Bootstrap the Ansible control host.
kayobe control host bootstrap

# Configure the seed hypervisor host.
kayobe seed hypervisor host configure

# Provision the seed VM.
kayobe seed vm provision

# Configure the seed host, and deploy a local registry.
kayobe seed host configure

# Deploy local pulp server as a container on the seed VM
kayobe seed service deploy --tags seed-deploy-containers --kolla-tags none

# Deploying the seed restarts networking interface, run configure-local-networking.sh again to re-add routes.
sudo $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/configure-local-networking.sh

# Sync package & container repositories.
kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp-repo-sync.yml
kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp-repo-publish.yml
kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp-container-sync.yml -e stackhpc_pulp_images_kolla_filter=bifrost
kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp-container-publish.yml -e stackhpc_pulp_images_kolla_filter=bifrost

# Re-run full task to set up bifrost_deploy etc. using newly-populated pulp repo
kayobe seed service deploy

# NOTE: Make sure to use ./tenks, since just ‘tenks’ will install via PyPI.
(export TENKS_CONFIG_PATH=$KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/tenks.yml && \
 export KAYOBE_CONFIG_SOURCE_PATH=$BASE_PATH/src/kayobe-config && \
 export KAYOBE_VENV_PATH=$BASE_PATH/venvs/kayobe && \
 cd $BASE_PATH/src/kayobe && \
 ./dev/tenks-deploy-overcloud.sh ./tenks)

# Inspect and provision the overcloud hardware:
kayobe overcloud inventory discover
kayobe overcloud hardware inspect
kayobe overcloud provision
kayobe overcloud host configure
kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/cephadm.yml
kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/cephadm-gather-keys.yml
exit 0
