# Real Issues Fix Plan — 2026-01-30

**User-Reported Problems:**

---

## Problem 1: Events Folder - Missing DELETE and PREVIEW Buttons ❌

**Location:** SlotLab Lower Zone → "Events Folder" tab

**Issue:**
- Right-click DELETE ne radi na event-u
- REMOVE button ne postoji na dnu ekrana
- PREVIEW button ne postoji na dnu ekrana

**Root Cause:**
`EventsFolderPanel` nema action strip na dnu — samo keyboard shortcuts postoje (Delete key, line 210-217).

**Fix:**
Add action strip sa 4 dugmeta:
1. **NEW EVENT** — Kreira novi event
2. **DELETE** — Briše selektovani event (sa confirmation)
3. **DUPLICATE** — Kopira event
4. **PREVIEW** — Pusti sve layere odjednom

**Files to Edit:**
- `flutter_ui/lib/widgets/middleware/events_folder_panel.dart` — Dodati `_buildActionStrip()` na dnu Column-a

**Implementation:**
```dart
// At line 178 (after Expanded timeline area):
if (selectedEvent != null) _buildActionStrip(context, middleware, selectedEvent),
```

---

## Problem 2: Grid Dimension Dropdown — Not Re-rendering Slot Machine ❌

**Location:** SlotLab → Grid settings dropdown (5x3, 5x4, 6x3, etc.)

**Issue:**
- Dropdown menja vrednost u settings-u
- Ali centralni slot preview NE re-renderuje sa novim dimenzijama
- Grid ostaje isti kao pre

**Root Cause:**
SlotLab screen ne sluša promene iz grid dropdown-a ili ne propagira update do `PremiumSlotPreview` widgeta.

**Fix:**
Proveriti callback chain:
1. Grid dropdown `onChanged` →
2. SlotLabProvider update →
3. PremiumSlotPreview rebuild sa novim reels/rows

**Files to Check:**
- `flutter_ui/lib/screens/slot_lab_screen.dart` — Grid dropdown callback
- `flutter_ui/lib/widgets/slot_lab/premium_slot_preview.dart` — Props update

**Potential Issue:**
- Grid settings su u `_slotLabSettings` local state, ne u provider
- Consumer<SlotLabProvider> ne triggeru rebuild

---

## Problem 3: Timing Profile Dropdown — No Visual Changes ❌

**Location:** SlotLab → Timing profile dropdown (Normal/Turbo/Studio/Mobile)

**Issue:**
- Dropdown se menja
- Ali se NIŠTA ne dešava u app-u
- Spin speed, anticipation timing, rollup duration — sve ostaje isto

**Root Cause:**
Timing profile se možda menja u provider-u, ali ne propagira do:
1. Rust SlotLab engine
2. Reel animation controller
3. Stage timing generation

**Fix:**
Povezati timing profile sa:
1. `SlotLabProvider.setTimingProfile()` → FFI call `slot_lab_set_timing_profile()`
2. `ProfessionalReelAnimationController` duration multipliers
3. Stage duration calculation

**Files to Edit:**
- `flutter_ui/lib/providers/slot_lab_provider.dart` — Add FFI sync
- `crates/rf-bridge/src/slot_lab_ffi.rs` — Add `slot_lab_set_timing_profile()`
- `flutter_ui/lib/widgets/slot_lab/professional_reel_animation.dart` — Apply timing multiplier

---

## Problem 4: Right-Click Context Menu on Events ❌

**Issue:**
Right-click na event u Events Folder ne pokazuje context menu sa DELETE opcijom.

**Root Cause:**
Event item widget nema `GestureDetector.onSecondaryTapDown` handler.

**Fix:**
Dodati context menu na event item sa opcijama:
- Delete Event
- Duplicate Event
- Rename Event
- Export Event

**Files to Edit:**
- `flutter_ui/lib/widgets/middleware/events_folder_panel.dart` — `_buildEventItem()` method

---

## Implementation Priority

| # | Issue | Impact | Effort | Priority |
|---|-------|--------|--------|----------|
| 1 | Events Folder Action Strip | HIGH | 1h | P0 |
| 4 | Right-Click Context Menu | HIGH | 30min | P0 |
| 2 | Grid Dimension Update | MEDIUM | 1h | P1 |
| 3 | Timing Profile Dropdown | MEDIUM | 2h | P1 |

**Total Estimate:** 4.5 hours

---

## Next Steps

1. ✅ Create this analysis document
2. Fix P0 issues (Action Strip + Context Menu)
3. Fix P1 issues (Grid + Timing Profile)
4. Test all fixes end-to-end
5. Update MASTER_TODO with REAL broken items list
6. Create detailed 9-role analysis per CLAUDE.md

---

**Created:** 2026-01-30
**Status:** 🚧 ACTIVE FIXES IN PROGRESS
