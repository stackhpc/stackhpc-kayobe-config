#!/bin/bash

# Script to determine the new directory of a playbook based on its name.

# Check if an argument is provided
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <playbook-name>"
    exit 1
fi

PLAYBOOK_NAME="$1"

# Arrays for specific cases
PULP_PLAYBOOKS=(
    "pulp-amphora-image-download.yml"
    "pulp-artifact-promote.yml"
    "pulp-artifact-upload.yml"
    "pulp-auth-proxy.yml"
    "pulp-container-publish.yml"
    "pulp-container-sync.yml"
    "pulp-host-image-download.yml"
    "pulp-repo-promote-production.yml"
    "pulp-repo-publish.yml"
    "pulp-repo-sync.yml"
    "pulp-sync-publish-promote.yml"
)
CEPH_PLAYBOOKS=(
    "ceph-enter-maintenance.yml"
    "ceph-exit-maintenance.yml"
    "cephadm-commands-post.yml"
    "cephadm-commands-pre.yml"
    "cephadm-crush-rules.yml"
    "cephadm-deploy.yml"
    "cephadm-ec-profiles.yml"
    "cephadm-gather-keys.yml"
    "cephadm-keys.yml"
    "cephadm-pools.yml"
    "cephadm.yml"
)
SECRET_STORE_PLAYBOOKS=(
    "secret-store-deploy-barbican.yml"
    "secret-store-deploy-overcloud.yml"
    "secret-store-deploy-seed.yml"
    "secret-store-generate-backend-tls.yml"
    "secret-store-generate-internal-tls.yml"
    "secret-store-generate-test-external-tls.yml"
    "secret-store-unseal-overcloud.yml"
    "secret-store-unseal-seed.yml"
)

FIXES_PLAYBOOKS=(
    "fix-grub-rl9.yml"
    "fix-hostname.yml"
    "fix-houston.yml"
    "fix-networking.yml"
    "hotfix-containers.yml"
    "ovn-fix-chassis-priorities.yml"
    "purge-command-not-found.yml"
    "rabbitmq-reset.yml"
    "run-container-hotfix.yml"
)
DEPLOYMENT_PLAYBOOKS=(
    "deploy-github-runner.yml"
    "deploy-gitlab-runner.yml"
    "deploy-openbao-kayobe-automation.yml"
    "deploy-os-capacity-exporter.yml"
    "deploy-radosgw-usage-exporter.yml"
    "get-nvme-drives.yml"
    "smartmon-tools.yml"
    "wazuh-agent.yml"
    "wazuh-manager.yml"
    "wazuh-secrets.yml"
    "write-github-workflows.yml"
    "write-gitlab-pipelines.yml"
)
MAINTENANCE_PLAYBOOKS=(
    "cis.yml"
    "nova-compute-disable.yml"
    "nova-compute-drain.yml"
    "nova-compute-enable.yml"
    "octavia-amphora-image-build.yml"
    "octavia-amphora-image-register.yml"
    "pci-passthrough.yml"
    "reboot.yml"
    "rekey-hosts.yml"
    "reset-bls-entries.yml"
    "stop-openstack-services.yml"
    "ubuntu-upgrade.yml"
)
TOOLS_PLAYBOOKS=(
    "advise-run.yml"
    "build-ofed-rocky.yml"
    "check-kayobe-version.yml"
    "check-kolla-ansible-version.yml"
    "check-kolla-images-py.yml"
    "check-tags.yml"
    "configure-aio-resources.yml"
    "configure-vxlan.yml"
    "diagnostics.yml"
    "docker-registry-login.yml"
    "firewalld-watchdog.yml"
    "get-cloud-facts.yml"
    "growroot.yml"
    "install-doca.yml"
    "install-pre-commit-hooks.yml"
    "openstack-host-image-upload.yml"
    "prometheus-network-names.yml"
    "prometheus.yml.j2"
    "push-ofed.yml"
    "rsyslog.yml"
    "stackhpc-cloud-tests.yml"
)


# Match name
if [[ " ${PULP_PLAYBOOKS[*]} " =~ [[:space:]]$PLAYBOOK_NAME[[:space:]] ]]; then
    echo "pulp/"
elif [[ " ${CEPH_PLAYBOOKS[*]} " =~ [[:space:]]$PLAYBOOK_NAME[[:space:]] ]]; then
    echo "ceph/"
elif [[ " ${SECRET_STORE_PLAYBOOKS[*]} " =~ [[:space:]]$PLAYBOOK_NAME[[:space:]] ]]; then
    echo "secret-store/"
elif [[ " ${FIXES_PLAYBOOKS[*]} " =~ [[:space:]]$PLAYBOOK_NAME[[:space:]] ]]; then
    echo "fixes/"
elif [[ " ${DEPLOYMENT_PLAYBOOKS[*]} " =~ [[:space:]]$PLAYBOOK_NAME[[:space:]] ]]; then
    echo "deployment/"
elif [[ " ${MAINTENANCE_PLAYBOOKS[*]} " =~ [[:space:]]$PLAYBOOK_NAME[[:space:]] ]]; then
    echo "maintenance/"
elif [[ " ${TOOLS_PLAYBOOKS[*]} " =~ [[:space:]]$PLAYBOOK_NAME[[:space:]] ]]; then
    echo "tools/"
else
    echo "Error: Unknown playbook name '$PLAYBOOK_NAME'" >&2
    exit 1
fi
