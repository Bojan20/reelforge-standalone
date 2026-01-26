# SlotLab Development Roadmap

**Datum kreiranja:** 2026-01-21
**Status:** Active Development

---

## Pregled Faza

| Faza | Fokus | Status |
|------|-------|--------|
| **Phase 1** | Timeline UX Polish | 🔄 In Progress |
| **Phase 2** | Audio Preview System | ⏳ Planned |
| **Phase 3** | Event Editor Enhancement | ⏳ Planned |
| **Phase 4** | Middleware Integration | ⏳ Planned |
| **Phase 5** | Production Export | ⏳ Planned |

---

## Phase 1: Timeline UX Polish

### 1.1 Snap-to-Grid za Layer Positioning ✅ COMPLETE

**Cilj:** Precizno pozicioniranje layera na definisane grid intervale.

**Specifikacija:**

| Feature | Opis | Status |
|---------|------|--------|
| Grid intervals | 10ms, 25ms, 50ms, 100ms, 250ms, 500ms, 1s | ✅ |
| Toggle | Keyboard shortcut (S) ili toolbar button | ✅ |
| Visual | Grid linije na timeline-u kad je snap aktivan | ✅ |
| Behavior | Layer snap-uje na najbliži grid point pri drag release | ✅ |
| Behavior | Region snap-uje na najbliži grid point pri drag release | ✅ |

**Implementacija:**

```dart
// GridInterval enum
enum GridInterval {
  ms10(10, '10ms'),
  ms25(25, '25ms'),
  // ...
}

// timeline_drag_controller.dart
double snapToGrid(double positionSeconds) {
  if (!_snapEnabled) return positionSeconds;
  final intervalSeconds = _gridInterval.seconds;
  return (positionSeconds / intervalSeconds).round() * intervalSeconds;
}

// Pri endLayerDrag():
final snappedPosition = getSnappedAbsolutePosition();
final newAbsoluteOffsetMs = snappedPosition * 1000;
```

**Kreirani fajlovi:**
- `flutter_ui/lib/widgets/slot_lab/timeline_toolbar.dart` — Snap toggle + interval dropdown
- `flutter_ui/lib/widgets/slot_lab/timeline_grid_overlay.dart` — Visual grid overlay

**Izmenjeni fajlovi:**
- `flutter_ui/lib/controllers/slot_lab/timeline_drag_controller.dart` — GridInterval enum, snap logic
- `flutter_ui/lib/screens/slot_lab_screen.dart` — Integration, S keyboard shortcut

**Status:** ✅ COMPLETE (2026-01-21)

---

### 1.2 Zoom In/Out na Timeline ✅ COMPLETE

**Cilj:** Kontrola nivoa detalja na timeline-u.

**Specifikacija:**

| Feature | Opis | Status |
|---------|------|--------|
| Zoom levels | 0.1x - 10x (continuous) | ✅ |
| Default | 1x = 100% | ✅ |
| Controls | Mouse wheel + Ctrl, G/H keys, slider | ✅ |
| Reset | Ctrl+0 ili klik na percentage | ✅ |
| Behavior | Zoom oko leve ivice (cursor-centered deferred) | ✅ |

**Implementacija:**

```dart
// TimelineToolbar dobio _ZoomControls widget sa:
// - Slider (0.1 - 10.0)
// - +/- buttons
// - Percentage display (klik za reset)

// Mouse wheel zoom u _buildTimelineContent():
Listener(
  onPointerSignal: (event) {
    if (event is PointerScrollEvent && HardwareKeyboard.instance.isControlPressed) {
      final delta = event.scrollDelta.dy;
      setState(() {
        _timelineZoom = delta < 0
            ? (_timelineZoom * 1.15).clamp(0.1, 10.0)  // zoom in
            : (_timelineZoom / 1.15).clamp(0.1, 10.0); // zoom out
      });
    }
  },
  child: SingleChildScrollView(...),
)
```

