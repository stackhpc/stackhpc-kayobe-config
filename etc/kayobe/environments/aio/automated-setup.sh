#!/bin/bash

BASE_PATH=~
OPENSTACK_RELEASE=2025.1
KAYOBE_BRANCH=stackhpc/$OPENSTACK_RELEASE
KAYOBE_CONFIG_BRANCH=stackhpc/$OPENSTACK_RELEASE
KAYOBE_AIO_LVM=true
KAYOBE_CONFIG_EDIT_PAUSE=false
AIO_RUN_TEMPEST=false
USE_OVS=false

# NOTE(Alex-Welsh): These values should not be changed unless you are sure you
# know what you are doing.
ARK_USERNAME_FILE=~/release_pulp_username
ARK_PASSWORD_FILE=~/release_pulp_password

# Error handling function
error_exit() {
    echo "[ERROR] $*"
    exit 1
}

# Ensure Ark credentials exist and are valid
check_ark_credentials() {
    if [[ ! -f "$ARK_USERNAME_FILE" ]]; then
        error_exit "Release pulp username file not found at $ARK_USERNAME_FILE"
    fi

    if [[ ! -f "$ARK_PASSWORD_FILE" ]]; then
        error_exit "Release pulp password file not found at $ARK_PASSWORD_FILE"
    fi

    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -u "$(cat $ARK_USERNAME_FILE):$(cat $ARK_PASSWORD_FILE)" https://ark.stackhpc.com/pulp/api/v3/users/)

    # Status is 200 if user exists and has permission
    # Status is 403 if user exists but does not have permission
    if [[ "$HTTP_STATUS" != "200" && "$HTTP_STATUS" != "403" ]]; then
        error_exit "Pulp credentials are not valid (HTTP Status: $HTTP_STATUS)"
    fi
}

# Ensure LVs are a minimum size. They will be extended during
# host-configure, but need enough space to install kayobe first
configure_lvm() {
    if sudo vgdisplay | grep -q lvm2; then
        echo "Resizing LVM volumes..."
        sudo pvresize "$(sudo pvs --noheadings | head -n 1 | awk '{print $1}')"
        sudo lvextend -L 4G /dev/rootvg/lv_home -r || true
        sudo lvextend -L 4G /dev/rootvg/lv_tmp -r || true
    elif [[ "$KAYOBE_AIO_LVM" == true ]]; then
        error_exit "This environment is designed for images using the default StackHPC LVM layout. Set KAYOBE_AIO_LVM to false to ignore this warning."
    fi
}

# Install package dependencies
install_dependencies() {
    echo "Installing dependencies..."
    if type dnf > /dev/null 2>&1; then
        sudo dnf -y install git python3.12
    else
        sudo apt update
        sudo apt -y install gcc git libffi-dev python3.12-dev python-is-python3 python3.12-venv
    fi
}

# Clone source repositories
clone_repositories() {
    echo "Cloning repositories..."
    mkdir -p "$BASE_PATH/src"
    pushd "$BASE_PATH/src"
    # NOTE: Kayobe isn't used for deploying the AIO, but it is used for
    # running the overcloud test VM script. TODO: run installed version
    [[ -d kayobe ]] || git clone https://github.com/stackhpc/kayobe.git -b "$KAYOBE_BRANCH"
    [[ -d kayobe-config ]] || git clone https://github.com/stackhpc/stackhpc-kayobe-config kayobe-config -b "$KAYOBE_CONFIG_BRANCH"
    popd
}

# Pause for configuration editing if requested
pause_for_configuration() {
    if [[ "$KAYOBE_CONFIG_EDIT_PAUSE" == true ]]; then
        echo "Deployment is paused, edit configuration in another terminal"
        echo "Press enter to continue"
        read -rs
    fi
}

# Disable OVN if requested (aka deploy OVS)
disable_ovn() {
    if [[ "$USE_OVS" == true ]]; then
        echo "Disabling OVN..."
        echo "kolla_enable_ovn: false" > "$BASE_PATH/src/kayobe-config/etc/kayobe/environments/aio/disable-ovn.yml"
    fi
}

