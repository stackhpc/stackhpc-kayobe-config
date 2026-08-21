#!/usr/bin/env python3
import json
import re
import subprocess
from pySMART import DeviceList

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

SMARTCTL_PATH = "/usr/sbin/smartctl"

DISK_INFO = {
    "name",
    "interface",
    "vendor",
    "family",
    "model",
    "serial",
    "firmware",
    "smart_capable",
    "smart_enabled",
    "assessment",
}

def camel_to_snake(name):
    """
    Convert a CamelCase string to snake_case.

    Reference: https://stackoverflow.com/questions/1175208/elegant-python-function-to-convert-camelcase-to-snake-case
    """
    return re.sub(r'(?<!^)(?=[A-Z])', '_', name).lower()

def canonical_device_path(name):
    """
    Ensure device name is returned as absolute /dev path for smartctl.

    pySMART sometimes reports bare device names (e.g. 'nvme0'); smartctl on the
    CLI expects the canonical /dev path, so normalise here to avoid surprises.
    """
    return name if name.startswith("/dev/") else f"/dev/{name}"

def attrs_to_dict(obj, allowed_keys):
    """
    Build {attr: value} for every public, non-callable attribute whose
    snake_case name is in `allowed_keys`.
    """
    attributes = {}
    for name in dir(obj):
        if name.startswith('_'):
            continue
        try:
            value = getattr(obj, name)
        except Exception:
            continue
        if value is None:
            continue
        if callable(value):
            continue
        if camel_to_snake(name) in allowed_keys:
            attributes[name] = value
    return attributes

def smartctl_json(device_name, device_type):
    """
    Execute smartctl -x -j for the given device and return the parsed JSON payload.

    The goal is to mirror the exact data smartmon.py consumes at runtime so our
    fixtures stay faithful to real hardware output.
    """
    if not device_name:
        return {}

    target = canonical_device_path(device_name)

    cmd = [SMARTCTL_PATH, "-x", "-j", target]
    if device_type and device_type.lower() not in (None, "", "nvme"):
        cmd.insert(3, device_type)
        cmd.insert(3, "-d")

    try:
        result = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            text=True,
        )
    except OSError:
        return {}

    if not result.stdout:
        return {}

    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        return {}

for disk in DeviceList().devices:

    fixtures = {}
    disk_info = attrs_to_dict(disk, DISK_INFO)
    if_stats = attrs_to_dict(disk.if_attributes, SMARTMON_ATTRS)
    smartctl_payload = smartctl_json(disk.name, disk.interface)

    fixtures["device_info"] = disk_info
    fixtures["if_attributes"] = if_stats
    fixtures["smartctl"] = smartctl_payload

    print(f'Disk: {disk.name}: \n')
    print(json.dumps(fixtures, indent=2, default=str))
