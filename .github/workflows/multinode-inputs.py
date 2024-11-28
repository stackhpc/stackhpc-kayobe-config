# Generate inputs for the reusable multinode.yml workflow.
# The test scenario is randomly selected.
# The inputs are printed to stdout in GitHub step output key=value format.

from dataclasses import dataclass
import random
import typing as t


@dataclass
class OSRelease:
    distribution: str
    release: str
    ssh_username: str


@dataclass
class OpenStackRelease:
    version: str
    previous_version: str
    os_releases: t.List[OSRelease]


@dataclass
class Scenario:
    openstack_release: OpenStackRelease
    os_release: OSRelease
    neutron_plugin: str
    upgrade: bool


ROCKY_9 = OSRelease("rocky", "9", "cloud-user")
UBUNTU_JAMMY = OSRelease("ubuntu", "jammy", "ubuntu")
# NOTE(upgrade): Add supported releases here.
OPENSTACK_RELEASES = [
    OpenStackRelease("2024.1", "2023.1", [ROCKY_9, UBUNTU_JAMMY]),
    OpenStackRelease("2023.1", "zed", [ROCKY_9, UBUNTU_JAMMY]),
]
NEUTRON_PLUGINS = ["ovs", "ovn"]


def main() -> None:
    scenario = random_scenario()
    inputs = generate_inputs(scenario)
    for name, value in inputs.items():
        write_output(name, value)


def random_scenario() -> Scenario:
    openstack_release = random.choice(OPENSTACK_RELEASES)
    os_release = random.choice(openstack_release.os_releases)
    neutron_plugin = random.choice(NEUTRON_PLUGINS)
    upgrade = random.random() > 0.6
    return Scenario(openstack_release, os_release, neutron_plugin, upgrade)


def generate_inputs(scenario: Scenario) -> t.Dict[str, str]:
    branch = get_branch(scenario.openstack_release.version)
    previous_branch = get_branch(scenario.openstack_release.previous_version)
    inputs = {
        "os_distribution": scenario.os_release.distribution,
        "os_release": scenario.os_release.release,
        "ssh_username": scenario.os_release.ssh_username,
        "neutron_plugin": scenario.neutron_plugin,
        "upgrade": str(scenario.upgrade).lower(),
        "stackhpc_kayobe_config_version": branch,
        "stackhpc_kayobe_config_previous_version": previous_branch,
    }
    return inputs


def get_branch(version: str) -> str:
    return f"stackhpc/{version}"


def write_output(name: str, value: str) -> None:
    print(f"{name}={value}")


if __name__ == "__main__":
    main()
