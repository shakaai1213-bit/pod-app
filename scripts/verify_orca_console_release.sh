#!/usr/bin/env bash
set -euo pipefail

: "${RELEASE_ALLOWED_SIGNERS:?Set RELEASE_ALLOWED_SIGNERS to the approved signer registry}"
: "${TRUSTED_ALLOWED_SIGNERS_SHA256:?Set TRUSTED_ALLOWED_SIGNERS_SHA256 from the external trust registry}"
: "${RELEASE_SIGNER_IDENTITY:?Set RELEASE_SIGNER_IDENTITY to the manifest signer identity}"

evidence_dir="${1:?Usage: verify_orca_console_release.sh <evidence-dir> <artifact>}"
artifact="${2:?Usage: verify_orca_console_release.sh <evidence-dir> <artifact>}"
python3 "$(dirname "$0")/verify_release_evidence.py" \
  "$evidence_dir" \
  "$artifact" \
  --allowed-signers "$RELEASE_ALLOWED_SIGNERS" \
  --trusted-allowed-signers-sha256 "$TRUSTED_ALLOWED_SIGNERS_SHA256" \
  --signer-identity "$RELEASE_SIGNER_IDENTITY"
