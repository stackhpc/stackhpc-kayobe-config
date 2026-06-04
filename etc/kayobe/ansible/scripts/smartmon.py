#!/usr/bin/env python3

import subprocess
import json
import re
import datetime
import os

from prometheus_client import CollectorRegistry, Gauge, write_to_textfile
from pySMART import DeviceList

SMARTCTL_PATH = "/usr/sbin/smartctl"

SMARTMON_ATTRS = {
    "airflow_temperature_cel",
    "command_timeout",
    "current_pending_sector",
    "end_to_end_error",
    "erase_fail_count",
    "g_sense_error_rate",
    "hardware_ecc_recovered",
    "host_reads_32mib",
    "host_reads_mib",
    "host_writes_32mib",
    "host_writes_mib",
    "load_cycle_count",
    "media_wearout_indicator",
    "nand_writes_1gib",
    "offline_uncorrectable",
    "power_cycle_count",
    "power_on_hours",
    "program_fail_cnt_total",
    "program_fail_count",
    "raw_read_error_rate",
    "reallocated_event_count",
    "reallocated_sector_ct",
    "reported_uncorrect",
    "runtime_bad_block",
    "sata_downshift_count",
    "seek_error_rate",
    "spin_retry_count",
    "spin_up_time",
    "start_stop_count",
    "temperature_case",
    "temperature_celsius",
    "temperature_internal",
    "total_lbas_read",
    "total_lbas_written",
    "udma_crc_error_count",
    "unsafe_shutdown_count",
    "unused_rsvd_blk_cnt_tot",
    "wear_leveling_count",
    "workld_host_reads_perc",
    "workld_media_wear_indic",
    "workload_minutes",
    "critical_warning",
    "available_spare",
    "available_spare_threshold",
    "percentage_used",
    "data_units_read",
    "data_units_written",
    "host_reads",
    "host_writes",
    "controller_busy_time",
    "power_cycles",
    "unsafe_shutdowns",
    "media_errors",
    "num_err_log_entries",
    "warning_temp_time",
    "critical_comp_time",
    "nvme_total_capacity",
    "nvme_unallocated_capacity",
}

DATA_UNIT_BYTES = 512000  # NVMe data unit size (1000 * 512 bytes)
BYTES_PER_TB = 10 ** 12
DWPD_RATINGS_PATH = "/opt/kayobe/etc/monitoring/dwpd_ratings.json"
DEFAULT_DWPD = 1.0


def canonical_device_path(name):
    """
    Ensure device name is an absolute /dev path for smartctl invocations.
    """
    if not name:
        return name
    return name if name.startswith("/dev/") else f"/dev/{name}"

def coerce_numeric(value):
    """
    Best effort conversion of various value types (including pySMART attribute objects)
    into a float. Returns None when conversion is not possible.
    """
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    for attr in ("value", "raw"):
        try:
            candidate = getattr(value, attr)
        except AttributeError:
            continue
        if isinstance(candidate, (int, float)):
            return float(candidate)
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def load_dwpd_ratings(path=DWPD_RATINGS_PATH):
    """
    Load rated DWPD values from JSON file.

    The file is expected to contain either a list of objects with
    'model_name' and 'rated_dwpd' keys, or a dictionary containing such a list.
    """
    mapping = {}

    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except FileNotFoundError:
        return mapping
    except (json.JSONDecodeError, OSError):
        return mapping

    if isinstance(data, dict):
        if isinstance(data.get("stackhpc_dwpd_ratings"), list):
            data_iterable = data["stackhpc_dwpd_ratings"]
        elif isinstance(data.get("dwpd_values"), list):
            data_iterable = data["dwpd_values"]
        else:
            data_iterable = []
    elif isinstance(data, list):
        data_iterable = data
    else:
        data_iterable = []

    for entry in data_iterable:
        if not isinstance(entry, dict):
            continue
        model_name = str(entry.get("model_name", "")).strip()
        rated_value = coerce_numeric(entry.get("rated_dwpd"))
        if not model_name:
            continue
        if rated_value is None:
            continue
        mapping[model_name.lower()] = rated_value

    return mapping


DWPD_RATINGS = load_dwpd_ratings()


# Helper: Identify historical temperature/airflow attribute failures
def is_historical_temperature_attr_failure(attribute):
    """
    Return True when a pySMART attribute failure represents only a historical
    temperature/airflow threshold breach.

    Some disks keep WHEN_FAILED=In_the_past forever after an overheating event.
    pySMART turns that into assessment=WARN, which is useful to expose, but it
    should not make the main smart_healthy metric look like an active disk
    failure.
    """
    when_failed = str(getattr(attribute, "when_failed", "") or "").strip().lower()
    name = str(getattr(attribute, "name", "") or "").strip().lower()

    if when_failed != "in_the_past":
        return False

    return "temperature" in name or "airflow" in name


