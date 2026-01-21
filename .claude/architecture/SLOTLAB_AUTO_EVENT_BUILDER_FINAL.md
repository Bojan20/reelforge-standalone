# SLOT LAB: Auto Event Builder — ULTIMATE SPECIFICATION v1.0

**Date:** 2026-01-21
**Status:** FINAL — Ready for Implementation
**Priority:** P0 — Core SlotLab Feature
**Analysis:** 28 gaps identified and resolved

---

## 0) Executive Summary

Drag & drop audio asset na SlotLab mockup element → automatski kreira:
1. **Event** (šta se dešava)
2. **Binding** (gde i kad se pali)
3. **Bus routing** + **Preset params** + **Voice management**

**Sve data-driven** (DropRules.json + Presets.json + CommandTemplates.json).

---

## 1) Core Objects

### 1.1 Asset (Audio File)

| Field | Type | Description | Required |
|-------|------|-------------|----------|
| `assetId` | String | Unique identifier | ✅ |
| `path` | String | File path (sanitized) | ✅ |
| `assetType` | Enum | `SFX` \| `MUSIC` \| `VO` \| `AMB` | ✅ |
| `tags` | List | `click`, `whoosh`, `impact`, `loop`, `stinger`, `tick`, `reel`, `stop`, `anticipation` | ✅ |
| `isLoop` | bool | Whether asset loops | ✅ |
| `durationMs` | int | Duration in milliseconds | ✅ |
| `variants` | List | Auto-detected variants (`spin_click_01..05`) | ✅ |
| `loudnessInfo` | Object | Loudness normalization data | ✅ |

#### 1.1.1 Loudness Info (GAP 3 FIX)

```json
{
  "loudnessInfo": {
    "integratedLufs": -16.0,
    "truePeak": -1.0,
    "normalizeTarget": -14.0,
    "normalizeGain": 2.0
  }
}
```

**Auto-computed on import.** Ensures consistent playback levels.

#### 1.1.2 Path Sanitization (GAP 25 FIX)

```dart
String sanitizeAssetPath(String path) {
  // No path traversal
  if (path.contains('..')) throw InvalidPathException('Path traversal detected');

  // Only allowed extensions
  const allowed = {'.wav', '.mp3', '.ogg', '.flac', '.aiff'};
  final ext = path.split('.').last.toLowerCase();
  if (!allowed.contains('.$ext')) throw InvalidExtensionException('Extension not allowed: $ext');

  // Max path length
  if (path.length > 512) throw PathTooLongException('Path exceeds 512 characters');

  // No special characters
  final sanitized = path.replaceAll(RegExp(r'[<>:"|?*]'), '_');

  return sanitized;
}
```

### 1.2 Target (Drop Zone)

| Field | Type | Description | Required |
|-------|------|-------------|----------|
| `targetId` | String | `ui.spin`, `reel.1`, `overlay.bigWin` | ✅ |
| `targetType` | Enum | See Target Types | ✅ |
| `targetTags` | List | `primary`, `secondary`, `cta`, `reels`, `wins` | ✅ |
| `stageContext` | Enum | `BaseGame` \| `FreeSpins` \| `Bonus:<id>` \| `Global` | ✅ |
| `interactionSemantics` | List | Supported triggers | ✅ |

**Target Types:**
- `ui_button`, `ui_toggle`
- `hud_counter`, `hud_meter`
- `reel_surface`, `reel_stop_zone`
- `symbol`
- `overlay`
- `feature_container`
- `screen_zone`

### 1.3 Event

| Field | Type | Description | Required |
|-------|------|-------------|----------|
| `eventId` | String | Unique ID (collision-safe) | ✅ |
| `intent` | String | Standardized intent name | ✅ |
| `actions` | List | Play asset, chain, etc. | ✅ |
| `bus` | String | Bus routing | ✅ |
| `presetId` | String | Param template reference | ✅ |
| `voiceLimitGroup` | String | Voice limiting group | ✅ |
| `variationPolicy` | Enum | `random` \| `round_robin` \| `shuffle_bag` | ✅ |
| `tags` | List | QA/analytics tags | ✅ |
| `dependencies` | Object | Event dependencies (GAP 14) | ⚪ |
| `conditions` | List | Conditional triggers (GAP 15) | ⚪ |
| `preloadPolicy` | Enum | Asset preload strategy (GAP 9) | ✅ |

#### 1.3.1 Event ID Collision Prevention (GAP 26 FIX)

```dart
String generateEventId(String base) {
  if (!manifest.hasEvent(base)) {
    return base;
  }

  // Generate unique suffix
  final suffix = _shortUuid();  // 4-char alphanumeric
  return '${base}_$suffix';     // ui.spin.click_primary_a1b2
}

String _shortUuid() {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final random = Random.secure();
  return List.generate(4, (_) => chars[random.nextInt(chars.length)]).join();
}
```

#### 1.3.2 Event Dependencies (GAP 14 FIX)

```json
{
  "eventId": "feature.fs.loop",
  "dependencies": {
    "after": "feature.fs.intro",
    "delayMs": 0,
    "required": true
  }
}
```

#### 1.3.3 Conditional Triggers (GAP 15 FIX)

```json
{
  "eventId": "overlay.bigwin.tier3",
  "conditions": [
    { "signal": "winXbet", "op": ">=", "value": 100 },
    { "signal": "consecutiveWins", "op": ">=", "value": 3, "logic": "AND" }
  ]
}
```

**Supported Operators:** `==`, `!=`, `<`, `<=`, `>`, `>=`, `contains`, `startsWith`
**Logic:** `AND`, `OR`, `NOT`

#### 1.3.4 Asset Preload Policy (GAP 9 FIX)

```json
{
  "preloadPolicy": "on_stage_enter",
  "preloadPriority": "high",
  "memoryBudgetBytes": 2097152
}
```

| Policy | Description |
|--------|-------------|
| `on_commit` | Load when event committed |
| `on_stage_enter` | Load when stage activates |
| `on_first_trigger` | Lazy load on first trigger |
| `manual` | Explicit load via API |

### 1.4 Binding

| Field | Type | Description | Required |
|-------|------|-------------|----------|
| `bindingId` | String | Unique ID | ✅ |
| `eventId` | String | Reference to Event | ✅ |
| `targetId` | String | Reference to Target | ✅ |
| `stageId` | String | Stage context | ✅ |
| `trigger` | String | Trigger type | ✅ |
| `paramOverrides` | Object | Per-binding overrides | ⚪ |
| `enabled` | bool | Whether active | ✅ |

---

## 2) Bus Hierarchy (GAP 1 FIX — CRITICAL)

### 2.1 Complete Hierarchy

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

### 2.2 Bus Configuration

```json
{
  "buses": [
    {
      "busId": "MASTER",
      "parent": null,
      "volumeDb": 0,
      "mute": false,
      "solo": false
    },
    {
      "busId": "SFX",
      "parent": "MASTER",
      "volumeDb": 0,
      "children": ["SFX/UI", "SFX/Reels", "SFX/Symbols", "SFX/Wins", "SFX/Features"]
    },
    {
      "busId": "SFX/UI",
      "parent": "SFX",
      "volumeDb": 0
    },
    // ... etc
  ]
}
```

**Benefits:**
- Master SFX fader
- Group mute/solo
- Per-category voice limiting
- Hierarchical ducking

### 2.3 Bus Routing Rules

| Drop Target | Bus |
|-------------|-----|
| UI button | `SFX/UI` |
| Reel surface | `SFX/Reels` |
| Symbol | `SFX/Symbols` |
| Win meter/counter | `SFX/Wins` |
| Feature overlay | `SFX/Features` |
| Music zone (base) | `MUSIC/Base` |
| Music zone (feature) | `MUSIC/Feature` |
| VO zone | `VO` |
| Ambience zone | `AMB` |

---

## 3) Preset Library (Complete)

### 3.1 Preset Schema (Enhanced)

```json
{
  "presetId": "ui_click_primary",
  "polyphony": 2,
  "voiceLimitGroup": "UI_PRIMARY",
  "voiceStealPolicy": "oldest",
  "voiceStealFadeMs": 10,
  "cooldownMs": 60,
  "priority": 70,
  "pitchRandCents": 10,
  "volRandDb": 0.5,
  "fadeInMs": 0,
  "fadeOutMs": 10,
  "ducking": null,
  "timingPrecision": "block",
  "triggerLatencyCompensation": true,
  "preTriggerMs": 0,
  "rtpcBindings": []
}
```

### 3.2 Voice Stealing Policy (GAP 5 FIX — CRITICAL)

```json
{
  "polyphony": 2,
  "voiceStealPolicy": "oldest",
  "voiceStealFadeMs": 10
}
```

| Policy | Description |
|--------|-------------|
| `oldest` | Steal oldest playing voice |
| `quietest` | Steal quietest voice |
| `lowest_priority` | Steal lowest priority voice |
| `none` | Reject new trigger (no stealing) |

### 3.3 Timing Precision (GAP 6 FIX)

```json
{
  "timingPrecision": "sample",
  "triggerLatencyCompensation": true,
  "preTriggerMs": 20
}
```

| Precision | Description |
|-----------|-------------|
| `sample` | Sample-accurate (< 1ms) |
| `block` | Block-accurate (buffer size) |
| `frame` | Frame-accurate (16-33ms) |

### 3.4 RTPC Bindings (GAP 7 FIX)

```json
{
  "rtpcBindings": [
    {
      "param": "volume",
      "rtpcId": "GameState_Intensity",
      "curve": [[0, -6], [0.5, 0], [1, 3]]
    },
    {
      "param": "pitch",
      "rtpcId": "Win_Amount",
      "curve": [[0, -100], [1, 100]]
    }
  ]
}
```

### 3.5 Per-Reel Spatial Positioning (GAP 8 FIX)

```json
{
  "spatialMode": "auto_per_reel",
  "paramOverrides": {
    "reel.1": { "pan": -0.8 },
    "reel.2": { "pan": -0.4 },
    "reel.3": { "pan": 0.0 },
    "reel.4": { "pan": 0.4 },
    "reel.5": { "pan": 0.8 }
  }
}
```

### 3.6 Ducking Configuration (GAP 2 FIX)

```json
{
  "ducking": {
    "targets": ["MUSIC/Base", "MUSIC/Feature"],
    "amount": -12,
    "attackMs": 10,
    "releaseMs": 300,
    "sidechainSource": "self",
    "curve": "exponential"
  }
}
```

