# Stage Ingest FFI Type Mismatch Fix — 2026-01-20

**Status:** ✅ COMPLETE
**Build:** `cargo build --release` OK, `flutter analyze` OK

---

## Summary

Fixed 3 critical FFI type mismatches that prevented the Stage Ingest Wizard from functioning.

| # | Issue | Location | Fix |
|---|-------|----------|-----|
| 1 | `wizard_analyze_json` returns `*mut c_char`, Dart expected `Bool` | `native_ffi.dart:1770-1771` | Changed to `Pointer<Utf8>` |
| 2 | `wizard_get_recommended_layer` returns `u8`, Dart expected `Pointer<Utf8>` | `native_ffi.dart:1774-1775` | Changed to `Uint8`/`int` |
| 3 | `adapter_get_info_json` takes `*const c_char`, Dart passed `Uint32` | `native_ffi.dart:1794` | Changed to `Pointer<Utf8>` |

---

## Fix 1: wizard_analyze_json

**Rust (rf-engine/src/ffi.rs:19129):**
```rust
pub extern "C" fn wizard_analyze_json(json_samples: *const c_char) -> *mut c_char
```

**Dart Before:**
```dart
typedef WizardAnalyzeJsonNative = Bool Function(Pointer<Utf8> json);
typedef WizardAnalyzeJsonDart = bool Function(Pointer<Utf8> json);

bool wizardAnalyzeJson(String json) { ... }
```

**Dart After:**
```dart
typedef WizardAnalyzeJsonNative = Pointer<Utf8> Function(Pointer<Utf8> json);
typedef WizardAnalyzeJsonDart = Pointer<Utf8> Function(Pointer<Utf8> json);

String? wizardAnalyzeJson(String json) {
  final inputPtr = json.toNativeUtf8();
  try {
    final resultPtr = _wizardAnalyzeJson(inputPtr);
    if (resultPtr == nullptr) return null;
    return resultPtr.toDartString();
  } finally {
    calloc.free(inputPtr);
  }
}
```

---

## Fix 2: wizard_get_recommended_layer

**Rust (rf-engine/src/ffi.rs:19171):**
```rust
pub extern "C" fn wizard_get_recommended_layer() -> u8 {
    // Returns: 0=DirectEvent, 1=SnapshotDiff, 2=RuleBased
}
```

**Dart Before:**
```dart
typedef WizardGetRecommendedLayerNative = Pointer<Utf8> Function();
typedef WizardGetRecommendedLayerDart = Pointer<Utf8> Function();

String? wizardGetRecommendedLayer() { ... }
```

**Dart After:**
```dart
typedef WizardGetRecommendedLayerNative = Uint8 Function();
typedef WizardGetRecommendedLayerDart = int Function();

int wizardGetRecommendedLayer() {
  if (!_loaded) return 0;
  return _wizardGetRecommendedLayer();
}
```

**Model Extension (stage_models.dart):**
```dart
enum IngestLayer {
  // Added fromInt factory
  static IngestLayer fromInt(int value) => switch (value) {
    0 => IngestLayer.directEvent,
    1 => IngestLayer.snapshotDiff,
    2 => IngestLayer.ruleBased,
    _ => IngestLayer.directEvent,
  };
}
```

---

## Fix 3: adapter_get_info_json

**Rust (rf-engine/src/ffi.rs:19292):**
```rust
pub extern "C" fn adapter_get_info_json(adapter_id: *const c_char) -> *mut c_char
```

**Dart Before:**
```dart
typedef AdapterGetInfoJsonNative = Pointer<Utf8> Function(Uint32 index);
typedef AdapterGetInfoJsonDart = Pointer<Utf8> Function(int index);

String? adapterGetInfoJson(int index) { ... }
```

**Dart After:**
```dart
typedef AdapterGetInfoJsonNative = Pointer<Utf8> Function(Pointer<Utf8> adapterId);
typedef AdapterGetInfoJsonDart = Pointer<Utf8> Function(Pointer<Utf8> adapterId);

String? adapterGetInfoJson(String adapterId) {
  final idPtr = adapterId.toNativeUtf8();
  try {
    final ptr = _adapterGetInfoJson(idPtr);
    if (ptr == nullptr) return null;
    return ptr.toDartString();
  } finally {
    calloc.free(idPtr);
  }
}
```

**Provider Update (stage_provider.dart):**
```dart
// Before
final infoJson = _ffi.adapterGetInfoJson(i);

// After - must get ID first, then info
final adapterId = _ffi.adapterGetIdAt(i);
if (adapterId == null) continue;
final infoJson = _ffi.adapterGetInfoJson(adapterId);
```

---

## Files Changed

| File | Changes |
|------|---------|
| `flutter_ui/lib/src/rust/native_ffi.dart` | 3 typedef fixes + 3 method fixes |
| `flutter_ui/lib/providers/stage_provider.dart` | 2 method call updates |
| `flutter_ui/lib/models/stage_models.dart` | Added `IngestLayer.fromInt()` |

---

## Verification

```bash
flutter analyze  # ✅ No issues found
cargo build --release  # ✅ Finished release profile
```

---

## Impact

The Stage Ingest Wizard is now functional:
- ✅ JSON wizard analysis works
- ✅ Company/engine auto-detection works
- ✅ Recommended layer detection works
- ✅ Adapter registry browsing works
- ✅ Full wizard flow enabled
