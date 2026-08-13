from __future__ import annotations

import hashlib
import importlib.util
import json
import subprocess
from pathlib import Path

import pytest


SCRIPT = Path(__file__).with_name("generate_release_evidence.py")
SPEC = importlib.util.spec_from_file_location("release_evidence", SCRIPT)
assert SPEC and SPEC.loader
release_evidence = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release_evidence)


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def signed_prior_release(tmp_path: Path) -> tuple[Path, Path, Path, str]:
    private_key = tmp_path / "release-key"
    subprocess.run(
        ["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(private_key)],
        check=True,
    )
    public = (tmp_path / "release-key.pub").read_text().strip()
    allowed = tmp_path / "allowed-signers"
    identity = "orca-release-test"
    allowed.write_text(f"{identity} {public}\n", encoding="utf-8")
    evidence = tmp_path / "prior-evidence"
    evidence.mkdir()
    artifact = tmp_path / "ORCA-Console-prior.zip"
    artifact.write_bytes(b"verified prior app")
    sbom = evidence / "sbom.spdx.json"
    sbom.write_text('{"spdxVersion":"SPDX-2.3"}\n', encoding="utf-8")
    manifest = evidence / "manifest.json"
    manifest.write_text(json.dumps({
        "schema": "orca.console.release-manifest.v2",
        "source": {"commit": "1" * 40, "commit_signed": True, "dirty": False},
        "artifact": {"name": artifact.name, "sha256": digest(artifact), "size_bytes": artifact.stat().st_size},
        "dependencies": {"sbom": sbom.name, "sbom_sha256": digest(sbom)},
        "runtime": {
            "backend_commit": "2" * 40,
            "backend_image_digest": f"sha256:{'3' * 64}",
            "host_bundle_sha256": "4" * 64,
        },
    }, sort_keys=True), encoding="utf-8")
    subprocess.run(
        ["ssh-keygen", "-Y", "sign", "-n", "orca-release", "-f", str(private_key), str(manifest)],
        check=True,
        stdout=subprocess.PIPE,
    )
    return evidence, artifact, allowed, identity


def test_prior_release_resolves_signed_manifest_artifact_and_sbom(tmp_path: Path) -> None:
    evidence, artifact, allowed, identity = signed_prior_release(tmp_path)

    verified = release_evidence.verify_prior_release(
        evidence_dir=evidence,
        artifact=artifact,
        allowed_signers=allowed,
        signer_identity=identity,
    )

    assert verified["manifest"]["artifact"]["sha256"] == digest(artifact)
    assert verified["manifest_sha256"] == digest(evidence / "manifest.json")


def test_prior_release_rejects_tampered_artifact(tmp_path: Path) -> None:
    evidence, artifact, allowed, identity = signed_prior_release(tmp_path)
    artifact.write_bytes(b"tampered prior app")

    with pytest.raises(ValueError, match="prior artifact"):
        release_evidence.verify_prior_release(
            evidence_dir=evidence,
            artifact=artifact,
            allowed_signers=allowed,
            signer_identity=identity,
        )


def test_auth_transition_contract_requires_revocation_on_downgrade(tmp_path: Path) -> None:
    contract = tmp_path / "transition.json"
    contract.write_text(json.dumps({
        "schema": "orca.native-auth.transition.v1",
        "migration_revision": "20260813_native_device_proof",
        "upgrade_action": "require_device_key_proof_for_native_refresh_and_api_requests",
        "rollback_action": "revoke_all_refresh_families_before_schema_downgrade",
        "rollback_preserves_sessions": False,
    }), encoding="utf-8")

    assert release_evidence.verify_auth_transition_contract(contract)["rollback_preserves_sessions"] is False

    payload = json.loads(contract.read_text())
    payload["rollback_preserves_sessions"] = True
    contract.write_text(json.dumps(payload), encoding="utf-8")
    with pytest.raises(ValueError, match="transition contract"):
        release_evidence.verify_auth_transition_contract(contract)


def test_source_commit_verification_uses_explicit_ssh_signer_registry(tmp_path: Path) -> None:
    repository = tmp_path / "repository"
    repository.mkdir()
    private_key = tmp_path / "commit-key"
    subprocess.run(
        ["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(private_key)],
        check=True,
    )
    identity = "release-test@example.com"
    allowed = tmp_path / "allowed-signers"
    allowed.write_text(
        f"{identity} {(tmp_path / 'commit-key.pub').read_text().strip()}\n",
        encoding="utf-8",
    )
    subprocess.run(["git", "init", "-q", str(repository)], check=True)
    subprocess.run(["git", "-C", str(repository), "config", "user.name", "Release Test"], check=True)
    subprocess.run(["git", "-C", str(repository), "config", "user.email", identity], check=True)
    (repository / "payload.txt").write_text("signed\n", encoding="utf-8")
    subprocess.run(["git", "-C", str(repository), "add", "payload.txt"], check=True)
    subprocess.run([
        "git", "-C", str(repository),
        "-c", "gpg.format=ssh",
        "-c", f"user.signingkey={private_key}",
        "commit", "-q", "-S", "-m", "signed release source",
    ], check=True)
    commit = subprocess.check_output(
        ["git", "-C", str(repository), "rev-parse", "HEAD"],
        text=True,
    ).strip()

    release_evidence.verify_git_commit(repository, commit, allowed_signers=allowed)

    bad_allowed = tmp_path / "bad-allowed-signers"
    bad_allowed.write_text("somebody-else ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\n")
    with pytest.raises(subprocess.CalledProcessError):
        release_evidence.verify_git_commit(repository, commit, allowed_signers=bad_allowed)