| Sidechain Source | Description |
|------------------|-------------|
| `self` | This event's audio |
| `bus:<name>` | Specific bus (e.g., `bus:SFX/Wins`) |
| `event:<id>` | Specific event |

### 3.7 Music Crossfade (GAP 4 FIX)

```json
{
  "transitionPolicy": "sync_to_bar",
  "crossfadeMs": 2000,
  "crossfadeType": "equal_power",
  "quantizePolicy": "bar"
}
```

| Crossfade Type | Description |
|----------------|-------------|
| `linear` | Linear crossfade |
| `equal_power` | -3dB at midpoint |
| `s_curve` | Smooth S-curve |

### 3.8 Template Inheritance (GAP 16 FIX)

```json
{
  "presetId": "bigwin_tier2",
  "extends": "bigwin_tier1",
  "overrides": {
    "priority": 99,
    "ducking": {
      "amount": -15
    }
  }
}
```

### 3.9 Complete Preset Library

#### UI Presets

```json
// ui_click_primary
{
  "presetId": "ui_click_primary",
  "polyphony": 2,
  "voiceLimitGroup": "UI_PRIMARY",
  "voiceStealPolicy": "oldest",
  "voiceStealFadeMs": 10,
  "cooldownMs": 60,
  "priority": 70,
  "pitchRandCents": 10,
  "volRandDb": 0.5,
  "fadeInMs": 0,
  "fadeOutMs": 10,
  "ducking": null,
  "timingPrecision": "block"
}

// ui_click_secondary
{
  "presetId": "ui_click_secondary",
  "extends": "ui_click_primary",
  "overrides": {
    "voiceLimitGroup": "UI_SECONDARY",
    "cooldownMs": 80,
    "priority": 55,
    "pitchRandCents": 8
  }
}

// ui_hover
{
  "presetId": "ui_hover",
  "polyphony": 1,
  "voiceLimitGroup": "UI_HOVER",
  "voiceStealPolicy": "oldest",
  "cooldownMs": 120,
  "priority": 40,
  "pitchRandCents": 5,
  "volRandDb": 0.3
}

// ui_toggle
{
  "presetId": "ui_toggle",
  "polyphony": 1,
  "voiceLimitGroup": "UI_TOGGLE",
  "voiceStealPolicy": "oldest",
  "cooldownMs": 100,
  "priority": 60
}

// ui_error
{
  "presetId": "ui_error",
  "polyphony": 1,
  "voiceLimitGroup": "UI_ERROR",
  "voiceStealPolicy": "oldest",
  "cooldownMs": 250,
  "priority": 90,
  "ducking": {
    "targets": ["MUSIC/Base", "MUSIC/Feature"],
    "amount": -6,
    "attackMs": 5,
    "releaseMs": 150,
    "sidechainSource": "self"
  }
}
```

#### Reel Presets

```json
// reel_spin_start
{
  "presetId": "reel_spin_start",
  "polyphony": 5,
  "voiceLimitGroup": "REEL_START",
  "voiceStealPolicy": "oldest",
  "cooldownMs": 0,
  "priority": 85,
  "pitchRandCents": 5,
  "volRandDb": 0.5,
  "spatialMode": "auto_per_reel"
}

// reel_spin_loop
{
  "presetId": "reel_spin_loop",
  "polyphony": 5,
  "voiceLimitGroup": "REEL_LOOP",
  "voiceStealPolicy": "oldest",
  "loop": true,
  "fadeInMs": 30,
  "fadeOutMs": 60,
  "priority": 80,
  "spatialMode": "auto_per_reel",
  "stopPolicy": "stop on onReelStop(reelIndex) or onAllReelsStop"
}

// reel_stop
{
  "presetId": "reel_stop",
  "polyphony": 5,
  "voiceLimitGroup": "REEL_STOP",
  "voiceStealPolicy": "oldest",
  "cooldownMs": 0,
  "priority": 95,
  "pitchRandCents": 6,
  "volRandDb": 0.4,
  "spatialMode": "auto_per_reel",
  "timingPrecision": "sample",
  "preTriggerMs": 20
}

// anticipation_loop
{
  "presetId": "anticipation_loop",
  "polyphony": 2,
  "voiceLimitGroup": "ANTICIPATION",
  "voiceStealPolicy": "oldest",
  "loop": true,
  "fadeInMs": 40,
  "fadeOutMs": 80,
  "priority": 92,
  "ducking": {
    "targets": ["MUSIC/Base", "MUSIC/Feature"],
    "amount": -6,
    "attackMs": 20,
    "releaseMs": 200,
    "sidechainSource": "self"
  },
  "preTriggerMs": 50
}
```

#### Symbol Presets

```json
// symbol_land_lp
{
  "presetId": "symbol_land_lp",
  "polyphony": 4,
  "voiceLimitGroup": "SYMBOL_LP",
  "voiceStealPolicy": "oldest",
  "cooldownMs": 0,
  "priority": 70,
  "pitchRandCents": 7
}

// symbol_land_hp
{
  "presetId": "symbol_land_hp",
  "polyphony": 4,
  "voiceLimitGroup": "SYMBOL_HP",
  "voiceStealPolicy": "oldest",
  "priority": 80,
  "pitchRandCents": 4
}

// symbol_special
{
  "presetId": "symbol_special",
  "polyphony": 2,
  "voiceLimitGroup": "SYMBOL_SPECIAL",
  "voiceStealPolicy": "lowest_priority",
  "priority": 95,
  "cooldownMs": 0
}
```

#### Win Presets

```json
// win_tick
{
  "presetId": "win_tick",
  "polyphony": 1,
  "voiceLimitGroup": "WIN_TICK",
  "voiceStealPolicy": "oldest",
  "cooldownMs": 30,
  "priority": 75,
  "pitchRandCents": 6
}

// line_win_stinger
{
  "presetId": "line_win_stinger",
  "polyphony": 2,
  "voiceLimitGroup": "WIN_STINGER",
  "voiceStealPolicy": "oldest",
  "priority": 88,
  "cooldownMs": 80
}

// bigwin_tier1
{
  "presetId": "bigwin_tier1",
  "polyphony": 1,
  "voiceLimitGroup": "BIGWIN",
  "voiceStealPolicy": "none",
  "priority": 98,
  "cooldownMs": 0,
  "ducking": {
    "targets": ["MUSIC/Base", "MUSIC/Feature"],
    "amount": -12,
    "attackMs": 10,
    "releaseMs": 500,
    "sidechainSource": "self"
  }
}

// bigwin_tier2 (inherits from tier1)
{
  "presetId": "bigwin_tier2",
  "extends": "bigwin_tier1",
  "overrides": {
    "priority": 99,
    "ducking": { "amount": -15 }
  }
}

// bigwin_tier3 (inherits from tier1)
{
  "presetId": "bigwin_tier3",
  "extends": "bigwin_tier1",
  "overrides": {
    "priority": 100,
    "ducking": { "amount": -18 }
  }
}

// jackpot
{
  "presetId": "jackpot",
  "polyphony": 1,
  "voiceLimitGroup": "JACKPOT",
  "voiceStealPolicy": "none",
  "priority": 100,
  "ducking": {
    "targets": ["MUSIC/Base", "MUSIC/Feature", "SFX"],
    "amount": -18,
    "attackMs": 5,
    "releaseMs": 800,
    "sidechainSource": "self"
  }
}
```

#### Feature Presets

```json
// feature_intro_stinger
{
  "presetId": "feature_intro_stinger",
  "polyphony": 1,
  "voiceLimitGroup": "FEATURE_INTRO",
  "voiceStealPolicy": "none",
  "priority": 95,
  "cooldownMs": 0
}

// feature_loop
{
  "presetId": "feature_loop",
  "polyphony": 1,
  "voiceLimitGroup": "FEATURE_LOOP",
  "voiceStealPolicy": "oldest",
  "loop": true,
  "fadeInMs": 200,
  "fadeOutMs": 300,
  "priority": 85
}
```

#### Music Presets

```json
// music_layer
{
  "presetId": "music_layer",
  "polyphony": 1,
  "voiceLimitGroup": "MUSIC",
  "voiceStealPolicy": "oldest",
  "loop": true,
  "fadeInMs": 1000,
  "fadeOutMs": 1000,
  "priority": 50,
  "quantizePolicy": "bar",
  "transitionPolicy": "sync_to_bar",
  "crossfadeMs": 2000,
  "crossfadeType": "equal_power"
}

// music_stinger
{
  "presetId": "music_stinger",
  "polyphony": 1,
  "voiceLimitGroup": "MUSIC_STINGER",
  "voiceStealPolicy": "oldest",
  "priority": 90,
  "ducking": {
    "targets": ["MUSIC/Base", "MUSIC/Feature"],
    "amount": -9,
    "attackMs": 10,
    "releaseMs": 400,
    "sidechainSource": "self"
  }
}
```

---

## 4) Trigger Vocabulary

### 4.1 UI Triggers

| Trigger | Description |
|---------|-------------|
| `press` | Button pressed |
| `release` | Button released |
| `hover` | Mouse hover (desktop) |
| `disabledPress` | Press when disabled |
| `toggleOn` | Toggle switched on |
| `toggleOff` | Toggle switched off |

### 4.2 Gameplay / Reels Triggers

| Trigger | Description |
|---------|-------------|
| `onSpinRequest` | Spin requested |
| `onSpinStart` | Spin started |
| `onReelStart(reelIndex)` | Specific reel starts |
| `onReelStop(reelIndex)` | Specific reel stops |
| `onAllReelsStop` | All reels stopped |
| `onAnticipationStart(reelIndex)` | Anticipation begins |
| `onAnticipationEnd(reelIndex)` | Anticipation ends |

### 4.3 Win System Triggers

| Trigger | Description |
|---------|-------------|
| `onWinStart` | Win presentation starts |
| `onWinTick` | Win counter tick |
| `onWinEnd` | Win presentation ends |
| `onBigWinTier(tier)` | Big win tier reached |
| `onJackpot(type)` | Jackpot won |

### 4.4 Feature Triggers

| Trigger | Description |
|---------|-------------|
| `onStageEnter` | Enter stage |
| `onStageExit` | Exit stage |
| `onFeatureIntro(featureId)` | Feature intro plays |
| `onFeatureStart(featureId)` | Feature gameplay starts |
| `onFeatureEnd(featureId)` | Feature ends |

---

## 5) DropRules System

### 5.1 Rule Schema

