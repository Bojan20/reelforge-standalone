# ReelForge Audio Editor Architecture

## ANALIZA PROBLEMA (2026-01-11)

### Identifikovani problemi

| Problem | Lokacija | Root Cause | Prioritet |
|---------|----------|------------|-----------|
| **Zoom ne radi glatko** | `timeline.dart:349-365` | Diskretni faktori (0.9/1.1), nema animacije | CRITICAL |
| **Slideri nisu smooth** | Nema dedicated slider widget | Nedostaje slider implementacija | HIGH |
| **Fade drag ne radi** | `clip_widget.dart:652-684` | Pozicija handle-a je OK, ali delta kalkulacija može biti bolja | MEDIUM |

---

## ZOOM PROBLEMI

### Trenutna implementacija (`timeline.dart:349-365`)

```dart
void _handleWheel(PointerScrollEvent event) {
  if (HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isMetaPressed) {
    // Zoom - PROBLEM: Discrete steps, no smoothing
    final delta = event.scrollDelta.dy > 0 ? 0.9 : 1.1;  // ❌ Fixed 10% steps
    final newZoom = (widget.zoom * delta).clamp(1.0, 500.0);
    widget.onZoomChange?.call(newZoom);  // ❌ No animation
  } else {
    // Scroll
    final delta = event.scrollDelta.dx != 0
        ? event.scrollDelta.dx
        : event.scrollDelta.dy;
    final newOffset = (widget.scrollOffset + delta / widget.zoom)
        .clamp(0.0, widget.totalDuration - _containerWidth / widget.zoom);
    widget.onScrollChange?.call(newOffset);
  }
}
```

### Problemi:
1. **Fiksni stepovi od 10%** - Zoom je "steppy", ne smooth
2. **Nema animacije** - Zoom je instantan, ne interpoliran
3. **Scroll delta nije skaliran** - Trackpad vs wheel daju različite rezultate
4. **Nema zoom-to-cursor** - Ne zumira ka poziciji miša

### Rešenje - Pro DAW Zoom:

```dart
// 1. Skaliran delta baziran na scroll magnitude
final scrollMagnitude = event.scrollDelta.dy.abs();
final zoomFactor = 1.0 + (scrollMagnitude / 500.0).clamp(0.02, 0.15);
final delta = event.scrollDelta.dy > 0 ? 1.0 / zoomFactor : zoomFactor;

// 2. Zoom to cursor position
final mouseX = event.localPosition.dx - _headerWidth;
final mouseTime = widget.scrollOffset + mouseX / widget.zoom;
final newZoom = (widget.zoom * delta).clamp(5.0, 500.0);

// Keep cursor position stable after zoom
final newMouseX = mouseX * (newZoom / widget.zoom);
final newScrollOffset = mouseTime - newMouseX / newZoom;

widget.onZoomChange?.call(newZoom);
widget.onScrollChange?.call(newScrollOffset.clamp(0.0, widget.totalDuration));
```

---

## SLIDER SMOOTHNESS

### Problem:
Nema dedicated slider widget za audio kontrole. Track volume/pan koriste basic kontrole.

### DAW Pattern - Smooth Slider:
- **Inertia/momentum** - Nastavlja kretanje nakon release
- **Fine control** - Shift+drag za precizne promene
- **Value snapping** - Snap na 0dB, center pan
- **Visual feedback** - Glow, value tooltip

### Potreban widget: `SmoothSlider`

```dart
class SmoothSlider extends StatefulWidget {
  final double value;
  final double min, max;
  final ValueChanged<double> onChanged;
  final bool vertical;
  final double? snapValue; // Optional snap point

  // Features:
  // - Fine mode (Shift held = 10x precision)
  // - Double-tap to reset
  // - Momentum scrolling
  // - Value tooltip on drag
}
```

---

## FADE HANDLE DRAG

### Trenutna implementacija (`clip_widget.dart:1229-1260`)

```dart
child: Listener(
  behavior: HitTestBehavior.opaque,
  onPointerDown: (event) {
    fadeHandleActiveGlobal = true;  // ✓ Prevents playhead jump
    _isDragging = true;
    _dragStartX = event.localPosition.dx;
    widget.onDragStart();
  },
  onPointerMove: (event) {
    if (_isDragging) {
      final delta = event.localPosition.dx - _dragStartX;
      _dragStartX = event.localPosition.dx;  // ✓ Relative delta
      widget.onDragUpdate(delta);
    }
  },
```

### Fade callback u `_ClipWidgetState`:

