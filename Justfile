# DESKTOP selects defaults; the third positional argument can override it.
export desktop := env("DESKTOP", "gnome")
export image_name := env("IMAGE_NAME", "justin-bazzite-dx" + if desktop == "kde" { "-kde" } else { "" })
export default_tag := env("DEFAULT_TAG", "latest")
export bib_image := env("BIB_IMAGE", "quay.io/centos-bootc/bootc-image-builder:latest")

alias build-vm := build-qcow2
alias rebuild-vm := rebuild-qcow2
alias run-vm := run-vm-qcow2

[private]
default:
    @just --list

# Check Just Syntax
[group('Just')]
check:
    #!/usr/bin/bash
    set -euo pipefail
    find . -type f -name "*.just" | while read -r file; do
    	echo "Checking syntax: $file"
    	just --unstable --fmt --check -f $file
    done
    echo "Checking syntax: Justfile"
    just --unstable --fmt --check -f Justfile

# Fix Just Syntax
[group('Just')]
fix:
    #!/usr/bin/bash
    set -euo pipefail
    find . -type f -name "*.just" | while read -r file; do
    	echo "Checking syntax: $file"
    	just --unstable --fmt -f $file
    done
    echo "Checking syntax: Justfile"
    just --unstable --fmt -f Justfile || { exit 1; }

# Clean Repo
[group('Utility')]
clean:
    #!/usr/bin/bash
    set -eoux pipefail
    touch _build
    find *_build* -exec rm -rf {} \;
    rm -f previous.manifest.json
    rm -f changelog.md
    rm -f output.env
    rm -rf output/

# Sudo Clean Repo
[group('Utility')]
[private]
sudo-clean:
    just sudoif just clean

