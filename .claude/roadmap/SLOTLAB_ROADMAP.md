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

### 1.1 Snap-to-Grid za Layer Positioning

**Cilj:** Precizno pozicioniranje layera na definisane grid intervale.

**Specifikacija:**

| Feature | Opis |
|---------|------|
| Grid intervals | 10ms, 25ms, 50ms, 100ms, 250ms, 500ms, 1s |
| Toggle | Keyboard shortcut (G) ili toolbar button |
| Visual | Grid linije na timeline-u kad je snap aktivan |
| Behavior | Layer snap-uje na najbliži grid point pri drag release |

**Implementacija:**

```dart
// timeline_drag_controller.dart
double _snapToGrid(double positionSeconds, double gridIntervalSeconds) {
  if (!_snapEnabled) return positionSeconds;
  return (positionSeconds / gridIntervalSeconds).round() * gridIntervalSeconds;
}

// Pri endLayerDrag():
final snappedPosition = _snapToGrid(getAbsolutePosition(), _gridInterval);
final newAbsoluteOffsetMs = snappedPosition * 1000;
```

**UI komponente:**
- Grid interval dropdown u toolbar-u
- Snap toggle button (magnet ikona)
- Grid linije overlay na timeline

**Fajlovi za izmenu:**
- `flutter_ui/lib/controllers/slot_lab/timeline_drag_controller.dart`
- `flutter_ui/lib/screens/slot_lab_screen.dart`
- `flutter_ui/lib/widgets/slot_lab/timeline_toolbar.dart` (novi)

**Status:** ⏳ Not Started

---

### 1.2 Zoom In/Out na Timeline

**Cilj:** Kontrola nivoa detalja na timeline-u.

**Specifikacija:**

| Feature | Opis |
|---------|------|
| Zoom levels | 0.5x, 1x, 2x, 4x, 8x, 16x |
| Default | 1x = 100 pixels per second |
| Controls | Mouse wheel + Ctrl, +/- keys, slider |
| Behavior | Zoom oko trenutne pozicije kursora |

**Implementacija:**

```dart
// slot_lab_screen.dart state
double _zoomLevel = 1.0;
double get _pixelsPerSecond => 100.0 * _zoomLevel;

void _handleZoom(double delta, Offset cursorPosition) {
  final oldZoom = _zoomLevel;
  _zoomLevel = (_zoomLevel * (1 + delta * 0.1)).clamp(0.5, 16.0);

  // Maintain cursor position on timeline
  final timeAtCursor = cursorPosition.dx / (100.0 * oldZoom);
  _scrollOffset = timeAtCursor * _pixelsPerSecond - cursorPosition.dx;
}
```

**UI komponente:**
- Zoom slider u toolbar-u
- Zoom percentage display
- Zoom-to-fit button

**Fajlovi za izmenu:**
- `flutter_ui/lib/screens/slot_lab_screen.dart`
- `flutter_ui/lib/widgets/slot_lab/timeline_toolbar.dart`

**Status:** ⏳ Not Started

---

### 1.3 Waveform Preview tokom Drag-a

**Cilj:** Vizualni feedback pozicije waveform-a dok se layer vuče.

**Specifikacija:**

| Feature | Opis |
|---------|------|
| Ghost waveform | Semi-transparent waveform na novoj poziciji |
| Original position | Outline gde je layer bio |
| Time tooltip | Tooltip sa trenutnom pozicijom u ms |

**Implementacija:**

```dart
// Tokom drag-a renderuj:
// 1. Ghost outline na originalnoj poziciji (dashed border)
// 2. Semi-transparent waveform na trenutnoj drag poziciji
// 3. Time tooltip iznad layer-a

Widget _buildDraggingLayer(...) {
  return Stack(
    clipBehavior: Clip.none,
    children: [
      // Original position ghost
      if (isDragging)
        Positioned(
          left: originalOffsetPixels,
          child: _buildGhostOutline(layerWidth),
        ),
      // Dragging layer with waveform
      Positioned(
        left: currentOffsetPixels,
        child: Opacity(
          opacity: 0.85,
          child: _buildLayerWithWaveform(layer),
        ),
      ),
      // Time tooltip
      if (isDragging)
        Positioned(
          left: currentOffsetPixels,
          top: -24,
          child: _buildTimeTooltip(currentOffsetSeconds),
        ),
    ],
  );
}
```

**Status:** ⏳ Not Started

---

## Phase 2: Audio Preview System

### 2.1 Hover Preview za Audio Fajlove

**Cilj:** Čuti audio pre nego što se doda na timeline.

**Specifikacija:**

| Feature | Opis |
|---------|------|
| Trigger | Mouse hover 500ms nad audio fajlom u browser-u |
| Playback | Auto-play prvih 3 sekunde |
| Stop | Mouse leave ili novi hover |
| Volume | Koristi preview volume setting |

**Implementacija:**

```dart
// audio_hover_preview.dart
class AudioHoverPreview extends StatefulWidget {
  final String audioPath;
  final Duration hoverDelay;
  final Duration previewDuration;

  // ...
}

class _AudioHoverPreviewState extends State<AudioHoverPreview> {
  Timer? _hoverTimer;

  void _onHoverStart() {
    _hoverTimer = Timer(widget.hoverDelay, () {
      AudioPlaybackService.instance.playPreview(
        widget.audioPath,
        duration: widget.previewDuration,
      );
    });
  }

  void _onHoverEnd() {
    _hoverTimer?.cancel();
    AudioPlaybackService.instance.stopPreview();
  }
}
```

**Fajlovi za izmenu:**
- `flutter_ui/lib/widgets/slot_lab/audio_hover_preview.dart`
- `flutter_ui/lib/services/audio_playback_service.dart`

**Status:** ⏳ Not Started

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

### In Progress

| Item | Started | Notes |
|------|---------|-------|
| - | - | - |

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
