# OrcaRuntimeContracts

Shared provider-neutral ORCA Chat Runtime contract for native iOS and macOS
clients. Swift types and the client are generated from
`Sources/OrcaRuntimeContracts/openapi.json` and checked in so release builds do
not resolve the generator toolchain.

## Contract ownership

The canonical schema and OpenAPI exporter live in the Mission Control backend:

- `backend/contracts/orca-chat-runtime-v1.openapi.json`
- `backend/scripts/export_chat_runtime_openapi.py`
- `backend/app/schemas/chat_runtime.py`

Do not hand-edit the copied OpenAPI document or generated Swift. Update the
backend contract, run its compatibility tests, export the artifact, and then
copy the reviewed artifact into this package. Generate `Types.swift` and
`Client.swift` with `swift-openapi-generator` 1.13.0 using
`openapi-generator-config.yaml`; the package pins runtime dependencies only.

## Verification

```bash
swift test
```

The tests decode the backend-produced complete-turn fixture and verify that
adapter, runtime-session, cursor, event, and terminal-outcome fields survive
Swift generation. They also fail closed when a named-agent capability bundle
drifts from its Agent Pack, overstates live attestation, or points execution
outside ORCA. Work Control bundles are likewise bound to the selected Agent Pack
and reject contradictory readiness, unauthorized approval decisions, count drift,
or execution pointers outside ORCA. Conversation V2 reads and reviewed proposals
use the same generated client, while the Flight Recorder accepts canonical reply
message identities without relaxing turn, conversation, agent, sequence, cursor,
or terminal-outcome invariants. The root Pod project and ORCA Console both link
this package during their native builds.
