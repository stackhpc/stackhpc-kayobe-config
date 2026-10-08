#!/usr/bin/env bash
set -eo pipefail

# Disable version check
export GRYPE_CHECK_FOR_APP_UPDATE=false
export SYFT_CHECK_FOR_APP_UPDATE=false

# Number of images to scan in parallel
scan_parallelism=${SCAN_PARALLELISM:-4}

# Global variables
# NOTE: --by-cve reports vulnerabilities by CVE ID where one exists (e.g.
# instead of a GHSA ID), and allows ignore rules to use either ID.
scan_common_args=" \
                  --fail-on high \
                  --output json \
                  --only-fixed \
                  --by-cve "

# Print usage instructions and error with wrong inputs
usage() {
  echo "Usage: scan-images.sh <os-distribution> <image-tag> [--sbom]"
  echo "Set SCAN_PARALLELISM to change the number of images scanned in parallel (default 4)"
  exit 2
}

# Check dependencies are installed, print installation instructions otherwise
check_deps_installed() {
  if ! grype --version > /dev/null 2>&1; then
    echo 'Please install grype: curl -sSfL https://raw.githubusercontent.com/anchore/grype/v0.120.0/install.sh | sudo sh -s -- -b /usr/local/bin v0.120.0'
    exit 1
  fi
  if ! syft --version > /dev/null 2>&1; then
    echo 'Please install syft: curl -sSfL https://raw.githubusercontent.com/anchore/syft/v1.54.0/install.sh | sudo sh -s -- -b /usr/local/bin v1.54.0'
    exit 1
  fi
  if ! yq --version > /dev/null 2>&1; then
    echo 'Please install yq: sudo dnf/apt install yq'
    exit 1
  fi
}

# Prepare output files
file_prep() {
  rm -rf image-scan-output
  mkdir -p image-scan-output
  touch image-scan-output/clean-images.txt image-scan-output/high-images.txt image-scan-output/critical-images.txt
}

# Gather image lists, largest first, so that the slowest scans start early
# rather than extending the end of the scan stage
get_images() {
  local output_file="$1-scanned-container-images.txt"

  docker image ls \
    --filter "reference=ark.stackhpc.com/stackhpc-dev/*:$2*" \
    --format "{{.Repository}}:{{.Tag}}" |
    while read -r image; do
      echo "$(docker image inspect --format '{{.Size}}' "$image") $image"
    done | sort -rn | cut -d " " -f 2 > "$output_file"

  cat "$output_file"
}

# Generate grype configuration file
generate_grype_config() {
  local imagename=$1
  local config=$2
  local family
  family="${imagename%%_*}"
  local global_vulnerabilities family_vulnerabilities image_vulnerabilities

  global_vulnerabilities=$(yq '.global_allowed_vulnerabilities[]' src/kayobe-config/etc/kayobe/grype/allowed-vulnerabilities.yml 2> /dev/null)
  if [[ "$family" != "$imagename" ]]; then
    family_vulnerabilities=$(yq ".${family}_allowed_vulnerabilities[]" src/kayobe-config/etc/kayobe/grype/allowed-vulnerabilities.yml 2> /dev/null)
  else
    family_vulnerabilities=""
  fi
  image_vulnerabilities=$(yq ".${imagename}_allowed_vulnerabilities[]" src/kayobe-config/etc/kayobe/grype/allowed-vulnerabilities.yml 2> /dev/null)

  echo "ignore:" > "$config"
  for vulnerability in $global_vulnerabilities $family_vulnerabilities $image_vulnerabilities; do
    echo "$vulnerability"
  done | sort -u | sed 's/^/  - vulnerability: /' >> "$config"
}

