# Enter config overrides in here
# These are required to diff against an older version of the config without requirements.txt
OPENSTACK_SERIES=victoria
KAYOBE_URI=https://github.com/RSE-Cambridge/kayobe
KAYOBE_BRANCH=cumulus/victoria

export TEMPEST_CONCURRENCY=2
# Specify single test whilst experimenting
#export TEMPEST_PATTERN="${TEMPEST_PATTERN:-tempest.api.compute.servers.test_create_server.ServersTestJSON.test_host_name_is_same_as_server_name}"

KAYOBE_AUTOMATION_TEMPEST_CONF_OVERRIDES="${KAYOBE_AUTOMATION_CONFIG_PATH}/tempest/tempest.overrides.conf"

if [ ! -z ${KAYOBE_ENVIRONMENT:+x} ]; then
  KAYOBE_AUTOMATION_TEMPEST_CONF_OVERRIDES="${KAYOBE_AUTOMATION_CONFIG_PATH}/tempest/tempest-${KAYOBE_ENVIRONMENT}-${KAYOBE_AUTOMATION_TEMPEST_LOADLIST:-}.overrides.conf"

  # Check if loadlist specific overrides exist, if not fallback to environment overrides.
  if [ ! -e "${KAYOBE_AUTOMATION_TEMPEST_CONF_OVERRIDES}" ]; then
      KAYOBE_AUTOMATION_TEMPEST_CONF_OVERRIDES="${KAYOBE_AUTOMATION_CONFIG_PATH}/tempest/tempest-${KAYOBE_ENVIRONMENT}.overrides.conf"
  fi

  if [ "$KAYOBE_ENVIRONMENT" == "aio" ] || [ "$KAYOBE_ENVIRONMENT" == "aio-rocky" ]; then
    # Seem to get servers failing to spawn with higher concurrency
    export TEMPEST_CONCURRENCY=1
  fi
fi

KAYOBE_AUTOMATION_CONFIG_DIFF_INJECT_FACTS=1
