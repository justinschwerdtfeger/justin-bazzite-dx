#!/bin/bash

set -ouex pipefail

### Install packages

# Packages can be installed from any enabled yum repo on the image.
# RPMfusion repos are available by default in ublue main images
# List of rpmfusion packages can be found here:
# https://mirrors.rpmfusion.org/mirrorlist?path=free/fedora/updates/39/x86_64/repoview/index.html&protocol=https&redirect=1

# this installs a package from fedora repos
dnf5 install -y tmux

# Install Niri from Copr
dnf5 -y copr enable yalter/niri
dnf5 -y install niri
dnf5 -y copr disable yalter/niri

# Install Niri Dependencies
dnf5 -y install brightnessctl
dnf5 -y install fuzzel
dnf5 -y install mako
dnf5 -y install waybar
dnf5 -y install swaybg
dnf5 -y install swayidle

# Install hyprlock from copr
dnf5 -y copr enable solopasha/hyprland
dnf5 -y install hyprlock
dnf5 -y copr disable solopasha/hyprland



# Use a COPR Example:
#
# dnf5 -y copr enable ublue-os/staging
# dnf5 -y install package
# Disable COPRs so they don't end up enabled on the final image:
# dnf5 -y copr disable ublue-os/staging

#### Example for enabling a System Unit File

systemctl enable podman.socket
