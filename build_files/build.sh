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

# Dank Material Shell
dnf5 -y copr enable avengemedia/dms
dnf5 -y copr enable avengemedia/danklinux
dnf5 -y install cliphist # For clipboard History
dnf5 -y install dgop # For Resource monitoring
dnf5 -y install danksearch # For File Search
dnf5 -y install material-symbols-fonts # For DMS Font
dnf5 -y install matugen # For Theme 
dnf5 -y install wl-mirror # For screen mirror
dnf5 -y install qt6-qtmultimedia 
dnf5 -y install dms
dnf5 -y copr disable avengemedia/danklinux
dnf5 -y copr disable avengemedia/dms


# Global Protect Open Connect for UTD-VPN
dnf5 -y copr enable yuezk/globalprotect-openconnect
dnf5 -y install globalprotect-openconnect
dnf5 -y copr disable yuezk/globalprotect-openconnect

# Install Tauri Dependencies
dnf5 -y install webkit2gtk4.1-devel \
  openssl-devel \
  curl \
  wget \
  file \
  libappindicator-gtk3-devel \
  librsvg2-devel \
  libxdo-devel
dnf5 -y group install "c-development"

dnf5 -y install golang

dnf5 -y copr enable dejan/lazygit
dnf5 -y install lazygit
dnf5 -y copr disable dejan/lazygit

dnf5 config-manager addrepo --id="antigravity-rpm" \
    --set=name="Antigravity RPM Repository" \
    --set=baseurl="https://us-central1-yum.pkg.dev/projects/antigravity-auto-updater-dev/antigravity-rpm" \
    --set=gpgcheck=0
dnf5 makecache
dnf5 -y install antigravity
dnf5 config-manager setopt antigravity-rpm.enabled=0

#### Example for enabling a System Unit File

systemctl enable podman.socket
