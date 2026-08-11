#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to an xcrun notarytool keychain profile}"
: "${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION to the exact Developer ID Application identity}"
: "${DEVELOPER_ID_PROFILE:?Set DEVELOPER_ID_PROFILE to the Sign in with Apple Developer ID provisioning profile name}"
: "${RELEASE_SIGNING_KEY:?Set RELEASE_SIGNING_KEY to the dedicated SSH manifest-signing private key}"
: "${ORCA_BACKEND_COMMIT:?Set ORCA_BACKEND_COMMIT to the exact runtime commit}"
: "${ORCA_BACKEND_IMAGE_DIGEST:?Set ORCA_BACKEND_IMAGE_DIGEST to the sha256 image digest}"
: "${HOST_BUNDLE_SHA256:?Set HOST_BUNDLE_SHA256 to the exact host bundle digest}"
: "${ROLLBACK_RELEASE_REF:?Set ROLLBACK_RELEASE_REF to the verified prior release}"

[[ "$ORCA_BACKEND_COMMIT" =~ ^[0-9a-f]{40}$ ]] || {
  echo "release refused: ORCA_BACKEND_COMMIT must be a full git SHA" >&2
  exit 2
}
[[ "$ORCA_BACKEND_IMAGE_DIGEST" =~ ^sha256:[0-9a-f]{64}$ ]] || {
  echo "release refused: ORCA_BACKEND_IMAGE_DIGEST must be sha256:<64 hex>" >&2
  exit 2
}
[[ "$HOST_BUNDLE_SHA256" =~ ^[0-9a-f]{64}$ ]] || {
  echo "release refused: HOST_BUNDLE_SHA256 must be 64 lowercase hex characters" >&2
  exit 2
}

if [[ -n "$(git status --porcelain)" ]]; then
  echo "release refused: source tree is dirty" >&2
  exit 2
fi
source_commit="$(git rev-parse HEAD)"
git verify-commit "$source_commit" >/dev/null

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

python3 scripts/generate_release_evidence.py \
  --root "$root" \
  --artifact "$artifact_path" \
  --source-commit "$source_commit" \
  --backend-commit "$ORCA_BACKEND_COMMIT" \
  --backend-image-digest "$ORCA_BACKEND_IMAGE_DIGEST" \
  --host-bundle-sha256 "$HOST_BUNDLE_SHA256" \
  --rollback-release-ref "$ROLLBACK_RELEASE_REF" \
  --output-dir "$evidence_dir"

ssh-keygen -Y sign \
  -n orca-release \
  -f "$RELEASE_SIGNING_KEY" \
  "$evidence_dir/manifest.json"

echo "release evidence: $evidence_dir"
