#!/usr/bin/env python3
"""Render an installer config that follows the selected registry image."""

import argparse
from pathlib import Path
import re
import tomllib


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image_ref", help="Installed system's registry image, with tag or digest")
    parser.add_argument("output", type=Path)
    parser.add_argument("--template", type=Path, default=Path("disk_config/iso.toml"))
    args = parser.parse_args()
    # This reference is embedded in a shell command inside a TOML string.
    if not re.fullmatch(
        r"[a-z0-9][a-z0-9._:/-]*(?::[A-Za-z0-9_][A-Za-z0-9_.-]*|@sha256:[0-9a-f]{64})",
        args.image_ref,
    ):
        parser.error("image_ref must be a registry reference with a tag or sha256 digest")
    template = args.template.read_text()
    if template.count("@IMAGE_REF@") != 1:
        parser.error("template must contain exactly one @IMAGE_REF@ placeholder")
    rendered = template.replace("@IMAGE_REF@", args.image_ref)
    tomllib.loads(rendered)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(rendered)


if __name__ == "__main__":
    main()
