from __future__ import annotations

import importlib.util
import plistlib
from pathlib import Path


SCRIPT = Path(__file__).with_name("audit_orca_console_installations.py")
SPEC = importlib.util.spec_from_file_location("console_install_audit", SCRIPT)
assert SPEC and SPEC.loader
audit = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(audit)


def make_app(
    root: Path,
    name: str = "ORCA Console.app",
    *,
    bundle_id: str = audit.CANONICAL_BUNDLE_ID,
    product_name: str = audit.CANONICAL_PRODUCT_NAME,
) -> Path:
    app = root / name
    contents = app / "Contents"
    executable = contents / "MacOS" / "OrcaMac"
    executable.parent.mkdir(parents=True)
    executable.write_bytes(b"test executable")
    with (contents / "Info.plist").open("wb") as handle:
        plistlib.dump(
            {
                "CFBundleIdentifier": bundle_id,
                "CFBundleDisplayName": product_name,
                "CFBundleExecutable": executable.name,
                "CFBundleVersion": "1",
            },
            handle,
        )
    return app


def inventory(
    tmp_path: Path,
    *,
    mode: str,
    canonical: Path,
) -> dict:
    return audit.build_inventory(
        mode=mode,
        install_roots=[tmp_path / "Applications"],
        loose_roots=[tmp_path / "Desktop", tmp_path / "Downloads"],
        evidence_roots=[tmp_path / "DerivedData"],
        canonical_path=canonical,
        quarantine_root=tmp_path / "quarantine",
    )


def test_initial_install_is_ready_when_only_build_evidence_exists(tmp_path: Path) -> None:
    make_app(tmp_path / "DerivedData" / "Build" / "Products" / "Debug")
    canonical = tmp_path / "Applications" / "ORCA Console.app"
    result = inventory(tmp_path, mode="initial-install", canonical=canonical)
    assert result["ready"] is True
    assert result["counts"] == {
        "canonical_install": 0,
        "installed_duplicate": 0,
        "loose_copy": 0,
        "build_evidence": 1,
    }


def test_initial_install_refuses_existing_canonical_target(tmp_path: Path) -> None:
    canonical = make_app(tmp_path / "Applications")
    result = inventory(tmp_path, mode="initial-install", canonical=canonical)
    assert result["ready"] is False
    assert {row["reason"] for row in result["violations"]} == {
        "initial_install_target_present"
    }


def test_upgrade_requires_exact_canonical_install(tmp_path: Path) -> None:
    canonical = tmp_path / "Applications" / "ORCA Console.app"
    missing = inventory(tmp_path, mode="upgrade", canonical=canonical)
    assert missing["ready"] is False
    assert missing["violations"] == [
        {"path": str(canonical), "reason": "upgrade_target_missing"}
    ]

    make_app(tmp_path / "Applications")
    present = inventory(tmp_path, mode="upgrade", canonical=canonical)
    assert present["ready"] is True
    assert present["counts"]["canonical_install"] == 1


def test_loose_copy_emits_preserve_first_quarantine_plan(tmp_path: Path) -> None:
    canonical = tmp_path / "Applications" / "ORCA Console.app"
    loose = make_app(tmp_path / "Downloads")
    result = inventory(tmp_path, mode="initial-install", canonical=canonical)
    assert result["ready"] is False
    assert result["violations"] == [
        {"path": str(loose), "reason": "loose_copy"}
    ]
    plan = result["quarantine_plan"][0]
    assert plan["source"] == str(loose)
    assert plan["destination"].startswith(str(tmp_path / "quarantine"))
    assert len(plan["preserve_before_move"]["executable_sha256"]) == 64


def test_wrong_or_malformed_identity_fails_closed(tmp_path: Path) -> None:
    canonical = tmp_path / "Applications" / "ORCA Console.app"
    wrong = make_app(
        tmp_path / "Desktop",
        bundle_id="com.example.orca",
        product_name="Orca Copy",
    )
    malformed = tmp_path / "Downloads" / "ORCA Broken.app"
    malformed.mkdir(parents=True)
    result = inventory(tmp_path, mode="initial-install", canonical=canonical)
    reasons = {(row["path"], row["reason"]) for row in result["violations"]}
    assert (str(wrong), "bundle_identity_mismatch") in reasons
    assert (str(wrong), "loose_copy") in reasons
    assert (str(malformed), "malformed_app_bundle") in reasons
    assert (str(malformed), "loose_copy") in reasons


def test_duplicate_install_root_is_not_mistaken_for_canonical(tmp_path: Path) -> None:
    canonical = tmp_path / "Applications" / "ORCA Console.app"
    duplicate = make_app(tmp_path / "Applications", "ORCA.app")
    result = inventory(tmp_path, mode="initial-install", canonical=canonical)
    assert result["ready"] is False
    assert result["counts"]["installed_duplicate"] == 1
    assert result["violations"] == [
        {"path": str(duplicate), "reason": "installed_duplicate"}
    ]
