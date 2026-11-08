#!/bin/bash
# These arrays are consumed by the sourcing build.sh.
# shellcheck disable=SC2034
# Add/remove KDE-only packages here. Shared packages belong in build.sh.
# Niri uses Dolphin and KDE file dialogs on this variant too.
# Unlike GNOME, the KDE base ships KWallet rather than oo7.
DESKTOP_PACKAGES=(dolphin xdg-desktop-portal-kde oo7-daemon oo7-portal pam_oo7)
DESKTOP_REMOVE_PACKAGES=()
