# AutoEventBuilderProvider Removal Documentation

**Date:** 2026-01-30
**Status:** ✅ COMPLETE

---

## Overview

The `AutoEventBuilderProvider` has been deprecated and largely removed from the codebase. Event management now uses `MiddlewareProvider` as the Single Source of Truth (SSoT).

---

## Architecture Change

### Before (Deprecated)
```
Audio Drop → AutoEventBuilderProvider.createDraft()
           → QuickSheet popup
           → AutoEventBuilderProvider.commitDraft()
           → CommittedEvent created
           → Bridge function converts to SlotCompositeEvent
           → MiddlewareProvider.addCompositeEvent()
```

### After (Current)
```
Audio Drop → DropTargetWrapper detects drop
           → MiddlewareProvider.addCompositeEvent() directly
           → SlotCompositeEvent created (SSoT)
           → EventRegistry notified
           → Audio playback ready
```

---

## Files Deleted

| File | LOC | Reason |
|------|-----|--------|
| `widgets/slot_lab/auto_event_builder/rule_editor_panel.dart` | ~400 | Unused, deprecated |
| `widgets/slot_lab/auto_event_builder/preset_editor_panel.dart` | ~350 | Unused, deprecated |
| `widgets/slot_lab/auto_event_builder/advanced_event_config.dart` | ~500 | Unused, deprecated |
| `widgets/slot_lab/auto_event_builder/droppable_slot_preview.dart` | ~300 | Replaced by DropTargetWrapper |
| `widgets/slot_lab/auto_event_builder/quick_sheet.dart` | ~600 | Functionality moved to DropTargetWrapper |

**Total Deleted:** ~2,150 LOC

---

## Files Modified

### slot_lab_screen.dart

**Changes:**
- Removed `AutoEventBuilderProvider` import, declaration, initialization, disposal
- Changed `MultiProvider` to single `ChangeNotifierProvider<MiddlewareProvider>`
- Updated `_buildMiniDropZone()` to use `Consumer<MiddlewareProvider>` directly
- Removed duplicate `_targetIdToStage()` method (kept comprehensive version at line 8400+)
- Added `StageContext` to import from `auto_event_builder_models.dart`
- Added inline implementations for missing widgets:
  - `_buildSymbolZonePanel()` — Symbol audio drop zones
  - `_buildMusicZonePanel()` — Music context drop zones
- Removed unused `AssetType` from import

### drop_target_wrapper.dart

**Changes:**
- Rewritten to use `MiddlewareProvider` directly instead of `AutoEventBuilderProvider`
- Removed `stage_group_service.dart` import (unused)
- Creates `SlotCompositeEvent` directly via provider
- Simplified event creation flow

### batch_export_panel.dart

**Changes:**
- Updated to use `MiddlewareProvider` methods for export data
- Connected to real exporters (Unity, Unreal, Howler)
- Proper file generation and progress tracking

---

## Stub Provider (Preserved)

**File:** `providers/auto_event_builder_provider.dart`

The provider file is preserved as a **stub** for backwards compatibility. It contains:

- Empty implementations returning `null`, `const []`, or no-ops
- Stub classes: `EventDraft`, `CommittedEvent`, `CrossfadeConfig`, `ConditionalTrigger`, etc.
- All methods are non-functional but prevent compile errors

**Why Preserved:**
- Some widgets may still import it
- Gradual migration path
- Can be deleted once all references are removed

---

## New Data Flow

### Event Creation via Drop

```dart
// DropTargetWrapper._handleDrop()
void _handleDrop(AudioAsset asset, Offset position) {
  final provider = context.read<MiddlewareProvider>();
  final stage = _targetIdToStage(target.targetId);

  final event = SlotCompositeEvent(
    id: 'evt_${DateTime.now().millisecondsSinceEpoch}',
    name: EventNamingService.instance.generateEventName(target.targetId, stage),
    triggerStages: [stage],
    layers: [
      SlotEventLayer(
        id: 'layer_${DateTime.now().millisecondsSinceEpoch}',
        audioPath: asset.path,
        volume: 1.0,
        pan: _calculatePan(target.targetId),
        busId: _stageToBusId(stage),
      ),
    ],
  );

  provider.addCompositeEvent(event);
  onEventCreated?.call(event);
}
```

### Event Count in Drop Zones

```dart
// slot_lab_screen.dart - _buildMiniDropZone()
Widget _buildMiniDropZone(String label, String targetId, Color color) {
  return Consumer<MiddlewareProvider>(
    builder: (context, provider, _) {
      final stage = _targetIdToStage(targetId);
      final count = provider.compositeEvents
          .where((e) => e.triggerStages.contains(stage))
          .length;
      // ... build UI with count badge
    },
  );
}
```

