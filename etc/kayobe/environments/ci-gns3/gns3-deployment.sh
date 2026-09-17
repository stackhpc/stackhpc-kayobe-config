#!/bin/bash

##########################################
# STACKHPC-KAYOBE-CONFIG ci-gns3 VERSION #
##########################################

# Script for a GNS3 deployment.

set -eux

BASE_PATH=~
KAYOBE_BRANCH=master
KAYOBE_CONFIG_REF=${KAYOBE_CONFIG_REF:-master}
KAYOBE_ENVIRONMENT=${KAYOBE_ENVIRONMENT:-ci-gns3}
KAYOBE_PATH=$BASE_PATH/src/kayobe
KAYOBE_CONFIG_ROOT=$BASE_PATH/src/kayobe-config
KAYOBE_CONFIG_PATH=$KAYOBE_CONFIG_ROOT/etc/kayobe
GNS3_ROLE_PATH=$BASE_PATH/gns3-ansible-role

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


# Create breth1 stuff
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

echo "BRIDGE AND DUMMY INTERFACES CREATED"

# Install dependencies
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
pushd "$KAYOBE_CONFIG_ROOT"
source kayobe-env --environment "$KAYOBE_ENVIRONMENT"

if [[ ! -d "$GNS3_ROLE_PATH" ]]; then
  git clone https://github.com/stackhpc/ansible-role-gns3.git "$GNS3_ROLE_PATH"
fi

cd "$GNS3_ROLE_PATH"

# Install GNS3
echo "RUNNING ANSIBLE PLAYBOOK TO INSTALL GNS3..."
ansible-playbook -i inventory.ini trialplaybook.yml -vvv
echo "GNS3 INSTALLED!"

mkdir -p "$KAYOBE_CONFIG_PATH/environments/ci-gns3/inventory/host_vars/"

# copy host_vars for switch to kayobe config
sudo cp "$GNS3_ROLE_PATH/roles/gns3/files/switch1" \
  "$KAYOBE_CONFIG_PATH/environments/ci-gns3/inventory/host_vars/switch1"

echo "SWITCH HOST_VARS COPIED"

cd "$KAYOBE_PATH"

kayobe control host bootstrap
kayobe physical network configure --group mgmt-switches