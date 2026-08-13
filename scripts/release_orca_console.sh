#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to an xcrun notarytool keychain profile}"
: "${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION to the exact Developer ID Application identity}"
: "${DEVELOPER_ID_PROFILE:?Set DEVELOPER_ID_PROFILE to the Sign in with Apple Developer ID provisioning profile name}"
: "${RELEASE_SIGNING_KEY:?Set RELEASE_SIGNING_KEY to the dedicated SSH manifest-signing private key}"
: "${ORCA_BACKEND_COMMIT:?Set ORCA_BACKEND_COMMIT to the exact runtime commit}"
: "${ORCA_BACKEND_ROOT:?Set ORCA_BACKEND_ROOT to the runtime Git checkout}"
: "${ORCA_BACKEND_IMAGE:?Set ORCA_BACKEND_IMAGE to the exact runtime image artifact}"
: "${HOST_BUNDLE:?Set HOST_BUNDLE to the exact host bundle artifact}"
: "${ROLLBACK_BACKEND_ROOT:?Set ROLLBACK_BACKEND_ROOT to the prior runtime Git checkout}"
: "${ROLLBACK_BACKEND_IMAGE:?Set ROLLBACK_BACKEND_IMAGE to the exact prior runtime image}"
: "${ROLLBACK_HOST_BUNDLE:?Set ROLLBACK_HOST_BUNDLE to the exact prior host bundle}"
: "${ROLLBACK_AUTH_STATE_CONTRACT:?Set ROLLBACK_AUTH_STATE_CONTRACT to the signed prior auth-state contract}"
: "${ROLLBACK_AUTH_STATE_SIGNATURE:?Set ROLLBACK_AUTH_STATE_SIGNATURE to the prior auth-state signature}"
: "${RELEASE_ALLOWED_SIGNERS:?Set RELEASE_ALLOWED_SIGNERS to the approved signer registry}"
: "${TRUSTED_ALLOWED_SIGNERS_SHA256:?Set TRUSTED_ALLOWED_SIGNERS_SHA256 from the external trust registry}"
: "${RELEASE_SIGNER_IDENTITY:?Set RELEASE_SIGNER_IDENTITY to the manifest signer identity}"

INSTALL_MODE="${INSTALL_MODE:-upgrade}"
case "$INSTALL_MODE" in
  upgrade)
    : "${ROLLBACK_EVIDENCE_DIR:?Set ROLLBACK_EVIDENCE_DIR to the signed prior evidence directory}"
    : "${ROLLBACK_ARTIFACT:?Set ROLLBACK_ARTIFACT to the exact prior app artifact}"
    ;;
  initial-install)
    if [[ -e "/Applications/ORCA Console.app" || -L "/Applications/ORCA Console.app" ]]; then
      echo "release refused: initial-install target already exists" >&2
      exit 2
    fi
    ;;
  *)
    echo "release refused: INSTALL_MODE must be upgrade or initial-install" >&2
    exit 2
    ;;
esac

[[ "$ORCA_BACKEND_COMMIT" =~ ^[0-9a-f]{40}$ ]] || {
  echo "release refused: ORCA_BACKEND_COMMIT must be a full git SHA" >&2
  exit 2
}
[[ "$TRUSTED_ALLOWED_SIGNERS_SHA256" =~ ^[0-9a-f]{64}$ ]] || {
  echo "release refused: TRUSTED_ALLOWED_SIGNERS_SHA256 must be 64 lowercase hex characters" >&2
  exit 2
}
if [[ "$INSTALL_MODE" == "upgrade" ]] && [[ ! -f "$ROLLBACK_EVIDENCE_DIR/manifest.json" || ! -f "$ROLLBACK_EVIDENCE_DIR/manifest.json.sig" || ! -f "$ROLLBACK_ARTIFACT" ]]; then
  echo "release refused: signed prior app evidence is incomplete" >&2
  exit 2
fi
[[ -f "$ORCA_BACKEND_IMAGE" && -f "$HOST_BUNDLE" && -f "$ROLLBACK_BACKEND_IMAGE" && -f "$ROLLBACK_HOST_BUNDLE" && -f "$ROLLBACK_AUTH_STATE_CONTRACT" && -f "$ROLLBACK_AUTH_STATE_SIGNATURE" ]] || {
  echo "release refused: rollback artifact or auth-state evidence is missing" >&2
  exit 2
}

if [[ -n "$(git status --porcelain)" ]]; then
  echo "release refused: source tree is dirty" >&2
  exit 2
