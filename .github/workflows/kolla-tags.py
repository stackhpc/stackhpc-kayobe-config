#!/usr/bin/env python3

"""
Script to manage Kolla container image tag YAML files.
"""

import argparse
import json
import yaml


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    update = subparsers.add_parser("update", help="Print updated tags YAML")
    update.add_argument("--images-file", help="Path to updated image list JSON file", required=True)
    update.add_argument("--tags-file", help="Path to tags YAML file", required=True)
    return parser.parse_args()


def get_image_var(repository: str) -> str:
    """Return the image tag variable name for a given image.

    :param repository: The repository (registry & name) of the updated image.
    """
    service_name = repository.rpartition("-source-")[2]
    return service_name.replace("-", "_") + "_tag"


def get_updated_images(images_file: str) -> dict[str, str]:
    """Return a dict of updated image tags.

    :param images_file: Path to a updated image list JSON file.
    """
    with open(images_file, "r") as f:
        images = f.readlines()

    updated = {}
    for image_json in images:
        image = json.loads(image_json)
        repo = image["Repository"]
        if repo.endswith("base"):
            continue
        image_var = get_image_var(repo)
        updated[image_var] = image["Tag"]
    return updated


def update(tags_file: str, images_file: str):
    """Generate and print updated image tags YAML."""
    updated = get_updated_images(images_file)
    with open(tags_file, "r") as f:
        tags = yaml.safe_load(f)
    tags.update(updated)
    print(yaml.dump(tags))


def main():
    args = parse_args()
    if args.command == "update":
        update(args.tags_file, args.images_file)


if __name__ == "__main__":
    main()
