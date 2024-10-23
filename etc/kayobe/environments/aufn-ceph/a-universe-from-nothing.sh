#!/bin/bash

###########################################
# STACKHPC-KAYOBE-CONFIG AUFN ENV VERSION #
###########################################

# Cheat script for a full deployment.
# This should be used for testing only.

set -eu

BASE_PATH=~
KAYOBE_BRANCH=stackhpc/2024.1
KAYOBE_CONFIG_BRANCH=stackhpc/2024.1
KAYOBE_ENVIRONMENT=aufn-ceph

# Install git and tmux.
if $(which dnf 2>/dev/null >/dev/null); then
    sudo dnf -y install git tmux
else
    sudo apt update
    sudo apt -y install git tmux gcc libffi-dev python3-dev python-is-python3
fi

# Disable the firewall.
sudo systemctl is-enabled firewalld && sudo systemctl stop firewalld && sudo systemctl disable firewalld

# Disable SELinux both immediately and permanently.
if $(which setenforce 2>/dev/null >/dev/null); then
    sudo setenforce 0
    sudo sed -i 's/^SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
fi

# Prevent sudo from performing DNS queries.
echo 'Defaults	!fqdn' | sudo tee /etc/sudoers.d/no-fqdn

# Clone repositories
cd $BASE_PATH
mkdir -p src
pushd src
[[ -d kayobe ]] || git clone https://github.com/stackhpc/kayobe.git -b $KAYOBE_BRANCH
[[ -d kayobe-config ]] || git clone https://github.com/stackhpc/stackhpc-kayobe-config kayobe-config -b $KAYOBE_CONFIG_BRANCH
[[ -d kayobe/tenks ]] || (cd kayobe && git clone https://opendev.org/openstack/tenks.git)
popd

# Create Kayobe virtualenv
mkdir -p venvs
pushd venvs
if [[ ! -d kayobe ]]; then
    python3 -m venv kayobe
fi
# NOTE: Virtualenv's activate and deactivate scripts reference an
# unbound variable. 
set +u
source kayobe/bin/activate
set -u
pip install -U pip
pip install ../src/kayobe
popd

# Activate environment
pushd $BASE_PATH/src/kayobe-config
source kayobe-env --environment $KAYOBE_ENVIRONMENT

# Configure host networking (bridge, routes & firewall)
$KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/configure-local-networking.sh

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
$KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/configure-local-networking.sh

# Sync package & container repositories.
kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp-repo-sync.yml
kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp-repo-publish.yml
kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp-container-sync.yml
kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp-container-publish.yml

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
kayobe overcloud container image pull
kayobe overcloud service deploy
source $KOLLA_CONFIG_PATH/public-openrc.sh
kayobe overcloud post configure
source $KOLLA_CONFIG_PATH/public-openrc.sh


# Use openstack-config-multinode here instead of init-runonce.sh script from standard aufn

#Deactivate current kayobe venv
set +u
deactivate
set -u
$KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/configure-openstack.sh $BASE_PATH

# Create a test vm 
VENV_DIR=$BASE_PATH/venvs/openstack
if [[ ! -d $VENV_DIR ]]; then
    python3 -m venv $VENV_DIR
fi
source $VENV_DIR/bin/activate
pip install -U pip
pip install python-openstackclient
source $KOLLA_CONFIG_PATH/public-openrc.sh
echo "Creating openstack key:"
openstack keypair create --public-key ~/.ssh/id_rsa.pub mykey
echo "Creating test vm:"
openstack server create --key-name mykey --flavor m1.tiny --image cirros --network admin-tenant test-vm-1
echo "Attaching floating IP:"
openstack floating ip create external
openstack server add floating ip test-vm-1 `openstack floating ip list -c ID  -f value`
echo -e "Done! \nopenstack server list:"
openstack server list