def get_failed_smart_attributes(device):
    """
    Return pySMART attributes with a meaningful WHEN_FAILED value.
    """
    failed_attrs = []
    for attribute in getattr(device, "attributes", []) or []:
        when_failed = str(getattr(attribute, "when_failed", "") or "").strip().lower()
        if when_failed and when_failed not in {"-", "none", "never"}:
            failed_attrs.append(attribute)
    return failed_attrs


def smart_health_value(device):
    """
    Convert pySMART assessment into the exported healthy metric.

    PASS is healthy. WARN is also treated as healthy only when every failed
    attribute is a historical temperature/airflow threshold breach. Other WARN
    states, FAIL states, current failures, and non-temperature historical
    failures remain unhealthy.
    """
    assessment = str(device.assessment or "").strip().upper()

    if assessment == "PASS":
        return 1

    if assessment != "WARN":
        return 0

    failed_attrs = get_failed_smart_attributes(device)
    if not failed_attrs:
        return 0

    if all(is_historical_temperature_attr_failure(attribute) for attribute in failed_attrs):
        return 1

    return 0


def get_rated_dwpd(model_name):
    """
    Look up DWPD rating for the given model name, defaulting to 1.0.
    """
    if not model_name:
        return DEFAULT_DWPD
    lookup_key = model_name.lower().strip()
    return DWPD_RATINGS.get(lookup_key, DEFAULT_DWPD)

def run_command(command, parse_json=False):
    """
    Helper to run a subprocess command and optionally parse JSON output.
    """
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if parse_json:
        return json.loads(result.stdout)
    return result.stdout.strip()


def smartctl_json(disk_name, disk_type=None, *args):
    """
    Execute smartctl with JSON output enabled and return the parsed response.

    Args:
        disk_name (str): Device path (e.g. /dev/nvme0).
        disk_type (str): Interface type passed to smartctl -d (optional).
        *args: Additional smartctl arguments (e.g. "-x", "-n", "standby").

    Returns:
        dict: Parsed JSON response.
    """
    cmd = [SMARTCTL_PATH]
    cmd.extend(args)
    if disk_type:
        cmd.extend(["-d", disk_type])
    cmd.extend(["-j", disk_name])
    return run_command(cmd, parse_json=True)


def camel_to_snake(name):
    """
    Convert a CamelCase string to snake_case.

    Reference: https://stackoverflow.com/questions/1175208/elegant-python-function-to-convert-camelcase-to-snake-case
    """
    return re.sub(r'(?<!^)(?=[A-Z])', '_', name).lower()

def parse_device_info(device):
    """
    Produce Prometheus lines describing the device's identity and SMART status:
    - device_info
    - device_smart_available
    - device_smart_enabled
    - device_smart_healthy

    Args:
        device (Device): A pySMART Device object with attributes such as name, interface, etc.

    Returns:
        List[str]: A list of Prometheus formatted metric strings.
    """
    serial_number = (device.serial or "").lower()
    labels = {
        "disk": device.name,
        "type": device.interface or "",
        "vendor": device.vendor or "",
        "model_family": device.family or "",
        "device_model": device.model or "",
        "serial_number": serial_number,
        "firmware_version": device.firmware or "",
        "assessment": device.assessment or "",
    }
    sorted_labels = sorted(labels.items())
    label_str = ",".join(f'{k}="{v}"' for k, v in sorted_labels)

    metric_labels = f'disk="{device.name}",serial_number="{serial_number}",type="{device.interface}"'

    metrics = [
        f'smartmon_device_info{{{label_str}}} 1.0',
        f'smartmon_device_smart_available{{{metric_labels}}} {float(1) if device.smart_capable else float(0)}',
    ]

    if device.smart_capable:
        metrics.append(
            f'smartmon_device_smart_enabled{{{metric_labels}}} {float(1) if device.smart_enabled else float(0)}'
        )
        if device.assessment:
            is_healthy = smart_health_value(device)
            metrics.append(
                f'smartmon_device_smart_healthy{{{metric_labels}}} {float(is_healthy)}'
            )
            failed_attrs = get_failed_smart_attributes(device)
            historical_temperature_attr_failure = 1 if failed_attrs and all(
                is_historical_temperature_attr_failure(attribute) for attribute in failed_attrs
            ) else 0
            metrics.append(
                f'smartmon_device_historical_temperature_failure{{{metric_labels}}} {float(historical_temperature_attr_failure)}'
            )

    # Explicitly collect top-level temperature if available (fixes SCSI temperature issue)
    # pySMART exposes 'temperature' as a top-level property which we can use for SCSI,
    # whereas device.if_attributes.temperature is often None for SCSI.
    if device.temperature is not None:
        metrics.append(f'smartmon_temperature{{{metric_labels}}} {float(device.temperature)}')

    return metrics

