#!/usr/bin/env python3
"""Generate an immutable ORCA Console release manifest and SPDX SBOM."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
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


def run_checked(command: list[str], *, stdin: bytes | None = None) -> None:
    subprocess.run(command, input=stdin, check=True, capture_output=True)


def verify_signature(
    path: Path,
    *,
    signature: Path,
    allowed_signers: Path,
    signer_identity: str,
    namespace: str,
) -> None:
    run_checked(
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
        stdin=path.read_bytes(),
    )


def verify_git_commit(root: Path, commit: str, *, allowed_signers: Path) -> None:
    run_checked(
        [
            "git",
            "-C",
            str(root),
            "-c",
            "gpg.format=ssh",
            "-c",
            f"gpg.ssh.allowedSignersFile={allowed_signers}",
            "verify-commit",
            commit,
        ]
    )


def write_git_commit_object(
    root: Path,
    commit: str,
    destination: Path,
    *,
    allowed_signers: Path,
) -> dict[str, Any]:
    verify_git_commit(root, commit, allowed_signers=allowed_signers)
    payload = subprocess.check_output(
        ["git", "-C", str(root), "cat-file", "commit", commit]
    )
    actual = (
        subprocess.check_output(
            ["git", "hash-object", "-t", "commit", "--stdin"],
            input=payload,
            text=False,
        )
        .decode()
        .strip()
    )
    if actual != commit:
        raise ValueError("git commit object does not match requested commit")
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(payload)
    return file_row(destination)


def file_row(path: Path, *, name: str | None = None) -> dict[str, Any]:
    return {
        "name": name or path.name,
        "sha256": sha256(path),
        "size_bytes": path.stat().st_size,
    }


def copy_file(source: Path, destination: Path) -> dict[str, Any]:
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, destination)
    return file_row(destination)


def require_digest(value: Any, *, label: str, prefix: bool = False) -> str:
    pattern = r"sha256:[0-9a-f]{64}" if prefix else r"[0-9a-f]{64}"
    text = str(value or "")
    if re.fullmatch(pattern, text) is None:
        raise ValueError(f"invalid {label}")
    return text


def require_commit(value: Any, *, label: str) -> str:
    text = str(value or "")
    if re.fullmatch(r"[0-9a-f]{40}", text) is None:
        raise ValueError(f"invalid {label}")
    return text


def token_family_digest(family_hashes: list[str]) -> str:
    return hashlib.sha256(("\n".join(family_hashes) + "\n").encode()).hexdigest()


def verify_auth_state_contract(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("schema") != "orca.native-auth.state.v1":
        raise ValueError("unsupported rollback auth-state contract")
    require_commit(payload.get("runtime_commit"), label="auth-state runtime commit")
    if payload.get("native_refresh_policy") not in {"legacy", "device-key-bound"}:
        raise ValueError("invalid native refresh policy")
    if (
        not isinstance(payload.get("active_refresh_families"), int)
        or payload["active_refresh_families"] < 0
    ):
        raise ValueError("invalid active refresh family count")
    hashes = payload.get("active_refresh_family_hashes")
    if not isinstance(hashes, list) or hashes != sorted(set(hashes)):
        raise ValueError("invalid active refresh family hashes")
    if any(re.fullmatch(r"[0-9a-f]{64}", str(value)) is None for value in hashes):
        raise ValueError("invalid active refresh family hash")
    if len(hashes) != payload["active_refresh_families"]:
        raise ValueError("active refresh family count does not match hashes")
    if payload.get("active_refresh_family_digest") != token_family_digest(hashes):
        raise ValueError("active refresh family digest mismatch")
    return payload


def verify_auth_transition_contract(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    expected = {
        "schema": "orca.native-auth.transition.v1",
        "migration_revision": "20260813_native_device_proof",
        "upgrade_action": "require_device_key_proof_for_native_refresh_and_api_requests",
        "rollback_action": "revoke_all_refresh_families_before_schema_downgrade",
        "rollback_preserves_sessions": False,
    }
    if payload != expected:
        raise ValueError(
            "native auth transition contract is not the approved v1 contract"
        )
    return payload


def verify_prior_release(
    *,
    evidence_dir: Path,
    artifact: Path,
    source_root: Path,
    backend_root: Path,
    backend_image: Path,
    host_bundle: Path,
    allowed_signers: Path,
    signer_identity: str,
) -> dict[str, Any]:
    manifest_path = evidence_dir / "manifest.json"
    signature_path = evidence_dir / "manifest.json.sig"
    sbom_path = evidence_dir / "sbom.spdx.json"
    for path in (
        manifest_path,
        signature_path,
        sbom_path,
        artifact,
        backend_image,
        host_bundle,
    ):
        if not path.is_file():
            raise ValueError(f"prior release file is missing: {path}")
    verify_signature(
        manifest_path,
        signature=signature_path,
        allowed_signers=allowed_signers,
        signer_identity=signer_identity,
        namespace="orca-release",
    )
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("schema") not in {
        "orca.console.release-manifest.v2",
        "orca.console.release-manifest.v3",
        "orca.console.release-manifest.v4",
    }:
        raise ValueError("unsupported prior release manifest")
    source = manifest.get("source") or {}
    source_commit = require_commit(source.get("commit"), label="prior source commit")
    if source.get("commit_signed") is not True or source.get("dirty") is not False:
        raise ValueError("prior source integrity flags are invalid")
    verify_git_commit(source_root, source_commit, allowed_signers=allowed_signers)
    artifact_row = manifest.get("artifact") or {}
    if (
        artifact_row.get("name") != artifact.name
        or artifact_row.get("size_bytes") != artifact.stat().st_size
    ):
        raise ValueError("prior artifact identity mismatch")
    if require_digest(
        artifact_row.get("sha256"), label="prior artifact digest"
    ) != sha256(artifact):
        raise ValueError("prior artifact digest mismatch")
    dependencies = manifest.get("dependencies") or {}
    if dependencies.get("sbom") != sbom_path.name:
        raise ValueError("prior SBOM identity mismatch")
    if require_digest(
        dependencies.get("sbom_sha256"), label="prior SBOM digest"
    ) != sha256(sbom_path):
        raise ValueError("prior SBOM digest mismatch")
    runtime = manifest.get("runtime") or {}
    backend_commit = require_commit(
        runtime.get("backend_commit"), label="prior backend commit"
    )
    verify_git_commit(backend_root, backend_commit, allowed_signers=allowed_signers)
    image_contract = runtime.get("backend_image") or {}
    expected_image = (
        require_digest(image_contract.get("sha256"), label="prior backend image")
        if image_contract
        else require_digest(
            runtime.get("backend_image_digest"),
            label="prior backend image",
            prefix=True,
        ).removeprefix("sha256:")
    )
    if expected_image != sha256(backend_image):
        raise ValueError("prior backend image digest mismatch")
    host_contract = runtime.get("host_bundle") or {}
    expected_host = require_digest(
        host_contract.get("sha256")
        if host_contract
        else runtime.get("host_bundle_sha256"),
        label="prior host bundle",
    )
    if expected_host != sha256(host_bundle):
        raise ValueError("prior host bundle digest mismatch")
    return {
        "manifest": manifest,
        "manifest_path": manifest_path,
        "signature_path": signature_path,
        "sbom_path": sbom_path,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--artifact", type=Path, required=True)
    parser.add_argument("--source-commit", required=True)
    parser.add_argument("--backend-commit", required=True)
    parser.add_argument("--backend-root", type=Path, required=True)
    parser.add_argument("--backend-image", type=Path, required=True)
    parser.add_argument("--host-bundle", type=Path, required=True)
    parser.add_argument("--auth-transition-contract", type=Path, required=True)
    parser.add_argument("--rollback-evidence-dir", type=Path, required=True)
    parser.add_argument("--rollback-artifact", type=Path, required=True)
    parser.add_argument("--rollback-backend-root", type=Path, required=True)
    parser.add_argument("--rollback-backend-image", type=Path, required=True)
    parser.add_argument("--rollback-host-bundle", type=Path, required=True)
    parser.add_argument("--rollback-auth-state-contract", type=Path, required=True)
    parser.add_argument("--rollback-auth-state-signature", type=Path, required=True)
    parser.add_argument("--release-allowed-signers", type=Path, required=True)
    parser.add_argument("--trusted-allowed-signers-sha256", required=True)
    parser.add_argument("--release-signer-identity", required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()

    root = args.root.resolve()
    artifact = args.artifact.resolve()
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    allowed_signers = args.release_allowed_signers.resolve()
    trusted_signers_sha256 = require_digest(
        args.trusted_allowed_signers_sha256,
        label="trusted allowed-signers registry",
    )
    if sha256(allowed_signers) != trusted_signers_sha256:
        raise SystemExit(
            "release evidence refused: signer registry does not match trusted hash"
        )
    try:
        verify_git_commit(
            root,
            args.source_commit,
            allowed_signers=allowed_signers,
        )
    except subprocess.CalledProcessError:
        raise SystemExit(
            "release evidence refused: source commit signature is not verified"
        )
    current_head = subprocess.check_output(
        ["git", "-C", str(root), "rev-parse", "HEAD"], text=True
    ).strip()
    if current_head != args.source_commit:
        raise SystemExit(
            "release evidence refused: source commit is not the checked-out HEAD"
        )
    if subprocess.run(
        ["git", "-C", str(root), "status", "--porcelain"],
        check=True,
        stdout=subprocess.PIPE,
    ).stdout.strip():
        raise SystemExit("release evidence refused: source tree is dirty")
    prior = verify_prior_release(
        evidence_dir=args.rollback_evidence_dir.resolve(),
        artifact=args.rollback_artifact.resolve(),
        source_root=root,
        backend_root=args.rollback_backend_root.resolve(),
        backend_image=args.rollback_backend_image.resolve(),
        host_bundle=args.rollback_host_bundle.resolve(),
        allowed_signers=allowed_signers,
        signer_identity=args.release_signer_identity,
    )
    backend_root = args.backend_root.resolve()
    backend_image = args.backend_image.resolve()
    host_bundle = args.host_bundle.resolve()
    for path in (backend_image, host_bundle):
        if not path.is_file():
            raise SystemExit(
                f"release evidence refused: runtime artifact is missing: {path}"
            )
    backend_commit = require_commit(args.backend_commit, label="current backend commit")
    try:
        verify_git_commit(backend_root, backend_commit, allowed_signers=allowed_signers)
    except subprocess.CalledProcessError:
        raise SystemExit(
            "release evidence refused: backend commit signature is not verified"
        )
    auth_state_path = args.rollback_auth_state_contract.resolve()
    verify_signature(
        auth_state_path,
        signature=args.rollback_auth_state_signature.resolve(),
        allowed_signers=allowed_signers,
        signer_identity=args.release_signer_identity,
        namespace="orca-auth-state",
    )
    auth_state = verify_auth_state_contract(auth_state_path)
    prior_manifest = prior["manifest"]
    prior_runtime = prior_manifest["runtime"]
    if auth_state["runtime_commit"] != prior_runtime["backend_commit"]:
        raise SystemExit(
            "release evidence refused: rollback auth state does not match prior runtime"
        )
    transition_path = args.auth_transition_contract.resolve()
    verify_auth_transition_contract(transition_path)
    transition_output = output / "native-auth-transition.json"
    transition_output.write_bytes(transition_path.read_bytes())
    source_object = write_git_commit_object(
        root,
        args.source_commit,
        output / "source-commit.object",
        allowed_signers=allowed_signers,
    )
    runtime_object = write_git_commit_object(
        backend_root,
        backend_commit,
        output / "runtime-commit.object",
        allowed_signers=allowed_signers,
    )
    current_image = copy_file(backend_image, output / "runtime" / backend_image.name)
    current_image["name"] = f"runtime/{backend_image.name}"
    current_host = copy_file(host_bundle, output / "runtime" / host_bundle.name)
    current_host["name"] = f"runtime/{host_bundle.name}"

    rollback_dir = output / "rollback"
    rollback_manifest = copy_file(
        prior["manifest_path"], rollback_dir / "manifest.json"
    )
    rollback_manifest["name"] = "rollback/manifest.json"
    rollback_signature = copy_file(
        prior["signature_path"], rollback_dir / "manifest.json.sig"
    )
    rollback_signature["name"] = "rollback/manifest.json.sig"
    rollback_sbom = copy_file(prior["sbom_path"], rollback_dir / "sbom.spdx.json")
    rollback_sbom["name"] = "rollback/sbom.spdx.json"
    rollback_artifact = copy_file(
        args.rollback_artifact.resolve(),
        rollback_dir / args.rollback_artifact.resolve().name,
    )
    rollback_artifact["name"] = f"rollback/{args.rollback_artifact.resolve().name}"
    rollback_source_object = write_git_commit_object(
        root,
        prior_manifest["source"]["commit"],
        rollback_dir / "source-commit.object",
        allowed_signers=allowed_signers,
    )
    rollback_source_object["name"] = "rollback/source-commit.object"
    rollback_runtime_object = write_git_commit_object(
        args.rollback_backend_root.resolve(),
        prior_runtime["backend_commit"],
        rollback_dir / "runtime-commit.object",
        allowed_signers=allowed_signers,
    )
    rollback_runtime_object["name"] = "rollback/runtime-commit.object"
    rollback_image = copy_file(
        args.rollback_backend_image.resolve(),
        rollback_dir / args.rollback_backend_image.resolve().name,
    )
    rollback_image["name"] = f"rollback/{args.rollback_backend_image.resolve().name}"
    rollback_host = copy_file(
        args.rollback_host_bundle.resolve(),
        rollback_dir / args.rollback_host_bundle.resolve().name,
    )
    rollback_host["name"] = f"rollback/{args.rollback_host_bundle.resolve().name}"
    rollback_auth_state = copy_file(
        auth_state_path, rollback_dir / auth_state_path.name
    )
    rollback_auth_state["name"] = f"rollback/{auth_state_path.name}"
    auth_signature_path = args.rollback_auth_state_signature.resolve()
    rollback_auth_signature = copy_file(
        auth_signature_path, rollback_dir / auth_signature_path.name
    )
    rollback_auth_signature["name"] = f"rollback/{auth_signature_path.name}"
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
    sbom_path.write_text(
        json.dumps(sbom, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )

    manifest = {
        "schema": "orca.console.release-manifest.v4",
        "created_at": created_at,
        "source": {
            "commit": args.source_commit,
            "commit_signed": True,
            "commit_object": source_object,
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
            "sbom_size_bytes": sbom_path.stat().st_size,
            "package_count": len(packages),
        },
        "trust": {
            "allowed_signers_sha256": trusted_signers_sha256,
            "release_signer_identity": args.release_signer_identity,
        },
        "runtime": {
            "backend_commit": backend_commit,
            "backend_commit_signed": True,
            "backend_commit_object": runtime_object,
            "backend_image": current_image,
            "host_bundle": current_host,
        },
        "auth_transition": {
            "contract": transition_output.name,
            "contract_sha256": sha256(transition_output),
            "schema": "orca.native-auth.transition.v1",
        },
        "rollback": {
            "release_ref": f"orca-console:{prior_manifest['source']['commit']}",
            "manifest": rollback_manifest,
            "manifest_signature": rollback_signature,
            "source_commit": prior_manifest["source"]["commit"],
            "source_commit_signed": True,
            "source_commit_object": rollback_source_object,
            "artifact": rollback_artifact,
            "sbom": rollback_sbom,
            "backend_commit": prior_runtime["backend_commit"],
            "backend_commit_signed": True,
            "backend_commit_object": rollback_runtime_object,
            "backend_image": rollback_image,
            "host_bundle": rollback_host,
            "auth_state": {
                **rollback_auth_state,
                "signature": rollback_auth_signature,
                "schema": "orca.native-auth.state.v1",
                "active_refresh_family_digest": auth_state[
                    "active_refresh_family_digest"
                ],
            },
            "procedure": "restore only the hash-bound prior app, runtime, host bundle, and non-secret auth-state contract; then rerun compatibility and G1-G10 canaries",
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
