# This file is used to configure kayobe-automation.
# https://github.com/stackhpc/kayobe-automation/blob/main/README.md

# See: https://github.com/stackhpc/docker-rally/blob/master/bin/rally-verify-wrapper.sh for a full list of tempest parameters that can be overriden.
# You can override tempest parameters like so:

# The Tempest concurrency determines how many tests can be running at once.
# Higher values run tests faster but risk running out of resources and failing tests
# On production systems, Tempest concurrency can usually be set to a high number e.g. 16-64. It is often limited by the number of available floating IPs.
# On virtualised test environments, compute and networking speeds often limit the concurrency to 1-16 before tests begin to fail due to timeouts.
export TEMPEST_CONCURRENCY=16


# Specify single test whilst experimenting
#export TEMPEST_PATTERN="${TEMPEST_PATTERN:-tempest.api.compute.servers.test_create_server.ServersTestJSON.test_host_name_is_same_as_server_name}"

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
    export TEMPEST_CONCURRENCY=4
    # Uncomment this to perform a full tempest test
    # export KAYOBE_AUTOMATION_TEMPEST_LOADLIST=tempest-full
    # export KAYOBE_AUTOMATION_TEMPEST_SKIPLIST=ci-multinode-tempest-full
  fi

fi

if [[ -z "${KAYOBE_AUTOMATION_TEMPEST_CONF_OVERRIDES:+x}" ]] || [[ ! -e "${KAYOBE_AUTOMATION_TEMPEST_CONF_OVERRIDES}" ]]; then
    KAYOBE_AUTOMATION_TEMPEST_CONF_OVERRIDES="${KAYOBE_AUTOMATION_CONFIG_PATH}/tempest/tempest.overrides.conf"
fi

if [[ -f ${KAYOBE_AUTOMATION_REPO_ROOT}/etc/kolla/public-openrc.sh ]]; then
    export TEMPEST_OPENRC="$(< ${KAYOBE_AUTOMATION_REPO_ROOT}/etc/kolla/public-openrc.sh)"
fi
