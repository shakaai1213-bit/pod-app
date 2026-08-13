#!/usr/bin/env python3
"""Independently verify an immutable ORCA Console release evidence bundle."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import tempfile
from pathlib import Path
from typing import Any


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def require_digest(value: Any, label: str) -> str:
    text = str(value or "")
    if re.fullmatch(r"[0-9a-f]{64}", text) is None:
        raise ValueError(f"invalid {label}")
    return text


def require_commit(value: Any, label: str) -> str:
    text = str(value or "")
    if re.fullmatch(r"[0-9a-f]{40}", text) is None:
        raise ValueError(f"invalid {label}")
    return text


def resolve_row(root: Path, row: dict[str, Any], label: str) -> Path:
    name = str(row.get("name") or "")
    relative = Path(name)
    if not name or relative.is_absolute() or ".." in relative.parts:
        raise ValueError(f"invalid {label} path")
    path = (root / relative).resolve()
    try:
        path.relative_to(root)
    except ValueError as exc:
        raise ValueError(f"invalid {label} path") from exc
    if not path.is_file():
        raise ValueError(f"missing {label}: {path}")
    if row.get("size_bytes") != path.stat().st_size:
        raise ValueError(f"{label} size mismatch")
    if require_digest(row.get("sha256"), f"{label} digest") != sha256(path):
        raise ValueError(f"{label} digest mismatch")
    return path


def verify_signature(
    path: Path,
    signature: Path,
    *,
    allowed_signers: Path,
    signer_identity: str,
    namespace: str,
) -> None:
    subprocess.run(
        [
            "ssh-keygen",
            "-Y",
            "verify",
            "-n",
            namespace,
            "-f",
            str(allowed_signers),
            "-I",
            signer_identity,
            "-s",
            str(signature),
        ],
        input=path.read_bytes(),
        check=True,
        capture_output=True,
    )


def verify_commit_object(
    object_path: Path,
    commit: str,
    *,
    allowed_signers: Path,
) -> None:
    expected = require_commit(commit, "commit")
    with tempfile.TemporaryDirectory(prefix="orca-release-git-") as temp_dir:
        repository = Path(temp_dir)
        subprocess.run(["git", "init", "-q", str(repository)], check=True)
        actual = (
            subprocess.check_output(
                [
                    "git",
                    "-C",
                    str(repository),
                    "hash-object",
                    "-t",
                    "commit",
                    "-w",
                    "--stdin",
                ],
                input=object_path.read_bytes(),
            )
            .decode()
            .strip()
        )
        if actual != expected:
            raise ValueError("commit object identity mismatch")
        subprocess.run(
            [
                "git",
                "-C",
                str(repository),
                "-c",
                "gpg.format=ssh",
                "-c",
                f"gpg.ssh.allowedSignersFile={allowed_signers}",
                "verify-commit",
                expected,
            ],
            check=True,
            capture_output=True,
        )


def token_family_digest(family_hashes: list[str]) -> str:
    return hashlib.sha256(("\n".join(family_hashes) + "\n").encode()).hexdigest()


def verify_auth_state(path: Path, *, runtime_commit: str) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("schema") != "orca.native-auth.state.v1":
        raise ValueError("invalid rollback auth-state schema")
    if payload.get("runtime_commit") != runtime_commit:
        raise ValueError("rollback auth state does not match runtime")
    hashes = payload.get("active_refresh_family_hashes")
    if not isinstance(hashes, list) or hashes != sorted(set(hashes)):
        raise ValueError("invalid active refresh family hashes")
    if any(re.fullmatch(r"[0-9a-f]{64}", str(value)) is None for value in hashes):
        raise ValueError("invalid active refresh family hash")
    if payload.get("active_refresh_families") != len(hashes):
        raise ValueError("active refresh family count mismatch")
    if payload.get("active_refresh_family_digest") != token_family_digest(hashes):
        raise ValueError("active refresh family digest mismatch")
    return payload


def verify_transition(path: Path) -> None:
    expected = {
        "schema": "orca.native-auth.transition.v1",
        "migration_revision": "20260813_native_device_proof",
        "upgrade_action": "require_device_key_proof_for_native_refresh_and_api_requests",
        "rollback_action": "revoke_all_refresh_families_before_schema_downgrade",
        "rollback_preserves_sessions": False,
    }
    if json.loads(path.read_text(encoding="utf-8")) != expected:
        raise ValueError("invalid native auth transition contract")


def verify_bundle(
    evidence_dir: Path,
    artifact: Path,
    *,
    allowed_signers: Path,
    trusted_allowed_signers_sha256: str,
    signer_identity: str,
) -> None:
    evidence_dir = evidence_dir.resolve()
    manifest_path = evidence_dir / "manifest.json"
    signature_path = evidence_dir / "manifest.json.sig"
    if (
        not manifest_path.is_file()
        or not signature_path.is_file()
        or not artifact.is_file()
    ):
        raise ValueError("release evidence bundle is incomplete")
    trusted_hash = require_digest(
        trusted_allowed_signers_sha256,
        "trusted allowed-signers registry",
    )
    if sha256(allowed_signers) != trusted_hash:
        raise ValueError("allowed-signers registry does not match external trust hash")
    verify_signature(
        manifest_path,
        signature_path,
        allowed_signers=allowed_signers,
        signer_identity=signer_identity,
        namespace="orca-release",
    )
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("schema") != "orca.console.release-manifest.v4":
        raise ValueError("unsupported release manifest schema")
    trust = manifest.get("trust") or {}
    if trust.get("allowed_signers_sha256") != trusted_hash:
        raise ValueError("manifest signer registry does not match external trust hash")
    if trust.get("release_signer_identity") != signer_identity:
        raise ValueError("manifest signer identity mismatch")

    artifact_row = manifest.get("artifact") or {}
    if artifact_row.get("name") != artifact.name:
        raise ValueError("release artifact name mismatch")
    if artifact_row.get("size_bytes") != artifact.stat().st_size:
        raise ValueError("release artifact size mismatch")
    if require_digest(artifact_row.get("sha256"), "release artifact") != sha256(
        artifact
    ):
        raise ValueError("release artifact digest mismatch")
    dependencies = manifest.get("dependencies") or {}
    sbom = resolve_row(
        evidence_dir,
        {
            "name": dependencies.get("sbom"),
            "sha256": dependencies.get("sbom_sha256"),
            "size_bytes": dependencies.get("sbom_size_bytes"),
        },
        "current SBOM",
    )
    if dependencies.get("sbom") != sbom.name:
        raise ValueError("current SBOM identity mismatch")

    source = manifest.get("source") or {}
    if source.get("commit_signed") is not True or source.get("dirty") is not False:
        raise ValueError("current source integrity flags are invalid")
    source_object = resolve_row(
        evidence_dir,
        source.get("commit_object") or {},
        "current source commit object",
    )
    verify_commit_object(
        source_object,
        require_commit(source.get("commit"), "current source commit"),
        allowed_signers=allowed_signers,
    )
    runtime = manifest.get("runtime") or {}
    if runtime.get("backend_commit_signed") is not True:
        raise ValueError("current runtime signature flag is invalid")
    runtime_object = resolve_row(
        evidence_dir,
        runtime.get("backend_commit_object") or {},
        "current runtime commit object",
    )
    verify_commit_object(
        runtime_object,
        require_commit(runtime.get("backend_commit"), "current runtime commit"),
        allowed_signers=allowed_signers,
    )
    resolve_row(
        evidence_dir, runtime.get("backend_image") or {}, "current runtime image"
    )
    resolve_row(evidence_dir, runtime.get("host_bundle") or {}, "current host bundle")
    transition = manifest.get("auth_transition") or {}
    transition_path = resolve_row(
        evidence_dir,
        {
            "name": transition.get("contract"),
            "sha256": transition.get("contract_sha256"),
            "size_bytes": (evidence_dir / str(transition.get("contract") or ""))
            .stat()
            .st_size
            if (evidence_dir / str(transition.get("contract") or "")).is_file()
            else -1,
        },
        "auth transition",
    )
    verify_transition(transition_path)

    rollback = manifest.get("rollback") or {}
    prior_manifest_path = resolve_row(
        evidence_dir, rollback.get("manifest") or {}, "rollback manifest"
    )
    prior_signature = resolve_row(
        evidence_dir,
        rollback.get("manifest_signature") or {},
        "rollback manifest signature",
    )
    verify_signature(
        prior_manifest_path,
        prior_signature,
        allowed_signers=allowed_signers,
        signer_identity=signer_identity,
        namespace="orca-release",
    )
    prior = json.loads(prior_manifest_path.read_text(encoding="utf-8"))
    if prior.get("schema") not in {
        "orca.console.release-manifest.v2",
        "orca.console.release-manifest.v3",
        "orca.console.release-manifest.v4",
    }:
        raise ValueError("unsupported rollback manifest schema")
    prior_source = prior.get("source") or {}
    prior_source_commit = require_commit(
        prior_source.get("commit"), "rollback source commit"
    )
    if rollback.get("source_commit") != prior_source_commit:
        raise ValueError("rollback source commit mismatch")
    rollback_source_object = resolve_row(
        evidence_dir,
        rollback.get("source_commit_object") or {},
        "rollback source commit object",
    )
    verify_commit_object(
        rollback_source_object,
        prior_source_commit,
        allowed_signers=allowed_signers,
    )
    prior_artifact = resolve_row(
        evidence_dir, rollback.get("artifact") or {}, "rollback artifact"
    )
    prior_artifact_row = prior.get("artifact") or {}
    if (
        prior_artifact.name != prior_artifact_row.get("name")
        or sha256(prior_artifact) != prior_artifact_row.get("sha256")
        or prior_artifact.stat().st_size != prior_artifact_row.get("size_bytes")
    ):
        raise ValueError("rollback artifact disagrees with signed prior manifest")
    prior_sbom = resolve_row(evidence_dir, rollback.get("sbom") or {}, "rollback SBOM")
    prior_dependencies = prior.get("dependencies") or {}
    if prior_sbom.name != prior_dependencies.get("sbom") or sha256(
        prior_sbom
    ) != prior_dependencies.get("sbom_sha256"):
        raise ValueError("rollback SBOM disagrees with signed prior manifest")
    prior_runtime = prior.get("runtime") or {}
    prior_runtime_commit = require_commit(
        prior_runtime.get("backend_commit"), "rollback runtime commit"
    )
    if rollback.get("backend_commit") != prior_runtime_commit:
        raise ValueError("rollback runtime commit mismatch")
    rollback_runtime_object = resolve_row(
        evidence_dir,
        rollback.get("backend_commit_object") or {},
        "rollback runtime commit object",
    )
    verify_commit_object(
        rollback_runtime_object,
        prior_runtime_commit,
        allowed_signers=allowed_signers,
    )
    prior_image = resolve_row(
        evidence_dir, rollback.get("backend_image") or {}, "rollback runtime image"
    )
    prior_image_contract = prior_runtime.get("backend_image") or {}
    expected_prior_image = (
        prior_image_contract.get("sha256")
        if prior_image_contract
        else str(prior_runtime.get("backend_image_digest") or "").removeprefix(
            "sha256:"
        )
    )
    if sha256(prior_image) != expected_prior_image:
        raise ValueError("rollback runtime image disagrees with signed prior manifest")
    prior_host = resolve_row(
        evidence_dir, rollback.get("host_bundle") or {}, "rollback host bundle"
    )
    prior_host_contract = prior_runtime.get("host_bundle") or {}
    expected_prior_host = (
        prior_host_contract.get("sha256")
        if prior_host_contract
        else prior_runtime.get("host_bundle_sha256")
    )
    if sha256(prior_host) != expected_prior_host:
        raise ValueError("rollback host bundle disagrees with signed prior manifest")
    auth_row = rollback.get("auth_state") or {}
    auth_path = resolve_row(evidence_dir, auth_row, "rollback auth state")
    auth_signature = resolve_row(
        evidence_dir, auth_row.get("signature") or {}, "rollback auth-state signature"
    )
    verify_signature(
        auth_path,
        auth_signature,
        allowed_signers=allowed_signers,
        signer_identity=signer_identity,
        namespace="orca-auth-state",
    )
    auth_state = verify_auth_state(auth_path, runtime_commit=prior_runtime_commit)
    if auth_row.get("active_refresh_family_digest") != auth_state.get(
        "active_refresh_family_digest"
    ):
        raise ValueError("rollback auth-state family digest mismatch")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("evidence_dir", type=Path)
    parser.add_argument("artifact", type=Path)
    parser.add_argument("--allowed-signers", type=Path, required=True)
    parser.add_argument("--trusted-allowed-signers-sha256", required=True)
    parser.add_argument("--signer-identity", required=True)
    args = parser.parse_args()
    verify_bundle(
        args.evidence_dir,
        args.artifact,
        allowed_signers=args.allowed_signers.resolve(),
        trusted_allowed_signers_sha256=args.trusted_allowed_signers_sha256,
        signer_identity=args.signer_identity,
    )
    print("ORCA Console release evidence verified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
