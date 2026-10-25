#!/usr/bin/env python3
"""Check installer media and boot its runtime to Anaconda's text summary.

Uses the ISO's kernel/initrd with the unchanged ISO attached as a CD-ROM.
This does not test firmware/GRUB boot, installation, or the installed desktop.
"""

import argparse
import json
from pathlib import Path
import re
import subprocess
import tempfile
import time


def verify(iso, output, desktop):
    output.mkdir(parents=True, exist_ok=True)
    with (output / "iso-layout.log").open("w") as log:
        subprocess.run(
            ["xorriso", "-indev", str(iso), "-pvd_info", "-report_el_torito", "plain"],
            stdout=log, stderr=subprocess.STDOUT, check=True,
        )
    layout = (output / "iso-layout.log").read_text()
    for firmware in ("BIOS", "UEFI"):
        if not re.search(r"El Torito boot img\s*:.*\b" + firmware + r"\b", layout):
            raise RuntimeError(f"Missing {firmware} boot catalog entry")
    label = "Container-Installer-x86_64"
    if label not in layout:
        raise RuntimeError("Unexpected installer volume label")

    with tempfile.TemporaryDirectory(prefix="iso-smoke-") as temp:
        kernel = Path(temp) / "pxeboot"
        with (output / "extraction.log").open("w") as log:
            subprocess.run(
                ["xorriso", "-osirrox", "on", "-indev", str(iso),
                 "-extract", "/images/pxeboot", str(kernel),
                 "-extract", "/osbuild.ks", str(output / "osbuild.ks"),
                 "-extract", "/osbuild-base.ks", str(output / "osbuild-base.ks")],
                stdout=log, stderr=subprocess.STDOUT, check=True,
            )
        kickstart = "\n".join(p.read_text() for p in output.glob("*.ks"))
        expected_target = (
            "bootc switch --mutate-in-place --transport registry "
            f"ghcr.io/justinschwerdtfeger/justin-bazzite-dx-{desktop}:latest"
        )
        if expected_target not in kickstart:
            raise RuntimeError("Installer update target does not match the desktop")
        if "/run/install/repo/container" not in kickstart:
            raise RuntimeError("Missing embedded container installation source")

        serial = output / "serial.log"
        args = [
            "qemu-system-x86_64", "-machine", "q35",
            "-accel", "kvm", "-accel", "tcg,thread=multi",
            "-cpu", "max", "-smp", "2", "-m", "4096",
            "-cdrom", str(iso),
            "-kernel", str(kernel / "vmlinuz"),
            "-initrd", str(kernel / "initrd.img"),
            "-append", (
                f"inst.stage2=hd:LABEL={label} "
                f"inst.ks=hd:LABEL={label}:/osbuild.ks "
                "inst.text inst.notmux inst.lang=en_US.UTF-8 inst.geoloc=0 "
                "console=tty0 console=ttyS0,115200n8"
            ),
            "-display", "none", "-serial", f"file:{serial}",
            "-monitor", "none", "-device", "virtio-serial-pci",
            "-chardev", f"file,id=anacondalog,path={output / 'anaconda.log'}",
            "-device", "virtserialport,chardev=anacondalog,"
            "name=org.fedoraproject.anaconda.log.0",
            "-nic", "none", "-no-reboot",
        ]
        (output / "command.json").write_text(json.dumps(args, indent=2) + "\n")
        with (output / "qemu.log").open("wb") as log:
            vm = subprocess.Popen(args, stdin=subprocess.DEVNULL, stdout=log, stderr=log)
            try:
                wait_for_installer(vm, serial, output)
            finally:
                vm.terminate()
                try:
                    vm.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    vm.kill()
                    vm.wait()


def wait_for_installer(vm, serial, output):
    deadline = time.monotonic() + 1800
    ready_since = None
    while time.monotonic() < deadline:
        if vm.poll() is not None:
            raise RuntimeError(f"QEMU exited early: {vm.returncode}")
        text = serial.read_text(errors="replace") if serial.exists() else ""
        text = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", text)
        (output / "serial-clean.log").write_text(text)
        for marker in (
            "Kernel panic - not syncing",
            "Traceback (most recent call last)",
            "Entering emergency mode",
        ):
            if marker in text:
                raise RuntimeError(f"Fatal boot or installer error: {marker}")
        if all(marker in text for marker in (
            "Installation Destination", "to begin installation",
        )):
            if ready_since is None:
                ready_since = time.monotonic()
            if time.monotonic() - ready_since >= 15:
                return
        time.sleep(2)
    raise RuntimeError("Timed out waiting for the installer summary")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("iso", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("desktop", choices=("gnome", "kde"))
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    passed = False
    try:
        verify(args.iso.resolve(strict=True), output, args.desktop)
        passed = True
        detail = "Installer summary reached and QEMU remained alive for 15 seconds"
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        detail = str(error)
    result = {
        "passed": passed, "desktop": args.desktop, "detail": detail,
        "elapsed_seconds": round(time.monotonic() - started),
        "scope": "ISO layout, embedded update target, and installer runtime startup",
    }
    (output / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result), flush=True)
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
