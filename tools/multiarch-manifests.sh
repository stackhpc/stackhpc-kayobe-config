#!/usr/bin/env bash
# Script used by the Image build workflow to build & push multiarch manifests.

set -o errexit
set -o xtrace
set -o pipefail

mkdir -p logs
images=$(cat all-pushed-images.txt | sort | uniq)

# Filter out Ubuntu and Rocky Bifrost images
manifest_images=$(echo "$images" \
  | sed -nE 's/-(amd64|aarch64)$//p' \
  | sort | uniq)

if [ -z "$manifest_images" ]; then
  echo "No Rocky overcloud images found. Skipping manifest creation." | tee -a logs/manifest-creation.log
  exit 0
fi

for base_image in $manifest_images; do
  arch_images=""
  for arch in amd64 aarch64; do
    arch_image="${base_image}-${arch}"
    # Check if the image exists in the registry
    if docker manifest inspect "$arch_image" > /dev/null 2>&1; then
      arch_images="$arch_images $arch_image"
    fi
  done
  if [ -n "$arch_images" ]; then
    echo "Creating manifest for $base_image with images:$arch_images" | tee -a logs/manifest-creation.log
    docker manifest create "$base_image" $arch_images | tee -a logs/manifest-creation.log
    docker manifest push "$base_image" | tee -a logs/manifest-creation.log
  else
    echo "No images found for $base_image, skipping." | tee -a logs/manifest-creation.log
  fi
done