---

## Symbol Zone Panel (Inline Implementation)

```dart
Widget _buildSymbolZonePanel() {
  final symbolCategories = [
    ('Special', ['WILD', 'SCATTER', 'BONUS'], Color(0xFFFF6B6B)),
    ('High Pay', ['HP1', 'HP2', 'HP3', 'HP4', 'HP5'], Color(0xFFFFD700)),
    ('Medium Pay', ['MP1', 'MP2', 'MP3', 'MP4', 'MP5'], Color(0xFF40C8FF)),
    ('Low Pay', ['LP1', 'LP2', 'LP3', 'LP4', 'LP5'], Color(0xFF40FF90)),
  ];

  return Container(
    width: 180,
    child: Column(
      children: [
        for (final (name, symbols, color) in symbolCategories) ...[
          Text(name, style: TextStyle(color: color)),
          Wrap(
            children: symbols.map((s) =>
              _buildLabeledDropZone('symbol.$s', s, color, compact: true)
            ).toList(),
          ),
        ],
      ],
    ),
  );
}
```

---

## Music Zone Panel (Inline Implementation)

```dart
Widget _buildMusicZonePanel() {
  final musicContexts = [
    ('Base Game', 'base', Color(0xFF40C8FF)),
    ('Feature', 'feature', Color(0xFFFF6B6B)),
    ('Free Spins', 'freespins', Color(0xFF40FF90)),
    ('Bonus', 'bonus', Color(0xFFFFD700)),
    ('Jackpot', 'jackpot', Color(0xFFFF9040)),
    ('Hold & Win', 'holdwin', Color(0xFF9370DB)),
  ];

  return Container(
    child: Wrap(
      children: musicContexts.map((ctx) {
        final (label, id, color) = ctx;
        return _buildLabeledDropZone('music.$id', label, color);
      }).toList(),
    ),
  );
}
```

---

## Stage Mapping (_targetIdToStage)

The comprehensive `_targetIdToStage()` method maps UI target IDs to canonical stage names:

| Target ID Pattern | Stage Name |
|-------------------|------------|
| `ui.spin` | `SPIN_START` |
| `ui.autospin` | `AUTOPLAY_START` |
| `ui.turbo` | `UI_TURBO_ON` |
| `reel.0` - `reel.4` | `REEL_STOP_0` - `REEL_STOP_4` |
| `overlay.win.big` | `WIN_PRESENT_BIG` |
| `overlay.jackpot.grand` | `JACKPOT_GRAND` |
| `feature.freespins` | `FREESPINS_TRIGGER` |
| `symbol.WILD` | `SYMBOL_LAND_WILD` |
| `music.base` | `MUSIC_BASE` |

Full mapping: ~150+ target→stage conversions covering all UI elements.

---

## Flutter Analyze Results

```
flutter analyze
Analyzing flutter_ui...

8 issues found. (ran in 2.7s)
```

**Issues (all info-level):**
- `unnecessary_overrides` in stub provider (expected)
- `unintended_html_in_doc_comment` (pre-existing)
- `constant_identifier_names` (pre-existing)
- `unrelated_type_equality_checks` (pre-existing)
- `unnecessary_underscores` (pre-existing)

**No errors. No warnings.**

---

## Migration Guide

### For New Code

Use `MiddlewareProvider` directly:

```dart
// Get provider
final provider = context.read<MiddlewareProvider>();

// Create event
final event = SlotCompositeEvent(
  id: 'evt_${DateTime.now().millisecondsSinceEpoch}',
  name: 'My Event',
  triggerStages: ['SPIN_START'],
  layers: [...],
);

// Add to SSoT
provider.addCompositeEvent(event);
```

### For Existing Code Using AutoEventBuilderProvider

Replace:
```dart
// Old way
final aeb = context.read<AutoEventBuilderProvider>();
aeb.createDraft(asset, target);
aeb.commitDraft();
```

With:
```dart
// New way
final provider = context.read<MiddlewareProvider>();
provider.addCompositeEvent(SlotCompositeEvent(...));
```

---

## Future Cleanup

Once all references to `AutoEventBuilderProvider` are removed:

1. Delete `providers/auto_event_builder_provider.dart`
2. Delete `models/auto_event_builder_models.dart` (if no other imports)
3. Remove any remaining stub imports

---

## Related Documentation

- `.claude/architecture/EVENT_SYNC_SYSTEM.md` — Event sync between providers
- `.claude/architecture/SLOTLAB_DROP_ZONE_SPEC.md` — Drop zone specification
- `.claude/docs/P3_CRITICAL_WEAKNESSES_2026_01_23.md` — Critical weaknesses analysis
