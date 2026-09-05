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
    parser.add_argument(
        "--runtime-commit-trust",
        choices=("git-ssh-signed", "preinstall-attested-legacy"),
        required=True,
    )
    parser.add_argument("--runtime-host-id", required=True)
    parser.add_argument("--runtime-source", type=Path, required=True)
    parser.add_argument("--backend-image", type=Path, required=True)
    parser.add_argument("--host-bundle", type=Path, required=True)
    parser.add_argument("--auth-state-contract", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--install-path", type=Path, default=INSTALL_PATH)
    args = parser.parse_args()

    if re.fullmatch(r"[0-9a-f]{40}", args.runtime_commit) is None:
        raise SystemExit("preinstall capture refused: invalid runtime commit")
    runtime_source = args.runtime_source.resolve()
    backend_image = args.backend_image.resolve()
    host_bundle = args.host_bundle.resolve()
    auth_state = args.auth_state_contract.resolve()
    for path in (runtime_source, backend_image, host_bundle, auth_state):
        if not path.is_file():
            raise SystemExit(f"preinstall capture refused: missing artifact: {path}")
    if args.install_path.exists() or args.install_path.is_symlink():
        raise SystemExit(
            f"preinstall capture refused: app target already exists: {args.install_path}"
        )
    app_host_id = platform.node()
    if re.fullmatch(r"[A-Za-z0-9._-]{1,255}", app_host_id) is None:
        raise SystemExit("preinstall capture refused: invalid app host identifier")
    if re.fullmatch(r"[A-Za-z0-9._-]{1,255}", args.runtime_host_id) is None:
        raise SystemExit("preinstall capture refused: invalid runtime host identifier")
    try:
        auth_payload = json.loads(auth_state.read_text(encoding="utf-8"))
        captured_at = str(auth_payload["captured_at"])
        if not captured_at.endswith("Z"):
            raise ValueError
        auth_captured_at = datetime.fromisoformat(
            captured_at.removesuffix("Z") + "+00:00"
        )
    except (KeyError, TypeError, ValueError, json.JSONDecodeError) as exc:
        raise SystemExit("preinstall capture refused: invalid auth-state capture") from exc
    if auth_payload.get("runtime_commit") != args.runtime_commit:
        raise SystemExit("preinstall capture refused: auth state does not match runtime")
    if auth_payload.get("runtime_host_id") != args.runtime_host_id:
        raise SystemExit("preinstall capture refused: auth state does not match host")
    auth_state_age = datetime.now(timezone.utc) - auth_captured_at
    if auth_state_age.total_seconds() < -60 or auth_state_age.total_seconds() > 900:
        raise SystemExit("preinstall capture refused: auth state is stale or future-dated")

    payload = {
        "app_bundle_id": "com.orcamc.mac",
        "app_present": False,
        "auth_state_sha256": sha256(auth_state),
        "backend_image_sha256": sha256(backend_image),
        "host_bundle_sha256": sha256(host_bundle),
        "app_host_id": app_host_id,
        "install_path": str(args.install_path),
        "observed_at": datetime.now(timezone.utc)
        .isoformat(timespec="seconds")
        .replace("+00:00", "Z"),
        "runtime_commit": args.runtime_commit,
        "runtime_commit_trust": args.runtime_commit_trust,
        "runtime_host_id": args.runtime_host_id,
        "runtime_source_sha256": sha256(runtime_source),
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
