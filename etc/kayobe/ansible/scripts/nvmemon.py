#!/usr/bin/env python3

"""
NVMe device metrics textfile collector.
Requires nvme-cli package.

Formatted with Black:
$ black -l 100 nvme_metrics.py
"""

import json
import os
import re
import sys
import subprocess
from dataclasses import dataclass
from enum import Enum
from typing import Any, Iterator, Optional

# Disable automatic addition of _created series. Must be set before importing prometheus_client.
os.environ["PROMETHEUS_DISABLE_CREATED_SERIES"] = "true"

from prometheus_client import CollectorRegistry, Counter, Gauge, Info, generate_latest  # noqa: E402

registry = CollectorRegistry()
namespace = "nvme"

# Path to DWPD ratings JSON file (same as legacy bash script)
DWPD_RATINGS_PATH = "/opt/kayobe/etc/monitoring/dwpd_ratings.json"

metrics = {
    # fmt: off
    "avail_spare": Gauge(
        "available_spare_ratio",
        "Device available spare ratio",
        ["device", "model", "serial_number"], namespace=namespace, registry=registry,
    ),
    "controller_busy_time": Counter(
        "controller_busy_time_seconds",
        "Device controller busy time in seconds",
        ["device", "model", "serial_number"], namespace=namespace, registry=registry,
    ),
    "critical_warning": Gauge(
        "critical_warning",
        "Device critical warning bitmap field",
        ["device", "model", "serial_number"], namespace=namespace, registry=registry,
    ),
    "data_units_read": Counter(
        "data_units_read_total",
        "Number of 512-byte data units read by host, reported in thousands",
        ["device", "model", "serial_number"], namespace=namespace, registry=registry,
    ),
    "data_units_written": Counter(
        "data_units_written_total",
        "Number of 512-byte data units written by host, reported in thousands",
        ["device", "model", "serial_number"], namespace=namespace, registry=registry,
    ),
    "device_info": Info(
        "device",
        "Device information",
        ["device", "model", "firmware", "serial"], namespace=namespace, registry=registry,
    ),
    "host_read_commands": Counter(
        "host_read_commands_total",
        "Device read commands from host",
        ["device", "model", "serial_number"], namespace=namespace, registry=registry,
    ),
    "host_write_commands": Counter(
        "host_write_commands_total",
        "Device write commands from host",
        ["device", "model", "serial_number"], namespace=namespace, registry=registry,
    ),
    "media_errors": Counter(
        "media_errors_total",
        "Device media errors total",
        ["device", "model", "serial_number"], namespace=namespace, registry=registry,
    ),
    "num_err_log_entries": Counter(
        "num_err_log_entries_total",
        "Device error log entry count",
        ["device", "model", "serial_number"], namespace=namespace, registry=registry,
    ),
    # FIXME: The "nvmecli" metric ought to be an Info type, not a Gauge. However, making this change
    # will result in the metric having a "_info" suffix automatically appended, which is arguably
    # a breaking change.
    "nvmecli": Gauge(
        "nvmecli",
        "nvme-cli tool information",
        ["version"], namespace=namespace, registry=registry,
    ),
    "percent_used": Gauge(
        "percentage_used_ratio",
        "Device percentage used ratio",
        ["device", "model", "serial_number"], namespace=namespace, registry=registry,
    ),
    "physical_size": Gauge(
        "physical_size_bytes",
        "Device size in bytes",
        ["device", "model", "serial_number"], namespace=namespace, registry=registry,
    ),
    "power_cycles": Counter(
        "power_cycles_total",
        "Device number of power cycles",
        ["device", "model", "serial_number"], namespace=namespace, registry=registry,
    ),
    "power_on_hours": Counter(
        "power_on_hours_total",
        "Device power-on hours",
        ["device", "model", "serial_number"], namespace=namespace, registry=registry,
    ),
    "sector_size": Gauge(
        "sector_size_bytes",
        "Device sector size in bytes",
        ["device", "model", "serial_number"], namespace=namespace, registry=registry,
    ),
    "spare_thresh": Gauge(
        "available_spare_threshold_ratio",
        "Device available spare threshold ratio",
        ["device", "model", "serial_number"], namespace=namespace, registry=registry,
    ),
    "temperature": Gauge(
        "temperature_celsius",
        "Device temperature in degrees Celsius",
        ["device", "model", "serial_number"], namespace=namespace, registry=registry,
    ),
    "unsafe_shutdowns": Counter(
        "unsafe_shutdowns_total",
        "Device number of unsafe shutdowns",
        ["device", "model", "serial_number"], namespace=namespace, registry=registry,
    ),
    "used_bytes": Gauge(
        "used_bytes",
        "Device used size in bytes",
        ["device", "model", "serial_number"], namespace=namespace, registry=registry,
    ),
    "rated_dwpd": Gauge(
        "rated_dwpd",
        "Device rated drive-writes-per-day (fallback 1 if unknown)",
        ["device", "model", "serial_number"], namespace=namespace, registry=registry,
    ),
    # fmt: on
}


