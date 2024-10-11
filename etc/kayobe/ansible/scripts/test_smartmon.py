import unittest
from unittest.mock import patch
from smartmon import (
    parse_smartctl_info,
    parse_smartctl_attributes,
    main,
)

class TestSmartMon(unittest.TestCase):
    @patch('smartmon.run_command')
    def test_parse_smartctl_info(self, mock_run_command):
        devices_info = [
            {
                'disk': '/dev/nvme0',
                'disk_type': 'nvme',
                'json_output': {
                    'device': {
                        'name': '/dev/nvme0',
                        'info_name': '/dev/nvme0',
                        'type': 'nvme',
                        'protocol': 'NVMe',
                    },
                    'model_name': 'Dell Ent NVMe CM6 RI 7.68TB',
                    'serial_number': 'Y2Q0A0BGTCF8',
                    'firmware_version': '2.2.0',
                    'smart_status': {
                        'passed': True,
                        'available': True,
                        'enabled': True
                    },
                }
            },
            {
                'disk': '/dev/nvme1',
                'disk_type': 'nvme',
                'json_output': {
                    'device': {
                        'name': '/dev/nvme1',
                        'info_name': '/dev/nvme1',
                        'type': 'nvme',
                        'protocol': 'NVMe',
                    },
                    'model_name': 'Dell Ent NVMe CM6 RI 7.68TB',
                    'serial_number': 'Y2Q0A09PTCF8',
                    'firmware_version': '2.2.0',
                    'smart_status': {
                        'passed': True,
                        'available': True,
                        'enabled': True
                    },
                }
            },
        ]

        for device_info in devices_info:
            disk = device_info['disk']
            disk_type = device_info['disk_type']
            json_output = device_info['json_output']
            serial_number = json_output.get('serial_number', '').lower()

            expected_metrics = [
                f'device_info{{disk="{disk}",type="{disk_type}",vendor="",product="",revision="",lun_id="",model_family="",device_model="{json_output.get("model_name", "")}",serial_number="{serial_number}",firmware_version="{json_output.get("firmware_version", "")}"}} 1',
                f'device_smart_available{{disk="{disk}",type="{disk_type}",serial_number="{serial_number}"}} 1',
                f'device_smart_enabled{{disk="{disk}",type="{disk_type}",serial_number="{serial_number}"}} 1',
                f'device_smart_healthy{{disk="{disk}",type="{disk_type}",serial_number="{serial_number}"}} 1',
            ]

            metrics = parse_smartctl_info(disk, disk_type, json_output)
            for expected_metric in expected_metrics:
                self.assertIn(expected_metric, metrics)

    @patch('smartmon.run_command')
    def test_parse_smartctl_attributes(self, mock_run_command):
        devices_attributes = [
            {
                'disk': '/dev/nvme0',
                'disk_type': 'nvme',
                'serial': 'y2q0a0bgtcf8',
                'json_output': {
                    'nvme_smart_health_information_log': {
                        'critical_warning': 0,
                        'temperature': 36,
                        'available_spare': 100,
                        'available_spare_threshold': 10,
                        'percentage_used': 0,
                        'data_units_read': 117446405,
                        'data_units_written': 84630284,
                        'host_reads': 634894145,
                        'host_writes': 4502620984,
                        'controller_busy_time': 92090,
                        'power_cycles': 746,
                        'power_on_hours': 12494,
                        'unsafe_shutdowns': 35,
                        'media_errors': 0,
                        'num_err_log_entries': 827,
                        'warning_temp_time': 0,
                        'critical_comp_time': 0
                    }
                }
            },
            {
                'disk': '/dev/nvme1',
                'disk_type': 'nvme',
                'serial': 'y2q0a09ptcf8',
                'json_output': {
                    'nvme_smart_health_information_log': {
                        'critical_warning': 0,
                        'temperature': 35,
                        'available_spare': 99,
                        'available_spare_threshold': 10,
                        'percentage_used': 1,
                        'data_units_read': 50000000,
                        'data_units_written': 40000000,
                        'host_reads': 300000000,
                        'host_writes': 2000000000,
                        'controller_busy_time': 80000,
                        'power_cycles': 700,
                        'power_on_hours': 12000,
                        'unsafe_shutdowns': 30,
                        'media_errors': 0,
                        'num_err_log_entries': 800,
                        'warning_temp_time': 0,
                        'critical_comp_time': 0
                    }
                }
            },
        ]

        for device_attr in devices_attributes:
            disk = device_attr['disk']
            disk_type = device_attr['disk_type']
            serial = device_attr['serial']
            json_output = device_attr['json_output']

            metrics = parse_smartctl_attributes(disk, disk_type, serial, json_output)

            expected_metrics = [
                f'temperature{{disk="{disk}",type="{disk_type}",serial_number="{serial}"}} {json_output["nvme_smart_health_information_log"]["temperature"]}',
                f'available_spare{{disk="{disk}",type="{disk_type}",serial_number="{serial}"}} {json_output["nvme_smart_health_information_log"]["available_spare"]}',
            ]

            for expected_metric in expected_metrics:
                self.assertIn(expected_metric, metrics)

    @patch('smartmon.run_command')
    def test_main(self, mock_run_command):
        def side_effect(command, parse_json=False):
            if '--scan-open' in command:
                return {
                    'devices': [
                        {'name': '/dev/nvme0', 'info_name': '/dev/nvme0', 'type': 'nvme'},
                        {'name': '/dev/nvme1', 'info_name': '/dev/nvme1', 'type': 'nvme'},
                    ]
                } if parse_json else ''
            elif '-n' in command:
                return {'power_mode': 'active'} if parse_json else ''
            elif '-i' in command:
                if '/dev/nvme0' in command:
                    return {
                        'device': {
                            'name': '/dev/nvme0',
                            'info_name': '/dev/nvme0',
                            'type': 'nvme',
                            'protocol': 'NVMe',
                        },
                        'model_name': 'Dell Ent NVMe CM6 RI 7.68TB',
                        'serial_number': 'Y2Q0A0BGTCF8',
                        'firmware_version': '2.2.0',
                        'smart_status': {
                            'passed': True,
                            'available': True,
                            'enabled': True
                        },
                    } if parse_json else ''
                elif '/dev/nvme1' in command:
                    return {
                        'device': {
                            'name': '/dev/nvme1',
                            'info_name': '/dev/nvme1',
                            'type': 'nvme',
                            'protocol': 'NVMe',
                        },
                        'model_name': 'Dell Ent NVMe CM6 RI 7.68TB',
                        'serial_number': 'Y2Q0A09PTCF8',
                        'firmware_version': '2.2.0',
                        'smart_status': {
                            'passed': True,
                            'available': True,
                            'enabled': True
                        },
                    } if parse_json else ''
            elif '-A' in command:
                if '/dev/nvme0' in command:
                    return {
                        'nvme_smart_health_information_log': {
                            'critical_warning': 0,
                            'temperature': 36,
                            'available_spare': 100,
                            'available_spare_threshold': 10,
                            'percentage_used': 0,
                            'data_units_read': 117446405,
                            'data_units_written': 84630284,
                            'host_reads': 634894145,
                            'host_writes': 4502620984,
                            'controller_busy_time': 92090,
                            'power_cycles': 746,
                            'power_on_hours': 12494,
                            'unsafe_shutdowns': 35,
                            'media_errors': 0,
                            'num_err_log_entries': 827,
                            'warning_temp_time': 0,
                            'critical_comp_time': 0
                        }
                    } if parse_json else ''
                elif '/dev/nvme1' in command:
                    return {
                        'nvme_smart_health_information_log': {
                            'critical_warning': 0,
                            'temperature': 35,
                            'available_spare': 99,
                            'available_spare_threshold': 10,
                            'percentage_used': 1,
                            'data_units_read': 50000000,
                            'data_units_written': 40000000,
                            'host_reads': 300000000,
                            'host_writes': 2000000000,
                            'controller_busy_time': 80000,
                            'power_cycles': 700,
                            'power_on_hours': 12000,
                            'unsafe_shutdowns': 30,
                            'media_errors': 0,
                            'num_err_log_entries': 800,
                            'warning_temp_time': 0,
                            'critical_comp_time': 0
                        }
                    } if parse_json else ''
            elif '-j' in command and len(command) == 2:
                return {
                    'smartctl': {
                        'version': [7, 2],
                        'svn_revision': '5155',
                        'platform_info': 'x86_64-linux-5.15.0-122-generic',
                        'build_info': '(local build)',
                    }
                } if parse_json else ''
            else:
                return {} if parse_json else ''

        mock_run_command.side_effect = side_effect

        with patch('builtins.print') as mock_print:
            main()
            output_lines = []
            for call in mock_print.call_args_list:
                output_lines.extend(call[0][0].split('\n'))
            expected_metrics = [
                'smartmon_device_info{disk="/dev/nvme0",type="nvme",vendor="",product="",revision="",lun_id="",model_family="",device_model="Dell Ent NVMe CM6 RI 7.68TB",serial_number="y2q0a0bgtcf8",firmware_version="2.2.0"} 1',
                'smartmon_device_info{disk="/dev/nvme1",type="nvme",vendor="",product="",revision="",lun_id="",model_family="",device_model="Dell Ent NVMe CM6 RI 7.68TB",serial_number="y2q0a09ptcf8",firmware_version="2.2.0"} 1',
            ]
            for expected_metric in expected_metrics:
                self.assertIn(expected_metric, output_lines)


if __name__ == '__main__':
    unittest.main()
