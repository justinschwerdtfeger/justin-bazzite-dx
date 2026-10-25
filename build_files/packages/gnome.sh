#!/bin/bash
# These arrays are consumed by the sourcing build.sh.
# shellcheck disable=SC2034
# Add/remove GNOME-only packages here. Shared packages belong in build.sh.
# Niri uses Nautilus for its shortcut and GNOME file chooser backend.
DESKTOP_PACKAGES=(nautilus)
DESKTOP_REMOVE_PACKAGES=()
