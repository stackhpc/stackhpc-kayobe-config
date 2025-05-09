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
    "temperature",
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
}

def run_command(command, parse_json=False):
    """
    Helper to run a subprocess command and optionally parse JSON output.
    """
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if parse_json:
        return json.loads(result.stdout)
    return result.stdout.strip()

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
            is_healthy = 1 if device.assessment.upper() == "PASS" else 0
            metrics.append(
                f'smartmon_device_smart_healthy{{{metric_labels}}} {float(is_healthy)}'
            )

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

        run_timestamp = int(datetime.datetime.now(datetime.timezone.utc).timestamp())
        all_metrics.append(f'smartmon_smartctl_run{{disk="{disk_name}",type="{disk_type}"}} {run_timestamp}')

        active = 1
        try:
            cmd = [SMARTCTL_PATH, "-n", "standby", "-d", disk_type, "-j", disk_name]
            standby_json = run_command(cmd, parse_json=True)
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

    write_metrics_to_textfile(all_metrics, output_path)

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Export SMART metrics to Prometheus textfile format.")
    parser.add_argument('--output', type=str, default=None, help='Output path for Prometheus textfile (default: /var/lib/node_exporter/textfile_collector/smartmon.prom)')
    args = parser.parse_args()
    main(args.output)
