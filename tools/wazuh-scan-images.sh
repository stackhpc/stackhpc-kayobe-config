#!/bin/bash

# SBOM directory path
SBOM_DIR="/opt/kayobe/stackhpc/sboms"

# Ensure the SBOM directory exists
mkdir -p "$SBOM_DIR"

# Ensure the custom output template exists
cat <<EOL > "$SBOM_DIR/trivy-custom.tmpl"
"Package","Version Installed","Vulnerability ID","Severity","Title"
{{- range \$ri, \$r := . }}
{{- range \$vi, \$v := .Vulnerabilities }}
"{{ $v.PkgName }}","{{$v.InstalledVersion }}","{{ $v.VulnerabilityID }}","{{$v.Severity }}","{{$v.Title }}"
{{- end}}
{{- end }}
EOL

# Loop through each container image and process its SBOM
docker image ls --format "{{.Repository}}:{{.Tag}}" | sort | uniq | while read -r image; do
    # Generate SBOM filename
    sbom_file="$SBOM_DIR/$(echo "$image" | tr '/:' '_').sbom"

    # Generate SBOM if missing
    if [[ ! -f "$sbom_file" ]]; then
        echo "Generating SBOM for $image"
        if ! trivy image --quiet --format spdx-json --output "$sbom_file" "$image"; then
            echo "Failed to generate SBOM for $image. Skipping."
            continue
        fi
    fi
    
    echo "Scanning SBOM: $sbom_file"
    # Scan SBOM and prepend image info to each output line
    trivy sbom \
      --scanners vuln \
      --severity CRITICAL,HIGH \
      --ignore-unfixed \
      --quiet \
      --format template \
      --template "@$SBOM_DIR/trivy-custom.tmpl" \
      "$sbom_file" | \
    awk -v img="$image" '{print "Trivy:\"" img "\"," $0}'
done
