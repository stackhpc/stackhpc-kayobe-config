#!/bin/bash

set -eux

cat << EOF | sudo tee -a /etc/hosts
10.205.3.187 pulp-server pulp-server.internal.sms-cloud
EOF

BASE_PATH=~
KAYOBE_BRANCH=stackhpc/yoga
KAYOBE_CONFIG_BRANCH=stackhpc/yoga

if [[ ! -f $BASE_PATH/vault-pw ]]; then
    echo "Vault password file not found at $BASE_PATH/vault-pw"
    exit 1
fi

if type dnf; then
    sudo dnf -y install git python3-virtualenv
else
    sudo apt update
    sudo apt -y install gcc git libffi-dev python3-dev python-is-python3 python3-virtualenv
fi

cd $BASE_PATH
mkdir -p src
pushd src
[[ -d kayobe ]] || git clone https://github.com/stackhpc/kayobe.git -b $KAYOBE_BRANCH
[[ -d kayobe-config ]] || git clone https://github.com/stackhpc/stackhpc-kayobe-config kayobe-config -b $KAYOBE_CONFIG_BRANCH
popd

mkdir -p venvs
pushd venvs
if [[ ! -d kayobe ]]; then
    virtualenv kayobe
fi
# NOTE: Virtualenv's activate and deactivate scripts reference an
# unbound variable.
set +u
source kayobe/bin/activate
set -u
pip install -U pip
pip install ../src/kayobe
popd

if ! ip l show breth1 >/dev/null 2>&1; then
    sudo ip l add breth1 type bridge
fi
sudo ip l set breth1 up
if ! ip a show breth1 | grep 192.168.33.3/24; then
    sudo ip a add 192.168.33.3/24 dev breth1
fi
if ! ip l show dummy1 >/dev/null 2>&1; then
    sudo ip l add dummy1 type dummy
fi
sudo ip l set dummy1 up
sudo ip l set dummy1 master breth1

export KAYOBE_VAULT_PASSWORD=$(cat $BASE_PATH/vault-pw)
pushd $BASE_PATH/src/kayobe-config
source kayobe-env --environment ci-aio

kayobe control host bootstrap

kayobe overcloud host configure

kayobe overcloud service deploy

export KAYOBE_CONFIG_SOURCE_PATH=$BASE_PATH/src/kayobe-config
export KAYOBE_VENV_PATH=$BASE_PATH/venvs/kayobe
pushd $BASE_PATH/src/kayobe
./dev/overcloud-test-vm.sh
