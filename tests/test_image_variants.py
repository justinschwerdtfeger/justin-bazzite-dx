"""Exercise Just recipes with Podman replaced at the host command boundary."""

import itertools
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[1]
VARIANTS = tuple(itertools.product(("gnome", "kde"), ("default", "nvidia-open")))
PODMAN = r'''#!/usr/bin/env python3
import json, os, pathlib, sys
args = sys.argv[1:]
with open(os.environ["PODMAN_CALLS"], "a") as log:
    log.write(json.dumps(args) + "\n")
if args[:2] == ["image", "inspect"]:
    print("fixture-image-id")
elif args[0] == "run":
    for arg in args:
        if arg.endswith(":/output"):
            output = pathlib.Path(arg.removesuffix(":/output")) / "bootiso/install.iso"
            output.parent.mkdir(parents=True)
            output.write_text("fixture ISO")
'''


class ImageVariantTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.work = self.root / "work"
        self.work.mkdir()
        for directory in ("build_files", "disk_config"):
            shutil.copytree(REPO / directory, self.work / directory)
        subprocess.run(["git", "init", "-q", str(self.work)], check=True)
        commands = self.root / "bin"
        commands.mkdir()
        for name, source in (("podman", PODMAN), ("sudo", '#!/bin/sh\nexec "$@"\n')):
            path = commands / name
            path.write_text(source)
            path.chmod(0o755)
        # The recipe calls sudo by its absolute host path.
        justfile = (REPO / "Justfile").read_text().replace(
            "/usr/bin/sudo", str(commands / "sudo"))
        (self.work / "Justfile").write_text(justfile)
        self.calls = self.root / "calls.jsonl"
        self.env = {key: value for key, value in os.environ.items() if key not in (
            "DESKTOP", "GPU", "IMAGE_NAME", "DEFAULT_TAG", "SSH_ASKPASS",
        )}
        self.env.update(
            PATH=f"{commands}:{os.environ['PATH']}",
            XDG_RUNTIME_DIR=str(self.root), PODMAN_CALLS=str(self.calls),
        )

    def run_just(self, *args, desktop="gnome", gpu="default"):
        self.calls.unlink(missing_ok=True)
        result = subprocess.run(
            ["just", *args], cwd=self.work,
            env=self.env | {"DESKTOP": desktop, "GPU": gpu},
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return [json.loads(line) for line in self.calls.read_text().splitlines()]

    def test_container_base_and_default_image_names(self):
        for desktop, gpu in VARIANTS:
            with self.subTest(desktop=desktop, gpu=gpu):
                calls = self.run_just("build", desktop=desktop, gpu=gpu)
                build, = calls
                self.assertEqual(build[0], "build")
                self.assertIn(f"DESKTOP={desktop}", build)
                self.assertIn(f"GPU={gpu}", build)
                suffix = "" if gpu == "default" else f"-{gpu}"
                self.assertEqual(build[build.index("--tag") + 1],
                                 f"justin-bazzite-dx-{desktop}{suffix}:latest")

    def test_explicit_image_tag_and_desktop_are_preserved(self):
        build, = self.run_just("build", "localhost/custom", "dev", "kde", gpu="nvidia-open")
        self.assertIn("DESKTOP=kde", build)
        self.assertIn("GPU=nvidia-open", build)
        self.assertEqual(build[build.index("--tag") + 1], "localhost/custom:dev")

    def test_iso_config_and_update_target_match_container_variant(self):
        import tomllib

        for desktop, gpu in VARIANTS:
            with self.subTest(desktop=desktop, gpu=gpu):
                calls = self.run_just("rebuild-iso", desktop=desktop, gpu=gpu)
                build, = (call for call in calls if call[0] == "build")
                self.assertIn(f"GPU={gpu}", build)
                run, = (call for call in calls if call[0] == "run")
                self.assertEqual(run[run.index("--type") + 1], "anaconda-iso")
                config, = (arg.removesuffix(":/config.toml:ro") for arg in run
                           if arg.endswith(":/config.toml:ro"))
                suffix = "" if gpu == "default" else f"-{gpu}"
                self.assertEqual(Path(config).name, f"iso-{desktop}{suffix}.toml")
                kickstart = tomllib.loads(Path(config).read_text())["customizations"]["installer"]["kickstart"]["contents"]
                self.assertIn(f"ghcr.io/justinschwerdtfeger/justin-bazzite-dx-{desktop}{suffix}:latest", kickstart)
                self.assertIn("touch /etc/justin-flatpak-setup-pending", kickstart)
                image = f"localhost/justin-bazzite-dx-{desktop}{suffix}:latest"
                self.assertIn(image, run)
                artifact = self.work / f"output/{desktop}/localhost_justin-bazzite-dx-{desktop}{suffix}/latest/bootiso/install.iso"
                self.assertEqual(artifact.read_text(), "fixture ISO")

    def test_invalid_gpu_stops_before_podman_build(self):
        result = subprocess.run(
            ["just", "build"], cwd=self.work,
            env=self.env | {"GPU": "unsupported"}, capture_output=True, text=True,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Unsupported GPU", result.stderr)
        self.assertFalse(self.calls.exists())


if __name__ == "__main__":
    unittest.main()
