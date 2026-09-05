from __future__ import annotations

import hashlib
import json
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ICON_SET = ROOT / "MacApp/Resources/Assets.xcassets/AppIcon.appiconset"
POD_MASTER = (
    ROOT
    / "Sources/App/Assets.xcassets/AppIcon.appiconset/Icon-1024@1x.png"
)


EXPECTED_PIXELS = {
    "Icon-16.png": 16,
    "Icon-16@2x.png": 32,
    "Icon-32.png": 32,
    "Icon-32@2x.png": 64,
    "Icon-128.png": 128,
    "Icon-128@2x.png": 256,
    "Icon-256.png": 256,
    "Icon-256@2x.png": 512,
    "Icon-512.png": 512,
    "Icon-512@2x.png": 1024,
}


def png_dimensions(path: Path) -> tuple[int, int]:
    data = path.read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    assert data[12:16] == b"IHDR"
    return struct.unpack(">II", data[16:24])


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def test_console_project_compiles_the_app_icon_catalog() -> None:
    project = (ROOT / "MacApp/project.yml").read_text(encoding="utf-8")
    assert "path: Resources/Assets.xcassets" in project
    assert "buildPhase: resources" in project
    assert "ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon" in project


def test_console_app_icon_catalog_is_complete_and_mac_native() -> None:
    manifest = json.loads((ICON_SET / "Contents.json").read_text(encoding="utf-8"))
    images = manifest["images"]
    assert {row["filename"] for row in images} == set(EXPECTED_PIXELS)
    assert all(row["idiom"] == "mac" for row in images)

    for filename, pixels in EXPECTED_PIXELS.items():
        assert png_dimensions(ICON_SET / filename) == (pixels, pixels)


def test_console_and_pod_share_the_same_orca_master_mark() -> None:
    assert sha256(ICON_SET / "Icon-512@2x.png") == sha256(POD_MASTER)
