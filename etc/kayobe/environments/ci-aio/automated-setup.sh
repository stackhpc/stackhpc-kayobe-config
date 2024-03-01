#!/bin/bash

set -eux

BASE_PATH=~
KAYOBE_BRANCH=stackhpc/zed
KAYOBE_CONFIG_BRANCH=stackhpc/zed
KAYOBE_AIO_LVM=true

if [[ ! -f $BASE_PATH/vault-pw ]]; then
    echo "Vault password file not found at $BASE_PATH/vault-pw"
    exit 1
fi

if sudo vgdisplay | grep -q lvm2; then
   sudo pvresize $(sudo pvs --noheadings | head -n 1 | awk '{print $1}')
   sudo lvextend -L 4G /dev/rootvg/lv_home -r || true
   sudo lvextend -L 4G /dev/rootvg/lv_tmp -r || true
elif $KAYOBE_AIO_LVM; then
   echo "This environment is only designed for LVM images. If possible, switch to an LVM image.
   To ignore this warning, set KAYOBE_AIO_LVM to false in this script."
   exit 1
fi

cat << EOF | sudo tee -a /etc/hosts
10.205.3.187 pulp-server pulp-server.internal.sms-cloud
EOF

if type dnf; then
    sudo dnf -y install git
else
    sudo apt update
    sudo apt -y install gcc git libffi-dev python3-dev python-is-python3 python3-venv
fi

cd $BASE_PATH
mkdir -p src
pushd src
[[ -d kayobe ]] || git clone https://github.com/stackhpc/kayobe.git -b $KAYOBE_BRANCH
[[ -d kayobe-config ]] || git clone https://github.com/stackhpc/stackhpc-kayobe-config kayobe-config -b $KAYOBE_CONFIG_BRANCH
popd

if ! sudo vgdisplay | grep -q lvm2; then
   rm $BASE_PATH/src/kayobe-config/etc/kayobe/environments/ci-aio/inventory/group_vars/controllers/lvm.yml
   sed -i -e '/controller_lvm_groups/,+2d' $BASE_PATH/src/kayobe-config/etc/kayobe/environments/ci-aio/controllers.yml
fi

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

kayobe playbook run etc/kayobe/ansible/growroot.yml etc/kayobe/ansible/purge-command-not-found.yml

kayobe overcloud host configure

kayobe overcloud service deploy

export KAYOBE_CONFIG_SOURCE_PATH=$BASE_PATH/src/kayobe-config
export KAYOBE_VENV_PATH=$BASE_PATH/venvs/kayobe
pushd $BASE_PATH/src/kayobe
./dev/overcloud-test-vm.sh