def parse_if_attributes(device):
    """
    For any device type (ATA, NVMe, SCSI, etc.), we read device.if_attributes.
    We'll iterate over its public fields, convert them to snake_case,
    and if it's in SMARTMON_ATTRS and numeric, we produce metrics.

    Args:
        device (Device): A pySMART Device object with attributes such as name, interface, etc.
    Returns:
        List[str]: A list of Prometheus formatted metric strings.
    """
    metrics = []

    if not device.if_attributes:
        return metrics

    disk = device.name
    disk_type = device.interface or ""
    serial_number = (device.serial or "").lower()
    labels = f'disk="{disk}",serial_number="{serial_number}",type="{disk_type}"'

    # Inspect all public attributes on device.if_attributes
    for attr_name in dir(device.if_attributes):
        if attr_name.startswith("_"):
            continue  # skip private / special methods
        val = getattr(device.if_attributes, attr_name, None)
        if callable(val):
            continue  # skip methods

        snake_name = camel_to_snake(attr_name)

        if snake_name in SMARTMON_ATTRS and isinstance(val, (int, float)):
            metrics.append(f"smartmon_{snake_name}{{{labels}}} {float(val)}")

    return metrics


def collect_nvme_metrics(device):
    """
    Collect NVMe specific metrics using smartctl JSON output.

    Args:
        device (Device): pySMART Device instance.

    Returns:
        List[str]: Prometheus formatted metric strings.
    """
    metrics = []
    disk_name = device.name
    disk_type = device.interface or ""
    serial_number = (device.serial or "").lower()
    labels = f'disk="{disk_name}",serial_number="{serial_number}",type="{disk_type}"'
    model_name = (device.model or "").strip()

    attr_values = {}
    if device.if_attributes:
        for attr_name in dir(device.if_attributes):
            if attr_name.startswith("_"):
                continue
            value = getattr(device.if_attributes, attr_name, None)
            if callable(value):
                continue
            attr_values[camel_to_snake(attr_name)] = value

    smartctl_target = canonical_device_path(disk_name)
    try:
        nvme_json = smartctl_json(smartctl_target, disk_type, "-x")
    except subprocess.SubprocessError:
        nvme_json = {}

    if not model_name:
        model_name = str(nvme_json.get("model_name", "")).strip()

    health_log = nvme_json.get("nvme_smart_health_information_log")
    if not isinstance(health_log, dict):
        health_log = {}

    user_capacity = nvme_json.get("user_capacity")
    if not isinstance(user_capacity, dict):
        user_capacity = {}

    namespaces = nvme_json.get("nvme_namespaces")
    if not isinstance(namespaces, list):
        namespaces = []

    def numeric_value(*sources):
        for source in sources:
            value = coerce_numeric(source)
            if value is not None:
                return value
        return None

    namespace_capacity = None
    for namespace in namespaces:
        if not isinstance(namespace, dict):
            continue
        namespace_capacity = numeric_value(
            namespace.get("capacity", {}).get("bytes"),
            namespace.get("size", {}).get("bytes"),
            namespace.get("utilization", {}).get("bytes"),
        )
        if namespace_capacity is not None:
            break

    total_capacity = numeric_value(
        attr_values.get("nvme_total_capacity"),
        nvme_json.get("nvme_total_capacity"),
        user_capacity.get("bytes"),
        namespace_capacity,
    )
    if total_capacity is not None:
        metrics.append(f"smartmon_nvme_total_capacity_bytes{{{labels}}} {total_capacity}")
        metrics.append(f"smartmon_physical_size_bytes{{{labels}}} {total_capacity}")

    rated_dwpd = get_rated_dwpd(model_name)
    metrics.append(f"smartmon_nvme_rated_dwpd{{{labels}}} {rated_dwpd}")

    unallocated_capacity = numeric_value(
        attr_values.get("nvme_unallocated_capacity"),
        nvme_json.get("nvme_unallocated_capacity"),
    )
    if unallocated_capacity is not None:
        metrics.append(f"smartmon_nvme_unallocated_capacity_bytes{{{labels}}} {unallocated_capacity}")

    data_units_read_attr = "data_units_read" in attr_values
    data_units_read = numeric_value(
        attr_values.get("data_units_read"),
        health_log.get("data_units_read"),
    )
    if data_units_read is not None:
        bytes_read = data_units_read * DATA_UNIT_BYTES
        if not data_units_read_attr:
            metrics.append(f"smartmon_data_units_read{{{labels}}} {data_units_read}")
        metrics.append(f"smartmon_nvme_terabytes_read_total{{{labels}}} {bytes_read / BYTES_PER_TB}")

    data_units_written_attr = "data_units_written" in attr_values
    data_units_written = numeric_value(
        attr_values.get("data_units_written"),
        health_log.get("data_units_written"),
    )
    if data_units_written is not None:
        bytes_written = data_units_written * DATA_UNIT_BYTES
        if not data_units_written_attr:
            metrics.append(f"smartmon_data_units_written{{{labels}}} {data_units_written}")
        metrics.append(f"smartmon_nvme_terabytes_written_total{{{labels}}} {bytes_written / BYTES_PER_TB}")

    # Collect additional NVMe health log metrics that might be missed by pySMART
    # due to naming mismatches
    nvme_health_metrics = [
        "media_errors",
        "num_err_log_entries",
        "warning_temp_time",
        "critical_comp_time",
        "host_reads",
        "host_writes",
    ]

    for key in nvme_health_metrics:
        # Check if we already got this from pySMART (may change in the future)
        if key in attr_values:
            continue

        val = numeric_value(health_log.get(key))
        if val is not None:
            metrics.append(f"smartmon_{key}{{{labels}}} {val}")

    return metrics


