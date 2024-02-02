#!/usr/bin/env python3

"""
Script to manage Kolla container image tags.

Background:
In Kolla Ansible each container is deployed using a specific image.
Typically the image is named the same as the container, with underscores
replaced by dashes, however there are some exceptions. Sometimes multiple
containers use the same image.

The image tag deployed by each container is defined by a Kolla Ansible variable
named <container>_tag. There are also intermediate tag variables to make it
easier to set the tag for all containers in a service, e.g. nova_tag is the
default for nova_api_tag, nova_compute, etc. There is a global default tag
defined by openstack_tag. This setup forms a hierarchy of tag variables.

This script captures this logic, as well as exceptions to these rules.
"""

import argparse
import inspect
import json
import os
import pathlib
import re
import subprocess
import sys
from typing import Dict, List, Optional

import yaml


# Dict of Kolla image tags to deploy for each service.
# Each key is the tag variable prefix name, and the value is another dict,
# where the key is the OS distro and the value is the tag to deploy.
# This is the content of etc/kayobe/kolla-image-tags.yml.
KollaImageTags = Dict[str, Dict[str, str]]

# Maps a Kolla image to a list of containers that use the image.
IMAGE_TO_CONTAINERS_EXCEPTIONS: Dict[str, List[str]] = {
    "haproxy": [
        "glance_tls_proxy",
        "neutron_tls_proxy",
    ],
    "mariadb-server": [
        "mariadb",
        "mariabackup",
    ],
    "neutron-eswitchd": [
        "neutron_mlnx_agent",
    ],
    "neutron-metadata-agent": [
        "neutron_metadata_agent",
        "neutron_ovn_metadata_agent",
    ],
    "nova-conductor": [
        "nova_super_conductor",
        "nova_conductor",
    ],
    "prometheus-v2-server": [
        "prometheus_server",
    ],
}

# Maps a container to the parent tag variable in the hierarchy.
CONTAINER_TO_PREFIX_VAR_EXCEPTIONS: Dict[str, str] = {
    "cron": "common",
    "fluentd": "common",
    "glance_tls_proxy": "haproxy",
    "hacluster_corosync": "openstack",
    "hacluster_pacemaker": "openstack",
    "hacluster_pacemaker_remote": "openstack",
    "heat_api_cfn": "heat",
    "ironic_neutron_agent": "neutron",
    "kolla_toolbox": "common",
    "mariabackup": "mariadb",
    "neutron_eswitchd": "neutron_mlnx_agent",
    "neutron_tls_proxy": "haproxy",
    "nova_compute_ironic": "nova",
    "redis_sentinel": "openstack",
    "swift_object_expirer": "swift",
    "tgtd": "iscsi",
}

# List of supported base distributions and versions.
SUPPORTED_BASE_DISTROS = [
    "rocky-9",
    "ubuntu-jammy",
]


def parse_args() -> argparse.Namespace:
    """Parse command line arguments."""
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-distros", default=",".join(SUPPORTED_BASE_DISTROS), choices=SUPPORTED_BASE_DISTROS)
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparser = subparsers.add_parser("check-hierarchy", help="Check tag variable hierarchy against kolla-ansible")
    subparser.add_argument("--kolla-ansible-path", required=True, help="Path to kolla-ansible repostory checked out to correct branch")

    subparser = subparsers.add_parser("check-tags", help="Check specified tags for each image exist in the Ark registry")
    subparser.add_argument("--registry", required=True, help="Hostname of container image registry")
    subparser.add_argument("--namespace", required=True, help="Namespace in container image registry")

    subparsers.add_parser("list-containers", help="List supported containers based on pulp.yml")

    subparsers.add_parser("list-images", help="List supported images based on pulp.yml")

    subparsers.add_parser("list-tags", help="List tags for each image based on kolla-image-tags.yml")

    subparsers.add_parser("list-tag-vars", help="List Kolla Ansible tag variables")

    return parser.parse_args()


def get_abs_path(relative_path: str) -> str:
    """Return the absolute path of a file in SKC."""
    script_path = pathlib.Path(inspect.getfile(inspect.currentframe()))
    return script_path.parent.parent / relative_path


def read_images(images_file: str) -> List[str]:
    """Read image list from pulp.yml config file."""
    with open(get_abs_path(images_file), "r") as f:
        variables = yaml.safe_load(f)
    return variables["stackhpc_pulp_images_kolla"]


def read_unbuildable_images(images_file: str) -> Dict[str, List[str]]:
    """Read unbuildable image list from pulp.yml config file."""
    with open(get_abs_path(images_file), "r") as f:
        variables = yaml.safe_load(f)
    return variables["stackhpc_kolla_unbuildable_images"]


