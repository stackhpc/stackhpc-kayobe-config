#!/usr/bin/env python3
"""Dump per-namespace NVMe fixtures for `nvmemon.py` tests.

Run this on a machine with NVMe hardware (preferably as root) and copy
each printed JSON blob into ``tests/nvmemon/<name>.json``.
"""

from __future__ import annotations

import copy
import json
import os
import re
import subprocess
import sys
from enum import Enum
from typing import Any, Iterator, Optional


class NvmeListSchema(str, Enum):
    """Known layouts of nvme list output across nvme-cli releases."""

    SUBSYSTEMS = "subsystems"
    CONTROLLERS = "controllers"


def exec_nvme(*args: str) -> bytes:
    cmd = ["nvme", *args]
    env = dict(os.environ, LC_ALL="C")
    return subprocess.check_output(cmd, stderr=subprocess.PIPE, env=env)


def exec_nvme_json(*args: str, require_verbose: bool = True) -> Any:
    """Run nvme command and return parsed JSON, retrying without --verbose if needed."""

    def _run(add_verbose: bool) -> bytes:
        extra = ["--output-format", "json"]
        if add_verbose:
            extra.append("--verbose")
        return exec_nvme(*args, *extra)

    try:
        output = _run(require_verbose)
    except subprocess.CalledProcessError as exc:
        if require_verbose:
            try:
                output = _run(False)
            except subprocess.CalledProcessError:
                raise exc
        else:
            raise
    return json.loads(output)


def parse_version_tuple(version: str) -> Optional[tuple[int, int, int]]:
    """Extract a comparable version tuple from nvme-cli version output."""

    match = re.match(r"^(\d+)(?:\.(\d+))?(?:\.(\d+))?", version)
    if not match:
        return None
    major = int(match.group(1))
    minor = int(match.group(2)) if match.group(2) is not None else 0
    patch = int(match.group(3)) if match.group(3) is not None else 0
    return major, minor, patch


def _normalize_list(value: Any) -> list[Any]:
    """Ensure we always iterate over lists even if nvme-cli emits singleton dicts."""

    if isinstance(value, list):
        return value
    if value is None:
        return []
    return [value]


def detect_nvme_list_schema(version_tuple: Optional[tuple[int, int, int]], payload: dict[str, Any]) -> NvmeListSchema:
    devices = payload.get("Devices")
    if not isinstance(devices, list):
        devices = []

    has_subsystems = any(isinstance(device.get("Subsystems"), list) for device in devices)
    has_controllers = any(isinstance(device.get("Controllers"), list) for device in devices)

    if has_subsystems:
        return NvmeListSchema.SUBSYSTEMS
    if has_controllers:
        return NvmeListSchema.CONTROLLERS

    if version_tuple and version_tuple[0] >= 2:
        return NvmeListSchema.SUBSYSTEMS
    return NvmeListSchema.CONTROLLERS


def iter_controller_namespaces(
    payload: dict[str, Any], schema: NvmeListSchema
) -> Iterator[tuple[dict[str, Any], Optional[dict[str, Any]], dict[str, Any], dict[str, Any]]]:
    devices = payload.get("Devices")
    if not isinstance(devices, list):
        return

    if schema is NvmeListSchema.SUBSYSTEMS:
        for device in devices:
            for subsystem in _normalize_list(device.get("Subsystems")):
                if not isinstance(subsystem, dict):
                    continue
                for controller in _normalize_list(subsystem.get("Controllers")):
                    if not isinstance(controller, dict):
                        continue
                    for namespace in _normalize_list(controller.get("Namespaces")):
                        if isinstance(namespace, dict):
                            yield device, subsystem, controller, namespace
    else:
        for device in devices:
            for controller in _normalize_list(device.get("Controllers")):
                if not isinstance(controller, dict):
                    continue
                for namespace in _normalize_list(controller.get("Namespaces")):
                    if isinstance(namespace, dict):
                        yield device, None, controller, namespace


def sanitize_namespace(namespace: dict[str, Any]) -> tuple[str, str, dict[str, Any]]:
    """Normalise namespace fields so fixtures mirror collector expectations."""

    ns = copy.deepcopy(namespace)
    namespace_name = ns.get("NameSpace") or ns.get("Namespace") or ns.get("DevicePath")
    if isinstance(namespace_name, (int, float)):
        namespace_name = f"ns{int(namespace_name)}"
    namespace_name = str(namespace_name or "").strip()
    if not namespace_name and isinstance(ns.get("DevicePath"), str):
        namespace_name = os.path.basename(ns["DevicePath"]) or namespace_name

    device_path = ns.get("DevicePath")
    if not isinstance(device_path, str) or not device_path:
        device_path = os.path.join("/dev", namespace_name) if namespace_name else ""

    ns["NameSpace"] = namespace_name
    ns["DevicePath"] = device_path
    return namespace_name, device_path, ns


def main() -> int:
    try:
        raw_version = exec_nvme("version").decode("utf-8", "ignore").strip()
    except FileNotFoundError:
        print("ERROR: nvme CLI not installed", file=sys.stderr)
        return 1
    except subprocess.CalledProcessError as exc:
        print(f"ERROR: nvme version failed: {exc}", file=sys.stderr)
        return 1

    version_line = raw_version.splitlines()[0] if raw_version else "nvme version unknown"
    match = re.match(r"^nvme version (\S+)", version_line)
    nvme_version = match.group(1) if match else "unknown"
    version_tuple = parse_version_tuple(nvme_version) if nvme_version != "unknown" else None

    try:
        nvme_list = exec_nvme_json("list")
    except subprocess.CalledProcessError as exc:
        print(f"ERROR: nvme list failed: {exc}", file=sys.stderr)
        return 1

    schema = detect_nvme_list_schema(version_tuple, nvme_list)
    for device, subsystem, controller, namespace in iter_controller_namespaces(nvme_list, schema):
        controller_snapshot = copy.deepcopy(controller)
        namespace_name, device_path, namespace_snapshot = sanitize_namespace(namespace)
        if not namespace_name:
            continue

        try:
            smart_log = exec_nvme_json("smart-log", device_path, require_verbose=False)
        except subprocess.CalledProcessError as exc:
            print(f"WARNING: smart-log failed for {namespace_name}: {exc}", file=sys.stderr)
            continue

        fixture = {
            "nvme_version": nvme_version,
            "device": copy.deepcopy(device) if isinstance(device, dict) else None,
            "subsystem": copy.deepcopy(subsystem) if isinstance(subsystem, dict) else None,
            "controller": controller_snapshot,
            "namespace": namespace_snapshot,
            "smart_log": smart_log,
        }

        if fixture["device"] is None:
            del fixture["device"]
        if fixture["subsystem"] is None:
            del fixture["subsystem"]

        print(f"Namespace: {namespace_name}\n")
        print(json.dumps(fixture, indent=2, sort_keys=True))
        print()

    return 0


if __name__ == "__main__":
    if os.geteuid() != 0:
        print("WARNING: running without root may miss data", file=sys.stderr)
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        pass
