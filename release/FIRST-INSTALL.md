# ORCA Console first-install release contract

`INSTALL_MODE=initial-install` is only for the first production installation of
ORCA Console on Shaka's Mac. It does not invent a prior Console release.

The release driver refuses this mode when `/Applications/ORCA Console.app`
already exists. After notarization, it captures and signs a short-lived
`orca.console.preinstall-state.v1` packet in the approved `orca-auth-state`
signature namespace that binds:

- the absent application target and bundle identifier;
- the app host, runtime host, and observation time;
- the exact rollback runtime commit object, source archive, image, and host
  bundle, and signed auth-state snapshot.

The first bootstrap may attest an unsigned historical production commit only
as `preinstall-attested-legacy`. The release-signed preinstall packet must bind
that commit object and every runtime artifact. A signed rollback commit must use
`git-ssh-signed`; the verifier rejects dishonest trust-mode selection. Upgrade
releases never permit legacy commit attestation.

The release manifest uses `orca.console.release-manifest.v7` and records either
`rollback.mode=initial-install` or `rollback.mode=upgrade`. Public verification
rejects mixed modes, an app-present claim, stale or future-dated preinstall
evidence, signature or digest tampering, and runtime/host mismatches.

Manifest v7 also carries the exact Runtime API OpenAPI documents from the signed
client and backend commits. Generation and independent verification fail closed
unless their canonical JSON, declared schema digest, and contract version match.
The same gate binds and checks the native client's compiled schema pin.

Before archive creation, `audit_orca_console_installations.py` inventories
`/Applications`, `~/Applications`, `~/Desktop`, and `~/Downloads`. It verifies
the canonical `com.orcamc.mac` identity, refuses malformed or symlinked apps,
and emits a preserve-first quarantine plan for every installed or loose copy.
DerivedData and explicitly supplied evidence roots are classified as build
evidence and never mistaken for installed products. The release stays closed
until the plan is empty. The exact fresh inventory is copied into the evidence
bundle and hash-bound by manifest v7; the independent verifier checks mode,
age, identity, counts, readiness, and canonical-install parity.

For the initial lab bootstrap, the rollback auth-state packet must be captured
from the production runtime immediately before release. It identifies active
refresh families only by sorted SHA-256 values and never carries raw refresh
tokens. If production has no active families, the signed list and count are
both empty.

Pipe one opaque active-family identifier per line from the production database
into `scripts/capture_runtime_auth_state.py`, then sign the resulting file in
the `orca-auth-state` namespace. The contract binds the exact runtime commit,
runtime host, policy, and UTC capture time. Both release generation and public
verification reject a snapshot older than 15 minutes, a future timestamp, or a
host mismatch with the signed preinstall packet.

Initial-install rollback revokes every native refresh family, removes the app
only when the installed app matches the current release identity, restores the
hash-bound prior runtime and host bundle, and reruns compatibility plus G1-G10
canaries. Later releases use `INSTALL_MODE=upgrade` and must provide the signed
prior app release chain.