def read_kolla_image_tags(tags_file: str) -> KollaImageTags:
    """Read kolla image tags kolla-image-tags.yml config file."""
    with open(get_abs_path(tags_file), "r") as f:
        variables = yaml.safe_load(f)
    return variables["kolla_image_tags"]


def get_containers(image):
    """Return a list of containers that use the specified image."""
    default_container = image.replace('-', '_')
    return IMAGE_TO_CONTAINERS_EXCEPTIONS.get(image, [default_container])


def get_parent_tag_name(kolla_image_tags: KollaImageTags, base_distro: Optional[str], container: str) -> str:
    """Return the parent tag variable for a container in the tag variable hierarchy."""

    if container in CONTAINER_TO_PREFIX_VAR_EXCEPTIONS:
        prefix_var = CONTAINER_TO_PREFIX_VAR_EXCEPTIONS[container]
        if prefix_var in kolla_image_tags:
            return prefix_var
    else:
        prefix_var = container

    def tag_key(tag):
        """Return a sort key to order the tags."""
        if tag == "openstack":
            # This is the default tag.
            return 0
        elif tag != prefix_var and prefix_var.startswith(tag) and (base_distro is None or base_distro in kolla_image_tags[tag]):
            # Prefix match - sort by the longest match.
            return -len(tag)
        else:
            # No match.
            return 1

    return sorted(kolla_image_tags.keys(), key=tag_key)[0]


def get_parent_tag(kolla_image_tags: KollaImageTags, base_distro: str, container: str) -> str:
    """Return the tag used by the parent in the hierarchy."""
    parent_tag_name = get_parent_tag_name(kolla_image_tags, base_distro, container)
    return kolla_image_tags[parent_tag_name][base_distro]


def get_tag(kolla_image_tags: KollaImageTags, base_distro: str, container: str) -> str:
    """Return the tag for a container."""
    container_tag = kolla_image_tags.get(container, {}).get(base_distro)
    if container_tag:
        return container_tag

    return get_parent_tag(kolla_image_tags, base_distro, container)


def get_tags(base_distros: List[str], kolla_image_tags: KollaImageTags) -> Dict[str, List[str]]:
    """Return a list of tags used for each image."""
    images = read_images("etc/kayobe/pulp.yml")
    unbuildable_images = read_unbuildable_images("etc/kayobe/pulp.yml")
    image_tags: Dict[str, List[str]] = {}
    for base_distro in base_distros:
        for image in images:
            if image not in unbuildable_images[base_distro]:
                for container in get_containers(image):
                    tag = get_tag(kolla_image_tags, base_distro, container)
                    tags = image_tags.setdefault(image, [])
                    if tag not in tags:
                        tags.append(tag)
    return image_tags


def get_openstack_release() -> str:
    """Return the OpenStack release."""
    with open(get_abs_path(".gitreview"), "r") as f:
        gitreview = f.readlines()
    for line in gitreview:
        if "=" not in line:
            continue
        key, value = line.split("=")
        if key.strip() == "defaultbranch":
            value = value.strip()
            for prefix in ("stable/", "unmaintained/"):
                if value.startswith(prefix):
                    return value[len(prefix):]
    raise Exception("Failed to determine OpenStack release")


def validate(kolla_image_tags: KollaImageTags):
    """Validate the kolla_image_tags variable."""
    tag_var_re = re.compile(r"^[a-z0-9_-]+$")
    openstack_release = get_openstack_release()
    tag_res = {
        base_distro: re.compile(f"^{openstack_release}-{base_distro}-[\d]{{8}}T[\d]{{6}}$")
        for base_distro in SUPPORTED_BASE_DISTROS
    }
    errors = []
    if "openstack" not in kolla_image_tags:
        errors.append("Missing default openstack tag")
    for tag_var, base_distros in kolla_image_tags.items():
        if not tag_var_re.match(tag_var):
            errors.append(f"Key {tag_var} does not match expected pattern. It should match {tag_var_re.pattern}")
        for base_distro, tag in base_distros.items():
            if base_distro not in SUPPORTED_BASE_DISTROS:
                errors.append(f"{tag_var}: base distro {base_distro} not supported. Options: {SUPPORTED_BASE_DISTROS}")
                continue
            if not tag_res[base_distro].match(tag):
                errors.append(f"{tag_var}: {base_distro}: tag {tag} does not match expected pattern. It should match {tag_res[base_distro].pattern}")
    if errors:
        print("Errors in kolla_image_tags variable:")
        for error in errors:
            print(error)
        sys.exit(1)


