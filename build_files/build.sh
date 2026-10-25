#!/bin/bash

set -ouex pipefail

if [[ "$(uname -m)" != x86_64 ]]; then
  echo "The Dux Shell prebuilt release only supports Linux x86_64." >&2
  exit 1
fi

case "${DESKTOP:-gnome}" in
  gnome|kde) ;;
  *) echo "Unsupported desktop: $DESKTOP (expected gnome or kde)" >&2; exit 1 ;;
esac
script_dir=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
# shellcheck source=build_files/packages/gnome.sh
source "$script_dir/packages/${DESKTOP:-gnome}.sh"

### Install packages

# Install browsers and monitoring tools in one transaction.
dnf5 -y install firefox wireshark iotop
rpm -q firefox

# Packages can be installed from any enabled yum repo on the image.
# RPMfusion repos are available by default in ublue main images
# List of rpmfusion packages can be found here:
# https://mirrors.rpmfusion.org/mirrorlist?path=free/fedora/updates/39/x86_64/repoview/index.html&protocol=https&redirect=1

# Dux Shell uses the prebuilt custom release; keep its runtime dependencies.
dnf5 -y copr enable avengemedia/danklinux
dnf5 -y config-manager setopt terra.enabled=0
dnf5 -y --refresh install \
  cava \
  dankcalendar-git \
  dgop \
  danksearch \
  matugen \
  quickshell \
  accountsservice \
  wl-mirror \
  curl \
  jq \
  tar \
  gzip \
  qt6-qtmultimedia
# Niri is installed below from yalter/niri.
rpm -q quickshell accountsservice cava dankcalendar-git dgop danksearch matugen qt6-qtmultimedia
dnf5 -y copr disable avengemedia/danklinux

# Install development tools and desktop utilities with Terra and the added Coprs
# disabled. One transaction avoids repeating dependency solving and RPM setup.
dnf5 -y install \
  gcc gcc-c++ make ncurses xz perl \
  wlsunset \
  ripgrep fd-find tree-sitter-cli neovim python3-neovim \
  pipx python3-devel \
  qt5ct qt6ct \
  brightnessctl \
  foot wl-clipboard \
  xdg-desktop-portal-gtk xdg-desktop-portal-gnome gnome-keyring \
  wget file
# Niri shares the screen-sharing portal and keyring on both desktops.
# File managers and the file chooser backend follow the desktop variant.
if (( ${#DESKTOP_PACKAGES[@]} )); then
  dnf5 -y install "${DESKTOP_PACKAGES[@]}"
fi
dnf5 -y group install "c-development"

# Install the packaged Qt5 and Qt6 theme plugins from Copr.
dnf5 -y copr enable desertedman/qtengine
dnf5 -y install qtengine
rpm -q qt5ct qt6ct qtengine
dnf5 -y copr disable desertedman/qtengine

# Terra packages share a transaction; keep Terra disabled for other installs.
dnf5 -y config-manager setopt terra.enabled=1
dnf5 -y install noctalia cliphist cursor
dnf5 -y config-manager setopt terra.enabled=0

dnf5 -y copr enable daniel-g-carrasco/wayland-scroll-factor
dnf5 -y install wayland-scroll-factor
dnf5 -y copr disable daniel-g-carrasco/wayland-scroll-factor

# Install Vicinae from Copr
dnf5 -y copr enable quadratech188/vicinae
dnf5 -y install vicinae
dnf5 -y copr disable quadratech188/vicinae

# Install Niri from Copr
dnf5 -y copr enable yalter/niri
dnf5 -y install niri xwayland-satellite
dnf5 -y copr disable yalter/niri

# Install Keyd from Copr
dnf5 -y copr enable alternateved/keyd
dnf5 -y install keyd
dnf5 -y copr disable alternateved/keyd

# Install Google Chrome
dnf5 config-manager addrepo --id="google-chrome" \
  --set=name="Google Chrome" \
  --set=baseurl="https://dl.google.com/linux/chrome/rpm/stable/x86_64" \
  --set=gpgkey="https://dl.google.com/linux/linux_signing_key.pub" \
  --set=gpgcheck=1
# install fetches the new repo's metadata on demand.
dnf5 -y install google-chrome-stable
dnf5 config-manager setopt google-chrome.enabled=0


# Global Protect Open Connect for UTD-VPN
dnf5 -y copr enable yuezk/globalprotect-openconnect
dnf5 -y install globalprotect-openconnect
dnf5 -y copr disable yuezk/globalprotect-openconnect

dnf5 -y copr enable dejan/lazygit
dnf5 -y install lazygit
dnf5 -y copr disable dejan/lazygit

#### Example for enabling a System Unit File

systemctl enable podman.socket

if (( ${#DESKTOP_REMOVE_PACKAGES[@]} )); then
  dnf5 -y remove "${DESKTOP_REMOVE_PACKAGES[@]}"
fi
