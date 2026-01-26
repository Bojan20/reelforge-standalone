# Middleware Inspector Panel — Pan Slider Race Condition Fix

**Date:** 2026-01-25
**Status:** ✅ FIXED
**File:** `flutter_ui/lib/widgets/middleware/event_editor_panel.dart`
**Reporter:** User (Serbian): "panovanje u middleware sekciji ne radi u inspectoru desnom panelu"

---

## Problem Description

Pan slider in the Middleware section's right inspector panel was not working correctly. User could drag the slider, but upon release, the value would revert to its previous state.

### Symptoms

1. User drags pan slider to new value (e.g., -0.5)
2. Slider visually shows -0.5 during drag
3. Upon release, slider snaps back to previous value (e.g., 0.0)
4. Audio playback uses old pan value

### Affected Parameters

- Pan (primary report)
- Gain
- Delay
- Fade Time

All sliders using `_updateActionDebounced()` were affected.

---

## Root Cause Analysis

### Code Flow Investigation

1. **Slider UI** → calls `_updateActionDebounced()`
2. **`_updateActionDebounced()`** → updates local `_events[id]` via `setState()`, schedules provider sync with 50ms debounce
3. **Widget rebuild** → `Selector<MiddlewareProvider>` triggers `_syncEventsFromProviderList()`
4. **`_syncEventsFromProviderList()`** → compares local with provider, overwrites if different

### The Race Condition

```
TIMELINE (BUGGY):

T+0ms:   User drags slider → pan = -0.5
         _updateActionDebounced() called
         setState() → local _events[id].pan = -0.5
         Timer scheduled for T+50ms

T+10ms:  Widget rebuilds (from setState)
         Selector triggers
         _syncEventsFromProviderList() runs
         Provider.events[id].pan = 0.0 (OLD VALUE!)
         Local != Provider → OVERWRITE local with provider
         local _events[id].pan = 0.0 ❌

T+50ms:  Debounce timer fires
         _syncEventToProvider() called
         But local is now 0.0 (was overwritten!)
         Provider receives 0.0 ❌

RESULT: Pan change lost!
```

### Key Insight

The `_syncEventsFromProviderList()` method was designed for EXTERNAL provider changes (e.g., another widget modifies the event). It correctly syncs provider→local when provider data is newer.

**BUT** during debounce period:
- Local has NEWER data (user's slider change)
- Provider has OLDER data (not yet synced)
- Method incorrectly treats provider as authoritative

---

## Solution

### Approach: Pending Edit Protection

Added tracking to identify events with pending local edits, and skip provider→local sync for those events.

### Implementation

**1. New field (line ~104):**

```dart
// Track which event has pending local edits to prevent provider overwrite during debounce
String? _pendingEditEventId;
```

**2. Updated `_updateActionDebounced()` (lines ~3857-3893):**

```dart
void _updateActionDebounced(
  MiddlewareEvent event,
  MiddlewareAction action, {
  double? gain,
  double? pan,
  double? delay,
  double? fadeTime,
}) {
  // MARK as pending edit
  _pendingEditEventId = event.id;

  // Update local state immediately for responsive UI
  final newAction = action.copyWith(
    gain: gain,
    pan: pan,
    delay: delay,
    fadeTime: fadeTime,
  );

  final newActions = event.actions.map((a) {
    return a.id == action.id ? newAction : a;
  }).toList();

  setState(() {
    _events[event.id] = event.copyWith(actions: newActions);
  });

  // Debounce the provider sync
  _sliderDebounceTimer?.cancel();
  _sliderDebounceTimer = Timer(const Duration(milliseconds: 50), () {
    _syncEventToProvider(_events[event.id]!);
    // CLEAR pending flag after sync
    _pendingEditEventId = null;
  });
}
```

**3. Updated `_syncEventsFromProviderList()` (lines ~163-212):**

```dart
void _syncEventsFromProviderList(List<MiddlewareEvent> providerEvents) {
  for (final event in providerEvents) {
    if (!_events.containsKey(event.id)) {
      // New event - add to local
      _events[event.id] = event;
      // ... category setup ...
    } else {
      // SKIP if this event has pending local edits
      if (event.id == _pendingEditEventId) {
        continue;  // ← KEY FIX
      }
      // ... rest of sync logic for non-pending events ...
    }
  }
}
```

---

## Fixed Timeline

```
TIMELINE (FIXED):

T+0ms:   User drags slider → pan = -0.5
         _updateActionDebounced() called
         _pendingEditEventId = event.id  ← SET
         setState() → local _events[id].pan = -0.5
         Timer scheduled for T+50ms

T+10ms:  Widget rebuilds (from setState)
         Selector triggers
         _syncEventsFromProviderList() runs
         event.id == _pendingEditEventId → SKIP ✅
         local _events[id].pan = -0.5 (preserved!)

T+50ms:  Debounce timer fires
         _syncEventToProvider() called
         Local is still -0.5 ✅
         Provider.updateEvent(pan: -0.5) ✅
         _pendingEditEventId = null  ← CLEARED

RESULT: Pan change preserved!
```

---

## Verification

### flutter analyze

```bash
cd flutter_ui && flutter analyze
```

**Result:** No issues found ✅

### Manual Testing

1. Open Middleware section
2. Select an event with actions
3. Drag pan slider to -0.5
4. Release slider
5. **Expected:** Slider stays at -0.5
6. Play event
7. **Expected:** Audio pans left

---

## Design Pattern: Pending Edit Protection

This pattern is useful whenever:

- Widget has LOCAL state that syncs BIDIRECTIONALLY with provider
- Updates are DEBOUNCED (not immediate)
- Provider data can trigger widget rebuilds during debounce

**Pattern Implementation:**

```dart
// 1. Track pending edits
String? _pendingEditId;

// 2. Mark on local change
void updateLocal(String id, value) {
  _pendingEditId = id;
  setState(() { _localData[id] = value; });

  _debounceTimer?.cancel();
  _debounceTimer = Timer(debounceMs, () {
    syncToProvider(_localData[id]);
    _pendingEditId = null;  // Clear after sync
  });
}

// 3. Skip in provider→local sync
void syncFromProvider(data) {
  for (final item in data) {
    if (item.id == _pendingEditId) continue;  // Skip pending
    _localData[item.id] = item;
  }
}
```

---

## Related Files

| File | Role |
|------|------|
| `event_editor_panel.dart` | Widget with bug/fix |
| `middleware_provider.dart` | Provider (source of truth) |
| `event_system_provider.dart` | Event storage subsystem |

---

## Related Documentation

- `.claude/architecture/EVENT_SYNC_SYSTEM.md` — Updated with this fix
- `.claude/analysis/MIDDLEWARE_DEEP_ANALYSIS_PLAN.md` — Middleware analysis

---

## Commit Reference

Fix committed with message:
```
fix: Middleware inspector pan slider race condition

Added _pendingEditEventId tracking to prevent provider→local sync
from overwriting local slider changes during debounce period.

Affected: pan, gain, delay, fadeTime sliders in event_editor_panel.dart
```
