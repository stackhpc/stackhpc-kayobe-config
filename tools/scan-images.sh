#!/usr/bin/env bash
set -eo pipefail

# Check correct usage
if [[ ! $2 ]]; then
  echo "Usage: scan-images.sh <os-distribution> <image-tag>"
  exit 2
fi

set -u

# Check that trivy is installed
if ! trivy --version; then
  echo 'Please install trivy: curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin v0.49.1'
fi

# Clear any previous outputs
rm -rf image-scan-output

# Make a fresh output directory
mkdir -p image-scan-output

# Get built container images
docker image ls --filter "reference=ark.stackhpc.com/stackhpc-dev/$1-*:$2" > $1-scanned-container-images.txt

# Make a file of imagename:tag
images=$(grep --invert-match --no-filename ^REPOSITORY $1-scanned-container-images.txt | sed 's/ \+/:/g' | cut -f 1,2 -d:)

# Ensure output files exist
touch image-scan-output/clean-images.txt image-scan-output/dirty-images.txt image-scan-output/critical-images.txt

# If Trivy detects no vulnerabilities, add the image name to clean-images.txt.
# If there are vulnerabilities detected, add it to dirty-images.txt and
# generate a csv summary
# If the image contains at least one critical vulnerabilities, add it to
# critical-images.txt
for image in $images; do
  filename=$(basename $image | sed 's/:/\./g')
  if $(trivy image \
          --quiet \
          --exit-code 1 \
          --scanners vuln \
          --format json \
          --severity HIGH,CRITICAL \
          --output image-scan-output/${filename}.json \
          --ignore-unfixed \
          $image); then
    # Clean up the output file for any images with no vulnerabilities
    rm -f image-scan-output/${filename}.json

    # Add the image to the clean list
    echo "${image}" >> image-scan-output/clean-images.txt
  else
    # Add the image to the dirty list
    echo "${image}" >> image-scan-output/dirty-images.txt

    # Write a header for the summary CSV
    echo '"PkgName","PkgPath","PkgID","VulnerabilityID","FixedVersion","PrimaryURL","Severity"' > image-scan-output/${filename}.summary.csv

    # Write the summary CSV data
    jq -r '.Results[]
            | select(.Vulnerabilities)
            | .Vulnerabilities
            # Ignore packages with "kernel" in the PkgName
            | map(select(.PkgName | test("kernel") | not ))
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
            | @csv' image-scan-output/${filename}.json >> image-scan-output/${filename}.summary.csv

    if [ $(grep "CRITICAL" image-scan-output/${filename}.summary.csv -c) -gt 0 ]; then
      # If the image contains critical vulnerabilities, add the image to critical list
      echo "${image}" >> image-scan-output/critical-images.txt
    fi
  fi
done
