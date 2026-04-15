
#!/bin/bash

###########################################
# STACKHPC-KAYOBE-CONFIG ci-tenks VERSION #
###########################################

# Script for a full deployment.

set -eux

BASE_PATH=~
KAYOBE_BRANCH=stackhpc/2025.1
KAYOBE_CONFIG_REF=${KAYOBE_CONFIG_REF:-stackhpc/2025.1}
KAYOBE_ENVIRONMENT=${KAYOBE_ENVIRONMENT:-ci-tenks}

if [[ ! -f $BASE_PATH/vault-pw ]]; then
    echo "Vault password file not found at $BASE_PATH/vault-pw"
    exit 1
fi

set +x
export KAYOBE_VAULT_PASSWORD=$(cat $BASE_PATH/vault-pw)
set -x

# Install git and tmux.
if $(which dnf 2>/dev/null >/dev/null); then
    sudo dnf -y install git tmux python3.12
else
    sudo apt update
    sudo apt -y install git tmux gcc libffi-dev python3-dev python-is-python3 python3-pip python3.12-venv
fi

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
if [[ ! -d kayobe-config ]]; then
    git clone https://github.com/stackhpc/stackhpc-kayobe-config kayobe-config
    pushd kayobe-config
    git checkout $KAYOBE_CONFIG_REF
    popd
fi
[[ -d kayobe ]] || git clone https://github.com/stackhpc/kayobe.git -b $KAYOBE_BRANCH
[[ -d kayobe/tenks ]] || (cd kayobe && git clone https://opendev.org/openstack/tenks.git)
popd

# Create Kayobe virtualenv
mkdir -p venvs
pushd venvs
if [[ ! -d kayobe ]]; then
    python3.12 -m venv kayobe
fi
# NOTE: Virtualenv's activate and deactivate scripts reference an
# unbound variable.
set +u
source kayobe/bin/activate
set -u
pip install -U pip
pip install -r ../src/kayobe-config/requirements.txt
popd

# Activate environment
pushd $BASE_PATH/src/kayobe-config
source kayobe-env --environment $KAYOBE_ENVIRONMENT

# Configure host networking (bridge, routes & firewall)
sudo $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/configure-local-networking.sh

# Bootstrap the Ansible control host.
kayobe control host bootstrap

# Write interface details to Kayobe configuration. These are required for host configure.
export ADMIN_IFACE=$(ip -4 route show default | awk '{for(i=1;i<NF;i++) if($i=="dev") {print $(i+1); exit}}')
cat << EOF >> $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/inventory/group_vars/seed-hypervisor/network-interfaces
admin_interface: $ADMIN_IFACE
EOF

export ADMIN_IP=$(ip -4 addr show dev "$ADMIN_IFACE" | awk '$1 == "inet" {split($2, a, "/"); print a[1]; exit}')
cat << EOF >> $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/network-allocation.yml
admin_ips:
  seed-hypervisor: $ADMIN_IP
EOF

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
# FIXME: repo sync playbook takes around 30 minutes (tested on ubuntu).
# for now we should skip it and just get to provisioning. Once we have a local
# package mirror, we can probably add it back in and at least get to host
# configuration.
#kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp/pulp-repo-sync.yml
#kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp/pulp-repo-publish.yml
kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp/pulp-container-sync.yml -e stackhpc_pulp_images_kolla_filter=bifrost
kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp/pulp-container-publish.yml -e stackhpc_pulp_images_kolla_filter=bifrost

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
