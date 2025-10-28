import copy
import importlib
import json
import os
import unittest
from unittest.mock import patch

from typing import Any

try:
    import prometheus_client  # noqa: F401
except ModuleNotFoundError:  # pragma: no cover
    prometheus_client = None


FIXTURE_DIR = os.path.join(os.path.dirname(__file__), "tests", "nvmemon")


def load_fixture(name):
    with open(os.path.join(FIXTURE_DIR, name), "r", encoding="utf-8") as handle:
        return json.load(handle)


def build_device_list(fixtures):
    """Merge namespace fixtures into the structure returned by nvme list."""

    namespace_names: set[str] = set()
    namespace_paths: set[str] = set()
    for fixture in fixtures:
        namespace = fixture.get("namespace", {})
        if not isinstance(namespace, dict):
            continue
        name = str(namespace.get("NameSpace") or namespace.get("Namespace") or "").strip()
        if name:
            namespace_names.add(name)
            namespace_paths.add(os.path.join("/dev", name))
        path = namespace.get("DevicePath")
        if isinstance(path, str) and path:
            namespace_paths.add(path)

    def namespace_matches(entry: dict[str, Any]) -> bool:
        ns_name = str(entry.get("NameSpace") or entry.get("Namespace") or "").strip()
        device_path = entry.get("DevicePath")
        return (
            (ns_name and ns_name in namespace_names)
            or (isinstance(device_path, str) and device_path in namespace_paths)
            or (ns_name and os.path.join("/dev", ns_name) in namespace_paths)
        )

    devices = []
    seen = set()
    for fixture in fixtures:
        device = fixture.get("device")
        if not isinstance(device, dict):
            continue
        signature = json.dumps(device, sort_keys=True)
        if signature in seen:
            continue

        if "Subsystems" in device:
            pruned_device = copy.deepcopy(device)
            subsystems = []
            for subsystem in pruned_device.get("Subsystems", []):
                if not isinstance(subsystem, dict):
                    continue
                controllers = []
                for controller in subsystem.get("Controllers", []):
                    if not isinstance(controller, dict):
                        continue
                    namespaces = [
                        copy.deepcopy(ns)
                        for ns in controller.get("Namespaces", [])
                        if isinstance(ns, dict) and namespace_matches(ns)
                    ]
                    if namespaces:
                        controller_copy = copy.deepcopy(controller)
                        controller_copy["Namespaces"] = namespaces
                        controllers.append(controller_copy)
                if controllers:
                    subsystem_copy = copy.deepcopy(subsystem)
                    subsystem_copy["Controllers"] = controllers
                    subsystems.append(subsystem_copy)
            if subsystems:
                pruned_device["Subsystems"] = subsystems
                devices.append(pruned_device)
        elif "Controllers" in device:
            controllers = []
            for controller in device.get("Controllers", []):
                if not isinstance(controller, dict):
                    continue
                namespaces = [
                    copy.deepcopy(ns)
                    for ns in controller.get("Namespaces", [])
                    if isinstance(ns, dict) and namespace_matches(ns)
                ]
                if namespaces:
                    controller_copy = copy.deepcopy(controller)
                    controller_copy["Namespaces"] = namespaces
                    controllers.append(controller_copy)
            if controllers:
                pruned_device = copy.deepcopy(device)
                pruned_device["Controllers"] = controllers
                devices.append(pruned_device)
        else:
            devices.append(copy.deepcopy(device))

        seen.add(signature)

    return {"Devices": devices}


