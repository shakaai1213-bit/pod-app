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


ROLLBACK_PROCEDURE = (
    "revoke all native refresh families; remove only a current-release-matching "
    "installed app for initial install or restore the hash-bound prior app for "
    "upgrade; restore the exact rollback runtime and host bundle; then rerun "
    "compatibility and G1-G10 canaries"
)


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
    require_signature: bool = True,
) -> dict[str, Any]:
    if require_signature:
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


def require_utc_timestamp(value: Any, *, label: str) -> datetime:
    if not isinstance(value, str) or not value.endswith("Z"):
        raise ValueError(f"invalid {label}")
    try:
        return datetime.fromisoformat(value.removesuffix("Z") + "+00:00")
    except ValueError as exc:
        raise ValueError(f"invalid {label}") from exc


def verify_auth_state_contract(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("schema") != "orca.native-auth.state.v1":
        raise ValueError("unsupported rollback auth-state contract")
    require_commit(payload.get("runtime_commit"), label="auth-state runtime commit")
    if payload.get("native_refresh_policy") not in {"legacy", "device-key-bound"}:
        raise ValueError("invalid native refresh policy")
    runtime_host_id = payload.get("runtime_host_id")
    if not isinstance(runtime_host_id, str) or re.fullmatch(
        r"[A-Za-z0-9._-]{1,255}", runtime_host_id
    ) is None:
        raise ValueError("invalid auth-state runtime host identifier")
    require_utc_timestamp(payload.get("captured_at"), label="auth-state capture time")
    if (
        type(payload.get("active_refresh_families")) is not int
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


def verify_preinstall_state_contract(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    expected_keys = {
        "app_bundle_id",
        "app_host_id",
        "app_present",
        "auth_state_sha256",
        "backend_image_sha256",
        "host_bundle_sha256",
        "install_path",
        "observed_at",
        "runtime_commit",
        "runtime_commit_trust",
        "runtime_host_id",
        "runtime_source_sha256",
        "schema",
    }
    if set(payload) != expected_keys:
        raise ValueError("invalid preinstall-state fields")
    if payload.get("schema") != "orca.console.preinstall-state.v1":
        raise ValueError("unsupported preinstall-state contract")
    if payload.get("app_bundle_id") != "com.orcamc.mac":
        raise ValueError("invalid preinstall app bundle identifier")
    if payload.get("install_path") != "/Applications/ORCA Console.app":
        raise ValueError("invalid preinstall app target")
    if payload.get("app_present") is not False:
        raise ValueError("first-install target must be absent")
    for key in ("app_host_id", "runtime_host_id"):
        host_id = payload.get(key)
        if not isinstance(host_id, str) or re.fullmatch(
            r"[A-Za-z0-9._-]{1,255}", host_id
        ) is None:
            raise ValueError(f"invalid preinstall {key.replace('_', ' ')}")
    require_utc_timestamp(
        payload.get("observed_at"), label="preinstall observation time"
    )
    require_commit(payload.get("runtime_commit"), label="preinstall runtime commit")
    if payload.get("runtime_commit_trust") not in {
        "git-ssh-signed",
        "preinstall-attested-legacy",
    }:
        raise ValueError("invalid preinstall runtime commit trust")
    require_digest(
        payload.get("runtime_source_sha256"), label="preinstall runtime source"
    )
    require_digest(payload.get("auth_state_sha256"), label="preinstall auth state")
    require_digest(
        payload.get("backend_image_sha256"), label="preinstall backend image"
    )
    require_digest(payload.get("host_bundle_sha256"), label="preinstall host bundle")
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
        "orca.console.release-manifest.v5",
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
    parser.add_argument(
        "--install-mode", choices=("upgrade", "initial-install"), default="upgrade"
    )
    parser.add_argument("--rollback-evidence-dir", type=Path)
    parser.add_argument("--rollback-artifact", type=Path)
    parser.add_argument("--rollback-backend-root", type=Path, required=True)
    parser.add_argument("--rollback-backend-source", type=Path)
    parser.add_argument("--rollback-backend-image", type=Path, required=True)
    parser.add_argument("--rollback-host-bundle", type=Path, required=True)
    parser.add_argument("--rollback-auth-state-contract", type=Path, required=True)
    parser.add_argument("--rollback-auth-state-signature", type=Path, required=True)
    parser.add_argument("--preinstall-state-contract", type=Path)
    parser.add_argument("--preinstall-state-signature", type=Path)
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
    if args.install_mode == "upgrade":
        if args.rollback_evidence_dir is None or args.rollback_artifact is None:
            raise SystemExit(
                "release evidence refused: upgrade requires prior release evidence and artifact"
            )
        if (
            args.preinstall_state_contract is not None
            or args.preinstall_state_signature is not None
        ):
            raise SystemExit(
                "release evidence refused: upgrade cannot use first-install state"
            )
    else:
        if (
            args.preinstall_state_contract is None
            or args.preinstall_state_signature is None
            or args.rollback_backend_source is None
        ):
            raise SystemExit(
                "release evidence refused: initial install requires signed preinstall state and rollback source"
            )
        if args.rollback_evidence_dir is not None or args.rollback_artifact is not None:
            raise SystemExit(
                "release evidence refused: initial install cannot claim a prior app release"
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
    auth_captured_at = require_utc_timestamp(
        auth_state["captured_at"], label="auth-state capture time"
    )
    auth_state_age = datetime.now(timezone.utc) - auth_captured_at
    if auth_state_age.total_seconds() < -60 or auth_state_age.total_seconds() > 900:
        raise SystemExit(
            "release evidence refused: rollback auth state is stale or future-dated"
        )
    rollback_backend_root = args.rollback_backend_root.resolve()
    rollback_backend_source = (
        args.rollback_backend_source.resolve()
        if args.rollback_backend_source is not None
        else None
    )
    rollback_backend_image = args.rollback_backend_image.resolve()
    rollback_host_bundle = args.rollback_host_bundle.resolve()
    rollback_paths = [rollback_backend_image, rollback_host_bundle]
    if rollback_backend_source is not None:
        rollback_paths.append(rollback_backend_source)
    for path in rollback_paths:
        if not path.is_file():
            raise SystemExit(
                f"release evidence refused: rollback runtime artifact is missing: {path}"
            )
    rollback_backend_commit = auth_state["runtime_commit"]
    prior: dict[str, Any] | None = None
    prior_manifest: dict[str, Any] | None = None
    preinstall_state: dict[str, Any] | None = None
    if args.install_mode == "upgrade":
        try:
            verify_git_commit(
                rollback_backend_root,
                rollback_backend_commit,
                allowed_signers=allowed_signers,
            )
        except subprocess.CalledProcessError:
            raise SystemExit(
                "release evidence refused: rollback backend commit signature is not verified"
            )
        prior = verify_prior_release(
            evidence_dir=args.rollback_evidence_dir.resolve(),
            artifact=args.rollback_artifact.resolve(),
            source_root=root,
            backend_root=rollback_backend_root,
            backend_image=rollback_backend_image,
            host_bundle=rollback_host_bundle,
            allowed_signers=allowed_signers,
            signer_identity=args.release_signer_identity,
        )
        prior_manifest = prior["manifest"]
        if rollback_backend_commit != prior_manifest["runtime"]["backend_commit"]:
            raise SystemExit(
                "release evidence refused: rollback auth state does not match prior runtime"
            )
    else:
        preinstall_path = args.preinstall_state_contract.resolve()
        verify_signature(
            preinstall_path,
            signature=args.preinstall_state_signature.resolve(),
            allowed_signers=allowed_signers,
            signer_identity=args.release_signer_identity,
            namespace="orca-auth-state",
        )
        preinstall_state = verify_preinstall_state_contract(preinstall_path)
        observed_at = datetime.fromisoformat(
            preinstall_state["observed_at"].removesuffix("Z") + "+00:00"
        )
        observation_age = datetime.now(timezone.utc) - observed_at
        if observation_age.total_seconds() < -60 or observation_age.total_seconds() > 900:
            raise SystemExit(
                "release evidence refused: preinstall observation is stale or future-dated"
            )
        if preinstall_state["runtime_commit"] != rollback_backend_commit:
            raise SystemExit(
                "release evidence refused: preinstall state does not match rollback runtime"
            )
        if preinstall_state["runtime_host_id"] != auth_state["runtime_host_id"]:
            raise SystemExit(
                "release evidence refused: preinstall state does not match auth-state host"
            )
        auth_observation_age = observed_at - auth_captured_at
        if (
            auth_observation_age.total_seconds() < -60
            or auth_observation_age.total_seconds() > 900
        ):
            raise SystemExit(
                "release evidence refused: auth state is outside the preinstall observation window"
            )
        commit_trust = preinstall_state["runtime_commit_trust"]
        try:
            verify_git_commit(
                rollback_backend_root,
                rollback_backend_commit,
                allowed_signers=allowed_signers,
            )
            rollback_commit_is_signed = True
        except subprocess.CalledProcessError:
            rollback_commit_is_signed = False
        if commit_trust == "git-ssh-signed" and not rollback_commit_is_signed:
            raise SystemExit(
                "release evidence refused: preinstall state claims an unsigned rollback commit is signed"
            )
        if commit_trust == "preinstall-attested-legacy" and rollback_commit_is_signed:
            raise SystemExit(
                "release evidence refused: signed rollback commit cannot use legacy attestation"
            )
        assert rollback_backend_source is not None
        if preinstall_state["runtime_source_sha256"] != sha256(
            rollback_backend_source
        ):
            raise SystemExit(
                "release evidence refused: preinstall state does not match rollback source"
            )
        if preinstall_state["backend_image_sha256"] != sha256(rollback_backend_image):
            raise SystemExit(
                "release evidence refused: preinstall state does not match rollback image"
            )
        if preinstall_state["host_bundle_sha256"] != sha256(rollback_host_bundle):
            raise SystemExit(
                "release evidence refused: preinstall state does not match rollback host bundle"
            )
        if preinstall_state["auth_state_sha256"] != sha256(auth_state_path):
            raise SystemExit(
                "release evidence refused: preinstall state does not match rollback auth state"
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
    rollback_runtime_object = write_git_commit_object(
        rollback_backend_root,
        rollback_backend_commit,
        rollback_dir / "runtime-commit.object",
        allowed_signers=allowed_signers,
        require_signature=(
            args.install_mode == "upgrade"
            or preinstall_state["runtime_commit_trust"] == "git-ssh-signed"
        ),
    )
    rollback_runtime_object["name"] = "rollback/runtime-commit.object"
    rollback_image = copy_file(
        rollback_backend_image,
        rollback_dir / rollback_backend_image.name,
    )
    rollback_image["name"] = f"rollback/{rollback_backend_image.name}"
    rollback_host = copy_file(
        rollback_host_bundle,
        rollback_dir / rollback_host_bundle.name,
    )
    rollback_host["name"] = f"rollback/{rollback_host_bundle.name}"
    rollback_auth_state = copy_file(
        auth_state_path, rollback_dir / auth_state_path.name
    )
    rollback_auth_state["name"] = f"rollback/{auth_state_path.name}"
    auth_signature_path = args.rollback_auth_state_signature.resolve()
    rollback_auth_signature = copy_file(
        auth_signature_path, rollback_dir / auth_signature_path.name
    )
    rollback_auth_signature["name"] = f"rollback/{auth_signature_path.name}"
    if args.install_mode == "upgrade":
        assert prior is not None and prior_manifest is not None
        rollback_manifest = copy_file(
            prior["manifest_path"], rollback_dir / "manifest.json"
        )
        rollback_manifest["name"] = "rollback/manifest.json"
        rollback_signature = copy_file(
            prior["signature_path"], rollback_dir / "manifest.json.sig"
        )
        rollback_signature["name"] = "rollback/manifest.json.sig"
        rollback_sbom = copy_file(
            prior["sbom_path"], rollback_dir / "sbom.spdx.json"
        )
        rollback_sbom["name"] = "rollback/sbom.spdx.json"
        rollback_artifact = copy_file(
            args.rollback_artifact.resolve(),
            rollback_dir / args.rollback_artifact.resolve().name,
        )
        rollback_artifact["name"] = (
            f"rollback/{args.rollback_artifact.resolve().name}"
        )
        rollback_source_object = write_git_commit_object(
            root,
            prior_manifest["source"]["commit"],
            rollback_dir / "source-commit.object",
            allowed_signers=allowed_signers,
        )
        rollback_source_object["name"] = "rollback/source-commit.object"
        rollback_contract = {
            "mode": "upgrade",
            "release_ref": f"orca-console:{prior_manifest['source']['commit']}",
            "manifest": rollback_manifest,
            "manifest_signature": rollback_signature,
            "source_commit": prior_manifest["source"]["commit"],
            "source_commit_signed": True,
            "source_commit_object": rollback_source_object,
            "artifact": rollback_artifact,
            "sbom": rollback_sbom,
        }
    else:
        assert preinstall_state is not None
        preinstall_path = args.preinstall_state_contract.resolve()
        copied_preinstall = copy_file(
            preinstall_path, rollback_dir / "preinstall-state.json"
        )
        copied_preinstall["name"] = "rollback/preinstall-state.json"
        copied_preinstall_signature = copy_file(
            args.preinstall_state_signature.resolve(),
            rollback_dir / "preinstall-state.json.sig",
        )
        copied_preinstall_signature["name"] = (
            "rollback/preinstall-state.json.sig"
        )
        rollback_source = copy_file(
            rollback_backend_source,
            rollback_dir / rollback_backend_source.name,
        )
        rollback_source["name"] = f"rollback/{rollback_backend_source.name}"
        rollback_contract = {
            "mode": "initial-install",
            "release_ref": "orca-console:first-install",
            "preinstall_state": {
                **copied_preinstall,
                "signature": copied_preinstall_signature,
                "schema": "orca.console.preinstall-state.v1",
            },
            "app": {
                "bundle_id": preinstall_state["app_bundle_id"],
                "install_path": preinstall_state["install_path"],
                "prior_present": False,
                "rollback_action": "remove_only_if_installed_app_matches_current_release_identity",
            },
            "backend_commit_trust": preinstall_state["runtime_commit_trust"],
            "backend_source": rollback_source,
        }
    rollback_contract.update(
        {
            "backend_commit": rollback_backend_commit,
            "backend_commit_signed": (
                args.install_mode == "upgrade"
                or preinstall_state["runtime_commit_trust"] == "git-ssh-signed"
            ),
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
            "procedure": ROLLBACK_PROCEDURE,
        }
    )
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
        "schema": "orca.console.release-manifest.v5",
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
        "rollback": rollback_contract,
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