# Remove LVM configuration if not using LVM
remove_lvm_configuration() {
    if ! sudo vgdisplay | grep -q lvm2; then
        if [[ "$KAYOBE_AIO_LVM" == true ]]; then
            error_exit "You have KAYOBE_AIO_LVM set to true, but LVM has not been found on this system. Set KAYOBE_AIO_LVM to false to ignore this warning."
        fi
        echo "Removing LVM configuration..."
        rm -f "$BASE_PATH/src/kayobe-config/etc/kayobe/environments/aio/inventory/group_vars/controllers/lvm.yml" || true
        sed -i -e '/controller_lvm_groups/,+2d' "$BASE_PATH/src/kayobe-config/etc/kayobe/environments/aio/controllers.yml" || true
    fi
}

# Set up Python virtual environment for Kayobe
setup_virtualenv() {
    echo "Setting up Python virtual environment..."
    mkdir -p "$BASE_PATH/venvs"
    pushd "$BASE_PATH/venvs"
    if [[ ! -d kayobe ]]; then
        python3.12 -m venv kayobe
    fi
    source kayobe/bin/activate
    pip install -U pip
    pip install -r "$BASE_PATH/src/kayobe-config/requirements.txt"
    deactivate
    popd
}

# AIO networking setup
configure_network() {
    echo "Configuring network..."
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
}

# Helper function to activate the Kayobe environment
activate_kayobe_env() {
    pushd "$BASE_PATH/src/kayobe-config"
    source kayobe-env --environment aio
    source $BASE_PATH/venvs/kayobe/bin/activate
    set -x
}

# Run Kayobe control host bootstrap
kayobe_control_host_bootstrap() {
    echo "Running Kayobe control host bootstrap..."
    activate_kayobe_env
    kayobe control host bootstrap
    set +x
    deactivate
}

# Run initialisation playbooks
kayobe_run_init_playbooks() {
    echo "Running Kayobe playbooks..."
    activate_kayobe_env
    kayobe playbook run etc/kayobe/ansible/tools/growroot.yml etc/kayobe/ansible/fixes/purge-command-not-found.yml
    set +x
    deactivate
}

# Run Kayobe overcloud host configure
kayobe_overcloud_host_configure() {
    echo "Running Kayobe overcloud host configure..."
    activate_kayobe_env
    kayobe overcloud host configure
    set +x
    deactivate
}

# Run Kayobe overcloud service deployment
kayobe_overcloud_service_deploy() {
    echo "Running Kayobe overcloud service deploy..."
    activate_kayobe_env
    kayobe overcloud service deploy
    set +x
    deactivate
}

# Run Kayobe overcloud test VM script
kayobe_test_overcloud_vm() {
    echo "Running Kayobe overcloud test VM script..."
    export KAYOBE_CONFIG_SOURCE_PATH="$BASE_PATH/src/kayobe-config"
    export KAYOBE_VENV_PATH="$BASE_PATH/venvs/kayobe"
    activate_kayobe_env
    pushd "$BASE_PATH/src/kayobe"
    ./dev/overcloud-test-vm.sh
    popd
    set +x
    deactivate
}

# Run all Kayobe commands in sequence
run_kayobe_commands() {
    echo "Running Kayobe commands..."
    kayobe_control_host_bootstrap
    kayobe_run_init_playbooks
    kayobe_overcloud_host_configure
    kayobe_overcloud_service_deploy
    kayobe_test_overcloud_vm
}