fi
source_commit="$(git rev-parse HEAD)"
git \
  -c gpg.format=ssh \
  -c "gpg.ssh.allowedSignersFile=$RELEASE_ALLOWED_SIGNERS" \
  verify-commit "$source_commit" >/dev/null

if ! security find-identity -v -p codesigning | grep -Fq "$DEVELOPER_ID_APPLICATION"; then
  echo "release refused: exact Developer ID Application identity is unavailable" >&2
  exit 2
fi

release_root="${RELEASE_ROOT:-/Volumes/DockerExt/coral-builds/orca-console/releases/$source_commit}"
archive_path="$release_root/ORCA Console.xcarchive"
artifact_path="$release_root/ORCA-Console-$source_commit.zip"
submission_path="$release_root/ORCA-Console-$source_commit-notary-submission.zip"
evidence_dir="$release_root/evidence"
derived_data="${DERIVED_DATA_DIR:-$release_root/DerivedData}"
if [[ -e "$evidence_dir/manifest.json" ]]; then
  echo "release refused: immutable release evidence already exists for $source_commit" >&2
  exit 2
fi
mkdir -p "$release_root" "$evidence_dir" "$derived_data"

xcodebuild archive \
  -project MacApp/OrcaMac.xcodeproj \
  -scheme OrcaMac \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$archive_path" \
  -derivedDataPath "$derived_data" \
  -disableAutomaticPackageResolution \
  -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION" \
  PROVISIONING_PROFILE_SPECIFIER="$DEVELOPER_ID_PROFILE"

app_path="$archive_path/Products/Applications/ORCA Console.app"
codesign --verify --deep --strict --verbose=2 "$app_path"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$submission_path"

xcrun notarytool submit "$submission_path" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$app_path"
xcrun stapler validate "$app_path"
spctl --assess --type execute --verbose=4 "$app_path"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$artifact_path"
rm -f "$submission_path"

rollback_mode_args=()
if [[ "$INSTALL_MODE" == "upgrade" ]]; then
  rollback_mode_args=(
    --rollback-evidence-dir "$ROLLBACK_EVIDENCE_DIR"
    --rollback-artifact "$ROLLBACK_ARTIFACT"
  )
else
  preinstall_state="$release_root/preinstall-state.json"
  rollback_runtime_commit="$(python3 - "$ROLLBACK_AUTH_STATE_CONTRACT" <<'PY'
import json
import sys
from pathlib import Path

print(json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["runtime_commit"])
PY
)"
  python3 scripts/capture_preinstall_state.py \
    --runtime-commit "$rollback_runtime_commit" \
    --backend-image "$ROLLBACK_BACKEND_IMAGE" \
    --host-bundle "$ROLLBACK_HOST_BUNDLE" \
    --output "$preinstall_state"
  ssh-keygen -Y sign \
    -n orca-auth-state \
    -f "$RELEASE_SIGNING_KEY" \
    "$preinstall_state"
  rollback_mode_args=(
    --preinstall-state-contract "$preinstall_state"
    --preinstall-state-signature "$preinstall_state.sig"
  )
fi

python3 scripts/generate_release_evidence.py \
  --root "$root" \
  --artifact "$artifact_path" \
  --source-commit "$source_commit" \
  --backend-commit "$ORCA_BACKEND_COMMIT" \
  --backend-root "$ORCA_BACKEND_ROOT" \
  --backend-image "$ORCA_BACKEND_IMAGE" \
  --host-bundle "$HOST_BUNDLE" \
  --auth-transition-contract "$root/release/native-auth-transition-v1.json" \
  --install-mode "$INSTALL_MODE" \
  "${rollback_mode_args[@]}" \
  --rollback-backend-root "$ROLLBACK_BACKEND_ROOT" \
  --rollback-backend-image "$ROLLBACK_BACKEND_IMAGE" \
  --rollback-host-bundle "$ROLLBACK_HOST_BUNDLE" \
  --rollback-auth-state-contract "$ROLLBACK_AUTH_STATE_CONTRACT" \
  --rollback-auth-state-signature "$ROLLBACK_AUTH_STATE_SIGNATURE" \
  --release-allowed-signers "$RELEASE_ALLOWED_SIGNERS" \
  --trusted-allowed-signers-sha256 "$TRUSTED_ALLOWED_SIGNERS_SHA256" \
  --release-signer-identity "$RELEASE_SIGNER_IDENTITY" \
  --output-dir "$evidence_dir"

ssh-keygen -Y sign \
  -n orca-release \
  -f "$RELEASE_SIGNING_KEY" \
  "$evidence_dir/manifest.json"

scripts/verify_orca_console_release.sh "$evidence_dir" "$artifact_path"

echo "release evidence: $evidence_dir"
