from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import shutil
import subprocess
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
GENERATOR = Path(__file__).with_name("generate_release_evidence.py")
VERIFIER = Path(__file__).with_name("verify_release_evidence.py")
SHELL_VERIFIER = Path(__file__).with_name("verify_orca_console_release.sh")
PREINSTALL_CAPTURE = Path(__file__).with_name("capture_preinstall_state.py")
AUTH_STATE_CAPTURE = Path(__file__).with_name("capture_runtime_auth_state.py")


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


def unsigned_commit(repository: Path, content: str) -> str:
    payload = repository / "payload.txt"
    payload.write_text(content, encoding="utf-8")
    subprocess.run(["git", "-C", str(repository), "add", payload.name], check=True)
    subprocess.run(
        ["git", "-C", str(repository), "commit", "-q", "-m", content.strip()],
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


def legacy_runtime_history(
    tmp_path: Path, key: Path, identity: str
) -> tuple[Path, str, str]:
    repository = tmp_path / "runtime"
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
    prior = unsigned_commit(repository, "runtime legacy prior\n")
    current = signed_commit(repository, key, identity, "runtime current\n")
    return repository, prior, current


def sign(path: Path, key: Path, namespace: str) -> Path:
    subprocess.run(
        ["ssh-keygen", "-Y", "sign", "-n", namespace, "-f", str(key), str(path)],
        check=True,
        capture_output=True,
    )
    return path.with_name(path.name + ".sig")


def build_bundle(
    tmp_path: Path,
    *,
    install_mode: str = "upgrade",
    rollback_commit_trust: str = "git-ssh-signed",
    preinstall_overrides: dict[str, object] | None = None,
    auth_state_overrides: dict[str, object] | None = None,
    extra_generator_args: list[str] | None = None,
) -> dict[str, object]:
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
    if rollback_commit_trust == "preinstall-attested-legacy":
        runtime, prior_runtime, current_runtime = legacy_runtime_history(
            tmp_path, key, identity
        )
    else:
        runtime, prior_runtime, current_runtime = signed_history(
            tmp_path, "runtime", key, identity
        )

    prior_artifact = tmp_path / "ORCA-Console-prior.zip"
    prior_artifact.write_bytes(b"verified prior app")
    prior_image = tmp_path / "prior-runtime-image.tar"
    prior_image.write_bytes(b"verified prior runtime image")
    prior_host = tmp_path / "prior-host-bundle.tar"
    prior_host.write_bytes(b"verified prior host bundle")
    prior_source_archive = tmp_path / "prior-runtime-source.tar"
    prior_source_archive.write_bytes(b"verified prior runtime source")
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
    auth_payload = {
        "schema": "orca.native-auth.state.v1",
        "runtime_commit": prior_runtime,
        "runtime_host_id": "release-test-runtime-host",
        "captured_at": datetime.now(timezone.utc)
        .isoformat(timespec="seconds")
        .replace("+00:00", "Z"),
        "native_refresh_policy": "legacy",
        "active_refresh_families": len(family_hashes),
        "active_refresh_family_hashes": family_hashes,
        "active_refresh_family_digest": release_evidence.token_family_digest(
            family_hashes
        ),
    }
    auth_payload.update(auth_state_overrides or {})
    auth_state.write_text(
        json.dumps(auth_payload, sort_keys=True),
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

    preinstall_state = tmp_path / "preinstall-state.json"
    preinstall_payload = {
        "app_bundle_id": "com.orcamc.mac",
        "app_host_id": "release-test-app-host",
        "app_present": False,
        "auth_state_sha256": digest(auth_state),
        "backend_image_sha256": digest(prior_image),
        "host_bundle_sha256": digest(prior_host),
        "install_path": "/Applications/ORCA Console.app",
        "observed_at": datetime.now(timezone.utc)
        .isoformat(timespec="seconds")
        .replace("+00:00", "Z"),
        "runtime_commit": prior_runtime,
        "runtime_commit_trust": rollback_commit_trust,
        "runtime_host_id": "release-test-runtime-host",
        "runtime_source_sha256": digest(prior_source_archive),
        "schema": "orca.console.preinstall-state.v1",
    }
    preinstall_payload.update(preinstall_overrides or {})
    preinstall_state.write_text(
        json.dumps(preinstall_payload, sort_keys=True), encoding="utf-8"
    )
    preinstall_signature = sign(preinstall_state, key, "orca-auth-state")

    command = [
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
        "--install-mode",
        install_mode,
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
    ]
    if install_mode == "upgrade":
        command.extend(
            [
            "--rollback-evidence-dir",
            str(prior_evidence),
            "--rollback-artifact",
            str(prior_artifact),
            ]
        )
    else:
        command.extend(
            [
                "--preinstall-state-contract",
                str(preinstall_state),
                "--preinstall-state-signature",
                str(preinstall_signature),
                "--rollback-backend-source",
                str(prior_source_archive),
            ]
        )
    command.extend(extra_generator_args or [])

    subprocess.run(
        command,
        check=True,
        capture_output=True,
    )
    sign(output / "manifest.json", key, "orca-release")
    return {
        "artifact": artifact,
        "allowed": allowed,
        "identity": identity,
        "key": key,
        "output": output,
        "preinstall_state": preinstall_state,
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


def test_initial_install_bundle_is_self_contained_and_verifiable(
    tmp_path: Path,
) -> None:
    bundle = build_bundle(tmp_path, install_mode="initial-install")

    verify(bundle)

    output = Path(bundle["output"])
    manifest = json.loads((output / "manifest.json").read_text(encoding="utf-8"))
    assert manifest["rollback"]["mode"] == "initial-install"
    assert manifest["rollback"]["app"]["prior_present"] is False
    assert (output / "rollback/preinstall-state.json").is_file()
    assert (output / "rollback/preinstall-state.json.sig").is_file()
    assert not (output / "rollback/manifest.json").exists()
    assert verify_with_public_shell(bundle).returncode == 0


def test_initial_install_accepts_release_attested_legacy_runtime(
    tmp_path: Path,
) -> None:
    bundle = build_bundle(
        tmp_path,
        install_mode="initial-install",
        rollback_commit_trust="preinstall-attested-legacy",
    )

    verify(bundle)

    manifest = json.loads(
        (Path(bundle["output"]) / "manifest.json").read_text(encoding="utf-8")
    )
    rollback = manifest["rollback"]
    assert rollback["backend_commit_signed"] is False
    assert rollback["backend_commit_trust"] == "preinstall-attested-legacy"
    assert verify_with_public_shell(bundle).returncode == 0


def test_initial_install_rejects_signed_runtime_as_legacy(tmp_path: Path) -> None:
    with pytest.raises(subprocess.CalledProcessError):
        build_bundle(
            tmp_path,
            install_mode="initial-install",
            rollback_commit_trust="git-ssh-signed",
            preinstall_overrides={
                "runtime_commit_trust": "preinstall-attested-legacy"
            },
        )


def test_initial_install_rejects_unsigned_runtime_as_git_signed(
    tmp_path: Path,
) -> None:
    with pytest.raises(subprocess.CalledProcessError):
        build_bundle(
            tmp_path,
            install_mode="initial-install",
            rollback_commit_trust="preinstall-attested-legacy",
            preinstall_overrides={"runtime_commit_trust": "git-ssh-signed"},
        )


def test_initial_install_rejects_runtime_source_mismatch(tmp_path: Path) -> None:
    with pytest.raises(subprocess.CalledProcessError):
        build_bundle(
            tmp_path,
            install_mode="initial-install",
            preinstall_overrides={"runtime_source_sha256": "f" * 64},
        )


def test_initial_install_rejects_auth_state_mismatch(tmp_path: Path) -> None:
    with pytest.raises(subprocess.CalledProcessError):
        build_bundle(
            tmp_path,
            install_mode="initial-install",
            preinstall_overrides={"auth_state_sha256": "f" * 64},
        )


def test_initial_install_rejects_auth_state_host_mismatch(tmp_path: Path) -> None:
    with pytest.raises(subprocess.CalledProcessError):
        build_bundle(
            tmp_path,
            install_mode="initial-install",
            preinstall_overrides={"runtime_host_id": "foreign-runtime-host"},
        )


def test_initial_install_rejects_stale_auth_state(tmp_path: Path) -> None:
    stale = (datetime.now(timezone.utc) - timedelta(minutes=16)).isoformat(
        timespec="seconds"
    ).replace("+00:00", "Z")
    with pytest.raises(subprocess.CalledProcessError):
        build_bundle(
            tmp_path,
            install_mode="initial-install",
            auth_state_overrides={"captured_at": stale},
        )


def test_initial_install_rejects_present_app_claim(tmp_path: Path) -> None:
    with pytest.raises(subprocess.CalledProcessError):
        build_bundle(
            tmp_path,
            install_mode="initial-install",
            preinstall_overrides={"app_present": True},
        )


def test_initial_install_rejects_stale_preinstall_state(tmp_path: Path) -> None:
    stale = (datetime.now(timezone.utc) - timedelta(hours=1)).isoformat(
        timespec="seconds"
    ).replace("+00:00", "Z")
    with pytest.raises(subprocess.CalledProcessError):
        build_bundle(
            tmp_path,
            install_mode="initial-install",
            preinstall_overrides={"observed_at": stale},
        )


def test_initial_install_rejects_mixed_prior_release_inputs(tmp_path: Path) -> None:
    extra_artifact = tmp_path / "false-prior.zip"
    extra_artifact.write_bytes(b"not a prior release")
    with pytest.raises(subprocess.CalledProcessError):
        build_bundle(
            tmp_path,
            install_mode="initial-install",
            extra_generator_args=[
                "--rollback-evidence-dir",
                str(tmp_path),
                "--rollback-artifact",
                str(extra_artifact),
            ],
        )


def test_initial_install_verifier_rejects_tampered_preinstall_state(
    tmp_path: Path,
) -> None:
    bundle = build_bundle(tmp_path, install_mode="initial-install")
    preinstall = Path(bundle["output"]) / "rollback/preinstall-state.json"
    preinstall.write_bytes(preinstall.read_bytes() + b"tamper")

    with pytest.raises((ValueError, subprocess.CalledProcessError)):
        verify(bundle)


def test_initial_install_verifier_rejects_tampered_runtime_source(
    tmp_path: Path,
) -> None:
    bundle = build_bundle(tmp_path, install_mode="initial-install")
    source = Path(bundle["output"]) / "rollback/prior-runtime-source.tar"
    source.write_bytes(source.read_bytes() + b"tamper")

    with pytest.raises((ValueError, subprocess.CalledProcessError)):
        verify(bundle)


def test_preinstall_capture_records_absent_target(tmp_path: Path) -> None:
    source = tmp_path / "runtime-source.tar"
    source.write_bytes(b"source")
    auth_state = tmp_path / "auth-state.json"
    auth_state.write_text(
        json.dumps(
            {
                "captured_at": datetime.now(timezone.utc)
                .isoformat(timespec="seconds")
                .replace("+00:00", "Z"),
                "runtime_commit": "a" * 40,
                "runtime_host_id": "runtime-host",
            }
        ),
        encoding="utf-8",
    )
    image = tmp_path / "runtime.tar"
    image.write_bytes(b"runtime")
    host = tmp_path / "host.tar"
    host.write_bytes(b"host")
    target = tmp_path / "ORCA Console.app"
    output = tmp_path / "preinstall.json"

    subprocess.run(
        [
            "python3",
            str(PREINSTALL_CAPTURE),
            "--runtime-commit",
            "a" * 40,
            "--runtime-commit-trust",
            "git-ssh-signed",
            "--runtime-host-id",
            "runtime-host",
            "--runtime-source",
            str(source),
            "--backend-image",
            str(image),
            "--host-bundle",
            str(host),
            "--auth-state-contract",
            str(auth_state),
            "--install-path",
            str(target),
            "--output",
            str(output),
        ],
        check=True,
        capture_output=True,
    )

    payload = json.loads(output.read_text(encoding="utf-8"))
    assert payload["app_present"] is False
    assert payload["backend_image_sha256"] == digest(image)
    assert payload["host_bundle_sha256"] == digest(host)
    assert payload["runtime_source_sha256"] == digest(source)
    assert payload["auth_state_sha256"] == digest(auth_state)


def test_preinstall_capture_refuses_existing_target(tmp_path: Path) -> None:
    source = tmp_path / "runtime-source.tar"
    source.write_bytes(b"source")
    auth_state = tmp_path / "auth-state.json"
    auth_state.write_text(
        json.dumps(
            {
                "captured_at": datetime.now(timezone.utc)
                .isoformat(timespec="seconds")
                .replace("+00:00", "Z"),
                "runtime_commit": "a" * 40,
                "runtime_host_id": "runtime-host",
            }
        ),
        encoding="utf-8",
    )
    image = tmp_path / "runtime.tar"
    image.write_bytes(b"runtime")
    host = tmp_path / "host.tar"
    host.write_bytes(b"host")
    target = tmp_path / "ORCA Console.app"
    target.mkdir()

    result = subprocess.run(
        [
            "python3",
            str(PREINSTALL_CAPTURE),
            "--runtime-commit",
            "a" * 40,
            "--runtime-commit-trust",
            "git-ssh-signed",
            "--runtime-host-id",
            "runtime-host",
            "--runtime-source",
            str(source),
            "--backend-image",
            str(image),
            "--host-bundle",
            str(host),
            "--auth-state-contract",
            str(auth_state),
            "--install-path",
            str(target),
            "--output",
            str(tmp_path / "preinstall.json"),
        ],
        capture_output=True,
        text=True,
    )

    assert result.returncode != 0
    assert "target already exists" in result.stderr


def test_auth_state_capture_hashes_identifiers_without_retaining_them(
    tmp_path: Path,
) -> None:
    output = tmp_path / "auth-state.json"
    subprocess.run(
        [
            "python3",
            str(AUTH_STATE_CAPTURE),
            "--runtime-commit",
            "a" * 40,
            "--runtime-host-id",
            "runtime-host",
            "--native-refresh-policy",
            "legacy",
            "--output",
            str(output),
        ],
        input="family-b\nfamily-a\nfamily-a\n",
        text=True,
        check=True,
        capture_output=True,
    )

    payload = json.loads(output.read_text(encoding="utf-8"))
    expected = sorted(
        {
            hashlib.sha256(value.encode()).hexdigest()
            for value in ("family-a", "family-b")
        }
    )
    assert payload["active_refresh_family_hashes"] == expected
    assert payload["active_refresh_families"] == 2
    assert "family-a" not in output.read_text(encoding="utf-8")
    assert output.stat().st_mode & 0o777 == 0o600


def test_auth_state_capture_supports_empty_active_set(tmp_path: Path) -> None:
    output = tmp_path / "auth-state.json"
    subprocess.run(
        [
            "python3",
            str(AUTH_STATE_CAPTURE),
            "--runtime-commit",
            "a" * 40,
            "--runtime-host-id",
            "runtime-host",
            "--native-refresh-policy",
            "legacy",
            "--output",
            str(output),
        ],
        input="",
        text=True,
        check=True,
        capture_output=True,
    )

    payload = json.loads(output.read_text(encoding="utf-8"))
    assert payload["active_refresh_families"] == 0
    assert payload["active_refresh_family_hashes"] == []
    assert payload["active_refresh_family_digest"] == hashlib.sha256(b"\n").hexdigest()


def test_public_shell_verifier_rejects_tampered_signed_manifest(tmp_path: Path) -> None:
    bundle = build_bundle(tmp_path)
    manifest = Path(bundle["output"]) / "manifest.json"
    manifest.write_bytes(manifest.read_bytes() + b"\n")

    result = verify_with_public_shell(bundle)

    assert result.returncode != 0


def test_public_shell_verifier_rejects_resigned_auth_state_without_policy(
    tmp_path: Path,
) -> None:
    bundle = build_bundle(tmp_path)
    output = Path(bundle["output"])
    key = Path(bundle["key"])
    auth_path = output / "rollback/rollback-auth-state.json"
    auth_state = json.loads(auth_path.read_text(encoding="utf-8"))
    del auth_state["native_refresh_policy"]
    auth_path.write_text(
        json.dumps(auth_state, sort_keys=True),
        encoding="utf-8",
    )
    auth_signature = auth_path.with_name(auth_path.name + ".sig")
    auth_signature.unlink()
    sign(auth_path, key, "orca-auth-state")

    manifest_path = output / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    auth_row = manifest["rollback"]["auth_state"]
    auth_row["sha256"] = digest(auth_path)
    auth_row["size_bytes"] = auth_path.stat().st_size
    auth_row["signature"]["sha256"] = digest(auth_signature)
    auth_row["signature"]["size_bytes"] = auth_signature.stat().st_size
    manifest_path.write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    manifest_signature = manifest_path.with_name(manifest_path.name + ".sig")
    manifest_signature.unlink()
    sign(manifest_path, key, "orca-release")

    result = verify_with_public_shell(bundle)

    assert result.returncode != 0
    assert "invalid native refresh policy" in result.stderr


def test_public_shell_verifier_rejects_resigned_boolean_family_count(
    tmp_path: Path,
) -> None:
    bundle = build_bundle(tmp_path)
    output = Path(bundle["output"])
    key = Path(bundle["key"])
    auth_path = output / "rollback/rollback-auth-state.json"
    auth_state = json.loads(auth_path.read_text(encoding="utf-8"))
    auth_state["active_refresh_families"] = True
    auth_state["active_refresh_family_hashes"] = ["a" * 64]
    auth_state["active_refresh_family_digest"] = release_evidence.token_family_digest(
        auth_state["active_refresh_family_hashes"]
    )
    auth_path.write_text(json.dumps(auth_state, sort_keys=True), encoding="utf-8")
    auth_signature = auth_path.with_name(auth_path.name + ".sig")
    auth_signature.unlink()
    sign(auth_path, key, "orca-auth-state")

    manifest_path = output / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    auth_row = manifest["rollback"]["auth_state"]
    auth_row["sha256"] = digest(auth_path)
    auth_row["size_bytes"] = auth_path.stat().st_size
    auth_row["active_refresh_family_digest"] = auth_state[
        "active_refresh_family_digest"
    ]
    auth_row["signature"]["sha256"] = digest(auth_signature)
    auth_row["signature"]["size_bytes"] = auth_signature.stat().st_size
    manifest_path.write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    manifest_signature = manifest_path.with_name(manifest_path.name + ".sig")
    manifest_signature.unlink()
    sign(manifest_path, key, "orca-release")

    result = verify_with_public_shell(bundle)

    assert result.returncode != 0
    assert "invalid active refresh family count" in result.stderr


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
                "runtime_host_id": "runtime-host",
                "captured_at": datetime.now(timezone.utc)
                .isoformat(timespec="seconds")
                .replace("+00:00", "Z"),
                "native_refresh_policy": "legacy",
                "active_refresh_families": 2,
            }
        ),
        encoding="utf-8",
    )

    with pytest.raises(ValueError, match="family hashes"):
        release_evidence.verify_auth_state_contract(contract)


def test_auth_state_rejects_boolean_family_count(tmp_path: Path) -> None:
    family_hashes = ["a" * 64]
    contract = tmp_path / "auth-state.json"
    contract.write_text(
        json.dumps(
            {
                "schema": "orca.native-auth.state.v1",
                "runtime_commit": "1" * 40,
                "runtime_host_id": "runtime-host",
                "captured_at": datetime.now(timezone.utc)
                .isoformat(timespec="seconds")
                .replace("+00:00", "Z"),
                "native_refresh_policy": "legacy",
                "active_refresh_families": True,
                "active_refresh_family_hashes": family_hashes,
                "active_refresh_family_digest": release_evidence.token_family_digest(
                    family_hashes
                ),
            }
        ),
        encoding="utf-8",
    )

    with pytest.raises(ValueError, match="family count"):
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
