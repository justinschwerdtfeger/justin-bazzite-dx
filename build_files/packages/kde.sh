#!/bin/bash
# These arrays are consumed by the sourcing build.sh.
# shellcheck disable=SC2034
# Add/remove KDE-only packages here. Shared packages belong in build.sh.
# Keep KDE's native file manager and portal alongside Niri's shared utilities.
DESKTOP_PACKAGES=(dolphin xdg-desktop-portal-kde)
DESKTOP_REMOVE_PACKAGES=()