@unittest.skipUnless(prometheus_client is not None, "prometheus_client not installed")
class TestNvmemonEndToEnd(unittest.TestCase):
    METRIC_KEY_MAP = {
        "nvme_nvmecli": "nvmecli",
        "nvme_available_spare_ratio": "avail_spare",
        "nvme_available_spare_threshold_ratio": "spare_thresh",
        "nvme_percentage_used_ratio": "percent_used",
        "nvme_temperature_celsius": "temperature",
    }

    @classmethod
    def setUpClass(cls):
        cls.fixture_names = sorted(
            name for name in os.listdir(FIXTURE_DIR) if name.endswith(".json")
        )

    class MetricRecorder:
        def __init__(self, name: str):
            self.name = name
            self.set_calls: dict[tuple[Any, ...], float] = {}
            self.inc_calls: dict[tuple[Any, ...], float] = {}
            self.info_calls: dict[tuple[Any, ...], Any] = {}
            self._labels: tuple[Any, ...] | None = None

        def labels(self, *values: Any):
            self._labels = tuple(values)
            return self

        def set(self, value: float):
            if self._labels is None:
                raise AssertionError(f"set() called on {self.name} without labels")
            self.set_calls[self._labels] = value

        def inc(self, value: float):
            if self._labels is None:
                raise AssertionError(f"inc() called on {self.name} without labels")
            self.inc_calls[self._labels] = self.inc_calls.get(self._labels, 0) + value

        def info(self, value: Any):
            if self._labels is None:
                raise AssertionError(f"info() called on {self.name} without labels")
            self.info_calls[self._labels] = value

    def run_collector(self, fixture_names):
        """Reload module to reset global metrics and replay nvme CLI interactions."""

        module = importlib.reload(importlib.import_module("nvmemon"))

        fixtures = [load_fixture(name) for name in fixture_names]
        device_list = build_device_list(fixtures)
        version = fixtures[0]["nvme_version"]
        smart_logs = {}
        for fixture in fixtures:
            namespace = fixture.get("namespace", {})
            device_path = namespace.get("DevicePath")
            if not isinstance(device_path, str) or not device_path:
                name = namespace.get("NameSpace") or namespace.get("Namespace")
                if isinstance(name, str) and name:
                    device_path = os.path.join("/dev", name)
            if isinstance(device_path, str) and device_path:
                smart_logs[device_path] = fixture["smart_log"]

        def exec_nvme_side_effect(*args):
            """Return canned nvme version output for the collector."""

            if not args:
                return b""
            if args[0] == "version":
                return f"nvme version {version}\n".encode("utf-8")
            raise AssertionError(f"Unexpected exec_nvme call: {args}")

        def exec_nvme_json_side_effect(*args, **kwargs):
            """Simulate nvme list/smart-log JSON responses using fixtures."""

            if not args:
                raise AssertionError("exec_nvme_json called without command")
            command = args[0]
            if command == "list":
                return device_list
            if command == "smart-log":
                device_path = args[1]
                try:
                    return smart_logs[device_path]
                except KeyError as exc:
                    raise AssertionError(f"No smart-log fixture for {device_path}") from exc
            raise AssertionError(f"Unexpected exec_nvme_json call: {args}")

        recorders = {name: self.MetricRecorder(name) for name in module.metrics}

        with patch.object(module, "metrics", recorders), patch.object(
            module, "exec_nvme", side_effect=exec_nvme_side_effect
        ), patch.object(module, "exec_nvme_json", side_effect=exec_nvme_json_side_effect):
            module.main()

        return recorders

    def metric_value(self, recorders, name, labels):
        metric_key = self.METRIC_KEY_MAP.get(name, name)
        recorder = recorders[metric_key]
        label_tuple = tuple(labels.values())
        if label_tuple in recorder.set_calls:
            return recorder.set_calls[label_tuple]
        if label_tuple in recorder.inc_calls:
            return recorder.inc_calls[label_tuple]
        raise self.failureException(f"Missing metric {name} with labels {labels}")

    def test_each_fixture(self):
        for fixture_name in self.fixture_names:
            with self.subTest(fixture=fixture_name):
                recorders = self.run_collector([fixture_name])
                fixture = load_fixture(fixture_name)

                version = fixture["nvme_version"]
                self.assertAlmostEqual(
                    self.metric_value(recorders, "nvme_nvmecli", {"version": version}),
                    1.0,
                )

                namespace = fixture["namespace"]
                controller = fixture["controller"]
                labels = {
                    "device": namespace.get("NameSpace") or namespace.get("Namespace"),
                    "model": controller.get("ModelNumber", "").strip(),
                    "serial_number": controller.get("SerialNumber", "").strip(),
                }

                self.assertAlmostEqual(
                    self.metric_value(recorders, "nvme_available_spare_ratio", labels),
                    fixture["smart_log"]["avail_spare"] / 100.0,
                )
                self.assertAlmostEqual(
                    self.metric_value(recorders, "nvme_available_spare_threshold_ratio", labels),
                    fixture["smart_log"]["spare_thresh"] / 100.0,
                )
                self.assertAlmostEqual(
                    self.metric_value(recorders, "nvme_percentage_used_ratio", labels),
                    fixture["smart_log"]["percent_used"] / 100.0,
                )
                expected_temp = fixture["smart_log"].get("temperature", 0) - 273
                self.assertAlmostEqual(
                    self.metric_value(recorders, "nvme_temperature_celsius", labels),
                    expected_temp if expected_temp else 0,
                )

    def test_modern_schema_metrics(self):
        fixture_names = ["system1_nvme1n1.json", "system1_nvme0n1.json"]
        fixtures = [load_fixture(name) for name in fixture_names]
        recorders = self.run_collector(fixture_names)

        version = fixtures[0]["nvme_version"]
        self.assertAlmostEqual(
            self.metric_value(recorders, "nvme_nvmecli", {"version": version}),
            1.0,
        )

        for fixture in fixtures:
            namespace = fixture["namespace"]
            controller = fixture["controller"]
            labels = {
                "device": namespace.get("NameSpace") or namespace.get("Namespace"),
                "model": controller.get("ModelNumber", "").strip(),
                "serial_number": controller.get("SerialNumber", "").strip(),
            }
            smart_log = fixture["smart_log"]

            self.assertAlmostEqual(
                self.metric_value(recorders, "nvme_available_spare_ratio", labels),
                smart_log["avail_spare"] / 100.0,
            )
            self.assertAlmostEqual(
                self.metric_value(recorders, "nvme_percentage_used_ratio", labels),
                smart_log["percent_used"] / 100.0,
            )
            expected_temp = smart_log.get("temperature", 0) - 273
            self.assertAlmostEqual(
                self.metric_value(recorders, "nvme_temperature_celsius", labels),
                expected_temp if expected_temp else 0,
            )

    def test_legacy_schema_metrics(self):
        fixture_name = "system2_nvme0n1.json"
        fixture = load_fixture(fixture_name)
        recorders = self.run_collector([fixture_name])

        self.assertAlmostEqual(
            self.metric_value(recorders, "nvme_nvmecli", {"version": fixture["nvme_version"]}),
            1.0,
        )

        namespace = fixture["namespace"]
        controller = fixture["controller"]
        labels = {
            "device": namespace.get("NameSpace") or namespace.get("Namespace"),
            "model": controller.get("ModelNumber", "").strip(),
            "serial_number": controller.get("SerialNumber", "").strip(),
        }
        smart_log = fixture["smart_log"]

        self.assertAlmostEqual(
            self.metric_value(recorders, "nvme_available_spare_ratio", labels),
            smart_log["avail_spare"] / 100.0,
        )
        self.assertAlmostEqual(
            self.metric_value(recorders, "nvme_percentage_used_ratio", labels),
            smart_log["percent_used"] / 100.0,
        )
        expected_temp = smart_log.get("temperature", 0) - 273
        self.assertAlmostEqual(
            self.metric_value(recorders, "nvme_temperature_celsius", labels),
            expected_temp if expected_temp else 0,
        )


if __name__ == "__main__":
    unittest.main()
