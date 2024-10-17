#!/usr/bin/env python3

import subprocess
import json
from datetime import datetime

SMARTCTL_PATH = "/usr/sbin/smartctl"

def run_command(command, parse_json=False):
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if parse_json:
        return json.loads(result.stdout)
    else:
        return result.stdout.strip()

def parse_smartctl_attributes(disk, disk_type, serial, json_data):
    labels = f'disk="{disk}",type="{disk_type}",serial_number="{serial}"'
    metrics = []
    smartmon_attrs = set([
        "airflow_temperature_cel", "command_timeout", "current_pending_sector", "end_to_end_error", "erase_fail_count",
        "g_sense_error_rate", "hardware_ecc_recovered", "host_reads_32mib", "host_reads_mib", "host_writes_32mib",
        "host_writes_mib", "load_cycle_count", "media_wearout_indicator", "nand_writes_1gib", "offline_uncorrectable",
        "power_cycle_count", "power_on_hours", "program_fail_cnt_total", "program_fail_count", "raw_read_error_rate",
        "reallocated_event_count", "reallocated_sector_ct", "reported_uncorrect", "runtime_bad_block", "sata_downshift_count",
        "seek_error_rate", "spin_retry_count", "spin_up_time", "start_stop_count", "temperature_case", "temperature_celsius",
        "temperature_internal", "total_lbas_read", "total_lbas_written", "udma_crc_error_count", "unsafe_shutdown_count",
        "unused_rsvd_blk_cnt_tot", "wear_leveling_count", "workld_host_reads_perc", "workld_media_wear_indic", "workload_minutes",
        "critical_warning", "temperature", "available_spare", "available_spare_threshold", "percentage_used",
        "data_units_read", "data_units_written", "host_reads", "host_writes", "controller_busy_time",
        "power_cycles", "unsafe_shutdowns", "media_errors", "num_err_log_entries",
        "warning_temp_time", "critical_comp_time"
    ])
    if 'nvme_smart_health_information_log' in json_data:
        smart_log = json_data['nvme_smart_health_information_log']
        for attr_name, value in smart_log.items():
            attr_name = attr_name.replace(' ', '_').lower()
            if attr_name in smartmon_attrs:
                metrics.append(f"{attr_name}{{{labels}}} {value}")
    elif 'scsi_grown_defect_list' in json_data:
        scsi_attrs = json_data.get('scsi_grown_defect_list', {})
        for attr_name, value in scsi_attrs.items():
            attr_name = attr_name.replace(' ', '_').lower()
            if attr_name in smartmon_attrs:
                metrics.append(f"{attr_name}{{{labels}}} {value}")
    elif 'ata_smart_attributes' in json_data and 'table' in json_data['ata_smart_attributes']:
        for attr in json_data['ata_smart_attributes']['table']:
            attr_name = attr['name'].replace('-', '_').lower()
            if attr_name in smartmon_attrs:
                attr_id = attr.get('id', '')
                value = attr.get('value', '')
                worst = attr.get('worst', '')
                threshold = attr.get('thresh', '')
                raw_value = attr.get('raw', {}).get('value', '')
                metrics.append(f"{attr_name}_value{{{labels},smart_id=\"{attr_id}\"}} {value}")
                metrics.append(f"{attr_name}_worst{{{labels},smart_id=\"{attr_id}\"}} {worst}")
                metrics.append(f"{attr_name}_threshold{{{labels},smart_id=\"{attr_id}\"}} {threshold}")
                metrics.append(f"{attr_name}_raw_value{{{labels},smart_id=\"{attr_id}\"}} {raw_value}")
    return metrics

def parse_smartctl_info(disk, disk_type, json_data):
    info = json_data.get('device', {})
    smart_status = json_data.get('smart_status', {})
    labels = {
        'disk': disk,
        'type': disk_type,
        'vendor': info.get('vendor', ''),
        'product': info.get('product', ''),
        'revision': info.get('revision', ''),
        'lun_id': info.get('lun_id', ''),
        'model_family': json_data.get('model_family', ''),
        'device_model': json_data.get('model_name', ''),
        'serial_number': json_data.get('serial_number', '').lower(),
        'firmware_version': json_data.get('firmware_version', '')
    }
    label_str = ','.join(f'{k}="{v}"' for k, v in labels.items())
    metrics = [
        f'device_info{{{label_str}}} 1',
        f'device_smart_available{{disk="{disk}",type="{disk_type}",serial_number="{labels["serial_number"]}"}} {1 if smart_status.get("available", False) else 0}',
    ]
    if smart_status.get("available", False):
        metrics.append(f'device_smart_enabled{{disk="{disk}",type="{disk_type}",serial_number="{labels["serial_number"]}"}} {1 if smart_status.get("enabled", False) else 0}')
        if 'passed' in smart_status:
            metrics.append(f'device_smart_healthy{{disk="{disk}",type="{disk_type}",serial_number="{labels["serial_number"]}"}} {1 if smart_status.get("passed", False) else 0}')
    return metrics

def format_output(metrics):
    output = []
    last_metric = ""
    for metric in sorted(metrics):
        metric_name = metric.split('{')[0]
        if metric_name != last_metric:
            output.append(f"# HELP smartmon_{metric_name} SMART metric {metric_name}")
            output.append(f"# TYPE smartmon_{metric_name} gauge")
            last_metric = metric_name
        output.append(f"smartmon_{metric}")
    return '\n'.join(output)

def main():
    try:
        version_output = run_command([SMARTCTL_PATH, '-j'], parse_json=True)
        smartctl_version_list = version_output.get('smartctl', {}).get('version', [])
        if smartctl_version_list:
            smartctl_version_str = '.'.join(map(str, smartctl_version_list))
        else:
            smartctl_version_str = "unknown"
    except json.JSONDecodeError:
        smartctl_version_str = "unknown"
    metrics = [f'smartctl_version{{version="{smartctl_version_str}"}} 1']

    try:
        device_list_output = run_command([SMARTCTL_PATH, '--scan-open', '-j'], parse_json=True)
        devices = []
        for device in device_list_output.get('devices', []):
            disk = device.get('name', '')
            disk_type = device.get('type', 'auto')
            if disk:
                devices.append((disk, disk_type))
    except json.JSONDecodeError:
        devices = []

    for disk, disk_type in devices:
        serial_number = ''
        active = 1
        metrics.append(f'smartctl_run{{disk="{disk}",type="{disk_type}"}} {int(datetime.utcnow().timestamp())}')

        try:
            standby_output = run_command([SMARTCTL_PATH, '-n', 'standby', '-d', disk_type, '-j', disk], parse_json=True)
            power_mode = standby_output.get('power_mode', '')
            if power_mode == 'standby':
                active = 0
        except json.JSONDecodeError:
            active = 0  # Assume device is inactive if we can't parse the output

        metrics.append(f'device_active{{disk="{disk}",type="{disk_type}"}} {active}')

        if active == 0:
            continue

        try:
            info_output = run_command([SMARTCTL_PATH, '-i', '-H', '-d', disk_type, '-j', disk], parse_json=True)
        except json.JSONDecodeError:
            continue
        metrics.extend(parse_smartctl_info(disk, disk_type, info_output))
        serial_number = info_output.get('serial_number', '').lower()

        try:
            attributes_output = run_command([SMARTCTL_PATH, '-A', '-d', disk_type, '-j', disk], parse_json=True)
        except json.JSONDecodeError:
            continue
        metrics.extend(parse_smartctl_attributes(disk, disk_type, serial_number, attributes_output))

    formatted_output = format_output(metrics)
    print(formatted_output)

if __name__ == "__main__":
    main()
