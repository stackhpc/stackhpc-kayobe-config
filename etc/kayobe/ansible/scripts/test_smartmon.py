import glob
import json
import os
import sys
import tempfile
import types
import unittest
import math

CURRENT_DIR = os.path.dirname(__file__)
if CURRENT_DIR not in sys.path:
    sys.path.insert(0, CURRENT_DIR)

prometheus_stub = types.ModuleType("prometheus_client")

class DummyCollectorRegistry:
    pass


class DummyGauge:
    def __init__(self, *args, **kwargs):
        self._values = {}

    def labels(self, *args, **kwargs):
        return self

    def set(self, value):
        self._last_set = value


prometheus_stub.CollectorRegistry = DummyCollectorRegistry
prometheus_stub.Gauge = DummyGauge
prometheus_stub.write_to_textfile = lambda *args, **kwargs: None
sys.modules.setdefault("prometheus_client", prometheus_stub)

pySMART_stub = types.ModuleType("pySMART")

class DummyDeviceList:
    def __init__(self, devices=None):
        self.devices = devices or []

pySMART_stub.DeviceList = DummyDeviceList
sys.modules.setdefault("pySMART", pySMART_stub)

# Import after stubbing so smartmon pulls in the lightweight stand-ins above.
import smartmon
from unittest.mock import patch, MagicMock
from smartmon import (
    parse_device_info,
    parse_if_attributes,
    main,
    SMARTMON_ATTRS,
    camel_to_snake,
    collect_nvme_metrics,
    DATA_UNIT_BYTES,
    BYTES_PER_TB,
    DEFAULT_DWPD,
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
        # Collect all JSON fixtures that include both device metadata and the smartctl JSON payload.
        data_folder = os.path.join(os.path.dirname(__file__), "tests")
        cls.fixture_files = []
        for path in glob.glob(os.path.join(data_folder, "*.json")):
            with open(path, "r", encoding="utf-8") as fh:
                try:
                    data = json.load(fh)
                except json.JSONDecodeError:
                    continue
            if isinstance(data, dict) and "device_info" in data and "smartctl" in data:
                cls.fixture_files.append(path)
        if not cls.fixture_files:
            raise unittest.SkipTest("No SMART fixtures found")
        cls.primary_fixture = os.path.basename(cls.fixture_files[0])

    def create_mock_device_from_json(self, device_info, if_attributes=None):
        """
        Given a 'device_info' dict and optional 'if_attributes', build
        a MagicMock that mimics a pySMART Device object so the code under test
        sees the same shape it would on a live host.
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

    @patch("smartmon.smartctl_json")
    def test_collect_nvme_metrics_capacity(self, mock_smartctl_json):
        """
        Ensure collect_nvme_metrics emits NVMe capacity metrics.
        """
        data = load_json_fixture(self.primary_fixture)
        device_info = data["device_info"]
        smartctl_payload = data["smartctl"]
        mock_smartctl_json.return_value = smartctl_payload

        device = self.create_mock_device_from_json(device_info, data.get("if_attributes"))
        metrics = collect_nvme_metrics(device)

        disk_name = device_info["name"]
        serial_number = device_info["serial"].lower()
        disk_type = device_info["interface"]
        labels = f'disk="{disk_name}",serial_number="{serial_number}",type="{disk_type}"'

        total_capacity = float(smartctl_payload["nvme_total_capacity"])
        expected_capacity = f"smartmon_nvme_total_capacity_bytes{{{labels}}} {total_capacity}"
        expected_physical = f"smartmon_physical_size_bytes{{{labels}}} {total_capacity}"
        expected_unallocated = f"smartmon_nvme_unallocated_capacity_bytes{{{labels}}} {float(smartctl_payload.get('nvme_unallocated_capacity', 0))}"

        self.assertIn(expected_capacity, metrics)
        self.assertIn(expected_physical, metrics)
        self.assertIn(expected_unallocated, metrics)

    @patch("smartmon.smartctl_json")
    @patch("smartmon.get_rated_dwpd")
    def test_collect_nvme_metrics_dwpd(self, mock_get_dwpd, mock_smartctl_json):
        """
        Ensure collect_nvme_metrics emits NVMe DWPD metrics.
        """
        data = load_json_fixture(self.primary_fixture)
        device_info = data["device_info"]
        smartctl_payload = data["smartctl"]
        mock_smartctl_json.return_value = smartctl_payload
        mock_get_dwpd.return_value = 2.5

        device = self.create_mock_device_from_json(device_info, data.get("if_attributes"))
        metrics = collect_nvme_metrics(device)

        disk_name = device_info["name"]
        serial_number = device_info["serial"].lower()
        disk_type = device_info["interface"]
        labels = f'disk="{disk_name}",serial_number="{serial_number}",type="{disk_type}"'

        expected_rated = f"smartmon_nvme_rated_dwpd{{{labels}}} 2.5"
        self.assertIn(expected_rated, metrics)

    @patch("smartmon.smartctl_json")
    def test_collect_nvme_metrics_terabytes(self, mock_smartctl_json):
        """
        Ensure collect_nvme_metrics emits NVMe TB counters and skips raw data units.
        """
        data = load_json_fixture(self.primary_fixture)
        device_info = data["device_info"]
        smartctl_payload = data["smartctl"]
        mock_smartctl_json.return_value = smartctl_payload

        device = self.create_mock_device_from_json(device_info, data.get("if_attributes"))
        metrics = collect_nvme_metrics(device)

        disk_name = device_info["name"]
        serial_number = device_info["serial"].lower()
        disk_type = device_info["interface"]
        labels = f'disk="{disk_name}",serial_number="{serial_number}",type="{disk_type}"'

        health_log = smartctl_payload["nvme_smart_health_information_log"]
        expected_tb_read = (health_log["data_units_read"] * DATA_UNIT_BYTES) / BYTES_PER_TB
        expected_tb_written = (health_log["data_units_written"] * DATA_UNIT_BYTES) / BYTES_PER_TB

        self.assertTrue(
            any(
                line.startswith(f"smartmon_nvme_terabytes_read_total{{{labels}}}") and
                math.isclose(float(line.split()[-1]), expected_tb_read, rel_tol=1e-9)
                for line in metrics
            ),
            "Expected NVMe TB read metric not found or incorrect value.",
        )
        self.assertTrue(
            any(
                line.startswith(f"smartmon_nvme_terabytes_written_total{{{labels}}}") and
                math.isclose(float(line.split()[-1]), expected_tb_written, rel_tol=1e-9)
                for line in metrics
            ),
            "Expected NVMe TB written metric not found or incorrect value.",
        )

        self.assertFalse(
            any(line.startswith(f"smartmon_data_units_read{{{labels}}}") for line in metrics),
            "collect_nvme_metrics should not emit raw data_units_read when already provided by pySMART.",
        )

    def _execute_main_with_fixture(self, fixture_name, mock_write_metrics, mock_devicelist_class):
        """
        Helper to execute main() with a specific fixture and return the output metrics.
        """
        mock_write_metrics.reset_mock()
        data = load_json_fixture(fixture_name)
        smartctl_payload = data.get("smartctl", {})
        device_info = data["device_info"]
        if_attrs = data.get("if_attributes", {})

        # Mock a single device from the fixture
        device_mock = self.create_mock_device_from_json(device_info, if_attrs)

        # Make DeviceList() return our single mock device
        mock_dev_list = MagicMock()
        mock_dev_list.devices = [device_mock]
        mock_devicelist_class.return_value = mock_dev_list

        with patch("smartmon.smartctl_json", return_value=smartctl_payload), patch("smartmon.get_rated_dwpd", return_value=DEFAULT_DWPD):
            with tempfile.NamedTemporaryFile(mode="r+", delete=False) as tmpfile:
                path = tmpfile.name
                main(output_path=path)
                tmpfile.close()

        self.assertEqual(mock_write_metrics.call_count, 1)

        with open(path, "r", encoding="utf-8") as f:
            metrics_lines = [
                line.strip()
                for line in f.readlines()
                if line.strip() and not line.startswith("#")
            ]

        if os.path.exists(path):
            os.unlink(path)

        return metrics_lines, device_mock, device_info, smartctl_payload

    def _verify_fixture_metrics(self, metrics_lines, device_mock, device_info, smartctl_payload):
        """
        Helper to verify that the generated metrics match expectations.
        """
        expected_metrics = []
        expected_metrics.extend(parse_device_info(device_mock))
        expected_metrics.extend(parse_if_attributes(device_mock))

        iface = (device_info.get("interface") or "").lower()
        if iface == "nvme" or device_info.get("name", "").startswith("/dev/nvme"):
            with patch("smartmon.smartctl_json", return_value=smartctl_payload):
                expected_metrics.extend(collect_nvme_metrics(device_mock))

        for expected in expected_metrics:
            exp_metric, exp_val_str = expected.rsplit(" ", 1)
            exp_val = float(exp_val_str)
            found = any(
                (exp_metric in line) and
                math.isclose(float(line.rsplit(" ", 1)[1]), exp_val, rel_tol=1e-9)
                for line in metrics_lines
            )
            self.assertTrue(found, f"Expected metric '{expected}' not found")

        version_found = any(line.startswith("smartmon_smartctl_version{") for line in metrics_lines)
        self.assertTrue(version_found, "Expected 'smartmon_smartctl_version' metric not found in output file.")
        self.assertTrue(metrics_lines, "Metrics output file is empty.")

    @patch("smartmon.run_command")
    @patch("smartmon.DeviceList")
    @patch("smartmon.write_metrics_to_textfile")
    def test_main(self, mock_write_metrics, mock_devicelist_class, mock_run_cmd):
        """
        End-to-end test of main() for every JSON fixture in ./tests/.
        This ensures we can handle multiple disks (multiple fixture files).
        Checks metrics written to a temp file, and that write_metrics_to_textfile is called once.
        """
        def fake_write_metrics(metrics, output_path):
            # Instead of writing Prometheus text format we simply dump the raw metric
            # strings so assertions can compare them without the collector library.
            with open(output_path, "w", encoding="utf-8") as fh:
                fh.write("\n".join(metrics))

        mock_write_metrics.side_effect = fake_write_metrics

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
                metrics_lines, device_mock, device_info, smartctl_payload = self._execute_main_with_fixture(
                    fixture_name, mock_write_metrics, mock_devicelist_class
                )
                self._verify_fixture_metrics(metrics_lines, device_mock, device_info, smartctl_payload)

if __name__ == "__main__":
    unittest.main()
