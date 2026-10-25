#!/bin/bash
# These arrays are consumed by the sourcing build.sh.
# shellcheck disable=SC2034
# Add/remove GNOME-only packages here. Shared packages belong in build.sh.
# The GNOME base already supplies its native desktop and file manager.
DESKTOP_PACKAGES=()
DESKTOP_REMOVE_PACKAGES=()
