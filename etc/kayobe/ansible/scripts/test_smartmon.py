import glob
import json
import os
import re
import unittest

from unittest.mock import patch, MagicMock

from smartmon import (
    parse_device_info,
    parse_if_attributes,
    main,
    SMARTMON_ATTRS
)

def load_json_fixture(filename):
    """
    Load a JSON file from the 'drives' subfolder.
    """
    path = os.path.join(os.path.dirname(__file__), "drives", filename)
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


class TestSmartMon(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Collect all *.json files from ./drives/
        data_folder = os.path.join(os.path.dirname(__file__), "drives")
        cls.fixture_files = glob.glob(os.path.join(data_folder, "*.json"))

    def create_mock_device_from_json(self, device_info, if_attributes=None):
        """
        Given a 'device_info' dict and optional 'if_attributes', build
        a MagicMock that mimics a pySMART Device object.
        """
        device = MagicMock()
        device.name = device_info.get("name", "")
        device.interface = device_info.get("interface", "")
        device.vendor = device_info.get("vendor", "")
        device.family = device_info.get("family", "")
        device.model = device_info.get("model", "")
        device.serial = device_info.get("serial", "")
        device.firmware = device_info.get("firmware", "")
        device.smart_capable = device_info.get("smart_capable", False)
        device.smart_enabled = device_info.get("smart_enabled", False)
        device.assessment = device_info.get("assessment", "")

        if if_attributes:
            class IfAttributesMock:
                pass

            if_mock = IfAttributesMock()
            for key, val in if_attributes.items():
                setattr(if_mock, key, val)
            device.if_attributes = if_mock
        else:
            device.if_attributes = None

        return device

    def test_parse_device_info(self):
        """
        Test parse_device_info() for every JSON fixture in ./drives/.
        We do subTest() so each fixture is tested individually.
        """
        for fixture_path in self.fixture_files:
            fixture_name = os.path.basename(fixture_path)
            with self.subTest(msg=f"Testing device_info with {fixture_name}"):
                data = load_json_fixture(fixture_name)
                device_info = data["device_info"]

                device = self.create_mock_device_from_json(device_info)
                metrics = parse_device_info(device)

                dev_name = device_info["name"]
                dev_iface = device_info["interface"]
                dev_serial = device_info["serial"].lower()

                # The device_info line should exist for every device
                # e.g. device_info{disk="/dev/...",type="...",serial_number="..."} 1
                device_info_found = any(
                    line.startswith("device_info{") and
                    f'disk="{dev_name}"' in line and
                    f'type="{dev_iface}"' in line and
                    f'serial_number="{dev_serial}"' in line
                    for line in metrics
                )
                self.assertTrue(
                    device_info_found,
                    f"Expected a device_info metric line for {dev_name} but didn't find it."
                )

                # If smart_capable is true, we expect device_smart_available = 1
                if device_info.get("smart_capable"):
                    smart_available_found = any(
                        line.startswith("device_smart_available{") and
                        f'disk="{dev_name}"' in line and
                        f'serial_number="{dev_serial}"' in line and
                        line.endswith(" 1")
                        for line in metrics
                    )
                    self.assertTrue(
                        smart_available_found,
                        f"Expected device_smart_available=1 for {dev_name}, not found."
                    )

                # If smart_enabled is true, we expect device_smart_enabled = 1
                if device_info.get("smart_enabled"):
                    smart_enabled_found = any(
                        line.startswith("device_smart_enabled{") and
                        f'disk="{dev_name}"' in line and
                        line.endswith(" 1")
                        for line in metrics
                    )
                    self.assertTrue(
                        smart_enabled_found,
                        f"Expected device_smart_enabled=1 for {dev_name}, not found."
                    )

                # device_smart_healthy if assessment in [PASS, WARN, FAIL]
                # PASS => 1, otherwise => 0
                assessment = device_info.get("assessment", "").upper()
                if assessment in ["PASS", "WARN", "FAIL"]:
                    expected_val = 1 if assessment == "PASS" else 0
                    smart_healthy_found = any(
                        line.startswith("device_smart_healthy{") and
                        f'disk="{dev_name}"' in line and
                        line.endswith(f" {expected_val}")
                        for line in metrics
                    )
                    self.assertTrue(
                        smart_healthy_found,
                        f"Expected device_smart_healthy={expected_val} for {dev_name}, not found."
                    )

    def test_parse_if_attributes(self):
        """
        Test parse_if_attributes() for every JSON fixture in ./drives/.
        We do subTest() so each fixture is tested individually.
        """
        for fixture_path in self.fixture_files:
            fixture_name = os.path.basename(fixture_path)
            with self.subTest(msg=f"Testing if_attributes with {fixture_name}"):
                data = load_json_fixture(fixture_name)
                device_info = data["device_info"]
                if_attrs = data.get("if_attributes", {})

                device = self.create_mock_device_from_json(device_info, if_attrs)
                metrics = parse_if_attributes(device)

                dev_name = device_info["name"]
                dev_iface = device_info["interface"]
                dev_serial = device_info["serial"].lower()

                # For each numeric attribute in JSON, if it's in SMARTMON_ATTRS,
                # we expect a line in the script's output.
                for attr_key, attr_val in if_attrs.items():
                    # Convert from e.g. "criticalWarning" -> "critical_warning"
                    snake_key = re.sub(r'(?<!^)(?=[A-Z])', '_', attr_key).lower()

                    if isinstance(attr_val, (int, float)) and snake_key in SMARTMON_ATTRS:
                        # We expect e.g. critical_warning{disk="/dev/..."} <value>
                        expected_line = (
                            f"{snake_key}{{disk=\"{dev_name}\",type=\"{dev_iface}\",serial_number=\"{dev_serial}\"}} {attr_val}"
                        )
                        self.assertIn(
                            expected_line,
                            metrics,
                            f"Expected metric '{expected_line}' for attribute '{attr_key}' not found."
                        )
                    else:
                        # If it's not in SMARTMON_ATTRS or not numeric,
                        # we do NOT expect a line with that name+value
                        unexpected_line = (
                            f"{snake_key}{{disk=\"{dev_name}\",type=\"{dev_iface}\",serial_number=\"{dev_serial}\"}} {attr_val}"
                        )
                        self.assertNotIn(
                            unexpected_line,
                            metrics,
                            f"Unexpected metric '{unexpected_line}' found for {attr_key}."
                        )

                # Also ensure that non-numeric or disallowed attributes do not appear
                # For instance "notInSmartmonAttrs" should never appear.
                for line in metrics:
                    self.assertNotIn(
                        "not_in_smartmon_attrs",
                        line,
                        f"'notInSmartmonAttrs' attribute unexpectedly found in metric line: {line}"
                    )

    @patch("smartmon.run_command")
    @patch("smartmon.DeviceList")
    def test_main(self, mock_devicelist_class, mock_run_cmd):
        """
        End-to-end test of main() for every JSON fixture in ./drives/.
        This ensures we can handle multiple disks (multiple fixture files).
        """
        for fixture_path in self.fixture_files:
            fixture_name = os.path.basename(fixture_path)
            with self.subTest(msg=f"Testing main() with {fixture_name}"):
                data = load_json_fixture(fixture_name)
                device_info = data["device_info"]
                if_attrs = data.get("if_attributes", {})

                # Patch run_command to return a version & "active" power_mode
                def run_command_side_effect(cmd, parse_json=False):
                    if "--version" in cmd:
                        return "smartctl 7.3 5422 [x86_64-linux-5.15.0]\n..."
                    if "-n" in cmd and "standby" in cmd and parse_json:
                        return {"power_mode": "active"}
                    return ""

                mock_run_cmd.side_effect = run_command_side_effect

                # Mock a single device from the fixture
                device_mock = self.create_mock_device_from_json(device_info, if_attrs)

                # Make DeviceList() return our single mock device
                mock_dev_list = MagicMock()
                mock_dev_list.devices = [device_mock]
                mock_devicelist_class.return_value = mock_dev_list

                with patch("builtins.print") as mock_print:
                    main()

                    printed_lines = []
                    for call_args in mock_print.call_args_list:
                        printed_lines.extend(call_args[0][0].split("\n"))
                dev_name = device_info["name"]
                dev_iface = device_info["interface"]
                dev_serial = device_info["serial"].lower()

                # We expect a line for the run timestamp, e.g.:
                # smartmon_smartctl_run{disk="/dev/...",type="..."} 1671234567
                run_line_found = any(
                    line.startswith("smartmon_smartctl_run{") and
                    f'disk="{dev_name}"' in line and
                    f'type="{dev_iface}"' in line
                    for line in printed_lines
                )
                self.assertTrue(
                    run_line_found,
                    f"Expected 'smartmon_smartctl_run' metric line for {dev_name} not found."
                )

                # Because we mocked "power_mode": "active", we expect device_active=1
                active_line_found = any(
                    line.startswith("smartmon_device_active{") and
                    f'disk="{dev_name}"' in line and
                    f'serial_number="{dev_serial}"' in line and
                    line.endswith(" 1")
                    for line in printed_lines
                )
                self.assertTrue(
                    active_line_found,
                    f"Expected 'device_active{{...}} 1' line for {dev_name} not found."
                )

if __name__ == "__main__":
    unittest.main()