def write_metrics_to_textfile(metrics, output_path=None):
    """
    Write metrics to a Prometheus textfile using prometheus_client.
    Args:
        metrics (List[str]): List of metric strings in 'name{labels} value' format.
        output_path (str): Path to write the metrics file. Defaults to node_exporter textfile collector path.
    """
    registry = CollectorRegistry()
    metric_gauges = {}
    for metric in metrics:
        # Split metric into name, labels, and value
        metric_name, rest = metric.split('{', 1)
        label_str, value = rest.split('}', 1)
        value = value.strip()
        # Parse labels into a dictionary
        labels = {}
        label_keys = []
        label_values = []
        for label in label_str.split(','):
            if '=' in label:
                k, v = label.split('=', 1)
                k = k.strip()
                v = v.strip('"')
                labels[k] = v
                label_keys.append(k)
                label_values.append(v)
        help_str = f"SMART metric {metric_name}"
        # Create Gauge if not already present
        if metric_name not in metric_gauges:
            metric_gauges[metric_name] = Gauge(metric_name, help_str, label_keys, registry=registry)
        # Set metric value
        gauge = metric_gauges[metric_name]
        gauge.labels(*label_values).set(float(value))
    if output_path is None:
        output_path = '/var/lib/node_exporter/textfile_collector/smartmon.prom'
    write_to_textfile(output_path, registry)  # Write all metrics to file

def main(output_path=None):
    all_metrics = []

    try:
        version_output = run_command([SMARTCTL_PATH, "--version"])
        if version_output.startswith("smartctl"):
            first_line = version_output.splitlines()[0]
            version_num = first_line.split()[1]
        else:
            version_num = "unknown"
    except Exception:
        version_num = "unknown"
    all_metrics.append(f'smartmon_smartctl_version{{version="{version_num}"}} 1')

    dev_list = DeviceList()

    for dev in dev_list.devices:
        disk_name = dev.name
        disk_type = dev.interface or ""
        serial_number = (dev.serial or "").lower()

        if not serial_number or not dev.assessment:
            continue

        run_timestamp = int(datetime.datetime.now(datetime.timezone.utc).timestamp())
        all_metrics.append(f'smartmon_smartctl_run{{disk="{disk_name}",type="{disk_type}"}} {run_timestamp}')

        active = 1
        try:
            standby_json = smartctl_json(canonical_device_path(disk_name), disk_type, "-n", "standby")
            if standby_json.get("power_mode", "") == "standby":
                active = 0
        except json.JSONDecodeError:
            active = 0
        except Exception:
            active = 0

        all_metrics.append(
            f'smartmon_device_active{{disk="{disk_name}",type="{disk_type}",serial_number="{serial_number}"}} {active}'
        )
        if active == 0:
            continue

        all_metrics.extend(parse_device_info(dev))
        all_metrics.extend(parse_if_attributes(dev))
        disk_basename = os.path.basename(disk_name)
        disk_type_normalized = (disk_type or "").lower()
        is_nvme = disk_type_normalized == "nvme" or disk_basename.startswith("nvme")
        if is_nvme:
            all_metrics.extend(collect_nvme_metrics(dev))

    write_metrics_to_textfile(all_metrics, output_path)

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Export SMART metrics to Prometheus textfile format.")
    parser.add_argument('--output', type=str, default=None, help='Output path for Prometheus textfile (default: /var/lib/node_exporter/textfile_collector/smartmon.prom)')
    args = parser.parse_args()
    main(args.output)