```dart
_FadeHandle(
  onDragUpdate: (deltaPixels) {
    final deltaSeconds = deltaPixels / widget.zoom;
    final newFadeIn = (clip.fadeIn + deltaSeconds)
        .clamp(0.0, clip.duration * 0.5);
    widget.onFadeChange?.call(newFadeIn, clip.fadeOut);
  },
```

### Potencijalni problem:
Handle pozicija je izračunata kao:
```dart
left: widget.isLeft ? widget.width - 18 : null,
right: widget.isLeft ? null : widget.width - 18,
```

Ovo postavlja handle na KRAJ fade regiona, što je ispravno. Ali `widget.width` je fade width u pikselima, koji se menja dok korisnik vuče - ovo može uzrokovati "drifting".

### Rešenje - Stabilna referenca:

```dart
// Use absolute clip position as reference, not relative fade width
onPointerMove: (event) {
  if (_isDragging) {
    // Get global X position and convert to time
    final RenderBox box = context.findRenderObject() as RenderBox;
    final globalPos = box.localToGlobal(event.localPosition);
    // ... calculate fade time from global position
  }
}
```

---

## DAW AUDIO EDITOR PATTERNS (Research)

### Cubase Audio Editor:
- **Sample-accurate editing** - Zoom do sample nivoa
- **Hitpoint detection** - Automatski markeri na transijenata
- **Warp markers** - Time stretch sa vizualnim markerima
- **VariAudio** - Pitch editing inline
- **Fade curves** - Multiple curve types (linear, log, S-curve)

### Logic Pro Audio Editor:
- **Flex Time** - Non-destructive time stretch
- **Flex Pitch** - Melodyne-style pitch editing
- **Smart Tempo** - Beat detection and alignment
- **Quick Sampler** - Drag region to sampler

### Pro Tools Audio Editor:
- **Elastic Audio** - Polyphonic/rhythmic/monophonic modes
- **AudioSuite** - Offline processing
- **Clip gain** - Per-clip volume adjustment (✓ imamo)
- **Strip Silence** - Automatic region splitting

### REAPER Audio Editor:
- **Dynamic split** - Based on transients/silence
- **Stretch markers** - Inline time stretch
- **Spectral editing** - Basic spectrum view
- **Take lanes** - Multiple takes per item

---

## IMPLEMENTACIONI PLAN

### Faza 1: Smooth Zoom (CRITICAL)
1. Skaliran zoom delta baziran na scroll magnitude
2. Zoom-to-cursor (zadržava poziciju ispod miša)
3. Min zoom povećan na 5.0 (sprečava ultra-zoom out)
4. Keyboard zoom (G/H) koristi isti sistem

### Faza 2: Fade Handle Fix
1. Koristi globalne koordinate za fade kalkulaciju
2. Dodaj snap-to-grid za fade pozicije
3. Visual feedback tokom drag-a (cursor change, tooltip)

### Faza 3: Audio Editor Features
1. Dodaj zoom slider u editor toolbar
2. Implement smooth pan/scroll
3. Add waveform overview bar (minimap)
4. Implement selection range editing

---

## KEY FILES

| File | Purpose | Lines |
|------|---------|-------|
| `timeline.dart` | Main timeline widget | 1632 |
| `clip_widget.dart` | Clip with fades, waveform | 1471 |
| `waveform_painter.dart` | Waveform rendering | 1223 |
| `time_ruler.dart` | Time ruler with markers | ~300 |
| `track_lane.dart` | Track lane container | ~400 |

---

## REFERENCE IMPLEMENTATIONS

### Zoom-to-cursor (Cubase pattern):
```dart
/// Zoom while keeping the point under cursor stable
void zoomToPoint(double zoomFactor, double cursorX) {
  final cursorTime = scrollOffset + cursorX / zoom;
  final newZoom = (zoom * zoomFactor).clamp(minZoom, maxZoom);
  final newScrollOffset = cursorTime - cursorX / newZoom;

  setZoom(newZoom);
  setScrollOffset(newScrollOffset.clamp(0, maxScroll));
}
```

### Smooth slider momentum:
```dart
/// Apply momentum after drag release
void _handleDragEnd(DragEndDetails details) {
  final velocity = details.velocity.pixelsPerSecond.dx;
  if (velocity.abs() > 100) {
    _animationController.animateWith(
      FrictionSimulation(0.5, _currentValue, velocity / 1000),
    );
  }
}
```

### Fine control mode:
```dart
/// Shift+drag for fine control
void _handleDragUpdate(DragUpdateDetails details) {
  final sensitivity = HardwareKeyboard.instance.isShiftPressed ? 0.1 : 1.0;
  final delta = details.delta.dx * sensitivity;
  // ...
}
```
