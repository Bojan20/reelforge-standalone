# Premium Slot Preview V2 — Extended Features Spec

**Created:** 2026-01-31
**Status:** SPEC READY
**Target:** `premium_slot_preview.dart`

---

## Overview

Proširenje PremiumSlotPreview sa 4 nova feature-a za kompletno testiranje:

1. **Device Simulation Mode** — Mobile/Tablet/Desktop preview
2. **A/B Theme Testing** — Brza promena vizuelnih tema
3. **Recording Mode** — Snimanje demo videa
4. **Debug Toolbar** — Quick access za QA

---

## 1. Device Simulation Mode

### Problem
Audio dizajneri moraju testirati kako slot izgleda i zvuči na različitim uređajima.

### Solution

```dart
enum DeviceSimulation {
  desktop,    // Full size (no constraints)
  tablet,     // 1024x768 (iPad)
  mobileLandscape,  // 844x390 (iPhone 14 Pro landscape)
  mobilePortrait,   // 390x844 (iPhone 14 Pro portrait)
}
```

### UI
- Dropdown u header-u: 📱 [Desktop ▼]
- Preview area se skalira/ograničava na odabranu rezoluciju
- Bezels/frame oko preview-a simulira uređaj

### Visual Mockup
```
┌─────────────────────────────────────────────────────┐
│ [📱 Desktop ▼] [🎨 Theme A ▼] [⏺ REC]    [✕ Exit] │
├─────────────────────────────────────────────────────┤
│                                                     │
│   ┌─────────────────────────────────────────────┐   │
│   │                                             │   │
│   │        SLOT PREVIEW (scaled)                │   │
│   │                                             │   │
│   │   [Simulated device frame if mobile]        │   │
│   │                                             │   │
│   └─────────────────────────────────────────────┘   │
│                                                     │
└─────────────────────────────────────────────────────┘
```

### State
```dart
DeviceSimulation _deviceSimulation = DeviceSimulation.desktop;
```

### Implementation
```dart
Widget _buildDeviceFrame(Widget child) {
  switch (_deviceSimulation) {
    case DeviceSimulation.desktop:
      return child; // No frame, full size
    case DeviceSimulation.tablet:
      return _buildTabletFrame(child, Size(1024, 768));
    case DeviceSimulation.mobileLandscape:
      return _buildPhoneFrame(child, Size(844, 390), isLandscape: true);
    case DeviceSimulation.mobilePortrait:
      return _buildPhoneFrame(child, Size(390, 844), isLandscape: false);
  }
}

Widget _buildPhoneFrame(Widget child, Size size, {required bool isLandscape}) {
  return Center(
    child: Container(
      width: size.width + 40, // Bezel
      height: size.height + 80, // Bezel + notch
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: Colors.grey.shade800, width: 3),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(36),
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
}
```

---

## 2. A/B Theme Testing

### Problem
Dizajneri žele brzo testirati različite vizuelne teme bez restarta.

### Solution

```dart
enum SlotThemePreset {
  casino,      // Current dark casino theme
  neon,        // Cyberpunk neon
  royal,       // Gold & purple luxury
  nature,      // Green & wood organic
  retro,       // 80s arcade
  minimal,     // Clean white
}
```

### UI
- Dropdown u header-u: 🎨 [Casino ▼]
- Instant theme switch (no restart)
- Side-by-side comparison mode (split screen)

### Comparison Mode
```
┌────────────────────┬────────────────────┐
│                    │                    │
│   THEME A          │   THEME B          │
│   (Casino)         │   (Neon)           │
│                    │                    │
│   [Same spin       │   [Same spin       │
│    result]         │    result]         │
│                    │                    │
└────────────────────┴────────────────────┘
        [🔀 Swap]  [✅ Select A]  [✅ Select B]
```

### State
```dart
SlotThemePreset _themeA = SlotThemePreset.casino;
SlotThemePreset? _themeB; // null = no comparison
bool _showComparison = false;
```

### Theme Data
```dart
class SlotThemeData {
  final Color bgDeep;
  final Color bgDark;
  final Color bgMid;
  final Color bgSurface;
  final Color gold;
  final Color accent;
  final Color winSmall;
  final Color winBig;
  final Color winMega;
  final Color winEpic;
  final Color winUltra;
  final List<Color> jackpotColors;
  final TextStyle tierLabelStyle;
  final BoxDecoration reelFrameDecoration;

  const SlotThemeData({...});

  static const casino = SlotThemeData(...);
  static const neon = SlotThemeData(...);
  // etc.
}
```

---

## 3. Recording Mode

### Problem
Produceri i QA trebaju snimiti demo videe za dokumentaciju/prezentacije.

### Solution
- Platform native screen recording via MethodChannel
- Overlay indicators (REC badge, timer)
- Auto-hide UI chrome option

### UI
```
Normal:   [⏺ REC]
Recording: [⏹ 00:15] (pulsing red dot)
```

### State
```dart
bool _isRecording = false;
Duration _recordingDuration = Duration.zero;
Timer? _recordingTimer;
bool _hideUiForRecording = false;
```

