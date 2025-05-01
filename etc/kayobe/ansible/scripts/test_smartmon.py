import glob
import json
import os
import unittest
import tempfile
import math
from time import sleep

from unittest.mock import patch, MagicMock
from smartmon import (
    parse_device_info,
    parse_if_attributes,
    main,
    SMARTMON_ATTRS,
    camel_to_snake,
    write_metrics_to_textfile,
)

def load_json_fixture(filename):
    """
    Load a JSON file from the 'tests' subfolder.
    """
    path = os.path.join(os.path.dirname(__file__), "tests", filename)
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


class TestSmartMon(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Collect all *.json files from ./tests/
        data_folder = os.path.join(os.path.dirname(__file__), "tests")
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

    def _test_parse_device_info(self, fixture_name):
        """
        Helper method to test parse_device_info() for a single JSON fixture.
        """
        data = load_json_fixture(fixture_name)
        device_info = data["device_info"]

        device = self.create_mock_device_from_json(device_info)
        metrics = parse_device_info(device)

        dev_name = device_info["name"]
        dev_iface = device_info["interface"]
        dev_serial = device_info["serial"].lower()

        # The device_info line should exist for every device
        device_info_found = any(
            line.startswith("smartmon_device_info{") and
            f'disk="{dev_name}"' in line and
            f'type="{dev_iface}"' in line and
            f'serial_number="{dev_serial}"' in line
            for line in metrics
        )
        self.assertTrue(
            device_info_found,
            f"Expected a smartmon_device_info metric line for {dev_name} but didn't find it."
        )

        # If smart_capable is true, we expect device_smart_available = 1
        if device_info.get("smart_capable"):
            smart_available_found = any(
                line.startswith("smartmon_device_smart_available{") and
                f'disk="{dev_name}"' in line and
                f'serial_number="{dev_serial}"' in line and
                line.endswith(" 1.0")
                for line in metrics
            )
            self.assertTrue(
                smart_available_found,
                f"Expected smartmon_device_smart_available=1.0 for {dev_name}, not found."
            )

        # If smart_enabled is true, we expect device_smart_enabled = 1
        if device_info.get("smart_enabled"):
            smart_enabled_found = any(
                line.startswith("smartmon_device_smart_enabled{") and
                f'disk="{dev_name}"' in line and
                line.endswith(" 1.0")
                for line in metrics
            )
            self.assertTrue(
                smart_enabled_found,
                f"Expected smartmon_device_smart_enabled=1.0 for {dev_name}, not found."
            )

        # device_smart_healthy if assessment in [PASS, WARN, FAIL]
        # PASS => 1, otherwise => 0
        assessment = device_info.get("assessment", "").upper()
        if assessment in ["PASS", "WARN", "FAIL"]:
            expected_val = float(1) if assessment == "PASS" else float(0)
            smart_healthy_found = any(
                line.startswith("smartmon_device_smart_healthy{") and
                f'disk="{dev_name}"' in line and
                line.endswith(f" {expected_val}")
                for line in metrics
            )
            self.assertTrue(
                smart_healthy_found,
                f"Expected smartmon_device_smart_healthy={expected_val} for {dev_name}, not found."
            )

    def test_parse_device_info(self):
        """
        Test parse_device_info() for every JSON fixture in ./tests/.
        Each fixture is tested individually with clear error reporting.
        """
        for fixture_path in self.fixture_files:
            fixture_name = os.path.basename(fixture_path)
            with self.subTest(fixture=fixture_name):
                self._test_parse_device_info(fixture_name)

    def _test_parse_if_attributes(self, fixture_name):
        """
        Helper method to test parse_if_attributes() for a single JSON fixture.
        """
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
            snake_key = camel_to_snake(attr_key)

            if isinstance(attr_val, (int, float)) and snake_key in SMARTMON_ATTRS:
                expected_line = (
                    f"smartmon_{snake_key}{{disk=\"{dev_name}\",serial_number=\"{dev_serial}\",type=\"{dev_iface}\"}} {float(attr_val)}"
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
                    f"smartmon_{snake_key}{{disk=\"{dev_name}\",serial_number=\"{dev_serial}\",type=\"{dev_iface}\"}} {float(attr_val)}"
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

    def test_parse_if_attributes(self):
        """
        Test parse_if_attributes() for every JSON fixture in ./tests/.
        Each fixture is tested individually with clear error reporting.
        """
        for fixture_path in self.fixture_files:
            fixture_name = os.path.basename(fixture_path)
            with self.subTest(fixture=fixture_name):
                self._test_parse_if_attributes(fixture_name)

    @patch("smartmon.run_command")
    @patch("smartmon.DeviceList")
    @patch("smartmon.write_metrics_to_textfile", wraps=write_metrics_to_textfile)
    def test_main(self, mock_write_metrics, mock_devicelist_class, mock_run_cmd):
        """
        End-to-end test of main() for every JSON fixture in ./tests/.
        This ensures we can handle multiple disks (multiple fixture files).
        Checks metrics written to a temp file, and that write_metrics_to_textfile is called once.
        """

        # Patch run_command to return a version & "active" power_mode
        def run_command_side_effect(cmd, parse_json=False):
            if "--version" in cmd:
                return "smartctl 7.3 5422 [x86_64-linux-5.15.0]\n..."
            if "-n" in cmd and "standby" in cmd and parse_json:
                return {"power_mode": "active"}
            return ""

        mock_run_cmd.side_effect = run_command_side_effect

        for fixture_path in self.fixture_files:
            fixture_name = os.path.basename(fixture_path)
            with self.subTest(msg=f"Testing main() with {fixture_name}"):
                mock_write_metrics.reset_mock()
                data = load_json_fixture(fixture_name)
                device_info = data["device_info"]
                if_attrs = data.get("if_attributes", {})

                # Mock a single device from the fixture
                device_mock = self.create_mock_device_from_json(device_info, if_attrs)

                # Make DeviceList() return our single mock device
                mock_dev_list = MagicMock()
                mock_dev_list.devices = [device_mock]
                mock_devicelist_class.return_value = mock_dev_list

                with tempfile.NamedTemporaryFile(mode="r+", delete_on_close=False) as tmpfile:
                    path= tmpfile.name
                    main(output_path=path)
                    tmpfile.close()

                    # Ensure write_metrics_to_textfile was called once
                    self.assertEqual(mock_write_metrics.call_count, 1)

                    with open(path, "r") as f:
                        # Read the metrics from the file
                        metrics_lines = [line.strip() for line in f.readlines() if line.strip() and not line.startswith('#')]
                        print(f"Metrics lines: {metrics_lines}")

                # Generate expected metrics using the parse functions
                expected_metrics = []
                expected_metrics.extend(parse_device_info(device_mock))
                expected_metrics.extend(parse_if_attributes(device_mock))

                # Check that all expected metrics are present in the file
                for expected in expected_metrics:
                    exp_metric, exp_val_str = expected.rsplit(" ", 1)
                    exp_val = float(exp_val_str)
                    found = any(
                        (exp_metric in line) and
                        math.isclose(float(line.rsplit(" ", 1)[1]), exp_val)
                        for line in metrics_lines
                    )
                    self.assertTrue(found, f"Expected metric '{expected}' not found")

                # Check that smartctl_version metric is present
                version_found = any(line.startswith("smartmon_smartctl_version{") for line in metrics_lines)
                self.assertTrue(version_found, "Expected 'smartmon_smartctl_version' metric not found in output file.")

                # Check that the output file is not empty
                self.assertTrue(metrics_lines, "Metrics output file is empty.")

if __name__ == "__main__":
    unittest.main()
