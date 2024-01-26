# This file is used to configure kayobe-automation.
# https://github.com/stackhpc/kayobe-automation/blob/main/README.md

# See: https://github.com/stackhpc/docker-rally/blob/master/bin/rally-verify-wrapper.sh for a full list of tempest parameters that can be overriden.
# You can override tempest parameters like so:
export TEMPEST_CONCURRENCY=2
# Specify single test whilst experimenting
export TEMPEST_PATTERN="${TEMPEST_PATTERN:-tempest.api.compute.volumes.test_attach_volume.AttachVolumeTestJSON.test_attach_detach_volume}"

if [ ! -z ${KAYOBE_ENVIRONMENT:+x} ]; then
  KAYOBE_AUTOMATION_TEMPEST_CONF_OVERRIDES="${KAYOBE_AUTOMATION_CONFIG_PATH}/tempest/tempest-${KAYOBE_ENVIRONMENT}-${KAYOBE_AUTOMATION_TEMPEST_LOADLIST:-}.overrides.conf"

  # Check if loadlist specific overrides exist, if not fallback to environment overrides.
  if [ ! -e "${KAYOBE_AUTOMATION_TEMPEST_CONF_OVERRIDES}" ]; then
      KAYOBE_AUTOMATION_TEMPEST_CONF_OVERRIDES="${KAYOBE_AUTOMATION_CONFIG_PATH}/tempest/tempest-${KAYOBE_ENVIRONMENT}.overrides.conf"
  fi

  if [[ "$KAYOBE_ENVIRONMENT" =~ "aio" ]]; then
    # Seem to get servers failing to spawn with higher concurrency
    export TEMPEST_CONCURRENCY=1
  fi

  if [[ "$KAYOBE_ENVIRONMENT" =~ "ci-multinode" ]]; then
    # SMSLab is currently running with 1G switches. This causes tests using volumes and images to fail if
    # the concurrency is set too high.
    export TEMPEST_CONCURRENCY=1
    #export KAYOBE_AUTOMATION_TEMPEST_LOADLIST=tempest-full
    #export KAYOBE_AUTOMATION_TEMPEST_SKIPLIST=ci-multinode
  fi

fi

if [[ -z "${KAYOBE_AUTOMATION_TEMPEST_CONF_OVERRIDES:+x}" ]] || [[ ! -e "${KAYOBE_AUTOMATION_TEMPEST_CONF_OVERRIDES}" ]]; then
    KAYOBE_AUTOMATION_TEMPEST_CONF_OVERRIDES="${KAYOBE_AUTOMATION_CONFIG_PATH}/tempest/tempest.overrides.conf"
fi

if [[ -f ${KAYOBE_AUTOMATION_REPO_ROOT}/etc/kolla/public-openrc.sh ]]; then
    export TEMPEST_OPENRC="$(< ${KAYOBE_AUTOMATION_REPO_ROOT}/etc/kolla/public-openrc.sh)"
fi

export KAYOBE_AUTOMATION_LOG_LEVEL=debug
