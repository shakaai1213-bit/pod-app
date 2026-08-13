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

The release manifest uses `orca.console.release-manifest.v5` and records either
`rollback.mode=initial-install` or `rollback.mode=upgrade`. Public verification
rejects mixed modes, an app-present claim, stale or future-dated preinstall
evidence, signature or digest tampering, and runtime/host mismatches.

For the initial lab bootstrap, the rollback auth-state packet must be captured
from the production runtime immediately before release. It identifies active
refresh families only by sorted SHA-256 values and never carries raw refresh
tokens. If production has no active families, the signed list and count are
both empty.

Initial-install rollback revokes every native refresh family, removes the app
only when the installed app matches the current release identity, restores the
hash-bound prior runtime and host bundle, and reruns compatibility plus G1-G10
canaries. Later releases use `INSTALL_MODE=upgrade` and must provide the signed
prior app release chain.