```json
{
  "ruleId": "UI_PRIMARY_CLICK",
  "priority": 1000,
  "when": {
    "targetType": "ui_button",
    "targetId": { "contains": "spin" },
    "targetTags": { "includes": "primary" },
    "assetType": "SFX"
  },
  "create": {
    "domain": "ui",
    "intent": "click_primary",
    "bus": "SFX/UI",
    "presetId": "ui_click_primary",
    "trigger": "press",
    "eventIdTemplate": "ui.{targetKey}.click_primary",
    "variationPolicy": "auto"
  },
  "constraints": {
    "defaultDropMode": "replace",
    "maxBindingsPerStage": 1
  }
}
```

### 5.2 Complete Rules (Priority Order)

#### UI Rules (1000-880)

| Rule ID | Priority | When | Creates |
|---------|----------|------|---------|
| `UI_PRIMARY_CLICK` | 1000 | ui_button + "spin"/primary tag | `ui.{targetKey}.click_primary` |
| `UI_SECONDARY_CLICK` | 950 | ui_button | `ui.{targetKey}.click_secondary` |
| `UI_HOVER` | 900 | ui_button + hover asset | `ui.{targetKey}.hover` |
| `UI_TOGGLE` | 890 | ui_toggle | `ui.{targetKey}.toggle_{on\|off}` |
| `UI_ERROR` | 880 | ui_button + error asset | `ui.{targetKey}.error` |

#### Reel Rules (820-800)

| Rule ID | Priority | When | Creates |
|---------|----------|------|---------|
| `REEL_SPIN_LOOP` | 820 | reel_surface + loop asset | `reel.{targetKey}.spin_loop` |
| `REEL_SPIN_START` | 810 | reel_surface + start asset | `reel.{targetKey}.spin_start` |
| `REEL_STOP` | 800 | reel_stop_zone | `reel.{targetKey}.stop` |

#### Anticipation Rules (770)

| Rule ID | Priority | When | Creates |
|---------|----------|------|---------|
| `ANTICIPATION_LOOP` | 770 | reel/overlay + anticipation asset | `reel.{targetKey}.anticipation_loop` |

#### Symbol Rules (740-710)

| Rule ID | Priority | When | Creates |
|---------|----------|------|---------|
| `SYMBOL_SPECIAL_SCATTER` | 740 | symbol + scatter | `symbol.scatter.hit` |
| `SYMBOL_SPECIAL_WILD` | 735 | symbol + wild | `symbol.wild.hit` |
| `SYMBOL_HP` | 720 | symbol + hp tag | `symbol.{targetKey}.hit_hp` |
| `SYMBOL_LP` | 710 | symbol | `symbol.{targetKey}.land` |

#### Win Rules (690-680)

| Rule ID | Priority | When | Creates |
|---------|----------|------|---------|
| `WIN_TICK` | 690 | hud_counter/meter + tick asset | `win.countup.tick` |
| `WIN_STINGER` | 680 | hud/overlay + stinger asset | `win.stinger` |

#### Big Win Rules (660-658)

| Rule ID | Priority | When | Creates |
|---------|----------|------|---------|
| `BIGWIN_TIER1` | 660 | overlay + bigWin tag + tier1 | `overlay.bigwin.tier1` |
| `BIGWIN_TIER2` | 659 | overlay + bigWin tag + tier2 | `overlay.bigwin.tier2` |
| `BIGWIN_TIER3` | 658 | overlay + bigWin tag + tier3 | `overlay.bigwin.tier3` |

#### Jackpot Rules (640)

| Rule ID | Priority | When | Creates |
|---------|----------|------|---------|
| `JACKPOT` | 640 | overlay + jackpot tag | `overlay.jackpot.{type}` |

#### Feature Rules (620-610)

| Rule ID | Priority | When | Creates |
|---------|----------|------|---------|
| `FEATURE_INTRO` | 620 | feature_container + intro asset | `feature.{featureId}.intro` |
| `FEATURE_LOOP` | 610 | feature_container + loop asset | `feature.{featureId}.loop` |

#### Music Rules (580-570)

| Rule ID | Priority | When | Creates |
|---------|----------|------|---------|
| `MUSIC_BASE` | 580 | screen_zone + BaseGame + MUSIC | `music.base.{layerKey}` |
| `MUSIC_FEATURE` | 570 | screen_zone + Feature + MUSIC | `music.{stageKey}.{layerKey}` |

#### Fallback Rules (10-9)

| Rule ID | Priority | When | Creates |
|---------|----------|------|---------|
| `FALLBACK_SFX` | 10 | any SFX | `misc.{targetKey}.play` |
| `FALLBACK_MUSIC` | 9 | any MUSIC | `music.{stageKey}.layer1` |

---

## 6) Manifest System (GAP 11 FIX — CRITICAL)

### 6.1 Manifest Schema

```json
{
  "manifestVersion": "2.0.0",
  "minRuntimeVersion": "1.5.0",
  "generatedAt": "2026-01-21T15:30:00Z",
  "generatorVersion": "FluxForge 2.1.0",
  "checksum": "sha256:a1b2c3d4e5f6...",

  "busHierarchy": { ... },
  "presets": [ ... ],
  "events": [ ... ],
  "bindings": [ ... ],
  "assets": [ ... ]
}
```

### 6.2 Manifest Integrity Check (GAP 27 FIX)

```dart
class ManifestValidator {
  static bool validateChecksum(Manifest manifest) {
    final computed = _computeChecksum(manifest);
    if (computed != manifest.checksum) {
      throw ManifestCorruptedException(
        'Checksum mismatch: expected ${manifest.checksum}, got $computed'
      );
    }
    return true;
  }

  static String _computeChecksum(Manifest manifest) {
    // Exclude checksum field itself
    final data = jsonEncode(manifest.toJsonWithoutChecksum());
    final bytes = utf8.encode(data);
    final digest = sha256.convert(bytes);
    return 'sha256:${digest.toString()}';
  }
}
```

### 6.3 Version Migration

```dart
class ManifestMigrator {
  static Manifest migrate(Map<String, dynamic> json) {
    final version = json['manifestVersion'] as String? ?? '1.0.0';

    if (version.startsWith('1.')) {
      json = _migrateV1ToV2(json);
    }

    return Manifest.fromJson(json);
  }

  static Map<String, dynamic> _migrateV1ToV2(Map<String, dynamic> json) {
    // Add bus hierarchy if missing
    json['busHierarchy'] ??= _defaultBusHierarchy;

    // Add voice stealing to presets
    for (final preset in json['presets'] ?? []) {
      preset['voiceStealPolicy'] ??= 'oldest';
    }

    json['manifestVersion'] = '2.0.0';
    return json;
  }
}
```

---

## 7) Undo/Redo System (GAP 13 FIX — CRITICAL)

### 7.1 Command Pattern

```dart
abstract class UndoableCommand {
  void execute();
  void undo();
  String get description;
}

class EventCommitCommand extends UndoableCommand {
  final Event event;
  final Binding binding;
  final Manifest manifest;

  EventCommitCommand({
    required this.event,
    required this.binding,
    required this.manifest,
  });

  @override
  void execute() {
    manifest.addEvent(event);
    manifest.addBinding(binding);
  }

  @override
  void undo() {
    manifest.removeBinding(binding.bindingId);
    manifest.removeEvent(event.eventId);
  }

  @override
  String get description => 'Create event: ${event.eventId}';
}
```

### 7.2 UndoManager Integration

```dart
class UndoManager {
  final List<UndoableCommand> _undoStack = [];
  final List<UndoableCommand> _redoStack = [];
  static const int maxHistorySize = 100;

  void execute(UndoableCommand command) {
    command.execute();
    _undoStack.add(command);
    _redoStack.clear();

    // Limit history size
    if (_undoStack.length > maxHistorySize) {
      _undoStack.removeAt(0);
    }

    notifyListeners();
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    final command = _undoStack.removeLast();
    command.undo();
    _redoStack.add(command);
    notifyListeners();
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    final command = _redoStack.removeLast();
    command.execute();
    _undoStack.add(command);
    notifyListeners();
  }

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
}
```

---

## 8) Engine Systems

### 8.1 Event Instance Pool (GAP 10 FIX)

```dart
class EventInstancePool {
  static const int maxInstancesPerType = 64;
  static const Duration instanceTimeout = Duration(seconds: 30);

  final Map<String, Queue<EventInstance>> _pools = {};

  EventInstance acquire(String eventId) {
    final pool = _pools[eventId];
    if (pool != null && pool.isNotEmpty) {
      final instance = pool.removeFirst();
      if (!instance.isExpired) {
        return instance..reset();
      }
    }
    return EventInstance(eventId);
  }

  void release(EventInstance instance) {
    final pool = _pools.putIfAbsent(instance.eventId, () => Queue());
    if (pool.length < maxInstancesPerType) {
      pool.add(instance..markReleased());
    }
  }
}
```

### 8.2 Batch Transaction (GAP 12 FIX)

```dart
class ManifestTransaction {
  final Manifest _manifest;
  final List<UndoableCommand> _pendingCommands = [];
  bool _isActive = false;

  void begin() {
    if (_isActive) throw StateError('Transaction already active');
    _isActive = true;
    _pendingCommands.clear();
  }

  void addCommand(UndoableCommand command) {
    if (!_isActive) throw StateError('No active transaction');
    _pendingCommands.add(command);
  }

  void commit() {
    if (!_isActive) throw StateError('No active transaction');

    // Execute all as single undoable batch
    final batch = BatchCommand(_pendingCommands);
    UndoManager.instance.execute(batch);

    _pendingCommands.clear();
    _isActive = false;
  }

  void rollback() {
    _pendingCommands.clear();
    _isActive = false;
  }
}
```

### 8.3 Rate Limiting (GAP 28 FIX)

```dart
class DropRateLimiter {
  static const int maxDropsPerSecond = 10;
  static const Duration cooldown = Duration(milliseconds: 100);

  final Queue<DateTime> _recentDrops = Queue();
  DateTime? _lastDrop;

  bool canDrop() {
    final now = DateTime.now();

    // Clean old entries
    while (_recentDrops.isNotEmpty &&
           now.difference(_recentDrops.first).inSeconds >= 1) {
      _recentDrops.removeFirst();
    }

    // Check rate limit
    if (_recentDrops.length >= maxDropsPerSecond) {
      return false;
    }

    // Check cooldown
    if (_lastDrop != null &&
        now.difference(_lastDrop!) < cooldown) {
      return false;
    }

    return true;
  }

  void recordDrop() {
    final now = DateTime.now();
    _recentDrops.add(now);
    _lastDrop = now;
  }
}
```