# Run Tempest tests
run_tempest() {
    echo "Running Tempest tests..."
    if type apt > /dev/null 2>&1; then
        sudo apt install -y docker-buildx-plugin
    fi

    pushd "$BASE_PATH/src/kayobe-config"
    git submodule init
    git submodule update

    if ! sudo docker image inspect kayobe:latest > /dev/null 2>&1; then
        echo "Building Kayobe Automation image"
        sudo DOCKER_BUILDKIT=1 docker build \
        --build-arg BASE_IMAGE=rockylinux/rockylinux:9 \
        --build-arg USE_PYTHON_312=true \
        --file .automation/docker/kayobe/Dockerfile \
        --tag kayobe:latest \
        --network host .
    else
        echo "Kayobe Automation image already exists. Skipping build."
    fi

    KAYOBE_AUTOMATION_SSH_PRIVATE_KEY=$(cat ~/.ssh/id_rsa)
    export KAYOBE_AUTOMATION_SSH_PRIVATE_KEY
    mkdir -p tempest-artifacts
    
    activate_kayobe_env
    sudo -E docker run \
        --name kayobe-automation \
        --detach -it --rm \
        --network host \
        -v "$(pwd)":/stack/kayobe-automation-env/src/kayobe-config \
        -v "$(pwd)"/tempest-artifacts:/stack/tempest-artifacts \
        -e KAYOBE_ENVIRONMENT \
        -e KAYOBE_AUTOMATION_SSH_PRIVATE_KEY \
        kayobe:latest \
        /stack/kayobe-automation-env/src/kayobe-config/.automation/pipeline/tempest.sh \
        -e ansible_user=stack
    
    deactivate
    echo "Sleeping for 5 minutes to allow Tempest to begin"
    sleep 300
    sudo docker logs -f tempest
    set +x
    popd
}

# Generate a Kayobe environment script for quick dev access
generate_kayobe_env_script() {

cat > $BASE_PATH/kayobe-env.sh <<EOF

source $BASE_PATH/src/kayobe-config/kayobe-env --environment aio
source $BASE_PATH/venvs/kayobe/bin/activate

EOF
}

# Generate an OpenStack environment script for quick dev access
generate_openstack_env_script() {

python3 -m venv $BASE_PATH/venvs/openstack
$BASE_PATH/venvs/openstack/bin/pip install -U pip
$BASE_PATH/venvs/openstack/bin/pip install -U python-openstackclient -c https://raw.githubusercontent.com/stackhpc/requirements/refs/heads/stackhpc/$OPENSTACK_RELEASE/upper-constraints.txt
cat > $BASE_PATH/openstack-env.sh <<EOF

source $BASE_PATH/venvs/openstack/bin/activate
source $BASE_PATH/src/kayobe-config/etc/kolla/public-openrc.sh

EOF
}

# Run all deployment prerequisites
run_deploy_prereqs() {
    check_ark_credentials
    configure_lvm
    install_dependencies
    clone_repositories
    disable_ovn
    pause_for_configuration
    remove_lvm_configuration
    setup_virtualenv
    configure_network
}

# End-to-end deployment
deploy_full() {
    run_deploy_prereqs
    generate_kayobe_env_script
    run_kayobe_commands
    if [[ "$AIO_RUN_TEMPEST" == true ]]; then
        run_tempest
    fi
    generate_openstack_env_script
    echo "Automated setup completed successfully."

}

help() {
    set +x

    echo "Usage: $0 <command>"
    echo
    echo "Commands:"
    echo "  help"
    echo "  deploy_full"
    echo "  run_deploy_prereqs"
    echo "  kayobe_control_host_bootstrap"
    echo "  kayobe_overcloud_host_configure"
    echo "  kayobe_overcloud_service_deploy"
    echo "  generate_kayobe_env_script"
    echo "  generate_openstack_env_script"
    echo "  run_kayobe_commands"
    echo "  run_tempest"
}

main() {
    set -eu

    if [[ $# -eq 0 ]]; then
        help
        error_exit "No arguments provided. Please specify a command."
    else
        for arg in "$@"; do
            case $arg in
                help) help ;;
                deploy_full) deploy_full ;;
                run_deploy_prereqs) run_deploy_prereqs ;;
                configure_network) configure_network ;;
                kayobe_control_host_bootstrap) kayobe_control_host_bootstrap ;;
                kayobe_overcloud_host_configure) kayobe_overcloud_host_configure ;;
                kayobe_overcloud_service_deploy) kayobe_overcloud_service_deploy ;;
                generate_kayobe_env_script) generate_kayobe_env_script ;;
                generate_openstack_env_script) generate_openstack_env_script ;;
                run_kayobe_commands) run_kayobe_commands ;;
                run_tempest) run_tempest ;;
                *) help && error_exit "Unknown argument: $arg" ;;
            esac
        done
    fi
}

main "$@"
