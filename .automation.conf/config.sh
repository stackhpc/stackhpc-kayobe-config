# Enter config overrides in here

KAYOBE_URI=https://github.com/stackhpc/kayobe
KAYOBE_BRANCH=scientific-openstack/wallaby

# See: https://github.com/stackhpc/docker-rally/blob/master/bin/rally-verify-wrapper.sh for a full list of tempest parameters that can be overriden.
# You can override tempest parameters like so:
export TEMPEST_CONCURRENCY=2
# Specify single test whilst experimenting
#export TEMPEST_PATTERN="${TEMPEST_PATTERN:-tempest.api.compute.servers.test_create_server.ServersTestJSON.test_host_name_is_same_as_server_name}"

KAYOBE_AUTOMATION_TEMPEST_CONF_OVERRIDES="${KAYOBE_AUTOMATION_CONFIG_PATH}/tempest/tempest.overrides.conf"

if [ ! -z ${KAYOBE_ENVIRONMENT:+x} ]; then
  # NOTE: could dynamically switch this based on environment
  KAYOBE_AUTOMATION_TEMPEST_CONF_OVERRIDES="${KAYOBE_AUTOMATION_CONFIG_PATH}/tempest/tempest-${KAYOBE_ENVIRONMENT}.overrides.conf"

  if [ "$KAYOBE_ENVIRONMENT" == "aio" ]; then
    # Seem to get servers failing to spawn with higher concurrency
    export TEMPEST_CONCURRENCY=1
  fi
fi