---

## 9) UX Features

### 9.1 Keyboard Shortcuts (GAP 17 FIX)

| Shortcut | Action |
|----------|--------|
| `D` | Toggle drop mode (Fast/Pro) |
| `Enter` | Commit draft |
| `Escape` | Cancel draft |
| `Space` | Audition draft |
| `Tab` | Next field in Quick Sheet |
| `Shift+Tab` | Previous field |
| `1-5` | Select trigger preset |
| `Cmd/Ctrl+Z` | Undo |
| `Cmd/Ctrl+Shift+Z` | Redo |
| `Cmd/Ctrl+S` | Save manifest |

### 9.2 Drop Preview (GAP 18 FIX)

```
┌─────────────────────────────┐
│ 📁 Drop Preview             │
├─────────────────────────────┤
│ Target: ui.spin             │
│ Rule: UI_PRIMARY_CLICK      │
│ Event: ui.spin.click_primary│
│ Bus: SFX/UI                 │
│ Preset: ui_click_primary    │
│ ──────────────────────────  │
│ 🎯 Drop to create           │
└─────────────────────────────┘
```

Tooltip appears while hovering with dragged asset.

### 9.3 Bulk Edit (GAP 19 FIX)

```
┌─────────────────────────────┐
│ 📋 Selected: 10 events      │
├─────────────────────────────┤
│ Change preset: [dropdown ▼] │
│ Change bus: [dropdown ▼]    │
│ Change volume: [slider]     │
│ ──────────────────────────  │
│ [Apply to Selected]         │
└─────────────────────────────┘
```

Multi-select via Shift+Click or Cmd/Ctrl+Click.

### 9.4 Search/Filter (GAP 20 FIX)

```
🔍 Search: [scatter__________]
Filter: [Stage: All ▼] [Bus: All ▼] [Type: All ▼]

Results (3):
• symbol.scatter.hit (Base, SFX/Symbols)
• symbol.scatter.hit (FS, SFX/Symbols)
• feature.scatter_bonus.intro (Bonus, SFX/Features)
```

### 9.5 Quick Sheet

| Field | Type | Options |
|-------|------|---------|
| **Trigger** | Dropdown | Default from rule, editable |
| **Stage scope** | Multi-select | This stage / Base + FS + Bonus... |
| **Drop mode** | Radio | Replace / Add variation / Add layer |
| **Variation policy** | Dropdown | Random / Round robin / Shuffle bag |
| **Bus** | Dropdown | From bus hierarchy |
| **Preset** | Dropdown | From preset library |
| **Commit** | Button | Creates event + binding |

---

## 10) Visualization (GAP 21-24)

### 10.1 Waveform Preview (GAP 21)

```
┌─────────────────────────────┐
│ Asset: spin_click_01.wav    │
│ ▁▂▄█▇▅▂▁ 0.2s  SFX         │
│ [▶ Play] [Browse...]        │
└─────────────────────────────┘
```

Mini waveform in asset dropdown and Quick Sheet.

### 10.2 Bus Meters (GAP 22)

```
┌─────────────────────────────┐
│ 🎚️ Bus Activity             │
├─────────────────────────────┤
│ SFX/UI    ████████░░ -6dB   │
│ SFX/Reels ░░░░░░░░░░ -∞     │
│ MUSIC/Base ██████░░░░ -12dB │
└─────────────────────────────┘
```

Live meters during audition.

### 10.3 Loop Timeline (GAP 23)

```
|--[LOOP START]═══════════════════════[STOP]--|
   onReelStart(1)                    onReelStop(1)
```

Visual loop region indicator.

### 10.4 Binding Graph (GAP 24)

```
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
     [Base]        [FS]
     vol: 0dB     vol: +1.5dB
```

Optional graph view for complex binding relationships.

---

## 11) Validation Layer

### 11.1 Auto-Checks

| Rule | Validation | Action |
|------|------------|--------|
| UI click | `cooldown >= 40ms` | Warning if lower |
| tick | `polyphony <= 1` | Force 1 |
| music | `voiceLimitGroup = MUSIC` | Force group |
| loop | Stop trigger defined | Error if missing |
| bus | Must exist | Error if invalid |
| eventId | Must be unique | Auto-suffix or merge |

### 11.2 Lint Warnings

```dart
class ManifestLinter {
  List<LintWarning> lint(Manifest manifest) {
    final warnings = <LintWarning>[];

    // Check orphan events (no bindings)
    for (final event in manifest.events) {
      final bindings = manifest.bindingsForEvent(event.eventId);
      if (bindings.isEmpty) {
        warnings.add(LintWarning(
          severity: LintSeverity.warning,
          message: 'Event "${event.eventId}" has no bindings',
          suggestion: 'Add a binding or remove the event',
        ));
      }
    }

    // Check missing stop triggers for loops
    for (final event in manifest.events) {
      final preset = manifest.getPreset(event.presetId);
      if (preset?.loop == true) {
        final hasStopBinding = manifest.bindings.any(
          (b) => b.eventId == event.eventId && b.trigger.startsWith('stop')
        );
        if (!hasStopBinding) {
          warnings.add(LintWarning(
            severity: LintSeverity.error,
            message: 'Loop event "${event.eventId}" has no stop trigger',
            suggestion: 'Add a stop binding',
          ));
        }
      }
    }

    return warnings;
  }
}
```

---

## 12) Command Builder (Pro Mode)

### 12.1 Draft Flow

```
Drop Asset
    ↓
Create Draft (no side effects)
    ↓
Open Command Builder
    ↓
User edits (params, template, etc.)
    ↓
User clicks Commit
    ↓
Execute via UndoManager
    ↓
Update Manifest
```

### 12.2 Command Templates

| Template | Auto-fills |
|----------|------------|
| `UI Click (primary)` | trigger: press, bus: SFX/UI, preset: ui_click_primary |
| `UI Click (secondary)` | trigger: press, bus: SFX/UI, preset: ui_click_secondary |
| `Reel Start` | trigger: onReelStart, bus: SFX/Reels, preset: reel_spin_start |
| `Reel Stop` | trigger: onReelStop, bus: SFX/Reels, preset: reel_stop |
| `Anticipation Loop` | trigger: onAnticipationStart/End, loop: true |
| `Win Tick` | trigger: onWinTick, polyphony: 1, cooldown: 30ms |
| `BigWin Tier` | trigger: onBigWinTier, ducking: medium |
| `Feature Intro` | trigger: onFeatureIntro, priority: 95 |
| `Base Music Bed` | trigger: onStageEnter, loop: true, crossfade |
| `Overlay Takeover` | ducking: strong, priority: 100 |

### 12.3 Command Line Syntax

```
ON press(ui.spin) -> PLAY sfx(ui_spin_click) VIA SFX/UI PRESET ui_click_primary
ON overlayEnter(BigWin) -> TAKEOVER music(bigwin_loop) MODE crossfade_under
ON stageEnter(BaseGame) -> START bed(music_base_L1) LOOP
ON onBigWinTier(3) WHERE winXbet >= 100 -> PLAY sfx(epic_win)
```

### 12.4 Two Modes

| Mode | Behavior | When to Use |
|------|----------|-------------|
| **Fast Commit** | Drop → Quick Sheet (2-3 options) → Commit | Rapid iteration |
| **Pro Draft** | Drop → Full Command Builder → Commit | Complex events |

Setting: `Default drop behavior: Fast | Pro`

---

## 13) Standard Target Map

### 13.1 Required Targets

| targetId | targetType | Tags | Stage |
|----------|------------|------|-------|
| `ui.spin` | `ui_button` | `primary` | Global |
| `ui.turbo` | `ui_toggle` | | Global |
| `ui.auto` | `ui_toggle` | | Global |
| `ui.betPlus` | `ui_button` | `secondary` | Global |
| `ui.betMinus` | `ui_button` | `secondary` | Global |
| `reel.1` - `reel.5` | `reel_surface` | `reels` | Global |
| `reelStop.1` - `reelStop.5` | `reel_stop_zone` | | Global |
| `hud.counterBar` | `hud_counter` | | Global |
| `hud.winMeter` | `hud_meter` | | Global |
| `overlay.bigWin` | `overlay` | `bigWin` | Global |
| `overlay.jackpot` | `overlay` | `jackpot` | Global |
| `feature.freeSpins` | `feature_container` | | FS |
| `screen.baseMusicZone` | `screen_zone` | `bg_music_zone` | Base |
| `screen.fsMusicZone` | `screen_zone` | `bg_music_zone` | FS |
| `symbol.wild` | `symbol` | `special` | Global |
| `symbol.scatter` | `symbol` | `special` | Global |
| `symbols.hpGroup` | `group_target` | `hp` | Global |
| `symbols.lpGroup` | `group_target` | `lp` | Global |

### 13.2 Batch Drop Groups

| Group | Targets |
|-------|---------|
| `reels_group` | reel.1 - reel.5 |
| `symbols_group_hp` | All HP symbols |
| `symbols_group_lp` | All LP symbols |
| `stage_zone` | All targets in stage |

---

## 14) Implementation Architecture

### 14.1 Core Classes

```dart
// Rule matching
class RuleEngine {
  Rule? matchRule(Target target, Asset asset);
  List<Rule> getAllMatchingRules(Target target, Asset asset);
}

// Event generation
class EventGenerator {
  EventBlueprint buildBlueprint(Rule rule, Target target, Asset asset, Stage stage);
  MergeResult checkMergePolicy(Event? existing, EventBlueprint blueprint);
}

// Validation
class Validator {
  ValidationResult validate(Event event, Binding binding, Preset preset);
  List<AutoFix> suggestFixes(List<ValidationError> errors);
}

// Commit engine
class CommitEngine {
  Event createEvent(DraftCommand draft);
  Binding createBinding(DraftCommand draft, Event event);
  void applyToManifest(UndoableCommand command);
}

// Export
class ManifestExporter {
  String exportJson(Manifest manifest);  // Deterministic, sorted
  Manifest importJson(String json);
}
```

### 14.2 Data Files

| File | Purpose |
|------|---------|
| `DropRules.json` | All rule definitions |
| `Presets.json` | All preset definitions |
| `CommandTemplates.json` | Template definitions |
| `BusHierarchy.json` | Bus configuration |
| `Manifest.json` | Runtime export |

### 14.3 Provider Integration

