#!/usr/bin/env bash
set -euo pipefail

: "${RELEASE_ALLOWED_SIGNERS:?Set RELEASE_ALLOWED_SIGNERS to the approved signer registry}"
: "${RELEASE_SIGNER_IDENTITY:?Set RELEASE_SIGNER_IDENTITY to the manifest signer identity}"

evidence_dir="${1:?Usage: verify_orca_console_release.sh <evidence-dir> <artifact>}"
artifact="${2:?Usage: verify_orca_console_release.sh <evidence-dir> <artifact>}"
manifest="$evidence_dir/manifest.json"
signature="$manifest.sig"

[[ -f "$manifest" && -f "$signature" && -f "$evidence_dir/sbom.spdx.json" ]] || {
  echo "release verification failed: evidence bundle is incomplete" >&2
  exit 2
}

ssh-keygen -Y verify \
  -n orca-release \
  -f "$RELEASE_ALLOWED_SIGNERS" \
  -I "$RELEASE_SIGNER_IDENTITY" \
  -s "$signature" \
  < "$manifest"

python3 - "$manifest" "$artifact" <<'PY'
import json
import re
import sys
from pathlib import Path

manifest = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
artifact = Path(sys.argv[2])
if manifest.get("schema") != "orca.console.release-manifest.v1":
    raise SystemExit("release verification failed: unsupported manifest schema")
source = manifest.get("source") or {}
if not re.fullmatch(r"[0-9a-f]{40}", str(source.get("commit") or "")):
    raise SystemExit("release verification failed: invalid source commit")
if source.get("commit_signed") is not True or source.get("dirty") is not False:
    raise SystemExit("release verification failed: source integrity flags are invalid")
runtime = manifest.get("runtime") or {}
if not re.fullmatch(r"[0-9a-f]{40}", str(runtime.get("backend_commit") or "")):
    raise SystemExit("release verification failed: invalid backend commit")
if not re.fullmatch(r"sha256:[0-9a-f]{64}", str(runtime.get("backend_image_digest") or "")):
    raise SystemExit("release verification failed: invalid backend image digest")
if not re.fullmatch(r"[0-9a-f]{64}", str(runtime.get("host_bundle_sha256") or "")):
    raise SystemExit("release verification failed: invalid host bundle digest")
if not str((manifest.get("rollback") or {}).get("release_ref") or "").strip():
    raise SystemExit("release verification failed: rollback release is missing")
artifact_row = manifest.get("artifact") or {}
if artifact_row.get("name") != artifact.name:
    raise SystemExit("release verification failed: artifact name mismatch")
if artifact_row.get("size_bytes") != artifact.stat().st_size:
    raise SystemExit("release verification failed: artifact size mismatch")
PY

expected_artifact="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["artifact"]["sha256"])' "$manifest")"
actual_artifact="$(shasum -a 256 "$artifact" | awk '{print $1}')"
[[ "$expected_artifact" == "$actual_artifact" ]]

expected_sbom="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["dependencies"]["sbom_sha256"])' "$manifest")"
actual_sbom="$(shasum -a 256 "$evidence_dir/sbom.spdx.json" | awk '{print $1}')"
[[ "$expected_sbom" == "$actual_sbom" ]]

echo "ORCA Console release evidence verified"
