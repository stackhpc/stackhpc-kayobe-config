# Generate inputs for the reusable multinode.yml workflow.
# The test scenario is randomly selected.
# The inputs are printed to stdout in GitHub step output key=value format.

import argparse
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
    upgrade: str


ROCKY_9 = OSRelease("rocky", "9", "cloud-user")
ROCKY_10 = OSRelease("rocky", "10", "cloud-user")
UBUNTU_JAMMY = OSRelease("ubuntu", "jammy", "ubuntu")
UBUNTU_NOBLE = OSRelease("ubuntu", "noble", "ubuntu")
# NOTE(upgrade): Add supported releases here.
OPENSTACK_RELEASES = [
    OpenStackRelease("2024.1", "2023.1", [ROCKY_9, UBUNTU_JAMMY]),
    OpenStackRelease("2025.1", "2024.1", [ROCKY_9, UBUNTU_NOBLE]),
    OpenStackRelease("2025.1", "", [ROCKY_10]),
]
NEUTRON_PLUGINS = ["ovs", "ovn"]
VERSION_HIERARCHY = ["2023.1", "2024.1", "2025.1"]


def main() -> None:

    parser = argparse.ArgumentParser(
        description='Randomly picks a multinode scenario to execute')
    parser.add_argument(
        '--output-summary', '-s',
        type=argparse.FileType('w', encoding='UTF-8'),
        default=None,
        help="Write a markdown summary table of selected inputs to a file (use '-' to write to stdout)")
    args = parser.parse_args()

    scenario = random_scenario()
    inputs = {
        "os_distribution": scenario.os_release.distribution,
        "os_release": scenario.os_release.release,
        "ssh_username": scenario.os_release.ssh_username,
        "neutron_plugin": scenario.neutron_plugin,
        "upgrade": scenario.upgrade,
        "stackhpc_kayobe_config_version": get_branch(scenario.openstack_release.version),
        "stackhpc_kayobe_config_previous_version": get_branch(scenario.openstack_release.previous_version),
        "terraform_kayobe_multinode_version": get_tkm_version(scenario.openstack_release.version),
        "terraform_kayobe_multinode_previous_version": get_tkm_version(scenario.openstack_release.previous_version),
    }
    for name, value in inputs.items():
        write_output(name, value)
    if args.output_summary:
        write_summary(inputs, args.output_summary)


def random_scenario() -> Scenario:
    openstack_release = random.choice(OPENSTACK_RELEASES)
    os_release = random.choice(openstack_release.os_releases)
    neutron_plugin = random.choice(NEUTRON_PLUGINS)
    upgrade = "major" if (random.random() > 0.6 and openstack_release.previous_version != "") else "none"
    return Scenario(openstack_release, os_release, neutron_plugin, upgrade)


def get_branch(version: str) -> str:
    return f"stackhpc/{version}" if version != "" else ""


def get_tkm_version(version: str) -> str:
    if version == "2025.1":
        return "main"
    else:
        return get_branch(version)


def write_output(name: str, value: str) -> None:
    print(f"{name}={value}")


def write_summary(inputs: dict, output: t.TextIO):
    print(
        '| Input  | Value |\n'
        '| -----: | :---- |', file=output)
    for key, value in inputs.items():
        print(f'| **{key}** | `{value}`  |', file=output)


if __name__ == "__main__":
    main()
