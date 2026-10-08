#!/bin/bash

##########################################
# STACKHPC-KAYOBE-CONFIG ci-gns3-ngs VERSION #
##########################################

# Script for a GNS3 deployment with NGS.

set -eux

BASE_PATH=~
KAYOBE_BRANCH=master
KAYOBE_CONFIG_REF=${KAYOBE_CONFIG_REF:-master}
KAYOBE_ENVIRONMENT=${KAYOBE_ENVIRONMENT:-ci-gns3-ngs}
KAYOBE_PATH=$BASE_PATH/src/kayobe
KAYOBE_CONFIG_ROOT=$BASE_PATH/src/kayobe-config
KAYOBE_CONFIG_PATH=$KAYOBE_CONFIG_ROOT/etc/kayobe
GNS3_ROLE_PATH=$BASE_PATH/gns3-ansible-role
TENKS_PATH=$KAYOBE_PATH/tenks


if [[ ! -f $BASE_PATH/vault-pw ]]; then
    echo "Vault password file not found at $BASE_PATH/vault-pw"
    exit 1
fi

set +x
export KAYOBE_VAULT_PASSWORD=$(cat $BASE_PATH/vault-pw)
set -x

echo "STARTING DEMO SCRIPT..."

cd "$BASE_PATH"
mkdir -p "$BASE_PATH/src"

# Clone repositories.
if [[ ! -d $KAYOBE_PATH ]]; then
  echo "CLONING KAYOBE REPO..."
  git clone https://github.com/openstack/kayobe.git "$KAYOBE_PATH" -b "$KAYOBE_BRANCH"
  echo "KAYOBE REPO CLONED"
fi

if [[ ! -d $KAYOBE_CONFIG_ROOT ]]; then
  echo "CLONING KAYOBE CONFIG REPO..."
  git clone https://github.com/stackhpc/stackhpc-kayobe-config \
    "$KAYOBE_CONFIG_ROOT"
  (
    cd "$KAYOBE_CONFIG_ROOT"
    git checkout "$KAYOBE_CONFIG_REF"
  )
  echo "KAYOBE CONFIG REPO CLONED"
fi


# Create required interfaces
echo "CREATING BRIDGE AND DUMMY INTERFACES..."
if ! ip l show breth1 >/dev/null 2>&1; then
  sudo ip l add breth1 type bridge
fi
sudo ip l set breth1 up
if ! ip a show breth1 | grep -q '192.168.33.3/24'; then
  sudo ip a add 192.168.33.3/24 dev breth1
fi
if ! ip l show dummy1 >/dev/null 2>&1; then
  sudo ip l add dummy1 type dummy
fi
sudo ip l set dummy1 up
sudo ip l set dummy1 master breth1

echo "BRIDGE AND DUMMY INTERFACES CREATED"# Install dependencies
if type dnf > /dev/null 2>&1; then
    sudo dnf -y install git python3.12
else
    sudo apt update
    sudo apt -y install gcc git libffi-dev python3.12-dev python-is-python3 python3.12-venv
fi


# Create Kayobe virtualenv
mkdir -p "$BASE_PATH/venvs"
pushd "$BASE_PATH/venvs"
if [[ ! -d kayobe ]]; then
    python3.12 -m venv kayobe
fi
# NOTE: Virtualenv's activate and deactivate scripts reference an
# unbound variable.
set +u
source kayobe/bin/activate
set -u
pip install -U pip
pip install -r "$KAYOBE_CONFIG_ROOT/requirements.txt"
popd


# Activate environment
cd "$KAYOBE_CONFIG_ROOT"
source kayobe-env --environment "$KAYOBE_ENVIRONMENT"

if [[ ! -d "$GNS3_ROLE_PATH" ]]; then
  git clone https://github.com/stackhpc/ansible-role-gns3.git "$GNS3_ROLE_PATH"
fi

export KAYOBE_CONFIG_SOURCE_PATH="$KAYOBE_CONFIG_ROOT"
export KAYOBE_VENV_PATH="$BASE_PATH/venvs/kayobe"

