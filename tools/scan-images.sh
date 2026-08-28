#!/usr/bin/env bash
set -eo pipefail

# Disable telemetry and version check:
# https://github.com/aquasecurity/trivy/discussions/8945
export TRIVY_DISABLE_TELEMETRY=true
export TRIVY_SKIP_VERSION_CHECK=true

# Global variables
scan_common_args=" \
                  --exit-code 1 \
                  --scanners vuln \
                  --format json \
                  --severity HIGH,CRITICAL \
                  --ignore-unfixed \
                  --db-repository ghcr.io/aquasecurity/trivy-db:2 \
                  --db-repository public.ecr.aws/aquasecurity/trivy-db \
                  --java-db-repository ghcr.io/aquasecurity/trivy-java-db:1 \
                  --java-db-repository public.ecr.aws/aquasecurity/trivy-java-db "

# Print usage instructions and error with wrong inputs
usage() {
  echo "Usage: scan-images.sh <os-distribution> <image-tag> [--sbom]"
  exit 2
}

# Check dependencies are installed, print installation instructions otherwise
check_deps_installed() {
  if ! trivy --version > /dev/null; then
    echo 'Please install trivy: curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sudo sh -s -- -b /usr/local/bin v0.69.2'
    exit 1
  fi
  if ! yq --version > /dev/null; then
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

# Generate ignored vulnerabilities file
generate_trivy_ignore() {
  local imagename=$1
  local global_vulnerabilities
  global_vulnerabilities=$(yq .global_allowed_vulnerabilities[] src/kayobe-config/etc/kayobe/trivy/allowed-vulnerabilities.yml 2> /dev/null)
  local image_vulnerabilities
  image_vulnerabilities=$(yq ."$imagename"'_allowed_vulnerabilities[]' src/kayobe-config/etc/kayobe/trivy/allowed-vulnerabilities.yml 2> /dev/null)

  truncate -s 0 .trivyignore  # ensure we start from a clean slate
  for vulnerability in $global_vulnerabilities; do
    echo "$vulnerability" >> .trivyignore
  done
  for vulnerability in $image_vulnerabilities; do
    echo "$vulnerability" >> .trivyignore
  done
}

# Put results into CSV
generate_summary_csv() {
  local scan="$1"
  local summary="$2"

  echo '"PkgName","PkgPath","PkgID","VulnerabilityID","FixedVersion","PrimaryURL","Severity"' > "$summary"

  jq -r '.Results[]
      | select(.Vulnerabilities)
      | .Vulnerabilities
      | map(select(.PkgName | test("^kernel|^linux-libc-dev") | not ))
      | group_by(.VulnerabilityID)
      | map(
        [
          (map(.PkgName) | unique | join(";")),
          (map(.PkgPath | select( . != null )) | join(";")),
          .[0].PkgID,
          .[0].VulnerabilityID,
          .[0].FixedVersion,
          .[0].PrimaryURL,
          .[0].Severity
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

# Generate SBOM, return correct scan command for SBOM
generate_sbom() {
  local sbom="$1"
  local scan="$2"
  local image="$3"
  trivy image \
        --debug \
        --format spdx-json \
        --output "$sbom" \
        "$image" &> "$sbom.log"
  if [ ! -e "$sbom" ]; then
    (
      echo "ERROR: trivy image didn't produce the sbom file $sbom for $image" 1>&2
      echo "==== trivy log ===="
      cat "$sbom.log"
    ) 1>&2
    exit 1
  elif grep -q FATAL "$sbom.log"; then
    (
      echo "ERROR: trivy image encountered a fatal error producing $sbom for $image"
      echo "==== trivy log ===="
      cat "$sbom.log"
      echo "==== sbom.json ===="
      cat "$sbom"
    ) 1>&2
    exit 1
  else
    echo "trivy sbom $scan_common_args --output $scan $sbom"
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
  generate_trivy_ignore "$imagename"

  # If SBOM is required, generate it first and scan the results, otherwise we
  # scan the image directly.
  if $generate_sbom; then
    echo "Generating SBOM for $imagename"
    scan_command="$(generate_sbom "$sbom" "$scan" "$image")"
  else
    scan_command="trivy image $scan_common_args --output $scan $image"
  fi

  # Run scan against image or SBOM, format output. If no results, delete files.
  echo "Scanning $imagename for vulnerabilities"
  if $scan_command >& "$scan.log"; then
    rm -f "$scan"
    echo "${image}" >> image-scan-output/clean-images.txt
  elif [ ! -f "$scan" ]; then
    (
      echo "ERROR: trivy scan encountered an error producing $scan"
      echo "Command: $scan_command"
      echo "==== trivy log ===="
      cat "$scan.log"
      if $generate_sbom; then
        echo "==== sbom.json ===="
        cat "$sbom"
      fi
    ) 1>&2
    exit 1
  else
    generate_summary_csv "$scan" "$summary"
    categorise_image "$summary" "$image"
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
