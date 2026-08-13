#!/usr/bin/env python3
"""Create a short-lived, privacy-preserving ORCA runtime auth-state contract."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path


def family_digest(family_hashes: list[str]) -> str:
    return hashlib.sha256(("\n".join(family_hashes) + "\n").encode()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime-commit", required=True)
    parser.add_argument("--runtime-host-id", required=True)
    parser.add_argument(
        "--native-refresh-policy",
        choices=("legacy", "device-key-bound"),
        required=True,
    )
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    if re.fullmatch(r"[0-9a-f]{40}", args.runtime_commit) is None:
        raise SystemExit("auth-state capture refused: invalid runtime commit")
    if re.fullmatch(r"[A-Za-z0-9._-]{1,255}", args.runtime_host_id) is None:
        raise SystemExit("auth-state capture refused: invalid runtime host identifier")

    identifiers = [line.rstrip("\r\n") for line in sys.stdin]
    if any(not identifier for identifier in identifiers):
        raise SystemExit("auth-state capture refused: empty family identifier")
    family_hashes = sorted(
        {hashlib.sha256(identifier.encode()).hexdigest() for identifier in identifiers}
    )
    payload = {
        "active_refresh_families": len(family_hashes),
        "active_refresh_family_digest": family_digest(family_hashes),
        "active_refresh_family_hashes": family_hashes,
        "captured_at": datetime.now(timezone.utc)
        .isoformat(timespec="seconds")
        .replace("+00:00", "Z"),
        "native_refresh_policy": args.native_refresh_policy,
        "runtime_commit": args.runtime_commit,
        "runtime_host_id": args.runtime_host_id,
        "schema": "orca.native-auth.state.v1",
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    os.chmod(args.output, 0o600)
    print(args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
