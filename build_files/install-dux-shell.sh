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

# Staged installs may not have a runnable Niri.
if [[ -z "${DESTDIR:-}" ]]; then
  niri_defaults=/usr/share/doc/niri/default-config.kdl
  config_dir=/usr/share/dux-shell/niri

  if [[ "${DESKTOP:-gnome}" == kde ]]; then
    # KService needs Plasma's menu to discover applications outside Plasma.
    test -f /etc/xdg/menus/plasma-applications.menu
    cat > /usr/lib/systemd/user/niri.service.d/20-kde.conf <<'EOF'
[Service]
Environment=XDG_MENU_PREFIX=plasma-
EOF
    # Keep Niri's other portal backends, including GNOME screen sharing.
    portal_defaults=/usr/share/xdg-desktop-portal/niri-portals.conf
    grep -qx '\[preferred\]' "$portal_defaults"
    install -d /etc/xdg/xdg-desktop-portal
    sed '/^org\.freedesktop\.impl\.portal\.FileChooser=/d; /^\[preferred\]$/a org.freedesktop.impl.portal.FileChooser=kde;' \
      "$portal_defaults" > /etc/xdg/xdg-desktop-portal/niri-portals.conf
    sed -i 's/spawn "nautilus";/spawn "dolphin";/' "$config_dir/dms/binds.kdl"
  fi

  if ! grep -qx 'input {' "$niri_defaults" ||
    ! grep -qx 'spawn-at-startup "waybar"' "$niri_defaults"; then
    echo "Niri defaults changed; review the Dux Shell integration." >&2
    exit 1
  fi

  # Keep upstream defaults; DMS owns input settings and replaces Waybar.
  sed '/^input {$/,/^}$/d; /^spawn-at-startup "waybar"$/d' \
    "$niri_defaults" >"$config_dir/upstream.kdl"
  sed -n '/^input {$/,/^}$/p' \
    "$niri_defaults" >"$config_dir/dms/input.kdl"
  [[ $(grep -c '^}$' "$config_dir/dms/input.kdl") == 1 ]]
  niri validate --config "$config_dir/config.kdl"
fi