```dart
class AutoEventBuilderProvider extends ChangeNotifier {
  final RuleEngine _ruleEngine;
  final EventGenerator _generator;
  final CommitEngine _commitEngine;
  final UndoManager _undoManager;
  final DropRateLimiter _rateLimiter;

  DraftCommand? _currentDraft;

  // Drop handling
  Future<DraftCommand?> handleDrop(Target target, Asset asset, Stage stage) async {
    if (!_rateLimiter.canDrop()) {
      throw RateLimitException('Too many drops');
    }

    final rule = _ruleEngine.matchRule(target, asset);
    if (rule == null) return null;

    final blueprint = _generator.buildBlueprint(rule, target, asset, stage);
    _currentDraft = DraftCommand.fromBlueprint(blueprint);
    _rateLimiter.recordDrop();

    notifyListeners();
    return _currentDraft;
  }

  // Commit
  void commitDraft() {
    if (_currentDraft == null) return;

    final command = EventCommitCommand(
      event: _currentDraft!.toEvent(),
      binding: _currentDraft!.toBinding(),
      manifest: _manifest,
    );

    _undoManager.execute(command);
    _currentDraft = null;
    notifyListeners();
  }

  // Undo/Redo
  void undo() => _undoManager.undo();
  void redo() => _undoManager.redo();
}
```

---

## 15) SlotLab UI Layout — Integrated Design

### 15.1 Core Principle: Everything on One Screen

**NE poseban prozor.** Sve integrisano u SlotLab screen sa sklopivim panelima.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ SLOTLAB                                                    [≡] [−] [□] [×] │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                         SLOT MOCKUP                                  │   │
│  │                      (UVEK VIDLJIV CENTAR)                          │   │
│  │                                                                      │   │
│  │  ┌───────┐ ┌───────┐ ┌───────┐ ┌───────┐ ┌───────┐                  │   │
│  │  │ REEL1 │ │ REEL2 │ │ REEL3 │ │ REEL4 │ │ REEL5 │  ← Drop zones   │   │
│  │  │  [2]  │ │  [1]  │ │  [3]  │ │  [1]  │ │  [2]  │  (badges=events)│   │
│  │  └───────┘ └───────┘ └───────┘ └───────┘ └───────┘                  │   │
│  │                                                                      │   │
│  │        [ 🎰 SPIN ]  [ ⚡ TURBO ]  [ 🔄 AUTO ]                        │   │
│  │            [3]          [2]          [1]                            │   │
│  │                                                                      │   │
│  │  ┌─────────────────────────────────────────────────────────────┐    │   │
│  │  │ INLINE QUICK SHEET (appears on drop, at drop position)      │    │   │
│  │  │ ─────────────────────────────────────────────────────────── │    │   │
│  │  │ Trigger: [press ▼]   Bus: SFX/UI   Preset: [primary ▼]      │    │   │
│  │  │ [✓ Commit]  [More...]  [Cancel]                             │    │   │
│  │  └─────────────────────────────────────────────────────────────┘    │   │
│  │                                                                      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─ LOWER ZONE (TABBED, COLLAPSIBLE, RESIZABLE) ────────────────────────┐  │
│  │ [▼] [Timeline] [Command Builder] [Event List] [Meters]    [···]      │  │
│  │ ════════════════════════════════════════════════════════════════════ │  │
│  │                                                                       │  │
│  │  ┌─────────────────────────────────────────────────────────────────┐ │  │
│  │  │ (Active tab content displayed here)                             │ │  │
│  │  │                                                                 │ │  │
│  │  │ Timeline:        Stage trace, event flow visualization          │ │  │
│  │  │ Command Builder: Full draft editing, all parameters             │ │  │
│  │  │ Event List:      Search, filter, bulk edit                      │ │  │
│  │  │ Meters:          Bus meters, voice stats, pool info             │ │  │
│  │  │                                                                 │ │  │
│  │  └─────────────────────────────────────────────────────────────────┘ │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 15.2 Interaction Flow (3 Levels)

#### Level 1: Instant Drop (90% of cases)

```
Drag asset → Drop on target → Inline Quick Sheet popup → Enter = Commit
```

- Popup appears **AT DROP POSITION** (context menu style)
- 3 fields only: Trigger, Bus (readonly), Preset
- `Enter` = commit, `Esc` = cancel, `Tab` = expand to Command Builder

#### Level 2: Quick Expand (8% of cases)

```
Drop → Inline popup → Click "More..." → Lower Zone expands to Command Builder tab
```

- Lower zone auto-expands if collapsed
- Command Builder tab auto-activates
- Full parameter editing
- Mockup stays visible above

#### Level 3: Full Pro Mode (2% of cases)

```
Drop → Tab Tab → Full Command Builder with conditions, dependencies, RTPC
```

- Same lower zone, more tabs visible
- Graph view for complex bindings
- Never a separate window

### 15.3 Lower Zone Controller

```dart
enum LowerZoneTab { timeline, commandBuilder, eventList, meters }

class LowerZoneController extends ChangeNotifier {
  LowerZoneTab _activeTab = LowerZoneTab.timeline;
  bool _isExpanded = true;
  double _height = 250;  // Resizable (100-500px)

  void switchTo(LowerZoneTab tab) {
    _activeTab = tab;
    if (!_isExpanded) _isExpanded = true;  // Auto-expand
    notifyListeners();
  }

  void toggle() {
    _isExpanded = !_isExpanded;
    notifyListeners();
  }

  void setHeight(double h) {
    _height = h.clamp(100, 500);
    notifyListeners();
  }

  // Getters
  LowerZoneTab get activeTab => _activeTab;
  bool get isExpanded => _isExpanded;
  double get height => _height;
}
```

### 15.4 Auto-Tab Switching

| Action | Auto-switches to |
|--------|------------------|
| Drop asset on target | Command Builder |
| Click Spin | Timeline |
| Click event in list | Command Builder (edit mode) |
| Press `4` key | Meters |

```dart
void _handleDrop(Target target, Asset asset) {
  context.read<LowerZoneController>().switchTo(LowerZoneTab.commandBuilder);
  _createDraft(target, asset);
}

void _handleSpin() {
  context.read<LowerZoneController>().switchTo(LowerZoneTab.timeline);
  _startSpin();
}
```

### 15.5 SlotLab Screen Implementation

```dart
class SlotLabScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => LowerZoneController(),
      child: Column(
        children: [
          // MOCKUP (expands to fill available space)
          Expanded(
            child: SlotMockupView(
              onAssetDropped: (target, asset, position) {
                // Show inline quick sheet at drop position
                _showQuickSheet(context, target, asset, position);
              },
            ),
          ),

          // LOWER ZONE (collapsible, resizable)
          Consumer<LowerZoneController>(
            builder: (context, controller, _) {
              return _LowerZone(controller: controller);
            },
          ),
        ],
      ),
    );
  }
}
```

### 15.6 Lower Zone Widget

```dart
class _LowerZone extends StatelessWidget {
  final LowerZoneController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header: Tabs + Collapse + Resize
        _LowerZoneHeader(controller: controller),

        // Content (animated)
        AnimatedContainer(
          duration: Duration(milliseconds: 200),
          height: controller.isExpanded ? controller.height : 0,
          curve: Curves.easeOutCubic,
          child: ClipRect(
            child: _LowerZoneContent(activeTab: controller.activeTab),
          ),
        ),
      ],
    );
  }
}

class _LowerZoneHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      color: Color(0xFF1a1a20),
      child: Row(
        children: [
          // Collapse/Expand
          IconButton(
            icon: Icon(
              controller.isExpanded ? Icons.expand_more : Icons.expand_less,
              size: 18,
            ),
            onPressed: controller.toggle,
          ),

          // Tabs
          _TabButton(tab: LowerZoneTab.timeline, label: 'Timeline', icon: Icons.timeline),
          _TabButton(tab: LowerZoneTab.commandBuilder, label: 'Command', icon: Icons.build),
          _TabButton(tab: LowerZoneTab.eventList, label: 'Events', icon: Icons.list),
          _TabButton(tab: LowerZoneTab.meters, label: 'Meters', icon: Icons.equalizer),

          Spacer(),

          // Resize handle
          GestureDetector(
            onVerticalDragUpdate: (d) => controller.setHeight(controller.height - d.delta.dy),
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeRow,
              child: Container(width: 60, child: Center(child: Text('⋯'))),
            ),
          ),
        ],
      ),
    );
  }
}

class _LowerZoneContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: activeTab.index,
      children: [
        StageTraceTimeline(),      // Timeline
        CommandBuilderPanel(),     // Command Builder
        EventListPanel(),          // Event List
        BusMetersPanel(),          // Meters
      ],
    );
  }
}
```

### 15.7 Inline Quick Sheet (Popup)

```dart
void _showQuickSheet(BuildContext context, Target target, Asset asset, Offset position) {
  final draft = context.read<AutoEventBuilderProvider>().createDraft(target, asset);

  showMenu(
    context: context,
    position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 280, position.dy + 180),
    items: [
      PopupMenuItem(
        enabled: false,
        child: _QuickSheetForm(
          draft: draft,
          onCommit: () {
            context.read<AutoEventBuilderProvider>().commitDraft();
            Navigator.pop(context);
          },
          onExpand: () {
            Navigator.pop(context);
            context.read<LowerZoneController>().switchTo(LowerZoneTab.commandBuilder);
          },
          onCancel: () {
            context.read<AutoEventBuilderProvider>().cancelDraft();
            Navigator.pop(context);
          },
        ),
      ),
    ],
  );
}

class _QuickSheetForm extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      padding: EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.music_note, size: 16, color: Colors.cyan),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  draft.eventId,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Divider(height: 16),

          // Trigger
          _DropdownField(
            label: 'Trigger',
            value: draft.trigger,
            items: draft.availableTriggers,
            onChanged: (v) => draft.trigger = v,
          ),

          // Bus (readonly)
          _ReadonlyField(label: 'Bus', value: draft.bus),

          // Preset
          _DropdownField(
            label: 'Preset',
            value: draft.presetId,
            items: presets.map((p) => p.id).toList(),
            onChanged: (v) => draft.presetId = v,
          ),

          SizedBox(height: 12),

          // Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: onExpand,
                child: Text('More...', style: TextStyle(fontSize: 12)),
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: onCancel,
                    child: Text('Cancel', style: TextStyle(fontSize: 12)),
                  ),
                  SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: onCommit,
                    autofocus: true,  // Enter = commit
                    child: Text('Commit', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

### 15.8 Drop Target Visual Feedback (GAP 18 FIX)

```dart
class DropTargetWidget extends StatefulWidget {
  final Target target;
  final Widget child;
  final Function(Asset, Offset) onAssetDropped;

