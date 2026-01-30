# Compilation Errors — Fix in Next Session

**Total:** 30 errors
**Estimated Fix Time:** 2-3h

---

## Error Categories

### 1. Missing EventRegistry.unregisterStage() (3 errors)
**File:** `lib/screens/slot_lab_screen.dart:12317-12319`
**Fix:** Add method to EventRegistry or use alternative

### 2. Missing InsertSlot.processorType (8 errors)
**File:** `lib/services/dsp/multi_processor_chain_validator.dart`
**Fix:** Add processorType field to InsertSlot model

### 3. Export Adapters Model Mismatches (15 errors)
**Files:** fmod_studio_exporter, godot_exporter, wwise_exporter
**Fix:** Update to current SlotCompositeEvent, RtpcDefinition models

### 4. Missing Theme Import (4 errors)
**File:** `lib/widgets/plugin/plugin_pdc_indicator.dart`
**Fix:** Replace `../../theme/theme.dart` with `../../theme/fluxforge_theme.dart`

**Estimated:** 30 min per file, 2h total

---

**Next Session:** Run cleanup script, fix all, verify 0 errors