### Implementation
```dart
// Platform channel for native recording
static const _recordingChannel = MethodChannel('fluxforge/screen_recording');

Future<void> _startRecording() async {
  final path = await _recordingChannel.invokeMethod<String>('startRecording', {
    'filename': 'slot_demo_${DateTime.now().toIso8601String()}.mp4',
    'fps': 60,
    'quality': 'high',
  });
  setState(() {
    _isRecording = true;
    _recordingDuration = Duration.zero;
  });
  _recordingTimer = Timer.periodic(Duration(seconds: 1), (_) {
    setState(() => _recordingDuration += Duration(seconds: 1));
  });
}

Future<String?> _stopRecording() async {
  _recordingTimer?.cancel();
  final path = await _recordingChannel.invokeMethod<String>('stopRecording');
  setState(() => _isRecording = false);
  return path; // Path to saved video
}
```

### Fallback (No Native)
- Show "Recording not available on this platform"
- Or: Export sequence of screenshots as GIF

---

## 4. Debug Toolbar

### Problem
QA inženjeri trebaju brz pristup debug alatima bez napuštanja preview-a.

### Solution
Collapsible toolbar sa:
- Forced outcomes (1-0 keys, sada i kao buttons)
- Stage trace toggle
- FPS counter
- Memory usage
- Active voices count

### UI
```
┌─────────────────────────────────────────────────────┐
│ 🔧 DEBUG  [Lose][Small][Big][Mega][FS][JP]  60fps  │
│           Voices: 12/48  Mem: 124MB  Stages: ▶     │
└─────────────────────────────────────────────────────┘
```

### State
```dart
bool _showDebugToolbar = false; // Toggle with D key
bool _showFpsCounter = true;
bool _showVoiceCount = true;
bool _showMemoryUsage = true;
bool _showStageTrace = false;
```

---

## 5. Consolidated Settings Panel

### Current
`_AudioVisualPanel` — samo audio/visual settings

### New: `_SettingsPanel` — sve na jednom mestu

```
┌─────────────────────────────────────────┐
│ ⚙️ SETTINGS                        [✕] │
├─────────────────────────────────────────┤
│ 📱 DEVICE                               │
│ ┌─────────────────────────────────────┐ │
│ │ Desktop │ Tablet │ Mobile-L │ Mobile│ │
│ └─────────────────────────────────────┘ │
├─────────────────────────────────────────┤
│ 🎨 THEME                                │
│ [Casino ▼]  [Compare: None ▼]           │
├─────────────────────────────────────────┤
│ 🔊 AUDIO                                │
│ Master: ═══════════●══ 80%              │
│ [🎵 Music] [🔊 SFX]                     │
├─────────────────────────────────────────┤
│ 🎬 RECORDING                            │
│ [⏺ Start Recording]                    │
│ ☐ Hide UI during recording              │
├─────────────────────────────────────────┤
│ 🔧 DEBUG                                │
│ ☐ Show FPS   ☐ Show Voices              │
│ ☐ Show Memory ☐ Stage Trace             │
└─────────────────────────────────────────┘
```

---

## Implementation Plan

### Phase 1: Device Simulation (~200 LOC)
- Add `DeviceSimulation` enum
- Add `_buildDeviceFrame()` method
- Add device selector dropdown in header

### Phase 2: Theme System (~400 LOC)
- Add `SlotThemeData` class with 6 presets
- Add `_themeA`, `_themeB` state
- Add theme selector dropdown
- Refactor `_SlotTheme` to use `SlotThemeData`

### Phase 3: A/B Comparison (~300 LOC)
- Add split-screen layout
- Add sync between A/B (same spin result)
- Add swap/select buttons

### Phase 4: Recording Mode (~250 LOC)
- Add platform channel stubs
- Add recording UI (badge, timer)
- Add "hide UI" option

### Phase 5: Debug Toolbar (~200 LOC)
- Add collapsible toolbar widget
- Add forced outcome buttons
- Add real-time stats (FPS, voices, memory)

### Phase 6: Consolidated Settings (~150 LOC)
- Merge all settings into one panel
- Remove old `_AudioVisualPanel`

### Phase 7: Remove fullscreen_slot_preview.dart (~-2000 LOC)
- Delete file
- Update all imports
- Update slot_lab_screen.dart references

---

## Total Estimate

| Phase | LOC Added | LOC Removed | Net |
|-------|-----------|-------------|-----|
| 1-6   | ~1,500    | ~200        | +1,300 |
| 7     | 0         | ~2,000      | -2,000 |
| **Total** | **~1,500** | **~2,200** | **-700** |

**Result:** Net reduction of ~700 LOC while adding 4 major features.

---

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| D | Toggle debug toolbar |
| R | Start/stop recording |
| T | Cycle themes (A→B→A) |
| 1-9,0 | Forced outcomes |
| M | Toggle music |
| S | Toggle SFX |
| ESC | Close panel / Exit |
| SPACE | Spin / Stop |

---

## Dependencies

- No new packages required
- Platform channel for recording (optional, graceful fallback)
- SharedPreferences for settings persistence (already used)

---

*Created 2026-01-31*
