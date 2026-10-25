#!/bin/bash

set -ouex pipefail

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
  gcc gcc-c++ gmp gmp-devel make ncurses ncurses-compat-libs xz perl \
  wlsunset \
  ripgrep fd-find tree-sitter-cli neovim python3-neovim \
  pipx python3-devel \
  python3-pip \
  qt5ct qt6ct \
  cmake extra-cmake-modules \
  qt5-qtbase-devel qt5-qtbase-private-devel qt5-qtbase-static qt5-qtquickcontrols2-devel \
  qt6-qtbase-devel qt6-qtbase-private-devel qt6-qtdeclarative-devel \
  kf5-kconfig-devel kf5-kconfigwidgets-devel kf5-kiconthemes-devel \
  kf6-kconfig-devel kf6-kcolorscheme-devel kf6-kiconthemes-devel \
  brightnessctl \
  webkit2gtk4.1-devel openssl-devel curl wget file \
  libappindicator-gtk3-devel librsvg2-devel libxdo-devel
dnf5 -y group install "c-development"

# qtengine is not packaged in the enabled repositories. Build both Qt plugins
# against this image's Qt libraries, using Fedora's actual plugin directories.
qtengine_revision=00db92c00f079bf68c4538f9def1b344b97ada0b
qtengine_dir=$(mktemp -d)
curl --fail --location --retry 3 \
  "https://codeload.github.com/kossLAN/qtengine/tar.gz/${qtengine_revision}" \
  --output "${qtengine_dir}/source.tar.gz"
printf '%s  %s\n' \
  671b49ffc77a97f82f1e0fb344330c6104b110c2f285e23f2b30403f3bc14863 \
  "${qtengine_dir}/source.tar.gz" | sha256sum --check --strict
tar --extract --gzip --file "${qtengine_dir}/source.tar.gz" \
  --directory "$qtengine_dir" --strip-components=1
cmake -S "$qtengine_dir" -B "${qtengine_dir}/build" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/usr \
  -DCMAKE_INSTALL_LIBDIR=lib64 \
  -DQT5_PLUGINDIR="$(qmake-qt5 -query QT_INSTALL_PLUGINS)" \
  -DQT6_PLUGINDIR="$(qmake6 -query QT_INSTALL_PLUGINS)" \
  -DBUILD_QT5=ON -DBUILD_QT6=ON
cmake --build "${qtengine_dir}/build" --parallel "$(nproc)"
cmake --install "${qtengine_dir}/build"
ldconfig
rm -rf "$qtengine_dir"
rpm -q qt5ct qt6ct

# Keep the native Firefox theme helper and its interpreter in the immutable
# image, isolated from Fedora's Python packages and available to every user.
python3 -m venv /usr/lib/pywalfox
/usr/lib/pywalfox/bin/pip install --no-cache-dir pywalfox==2.9.0
ln -s /usr/lib/pywalfox/bin/pywalfox /usr/bin/pywalfox
pywalfox --version
pywalfox install --global --executable /usr/bin/pywalfox \
  --manifest-path /usr/lib64/mozilla/native-messaging-hosts

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
dnf5 -y install niri
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