**Keyboard shortcuts:**
- **G** - Zoom out
- **H** - Zoom in
- **Ctrl+0** - Reset to 100%
- **]** - Zoom in (legacy)
- **[** - Zoom out (legacy)

**Fajlovi izmenjeni:**
- `flutter_ui/lib/widgets/slot_lab/timeline_toolbar.dart` — _ZoomControls widget
- `flutter_ui/lib/screens/slot_lab_screen.dart` — Mouse wheel Listener

**Status:** ✅ COMPLETE (2026-01-21)

---

### 1.3 Waveform Preview tokom Drag-a ✅ COMPLETE

**Cilj:** Vizualni feedback pozicije waveform-a dok se layer vuče.

**Specifikacija:**

| Feature | Opis | Status |
|---------|------|--------|
| Ghost outline | Outline na originalnoj poziciji | ✅ |
| Semi-transparent waveform | Opacity 0.85 na trenutnoj poziciji | ✅ |
| Time tooltip | Tooltip sa pozicijom u ms iznad layera | ✅ |

**Implementacija:**

```dart
// U _buildDraggableLayerRow:
// 1. Ghost outline na originalnoj poziciji
if (isDragging && (offsetPixels - originalOffsetPixels).abs() > 2)
  Positioned(
    left: originalOffsetPixels.clamp(0.0, double.infinity),
    child: Container(
      decoration: BoxDecoration(
        border: Border.all(color: color.withAlpha(100), width: 1),
      ),
    ),
  ),

// 2. Time tooltip iznad layera
if (isDragging)
  Positioned(
    left: offsetPixels,
    top: -20,
    child: Container(
      // Blue styled tooltip sa _formatTimeMs(currentAbsoluteMs)
    ),
  ),
```

**Helper funkcija:**
```dart
String _formatTimeMs(int ms) {
  if (ms < 1000) return '${ms}ms';
  else if (ms < 60000) return '${(ms/1000).toStringAsFixed(2)}s';
  else return '${ms~/60000}m ${((ms%60000)/1000).toStringAsFixed(1)}s';
}
```

**Fajlovi izmenjeni:**
- `flutter_ui/lib/screens/slot_lab_screen.dart` — _buildDraggableLayerRow + _formatTimeMs

**Status:** ✅ COMPLETE (2026-01-21)

---

## Phase 2: Audio Preview System

### 2.1 Manual Audio Preview (Play/Stop Buttons)

> **V6.4 Update (2026-01-26):** Hover auto-play DISABLED. Sada koristi manual play/stop buttons.

**Cilj:** Čuti audio pre nego što se doda na timeline.

**Specifikacija:**

| Feature | Opis |
|---------|------|
| Trigger | ~~Mouse hover 500ms~~ **DISABLED** — Klik na Play dugme |
| Playback | Manualni play/stop kontrola |
| Stop | Klik na Stop dugme (ostaje expanded dok svira) |
| Volume | Koristi preview volume setting |

**Implementacija:**

```dart
// events_panel_widget.dart
class _HoverPreviewItemState extends State<_HoverPreviewItem> {
  bool _isPlaying = false;
  int _currentVoiceId = -1;

  void _onHoverStart() {
    setState(() => _isHovered = true);
    // NOTE: Auto-playback on hover disabled — use play/stop button instead
  }

  void _onHoverEnd() {
    setState(() => _isHovered = false);
    // NOTE: Playback continues until manually stopped via button
  }

  void _startPlayback() {
    _currentVoiceId = AudioPlaybackService.instance.previewFile(
      widget.audioInfo.path,
      source: PlaybackSource.browser,
    );
    setState(() => _isPlaying = true);
  }

  void _stopPlayback() {
    AudioPlaybackService.instance.stopSource(PlaybackSource.browser);
    setState(() => _isPlaying = false);
  }
}
```

**Fajlovi:**
- `flutter_ui/lib/widgets/slot_lab/events_panel_widget.dart`
- `flutter_ui/lib/services/audio_playback_service.dart`

**Status:** ✅ DONE (V6.4)

---

### 2.2 Waveform Thumbnail u File List

**Cilj:** Vizualni pregled audio fajla u browser listi.

**Specifikacija:**

| Feature | Opis |
|---------|------|
| Size | 80x24 pixels mini waveform |
| Cache | Thumbnails keširani po file path |
| Generation | Async, pokazuje placeholder dok se generiše |
| Color | Mono color, matches theme |

**Implementacija:**

```dart
// waveform_thumbnail_cache.dart
class WaveformThumbnailCache {
  static final instance = WaveformThumbnailCache._();
  final _cache = <String, Uint8List>{};

  Future<Uint8List?> getThumbnail(String audioPath) async {
    if (_cache.containsKey(audioPath)) {
      return _cache[audioPath];
    }

    final thumbnail = await _generateThumbnail(audioPath);
    if (thumbnail != null) {
      _cache[audioPath] = thumbnail;
    }
    return thumbnail;
  }

  Future<Uint8List?> _generateThumbnail(String audioPath) async {
    // FFI call to Rust for fast waveform generation
    return NativeFFI.generateWaveformThumbnail(audioPath, 80, 24);
  }
}
```

**Rust FFI (rf-bridge):**
```rust
#[no_mangle]
pub extern "C" fn generate_waveform_thumbnail(
    path: *const c_char,
    width: i32,
    height: i32,
) -> *mut u8 {
    // Load audio, downsample, generate peaks, render to bitmap
}
```

**Status:** ⏳ Not Started

---

## Phase 3: Event Editor Enhancement

### 3.1 Multi-Select Layers

**Cilj:** Selektovati više layera za bulk operacije.

**Specifikacija:**

| Feature | Opis |
|---------|------|
| Selection | Ctrl+click za toggle, Shift+click za range |
| Visual | Highlighted border na selektovanim layerima |
| Operations | Delete, Move, Copy, Volume/Pan adjust |

**Implementacija:**

```dart
// slot_lab_screen.dart state
final Set<String> _selectedLayerIds = {};

void _handleLayerClick(String layerId, bool isCtrl, bool isShift) {
  setState(() {
    if (isCtrl) {
      // Toggle selection
      if (_selectedLayerIds.contains(layerId)) {
        _selectedLayerIds.remove(layerId);
      } else {
        _selectedLayerIds.add(layerId);
      }
    } else if (isShift && _lastSelectedLayerId != null) {
      // Range selection
      _selectLayerRange(_lastSelectedLayerId!, layerId);
    } else {
      // Single selection
      _selectedLayerIds.clear();
      _selectedLayerIds.add(layerId);
    }
    _lastSelectedLayerId = layerId;
  });
}
```

**Status:** ⏳ Not Started

---

### 3.2 Copy/Paste Layers

**Cilj:** Kopirati layere između eventa.

**Specifikacija:**

| Feature | Opis |
|---------|------|
| Copy | Ctrl+C kopira selektovane layere |
| Paste | Ctrl+V paste-uje u trenutno selektovani event |
| Clipboard | Interno, ne koristi system clipboard |

**Implementacija:**

```dart
// layer_clipboard.dart
class LayerClipboard {
  static final instance = LayerClipboard._();
  List<SlotEventLayer>? _copiedLayers;

  void copy(List<SlotEventLayer> layers) {
    _copiedLayers = layers.map((l) => l.copyWith(
      id: 'layer_${DateTime.now().millisecondsSinceEpoch}_${_copiedLayers!.indexOf(l)}',
    )).toList();
  }

  List<SlotEventLayer>? paste() {
    if (_copiedLayers == null) return null;
    // Generate new IDs for pasted layers
    return _copiedLayers!.map((l) => l.copyWith(
      id: 'layer_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}',
    )).toList();
  }
}
```

**Status:** ⏳ Not Started

---

### 3.3 Fade In/Out Controls per Layer

**Cilj:** Kontrola fade-a za svaki layer.

**Specifikacija:**

| Feature | Opis |
|---------|------|
| Fade In | 0-5000ms, logarithmic curve |
| Fade Out | 0-5000ms, logarithmic curve |
| Visual | Fade curve overlay na waveform-u |
| UI | Slider ili number input u layer properties |

**Model update:**

```dart
// SlotEventLayer already has fadeInMs and fadeOutMs
// Need to add:
// - UI controls in layer detail panel
// - Visual fade curve on waveform
// - Apply fade in AudioPlaybackService
```

**Status:** ⏳ Not Started

---

## Phase 4: Middleware Integration

### 4.1 RTPC Vizualizacija

**Cilj:** Real-time prikaz RTPC vrednosti tokom spin-a.

**Specifikacija:**

| Feature | Opis |
|---------|------|
| Display | Sparkline graf za svaki RTPC |
| Update rate | 60fps tokom spin-a |
| History | Poslednih 5 sekundi |
| Highlight | Trenutna vrednost numerički |

**Komponente:**
- `RtpcMonitorWidget` - lista svih RTPC-ova sa sparkline-ovima
- `RtpcSparkline` - pojedinačni RTPC graf
- Integracija sa `SlotLabProvider` za spin events

**Status:** ⏳ Not Started

---

### 4.2 Ducking Matrix UI

**Cilj:** Vizualni editor za bus ducking konfiguraciju.

**Specifikacija:**

| Feature | Opis |
|---------|------|
| Layout | Grid matrix - sources vs targets |
| Cell | Ducking amount (0-100%) + attack/release |
| Visual | Color intensity pokazuje ducking amount |
| Real-time | Aktivni ducking highlighted tokom playback-a |

**Status:** ⏳ Not Started

---

### 4.3 ALE Integration

**Cilj:** Povezati Adaptive Layer Engine sa spin rezultatima.

**Specifikacija:**

| Feature | Opis |
|---------|------|
| Signal sync | Spin rezultati → ALE signals (winTier, winXbet, etc.) |
| Context switch | Auto context change (BASE → FREESPINS → BIGWIN) |
| Layer viz | Real-time layer volume bars |
| Profile edit | ALE profile editor u SlotLab |

**Status:** ⏳ Not Started

---

## Phase 5: Production Export

### 5.1 Event Export (JSON/XML)

**Cilj:** Eksportovati evente za game engine integraciju.

**Specifikacija:**

| Format | Use Case |
|--------|----------|
| JSON | Web/Unity/Custom engines |
| XML | Wwise-compatible |
| Soundbank | Packed binary format |

**Export struktura:**
```json
{
  "version": "1.0",
  "events": [
    {
      "id": "spin_start",
      "name": "Spin Start",
      "triggerStages": ["SPIN_START"],
      "layers": [
        {
          "audioFile": "spin_whoosh.wav",
          "volume": 0.8,
          "pan": 0.0,
          "offsetMs": 0,
          "fadeInMs": 10,
          "fadeOutMs": 50
        }
      ]
    }
  ],
  "buses": [...],
  "rtpcs": [...],
  "duckingRules": [...]
}
```

**Status:** ⏳ Not Started

---

### 5.2 Audio Pack Export

**Cilj:** Renderovati sve audio sa efektima.

**Specifikacija:**

| Feature | Opis |
|---------|------|
| Format | WAV 48kHz/24bit, MP3, OGG |
| Rendering | Apply volume, pan, fades |
| Naming | Configurable naming convention |
| Structure | Flat or folder-per-event |

**Status:** ⏳ Not Started

---

## Tracking

### Completed Items

| Date | Item | Commit |
|------|------|--------|
| 2026-01-21 | Event log deduplication | `e1820b0c` |
| 2026-01-21 | Absolute positioning drag | `97d8723f` |
| 2026-01-21 | Documentation update | `832554c6` |
| 2026-01-21 | **P2.1 Snap-to-Grid** | `abf3df17` |
| 2026-01-21 | **P2.2 Timeline Zoom** | `3783b0c1` |
| 2026-01-21 | **P2.3 Drag Waveform Preview** | pending |

### In Progress

| Item | Started | Notes |
|------|---------|-------|
| Phase 2: Audio Preview | 2026-01-21 | P2.4 Hover Preview next |

### Blocked

| Item | Blocker | Notes |
|------|---------|-------|
| - | - | - |

---

## Notes

- Svaka faza treba da ima working commit pre prelaska na sledeću
- UI/UX promene testirati na realnim slot audio projektima
- Performance critical: waveform rendering, RTPC updates
- Rust FFI za heavy lifting (waveform generation, audio processing)

---

**Last Updated:** 2026-01-21
