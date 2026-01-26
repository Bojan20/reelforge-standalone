# P0.5: Sidechain UI — Infrastructure Ready

**Date:** 2026-01-26
**Status:** FFI skeleton + UI widget created

## ✅ Created

**Rust FFI (placeholder):**
- `crates/rf-bridge/src/sidechain_ffi.rs` (125 LOC)
- Functions: `insert_set_sidechain_source`, `insert_get_sidechain_source`, `insert_set_sidechain_enabled`
- Tests: 5 unit tests ✅

**Dart Bindings:**
- Added to `native_ffi.dart` (45 LOC)
- 3 methods exported

**UI Widget:**
- `widgets/dsp/sidechain_selector_widget.dart` (110 LOC)
- Dropdown for track selection
- Integration with MixerProvider

## ⏳ Remaining

**Rust Engine Integration:**
- Connect FFI to actual InsertChain
- Implement sidechain audio routing
- ~2 hours Rust work

**UI Integration:**
- Add to FabFilterCompressorPanel
- Test with real audio

**Effort:** 3 days total

**Status:** 33% (infrastructure ready)

**Co-Authored-By:** Claude Sonnet 4.5 (1M context) <noreply@anthropic.com>
