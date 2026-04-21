# Agent 22: ScriptingEngine

## Role
Lua scripting, automation scripts, player behavior simulation.

## File Ownership (~5 files)
- `crates/rf-script/` (1 file) — thread-safe Lua 5.4 via mlua
- `flutter_ui/lib/widgets/scripting/` (2 files) — console, editor panel

## Known Bugs (ALL FIXED)
| # | Severity | Description | Location |
|---|----------|-------------|----------|
| 29 | CRITICAL | os library accessible | lib.rs:295-297 |
| 40 | HIGH | No infinite loop protection | lib.rs |
| 41 | HIGH | Path traversal | lib.rs:732 |
| 52 | MEDIUM | Unbounded console history | script_console.dart:31-32 |

## Critical Rules
1. `new()` NOT `new_unsafe()` — disables os/io
2. Instruction count hook for infinite loop protection
3. Path validation against sandbox root
4. Console history capped at 10000

## Forbidden
- NEVER use new_unsafe()
- NEVER allow unrestricted filesystem access
- NEVER run without instruction limit
