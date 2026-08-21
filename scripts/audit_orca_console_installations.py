#!/usr/bin/env python3
"""Inventory user-facing ORCA Console copies before a signed release.

The audit is read-only. It distinguishes installed or loose app copies from
build/evidence products and emits a preserve-first quarantine plan. A release
must refuse while a user-facing duplicate, malformed bundle, or wrong identity
is present.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import plistlib
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable


SCHEMA = "orca.console.installation-inventory.v1"
CANONICAL_INSTALL_PATH = Path("/Applications/ORCA Console.app")
CANONICAL_BUNDLE_ID = "com.orcamc.mac"
CANONICAL_PRODUCT_NAME = "ORCA Console"
DEFAULT_QUARANTINE_ROOT = (
    Path("/Volumes") / "DockerExt" / "quarantine" / "orca-console-preinstall"
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _absolute(path: Path) -> Path:
    return Path(os.path.abspath(path.expanduser()))


def _walk_apps(root: Path, *, max_depth: int) -> Iterable[Path]:
    root = _absolute(root)
    if not root.exists():
        return
    if root.name.lower().endswith(".app"):
        yield root
        return
    for directory, dirnames, _filenames in os.walk(root, followlinks=False):
        current = Path(directory)
        depth = len(current.relative_to(root).parts)
        if depth >= max_depth:
            dirnames[:] = []
            continue
        app_names = [name for name in dirnames if name.lower().endswith(".app")]
        for name in sorted(app_names):
            yield current / name
        dirnames[:] = [name for name in dirnames if name not in app_names]


def _read_identity(app: Path) -> dict[str, Any]:
    info_path = app / "Contents" / "Info.plist"
    try:
        with info_path.open("rb") as handle:
            info = plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException):
        return {
            "bundle_id": None,
            "bundle_name": None,
            "bundle_version": None,
            "executable_name": None,
            "executable_sha256": None,
            "identity_valid": False,
        }
    executable_name = str(info.get("CFBundleExecutable") or "").strip()
    executable = app / "Contents" / "MacOS" / executable_name
    executable_digest = sha256(executable) if executable.is_file() else None
    return {
        "bundle_id": str(info.get("CFBundleIdentifier") or "").strip() or None,
        "bundle_name": str(
            info.get("CFBundleDisplayName") or info.get("CFBundleName") or ""
        ).strip()
        or None,
        "bundle_version": str(
            info.get("CFBundleVersion") or info.get("CFBundleShortVersionString") or ""
        ).strip()
        or None,
        "executable_name": executable_name or None,
        "executable_sha256": executable_digest,
        "identity_valid": bool(executable_digest),
    }


def _is_orca_candidate(path: Path, identity: dict[str, Any]) -> bool:
    return (
        "orca" in path.stem.casefold()
        or identity.get("bundle_id") == CANONICAL_BUNDLE_ID
        or "orca" in str(identity.get("bundle_name") or "").casefold()
    )


def _quarantine_target(
    app: Path,
    identity: dict[str, Any],
    *,
    quarantine_root: Path,
) -> Path:
    fingerprint = str(identity.get("executable_sha256") or "unreadable")[:12]
    return _absolute(quarantine_root) / f"{app.stem}-{fingerprint}.app"


def build_inventory(
    *,
    mode: str,
    install_roots: list[Path],
    loose_roots: list[Path],
    evidence_roots: list[Path],
    canonical_path: Path = CANONICAL_INSTALL_PATH,
    quarantine_root: Path = DEFAULT_QUARANTINE_ROOT,
    max_depth: int = 4,
) -> dict[str, Any]:
    if mode not in {"initial-install", "upgrade"}:
        raise ValueError("mode must be initial-install or upgrade")
    canonical_path = _absolute(canonical_path)
    roots: list[tuple[str, Path]] = [
        *(('install', _absolute(path)) for path in install_roots),
        *(('loose', _absolute(path)) for path in loose_roots),
        *(('evidence', _absolute(path)) for path in evidence_roots),
    ]
    seen: set[str] = set()
    entries: list[dict[str, Any]] = []
    violations: list[dict[str, str]] = []
    quarantine_plan: list[dict[str, Any]] = []

    for root_kind, root in roots:
        for app in _walk_apps(root, max_depth=max_depth):
            absolute = _absolute(app)
            key = str(absolute)
            if key in seen:
                continue
            seen.add(key)
            identity = _read_identity(absolute)
            if not _is_orca_candidate(absolute, identity):
                continue
            if absolute == canonical_path:
                classification = "canonical_install"
            elif root_kind == "install":
                classification = "installed_duplicate"
            elif root_kind == "loose":
                classification = "loose_copy"
            else:
                classification = "build_evidence"
            canonical_identity = (
                identity.get("bundle_id") == CANONICAL_BUNDLE_ID
                and identity.get("bundle_name") == CANONICAL_PRODUCT_NAME
                and identity.get("identity_valid") is True
            )
            entry = {
                "path": key,
                "classification": classification,
                "is_symlink": absolute.is_symlink(),
                "canonical_identity": canonical_identity,
                **identity,
            }
            entries.append(entry)

            if classification != "build_evidence":
                if absolute.is_symlink():
                    violations.append({"path": key, "reason": "app_symlink_refused"})
                if not identity.get("identity_valid"):
                    violations.append({"path": key, "reason": "malformed_app_bundle"})
                elif not canonical_identity:
                    violations.append({"path": key, "reason": "bundle_identity_mismatch"})
            if classification in {"installed_duplicate", "loose_copy"}:
                violations.append({"path": key, "reason": classification})
                quarantine_plan.append(
                    {
                        "source": key,
                        "destination": str(
                            _quarantine_target(
                                absolute,
                                identity,
                                quarantine_root=quarantine_root,
                            )
                        ),
                        "preserve_before_move": {
                            "bundle_id": identity.get("bundle_id"),
                            "bundle_version": identity.get("bundle_version"),
                            "executable_sha256": identity.get("executable_sha256"),
                        },
                    }
                )

    entries.sort(key=lambda row: (str(row["classification"]), str(row["path"])))
    canonical_entries = [
        row for row in entries if row["classification"] == "canonical_install"
    ]
    if mode == "initial-install" and canonical_entries:
        violations.append(
            {"path": str(canonical_path), "reason": "initial_install_target_present"}
        )
    if mode == "upgrade" and len(canonical_entries) != 1:
        violations.append(
            {"path": str(canonical_path), "reason": "upgrade_target_missing"}
        )
    if mode == "upgrade" and canonical_entries and not canonical_entries[0][
        "canonical_identity"
    ]:
        violations.append(
            {"path": str(canonical_path), "reason": "upgrade_identity_mismatch"}
        )

    violations = sorted(
        {json.dumps(row, sort_keys=True): row for row in violations}.values(),
        key=lambda row: (row["path"], row["reason"]),
    )
    counts = {
        classification: sum(
            1 for entry in entries if entry["classification"] == classification
        )
        for classification in (
            "canonical_install",
            "installed_duplicate",
            "loose_copy",
            "build_evidence",
        )
    }
    return {
        "schema": SCHEMA,
        "mode": mode,
        "observed_at": datetime.now(timezone.utc)
        .isoformat(timespec="seconds")
        .replace("+00:00", "Z"),
        "app_host_id": platform.node(),
        "canonical_install_path": str(canonical_path),
        "canonical_bundle_id": CANONICAL_BUNDLE_ID,
        "canonical_product_name": CANONICAL_PRODUCT_NAME,
        "scan_roots": [
            {"kind": kind, "path": str(path)} for kind, path in roots
        ],
        "counts": counts,
        "entries": entries,
        "quarantine_plan": quarantine_plan,
        "violations": violations,
        "ready": not violations,
    }


def main() -> int:
    home = Path.home()
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=("initial-install", "upgrade"), required=True)
    parser.add_argument("--install-root", type=Path, action="append")
    parser.add_argument("--loose-root", type=Path, action="append")
    parser.add_argument("--evidence-root", type=Path, action="append", default=[])
    parser.add_argument("--canonical-path", type=Path, default=CANONICAL_INSTALL_PATH)
    parser.add_argument("--quarantine-root", type=Path, default=DEFAULT_QUARANTINE_ROOT)
    parser.add_argument("--max-depth", type=int, default=4)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--strict", action="store_true")
    args = parser.parse_args()
    install_roots = args.install_root or [Path("/Applications"), home / "Applications"]
    loose_roots = args.loose_root or [home / "Desktop", home / "Downloads"]
    inventory = build_inventory(
        mode=args.mode,
        install_roots=install_roots,
        loose_roots=loose_roots,
        evidence_roots=args.evidence_root,
        canonical_path=args.canonical_path,
        quarantine_root=args.quarantine_root,
        max_depth=args.max_depth,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(inventory, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(json.dumps({"output": str(args.output), "ready": inventory["ready"]}))
    return 2 if args.strict and not inventory["ready"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
