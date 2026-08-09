# OrcaRuntimeContracts

Shared provider-neutral ORCA Chat Runtime contract for native iOS and macOS
clients. Swift types and the client are generated at build time from
`Sources/OrcaRuntimeContracts/openapi.json`.

## Contract ownership

The canonical schema and OpenAPI exporter live in the Mission Control backend:

- `backend/contracts/orca-chat-runtime-v1.openapi.json`
- `backend/scripts/export_chat_runtime_openapi.py`
- `backend/app/schemas/chat_runtime.py`

Do not hand-edit the copied OpenAPI document or generated Swift. Update the
backend contract, run its compatibility tests, export the artifact, and then
copy the reviewed artifact into this package.

## Verification

```bash
swift test
```

The tests decode the backend-produced complete-turn fixture and verify that
adapter, runtime-session, cursor, event, and terminal-outcome fields survive
Swift generation. The root Pod project also links this package during its iOS
build.
