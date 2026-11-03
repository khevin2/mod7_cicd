#!/usr/bin/env bash
# Remove only the tag and image identity recorded by this Jenkins build.
set -Eeuo pipefail
image_ref=${IMAGE_REF:-}
[[ "$image_ref" =~ ^mod9-jenkins-webapp:[0-9a-f]{40}-[0-9]+$ ]] || exit 0
[[ -s build-metadata/scanned-image-id.txt ]] || exit 0
expected_id=$(<build-metadata/scanned-image-id.txt)
[[ "$expected_id" =~ ^sha256:[0-9a-f]{64}$ ]] || { echo 'Invalid recorded image ID; skipping cleanup.' >&2; exit 1; }
if current_id=$(docker image inspect --format '{{.Id}}' "$image_ref" 2>/dev/null); then
  if [[ "$current_id" != "$expected_id" ]]; then
    echo 'Image tag no longer matches this build; skipping cleanup.' >&2
    exit 1
  fi
  docker image rm "$image_ref" >/dev/null
else
  echo 'Could not inspect the build image; cleanup was not verified.' >&2
  exit 1
fi
