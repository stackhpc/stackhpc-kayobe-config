#!/usr/bin/env bash
set -eo pipefail

# Disable telemetry and version check:
export GRYPE_CHECK_FOR_APP_UPDATE=false
export SYFT_CHECK_FOR_APP_UPDATE=false

# Global variables
scan_common_args=" \
                  --fail-on high \
                  --output json \
                  --only-fixed "

# Print usage instructions and error with wrong inputs
usage() {
  echo "Usage: scan-images.sh <os-distribution> <image-tag> [--sbom]"
  exit 2
}

# Check dependencies are installed, print installation instructions otherwise
check_deps_installed() {
  if ! grype --version > /dev/null 2>&1; then
    echo 'Please install grype: curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sh -s -- -b /usr/local/bin'
    exit 1
  fi
  if ! syft --version > /dev/null 2>&1; then
    echo 'Please install syft: curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin'
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

# Gather image lists
get_images() {
  local output_file="$1-scanned-container-images.txt"

  docker image ls \
    --filter "reference=ark.stackhpc.com/stackhpc-dev/*:$2*" \
    --format "{{.Repository}}:{{.Tag}}" \
    > "$output_file"

  cat "$output_file"
}

# Generate grype configuration file
generate_grype_config() {
  local imagename=$1
  local global_vulnerabilities
  global_vulnerabilities=$(yq .global_allowed_vulnerabilities[] src/kayobe-config/etc/kayobe/grype/allowed-vulnerabilities.yml 2> /dev/null)
  local image_vulnerabilities
  image_vulnerabilities=$(yq ."$imagename"'_allowed_vulnerabilities[]' src/kayobe-config/etc/kayobe/grype/allowed-vulnerabilities.yml 2> /dev/null)

  echo "ignore:" > .grype.yaml
  for vulnerability in $global_vulnerabilities; do
    echo "  - vulnerability: $vulnerability" >> .grype.yaml
  done
  for vulnerability in $image_vulnerabilities; do
    echo "  - vulnerability: $vulnerability" >> .grype.yaml
  done
}

# Put results into CSV
generate_summary_csv() {
  local scan="$1"
  local summary="$2"

  echo '"PkgName","PkgPath","PkgID","VulnerabilityID","FixedVersion","PrimaryURL","Severity"' > "$summary"

  jq -r '.matches
      | map(select(.artifact.name | test("kernel") | not ))
      | group_by(.vulnerability.id)
      | map(
        [
          (map(.artifact.name) | unique | join(";")),
          (map(.artifact.locations[]?.path // empty) | unique | join(";")),
          .[0].artifact.purl,
          .[0].vulnerability.id,
          (.[0].vulnerability.fix.versions | join(";")),
          (.[0].vulnerability.urls | first),
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
  local scan="$2"
  local image="$3"
  syft "$image" \
        -o spdx-json \
        > "$sbom" 2> "$sbom.log"

  if [ ! -s "$sbom" ]; then
    (
      echo "ERROR: syft didn't produce the sbom file $sbom for $image" 1>&2
      echo "==== syft log ===="
      cat "$sbom.log"
    ) 1>&2
    exit 1
  else
    echo "grype $sbom $scan_common_args"
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

  mkdir -p "image-scan-output/$imagename"
  generate_grype_config "$imagename"

  # If SBOM is required, generate it first and scan the results, otherwise we
  # scan the image directly.
  if $generate_sbom; then
    echo "Generating SBOM for $imagename"
    scan_command="$(generate_sbom "$sbom" "$scan" "$image")"
  else
    scan_command="grype $image $scan_common_args"
  fi

  # Run scan against image or SBOM, format output. If no results, delete files.
  echo "Scanning $imagename for vulnerabilities"
  if $scan_command > "$scan" 2> "$scan.log"; then
    rm -f "$scan"
    echo "${image}" >> image-scan-output/clean-images.txt
  # return code is 2 if a vulnerability is found with a severity higher than
  # configured
  elif [ $? -ne 2 ]; then
    (
      echo "ERROR: grype scan encountered an error producing $scan"
      echo "Command: $scan_command"
      echo "==== grype log ===="
      cat "$scan.log"
      if $generate_sbom; then
        echo "==== sbom.json ===="
        cat "$sbom"
      fi
    ) 1>&2
    exit 1
  else
    generate_summary_csv "$scan" "$summary"
    if [ "$(tail -n +2 "$summary" | wc -l)" -eq 0 ]; then
       echo "${image}" >> image-scan-output/clean-images.txt
    else
       categorise_image "$summary" "$image"
    fi
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

  images=$(get_images "$1" "$2")
  for image in $images; do
    scan_image "$image"
  done
}

main "$@"
