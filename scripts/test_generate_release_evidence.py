from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
GENERATOR = Path(__file__).with_name("generate_release_evidence.py")
VERIFIER = Path(__file__).with_name("verify_release_evidence.py")
SHELL_VERIFIER = Path(__file__).with_name("verify_orca_console_release.sh")


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


release_evidence = load_module("release_evidence", GENERATOR)
release_verifier = load_module("release_verifier", VERIFIER)


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def signed_commit(repository: Path, key: Path, identity: str, content: str) -> str:
    payload = repository / "payload.txt"
    payload.write_text(content, encoding="utf-8")
    subprocess.run(["git", "-C", str(repository), "add", payload.name], check=True)
    subprocess.run(
        [
            "git",
            "-C",
            str(repository),
            "-c",
            "gpg.format=ssh",
            "-c",
            f"user.signingkey={key}",
            "commit",
            "-q",
            "-S",
            "-m",
            content.strip(),
        ],
        check=True,
    )
    return subprocess.check_output(
        ["git", "-C", str(repository), "rev-parse", "HEAD"], text=True
    ).strip()


def signed_history(
    tmp_path: Path, name: str, key: Path, identity: str
) -> tuple[Path, str, str]:
    repository = tmp_path / name
    repository.mkdir()
    subprocess.run(["git", "init", "-q", str(repository)], check=True)
    subprocess.run(
        ["git", "-C", str(repository), "config", "user.name", "Release Test"],
        check=True,
    )
    subprocess.run(
        ["git", "-C", str(repository), "config", "user.email", identity],
        check=True,
    )
    prior = signed_commit(repository, key, identity, f"{name} prior\n")
    current = signed_commit(repository, key, identity, f"{name} current\n")
    return repository, prior, current


def sign(path: Path, key: Path, namespace: str) -> Path:
    subprocess.run(
        ["ssh-keygen", "-Y", "sign", "-n", namespace, "-f", str(key), str(path)],
        check=True,
        capture_output=True,
    )
    return path.with_name(path.name + ".sig")