@dataclass
class NamespaceContext:
    """Normalized view of a namespace regardless of nvme-cli schema."""

    device_name: str
    device_path: str
    model: str
    serial: str
    firmware: str
    physical_size: int
    sector_size: int
    used_bytes: int


class NvmeListSchema(str, Enum):
    """Shapes observed in nvme list JSON across nvme-cli versions."""

    SUBSYSTEMS = "subsystems"
    CONTROLLERS = "controllers"


def parse_version_tuple(version: str) -> Optional[tuple[int, int, int]]:
    """Return (major, minor, patch) for comparisons; tolerate short versions."""

    match = re.match(r"^(\d+)(?:\.(\d+))?(?:\.(\d+))?", version)
    if not match:
        return None
    major = int(match.group(1))
    minor = int(match.group(2)) if match.group(2) is not None else 0
    patch = int(match.group(3)) if match.group(3) is not None else 0
    return major, minor, patch


def _normalize_list(value: Any) -> list[Any]:
    """nvme-cli sometimes emits dicts instead of singleton lists; fix that."""

    if isinstance(value, list):
        return value
    if value is None:
        return []
    return [value]


def _to_int(value: Any, default: int = 0) -> int:
    """Coerce nvme smart-log values to int, handling strings/nested dicts."""

    if isinstance(value, dict):
        for key in ("value", "raw", "current", "data"):
            if key in value:
                return _to_int(value[key], default)
        return default
    if isinstance(value, list):
        return _to_int(value[0], default) if value else default
    if isinstance(value, bool):
        return int(value)
    try:
        if isinstance(value, str):
            stripped = value.strip()
            if not stripped:
                return default
            base = 16 if stripped.lower().startswith("0x") else 10
            return int(stripped, base)
        return int(value)
    except (TypeError, ValueError):
        try:
            if isinstance(value, str):
                return int(float(value))
            return int(float(value))
        except (TypeError, ValueError):
            return default


def _to_float(value: Any, default: float = 0.0) -> float:
    """Coerce smart-log values to float without crashing on odd encodings."""

    if isinstance(value, dict):
        for key in ("value", "raw", "current", "data"):
            if key in value:
                return _to_float(value[key], default)
        return default
    if isinstance(value, list):
        return _to_float(value[0], default) if value else default
    try:
        if isinstance(value, str):
            stripped = value.strip()
            if not stripped:
                return default
            return float(stripped)
        return float(value)
    except (TypeError, ValueError):
        return default


def detect_nvme_list_schema(version_tuple: Optional[tuple[int, int, int]], payload: dict[str, Any]) -> NvmeListSchema:
    """Infer schema using explicit keys first, falling back to version heuristic."""

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


