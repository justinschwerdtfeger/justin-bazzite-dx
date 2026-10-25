# Justin's Bazzite DX + niri

Two x86_64 desktop variants share the same packages, artwork, niri integration,
and prebuilt Dux Shell:

- **GNOME + niri** (default): `ghcr.io/justinschwerdtfeger/justin-bazzite-dx:latest`,
  based on `ghcr.io/ublue-os/bazzite-dx-gnome:stable-44`.
- **KDE Plasma + niri**: `ghcr.io/justinschwerdtfeger/justin-bazzite-dx-kde:latest`,
  based on `ghcr.io/ublue-os/bazzite-dx:stable-44`.

The [upstream Bazzite DX project](https://github.com/ublue-os/bazzite-dx)
uses the unsuffixed image name for KDE. This repository keeps its existing
unsuffixed **GNOME** image name for compatibility. Only x86_64/amd64 is supported;
the Dux prebuilt release and Google Chrome repository require it.

## Switch back to the published image

After testing a local development image, use the registry image matching your
installed desktop:

```bash
# GNOME
sudo bootc switch --transport registry ghcr.io/justinschwerdtfeger/justin-bazzite-dx:latest
# KDE
sudo bootc switch --transport registry ghcr.io/justinschwerdtfeger/justin-bazzite-dx-kde:latest
```

Reboot when ready, then check `sudo bootc status`. Future updates follow that
registry image; `sudo bootc upgrade` stages an update manually. Upstream advises
using the variant matching your installed desktop rather than rebasing between
GNOME and KDE; use the corresponding installer for a new desktop installation.

## Niri with Dux Shell

Select **Niri** at the login screen after installing either variant or rebasing
and rebooting. The native desktop session is also available. First login
initializes `~/.config/niri` (or `$XDG_CONFIG_HOME/niri`) with Dux Shell defaults.
Existing Niri paths and `NIRI_CONFIG` overrides are preserved; image updates
leave user settings alone. To switch an existing setup, run `dms setup`, which
backs up its configuration.

Each image build uses the installed Niri package's defaults with Dux Shell
integration. Navigation shortcuts and application window rules follow upstream.
**Super+Space** opens the launcher, **Super+Return** opens Foot,
**Super+Ctrl+Comma** opens settings, **Super+Ctrl+V** opens the clipboard,
**Super+E** opens Nautilus, and **Super+Alt+L** locks the screen.

Nautilus, GNOME Keyring, and the GTK/GNOME portals are shared intentionally for
niri's file manager, secrets, and screen sharing. KDE also retains Dolphin and
its native portal. Desktop-specific package additions and removals belong in
[`build_files/packages/gnome.sh`](build_files/packages/gnome.sh) or
[`build_files/packages/kde.sh`](build_files/packages/kde.sh). Most packages remain
in [`build_files/build.sh`](build_files/build.sh). Both variants use the same
[`system_files`](system_files) and Dux Shell installer.

## Build locally

Required: `just`, Podman, standard GNU shell utilities, and Python 3.11+ for ISO
configuration generation. Disk builds additionally require privileged rootful
Podman and sudo access (or a root shell). Container builds can use rootless
Podman. The recipes do not install host tools. Run `just lint` with ShellCheck
installed, and `just check` to check Justfile formatting.

```bash
# Default GNOME image: localhost/justin-bazzite-dx:latest
just build
# KDE image: localhost/justin-bazzite-dx-kde:latest
DESKTOP=kde just build

# Existing image/tag positional arguments still work; desktop is optional third.
just build localhost/my-gnome dev
just build localhost/my-kde dev kde
```

Set `DESKTOP=gnome|kde` to choose default names for all recipes. `IMAGE_NAME`
overrides the default local image name; `DEFAULT_TAG` defaults to `latest`.
An explicit third desktop argument selects the base but leaves your explicit
image name unchanged. Use `just build` so package and initramfs content hashes
are supplied for the bind-mounted build scripts.

### Disk images and VMs

```bash
# Convert the existing local container image.
just build-iso
DESKTOP=kde just build-iso
DESKTOP=kde just build-qcow2

# Build the container first, then convert it.
DESKTOP=kde just rebuild-iso
just rebuild-qcow2 localhost/my-gnome dev gnome

# qcow2, raw, and iso commands accept the same image/tag/desktop arguments.
DESKTOP=kde just run-vm-qcow2
DESKTOP=kde just run-vm-iso
```

`build-vm`, `rebuild-vm`, and `run-vm` remain aliases for their QCOW2 recipes.
Artifacts are separated by desktop, image name (slashes replaced with `_`), and
tag. For example:

```text
output/gnome/localhost_justin-bazzite-dx/latest/bootiso/install.iso
output/kde/localhost_justin-bazzite-dx-kde/latest/qcow2/disk.qcow2
```

`spawn-vm` uses systemd-vmspawn and preserves its first three arguments:
`just spawn-vm 0 qcow2 6G [image] [tag] [desktop]`. The other VM recipes use
QEMU in Podman and require `/dev/kvm`.

Both local disk builds and disk CI use the official builder digest in
[`disk_config/builder-image`](disk_config/builder-image), with the explicit
`build IMAGE --type TYPE --config /config.toml --output /output` CLI. Local builds
can override it with `BIB_IMAGE`, using a version compatible with that CLI.
`just build-iso` requests **anaconda-iso**; `iso` remains the friendly recipe name.
The local rootless image is streamed into rootful Podman when needed, without
requiring localhost SSH or Podman scp configuration. A host without working
privileged Podman/sudo can build containers, but cannot run these disk recipes.

Restricted LXC containers may deny the builder's required `devtmpfs` mount even
with `--privileged`. This development LXC does so; both container variants build,
but local ISO generation needs a VM/native host or LXC configuration that permits
that mount. Installing another host package does not resolve this restriction.

### Installer update target

[`disk_config/iso.toml`](disk_config/iso.toml) is a shared template. Both local
recipes and CI render its `@IMAGE_REF@` placeholder using
[`build_files/render-iso-config.py`](build_files/render-iso-config.py), so the
installed system follows the intended registry image. The former desktop ISO
files containing fixed registry names have been replaced by this one template.
The installer enables the normal storage, networking, users, and desktop setup
modules for both variants.

For local builds, `localhost/name:tag` (or an unqualified name) defaults to
`IMAGE_REGISTRY/name:tag`, where `IMAGE_REGISTRY` defaults to
`ghcr.io/justinschwerdtfeger`. A fully qualified registry image keeps its reference.
Set `INSTALL_IMAGE` to override the installed system's update source independently
of the local build tag, including when that local tag is unpublished:

```bash
INSTALL_IMAGE=ghcr.io/justinschwerdtfeger/justin-bazzite-dx-kde:latest \
  just build-iso localhost/my-kde dev kde
```

Use a registry image that exists and matches the desktop being installed.
CI derives the target directly from its selected published image and tag.

## CI and build caching

[`build.yml`](.github/workflows/build.yml) builds both desktop variants on amd64.
GNOME preserves the existing registry package; KDE publishes to `<repo>-kde`.
Metadata links still point to the source repository. Each image has a separate
`<image>-build-cache` GHCR package; existing GNOME cache names are preserved.
The cache packages must grant this repository's Actions token read/write access.

Only default-branch publishing builds write caches. Same-repository pull requests
can read them; fork pull requests build without reading them. The workflow
checks for newer base images. A daily key refreshes package installation, and a
combined hash of `build_files/build.sh` and **all** desktop package files
invalidates that layer when package settings change. Local Just builds calculate
the same hash. Changes to the shell installer or initramfs script use separate
contexts so they can reuse package installation. Artwork is copied before
dracut runs. Choose **fresh-build** in the container workflow to ignore caches.

Package installs are grouped by repository availability. Each Copr is enabled
only for its own packages, and Terra is disabled for the remaining development
tools. The prebuilt Dux Shell is refreshed after initramfs generation on every
build. The final shell install and `bootc container lint` share a layer. Each
published image digest is signed once for all its tags.

[`build-disk.yml`](.github/workflows/build-disk.yml) builds QCOW2 and Anaconda ISO
artifacts for both published desktops on amd64. Artifact names and S3 prefixes
include the desktop image name, tag, architecture, and disk type. Disk pull-request
checks use the **already published** `latest` containers, not the pull request's
container changes. Publish both containers before building disks for a new repo.

To enable publishing in a fork, generate a Cosign key pair, keep `cosign.pub` in
the repository, and store the unencrypted private key as the `SIGNING_SECRET`
Actions secret. Never commit `cosign.key`. Workflow image names default to your
repository name; adjust local `IMAGE_NAME`/`IMAGE_REGISTRY` for your fork.

Optional S3 uploads use `S3_PROVIDER`, `S3_BUCKET_NAME`, `S3_ACCESS_KEY_ID`,
`S3_SECRET_ACCESS_KEY`, `S3_REGION`, and `S3_ENDPOINT` Actions secrets. Without
S3, disk images are available as Actions artifacts.

## DMS application theming

Both images include `qt5ct`, `qt6ct`, and the Qt5/Qt6 plugins for
[qtengine](https://github.com/kossLAN/qtengine), installed from the
[desertedman/qtengine Copr](https://copr.fedorainfracloud.org/coprs/desertedman/qtengine/).
To use qtengine in your DMS session, set `QT_QPA_PLATFORMTHEME=qtengine` in
`~/.config/environment.d/90-dms.conf`, then log out and back in. Enable **Apply Qt
Themes** in DMS's **Theme & Colors** settings. You can instead select `qt5ct` or
`qt6ct` in your session configuration. See the
[DMS application theming guide](https://duxlabs.dev/docs/dankmaterialshell/application-themes/).
