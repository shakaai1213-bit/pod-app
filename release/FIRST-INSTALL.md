# ORCA Console first-install release contract

`INSTALL_MODE=initial-install` is only for the first production installation of
ORCA Console on Shaka's Mac. It does not invent a prior Console release.

The release driver refuses this mode when `/Applications/ORCA Console.app`
already exists. After notarization, it captures and signs a short-lived
`orca.console.preinstall-state.v1` packet in the approved `orca-auth-state`
signature namespace that binds:

- the absent application target and bundle identifier;
- the target host identifier and observation time;
- the exact rollback runtime commit, image, and host bundle.

The release manifest uses `orca.console.release-manifest.v5` and records either
`rollback.mode=initial-install` or `rollback.mode=upgrade`. Public verification
rejects mixed modes, an app-present claim, stale or future-dated preinstall
evidence, signature or digest tampering, and runtime/host mismatches.

Initial-install rollback revokes every native refresh family, removes the app
only when the installed app matches the current release identity, restores the
hash-bound prior runtime and host bundle, and reruns compatibility plus G1-G10
canaries. Later releases use `INSTALL_MODE=upgrade` and must provide the signed
prior app release chain.
