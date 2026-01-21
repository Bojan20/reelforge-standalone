# SlotLab Auto Event Builder — ULTIMATIVNA MULTI-PERSPEKTIVNA ANALIZA

**Date:** 2026-01-21
**Analyzers:** 7 uloga iz CLAUDE.md
**Subject:** SLOTLAB_AUTO_EVENT_BUILDER.md specifikacija

---

## 🎵 1. CHIEF AUDIO ARCHITECT — Audio Pipeline Analysis

### Strengths ✅

1. **Bus architecture je profesionalna** — 10 buseva sa jasnom hijerarhijom (SFX/*, MUSIC/*, VO, AMB, MASTER)
2. **Voice limiting per-group** — Sprečava voice stacking i CPU spikes
3. **Ducking integration** — bigwin/jackpot automatski duckuje MUSIC/*
4. **Priority system** — 0-100 range sa jasnim tier-ovima

### Gaps & Fixes 🔧

#### GAP 1: Missing Bus Hierarchy Definition

**Problem:** Bus map ne definiše parent→child routing.

**Fix:** Dodaj eksplicitnu hijerarhiju:
```
MASTER
├── SFX (submix)
│   ├── SFX/UI
│   ├── SFX/Reels
│   ├── SFX/Symbols
│   ├── SFX/Wins
│   └── SFX/Features
├── MUSIC (submix)
│   ├── MUSIC/Base
│   └── MUSIC/Feature
├── VO
└── AMB
```

**Impact:** Omogućava master SFX fader, group mute, i per-category limiting.

#### GAP 2: Missing Sidechain Source Definition

**Problem:** Ducking kaže "medium on MUSIC/*" ali ne definiše sidechain source.

**Fix:** Dodaj u preset:
```json
{
  "ducking": {
    "targets": ["MUSIC/Base", "MUSIC/Feature"],
    "amount": -12,
    "attackMs": 10,
    "releaseMs": 300,
    "sidechainSource": "self"  // ili "bus:SFX/Wins"
  }
}
```

#### GAP 3: Missing Loudness Normalization

**Problem:** Assets mogu imati različite loudness levels.

**Fix:** Dodaj u Asset model:
```json
{
  "loudnessInfo": {
    "integratedLufs": -16.0,
    "truePeak": -1.0,
    "normalizeTarget": -14.0,
    "normalizeGain": 2.0  // auto-computed
  }
}
```

#### GAP 4: Missing Crossfade for Music Transitions

**Problem:** Music layer nema crossfade između stage-ova.

**Fix:** Dodaj u music_layer preset:
```json
{
  "transitionPolicy": "sync_to_bar",
  "crossfadeMs": 2000,
  "crossfadeType": "equal_power"
}
```

---

## 🔊 2. LEAD DSP ENGINEER — Real-Time Processing Analysis

### Strengths ✅

1. **Lock-free design implied** — Event system koristi trigger→action, ne blocking calls
2. **Voice pooling via voiceLimitGroup** — Pre-allocated voices per category
3. **Cooldown prevents rapid-fire** — 30-250ms cooldowns su razumni

### Gaps & Fixes 🔧

#### GAP 5: Missing Voice Stealing Policy

**Problem:** Kada polyphony limit dosegne, šta se dešava?

**Fix:** Dodaj u preset:
```json
{
  "polyphony": 2,
  "voiceStealPolicy": "oldest",  // oldest | quietest | none | priority
  "voiceStealFadeMs": 10
}
```

#### GAP 6: Missing Sample-Accurate Timing

**Problem:** Triggeri su event-based, ali timing granularity nije definisana.

**Fix:** Dodaj timing precision:
```json
{
  "timingPrecision": "sample",  // sample | block | frame
  "triggerLatencyCompensation": true,
  "preTriggerMs": 0  // za anticipation pre-load
}
```

#### GAP 7: Missing RTPC Integration

**Problem:** Preseti imaju static values, ali RTPC može dinamički menjati.

**Fix:** Dodaj RTPC bindings:
```json
{
  "rtpcBindings": [
    {
      "param": "volume",
      "rtpcId": "GameState_Intensity",
      "curve": [[0, -6], [0.5, 0], [1, 3]]
    }
  ]
}
```

#### GAP 8: Missing Per-Reel Spatial Positioning

**Problem:** Reel sounds idu na isti bus, ali nemaju pan per-reel.

**Fix:** Dodaj spatial info u binding:
```json
{
  "paramOverrides": {
    "pan": -0.8  // reel 1 = left
  }
}
```

Ili automatski: `reel.1 = -0.8, reel.2 = -0.4, reel.3 = 0, reel.4 = 0.4, reel.5 = 0.8`

---

## ⚙️ 3. ENGINE ARCHITECT — Performance & Memory Analysis

### Strengths ✅

1. **Data-driven rules** — JSON umesto hardcode
2. **Deterministic export** — Sorted IDs, stable output
3. **Draft-commit pattern** — No immediate side effects

### Gaps & Fixes 🔧

#### GAP 9: Missing Asset Preload Strategy

**Problem:** Kad se event kreira, kad se asset učitava u memoriju?

**Fix:** Dodaj preload policy:
```json
{
  "preloadPolicy": "on_stage_enter",  // on_commit | on_stage_enter | on_first_trigger | manual
  "preloadPriority": "high",
  "memoryBudgetBytes": 2097152  // 2MB max for this event
}
```

#### GAP 10: Missing Event Instance Pooling

**Problem:** Svaki trigger može kreirati novi event instance — GC pressure.

**Fix:** Definisati pooling strategiju:
```dart
class EventInstancePool {
  final int maxInstances = 64;  // per event type
  final Duration instanceTimeout = Duration(seconds: 30);
}
```

#### GAP 11: Missing Manifest Versioning

**Problem:** Export manifest nema verziju — breaking changes mogu uništiti runtime.

**Fix:** Dodaj verzioniranje:
```json
{
  "manifestVersion": "2.0.0",
  "minRuntimeVersion": "1.5.0",
  "generatedAt": "2026-01-21T15:30:00Z",
  "generatorVersion": "FluxForge 2.1.0",
  "events": [],
  "bindings": []
}
```

#### GAP 12: Missing Batch Operation Optimization

**Problem:** Batch drop na 5 reels može kreirati 5 pojedinačnih commits.

**Fix:** Dodaj batch transaction:
```dart
manifestTransaction.begin();
for (reel in reels) {
  commitEngine.createEvent(draft);
}
manifestTransaction.commit();  // Single manifest write
```

---

## 🏗️ 4. TECHNICAL DIRECTOR — Architecture & Tech Decisions

### Strengths ✅

1. **Separation of concerns** — Asset, Target, Event, Binding su odvojeni
2. **Rule-based matching** — Priority-based, extensible
3. **Two-mode UX** — Fast/Pro caters to different users

### Gaps & Fixes 🔧

#### GAP 13: Missing Undo/Redo for Commits

**Problem:** Commit je jednokratan — nema undo.

**Fix:** Integracija sa UndoManager:
```dart
class EventCommitCommand extends UndoableCommand {
  final Event event;
  final Binding binding;

  void execute() => manifest.add(event, binding);
  void undo() => manifest.remove(event.id, binding.id);
}
```

#### GAP 14: Missing Event Dependencies

**Problem:** Event A može zavisiti od Event B (npr. stinger after intro).

**Fix:** Dodaj dependency graph:
```json
{
  "eventId": "feature.fs.loop",
  "dependencies": {
    "after": "feature.fs.intro",
    "delayMs": 0
  }
}
```

#### GAP 15: Missing Conditional Triggers

**Problem:** Triggeri su always-fire, ali slot logika ima uslove.

**Fix:** Dodaj conditions:
```json
{
  "trigger": "onBigWinTier(tier)",
  "conditions": [
    { "signal": "winXbet", "op": ">=", "value": 50 }
  ]
}
```

#### GAP 16: Missing Template Inheritance

**Problem:** Preset duplikacija (bigwin_tier1/2/3 su skoro isti).

**Fix:** Dodaj inheritance:
```json
{
  "presetId": "bigwin_tier2",
  "extends": "bigwin_tier1",
  "overrides": {
    "priority": 99,
    "ducking.amount": -15
  }
}
```

---

## 🎨 5. UI/UX EXPERT — DAW Workflow Analysis

### Strengths ✅

1. **Quick Sheet for fast iteration** — 1-click commit
2. **Command Builder for power users** — Full control
3. **Audition before commit** — Preview loop

### Gaps & Fixes 🔧

#### GAP 17: Missing Keyboard Shortcuts

**Problem:** Sve je mouse-driven.

**Fix:** Dodaj shortcuts:
| Shortcut | Action |
|----------|--------|
| `D` | Toggle drop mode (Fast/Pro) |
| `Enter` | Commit draft |
| `Escape` | Cancel draft |
| `Space` | Audition draft |
| `Tab` | Next field in Quick Sheet |
| `1-5` | Select trigger preset |

#### GAP 18: Missing Visual Feedback During Drop

**Problem:** Dok držiš asset iznad targeta, nema preview šta će se desiti.

**Fix:** Dodaj drop preview:
```
[Drop Preview Tooltip]
━━━━━━━━━━━━━━━━━━━━━
Target: ui.spin
Rule: UI_PRIMARY_CLICK
Event: ui.spin.click_primary
Bus: SFX/UI
Preset: ui_click_primary
━━━━━━━━━━━━━━━━━━━━━
[Drop to create]
```

#### GAP 19: Missing Bulk Edit

**Problem:** Promena preset-a za 10 eventova zahteva 10 pojedinačnih edita.

**Fix:** Dodaj multi-select + bulk edit:
```
[Selected: 10 events]
━━━━━━━━━━━━━━━━━━━━━
Change preset for all: [dropdown]
Change bus for all: [dropdown]
[Apply to Selected]
```

#### GAP 20: Missing Search/Filter in Event List

**Problem:** Sa 100+ eventa, pronalaženje specifičnog je teško.

**Fix:** Dodaj search:
```
🔍 Search: [scatter____________]
Filter: [Stage: All ▼] [Bus: All ▼] [Type: All ▼]

Results:
• symbol.scatter.hit (Base, SFX/Symbols)
• symbol.scatter.hit (FS, SFX/Symbols)
```

---

## 🖥️ 6. GRAPHICS ENGINEER — Visualization Analysis

### Strengths ✅

1. **Target badges** — Visual count of events
2. **Inspector panel** — Detailed view

### Gaps & Fixes 🔧

#### GAP 21: Missing Waveform in Quick Sheet

**Problem:** Asset dropdown nema visual preview.

**Fix:** Dodaj mini waveform:
```
[Asset: spin_click_01.wav]
 ▁▂▄█▇▅▂▁ 0.2s  SFX
[Play] [Browse...]
```

#### GAP 22: Missing Bus Meter Visualization

**Problem:** Audition ne pokazuje koji bus prima signal.

**Fix:** Dodaj live bus meters:
```
[Bus Activity]
SFX/UI    ████████░░ -6dB
SFX/Reels ░░░░░░░░░░ -∞
MUSIC/Base ██████░░░░ -12dB
```

#### GAP 23: Missing Timeline Visualization for Loops

**Problem:** Loop start/stop nije vizualno jasan.

**Fix:** Dodaj loop indicator na timeline:
```
|--[LOOP]========================================[STOP]--|
   onReelStart                                  onReelStop
```

#### GAP 24: Missing Binding Graph View

**Problem:** Kompleksne binding veze su teške za razumevanje.

**Fix:** Dodaj graph view:
```
[Graph View]

    ┌─────────────┐
    │ ui.spin     │
    │ (target)    │
    └──────┬──────┘
           │ press
           ▼
    ┌─────────────┐
    │ ui.spin.    │
    │ click_primary│
    │ (event)     │
    └──────┬──────┘
           │
    ┌──────┴──────┐
    ▼             ▼
[Base]         [FS]
vol: 0dB      vol: +1.5dB
```

---

## 🔒 7. SECURITY EXPERT — Input Validation & Safety

### Strengths ✅

1. **Validation layer defined** — Cooldown, polyphony, bus existence checks
2. **Conflict resolution** — Merge vs create new

### Gaps & Fixes 🔧

#### GAP 25: Missing Input Sanitization

**Problem:** Asset path može sadržati malicious characters.

**Fix:** Dodaj sanitization:
```dart
String sanitizeAssetPath(String path) {
  // No path traversal
  if (path.contains('..')) throw InvalidPathException();
  // Only allowed extensions
  if (!allowedExtensions.contains(extension(path))) throw InvalidExtensionException();
  // Max path length
  if (path.length > 512) throw PathTooLongException();
  return path;
}
```

#### GAP 26: Missing eventId Collision Prevention

**Problem:** Dva različita asset-a mogu generisati isti eventId.

**Fix:** Dodaj unique suffix:
```dart
String generateEventId(String base) {
  if (manifest.hasEvent(base)) {
    return '${base}_${shortUuid()}';  // ui.spin.click_primary_a1b2
  }
  return base;
}
```

#### GAP 27: Missing Manifest Integrity Check

**Problem:** Corrupted manifest može crashovati runtime.

**Fix:** Dodaj checksum:
```json
{
  "manifestVersion": "2.0.0",
  "checksum": "sha256:a1b2c3d4...",
  "events": []
}
```

Plus validation on load:
```dart
if (computeChecksum(manifest) != manifest.checksum) {
  throw ManifestCorruptedException();
}
```

#### GAP 28: Missing Rate Limiting for Rapid Drops

**Problem:** User može spam-ovati drops i flood-ovati sistem.

**Fix:** Dodaj rate limit:
```dart
class DropRateLimiter {
  final int maxDropsPerSecond = 10;
  final Duration cooldown = Duration(milliseconds: 100);

  bool canDrop() => _recentDrops < maxDropsPerSecond;
}
```

---

## 📊 SUMMARY — Pronađene Rupe

| # | Gap | Severity | Domain |
|---|-----|----------|--------|
| 1 | Bus hierarchy undefined | HIGH | Audio |
| 2 | Sidechain source undefined | MEDIUM | Audio |
| 3 | Loudness normalization missing | MEDIUM | Audio |
| 4 | Music crossfade undefined | MEDIUM | Audio |
| 5 | Voice stealing policy undefined | HIGH | DSP |
| 6 | Timing precision undefined | MEDIUM | DSP |
| 7 | RTPC integration missing | MEDIUM | DSP |
| 8 | Per-reel spatial undefined | LOW | DSP |
| 9 | Asset preload strategy undefined | HIGH | Engine |
| 10 | Event instance pooling undefined | MEDIUM | Engine |
| 11 | Manifest versioning missing | HIGH | Engine |
| 12 | Batch transaction missing | MEDIUM | Engine |
| 13 | Undo/Redo missing | HIGH | Architecture |
| 14 | Event dependencies missing | MEDIUM | Architecture |
| 15 | Conditional triggers missing | HIGH | Architecture |
| 16 | Template inheritance missing | LOW | Architecture |
| 17 | Keyboard shortcuts missing | MEDIUM | UX |
| 18 | Drop preview missing | MEDIUM | UX |
| 19 | Bulk edit missing | MEDIUM | UX |
| 20 | Search/filter missing | MEDIUM | UX |
| 21 | Waveform preview missing | LOW | Graphics |
| 22 | Bus meters missing | MEDIUM | Graphics |
| 23 | Loop visualization missing | LOW | Graphics |
| 24 | Binding graph missing | LOW | Graphics |
| 25 | Input sanitization missing | HIGH | Security |
| 26 | eventId collision unhandled | HIGH | Security |
| 27 | Manifest integrity missing | HIGH | Security |
| 28 | Rate limiting missing | MEDIUM | Security |

### HIGH Priority Fixes (Must Have)

1. **GAP 1:** Bus hierarchy
2. **GAP 5:** Voice stealing
3. **GAP 9:** Asset preload
4. **GAP 11:** Manifest versioning
5. **GAP 13:** Undo/Redo
6. **GAP 15:** Conditional triggers
7. **GAP 25:** Input sanitization
8. **GAP 26:** eventId collision
9. **GAP 27:** Manifest integrity

### MEDIUM Priority Fixes (Should Have)

10. **GAP 2:** Sidechain source
11. **GAP 3:** Loudness normalization
12. **GAP 4:** Music crossfade
13. **GAP 6:** Timing precision
14. **GAP 7:** RTPC integration
15. **GAP 10:** Event pooling
16. **GAP 12:** Batch transaction
17. **GAP 14:** Event dependencies
18. **GAP 17-20:** UX improvements
19. **GAP 22:** Bus meters
20. **GAP 28:** Rate limiting

---

## 🛠️ IMPLEMENTATION PRIORITY

### Phase 1: Critical Foundation (Before Implementation)
- GAP 1, 5, 9, 11, 25, 26, 27

### Phase 2: Core Features (During Implementation)
- GAP 13, 15, 2, 6, 12

### Phase 3: Polish (After MVP)
- GAP 3, 4, 7, 10, 14, 17-24, 28

### Phase 4: Nice-to-Have
- GAP 8, 16

---

**Analysis Complete.**
**28 gaps identified, 9 HIGH priority, 11 MEDIUM priority.**

---

**Last Updated:** 2026-01-21
