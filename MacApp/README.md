# ORCA Console for Mac

Native Mac operating surface for ORCA. It consumes the same
`OrcaRuntimeContracts` package as Pod and reads canonical ORCA product data;
it does not own agent identity, routing, work truth, approvals, memory, or
provider credentials.

## Current milestone

- native macOS 14 SwiftUI application target;
- Overview, Work, Fund, Crew, Knowledge, Lab, Runtime, and Maker navigation;
- seven named-agent conversation lanes;
- Runtime API v1 compatibility handshake;
- Keychain-backed ORCA client credential;
- server-discovered canonical direct-agent channels shared with Pod, with
  organization-scoped local persistence;
- canonical message refresh and duplicate-safe merge;
- visible route and trace receipts;
- Mac-native sidebar, list/detail views, conversation, inspector, settings,
  and keyboard commands.

Workbench files, diffs, tests, terminal, workers, approvals, and evidence panes
belong to the next bounded milestone. They must use ORCA AgentRun and the host
relay rather than adding unrestricted shell authority to this client.

## Build

Regenerate the project after editing `project.yml`:

```bash
cd MacApp
xcodegen generate --spec project.yml
xcodebuild \
  -project OrcaMac.xcodeproj \
  -scheme OrcaMac \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .derived \
  CODE_SIGNING_ALLOWED=NO \
  -disableAutomaticPackageResolution \
  -onlyUsePackageVersionsFromResolvedFile \
  test
```

ORCA Console uses Sign in with Apple. The backend exchanges the Apple identity
token for a short-lived, device-bound access token and a rotating refresh token;
the native client stores that credential only in the device Keychain. The app
does not accept shared bearer-token bootstrap values in settings, source,
fixtures, build settings, or environment variables.