# write the ubuntu user's ssh key to its own authorized_keys file.
sudo ssh-keygen -t rsa -N "" -f /home/ubuntu/.ssh/id_rsa
ssh_key=$(sudo cat /home/ubuntu/.ssh/id_rsa.pub)
sudo touch /home/ubuntu/.ssh/authorized_keys
sudo echo "$ssh_key" > /home/ubuntu/.ssh/authorized_keys

# Bootstrap the Ansible control host.
kayobe control host bootstrap

# Configure the overcloud host.
kayobe overcloud host configure

# Deploy the overcloud services
kayobe overcloud service deploy

#Tenks install
echo "INSTALLING TENKS..."
if [[ ! -d "$TENKS_PATH" ]]; then
  git clone https://opendev.org/openstack/tenks.git "$TENKS_PATH"
fi
./dev/tenks-deploy-compute.sh "$TENKS_PATH"

# make new bridge for gns3
echo "CREATING GNS3 BRIDGE..."
sudo ovs-vsctl del-port p-tk00-0-ovs
sudo ip l add brgns3 type bridge
sudo ip l set brgns3 up
sudo ip link set dev p-tk00-0-ovs master brgns3

mkdir -p "$KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/inventory/host_vars/"

cd "$GNS3_ROLE_PATH"

# run gns3 role
ansible-playbook -i inventory.ini $KAYOBE_CONFIG_ROOT/ansible/tests/gns3-ngs.yml -e gns3_ansible_host_vars_dir=$KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/inventory/host_vars -vvv

source "$KAYOBE_CONFIG_ROOT/kayobe-env"
pip install -e "$KAYOBE_PATH"

cd "$KAYOBE_PATH"

./dev/overcloud-init.sh

kayobe overcloud service deploy

kayobe overcloud host configure

# install openstack clients

pip install python-openstackclient
pip install python-ironicclient
source "$KAYOBE_CONFIG_ROOT/etc/kolla/public-openrc.sh"

# Delete demo-router if it exists, provision-net and remake provision-net as vlan type
if openstack router list | grep demo-router; then
  echo "demo-router exists, deleting it..."
  while read -r demo_router_port; do
    if ! openstack router remove port demo-router "$demo_router_port"; then
      echo "WARNING: failed to remove port $demo_router_port from demo-router; continuing..." >&2
    fi
  done < <(openstack port list --router demo-router -f value -c ID)
  openstack router delete demo-router
fi
openstack network delete provision-net

# Generate new provision-net using post configure
kayobe overcloud post configure

# Restart nova_libvirt if docker container is unhealthy
if  sudo docker ps | grep nova_libvirt | grep unhealthy; then
  echo "nova_libvirt container is unhealthy, restarting it..."
  sudo docker restart nova_libvirt
  sleep 180 # wait for nova_libvirt to restart
fi

# Set maintenance mode for baremetal nodes

openstack baremetal node maintenance set red0
openstack baremetal node maintenance set tk0
openstack baremetal node maintenance set tk1


# get switch mac address from host vars file, is like this switch_facts_mac: "{{ switch.mac_address }}"
switch_mac=$(grep switch_facts_mac "$KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/inventory/host_vars/switch1" | awk '{print $2}')

# Configure tk0 to connect to GNS3
baremetal_port_uuid=$(openstack baremetal port list --node tk0 -f value -c uuid)
openstack baremetal port set  --local-link-connection port_id="Eth 1/1/2" $baremetal_port_uuid
openstack baremetal port set  --local-link-connection switch_id="$switch_mac" $baremetal_port_uuid
openstack baremetal node set --network-interface neutron tk0
openstack baremetal node maintenance unset tk0

# # Create router for .33 and .34
openstack router create provision-router

openstack router add subnet provision-router provision-net
openstack router add subnet provision-router cleaning-net

# Check tk0 is in state available before running test script
tk0_state=$(openstack baremetal node show tk0 -f value -c provision_state)
if [ "$tk0_state" != "available" ]; then
  echo "ERROR: tk0 is not in state 'available', it is in state '$tk0_state'. Please check the node and try again." >&2
  exit 1
fi
# Run test baremetal script
./dev/overcloud-test-baremetal.sh