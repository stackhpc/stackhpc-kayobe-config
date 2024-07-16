#!/usr/bin/env bash
set -eu

# Dependencies: nvme-cli, jq (packages)
# Based on code from
# - https://github.com/prometheus/node_exporter/blob/master/text_collector_examples/smartmon.sh
# - https://github.com/prometheus/node_exporter/blob/master/text_collector_examples/mellanox_hca_temp
# - https://github.com/vorlon/check_nvme/blob/master/check_nvme.sh
#
# Author: Henk <henk@wearespindle.com>

# Check if we are root
if [ "$EUID" -ne 0 ]; then
  echo "${0##*/}: Please run as root!" >&2
  exit 1
fi

# Check if programs are installed
if ! command -v nvme >/dev/null 2>&1; then
  echo "${0##*/}: nvme is not installed. Aborting." >&2
  exit 1
fi

# Set path to the DWPD ratings file
dwpd_file="/opt/kayobe/etc/monitoring/dwpd_ratings.yml"

# Function to load rated DWPD values from the YML file
load_dwpd_ratings() {
  declare -gA rated_dwpd
  if [[ -f "$dwpd_file" ]]; then
    while IFS= read -r line; do
      key="$(echo "$line" | jq -r '.model_name')"
      value="$(echo "$line" | jq -r '.rated_dwpd')"
      # Strip trailing spaces
      key="$(echo "$key" | sed 's/[[:space:]]*$//')"
      value="$(echo "$value" | sed 's/[[:space:]]*$//')"
      rated_dwpd["$key"]="$value"
    done < <(jq -c '.[]' "$dwpd_file")
  else
    echo "Warning: DWPD ratings file not found at $dwpd_file. Defaulting to 1 DWPD."
  fi
}

load_dwpd_ratings

output_format_awk="$(
  cat <<'OUTPUTAWK'
BEGIN { v = "" }
v != $1 {
  print "# HELP nvme_" $1 " SMART metric " $1;
  if ($1 ~ /_total$/)
    print "# TYPE nvme_" $1 " counter";
  else
    print "# TYPE nvme_" $1 " gauge";
  v = $1
}
{print "nvme_" $0}
OUTPUTAWK
)"

format_output() {
  sort | awk -F'{' "${output_format_awk}"
}

# Get the nvme-cli version
nvme_version="$(nvme version | awk '$1 == "nvme" {print $3}')"
echo "nvmecli{version=\"${nvme_version}\"} 1" | format_output

# Get devices (DevicePath, PhysicalSize and ModelNumber)
device_info="$(nvme list -o json | jq -c '.Devices[] | {DevicePath, PhysicalSize, ModelNumber}')"

# Convert device_info to an array
device_info_array=()
while IFS= read -r line; do
  device_info_array+=("$line")
done <<< "$device_info"

# Loop through the NVMe devices
for device_data in "${device_info_array[@]}"; do
  device="$(echo "$device_data" | jq -r '.DevicePath')"
  json_check="$(nvme smart-log -o json "${device}")"
  disk="${device##*/}"
  model_name="$(echo "$device_data" | jq -r '.ModelNumber')"

  physical_size="$(echo "$device_data" | jq -r '.PhysicalSize')"
  echo "physical_size_bytes{device=\"${disk}\",model=\"${model_name}\"} ${physical_size}"

  # The temperature value in JSON is in Kelvin, we want Celsius
  value_temperature="$(echo "$json_check" | jq '.temperature - 273')"
  echo "temperature_celsius{device=\"${disk}\",model=\"${model_name}\"} ${value_temperature}"

  # Get the rated DWPD from the dictionary or default to 1 if not found
  value_rated_dwpd="${rated_dwpd[$model_name]:-1}"
  echo "rated_dwpd{device=\"${disk}\",model=\"${model_name}\"} ${value_rated_dwpd}"

  value_available_spare="$(echo "$json_check" | jq '.avail_spare / 100')"
  echo "available_spare_ratio{device=\"${disk}\",model=\"${model_name}\"} ${value_available_spare}"

  value_available_spare_threshold="$(echo "$json_check" | jq '.spare_thresh / 100')"
  echo "available_spare_threshold_ratio{device=\"${disk}\",model=\"${model_name}\"} ${value_available_spare_threshold}"

  value_percentage_used="$(echo "$json_check" | jq '.percent_used / 100')"
  echo "percentage_used_ratio{device=\"${disk}\",model=\"${model_name}\"} ${value_percentage_used}"

  value_critical_warning="$(echo "$json_check" | jq '.critical_warning')"
  echo "critical_warning_total{device=\"${disk}\",model=\"${model_name}\"} ${value_critical_warning}"

  value_media_errors="$(echo "$json_check" | jq '.media_errors')"
  echo "media_errors_total{device=\"${disk}\",model=\"${model_name}\"} ${value_media_errors}"

  value_num_err_log_entries="$(echo "$json_check" | jq '.num_err_log_entries')"
  echo "num_err_log_entries_total{device=\"${disk}\",model=\"${model_name}\"} ${value_num_err_log_entries}"

  value_power_cycles="$(echo "$json_check" | jq '.power_cycles')"
  echo "power_cycles_total{device=\"${disk}\",model=\"${model_name}\"} ${value_power_cycles}"

  value_power_on_hours="$(echo "$json_check" | jq '.power_on_hours')"
  echo "power_on_hours_total{device=\"${disk}\",model=\"${model_name}\"} ${value_power_on_hours}"

  value_controller_busy_time="$(echo "$json_check" | jq '.controller_busy_time')"
  echo "controller_busy_time_seconds{device=\"${disk}\",model=\"${model_name}\"} ${value_controller_busy_time}"

  value_data_units_written="$(echo "$json_check" | jq '.data_units_written')"
  echo "data_units_written_total{device=\"${disk}\",model=\"${model_name}\"} ${value_data_units_written}"

  value_data_units_read="$(echo "$json_check" | jq '.data_units_read')"
  echo "data_units_read_total{device=\"${disk}\",model=\"${model_name}\"} ${value_data_units_read}"

  value_host_read_commands="$(echo "$json_check" | jq '.host_read_commands')"
  echo "host_read_commands_total{device=\"${disk}\",model=\"${model_name}\"} ${value_host_read_commands}"

  value_host_write_commands="$(echo "$json_check" | jq '.host_write_commands')"
  echo "host_write_commands_total{device=\"${disk}\",model=\"${model_name}\"} ${value_host_write_commands}"
done | format_output
