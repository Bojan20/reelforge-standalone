# P3-19 — Quick Assign Mode

**Date:** 2026-01-31
**Status:** ✅ COMPLETE

---

## Overview

Implementacija Quick Assign Mode za UltimateAudioPanel — alternativni workflow za audio assignment koji eliminiše potrebu za drag-drop.

**Problem:** Sa 341 audio slotova, drag-drop je spor i glomazan.

**Solution:** Click-to-select workflow:
1. Uključi Quick Assign mode (toggle dugme)
2. Klikni audio slot → označi se kao SELECTED
3. Klikni audio fajl u Audio Browser-u → assign!

---

## Implementation

### File: `flutter_ui/lib/widgets/slot_lab/ultimate_audio_panel.dart`

### New Typedef

```dart
/// Callback when slot is selected in Quick Assign mode
typedef OnQuickAssignSlotSelected = void Function(String stage);
```

### New Widget Parameters

```dart
/// Quick Assign Mode: Called when slot is clicked in quick assign mode
final OnQuickAssignSlotSelected? onQuickAssignSlotSelected;

/// Quick Assign Mode: Currently selected slot (highlighted)
final String? quickAssignSelectedSlot;

/// Quick Assign Mode: Whether quick assign mode is active
final bool quickAssignMode;
```

### Constructor Update

```dart
const UltimateAudioPanel({
  // ... existing parameters ...
  this.onQuickAssignSlotSelected,
  this.quickAssignSelectedSlot,
  this.quickAssignMode = false,
});
```

### Header Toggle Button (~65 LOC)

Lokacija: `_buildHeader()` metoda

```dart
// Quick Assign toggle button
GestureDetector(
  onTap: () => widget.onQuickAssignSlotSelected?.call('__TOGGLE__'),
  child: AnimatedContainer(
    duration: const Duration(milliseconds: 200),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: widget.quickAssignMode
          ? const Color(0xFF40FF90).withValues(alpha: 0.2)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(
        color: widget.quickAssignMode
            ? const Color(0xFF40FF90)
            : Colors.white24,
        width: widget.quickAssignMode ? 2 : 1,
      ),
      boxShadow: widget.quickAssignMode
          ? [BoxShadow(color: const Color(0xFF40FF90).withValues(alpha: 0.3), blurRadius: 8)]
          : null,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          widget.quickAssignMode ? Icons.touch_app : Icons.touch_app_outlined,
          size: 14,
          color: widget.quickAssignMode ? const Color(0xFF40FF90) : Colors.white54,
        ),
        const SizedBox(width: 6),
        Text(
          'Quick Assign',
          style: TextStyle(
            fontSize: 11,
            fontWeight: widget.quickAssignMode ? FontWeight.w600 : FontWeight.normal,
            color: widget.quickAssignMode ? const Color(0xFF40FF90) : Colors.white54,
          ),
        ),
      ],
    ),
  ),
),
```

### Slot Click-to-Select (~35 LOC)

Lokacija: `_buildSlot()` metoda

```dart
// Quick Assign Mode selection
final isQuickAssignSelected = widget.quickAssignMode &&
    widget.quickAssignSelectedSlot == slot.stage;

return GestureDetector(
  onTap: widget.quickAssignMode
      ? () => widget.onQuickAssignSlotSelected?.call(slot.stage)
      : null,
  child: AnimatedContainer(
    duration: const Duration(milliseconds: 150),
    // ... dynamic styling based on isQuickAssignSelected
  ),
);
```

### Visual Feedback (~45 LOC)

