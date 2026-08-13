#!/bin/bash

set -ouex pipefail

### Install packages

# Packages can be installed from any enabled yum repo on the image.
# RPMfusion repos are available by default in ublue main images
# List of rpmfusion packages can be found here:
# https://mirrors.rpmfusion.org/mirrorlist?path=free/fedora/updates/39/x86_64/repoview/index.html&protocol=https&redirect=1

# Install DMS
# dnf5 -y copr enable avengemedia/dms
# dnf5 -y install dms
# dnf5 -y copr disable avengemedia/dms

dnf5 -y copr enable daniel-g-carrasco/wayland-scroll-factor
dnf5 -y install wayland-scroll-factor
dnf5 -y copr disable daniel-g-carrasco/wayland-scroll-factor

# Install Cursor
dnf5 -y config-manager setopt terra.enabled=1
dnf5 -y install cursor
dnf5 -y config-manager setopt terra.enabled=0

# Install Noctalia Shell
dnf5 -y config-manager setopt terra.enabled=1
dnf5 -y install noctalia-shell
dnf5 -y install cliphist # For clipboard History
dnf5 -y config-manager setopt terra.enabled=0

# Install haskell dependencies
dnf5 -y install gcc gcc-c++ gmp gmp-devel make ncurses ncurses-compat-libs xz perl

# Install wlsunset for Night light
dnf5 -y install wlsunset

# Install lazygit dependencies
dnf5 -y install ripgrep
dnf5 -y install fd-find
dnf5 -y install tree-sitter-cli
dnf5 -y install neovim python3-neovim

# Install pipx for brotab (tab search)
dnf5 -y install pipx
dnf5 -y install python3-devel

# Install Vicinae from Copr
dnf5 -y copr enable quadratech188/vicinae
dnf5 -y install vicinae
dnf5 -y copr disable quadratech188/vicinae

# Install Niri from Copr
dnf5 -y copr enable yalter/niri
dnf5 -y install niri
dnf5 -y copr disable yalter/niri

# Install Keyd from Copr
dnf5 -y copr enable alternateved/keyd
dnf5 -y install keyd
dnf5 -y copr disable alternateved/keyd

# Install Niri Dependencies
dnf5 -y install brightnessctl
dnf5 -y install fuzzel
dnf5 -y install mako
dnf5 -y install waybar
dnf5 -y install swaybg
dnf5 -y install swayidle

# Install Google Chrome
dnf5 config-manager addrepo --id="google-chrome" \
  --set=name="Google Chrome" \
  --set=baseurl="https://dl.google.com/linux/chrome/rpm/stable/x86_64" \
  --set=gpgkey="https://dl.google.com/linux/linux_signing_key.pub" \
  --set=gpgcheck=1
dnf5 makecache
dnf5 -y install google-chrome-stable
dnf5 config-manager setopt google-chrome.enabled=0

# # Dank Material Shell
# dnf5 -y copr enable avengemedia/dms
# dnf5 -y copr enable avengemedia/danklinux
# dnf5 -y install cliphist # For clipboard History
# dnf5 -y install dgop # For Resource monitoring
# dnf5 -y install danksearch # For File Search
# dnf5 -y install material-symbols-fonts # For DMS Font
# dnf5 -y install matugen # For Theme
# dnf5 -y install wl-mirror # For screen mirror
# dnf5 -y install qt6-qtmultimedia
# dnf5 -y install dms
# dnf5 -y copr disable avengemedia/danklinux
# dnf5 -y copr disable avengemedia/dms

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

dnf5 -y copr enable dejan/lazygit
dnf5 -y install lazygit
dnf5 -y copr disable dejan/lazygit

#### Example for enabling a System Unit File

systemctl enable podman.socket