  @override
  State<DropTargetWidget> createState() => _DropTargetWidgetState();
}

class _DropTargetWidgetState extends State<DropTargetWidget> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final eventCount = context.select<AutoEventBuilderProvider, int>(
      (p) => p.getEventCountForTarget(widget.target.targetId),
    );

    return DragTarget<Asset>(
      onWillAcceptWithDetails: (details) {
        setState(() => _isHovering = true);
        return true;
      },
      onLeave: (_) => setState(() => _isHovering = false),
      onAcceptWithDetails: (details) {
        setState(() => _isHovering = false);
        widget.onAssetDropped(details.data, details.offset);
      },
      builder: (context, candidateData, rejectedData) {
        return AnimatedContainer(
          duration: Duration(milliseconds: 150),
          decoration: BoxDecoration(
            border: Border.all(
              color: _isHovering ? Colors.cyan : Colors.transparent,
              width: 2,
            ),
            borderRadius: BorderRadius.circular(8),
            boxShadow: _isHovering
                ? [BoxShadow(color: Colors.cyan.withOpacity(0.3), blurRadius: 12)]
                : null,
          ),
          child: Stack(
            children: [
              widget.child,

              // Event count badge
              if (eventCount > 0)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$eventCount',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),

              // Drop preview tooltip (while hovering with asset)
              if (_isHovering && candidateData.isNotEmpty)
                Positioned(
                  bottom: -70,
                  left: 0,
                  child: _DropPreviewTooltip(
                    target: widget.target,
                    asset: candidateData.first!,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
```

### 15.9 Keyboard Shortcuts (UI)

| Shortcut | Action |
|----------|--------|
| `1` | Switch to Timeline tab |
| `2` | Switch to Command Builder tab |
| `3` | Switch to Event List tab |
| `4` | Switch to Meters tab |
| `` ` `` | Toggle lower zone collapse |
| `Cmd+↑` | Expand lower zone to max (500px) |
| `Cmd+↓` | Collapse lower zone |
| `Enter` | Commit draft (when Quick Sheet open) |
| `Esc` | Cancel draft / Close Quick Sheet |
| `Tab` | Expand Quick Sheet to Command Builder |

### 15.10 State Transitions

```
                     ┌──────────────────┐
                     │   Lower Zone     │
                     │   COLLAPSED      │
                     └─────────┬────────┘
                               │
           ┌───────────────────┼───────────────────┐
           │ click expand      │ drop asset        │ click spin
           ▼                   ▼                   ▼
 ┌──────────────────┐ ┌──────────────────┐ ┌──────────────────┐
 │ EXPANDED         │ │ EXPANDED         │ │ EXPANDED         │
 │ Last Active Tab  │ │ Command Builder  │ │ Timeline         │
 └──────────────────┘ └──────────────────┘ └──────────────────┘
```

### 15.11 Benefits

| Aspect | Benefit |
|--------|---------|
| **Context** | Mockup always visible — you know where you are |
| **Speed** | 3 seconds for 90% of operations |
| **Depth** | Pro mode accessible without new window |
| **Muscle memory** | Drop → Enter becomes reflex |
| **Professional pattern** | Wwise/FMOD designers already know this flow |
| **Zero context switch** | Never lose focus |

---

## 16) Summary

### 16.1 All Gaps Resolved

| Gap | Description | Resolution |
|-----|-------------|------------|
| GAP 1 | Bus hierarchy | Full hierarchy with MASTER→SFX→children |
| GAP 2 | Sidechain source | Explicit `sidechainSource` in ducking |
| GAP 3 | Loudness normalization | `loudnessInfo` in Asset model |
| GAP 4 | Music crossfade | `transitionPolicy`, `crossfadeMs`, `crossfadeType` |
| GAP 5 | Voice stealing | `voiceStealPolicy`, `voiceStealFadeMs` |
| GAP 6 | Timing precision | `timingPrecision`, `preTriggerMs` |
| GAP 7 | RTPC integration | `rtpcBindings` array in presets |
| GAP 8 | Per-reel spatial | `spatialMode: auto_per_reel` |
| GAP 9 | Asset preload | `preloadPolicy`, `memoryBudgetBytes` |
| GAP 10 | Event pooling | `EventInstancePool` class |
| GAP 11 | Manifest versioning | `manifestVersion`, `minRuntimeVersion` |
| GAP 12 | Batch transaction | `ManifestTransaction` class |
| GAP 13 | Undo/Redo | `UndoManager` + command pattern |
| GAP 14 | Event dependencies | `dependencies` object in Event |
| GAP 15 | Conditional triggers | `conditions` array in Event |
| GAP 16 | Template inheritance | `extends` + `overrides` in presets |
| GAP 17 | Keyboard shortcuts | Full shortcut map |
| GAP 18 | Drop preview | Tooltip with preview info |
| GAP 19 | Bulk edit | Multi-select + bulk apply panel |
| GAP 20 | Search/filter | Search bar + filter dropdowns |
| GAP 21 | Waveform preview | Mini waveform in dropdowns |
| GAP 22 | Bus meters | Live meters during audition |
| GAP 23 | Loop visualization | Timeline with loop markers |
| GAP 24 | Binding graph | Optional graph view |
| GAP 25 | Input sanitization | `sanitizeAssetPath()` |
| GAP 26 | eventId collision | `generateEventId()` with suffix |
| GAP 27 | Manifest integrity | SHA-256 checksum |
| GAP 28 | Rate limiting | `DropRateLimiter` class |

### 16.2 Implementation Priority

| Phase | Components | Priority |
|-------|------------|----------|
| **Phase 1** | Bus hierarchy, voice stealing, manifest versioning, input sanitization, eventId collision, manifest integrity, asset preload | CRITICAL |
| **Phase 2** | Undo/redo, conditional triggers, sidechain source, timing precision, batch transaction | HIGH |
| **Phase 3** | Loudness normalization, music crossfade, RTPC integration, event pooling, dependencies, UX improvements (17-24), rate limiting | MEDIUM |
| **Phase 4** | Per-reel spatial, template inheritance | LOW |

### 16.3 File Structure

```
flutter_ui/lib/
├── providers/
│   └── auto_event_builder_provider.dart
├── services/
│   ├── rule_engine.dart
│   ├── event_generator.dart
│   ├── commit_engine.dart
│   ├── manifest_validator.dart
│   ├── undo_manager.dart
│   ├── event_instance_pool.dart
│   └── drop_rate_limiter.dart
├── models/
│   ├── asset.dart
│   ├── target.dart
│   ├── event.dart
│   ├── binding.dart
│   ├── preset.dart
│   ├── rule.dart
│   └── manifest.dart
├── widgets/
│   └── auto_event_builder/
│       ├── quick_sheet.dart
│       ├── command_builder.dart
│       ├── drop_preview.dart
│       ├── bulk_edit_panel.dart
│       ├── search_filter.dart
│       ├── bus_meters.dart
│       └── binding_graph.dart
└── data/
    ├── drop_rules.json
    ├── presets.json
    ├── command_templates.json
    └── bus_hierarchy.json
```

---

## 17) Conclusion

This specification is **100% complete** and ready for implementation.

**Key Principles:**
1. **Data-driven** — All rules, presets, templates in JSON
2. **Draft-Commit** — No immediate side effects
3. **Undoable** — Full undo/redo support
4. **Validated** — Comprehensive validation layer
5. **Secure** — Input sanitization, integrity checks
6. **Performant** — Pooling, rate limiting, batch ops
7. **Professional UX** — Keyboard shortcuts, previews, bulk ops
8. **Integrated UI** — Everything on one screen, collapsible panels, zero context switch

**Sections:**
1. Core Objects (Asset, Target, Event, Binding)
2. Bus Hierarchy (MASTER→SFX→children)
3. Preset Library (Complete with all fixes)
4. Trigger Vocabulary
5. DropRules System
6. Manifest System (versioning + integrity)
7. Undo/Redo System
8. Engine Systems (pooling, batch, rate limiting)
9. UX Features (shortcuts, preview, bulk edit, search)
10. Visualization (waveform, meters, timeline, graph)
11. Validation Layer
12. Command Builder (Pro mode)
13. Standard Target Map
14. Implementation Architecture
15. **SlotLab UI Layout** (integrated design, collapsible lower zone)
16. Summary (28 gaps resolved)
17. Conclusion

---

## 18) Implementation Progress

### 18.1 Phase 1 Core Foundation — ✅ COMPLETED (2026-01-21)

| Component | File | Status | Notes |
|-----------|------|--------|-------|
| **LowerZoneController** | `controllers/slot_lab/lower_zone_controller.dart` | ✅ Done | Enum, ChangeNotifier, keyboard shortcuts, serialization |
| **LowerZone Widget** | `widgets/slot_lab/lower_zone/lower_zone.dart` | ✅ Done | Header, tabs, content, resize handle, animations |
| **CommandBuilderPlaceholder** | `widgets/slot_lab/lower_zone/command_builder_placeholder.dart` | ✅ Done | Placeholder UI |
| **EventListPlaceholder** | `widgets/slot_lab/lower_zone/event_list_placeholder.dart` | ✅ Done | Placeholder UI |
| **MetersPlaceholder** | `widgets/slot_lab/lower_zone/meters_placeholder.dart` | ✅ Done | Mock meters UI |
| **SlotLabScreen Integration** | `screens/slot_lab_screen.dart` | ✅ Done | Provider wrapper, init/dispose, backtick shortcut |

**LowerZoneController Features:**
- `LowerZoneTab` enum: timeline, commandBuilder, eventList, meters
- Tab configs with labels, icons, shortcuts
- Expand/collapse with animation (200ms, easeOutCubic)
- Resizable height (100-500px) with drag handle
- Auto-expand when switching tabs
- Toggle collapse when clicking active tab
- Backtick keyboard shortcut for toggle
- JSON serialization for state persistence

**LowerZone Widget Features:**
- Animated resize handle with hover feedback
- Tab buttons with active state and shortcut hints
- Height indicator (px) when expanded
- IndexedStack for efficient tab switching
- StageTraceWidget integration for Timeline tab

### 18.2 Phase 2 Complete — Core Models & Provider ✅

**Completed:** 2026-01-21

| Component | File | Status | Description |
|-----------|------|--------|-------------|
| **AudioAsset Model** | `models/auto_event_builder_models.dart` | ✅ Done | Path sanitization (GAP 25), loudness info (GAP 3) |
| **DropTarget Model** | `models/auto_event_builder_models.dart` | ✅ Done | 10 target types, stage context |
| **EventPreset System** | `models/auto_event_builder_models.dart` | ✅ Done | 12 standard presets |
| **DropRule Engine** | `models/auto_event_builder_models.dart` | ✅ Done | 11 standard rules, priority matching |
| **AutoEventBuilderProvider** | `providers/auto_event_builder_provider.dart` | ✅ Done | Draft management, undo/redo (GAP 13) |
| **QuickSheet Popup** | `widgets/slot_lab/auto_event_builder/quick_sheet.dart` | ✅ Done | Inline popup, keyboard shortcuts |

**Key Features Implemented:**

**AudioAsset:**
- Path sanitization (blocks `..` traversal, validates extensions)
- Auto-detect asset type from path (`sfx/`, `music/`, `vo/`, `amb/`)
- Auto-extract tags from path components
- Optional loudness info (integrated, LUFS, true peak)

**DropTarget (10 types):**
- `spinButton`, `reelArea`, `reelColumn`, `symbolArea`
- `winDisplay`, `featureTrigger`, `bonusArea`, `uiButton`
- `background`, `custom`

**EventPreset (12 presets):**
- `oneShot`, `looping`, `layered`, `randomContainer`
- `sequenceContainer`, `anticipationLoop`, `winCelebration`
- `featureMusic`, `uiConfirm`, `uiHover`, `ambientLoop`, `custom`

**DropRule Engine:**
- Priority-based matching (higher priority wins)
- Asset type + target type conditions
- Tag-based conditions (contains, does not contain)
- Event ID template generation with placeholders

**AutoEventBuilderProvider:**
- Draft-commit pattern (no immediate side effects)
- `createDraft()` → `updateDraft()` → `commitDraft()`
- Unique event ID generation with collision prevention (GAP 26)
- Full undo/redo system (GAP 13)
- Custom rules management

**QuickSheet Popup:**
- Inline popup at drop position
- Event ID preview (editable)
- Trigger dropdown
- Bus field (readonly, auto-populated)
- Preset dropdown
- Keyboard shortcuts: Enter=Commit, Esc=Cancel, Tab=Expand

### 18.3 Phase 3 Complete — Command Builder Panel ✅

**Completed:** 2026-01-21

| Component | File | Status | Description |
|-----------|------|--------|-------------|
| **CommandBuilderPanel** | `widgets/slot_lab/lower_zone/command_builder_panel.dart` | ✅ Done | Full parameter editor |

**CommandBuilderPanel Features:**

**Left Panel (Asset Info):**
- Asset icon + name with type-based coloring
- Target info display (name, type, context)
- Tags display with wrap layout

**Center Panel (Main Parameters):**
- Event ID field (editable, monospace)
- Trigger dropdown (from target's available triggers)
- Bus field (readonly, auto-populated)
- Preset dropdown (all standard + custom presets)
- Variation policy dropdown

**Advanced Section (Expandable):**
- Volume, Pitch, Pan display
- Timing params (delay, fade in/out)
- Voice settings (polyphony, cooldown, priority)

**Right Panel (Actions):**
- Commit Event button (green)
- Cancel button
- Undo/Redo controls with tooltips
- Stats display (events count, bindings count)

**Empty State:**
- Instructions (1-2-3 steps)
- Recent events list (last 5)
- Delete event action

### 18.4 Phase 4 Complete — Drop Targets & Event List ✅

**Completed:** 2026-01-21

| Component | File | Status | Description |
|-----------|------|--------|-------------|
| **DropTargetWrapper** | `widgets/slot_lab/auto_event_builder/drop_target_wrapper.dart` | ✅ Done | Visual feedback wrapper |
| **DraggableAudioAsset** | `widgets/slot_lab/auto_event_builder/drop_target_wrapper.dart` | ✅ Done | Draggable asset wrapper |
| **SlotLabDropTargets** | `widgets/slot_lab/auto_event_builder/drop_target_wrapper.dart` | ✅ Done | Predefined target factory |
| **EventListPanel** | `widgets/slot_lab/lower_zone/event_list_panel.dart` | ✅ Done | Full event browser |

**DropTargetWrapper Features:**
- Hover glow effect with target-type coloring
- Pulse animation on successful drop
- Event count badge (top-right by default)
- Target type indicator on drag-over
- Drop overlay with "Drop to create event" message
- Integrates with QuickSheet for immediate event creation

**DraggableAudioAsset Features:**
- Wraps any widget to make it draggable
- Default drag feedback with asset icon/name
- Custom feedback support
- Drag started/ended callbacks

**SlotLabDropTargets Factory:**
- `spinButton()` — Primary spin button
- `autoSpinButton()` — Auto-spin toggle
- `reelSurface()` — Entire reel area
- `reelStopZone(index)` — Individual reel columns
- `winDisplay(tier)` — Win celebration overlays
- `featureTrigger(name)` — Feature trigger areas
- `balanceCounter()` — HUD balance display
- `uiButton(id)` — Generic UI buttons

**EventListPanel Features:**
- Search by event ID, bus, tags
- Filter by bus type (dropdown)
- Sort by name/bus/date (asc/desc)
- Multi-select with checkboxes
- Bulk delete action
- Event details: ID, bus, binding count, tags
- Hover actions (delete button)
- Empty state with instructions

---

## 19) API Reference — Implemented Components

### 19.1 Models (`auto_event_builder_models.dart`)

#### AssetType Enum
```dart
enum AssetType { sfx, music, vo, amb }

extension AssetTypeExtension on AssetType {
  String get displayName;    // 'SFX', 'Music', 'Voice', 'Ambience'
  String get defaultBus;     // 'SFX', 'MUSIC/Base', 'VO', 'AMB'
  static AssetType fromString(String s);
}
```

#### LoudnessInfo Class (GAP 3)
```dart
class LoudnessInfo {
  final double integratedLufs;  // -16.0 default
  final double truePeak;         // -1.0 default
  final double normalizeTarget;  // -14.0 default
  final double normalizeGain;    // computed

  factory LoudnessInfo.computed({
    required double integratedLufs,
    required double truePeak,
    double normalizeTarget = -14.0,
  });
}
```

#### AudioAsset Class
```dart
class AudioAsset {
  final String assetId;
  final String path;           // Sanitized
  final AssetType assetType;
  final List<String> tags;
  final bool isLoop;
  final int durationMs;
  final List<String> variants;
  final LoudnessInfo loudnessInfo;

  String get displayName;      // Filename without extension
  String get extension;        // File extension

  static String sanitizePath(String rawPath);  // GAP 25 fix
  factory AudioAsset.fromPath(String rawPath, {String? assetId});

  bool hasAnyTag(List<String> checkTags);
  bool hasAllTags(List<String> checkTags);
}
```

#### TargetType Enum (10 types)
```dart
enum TargetType {
  uiButton,         // Spin, AutoSpin, Turbo buttons
  uiToggle,         // Toggle buttons
  hudCounter,       // Balance, bet, win displays
  hudMeter,         // Progress bars, meters
  reelSurface,      // Entire reel area
  reelStopZone,     // Individual reel stop positions
  symbol,           // Symbol elements
  overlay,          // Win overlays, popups
  featureContainer, // Feature UI containers
  screenZone,       // General screen areas
}

extension TargetTypeExtension on TargetType {
  String get displayName;
  List<String> get defaultTriggers;
}
```

#### StageContext Enum
```dart
enum StageContext { global, baseGame, freeSpins, bonus, holdWin }
```

#### DropTarget Class
```dart
class DropTarget {
  final String targetId;       // e.g., "ui.spin", "reel.1"
  final TargetType targetType;
  final List<String> targetTags;
  final StageContext stageContext;
  final List<String> interactionSemantics;

  String get displayName;
  List<String> get availableTriggers;
  bool hasAnyTag(List<String> checkTags);
}
```

#### VariationPolicy Enum
```dart
enum VariationPolicy { random, roundRobin, shuffleBag, sequential, weighted }
```

#### VoiceStealPolicy Enum (GAP 5)
```dart
enum VoiceStealPolicy { none, oldest, quietest, lowestPriority, farthest }
```

#### PreloadPolicy Enum (GAP 9)
```dart
enum PreloadPolicy { onCommit, onStageEnter, onFirstTrigger, manual }
```

#### EventPreset Class
```dart
class EventPreset {
  final String presetId;
  final String name;
  final String? description;

  // Audio parameters
  final double volume;      // -60 to +12 dB
  final double pitch;       // 0.5 to 2.0
  final double pan;         // -1.0 to +1.0
  final double lpf;         // Low-pass filter cutoff
  final double hpf;         // High-pass filter cutoff

  // Timing
  final int delayMs;
  final int fadeInMs;
  final int fadeOutMs;
  final int cooldownMs;

  // Voice management
  final int polyphony;
  final String voiceLimitGroup;
  final VoiceStealPolicy voiceStealPolicy;
  final int voiceStealFadeMs;

  final int priority;       // 0-100
  final PreloadPolicy preloadPolicy;
}
```

#### StandardPresets Class
```dart
class StandardPresets {
  static const uiClickPrimary;    // Main button clicks
  static const uiClickSecondary;  // Secondary button clicks
  static const uiHover;           // Hover feedback
  static const reelSpin;          // Reel spinning loop
  static const reelStop;          // Reel stop impact
  static const anticipation;      // Near-win tension
  static const winSmall;          // Minor win
  static const winBig;            // Major win
  static const bigwinTier;        // Tier escalation
  static const jackpot;           // Jackpot win
  static const musicBase;         // Background music
  static const musicFeature;      // Feature music

  static const List<EventPreset> all;
  static EventPreset? getById(String presetId);
}
```

#### DropRule Class
```dart
class DropRule {
  final String ruleId;
  final String name;
  final int priority;

  // Match conditions
  final List<String> assetTags;
  final List<String> targetTags;
  final AssetType? assetType;
  final TargetType? targetType;

  // Output templates
  final String eventIdTemplate;   // e.g., "{target}.{asset}"
  final String intentTemplate;
  final String defaultPresetId;
  final String defaultBus;
  final String defaultTrigger;

  bool matches(AudioAsset asset, DropTarget target);
  String generateEventId(AudioAsset asset, DropTarget target);
  String generateIntent(AudioAsset asset, DropTarget target);
}
```

#### StandardDropRules Class
```dart
class StandardDropRules {
  static const uiPrimaryClick;    // priority: 100
  static const uiSecondaryClick;  // priority: 90
  static const uiHover;           // priority: 80
  static const reelSpin;          // priority: 100
  static const reelStop;          // priority: 100
  static const anticipation;      // priority: 100
  static const winSmall;          // priority: 90
  static const winBig;            // priority: 100
  static const musicBase;         // priority: 100
  static const musicFeature;      // priority: 100
  static const fallbackSfx;       // priority: 1

  static List<DropRule> get all;  // Sorted by priority (highest first)
}
```

### 19.2 Provider (`auto_event_builder_provider.dart`)

#### EventDraft Class
```dart
class EventDraft {
  String eventId;
  final DropTarget target;
  final AudioAsset asset;
  String trigger;
  String bus;
  String presetId;
  StageContext stageContext;
  VariationPolicy variationPolicy;
  List<String> tags;
  Map<String, dynamic> paramOverrides;

  bool get isModified;
  void markModified();
  List<String> get availableTriggers;
}
```

#### CommittedEvent Class
```dart
class CommittedEvent {
  final String eventId;
  final String intent;
  final String assetPath;
  final String bus;
  final String presetId;
  final String voiceLimitGroup;
  final VariationPolicy variationPolicy;
  final List<String> tags;
  final Map<String, dynamic> parameters;
  final PreloadPolicy preloadPolicy;
  final DateTime createdAt;
  final DateTime? modifiedAt;
}
```

#### EventBinding Class
```dart
class EventBinding {
  final String bindingId;
  final String eventId;
  final String targetId;
  final String stageId;
  final String trigger;
  final Map<String, dynamic> paramOverrides;
  final bool enabled;
}
```

#### AutoEventBuilderProvider Class
```dart
class AutoEventBuilderProvider extends ChangeNotifier {
  // Getters
  EventDraft? get currentDraft;
  bool get hasDraft;
  List<CommittedEvent> get events;
  List<EventBinding> get bindings;
  List<EventPreset> get presets;
  bool get canUndo;
  bool get canRedo;

  // Draft management
  EventDraft createDraft(AudioAsset asset, DropTarget target);
  void updateDraft({...});
  CommittedEvent? commitDraft();
  void cancelDraft();

  // Event management
  void deleteEvent(String eventId);
  int getEventCountForTarget(String targetId);
  List<CommittedEvent> getEventsForTarget(String targetId);

  // Undo/Redo (GAP 13)
  bool undo();
  bool redo();

  // Presets
  void addPreset(EventPreset preset);
  void removePreset(String presetId);

  // Rules
  void addRule(DropRule rule);
  void removeRule(String ruleId);

  // Serialization
  Map<String, dynamic> toJson();
  void fromJson(Map<String, dynamic> json);
  void clear();
}
```

### 19.3 Widgets

#### DropTargetWrapper (`drop_target_wrapper.dart`)
```dart
class DropTargetWrapper extends StatefulWidget {
  final Widget child;
  final DropTarget target;
  final bool showBadge;           // default: true
  final Alignment badgeAlignment; // default: topRight
  final Color? glowColor;
  final void Function(CommittedEvent)? onEventCreated;
}
```

#### DraggableAudioAsset (`drop_target_wrapper.dart`)
```dart
class DraggableAudioAsset extends StatelessWidget {
  final Widget child;
  final AudioAsset asset;
  final Widget? feedback;
  final VoidCallback? onDragStarted;
  final VoidCallback? onDragEnd;
}
```

#### SlotLabDropTargets Factory (`drop_target_wrapper.dart`)
```dart
class SlotLabDropTargets {
  static DropTarget spinButton({StageContext context});
  static DropTarget autoSpinButton({StageContext context});
  static DropTarget reelSurface({StageContext context});
  static DropTarget reelStopZone(int reelIndex, {StageContext context});
  static DropTarget winDisplay({String tier, StageContext context});
  static DropTarget featureTrigger(String featureName, {StageContext context});
  static DropTarget balanceCounter({StageContext context});
  static DropTarget uiButton(String buttonId, {List<String> tags, StageContext context});
}
```

#### QuickSheet (`quick_sheet.dart`)
```dart
void showQuickSheet({
  required BuildContext context,
  required AudioAsset asset,
  required DropTarget target,
  required Offset position,
  VoidCallback? onCommit,
  VoidCallback? onExpand,
  VoidCallback? onCancel,
});
```

---

### 18.5 Phase 5 Complete — Finalization ✅

**All core components implemented. System ready for integration.**

| Component | File | Status | Description |
|-----------|------|--------|-------------|
| **BusMetersPanel** | `lower_zone/bus_meters_panel.dart` | ✅ | Live audio bus meters with peak hold, RMS |
| **PresetEditorPanel** | `auto_event_builder/preset_editor_panel.dart` | ✅ | Full preset creation/editing UI |
| **RuleEditorPanel** | `auto_event_builder/rule_editor_panel.dart` | ✅ | Custom drop rule creation UI |
| **Export/Import** | `auto_event_builder_provider.dart` | ✅ | JSON manifest export/import |

#### 18.5.1 BusMetersPanel Features

- 4 bus meters (SFX, Music, Voice, Ambience) + stereo Master
- 60fps smooth animation with level smoothing
- Peak hold (2 seconds) with decay
- RMS averaging
- Clip indicators
- Simulated values (ready for FFI integration)

#### 18.5.2 PresetEditorPanel Features

- Volume, pitch, pan controls (-60dB to +12dB, ±24 semitones)
- Fade in/out (0-2000ms)
- Loop toggle
- Low-pass/High-pass filter controls
- Voice stealing policy selector
- Preload policy selector
- Priority level (0-100)
- Cancel/Save actions

#### 18.5.3 RuleEditorPanel Features

- Rule name and priority
- Match conditions (asset type, tags, target type, target tags)
- Output template settings (intent format, bus routing)
- Preset assignment dropdown
- Enabled toggle
- Cancel/Save actions

#### 18.5.4 Export/Import Features

```dart
// Export full manifest
Map<String, dynamic> exportManifest() // → version, events, bindings, presets, rules

// Import with optional merge
void importManifest(Map<String, dynamic> manifest, {bool merge = false})

// Export single target's events
Map<String, dynamic> exportEventsForTarget(String targetId)

// Get statistics
Map<String, int> getStatistics() // → events, bindings, drafts, presets, rules
```

### 18.6 File Structure (ALL PHASES COMPLETE)

```
flutter_ui/lib/
├── controllers/
│   └── slot_lab/
│       ├── lower_zone_controller.dart    ✅ Phase 1
│       └── timeline_drag_controller.dart (existing)
├── models/
│   └── auto_event_builder_models.dart    ✅ Phase 2
├── providers/
│   └── auto_event_builder_provider.dart  ✅ Phase 2 + 5 (export/import)
├── widgets/
│   └── slot_lab/
│       ├── lower_zone/
│       │   ├── lower_zone.dart           ✅ Phase 1
│       │   ├── command_builder_panel.dart        ✅ Phase 3
│       │   ├── event_list_panel.dart             ✅ Phase 4 (replaced placeholder)
│       │   ├── bus_meters_panel.dart             ✅ Phase 5 NEW (replaced placeholder)
│       │   └── meters_placeholder.dart           (legacy, unused)
│       └── auto_event_builder/
│           ├── quick_sheet.dart          ✅ Phase 2
│           ├── drop_target_wrapper.dart  ✅ Phase 4
│           ├── preset_editor_panel.dart  ✅ Phase 5 NEW
│           └── rule_editor_panel.dart    ✅ Phase 5 NEW
└── screens/
    └── slot_lab_screen.dart              ✅ Phase 2 MODIFIED
```

### 18.7 Phase 6 Complete — UI Integration ✅

**Auto Event Builder tabs integrated into SlotLab bottom panel.**

| Task | Status | Description |
|------|--------|-------------|
| Add tabs to bottom panel | ✅ | Added Command Builder, Events, Meters tabs |
| Create AutoEventBuilderProvider instance | ✅ | Initialized in initState, disposed in dispose |
| Wire up content widgets | ✅ | CommandBuilderPanel, EventListPanel, BusMetersPanel |

#### 18.7.1 New Bottom Panel Tabs

```dart
enum _BottomPanelTab {
  // Existing tabs...
  commandBuilder,  // Auto Event Builder command editor
  eventList,       // Committed events browser
  meters,          // Live audio bus meters
}
```

#### 18.7.2 Tab Labels

| Tab | Label | Content Widget |
|-----|-------|----------------|
| `commandBuilder` | "Command Builder" | `CommandBuilderPanel` |
| `eventList` | "Events" | `EventListPanel` |
| `meters` | "Meters" | `BusMetersPanel` |

### 18.8 Phase 7 Complete — FFI & Shortcuts ✅

**BusMeters connected to MeterProvider. Keyboard shortcuts implemented.**

#### 18.8.1 BusMeters FFI Integration

| Feature | Status | Description |
|---------|--------|-------------|
| `MeterProvider` integration | ✅ | Uses `context.watch<MeterProvider>()` |
| Real-time levels | ✅ | Peak, RMS, peak hold from provider |
| Bus index mapping | ✅ | sfx=0, music=1, voice=2, ambience=3, master=5 |
| Connection indicator | ✅ | Shows "LIVE" (green) or "OFFLINE" (gray) |
| Fallback mode | ✅ | Works without provider (static meters) |

#### 18.8.2 Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `` ` `` (backtick) | Toggle bottom panel collapse |
| `Ctrl+Shift+C` | Switch to Command Builder tab |
| `Ctrl+Shift+E` | Switch to Events tab |
| `Ctrl+Shift+M` | Switch to Meters tab |
| `Ctrl+Shift+T` | Switch to Timeline tab |
| `Ctrl+Shift+L` | Switch to Event Log tab |

### 18.9 Next Steps — Final Polish

| Task | Priority | Description |
|------|----------|-------------|
| Persistence | MEDIUM | Save/load user presets and rules |
| Drag-drop from browser | LOW | Direct asset drag to drop targets |
| Tooltip hints | LOW | Show shortcuts in tab tooltips |

---

**Last Updated:** 2026-01-21
**Version:** 1.7 (Phase 7 Complete — FFI & Shortcuts)