```dart
// AnimatedContainer decoration
decoration: BoxDecoration(
  color: isQuickAssignSelected
      ? const Color(0xFF40FF90).withValues(alpha: 0.15)
      : (slot.audioPath != null
          ? Colors.green.withValues(alpha: 0.1)
          : Colors.white.withValues(alpha: 0.03)),
  borderRadius: BorderRadius.circular(6),
  border: Border.all(
    color: isQuickAssignSelected
        ? const Color(0xFF40FF90)
        : (slot.audioPath != null ? Colors.green.withValues(alpha: 0.3) : Colors.white10),
    width: isQuickAssignSelected ? 2 : 1,
  ),
  boxShadow: isQuickAssignSelected
      ? [BoxShadow(color: const Color(0xFF40FF90).withValues(alpha: 0.3), blurRadius: 8)]
      : null,
),

// SELECTED badge
if (isQuickAssignSelected)
  Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: const Color(0xFF40FF90),
      borderRadius: BorderRadius.circular(4),
    ),
    child: const Text(
      'SELECTED',
      style: TextStyle(
        color: Colors.black,
        fontSize: 8,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    ),
  ),

// Dynamic hint text
Text(
  isQuickAssignSelected
      ? '← Click audio to assign'
      : (widget.quickAssignMode ? 'Click to select' : 'Drag audio here'),
  style: TextStyle(
    color: isQuickAssignSelected ? const Color(0xFF40FF90) : Colors.white38,
    fontSize: 9,
    fontStyle: FontStyle.italic,
  ),
),
```

---

## Signal Protocol

Special signal `'__TOGGLE__'` differentiates mode toggle from slot selection:

```dart
// Parent widget (slot_lab_screen.dart) handles:
onQuickAssignSlotSelected: (stage) {
  if (stage == '__TOGGLE__') {
    setState(() => _quickAssignMode = !_quickAssignMode);
  } else {
    setState(() => _quickAssignSelectedSlot = stage);
  }
},
```

---

## Visual Design

### Colors

| State | Background | Border | Shadow |
|-------|------------|--------|--------|
| Normal | `white.alpha(0.03)` | `white10` | none |
| Has Audio | `green.alpha(0.1)` | `green.alpha(0.3)` | none |
| Quick Assign Mode | unchanged | `white24` | none |
| **Selected** | `#40FF90.alpha(0.15)` | `#40FF90` (2px) | `#40FF90` blur 8px |

### Toggle Button

| State | Background | Border | Icon |
|-------|------------|--------|------|
| Off | transparent | `white24` (1px) | `touch_app_outlined` white54 |
| **On** | `#40FF90.alpha(0.2)` | `#40FF90` (2px) + glow | `touch_app` #40FF90 |

---

## LOC Summary

| Component | LOC |
|-----------|-----|
| Typedef | 2 |
| Widget parameters | 12 |
| Constructor | 3 |
| Header toggle button | ~65 |
| Slot click handler | ~35 |
| Visual feedback | ~45 |
| **Total** | **~162** |

---

## Verification

```bash
$ cd flutter_ui && flutter analyze
Analyzing flutter_ui...
   info • Use interpolation to compose strings and values • lib/services/documentation_generator.dart:223:43

1 issue found. (ran in 3.6s)
```

**Result:** 0 errors, 0 warnings — PASS ✅

---

## Integration (Parent Widget) ✅ IMPLEMENTED

### File: `flutter_ui/lib/screens/slot_lab_screen.dart`

#### 1. State Variables (~line 485)

```dart
// ═══════════════════════════════════════════════════════════════════════════
// QUICK ASSIGN MODE (P3-19)
// ═══════════════════════════════════════════════════════════════════════════
bool _quickAssignMode = false;
String? _quickAssignSelectedSlot;
```

#### 2. UltimateAudioPanel Integration (~line 2350)

```dart
UltimateAudioPanel(
  // ... existing parameters ...

  // P3-19: Quick Assign Mode
  quickAssignMode: _quickAssignMode,
  quickAssignSelectedSlot: _quickAssignSelectedSlot,
  onQuickAssignSlotSelected: (stage) {
    if (stage == '__TOGGLE__') {
      setState(() {
        _quickAssignMode = !_quickAssignMode;
        if (!_quickAssignMode) {
          _quickAssignSelectedSlot = null;  // Clear selection on mode off
        }
      });
    } else {
      setState(() => _quickAssignSelectedSlot = stage);
    }
  },
),
```

#### 3. EventsPanelWidget Integration (~line 2480)

```dart
EventsPanelWidget(
  // ... existing parameters ...

  // P3-19: Quick Assign Mode — click audio to assign to selected slot
  onAudioClicked: (audioPath) {
    if (_quickAssignMode && _quickAssignSelectedSlot != null) {
      final projectProvider = context.read<SlotLabProjectProvider>();
      _handleQuickAssign(audioPath, _quickAssignSelectedSlot!, projectProvider);
      setState(() => _quickAssignSelectedSlot = null);
    }
  },
),
```

