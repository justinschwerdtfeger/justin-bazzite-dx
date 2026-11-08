"""Exercise the boot helper without root, a running systemd, or network access."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import tomllib
import unittest


REPO = Path(__file__).resolve().parents[1]
PENDING = "/etc/justin-flatpak-setup-pending"
IMAGE_INFO = "/usr/share/ublue-os/image-info.json"
UNITS = REPO / "system_files/usr/lib/systemd/system"
LISTS = {
    "gnome": ["app/org.gnome.Calculator/x86_64/stable"],
    "kde": ["app/org.kde.kcalc/x86_64/stable"],
}
RUNTIME = "runtime/org.freedesktop.Platform.VulkanLayer.MangoHud/x86_64/25.08"

MOCK = r'''#!/usr/bin/python3
import json, os, pathlib, sys
root = pathlib.Path(os.environ["FIXTURE_ROOT"])
config = json.loads((root / "config.json").read_text())
name, args = pathlib.Path(sys.argv[0]).name, sys.argv[1:]
with (root / "calls.jsonl").open("a") as log:
    log.write(json.dumps([name, *args]) + "\n")
if name == "curl":
    assert "--fail" in args, args
    mode = config.get("download", "ok")
    if mode in ("offline", "http-error"):
        sys.exit(7 if mode == "offline" else 22)
    desktop = "gnome" if "/gnome_flatpaks/" in args[-1] else "kde"
    refs = config[desktop]
    if mode == "empty":
        refs = []
    elif mode == "invalid":
        refs = ["<html>temporary error</html>"]
    elif mode == "partial-transfer":
        print(refs[0])
        sys.exit(18)
    print("\n".join(refs), end="\n" if refs else "")
elif name == "flatpak":
    installed_file = root / "installed.json"
    installed = json.loads(installed_file.read_text()) if installed_file.exists() else []
    assert args[:6] == ["--system", "--noninteractive", "-y", "install", "--or-update", "flathub"], args
    refs = args[6:]
    if config.get("install_fail"):
        refs = refs[:1]
    installed_file.write_text(json.dumps(sorted(set(installed + refs))))
    sys.exit(1 if config.get("install_fail") else 0)
else:
    raise AssertionError(name)
'''


class FlatpakSetupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.pending = self.root / "pending"
        self.pending.touch()
        self.config = {key: refs + [RUNTIME] for key, refs in LISTS.items()}
        self.set_base("silverblue")
        source = (REPO / "system_files/usr/libexec/justin-flatpak-setup").read_text()
        self.helper = self.root / "setup"
        self.helper.write_text(source.replace(PENDING, str(self.pending)).replace(
            IMAGE_INFO, str(self.root / "image-info.json")))
        self.helper.chmod(0o755)
        mock = self.root / "mock"
        mock.write_text(MOCK)
        mock.chmod(0o755)
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        for name in ("curl", "flatpak"):
            (bin_dir / name).symlink_to(mock)
        self.env = dict(os.environ, FIXTURE_ROOT=str(self.root),
                        PATH=f"{bin_dir}:{os.environ['PATH']}")

    def set_base(self, base):
        (self.root / "image-info.json").write_text(json.dumps({"base-image-name": base}))

    def calls(self):
        log = self.root / "calls.jsonl"
        return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []

    def run_setup(self, success=True):
        (self.root / "config.json").write_text(json.dumps(self.config))
        result = subprocess.run([str(self.helper)], env=self.env, text=True,
                                capture_output=True, timeout=10)
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        self.assertEqual(self.pending.exists(), not success)

    def test_unenrolled_host_does_nothing(self):
        self.pending.unlink()
        self.run_setup()
        self.assertEqual(self.calls(), [])

    def test_each_desktop_installs_only_its_defaults_and_stays_complete(self):
        for base, desktop in (("silverblue", "gnome"), ("kinoite", "kde")):
            with self.subTest(desktop=desktop):
                self.pending.touch()
                (self.root / "installed.json").write_text("[]")
                self.set_base(base)
                before = len(self.calls())
                self.run_setup()
                installed = json.loads((self.root / "installed.json").read_text())
                self.assertEqual(set(installed), set(self.config[desktop]))
                calls = self.calls()
                download, install = calls[before:]
                self.assertEqual(download[0], "curl")
                self.assertTrue(download[-1].endswith(f"/{desktop}_flatpaks/flatpaks"))
                self.assertEqual(install[7:], self.config[desktop])
                # Simulate uninstalling defaults and rebooting/updating the OS.
                (self.root / "installed.json").write_text("[]")
                self.run_setup()
                self.assertEqual(self.calls(), calls)

    def test_download_failures_remain_retryable(self):
        for mode in ("offline", "http-error", "empty", "invalid", "partial-transfer"):
            with self.subTest(mode=mode):
                self.pending.touch()
                self.config["download"] = mode
                before = len(self.calls())
                self.run_setup(success=False)
                self.assertEqual([call[0] for call in self.calls()[before:]], ["curl"])
                self.config["download"] = "ok"
                self.run_setup()

    def test_partial_install_is_preserved_and_retried(self):
        self.config["install_fail"] = True
        self.run_setup(success=False)
        installed = self.root / "installed.json"
        self.assertEqual(json.loads(installed.read_text()), self.config["gnome"][:1])
        self.config["install_fail"] = False
        self.run_setup()
        self.assertEqual(set(json.loads(installed.read_text())), set(self.config["gnome"]))

    def test_bad_image_metadata_cannot_select_the_other_desktop(self):
        for base in (None, "unknown"):
            with self.subTest(base=base):
                self.set_base(base)
                self.run_setup(success=False)
                self.assertEqual(self.calls(), [])

    def test_iso_and_disk_enrollment_and_systemd_units(self):
        for desktop in LISTS:
            config = tomllib.loads((REPO / f"disk_config/iso-{desktop}.toml").read_text())
            kickstart = config["customizations"]["installer"]["kickstart"]["contents"]
            self.assertIn(f"touch {PENDING}", kickstart)
            self.assertIn(f"justin-bazzite-dx-{desktop}:latest", kickstart)
            subprocess.run(["bash", "-n"], input=kickstart.split("%post --erroronfail\n")[1]
                           .split("%end")[0], text=True, check=True)
        disk = tomllib.loads((REPO / "disk_config/disk.toml").read_text())["customizations"]
        self.assertNotIn("directories", disk)
        self.assertEqual(disk["files"], [{"path": PENDING, "mode": "0644",
                                         "user": "root", "group": "root", "data": ""}])
        # Enrollment belongs to the installer/disk config, never the OCI OS image.
        self.assertFalse((REPO / f"system_files{PENDING}").exists())
        link = UNITS / "timers.target.wants/justin-flatpak-setup.timer"
        self.assertEqual(link.readlink(), Path("../justin-flatpak-setup.timer"))

        # Verify the shipped units unchanged against a minimal image filesystem.
        units = self.root / "usr/lib/systemd/system"
        units.mkdir(parents=True)
        for suffix in ("service", "timer"):
            name = f"justin-flatpak-setup.{suffix}"
            source = (UNITS / name).read_text()
            self.assertIn(f"ConditionPathExists={PENDING}\n", source)
            if suffix == "service":
                self.assertIn("After=network-online.target bazzite-flatpak-manager.service\n", source)
                self.assertIn("TimeoutStartSec=2h\n", source)
            else:
                self.assertIn("OnBootSec=2min\nOnUnitInactiveSec=5min\n", source)
            (units / name).write_text(source)
        for name in ("sysinit", "basic", "shutdown", "timers"):
            (units / f"{name}.target").write_text("[Unit]\nDefaultDependencies=no\n")
        (units / "bazzite-flatpak-manager.service").write_text(
            "[Service]\nType=oneshot\nExecStart=/usr/libexec/justin-flatpak-setup\n")
        executable = self.root / "usr/libexec/justin-flatpak-setup"
        executable.parent.mkdir(parents=True)
        executable.write_text("#!/bin/bash\n")
        executable.chmod(0o755)
        result = subprocess.run(["systemd-analyze", f"--root={self.root}", "verify",
                                 "justin-flatpak-setup.service", "justin-flatpak-setup.timer"],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