def check_tags(base_distros: List[str], kolla_image_tags: KollaImageTags, registry: str, namespace: str):
    """Check whether expected tags are present in container image registry."""
    try:
        subprocess.check_output("type skopeo", shell=True)
    except subprocess.CalledProcessError:
        print("Failed to find skopeo. Please install it.")
        sys.exit(1)
    image_tags = get_tags(base_distros, kolla_image_tags)

    missing = {}
    for image, tags in image_tags.items():
        for _ in range(3):
            try:
                output = subprocess.check_output(f"skopeo list-tags docker://{registry}/{namespace}/{image}", shell=True)
            except Exception as e:
                exc = e
            else:
                break
        else:
            raise exc
        ark_tags = json.loads(output)["Tags"]
        missing_tags = set(tags) - set(ark_tags)
        if missing_tags:
            missing[image] = list(missing_tags)

    if missing:
        print(f"ERROR: Some expected tags not found in {namespace} namespace")
        print(yaml.dump(missing, indent=2))
        sys.exit(1)


def check_hierarchy(kolla_ansible_path: str):
    """Check the tag variable hierarchy against Kolla Ansible variables."""
    cmd = """git grep -h '^[a-z0-9_]*_tag:' ansible/roles/*/defaults/main.yml"""
    hierarchy_str = subprocess.check_output(cmd, shell=True, cwd=os.path.realpath(kolla_ansible_path))
    hierarchy = yaml.safe_load(hierarchy_str)
    # This one is not a container:
    hierarchy.pop("octavia_amp_image_tag")
    tag_var_re = re.compile(r"^([a-z0-9_]+)_tag$")
    parent_re = re.compile(r"{{[\s]*([a-z0-9_]+)_tag[\s]*}}")
    hierarchy = {
        tag_var_re.match(tag_var).group(1): parent_re.match(parent).group(1)
        for tag_var, parent in hierarchy.items()
    }
    kolla_image_tags: KollaImageTags = {image: {} for image in hierarchy}
    kolla_image_tags["openstack"] = {}
    errors = []
    for tag_var, expected in hierarchy.items():
        parent = get_parent_tag_name(kolla_image_tags, None, tag_var)
        if parent != expected:
            errors.append((tag_var, parent, expected))
    if errors:
        print("Errors:")
    for tag_var, parent, expected in errors:
        print(f"{tag_var} -> {parent} != {expected}")
    if errors:
        sys.exit(1)


def list_containers(base_distros: List[str]):
    """List supported containers."""
    images = read_images("etc/kayobe/pulp.yml")
    unbuildable_images = read_unbuildable_images("etc/kayobe/pulp.yml")
    containers = set()
    for base_distro in base_distros:
        for image in images:
            if image not in unbuildable_images[base_distro]:
                containers |= set(get_containers(image))
    print(yaml.dump(sorted(containers)))


def list_images(base_distros: List[str]):
    """List supported images."""
    images = read_images("etc/kayobe/pulp.yml")
    print(yaml.dump(images))


def list_tags(base_distros: List[str], kolla_image_tags: KollaImageTags):
    """List tags used by each image."""
    image_tags = get_tags(base_distros, kolla_image_tags)

    print(yaml.dump(image_tags))


def list_tag_vars(kolla_image_tags: KollaImageTags):
    """List tag variables."""
    tag_vars = []
    for tag_var in kolla_image_tags:
        if tag_var == "openstack":
            default = ""
        else:
            parent_tag_name = get_parent_tag_name(kolla_image_tags, None, tag_var)
            default = f" | default({parent_tag_name}_tag)"
        tag_vars.append(f"{tag_var}_tag: \"{{{{ kolla_image_tags['{tag_var}'][kolla_base_distro_and_version]{default} }}}}\"")

    for tag_var in tag_vars:
        print(tag_var)


def main():
    args = parse_args()
    kolla_image_tags = read_kolla_image_tags("etc/kayobe/kolla-image-tags.yml")
    base_distros = args.base_distros.split(",")

    validate(kolla_image_tags)

    if args.command == "check-hierarchy":
        check_hierarchy(args.kolla_ansible_path)
    elif args.command == "check-tags":
        check_tags(base_distros, kolla_image_tags, args.registry, args.namespace)
    elif args.command == "list-containers":
        list_containers(base_distros)
    elif args.command == "list-images":
        list_images(base_distros)
    elif args.command == "list-tags":
        list_tags(base_distros, kolla_image_tags)
    elif args.command == "list-tag-vars":
        list_tag_vars(kolla_image_tags)
    else:
        sys.exit(1)


if __name__ == "__main__":
    main()