#### 4. _handleQuickAssign Method (~80 LOC, ~line 8950)

```dart
void _handleQuickAssign(
  String audioPath,
  String stage,
  SlotLabProjectProvider projectProvider,
) {
  // 1. Create stage name from slot
  final stageName = stage.toUpperCase().replaceAll(' ', '_');

  // 2. Generate event ID
  final eventId = 'quick_${stageName}_${DateTime.now().millisecondsSinceEpoch}';

  // 3. Create SlotCompositeEvent
  final compositeEvent = SlotCompositeEvent(
    id: eventId,
    name: stageName.replaceAll('_', ' ').toLowerCase(),
    triggerStages: [stageName],
    layers: [
      SlotEventLayer(
        id: 'layer_${DateTime.now().millisecondsSinceEpoch}',
        audioPath: audioPath,
        volume: 1.0,
        pan: 0.0,
        offsetMs: 0,
        fadeInMs: 0,
        fadeOutMs: 0,
      ),
    ],
    priority: 50,
    looping: false,
  );

  // 4. Register to EventRegistry for playback
  final eventRegistry = context.read<EventRegistry>();
  final audioEvent = AudioEvent(
    id: eventId,
    name: compositeEvent.name,
    stage: stageName,
    layers: compositeEvent.layers.map((l) => AudioLayer(
      audioPath: l.audioPath,
      volume: l.volume,
      pan: l.pan,
      delay: l.offsetMs,
    )).toList(),
  );
  eventRegistry.registerEvent(audioEvent);

  // 5. Add to MiddlewareProvider for persistence
  final middlewareProvider = context.read<MiddlewareProvider>();
  middlewareProvider.addCompositeEvent(compositeEvent);

  // 6. Show confirmation SnackBar
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          const Icon(Icons.flash_on, color: Color(0xFF40FF90)),
          const SizedBox(width: 8),
          Text('Assigned to $stageName'),
        ],
      ),
      backgroundColor: const Color(0xFF1A1A20),
      duration: const Duration(seconds: 2),
    ),
  );
}
```

---

### File: `flutter_ui/lib/widgets/slot_lab/events_panel_widget.dart`

#### 1. New Widget Parameter (~line 45)

```dart
/// P3-19: Callback when audio file is clicked (for Quick Assign Mode)
final Function(String audioPath)? onAudioClicked;
```

#### 2. _AudioBrowserItemWrapper onTap Parameter (~line 890)

```dart
/// P3-19: Callback when item is clicked (for Quick Assign Mode)
final VoidCallback? onTap;
```

#### 3. GestureDetector Wrapper (~line 920)

```dart
@override
Widget build(BuildContext context) {
  return GestureDetector(
    onTap: onTap,
    child: _buildAudioBrowserItemContent(),
  );
}
```

#### 4. Usage in _buildAudioItem (~lines 750, 780, 810)

```dart
_AudioBrowserItemWrapper(
  // ... existing parameters ...
  onTap: () => widget.onAudioClicked?.call(audioPath),
),
```

---

## Acceptance Criteria

- [x] Quick Assign toggle button in header
- [x] Green glow effect when active
- [x] Click slot to select in quick assign mode
- [x] Selected slot has green highlight + "SELECTED" badge
- [x] Dynamic hint text based on state
- [x] AnimatedContainer for smooth transitions
- [x] **Audio browser click assigns to selected slot**
- [x] **EventRegistry registration for playback**
- [x] **MiddlewareProvider sync for persistence**
- [x] **SnackBar confirmation with ⚡ icon**
- [x] `flutter analyze` = 0 errors

---

## LOC Summary (Updated)

| Component | File | LOC |
|-----------|------|-----|
| Widget implementation | `ultimate_audio_panel.dart` | ~162 |
| State + callbacks | `slot_lab_screen.dart` | ~100 |
| Audio click handler | `events_panel_widget.dart` | ~20 |
| **Total** | | **~282** |

---

*Completed: 2026-01-31*
