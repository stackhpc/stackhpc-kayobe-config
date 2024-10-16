#!/bin/bash

set -euE
set -o pipefail

PARENT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KAYOBE_AUTOMATION_DIR="$(realpath "${PARENT}/../../.automation")"

function main {
	if [ "${PULP_DO_CONTAINER_SYNC:-}" = true ]; then
		${KAYOBE_AUTOMATION_DIR}/scripts/playbook-run.sh '$KAYOBE_CONFIG_PATH/ansible/pulp-container-sync.yml' -e stackhpc_pulp_images_kolla_filter="${PULP_KOLLA_FILTER:-}"
	fi
	if [ "${PULP_DO_CONTAINER_PUBLISH:-}" = true ]; then
		${KAYOBE_AUTOMATION_DIR}/scripts/playbook-run.sh '$KAYOBE_CONFIG_PATH/ansible/pulp-container-publish.yml' -e stackhpc_pulp_images_kolla_filter="${PULP_KOLLA_FILTER:-}"
	fi
	if [ "${PULP_DO_REPO_SYNC:-}" = true ]; then
		${KAYOBE_AUTOMATION_DIR}/scripts/playbook-run.sh '$KAYOBE_CONFIG_PATH/ansible/pulp-repo-sync.yml'
	fi
	if [ "${PULP_DO_REPO_PUBLISH:-}" = true ]; then
		${KAYOBE_AUTOMATION_DIR}/scripts/playbook-run.sh '$KAYOBE_CONFIG_PATH/ansible/pulp-repo-publish.yml'
	fi
	if [ "${PULP_DO_REPO_PROMOTE:-}" = true ]; then
		${KAYOBE_AUTOMATION_DIR}/scripts/playbook-run.sh '$KAYOBE_CONFIG_PATH/ansible/pulp-repo-promote-production.yml'
	fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main
fi
