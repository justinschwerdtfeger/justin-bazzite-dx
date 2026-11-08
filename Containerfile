ARG DESKTOP=gnome
ARG GPU=default

# Upstream names KDE's image bazzite-dx; retain GNOME as the default.
FROM ghcr.io/ublue-os/bazzite-dx-gnome:stable-45 AS base-gnome-default
FROM ghcr.io/ublue-os/bazzite-dx:stable-45 AS base-kde-default
# Upstream's DX NVIDIA images use the open kernel modules.
FROM ghcr.io/ublue-os/bazzite-dx-nvidia-gnome:stable-45 AS base-gnome-nvidia-open
FROM ghcr.io/ublue-os/bazzite-dx-nvidia:stable-45 AS base-kde-nvidia-open

# The QtEngine Copr only publishes Fedora 44 binaries. Build the same release
# against Fedora 45's Qt libraries, keeping compilers and headers out of the OS.
FROM registry.fedoraproject.org/fedora:45 AS qtengine_builder
COPY build_files/qtengine/ /tmp/qtengine/
ARG PACKAGE_REFRESH=local
RUN test -n "$PACKAGE_REFRESH" && \
    dnf5 -y --setopt=install_weak_deps=False install rpm-build dnf5-plugins curl && \
    dnf5 -y --setopt=install_weak_deps=False builddep /tmp/qtengine/qtengine.spec && \
    mkdir -p /tmp/qtengine/rpmbuild/SOURCES && \
    curl --fail --location --retry 3 \
      https://github.com/kossLAN/qtengine/archive/167e7d9a27cdc8005ef2bd4d5d317b9da01b853f.tar.gz \
      -o /tmp/qtengine/rpmbuild/SOURCES/qtengine-0.2.2.tar.gz && \
    rpmbuild -bb --define '_topdir /tmp/qtengine/rpmbuild' /tmp/qtengine/qtengine.spec && \
    mkdir /rpms && cp /tmp/qtengine/rpmbuild/RPMS/*/qtengine-0.2.2-*.rpm /rpms/

# Keep script contexts separate so shell/initramfs edits don't invalidate packages.
# Bind mounts keep the scripts out of the final image.
FROM scratch AS packages_ctx
COPY build_files/build.sh /
COPY build_files/packages /packages

FROM scratch AS initramfs_ctx
COPY build_files/build-initramfs.sh /

FROM scratch AS shell_ctx
COPY build_files/install-dux-shell.sh /

# Select the desktop and GPU base; every customization below is shared.
FROM base-${DESKTOP}-${GPU} AS final
ARG DESKTOP
ARG GPU
LABEL io.github.justinschwerdtfeger.desktop="${DESKTOP}"
LABEL io.github.justinschwerdtfeger.gpu="${GPU}"

### [IM]MUTABLE /opt
## Some bootable images, like Fedora, have /opt symlinked to /var/opt, in order to
## make it mutable/writable for users. However, some packages write files to this directory,
## thus its contents might be wiped out when bootc deploys an image, making it troublesome for
## some packages. Eg, google-chrome, docker-desktop.
##
## Uncomment the following line if one desires to make /opt immutable and be able to be used
## by the package manager.

RUN rm /opt && mkdir /opt

### MODIFICATIONS
## make modifications desired in your image and install packages by modifying the build.sh script
## the following RUN directive does all the things required to run "build.sh" as recommended.

# CI changes this daily so cached package installs still receive repository updates.
ARG PACKAGE_REFRESH=local
ARG PACKAGE_SCRIPT_SHA=local
# DNF deletes cached RPMs after installing them; concurrent builds must wait.
RUN --mount=type=bind,from=packages_ctx,source=/,target=/ctx \
    --mount=type=bind,from=qtengine_builder,source=/rpms,target=/qtengine-rpms \
    --mount=type=cache,dst=/var/cache,sharing=locked \
    --mount=type=cache,dst=/var/log,sharing=locked \
    --mount=type=tmpfs,dst=/tmp \
    test -n "$PACKAGE_REFRESH" && test -n "$PACKAGE_SCRIPT_SHA" && \
    /ctx/build.sh

# Artwork changes can reuse package installation. Copy before dracut so the
# custom Plymouth artwork is included in the generated initramfs.
COPY system_files /

ARG INITRAMFS_SCRIPT_SHA=local
RUN --mount=type=bind,from=initramfs_ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache,sharing=locked \
    --mount=type=cache,dst=/var/log,sharing=locked \
    --mount=type=tmpfs,dst=/tmp \
    test -n "$INITRAMFS_SCRIPT_SHA" && /ctx/build-initramfs.sh

# Refresh the prebuilt shell after dracut so it doesn't invalidate the initramfs.
# CI and `just build` supply a fresh value for this layer's cache key.
# Lint in the same RUN to avoid another filesystem scan/commit of the OS image.
ARG DUX_SHELL_REFRESH=local
RUN --mount=type=bind,from=shell_ctx,source=/,target=/ctx \
    --mount=type=tmpfs,dst=/tmp \
    test -n "$DUX_SHELL_REFRESH" && bash /ctx/install-dux-shell.sh && \
    bootc container lint
