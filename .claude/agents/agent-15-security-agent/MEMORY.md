# Agent 15: SecurityAgent — Memory

## Accumulated Knowledge
- 45 unwrap() in rf-bridge — all safe (internal state, not user input)
- FFmpeg Send+Sync removed, properly synchronized
- Lua sandbox: new() disables os/io, instruction count hook
- PathValidator centralizes file path sanitization
- FFIBoundsChecker validates all FFI parameters

## Gotchas
- malloc.free() on calloc allocation = UB
- CStr::from_ptr() can read beyond buffer if not null-terminated
- unsafe impl Send+Sync on FFmpeg was dangerous (BUG #27)
