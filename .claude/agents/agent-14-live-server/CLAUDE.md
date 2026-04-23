# Agent 14: LiveServer

## Role
Live server integration, networking, remote sync.

## File Ownership (~5 files)
- `crates/rf-connector/` (4 files) — WebSocket/TCP, protocol, commands, connector
- `.claude/architecture/LIVE_SERVER_INTEGRATION.md`

## Status
**Implemented, maintenance mode.** WebSocket/TCP + JSON-RPC server (port 8765).

## Forbidden
- NEVER change default port without updating docs
- NEVER expose internal state without authentication