# sudoif bash function
[group('Utility')]
[private]
sudoif command *args:
    #!/usr/bin/bash
    function sudoif(){
        if [[ "${UID}" -eq 0 ]]; then
            "$@"
        elif [[ "$(command -v sudo)" && -n "${SSH_ASKPASS:-}" ]] && [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
            /usr/bin/sudo --askpass "$@" || exit 1
        elif [[ "$(command -v sudo)" ]]; then
            /usr/bin/sudo "$@" || exit 1
        else
            exit 1
        fi
    }
    sudoif {{ command }} {{ args }}

# Build an image; existing target_image/tag positions are unchanged.
# Examples: just build; DESKTOP=kde just build; just build my-kde latest kde
build $target_image=image_name $tag=default_tag $variant=desktop:
    #!/usr/bin/env bash
    set -euo pipefail
    case "$variant" in
        gnome|kde) ;;
        *) echo "Unsupported desktop: $variant (expected gnome or kde)" >&2; exit 1 ;;
    esac
    [[ $(uname -m) == x86_64 ]] || { echo "Dux Shell requires x86_64." >&2; exit 1; }

    BUILD_ARGS=()
    if [[ -z "$(git status -s)" ]]; then
        BUILD_ARGS+=("--build-arg" "SHA_HEAD_SHORT=$(git rev-parse --short HEAD)")
    fi
    # Buildah/Podman bind contexts need an explicit content hash in the cache key.
    PACKAGE_SCRIPT_SHA=$(sha256sum build_files/build.sh build_files/packages/*.sh | sha256sum | cut -d ' ' -f 1)
    INITRAMFS_SCRIPT_SHA=$(sha256sum build_files/build-initramfs.sh | cut -d ' ' -f 1)

    podman build \
        "${BUILD_ARGS[@]}" \
        --platform linux/amd64 \
        --pull=newer \
        --build-arg "DESKTOP=$variant" \
        --build-arg "PACKAGE_REFRESH=$(date -u +%Y%m%d)" \
        --build-arg "DUX_SHELL_REFRESH=$(date -u +%s%N)" \
        --build-arg "PACKAGE_SCRIPT_SHA=$PACKAGE_SCRIPT_SHA" \
        --build-arg "INITRAMFS_SCRIPT_SHA=$INITRAMFS_SCRIPT_SHA" \
        --tag "${target_image}:${tag}" \
        .

# BIB runs rootful and must see the local image. A stream avoids SSH/scp setup.
_rootful_load_image $target_image=image_name $tag=default_tag:
    #!/usr/bin/env bash
    set -euo pipefail
    if podman image exists "${target_image}:${tag}"; then
        user_id=$(podman image inspect --format '{{ '{{.Id}}' }}' "${target_image}:${tag}")
        root_id=$(just sudoif podman image inspect --format '{{ '{{.Id}}' }}' "${target_image}:${tag}" 2>/dev/null || true)
        if [[ "$root_id" != "$user_id" ]]; then
            podman save "${target_image}:${tag}" | just sudoif podman load
        fi
    else
        just sudoif podman pull "${target_image}:${tag}"
    fi

# Convert a local image using the template's privileged Bootc Image Builder flow.
_build-bib $target_image $tag $type $config $variant=desktop: (_rootful_load_image target_image tag)
    #!/usr/bin/env bash
    set -euo pipefail
    case "$variant" in
        gnome|kde) ;;
        *) echo "Unsupported desktop: $variant (expected gnome or kde)" >&2; exit 1 ;;
    esac
    [[ $(uname -m) == x86_64 ]] || { echo "Dux Shell requires x86_64." >&2; exit 1; }
    BUILDTMP=$(mktemp -p "${PWD}" -d -t _build-bib.XXXXXXXXXX)
    trap 'just sudoif rm -rf -- "$BUILDTMP"' EXIT
    mkdir -p "$BUILDTMP/output"
    config_path=$(realpath -e "$config")

    just sudoif podman run \
        --rm --privileged --pull=newer --net=host \
        --security-opt label=type:unconfined_t \
        -v "$config_path:/config.toml:ro" \
        -v "$BUILDTMP/output:/output" \
        -v /var/lib/containers/storage:/var/lib/containers/storage \
        "$bib_image" build "${target_image}:${tag}" \
        --type "$type" --config /config.toml --output /output --use-librepo --rootfs=btrfs \
        --chown "${SUDO_UID:-$(id -u)}:${SUDO_GID:-$(id -g)}"

    output_dir="output/$variant/${target_image//\//_}/$tag"
    mkdir -p "$output_dir"
    just sudoif cp -a "$BUILDTMP/output/." "$output_dir/"
    just sudoif chown -R "${SUDO_UID:-$(id -u)}:${SUDO_GID:-$(id -g)}" "$output_dir"
    echo "Artifacts: $output_dir"

_rebuild-bib $target_image $tag $type $config $variant=desktop: (build target_image tag variant) && (_build-bib target_image tag type config variant)

# Existing image/tag positional arguments remain first; desktop is third.
[group('Build Virtual Machine Image')]
build-qcow2 $target_image=("localhost/" + image_name) $tag=default_tag $variant=desktop: && (_build-bib target_image tag "qcow2" "disk_config/disk.toml" variant)

[group('Build Virtual Machine Image')]
build-raw $target_image=("localhost/" + image_name) $tag=default_tag $variant=desktop: && (_build-bib target_image tag "raw" "disk_config/disk.toml" variant)

[group('Build Virtual Machine Image')]
build-iso $target_image=("localhost/" + image_name) $tag=default_tag $variant=desktop: && (_build-bib target_image tag "anaconda-iso" ("disk_config/iso-" + variant + ".toml") variant)

[group('Build Virtual Machine Image')]
rebuild-qcow2 $target_image=("localhost/" + image_name) $tag=default_tag $variant=desktop: && (_rebuild-bib target_image tag "qcow2" "disk_config/disk.toml" variant)

[group('Build Virtual Machine Image')]
rebuild-raw $target_image=("localhost/" + image_name) $tag=default_tag $variant=desktop: && (_rebuild-bib target_image tag "raw" "disk_config/disk.toml" variant)

[group('Build Virtual Machine Image')]
rebuild-iso $target_image=("localhost/" + image_name) $tag=default_tag $variant=desktop: && (_rebuild-bib target_image tag "anaconda-iso" ("disk_config/iso-" + variant + ".toml") variant)

# Run a virtual machine with the specified image type and configuration
_run-vm $target_image $tag $type $config $variant=desktop:
    #!/usr/bin/bash
    set -eoux pipefail

    # Determine the image file based on the type
    output_dir="output/$variant/${target_image//\//_}/$tag"
    image_file="$output_dir/${type}/disk.${type}"
    if [[ $type == iso ]]; then
        image_file="$output_dir/bootiso/install.iso"
    fi

    # Build the image if it does not exist
    if [[ ! -f "${image_file}" ]]; then
        just "build-${type}" "$target_image" "$tag" "$variant"
    fi

    # Determine an available port to use
    port=8006
    while grep -q :${port} <<< $(ss -tunalp); do
        port=$(( port + 1 ))
    done
    echo "Using Port: ${port}"
    echo "Connect to http://localhost:${port}"

    # Set up the arguments for running the VM
    run_args=()
    run_args+=(--rm --privileged)
    run_args+=(--pull=newer)
    run_args+=(--publish "127.0.0.1:${port}:8006")
    run_args+=(--env "CPU_CORES=4")
    run_args+=(--env "RAM_SIZE=8G")
    run_args+=(--env "DISK_SIZE=64G")
    run_args+=(--env "TPM=Y")
    run_args+=(--env "GPU=Y")
    run_args+=(--device=/dev/kvm)
    run_args+=(--volume "${PWD}/${image_file}":"/boot.${type}")
    run_args+=(docker.io/qemux/qemu)

    # Run the VM and open the browser to connect
    (sleep 30 && xdg-open http://localhost:"$port") &
    podman run "${run_args[@]}"

# Run a virtual machine from a QCOW2 image
[group('Run Virtal Machine')]
run-vm-qcow2 $target_image=("localhost/" + image_name) $tag=default_tag $variant=desktop: && (_run-vm target_image tag "qcow2" "disk_config/disk.toml" variant)

# Run a virtual machine from a RAW image
[group('Run Virtal Machine')]
run-vm-raw $target_image=("localhost/" + image_name) $tag=default_tag $variant=desktop: && (_run-vm target_image tag "raw" "disk_config/disk.toml" variant)

# Run a virtual machine from an ISO
[group('Run Virtal Machine')]
run-vm-iso $target_image=("localhost/" + image_name) $tag=default_tag $variant=desktop: && (_run-vm target_image tag "iso" ("disk_config/iso-" + variant + ".toml") variant)

# Run a virtual machine using systemd-vmspawn
[group('Run Virtal Machine')]
spawn-vm rebuild="0" type="qcow2" ram="6G" $target_image=("localhost/" + image_name) $tag=default_tag $variant=desktop:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ type }}" in
        qcow2|raw) ;;
        *) echo "spawn-vm supports qcow2 or raw." >&2; exit 1 ;;
    esac
    if [[ "{{ rebuild }}" == 1 ]]; then
        just "rebuild-{{ type }}" "$target_image" "$tag" "$variant"
    fi
    image_file="output/$variant/${target_image//\//_}/$tag/{{ type }}/disk.{{ type }}"
    [[ -f "$image_file" ]] || just "build-{{ type }}" "$target_image" "$tag" "$variant"
    systemd-vmspawn \
        -M "bootc-image-$variant" \
        --console=gui --cpus=2 \
        --ram="$(numfmt --from=iec '{{ ram }}')" \
        --network-user-mode --vsock=false --pass-ssh-key=false \
        -i "$image_file"

# Runs shell check on all Bash scripts
lint:
    #!/usr/bin/env bash
    set -eoux pipefail
    # Check if shellcheck is installed
    if ! command -v shellcheck &> /dev/null; then
        echo "shellcheck could not be found. Please install it."
        exit 1
    fi
    # Run shellcheck on all Bash scripts
    /usr/bin/find . \( -iname "*.sh" -o -path "./system_files/usr/libexec/*" \) -type f -exec shellcheck "{}" +

# Runs shfmt on all Bash scripts
format:
    #!/usr/bin/env bash
    set -eoux pipefail
    # Check if shfmt is installed
    if ! command -v shfmt &> /dev/null; then
        echo "shellcheck could not be found. Please install it."
        exit 1
    fi
    # Run shfmt on all Bash scripts
    /usr/bin/find . -iname "*.sh" -type f -exec shfmt --write "{}" ';'