def _namespace_from_payload(model: str, serial: str, firmware: str, namespace: dict[str, Any]) -> Optional[NamespaceContext]:
    """Build a NamespaceContext with sane defaults even if fields are missing."""

    if not isinstance(namespace, dict):
        return None

    device_name = str(namespace.get("NameSpace") or namespace.get("Namespace") or "").strip()
    device_path = namespace.get("DevicePath")
    if isinstance(device_path, str):
        device_path = device_path.strip()
    else:
        device_path = None

    if device_path:
        candidate = os.path.basename(device_path)
        if candidate:
            device_name = candidate

    if not device_name:
        return None

    if not device_path:
        device_path = os.path.join("/dev", device_name)

    return NamespaceContext(
        device_name=device_name,
        device_path=device_path,
        model=model,
        serial=serial,
        firmware=firmware,
        physical_size=_to_int(namespace.get("PhysicalSize"), 0),
        sector_size=_to_int(namespace.get("SectorSize"), 0),
        used_bytes=_to_int(namespace.get("UsedBytes"), 0),
    )


def iter_namespaces(payload: dict[str, Any], schema: NvmeListSchema) -> Iterator[NamespaceContext]:
    """Yield namespaces in a schema-agnostic manner for metric emission."""

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
                    model = str(controller.get("ModelNumber", "")).strip()
                    serial = str(controller.get("SerialNumber", "")).strip()
                    firmware = str(controller.get("Firmware", "")).strip()
                    for namespace in _normalize_list(controller.get("Namespaces")):
                        ctx = _namespace_from_payload(model, serial, firmware, namespace)
                        if ctx:
                            yield ctx
    else:
        for device in devices:
            for controller in _normalize_list(device.get("Controllers")):
                if not isinstance(controller, dict):
                    continue
                model = str(controller.get("ModelNumber", "")).strip()
                serial = str(controller.get("SerialNumber", "")).strip()
                firmware = str(controller.get("Firmware", "")).strip()
                for namespace in _normalize_list(controller.get("Namespaces")):
                    ctx = _namespace_from_payload(model, serial, firmware, namespace)
                    if ctx:
                        yield ctx


def load_dwpd_ratings(path: str = DWPD_RATINGS_PATH) -> dict[str, float]:
    """Load DWPD ratings file.

    Returns mapping model_name -> rated_dwpd (float/int). If file missing or invalid, returns empty dict.
    """
    try:
        with open(path, "r") as f:
            data = json.load(f)
        if not isinstance(data, list):
            return {}
        result = {}
        for item in data:
            if not isinstance(item, dict):
                continue
            model = str(item.get("model_name", "")).strip()
            if not model:
                continue
            try:
                rated_dwpd = float(item.get("rated_dwpd", 1))
            except (TypeError, ValueError):
                rated_dwpd = 1.0
            result[model] = rated_dwpd
        return result
    except FileNotFoundError:
        print(f"WARNING: DWPD ratings file {path} not found, proceeding with fallback of 1 DWPD")
        return {}
    except Exception:
        return {}


def exec_nvme(*args):
    """
    Execute nvme CLI tool with specified arguments and return captured stdout result. Set LC_ALL=C
    in child process environment so that the nvme tool does not perform any locale-specific number
    or date formatting, etc.
    """
    cmd = ["nvme", *args]
    return subprocess.check_output(cmd, stderr=subprocess.PIPE, env=dict(os.environ, LC_ALL="C"))


def exec_nvme_json(*args, require_verbose: bool = True):
    """Execute nvme CLI tool with specified arguments and return parsed JSON output."""

    def _run(add_verbose: bool):
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


