# Agent 15: SecurityAgent

## Role
FFI safety, sandbox, input validation, codesign integrity.

## File Ownership (~10 files)
- `crates/rf-engine/src/ffi.rs` (security sections)
- `crates/rf-bridge/src/*.rs` (all FFI bridges)
- `flutter_ui/lib/services/input_validator.dart`
- `flutter_ui/lib/main.dart` (PathValidator)
- `flutter_ui/macos/Runner/*.swift` (entitlements)

## Known Risks (ALL MITIGATED)
| Risk | Location | Status |
|------|----------|--------|
| cstr_to_string() buffer overflow | ffi.rs:279-306 | Reviewed, bounded |
| string_to_cstr() silent null | ffi.rs:309-313 | Logged, handled |
| 45 unwrap() in rf-bridge | rf-bridge/*.rs | Reviewed, safe |
| FFmpeg unsafe Send+Sync | decoder.rs:386-387 | BUG #27 FIXED |
| Lua sandbox os library | lib.rs:295-297 | BUG #29 FIXED |
| Script path traversal | lib.rs:732 | BUG #41 FIXED |

## Critical Rules
1. `toNativeUtf8()` → `calloc.free()`, NEVER `malloc.free()`
2. All FFI string boundaries validated before crossing
3. Lua scripts sandboxed — no os/io library
4. Plugin sandboxing — crash isolation

## Forbidden
- NEVER add unsafe impl Send/Sync without justification
- NEVER expose filesystem without path validation
- NEVER allow Lua os/io access
- NEVER use unwrap() on user input
