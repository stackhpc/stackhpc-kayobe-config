set -euo pipefail

# TODO: Check trivy installed

# TODO: Check inputs - requires $1 as a distro and $2 as container iamge

# Make a fresh output directory
mkdir -p $1-image-scan-output

# Get built container images
docker image ls --filter "reference=ark.stackhpc.com/stackhpc-dev/$1-*:$2" > $1-container-images

# Make a file of imagename:tag
grep --invert-match --no-filename ^REPOSITORY $1-container-images |\
sed 's/ \+/:/g' |\
cut -f 1,2 -d: > $1-docker-images.txt

# If Trivy detects no vulnerabilities, add the image name to clean-images.txt.
# If there are vulnerabilities detected, generate a CSV summary and do not add
# to clean-images.txt.
while read -r image; do
  filename=$(basename $image | sed 's/:/\./g')
  if $(trivy image \
          --quiet \
          --exit-code 1 \
          --scanners vuln \
          --format json \
          --severity HIGH,CRITICAL \
          --output $1-image-scan-output/${filename}.json \
          --ignore-unfixed \
          $image); then
    # Clean up the output file for any images with no vulnerabilities
    rm -f $1-image-scan-output/${filename}.json

    # Add the image to the clean list
    echo "${image}" >> $1-clean-images.txt
  else
    # Add the image to the dirty list
    echo "${image}" >> $1-clean-images.txt
    
    # Write a header for the summary CSV
    echo '"PkgName","PkgPath","PkgID","VulnerabilityID","FixedVersion","PrimaryURL","Severity"' > $1-image-scan-output/${filename}.summary.csv

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
            | @csv' $1-image-scan-output/${filename}.json >> $1-image-scan-output/${filename}.summary.csv
  fi
done < $1-docker-images.txt