def main():
    match = re.match(r"^nvme version (\S+)", exec_nvme("version").decode())
    if match:
        cli_version = match.group(1)
    else:
        cli_version = "unknown"
    metrics["nvmecli"].labels(cli_version).set(1)

    device_list = exec_nvme_json("list")
    version_tuple = parse_version_tuple(cli_version) if cli_version != "unknown" else None
    # Older nvme-cli releases expose controllers directly, newer ones nest under subsystems.
    schema = detect_nvme_list_schema(version_tuple, device_list)

    dwpd_map = load_dwpd_ratings()

    for context in iter_namespaces(device_list, schema):
        device_name = context.device_name
        model = context.model
        serial_number = context.serial

        # FIXME: This metric ought to be refactored into a "controller_info" metric,
        # since it contains information that is not unique to the namespace. However,
        # previous versions of this collector erroneously referred to namespaces, e.g.
        # "nvme0n1", as devices, so preserve the former behaviour for now.
        metrics["device_info"].labels(
            device_name,
            model,
            context.firmware,
            serial_number,
        )

        metrics["sector_size"].labels(device_name, model, serial_number).set(context.sector_size)
        metrics["physical_size"].labels(device_name, model, serial_number).set(context.physical_size)
        metrics["used_bytes"].labels(device_name, model, serial_number).set(context.used_bytes)

        # Rated DWPD (drive endurance). Fallback to 1 if unknown.
        rated_dwpd = dwpd_map.get(model, 1)
        metrics["rated_dwpd"].labels(device_name, model, serial_number).set(rated_dwpd)

        # FIXME: The smart-log should only need to be fetched once per controller, not
        # per namespace. However, in order to preserve legacy metric labels, fetch it
        # per namespace anyway. Most consumer grade SSDs will only have one namespace.
        smart_log = exec_nvme_json("smart-log", context.device_path, require_verbose=False)

        # Various counters in the NVMe specification are 128-bit, which would have to
        # discard resolution if converted to a JSON number (i.e., float64_t). Instead,
        # nvme-cli marshals them as strings. As such, they need to be explicitly cast
        # to int or float when using them in Counter metrics.
        metrics["data_units_read"].labels(device_name, model, serial_number).inc(
            _to_int(smart_log.get("data_units_read"))
        )
        metrics["data_units_written"].labels(device_name, model, serial_number).inc(
            _to_int(smart_log.get("data_units_written"))
        )
        metrics["host_read_commands"].labels(device_name, model, serial_number).inc(
            _to_int(smart_log.get("host_read_commands"))
        )
        metrics["host_write_commands"].labels(device_name, model, serial_number).inc(
            _to_int(smart_log.get("host_write_commands"))
        )
        metrics["avail_spare"].labels(device_name, model, serial_number).set(
            _to_float(smart_log.get("avail_spare")) / 100
        )
        metrics["spare_thresh"].labels(device_name, model, serial_number).set(
            _to_float(smart_log.get("spare_thresh")) / 100
        )
        metrics["percent_used"].labels(device_name, model, serial_number).set(
            _to_float(smart_log.get("percent_used")) / 100
        )
        metrics["critical_warning"].labels(device_name, model, serial_number).set(
            _to_int(smart_log.get("critical_warning"))
        )
        metrics["media_errors"].labels(device_name, model, serial_number).inc(
            _to_int(smart_log.get("media_errors"))
        )
        metrics["num_err_log_entries"].labels(device_name, model, serial_number).inc(
            _to_int(smart_log.get("num_err_log_entries"))
        )
        metrics["power_cycles"].labels(device_name, model, serial_number).inc(
            _to_int(smart_log.get("power_cycles"))
        )
        metrics["power_on_hours"].labels(device_name, model, serial_number).inc(
            _to_int(smart_log.get("power_on_hours"))
        )
        metrics["controller_busy_time"].labels(device_name, model, serial_number).inc(
            _to_int(smart_log.get("controller_busy_time"))
        )
        metrics["unsafe_shutdowns"].labels(device_name, model, serial_number).inc(
            _to_int(smart_log.get("unsafe_shutdowns"))
        )

        # NVMe reports temperature in kelvins; convert it to degrees Celsius.
        temperature_kelvin = _to_int(smart_log.get("temperature"))
        metrics["temperature"].labels(device_name, model, serial_number).set(
            temperature_kelvin - 273 if temperature_kelvin else 0
        )


if __name__ == "__main__":
    if os.geteuid() != 0:
        print("ERROR: script requires root privileges", file=sys.stderr)
        sys.exit(1)

    # Check if nvme-cli is installed
    try:
        exec_nvme()
    except FileNotFoundError:
        print("ERROR: nvme-cli is not installed. Aborting.", file=sys.stderr)
        sys.exit(1)

    try:
        main()
    except Exception as e:
        print("ERROR: {}".format(e), file=sys.stderr)
        sys.exit(1)

    print(generate_latest(registry).decode(), end="")