# Put results into CSV
generate_summary_csv() {
  local scan="$1"
  local summary="$2"

  echo '"PkgName","PkgPath","PkgID","VulnerabilityID","FixedVersion","PrimaryURL","Severity"' > "$summary"

  # NOTE: Grype reports matches of all severities, so filter on HIGH and
  # CRITICAL here.
  jq -r '.matches
      | map(select(.vulnerability.severity | test("^(high|critical)$"; "i")))
      | map(select(.artifact.name | test("^kernel|^linux-libc-dev") | not ))
      | group_by(.vulnerability.id)
      | map(
        [
          (map(.artifact.name) | unique | join(";")),
          (map(.artifact.locations[]?.path // empty) | unique | join(";")),
          .[0].artifact.purl,
          .[0].vulnerability.id,
          (.[0].vulnerability.fix.versions // [] | join(";")),
          .[0].vulnerability.dataSource,
          (.[0].vulnerability.severity | ascii_upcase)
          ]
        )
      | .[]
      | @csv' "$scan" >> "$summary"
}

# Categorise images based on severity
categorise_image() {
  local summary="$1"
  local image="$2"

  if [ "$(grep "CRITICAL" "$summary" -c)" -gt 0 ]; then
    echo "${image}" >> image-scan-output/critical-images.txt
  else
    echo "${image}" >> image-scan-output/high-images.txt
  fi
}

# Generate SBOM using syft, return correct scan command for SBOM
generate_sbom() {
  local sbom="$1"
  local config="$2"
  local image="$3"
  # NOTE: Omit files owned by packages from the SBOM. They make up most of its
  # size, and are not needed for vulnerability scanning.
  if ! SYFT_FILE_METADATA_SELECTION=none \
       SYFT_RELATIONSHIPS_PACKAGE_FILE_OWNERSHIP=false \
       syft "docker:$image" \
          --output spdx-json \
          -v \
          > "$sbom" 2> "$sbom.log" || [ ! -s "$sbom" ]; then
    # Print the error in a single write to avoid interleaving with output
    # from images scanned in parallel.
    echo "$(
      echo "ERROR: syft failed to produce the sbom file $sbom for $image"
      echo "==== syft log ===="
      cat "$sbom.log"
    )" 1>&2
    exit 1
  else
    echo "grype sbom:$sbom --config $config $scan_common_args"
  fi
}

# Scan images, generate SBOMs if requested
scan_image() {
  local image=$1
  local filename
  filename=$(basename "$image" | sed 's/:/\./g')
  local imagename
  imagename=$(echo "$filename" | cut -d "." -f 1 | sed 's/-/_/g')
  local sbom="image-scan-output/${imagename}/${filename}-sbom.json"
  local scan="image-scan-output/${imagename}/${filename}-scan.json"
  local summary="image-scan-output/${imagename}/${filename}-summary.csv"
  local config="image-scan-output/${imagename}/${filename}-grype.yaml"
  local scan_command

  mkdir -p "image-scan-output/$imagename"
  generate_grype_config "$imagename" "$config"

  # If SBOM is required, generate it first and scan the results, otherwise we
  # scan the image directly.
  if $generate_sbom; then
    echo "Generating SBOM for $imagename"
    scan_command="$(generate_sbom "$sbom" "$config" "$image")"
  else
    scan_command="grype docker:$image --config $config $scan_common_args"
  fi

  # Run scan against image or SBOM, format output. If no results, delete files.
  echo "Scanning $imagename for vulnerabilities"
  if $scan_command > "$scan" 2> "$scan.log"; then
    rm -f "$scan"
    echo "${image}" >> image-scan-output/clean-images.txt
  # Grype exits with code 2 if any vulnerability is found at or above the
  # --fail-on severity. Any other non-zero exit code is an error.
  elif [ $? -ne 2 ]; then
    # Print the error in a single write to avoid interleaving with output
    # from images scanned in parallel.
    echo "$(
      echo "ERROR: grype scan encountered an error producing $scan"
      echo "Command: $scan_command"
      echo "==== grype log ===="
      cat "$scan.log"
    )" 1>&2
    exit 1
  else
    # Drop matches ignored only because they have no fix, which make up most
    # of the scan output. Keep those ignored by the allowed vulnerabilities
    # list.
    jq -c '.ignoredMatches |= ((. // []) | map(select(any((.appliedIgnoreRules // [])[]; (.vulnerability // "") != ""))))' \
      "$scan" > "$scan.tmp"
    mv "$scan.tmp" "$scan"
    generate_summary_csv "$scan" "$summary"
    # The summary is empty if all vulnerabilities found are in kernel packages.
    if [ "$(tail -n +2 "$summary" | wc -l)" -eq 0 ]; then
      echo "${image}" >> image-scan-output/clean-images.txt
    else
      categorise_image "$summary" "$image"
    fi
  fi
}

# Scan an image in a subshell so that errexit applies, and record failures
scan_image_and_record_failure() {
  ( scan_image "$1" ) &
  wait $! || echo "$1" >> image-scan-output/failed-images.txt
}

# Scan images in parallel, up to scan_parallelism at a time. Stop starting new
# scans after a failure (best effort), and fail once the running scans have
# finished.
scan_images() {
  local images=$1

  for image in $images; do
    while (( $(jobs -rp | wc -l) >= scan_parallelism )); do
      wait -n || true
    done
    if [ -s image-scan-output/failed-images.txt ]; then
      break
    fi
    scan_image_and_record_failure "$image" &
  done
  wait

  if [ -s image-scan-output/failed-images.txt ]; then
    echo "ERROR: failed to scan images:" 1>&2
    cat image-scan-output/failed-images.txt 1>&2
    exit 1
  fi
}

# Main function
main() {
  if [[ ! $2 ]]; then
    usage
  fi

  generate_sbom=false
  if [[ "$3" == "--sbom" ]]; then
    generate_sbom=true
  fi

  set -u

  check_deps_installed
  file_prep

  # Update the vulnerability database once, and disable automatic updates.
  # Grype does not lock the database, so it must not be updated while scans
  # are running in parallel.
  grype db update
  export GRYPE_DB_AUTO_UPDATE=false

  images=$(get_images "$1" "$2")
  scan_images "$images"
}

main "$@"
