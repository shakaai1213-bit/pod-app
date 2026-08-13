from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


SCRIPT = Path(__file__).with_name("generate_release_evidence.py")


def test_manifest_binds_complete_rollback_state(tmp_path: Path) -> None:
    root = tmp_path / "root"
    root.mkdir()
    artifact = tmp_path / "ORCA Console.zip"
    artifact.write_bytes(b"signed app")
    output = tmp_path / "evidence"
    hex64 = "a" * 64
    subprocess.run(
        [
            sys.executable,
            str(SCRIPT),
            "--root",
            str(root),
            "--artifact",
            str(artifact),
            "--source-commit",
            "1" * 40,
            "--backend-commit",
            "2" * 40,
            "--backend-image-digest",
            f"sha256:{'3' * 64}",
            "--host-bundle-sha256",
            "4" * 64,
            "--rollback-release-ref",
            "orca-console:prior",
            "--rollback-artifact-sha256",
            hex64,
            "--rollback-manifest-sha256",
            "b" * 64,
            "--rollback-backend-commit",
            "5" * 40,
            "--rollback-backend-image-digest",
            f"sha256:{'6' * 64}",
            "--rollback-host-bundle-sha256",
            "7" * 64,
            "--rollback-auth-state-sha256",
            "8" * 64,
            "--output-dir",
            str(output),
        ],
        check=True,
    )

    manifest = json.loads((output / "manifest.json").read_text())
    assert manifest["schema"] == "orca.console.release-manifest.v2"
    assert manifest["rollback"] == {
        "artifact_sha256": hex64,
        "auth_state_sha256": "8" * 64,
        "backend_commit": "5" * 40,
        "backend_image_digest": f"sha256:{'6' * 64}",
        "host_bundle_sha256": "7" * 64,
        "manifest_sha256": "b" * 64,
        "procedure": "restore only the hash-bound prior app, runtime, host bundle, and non-secret auth-state contract; then rerun compatibility and G1-G10 canaries",
        "release_ref": "orca-console:prior",
    }
