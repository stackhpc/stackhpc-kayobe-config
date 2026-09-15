
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
KAYOBE_PATH=$BASE_PATH/kayobe
KAYOBE_CONFIG_PATH=$KAYOBE_PATH/config/src/kayobe-config
GNS3_ROLE_PATH=$BASE_PATH/gns3-ansible-role

echo "STARTING DEMO SCRIPT..."

# Clone repositories.
if [[ ! -d $KAYOBE_PATH ]]; then
  echo "CLONING KAYOBE REPO..."
  git clone https://github.com/openstack/kayobe.git "$KAYOBE_PATH" -b "$KAYOBE_BRANCH"
  echo "KAYOBE REPO CLONED"
fi

mkdir -p "$KAYOBE_PATH/config/src"
if [[ ! -d $KAYOBE_CONFIG_PATH ]]; then
  echo "CLONING KAYOBE CONFIG REPO..."
  git clone https://opendev.org/openstack/kayobe-config-dev.git \
    "$KAYOBE_CONFIG_PATH" -b "$KAYOBE_CONFIG_REF"
  echo "KAYOBE CONFIG REPO CLONED"
fi


# Create breth1 stuff
echo "CREATING BRIDGE AND DUMMY INTERFACES..."
sudo ip l add breth1 type bridge
sudo ip l set breth1 up
sudo ip a add 192.168.33.3/24 dev breth1
sudo ip l add dummy1 type dummy
sudo ip l set dummy1 up
sudo ip l set dummy1 master breth1

echo "BRIDGE AND DUMMY INTERFACES CREATED"

# Install kayobe dev environment
echo "INSTALLING KAYOBE DEV ENVIRONMENT..."
(cd "$KAYOBE_PATH" && ./dev/install-dev.sh)

echo "KAYOBE DEV ENVIRONMENT INSTALLED"


# Environment setup

echo "SETTING UP ENVIRONMENT..."
source ~/kayobe-venv/bin/activate

cd "$GNS3_ROLE_PATH"

# Install GNS3
echo "RUNNING ANSIBLE PLAYBOOK TO INSTALL GNS3..."
ansible-playbook -i inventory.ini trialplaybook.yml -vvv
echo "GNS3 INSTALLED!"

# copy host_vars for switch to kayobe config
sudo cp "$GNS3_ROLE_PATH/roles/gns3/files/switch1" \
  "$KAYOBE_CONFIG_PATH/etc/kayobe/inventory/host_vars/switch1"

echo "SWITCH HOST_VARS COPIED"

groups_file=$KAYOBE_CONFIG_PATH/etc/kayobe/inventory/groups
host="switch1"
if ! awk '/^\[mgmt-switches\]/{flag=1;next}/^\[/{flag=0} flag && $0 == "'"$host"'"' "$groups_file" | grep -q "$host"; then
    sed -i "/^\[mgmt-switches\]$/a ${host}" "$groups_file"
fi
echo "SWITCH GROUP_VARS COPIED"


cd "$KAYOBE_PATH"

source "$KAYOBE_CONFIG_PATH/kayobe-env" --environment "$KAYOBE_ENVIRONMENT"
pip install -e "$KAYOBE_PATH"

kayobe control host bootstrap
kayobe physical network configure --group mgmt-switches