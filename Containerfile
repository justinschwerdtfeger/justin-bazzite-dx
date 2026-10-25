# Keep script contexts separate so shell/initramfs edits don't invalidate packages.
# Bind mounts keep the scripts out of the final image.
FROM scratch AS packages_ctx
COPY build_files/build.sh /

FROM scratch AS initramfs_ctx
COPY build_files/build-initramfs.sh /

FROM scratch AS shell_ctx
COPY build_files/install-dux-shell.sh /

# Base Image
FROM ghcr.io/ublue-os/bazzite-dx-gnome:stable-44

## Other possible base images include:
# FROM ghcr.io/ublue-os/bazzite:latest
# FROM ghcr.io/ublue-os/bluefin-nvidia:stable
# 
# ... and so on, here are more base images
# Universal Blue Images: https://github.com/orgs/ublue-os/packages
# Fedora base image: quay.io/fedora/fedora-bootc:41
# CentOS base images: quay.io/centos-bootc/centos-bootc:stream10

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
RUN --mount=type=bind,from=packages_ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    test -n "$PACKAGE_REFRESH" && test -n "$PACKAGE_SCRIPT_SHA" && \
    /ctx/build.sh

# Artwork changes can reuse package installation. Copy before dracut so the
# custom Plymouth artwork is included in the generated initramfs.
COPY system_files /

ARG INITRAMFS_SCRIPT_SHA=local
RUN --mount=type=bind,from=initramfs_ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
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
