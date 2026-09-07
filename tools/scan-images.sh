#!/usr/bin/env bash
set -eo pipefail

# Disable telemetry and version check:
# https://github.com/aquasecurity/trivy/discussions/8945
export TRIVY_DISABLE_TELEMETRY=true
export TRIVY_SKIP_VERSION_CHECK=true

# Global variables
db_repository_args=" \
                  --db-repository ghcr.io/aquasecurity/trivy-db:2 \
                  --db-repository public.ecr.aws/aquasecurity/trivy-db \
                  --java-db-repository ghcr.io/aquasecurity/trivy-java-db:1 \
                  --java-db-repository public.ecr.aws/aquasecurity/trivy-java-db "

# download_dbs fetches the databases once before any scan starts, so the
# concurrent scans must not try to update them again.
db_skip_args=" --skip-db-update --skip-java-db-update "

# Trivy's filesystem scan cache is a single-writer database: concurrent scans
# cannot share it, and all but one fail to acquire its lock. Each scan keeps its
# own scan cache in memory instead. This is already the default for "trivy
# sbom", but not for "trivy image".
cache_args=" --cache-backend memory "

scan_common_args=" \
                  --exit-code 1 \
                  --scanners vuln \
                  --format json \
                  --severity HIGH,CRITICAL \
                  --ignore-unfixed \
                  $db_repository_args \
                  $db_skip_args \
                  $cache_args "

# Number of images to scan concurrently. Trivy parallelises the analysis of a
# single image, but scans only one image per invocation, so several invocations
# are needed to keep the runner busy. Lower this if the runner runs out of
# memory.
scan_parallelism="${SCAN_PARALLELISM:-4}"

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

# Download the vulnerability databases up front. The scans run concurrently, and
# would otherwise all try to populate the shared cache at the same time.
download_dbs() {
  # shellcheck disable=SC2086
  trivy image --download-db-only $db_repository_args
  # shellcheck disable=SC2086
  trivy image --download-java-db-only $db_repository_args
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
  local ignorefile=$2
  local family
  family="${imagename%%_*}"
  local global_vulnerabilities family_vulnerabilities image_vulnerabilities

  global_vulnerabilities=$(yq '.global_allowed_vulnerabilities[]' src/kayobe-config/etc/kayobe/trivy/allowed-vulnerabilities.yml 2> /dev/null)
  if [[ "$family" != "$imagename" ]]; then
    family_vulnerabilities=$(yq ".${family}_allowed_vulnerabilities[]" src/kayobe-config/etc/kayobe/trivy/allowed-vulnerabilities.yml 2> /dev/null)
  else
    family_vulnerabilities=""
  fi
  image_vulnerabilities=$(yq ".${imagename}_allowed_vulnerabilities[]" src/kayobe-config/etc/kayobe/trivy/allowed-vulnerabilities.yml 2> /dev/null)

  for vulnerability in $global_vulnerabilities $family_vulnerabilities $image_vulnerabilities; do
    echo "$vulnerability"
  done | sort -u > "$ignorefile"
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

# Categorise images based on severity. The verdict is recorded in the image's
# own output directory, and collate_results gathers them once every scan has
# finished, so that concurrent scans never append to the same file.
categorise_image() {
  local summary="$1"
  local image="$2"
  local outdir="$3"

  if [ "$(grep "CRITICAL" "$summary" -c)" -gt 0 ]; then
    echo "${image}" > "${outdir}/critical"
  else
    echo "${image}" > "${outdir}/high"
  fi
}

# Generate SBOM, return correct scan command for SBOM
generate_sbom() {
  local sbom="$1"
  local scan="$2"
  local image="$3"
  local ignorefile="$4"
  # shellcheck disable=SC2086
  trivy image \
        --debug \
        --format spdx-json \
        $db_skip_args \
        $cache_args \
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
    echo "trivy sbom $scan_common_args --ignorefile $ignorefile --output $scan $sbom"
  fi
}

# Scan images, generate SBOMs if requested
scan_image() {
  local image=$1
  local filename
  filename=$(basename "$image" | sed 's/:/\./g')
  local imagename
  imagename=$(echo "$filename" | cut -d "." -f 1 | sed 's/-/_/g')
  local outdir="image-scan-output/${imagename}"
  local sbom="${outdir}/${filename}-sbom.json"
  local scan="${outdir}/${filename}-scan.json"
  local summary="${outdir}/${filename}-summary.csv"
  # Each image gets its own ignore file, since concurrent scans would otherwise
  # overwrite each other's list of allowed vulnerabilities.
  local ignorefile="${outdir}/${filename}-trivyignore"

  mkdir -p "$outdir"
  generate_trivy_ignore "$imagename" "$ignorefile"

  # If SBOM is required, generate it first and scan the results, otherwise we
  # scan the image directly.
  if $want_sbom; then
    echo "Generating SBOM for $imagename"
    scan_command="$(generate_sbom "$sbom" "$scan" "$image" "$ignorefile")"
  else
    scan_command="trivy image $scan_common_args --ignorefile $ignorefile --output $scan $image"
  fi

  # Run scan against image or SBOM, format output. If no results, delete files.
  echo "Scanning $imagename for vulnerabilities"
  if $scan_command >& "$scan.log"; then
    rm -f "$scan"
    echo "${image}" > "${outdir}/clean"
  elif [ ! -f "$scan" ]; then
    (
      echo "ERROR: trivy scan encountered an error producing $scan"
      echo "Command: $scan_command"
      echo "==== trivy log ===="
      cat "$scan.log"
      if $want_sbom; then
        echo "==== sbom.json ===="
        cat "$sbom"
      fi
    ) 1>&2
    exit 1
  else
    generate_summary_csv "$scan" "$summary"
    categorise_image "$summary" "$image" "$outdir"
  fi
}

# Gather the per-image verdicts into the lists consumed by the workflow.
collate_results() {
  local category
  for category in clean high critical; do
    cat image-scan-output/*/"$category" > "image-scan-output/${category}-images.txt" 2> /dev/null || true
  done
}

# Main function
main() {
  if [[ ! $2 ]]; then
    usage
  fi

  want_sbom=false
  if [[ "$3" == "--sbom" ]]; then
    want_sbom=true
  fi

  set -u

  check_deps_installed
  file_prep
  download_dbs

  images=$(get_images "$1" "$2")

  # Scan the images concurrently. Each scan writes only to its own output
  # directory, so the workers do not need to coordinate.
  export scan_common_args db_skip_args cache_args want_sbom
  export -f scan_image generate_sbom generate_trivy_ignore generate_summary_csv categorise_image

  local status=0
  echo "$images" |
    xargs -r -P "$scan_parallelism" -I{} \
      bash -c 'set -eo pipefail; set -u; scan_image "$@"' _ {} || status=$?

  # Collate before failing, so that a failed run still reports the images it did
  # manage to scan.
  collate_results

  return $status
}

main "$@"
