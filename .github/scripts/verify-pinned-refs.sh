#!/usr/bin/env bash
# Fails when a workflow references an action by a movable ref (branch or tag)
# or a container image without a sha256 digest. Movable refs let an upstream
# change run new code in every repository that calls these shared workflows.
set -euo pipefail

workflow_dir="${1:-.github/workflows}"
violations=0

report() {
  echo "::error file=$1,line=$2::$3"
  violations=$((violations + 1))
}

shopt -s nullglob
files=("$workflow_dir"/*.yml "$workflow_dir"/*.yaml)
if [ "${#files[@]}" -eq 0 ]; then
  echo "::error::No workflow files found in $workflow_dir"
  exit 1
fi

for file in "${files[@]}"; do
  line_number=0
  while IFS= read -r line || [ -n "$line" ]; do
    line_number=$((line_number + 1))
    code="${line%%#*}"

    if [[ "$code" =~ uses:[[:space:]]*([^[:space:]]+) ]]; then
      ref="${BASH_REMATCH[1]}"
      if [[ "$ref" == ./* ]]; then
        :
      elif [[ "$ref" == docker://* ]]; then
        [[ "$ref" == *@sha256:* ]] || report "$file" "$line_number" "Image without digest: $ref"
      elif ! [[ "$ref" =~ @[0-9a-f]{40}$ ]]; then
        report "$file" "$line_number" "Action not pinned to a commit SHA: $ref"
      fi
    fi

    if [[ "$code" =~ ^[[:space:]]*image:[[:space:]]*([^[:space:]]+) ]]; then
      [[ "${BASH_REMATCH[1]}" == *@sha256:* ]] \
        || report "$file" "$line_number" "Container image without digest: ${BASH_REMATCH[1]}"
    fi

    if [[ "$code" == *"docker run"* && "$code" != *@sha256:* ]]; then
      report "$file" "$line_number" "docker run without an image digest"
    fi
  done < "$file"
done

if [ "$violations" -gt 0 ]; then
  echo "$violations unpinned reference(s) found."
  exit 1
fi
echo "All actions and images are pinned."
