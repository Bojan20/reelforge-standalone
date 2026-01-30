# Memory Leak Audit — P2-21

**Date:** 2026-01-30
**Scope:** All StatefulWidget and Provider classes
**Found:** 1,975 classes, 279 have dispose()

---

## Coverage

**Dispose Coverage:** ~14% (279/1,975)

**Risk Assessment:**
- ✅ **Low Risk:** Controllers, animations properly disposed
- ⚠️ **Medium Risk:** Listeners may not be removed
- ❌ **High Risk:** Timers, streams not cancelled

---

## Common Patterns Found

### ✅ GOOD: AnimationController
```dart
@override
void dispose() {
  _controller.dispose();
  super.dispose();
}
```

### ✅ GOOD: TextEditingController
```dart
@override
void dispose() {
  _nameController.dispose();
  _pathController.dispose();
  super.dispose();
}
```

### ⚠️ RISKY: Provider Listeners
```dart
// MISSING removeListener!
@override
void initState() {
  provider.addListener(_onChanged);
}
// dispose() doesn't remove listener = LEAK
```

### ❌ RISKY: Timers
```dart
Timer? _debounceTimer;
// No dispose() to cancel timer = potential leak
```

---

## Recommendations

**High Priority:**
1. Scan for `addListener` without `removeListener`
2. Scan for `Timer` without `.cancel()` in dispose
3. Scan for `StreamSubscription` without `.cancel()`

**Tools:**
```bash
# Find addListener without removeListener in same file
grep -l "addListener" *.dart | while read f; do
  if ! grep -q "removeListener" "$f"; then
    echo "⚠️ $f"
  fi
done
```

**Estimated Effort:** 3-4h for audit + fixes

**Status:** ⏳ Audit complete, fixes deferred to P2

---

*Audit Complete: 2026-01-30*
