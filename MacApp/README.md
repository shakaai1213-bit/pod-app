# ORCA for Mac

Native Captain Console for the provider-neutral ORCA Chat Runtime. This target
consumes the same `OrcaRuntimeContracts` package as Pod and does not own agent
identity, routing, work truth, approvals, memory, or provider credentials.

## Current milestone

- native macOS 14 SwiftUI application target;
- seven named-agent conversation lanes;
- Runtime API v1 compatibility handshake;
- Keychain-backed agent credential;
- persisted conversation identifiers per agent;
- canonical message refresh and duplicate-safe merge;
- visible route and trace receipts;
- Mac-native sidebar, conversation, inspector, settings, and keyboard commands.

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
  -skipPackagePluginValidation \
  test
```

The development app accepts an `ORCA_AGENT_TOKEN` bootstrap once and stores it
in the device Keychain. It may also be entered in ORCA Settings. Never commit a
token or add one to `project.yml`, source, fixtures, or build settings.
