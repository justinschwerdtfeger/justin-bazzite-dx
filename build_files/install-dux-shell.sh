#!/bin/bash

set -euo pipefail

if [[ "$(uname -m)" != x86_64 ]]; then
  echo "The Dux Shell prebuilt release only supports Linux x86_64." >&2
  exit 1
fi

download_dir=$(mktemp -d)
trap 'rm -rf "$download_dir"' EXIT

curl --fail --location --retry 3 \
  https://github.com/justinschwerdtfeger/dux-shell/releases/latest/download/metadata.json \
  --output "${download_dir}/metadata.json"
release=$(jq --exit-status --raw-output '
  select(.repository == "justinschwerdtfeger/dux-shell" and
         .branch == "justin-stable" and .platform == "linux-amd64") |
  .release | select(test("^justin-[0-9a-f]{40}$"))
' "${download_dir}/metadata.json")
archive="dms-${release}-linux-amd64.tar.gz"
sha256=$(jq --exit-status --raw-output --arg archive "$archive" '
  select(.archive == $archive) | .sha256 | select(test("^[0-9a-f]{64}$"))
' "${download_dir}/metadata.json")

curl --fail --location --retry 3 \
  "https://github.com/justinschwerdtfeger/dux-shell/releases/download/${release}/${archive}" \
  --output "${download_dir}/${archive}"
printf '%s  %s\n' "$sha256" "${download_dir}/${archive}" | sha256sum --check --strict

# The bundle includes the embedded UI, user service, desktop entries, and icon.
# DESTDIR allows installation into a staging directory for verification.
tar --extract --gzip --file "${download_dir}/${archive}" \
  --directory "${DESTDIR:-/}" --no-same-owner
install -Dm644 "${download_dir}/metadata.json" "${DESTDIR:-/}/usr/share/dux-shell/metadata.json"
