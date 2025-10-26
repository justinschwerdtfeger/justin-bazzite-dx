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

# Dank Material Shell
dnf5 -y copr enable avengemedia/dms
dnf5 -y install dms
dnf5 -y copr disable avengemedia/dms

# Noctalia Shell
dnf5 -y copr enable zhangyi6324/noctalia-shell
dnf5 -y install noctalia-shell
dnf5 -y copr disable zhangyi6324/noctalia-shell

# Global Protect Open Connect for UTD-VPN
dnf5 -y copr enable yuezk/globalprotect-openconnect
dnf5 -y install globalprotect-openconnect
dnf5 -y copr disable yuezk/globalprotect-openconnect

#### Example for enabling a System Unit File

systemctl enable podman.socket
