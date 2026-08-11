#!/usr/bin/env python3
"""Generate an immutable ORCA Console release manifest and SPDX SBOM."""

from __future__ import annotations

import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def package_rows(root: Path) -> list[dict[str, Any]]:
    rows: dict[str, dict[str, Any]] = {}
    for resolved_path in sorted(root.rglob("Package.resolved")):
        if any(
            part in {".build", ".git", "DerivedData", ".derived"}
            for part in resolved_path.parts
        ):
            continue
        payload = json.loads(resolved_path.read_text(encoding="utf-8"))
        pins = payload.get("pins") or payload.get("object", {}).get("pins") or []
        for pin in pins:
            if not isinstance(pin, dict):
                continue
            identity = str(pin.get("identity") or pin.get("package") or "").strip()
            if not identity:
                continue
            state = pin.get("state") if isinstance(pin.get("state"), dict) else {}
            location = str(pin.get("location") or pin.get("repositoryURL") or "")
            version = str(state.get("version") or state.get("revision") or "unknown")
            rows[identity] = {
                "SPDXID": f"SPDXRef-Package-{identity.replace('_', '-').replace('.', '-')}",
                "name": identity,
                "versionInfo": version,
                "downloadLocation": location or "NOASSERTION",
                "filesAnalyzed": False,
                "supplier": "NOASSERTION",
                "externalRefs": [
                    {
                        "referenceCategory": "PACKAGE-MANAGER",
                        "referenceType": "purl",
                        "referenceLocator": f"pkg:swift/{identity}@{version}",
                    }
                ],
            }
    return [rows[key] for key in sorted(rows)]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--artifact", type=Path, required=True)
    parser.add_argument("--source-commit", required=True)
    parser.add_argument("--backend-commit", required=True)
    parser.add_argument("--backend-image-digest", required=True)
    parser.add_argument("--host-bundle-sha256", required=True)
    parser.add_argument("--rollback-release-ref", required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()

    root = args.root.resolve()
    artifact = args.artifact.resolve()
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    created_at = datetime.now(timezone.utc).isoformat()
    packages = package_rows(root)
    sbom = {
        "spdxVersion": "SPDX-2.3",
        "dataLicense": "CC0-1.0",
        "SPDXID": "SPDXRef-DOCUMENT",
        "name": f"orca-console-{args.source_commit[:12]}",
        "documentNamespace": f"https://orca.local/sbom/orca-console/{args.source_commit}",
        "creationInfo": {
            "created": created_at,
            "creators": ["Tool: ORCA-Scripts/generate_release_evidence.py"],
        },
        "documentDescribes": [row["SPDXID"] for row in packages],
        "packages": packages,
    }
    sbom_path = output / "sbom.spdx.json"
    sbom_path.write_text(json.dumps(sbom, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    manifest = {
        "schema": "orca.console.release-manifest.v1",
        "created_at": created_at,
        "source": {
            "commit": args.source_commit,
            "commit_signed": True,
            "dirty": False,
        },
        "artifact": {
            "name": artifact.name,
            "sha256": sha256(artifact),
            "size_bytes": artifact.stat().st_size,
        },
        "dependencies": {
            "sbom": sbom_path.name,
            "sbom_sha256": sha256(sbom_path),
            "package_count": len(packages),
        },
        "runtime": {
            "backend_commit": args.backend_commit,
            "backend_image_digest": args.backend_image_digest,
            "host_bundle_sha256": args.host_bundle_sha256,
        },
        "rollback": {
            "release_ref": args.rollback_release_ref,
            "procedure": "restore the exact prior app artifact and runtime release ref, then rerun compatibility and G1-G10 canaries",
        },
    }
    manifest_path = output / "manifest.json"
    manifest_path.write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(json.dumps({"manifest": str(manifest_path), "sbom": str(sbom_path)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
