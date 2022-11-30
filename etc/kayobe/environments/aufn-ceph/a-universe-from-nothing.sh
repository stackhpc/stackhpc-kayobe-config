#!/bin/bash

###########################################
# STACKHPC-KAYOBE-CONFIG AUFN ENV VERSION #
###########################################

# Cheat script for a full deployment.
# This should be used for testing only.

# set -eu

BASE_PATH=~
KAYOBE_BRANCH=stackhpc/yoga
KAYOBE_CONFIG_BRANCH=yoga-aufn
KAYOBE_ENVIRONMENT=aufn-ceph

# FIXME: Work around lack of DNS on SMS lab.
PELICAN_HOST="10.0.0.34 pelican pelican.service.compute.sms-lab.cloud"
PULP_HOST="10.205.3.187 pulp-server pulp-server.internal.sms-cloud"
cat << EOF | sudo tee -a /etc/hosts
$PELICAN_HOST
$PULP_HOST
EOF

# # Install git and tmux.
# if $(which dnf 2>/dev/null >/dev/null); then
#     sudo dnf -y install git tmux python3-virtualenv
# else
#     sudo apt update
#     sudo apt -y install git tmux gcc libffi-dev python3-dev python-is-python3 python3-virtualenv
# fi

# # Disable the firewall.
# sudo systemctl is-enabled firewalld && sudo systemctl stop firewalld && sudo systemctl disable firewalld

# # Disable SELinux both immediately and permanently.
# if $(which setenforce 2>/dev/null >/dev/null); then
#     sudo setenforce 0
#     sudo sed -i 's/^SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
# fi

# # Prevent sudo from performing DNS queries.
# echo 'Defaults	!fqdn' | sudo tee /etc/sudoers.d/no-fqdn

# # Clone repositories
# cd $BASE_PATH
# mkdir -p src
# pushd src
# [[ -d kayobe ]] || git clone https://github.com/stackhpc/kayobe.git -b $KAYOBE_BRANCH
# [[ -d kayobe-config ]] || git clone https://github.com/stackhpc/stackhpc-kayobe-config kayobe-config -b $KAYOBE_CONFIG_BRANCH
# [[ -d kayobe/tenks ]] || (cd kayobe && git clone https://opendev.org/openstack/tenks.git)
# popd

# Create Kayobe virtualenv
# mkdir -p venvs
# pushd venvs
# if [[ ! -d kayobe ]]; then
#     virtualenv kayobe
# fi
# # NOTE: Virtualenv's activate and deactivate scripts reference an
# # unbound variable. 
# set +u
# source kayobe/bin/activate
# set -u
# pip install -U pip
# pip install ../src/kayobe
# popd

# # Activate environment
# pushd $BASE_PATH/src/kayobe-config
# source kayobe-env --environment $KAYOBE_ENVIRONMENT

# Configure host networking (bridge, routes & firewall)
# $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/configure-local-networking.sh

# # Bootstrap the Ansible control host.
# kayobe control host bootstrap

# # Configure the seed hypervisor host.
# kayobe seed hypervisor host configure

# # Provision the seed VM.
# kayobe seed vm provision

# # Configure the seed host, and deploy a local registry.
# kayobe seed host configure

# kayobe seed container image build bifrost_deploy

# # Deploy the seed services (including local pulp registry)
# kayobe seed service deploy -vvv #Doesn't work
# kayobe seed service deploy --tags seed-deploy-containers --kolla-tags none # Deploy local pulp server

# Deploying the seed restarts networking interface, run
# configure-local-networking.sh again to re-add routes.
# $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/configure-local-networking.sh


#######################################################################
# NEED TO ADD 10.205.3.187 pulp-server pulp-server.internal.sms-cloud 
# TO ETC/HOSTS OF DOCKER CONTAINER BEFORE SYNCING WITH UPSTEAM PULP
# - I'VE DONE THIS MANUALLY FOR NOW.
#######################################################################

# Add sms lab test pulp to /etc/hosts of seed vm's pulp container
SEED_IP=192.168.33.5
REMOTE_COMMAND="docker exec pulp sh -c 'echo $PULP_HOST | sudo tee -a /etc/hosts'"
ssh stack@$SEED_IP $REMOTE_COMMAND
# Check contents of hosts file was modified correctly
# echo -e "\nContents of /etc/hosts on pulp container:\n"
# ssh stack@$SEED_IP 'docker exec pulp cat /etc/hosts'
# echo


# Sync package & container repositories.
# kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp-repo-sync.yml -vvv &> _pulp_repo_sync.log
# kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp-repo-publish.yml -vvv &> _pulp_repo_publish.log
# kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp-container-sync.yml -vvv &> _pulp_container_sync.log
# kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp-container-publish.yml -vvv &> _pulp_container_publish.log

# Re-run full task to set up bifrost_deploy etc. using newly-populated pulp repo
# kayobe seed service deploy


# Deploying the seed restarts networking interface, run
# configure-local-networking.sh again to re-add routes.
# $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/configure-local-networking.sh


# NOTE: Make sure to use ./tenks, since just ‘tenks’ will install via PyPI.
# (export TENKS_CONFIG_PATH=$KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/tenks.yml && \
#  export KAYOBE_CONFIG_SOURCE_PATH=$BASE_PATH/src/kayobe-config && \
#  export KAYOBE_VENV_PATH=$BASE_PATH/venvs/kayobe && \
#  cd $BASE_PATH/src/kayobe && \.
#  ./dev/tenks-deploy-overcloud.sh ./tenks)
#  ./dev/tenks-teardown-overcloud.sh ./tenks)

# Inspect and provision the overcloud hardware:
# kayobe overcloud inventory discover
# kayobe overcloud hardware inspect
# kayobe overcloud provision
# kayobe overcloud host configure
# kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/cephadm.yml
# kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/cephadm-gather-keys.yml
# kayobe overcloud container image pull
# kayobe overcloud service deploy
# source $KOLLA_CONFIG_PATH/public-openrc.sh
# kayobe overcloud post configure
# source $KOLLA_CONFIG_PATH/public-openrc.sh


# $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/init-runonce.sh
# Use openstack-config-multinode here instead of init-runonce.sh

# (export KAYOBE_CONFIG_SOURCE_PATH=$BASE_PATH/src/kayobe-config && \
#  export KAYOBE_VENV_PATH=$BASE_PATH/venvs/kayobe && \
#  cd $BASE_PATH/src/kayobe && \
#  ./dev/overcloud-test-vm.sh)


