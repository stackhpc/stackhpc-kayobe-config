#!/bin/bash

BASE_PATH=~
VENV_DIR=$BASE_PATH/venvs/ansible
cd $BASE_PATH/src/
[[ -d openstack-network-config ]] || git clone https://github.com/stackhpc/openstack-config-multinode.git -b geneve openstack-network-config
cd openstack-network-config
if [[ ! -d $VENV_DIR ]]; then
    # Using virtualenv causes a strange bug with python3.6 where 
    # nested virtual env creation leads to envs without pip...
    # virtualenv $VENV_DIR
    python3 -m venv $VENV_DIR
fi

# NOTE: Virtualenv's activate and deactivate scripts reference an unbound variable. 
set +u
source $VENV_DIR/bin/activate
set -u

pip install -U pip
pip install -r requirements.txt
ansible-galaxy role install -p ansible/roles -r requirements.yml
ansible-galaxy collection install -p ansible/collections -r requirements.yml

source $BASE_PATH/src/kayobe-config/etc/kolla/public-openrc.sh

tools/openstack-config #Run script to configure openstack cloud