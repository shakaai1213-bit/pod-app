#!/usr/bin/env python3
"""Capture the bounded state needed to roll back a first ORCA Console install."""

from __future__ import annotations

import argparse
import hashlib
import json
import platform
import re
from datetime import datetime, timezone
from pathlib import Path


INSTALL_PATH = Path("/Applications/ORCA Console.app")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime-commit", required=True)
    parser.add_argument("--backend-image", type=Path, required=True)
    parser.add_argument("--host-bundle", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--install-path", type=Path, default=INSTALL_PATH)
    args = parser.parse_args()

    if re.fullmatch(r"[0-9a-f]{40}", args.runtime_commit) is None:
        raise SystemExit("preinstall capture refused: invalid runtime commit")
    backend_image = args.backend_image.resolve()
    host_bundle = args.host_bundle.resolve()
    for path in (backend_image, host_bundle):
        if not path.is_file():
            raise SystemExit(f"preinstall capture refused: missing artifact: {path}")
    if args.install_path.exists() or args.install_path.is_symlink():
        raise SystemExit(
            f"preinstall capture refused: app target already exists: {args.install_path}"
        )
    host_id = platform.node()
    if re.fullmatch(r"[A-Za-z0-9._-]{1,255}", host_id) is None:
        raise SystemExit("preinstall capture refused: invalid host identifier")

    payload = {
        "app_bundle_id": "com.orcamc.mac",
        "app_present": False,
        "backend_image_sha256": sha256(backend_image),
        "host_bundle_sha256": sha256(host_bundle),
        "host_id": host_id,
        "install_path": str(args.install_path),
        "observed_at": datetime.now(timezone.utc)
        .isoformat(timespec="seconds")
        .replace("+00:00", "Z"),
        "runtime_commit": args.runtime_commit,
        "schema": "orca.console.preinstall-state.v1",
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