def build_bundle(tmp_path: Path) -> dict[str, object]:
    key = tmp_path / "release-key"
    subprocess.run(
        ["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(key)],
        check=True,
    )
    identity = "orca-release-test@example.com"
    allowed = tmp_path / "allowed-signers"
    allowed.write_text(
        f"{identity} {(tmp_path / 'release-key.pub').read_text().strip()}\n",
        encoding="utf-8",
    )
    source, prior_source, current_source = signed_history(
        tmp_path, "source", key, identity
    )
    runtime, prior_runtime, current_runtime = signed_history(
        tmp_path, "runtime", key, identity
    )

    prior_artifact = tmp_path / "ORCA-Console-prior.zip"
    prior_artifact.write_bytes(b"verified prior app")
    prior_image = tmp_path / "prior-runtime-image.tar"
    prior_image.write_bytes(b"verified prior runtime image")
    prior_host = tmp_path / "prior-host-bundle.tar"
    prior_host.write_bytes(b"verified prior host bundle")
    prior_evidence = tmp_path / "prior-evidence"
    prior_evidence.mkdir()
    prior_sbom = prior_evidence / "sbom.spdx.json"
    prior_sbom.write_text('{"spdxVersion":"SPDX-2.3"}\n', encoding="utf-8")
    prior_manifest = prior_evidence / "manifest.json"
    prior_manifest.write_text(
        json.dumps(
            {
                "schema": "orca.console.release-manifest.v3",
                "source": {
                    "commit": prior_source,
                    "commit_signed": True,
                    "dirty": False,
                },
                "artifact": {
                    "name": prior_artifact.name,
                    "sha256": digest(prior_artifact),
                    "size_bytes": prior_artifact.stat().st_size,
                },
                "dependencies": {
                    "sbom": prior_sbom.name,
                    "sbom_sha256": digest(prior_sbom),
                },
                "runtime": {
                    "backend_commit": prior_runtime,
                    "backend_image_digest": f"sha256:{digest(prior_image)}",
                    "host_bundle_sha256": digest(prior_host),
                },
            },
            sort_keys=True,
        ),
        encoding="utf-8",
    )
    sign(prior_manifest, key, "orca-release")

    family_hashes = ["a" * 64, "b" * 64]
    auth_state = tmp_path / "rollback-auth-state.json"
    auth_state.write_text(
        json.dumps(
            {
                "schema": "orca.native-auth.state.v1",
                "runtime_commit": prior_runtime,
                "native_refresh_policy": "legacy",
                "active_refresh_families": len(family_hashes),
                "active_refresh_family_hashes": family_hashes,
                "active_refresh_family_digest": release_evidence.token_family_digest(
                    family_hashes
                ),
            },
            sort_keys=True,
        ),
        encoding="utf-8",
    )
    auth_signature = sign(auth_state, key, "orca-auth-state")
    transition = tmp_path / "transition.json"
    transition.write_text(
        (ROOT / "release/native-auth-transition-v1.json").read_text(encoding="utf-8"),
        encoding="utf-8",
    )
    artifact = tmp_path / "ORCA-Console-current.zip"
    artifact.write_bytes(b"verified current app")
    current_image = tmp_path / "current-runtime-image.tar"
    current_image.write_bytes(b"verified current runtime image")
    current_host = tmp_path / "current-host-bundle.tar"
    current_host.write_bytes(b"verified current host bundle")
    output = tmp_path / "current-evidence"
    trusted_hash = digest(allowed)

    subprocess.run(
        [
            "python3",
            str(GENERATOR),
            "--root",
            str(source),
            "--artifact",
            str(artifact),
            "--source-commit",
            current_source,
            "--backend-commit",
            current_runtime,
            "--backend-root",
            str(runtime),
            "--backend-image",
            str(current_image),
            "--host-bundle",
            str(current_host),
            "--auth-transition-contract",
            str(transition),
            "--rollback-evidence-dir",
            str(prior_evidence),
            "--rollback-artifact",
            str(prior_artifact),
            "--rollback-backend-root",
            str(runtime),
            "--rollback-backend-image",
            str(prior_image),
            "--rollback-host-bundle",
            str(prior_host),
            "--rollback-auth-state-contract",
            str(auth_state),
            "--rollback-auth-state-signature",
            str(auth_signature),
            "--release-allowed-signers",
            str(allowed),
            "--trusted-allowed-signers-sha256",
            trusted_hash,
            "--release-signer-identity",
            identity,
            "--output-dir",
            str(output),
        ],
        check=True,
        capture_output=True,
    )
    sign(output / "manifest.json", key, "orca-release")
    return {
        "artifact": artifact,
        "allowed": allowed,
        "identity": identity,
        "output": output,
        "trusted_hash": trusted_hash,
    }


def verify(bundle: dict[str, object]) -> None:
    release_verifier.verify_bundle(
        Path(bundle["output"]),
        Path(bundle["artifact"]),
        allowed_signers=Path(bundle["allowed"]),
        trusted_allowed_signers_sha256=str(bundle["trusted_hash"]),
        signer_identity=str(bundle["identity"]),
    )


def verify_with_public_shell(bundle: dict[str, object]) -> subprocess.CompletedProcess[str]:
    env = {
        **os.environ,
        "RELEASE_ALLOWED_SIGNERS": str(bundle["allowed"]),
        "TRUSTED_ALLOWED_SIGNERS_SHA256": str(bundle["trusted_hash"]),
        "RELEASE_SIGNER_IDENTITY": str(bundle["identity"]),
    }
    return subprocess.run(
        [
            "bash",
            str(SHELL_VERIFIER),
            str(bundle["output"]),
            str(bundle["artifact"]),
        ],
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )


def test_release_bundle_is_self_contained_and_independently_verifiable(
    tmp_path: Path,
) -> None:
    bundle = build_bundle(tmp_path)

    verify(bundle)

    output = Path(bundle["output"])
    assert (output / "source-commit.object").is_file()
    assert (output / "runtime/current-runtime-image.tar").is_file()
    assert (output / "rollback/runtime-commit.object").is_file()
    assert (output / "rollback/rollback-auth-state.json.sig").is_file()


def test_public_shell_verifier_executes_complete_bundle_contract(tmp_path: Path) -> None:
    bundle = build_bundle(tmp_path)

    result = verify_with_public_shell(bundle)

    assert result.returncode == 0, result.stderr
    assert "release evidence verified" in result.stdout


def test_public_shell_verifier_rejects_tampered_signed_manifest(tmp_path: Path) -> None:
    bundle = build_bundle(tmp_path)
    manifest = Path(bundle["output"]) / "manifest.json"
    manifest.write_bytes(manifest.read_bytes() + b"\n")

    result = verify_with_public_shell(bundle)

    assert result.returncode != 0


@pytest.mark.parametrize(
    "relative_path",
    [
        "runtime/current-runtime-image.tar",
        "runtime/current-host-bundle.tar",
        "rollback/prior-runtime-image.tar",
        "rollback/prior-host-bundle.tar",
        "rollback/rollback-auth-state.json",
        "rollback/rollback-auth-state.json.sig",
        "rollback/source-commit.object",
        "rollback/runtime-commit.object",
        "rollback/manifest.json.sig",
    ],
)
def test_release_bundle_rejects_tampered_or_missing_evidence(
    tmp_path: Path, relative_path: str
) -> None:
    bundle = build_bundle(tmp_path)
    target = Path(bundle["output"]) / relative_path
    target.write_bytes(target.read_bytes() + b"tamper")

    with pytest.raises((ValueError, subprocess.CalledProcessError)):
        verify(bundle)


def test_release_bundle_rejects_untrusted_signer_registry(tmp_path: Path) -> None:
    bundle = build_bundle(tmp_path)
    Path(bundle["allowed"]).write_text("untrusted\n", encoding="utf-8")

    with pytest.raises(ValueError, match="external trust hash"):
        verify(bundle)


def test_auth_state_rejects_count_only_contract(tmp_path: Path) -> None:
    contract = tmp_path / "auth-state.json"
    contract.write_text(
        json.dumps(
            {
                "schema": "orca.native-auth.state.v1",
                "runtime_commit": "1" * 40,
                "native_refresh_policy": "legacy",
                "active_refresh_families": 2,
            }
        ),
        encoding="utf-8",
    )

    with pytest.raises(ValueError, match="family hashes"):
        release_evidence.verify_auth_state_contract(contract)


def test_auth_transition_contract_requires_revocation_on_downgrade(
    tmp_path: Path,
) -> None:
    contract = tmp_path / "transition.json"
    contract.write_text(
        json.dumps(
            {
                "schema": "orca.native-auth.transition.v1",
                "migration_revision": "20260813_native_device_proof",
                "upgrade_action": "require_device_key_proof_for_native_refresh_and_api_requests",
                "rollback_action": "revoke_all_refresh_families_before_schema_downgrade",
                "rollback_preserves_sessions": False,
            }
        ),
        encoding="utf-8",
    )

    assert (
        release_evidence.verify_auth_transition_contract(contract)[
            "rollback_preserves_sessions"
        ]
        is False
    )
    payload = json.loads(contract.read_text())
    payload["rollback_preserves_sessions"] = True
    contract.write_text(json.dumps(payload), encoding="utf-8")
    with pytest.raises(ValueError, match="transition contract"):
        release_evidence.verify_auth_transition_contract(contract)


def test_missing_rollback_file_is_rejected(tmp_path: Path) -> None:
    bundle = build_bundle(tmp_path)
    target = Path(bundle["output"]) / "rollback/prior-host-bundle.tar"
    target.unlink()

    with pytest.raises(ValueError, match="missing rollback host bundle"):
        verify(bundle)


def test_bundle_copy_remains_verifiable_without_source_repositories(
    tmp_path: Path,
) -> None:
    bundle = build_bundle(tmp_path)
    copied = tmp_path / "copied-evidence"
    shutil.copytree(Path(bundle["output"]), copied)

    release_verifier.verify_bundle(
        copied,
        Path(bundle["artifact"]),
        allowed_signers=Path(bundle["allowed"]),
        trusted_allowed_signers_sha256=str(bundle["trusted_hash"]),
        signer_identity=str(bundle["identity"]),
    )
