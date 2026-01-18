# Sample Editor Upgrade Plan — Cubase-Style Implementation

## Status: DETAILED IMPLEMENTATION GUIDE

Ovaj dokument definiše **konkretne promene** u postojećem kodu za dostizanje Cubase Pro nivoa Sample Editor-a.

---

## PART A: WAVEFORM CACHE UPGRADE

### A1. Proširenje WaveformBucket strukture

**Fajl:** `crates/rf-engine/src/waveform.rs`

**Trenutno (linija ~15):**
```rust
pub struct WaveformBucket {
    pub min: f32,
    pub max: f32,
    pub rms: f32,
}
```

**Potrebna promena:**
```rust
/// Waveform bucket with extended analysis data
#[derive(Clone, Copy, Debug, Default)]
pub struct WaveformBucket {
    pub min: f32,           // Minimum sample value
    pub max: f32,           // Maximum sample value
    pub rms: f32,           // RMS energy
    pub peak_abs: f32,      // Absolute peak (for clipping detection)
    pub transient: f32,     // Transient strength (0.0-1.0)
}
```

**Implikacije:**
- Bucket size: 12 → 20 bytes (5 × f32)
- Cache file format version bump potreban
- Backward compatibility: čitaj stare .wfc fajlove, piši nove sa verzijom

### A2. Dodavanje LOD Level 0 (Sample-Accurate)

**Fajl:** `crates/rf-engine/src/waveform.rs`

**Trenutno (linija ~10):**
```rust
pub const SAMPLES_PER_PEAK: [usize; 11] = [4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096];
pub const NUM_LOD_LEVELS: usize = 11;
```

**Potrebna promena:**
```rust
/// LOD levels: Level 0 = 1 sample (raw), Level 1-11 = bucketed
pub const SAMPLES_PER_PEAK: [usize; 12] = [1, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096];
pub const NUM_LOD_LEVELS: usize = 12;

/// Threshold below which we use raw samples instead of buckets
pub const RAW_SAMPLE_THRESHOLD: f64 = 1.5; // frames per pixel
```

### A3. Transient Strength Calculation During Cache Build

**Fajl:** `crates/rf-engine/src/waveform.rs`

**Dodati u `build_cache()` funkciju (linija ~80):**
```rust
// Inside the bucket building loop:
let mut transient_strength = 0.0f32;
if i > 0 {
    // Differential energy for transient detection
    let prev_energy = prev_bucket_rms * prev_bucket_rms;
    let curr_energy = rms * rms;
    let energy_delta = (curr_energy - prev_energy).max(0.0);
    transient_strength = (energy_delta / (curr_energy + 0.0001)).min(1.0) as f32;
}

bucket.transient = transient_strength;
bucket.peak_abs = bucket.max.abs().max(bucket.min.abs());
```

---

## PART B: FFI EXPORTS ZA HITPOINT DETECTION

### B1. Nova FFI funkcija: engine_detect_transients

**Fajl:** `crates/rf-engine/src/ffi.rs`

**Dodati nakon linije ~1530 (posle marker funkcija):**

```rust
// ═══════════════════════════════════════════════════════════════════════════
// HITPOINT / TRANSIENT DETECTION FFI
// ═══════════════════════════════════════════════════════════════════════════

/// Detect transients in a clip
///
/// # Arguments
/// * `clip_id` - Clip to analyze
/// * `sensitivity` - Detection sensitivity (0.0-1.0)
/// * `algorithm` - Algorithm type: 0=Enhanced, 1=HighEmphasis, 2=LowEmphasis
/// * `min_gap_ms` - Minimum gap between detections in milliseconds
/// * `out_positions` - Output buffer for sample positions (u64)
/// * `out_strengths` - Output buffer for strength values (f32)
/// * `out_capacity` - Size of output buffers
///
/// # Returns
/// Number of transients detected (or 0 on error)
#[unsafe(no_mangle)]
pub extern "C" fn engine_detect_transients(
    clip_id: u64,
    sensitivity: f32,
    algorithm: u32,
    min_gap_ms: f32,
    out_positions: *mut u64,
    out_strengths: *mut f32,
    out_capacity: u32,
) -> u32 {
    use rf_dsp::transient::{TransientDetector, DetectionSettings, DetectionAlgorithm};

    // Get clip audio data
    let clips = IMPORTED_AUDIO.read();
    let Some(audio) = clips.get(&ClipId(clip_id)) else {
        eprintln!("[FFI] engine_detect_transients: clip {} not found", clip_id);
        return 0;
    };

    // Configure detector
    let algo = match algorithm {
        1 => DetectionAlgorithm::HighEmphasis,
        2 => DetectionAlgorithm::LowEmphasis,
        3 => DetectionAlgorithm::SpectralFlux,
        _ => DetectionAlgorithm::Enhanced,
    };

    let settings = DetectionSettings {
        algorithm: algo,
        sensitivity: sensitivity as f64,
        min_gap_samples: ((min_gap_ms / 1000.0) * audio.sample_rate as f32) as u64,
        ..Default::default()
    };

    let mut detector = TransientDetector::with_settings(audio.sample_rate as f64, settings);

    // Convert to mono f64 for analysis
    let mono: Vec<f64> = if audio.channels == 2 {
        audio.samples.chunks(2)
            .map(|chunk| ((chunk[0] + chunk[1]) * 0.5) as f64)
            .collect()
    } else {
        audio.samples.iter().map(|&s| s as f64).collect()
    };

    // Detect transients
    let markers = detector.analyze(&mono);

    // Copy to output buffers
    let count = markers.len().min(out_capacity as usize);

    unsafe {
        for (i, marker) in markers.iter().take(count).enumerate() {
            *out_positions.add(i) = marker.position;
            *out_strengths.add(i) = marker.strength as f32;
        }
    }

    count as u32
}

/// Get transient positions from waveform cache (fast, pre-computed)
///
/// Returns transient positions where bucket.transient > threshold
#[unsafe(no_mangle)]
pub extern "C" fn engine_get_cached_transients(
    clip_id: u64,
    threshold: f32,
    out_positions: *mut u64,
    out_strengths: *mut f32,
    out_capacity: u32,
) -> u32 {
    // Query from waveform cache (much faster than full detection)
    let cache = WAVEFORM_CACHE.get_cache(ClipId(clip_id));
    let Some(waveform) = cache else {
        return 0;
    };

    let mut count = 0u32;
    let buckets = waveform.get_level(0); // Use finest LOD
    let samples_per_bucket = SAMPLES_PER_PEAK[0];

    unsafe {
        for (i, bucket) in buckets.iter().enumerate() {
            if bucket.transient > threshold && count < out_capacity {
                let position = (i * samples_per_bucket) as u64;
                *out_positions.add(count as usize) = position;
                *out_strengths.add(count as usize) = bucket.transient;
                count += 1;
            }
        }
    }

    count
}

/// Add a hitpoint marker to clip
#[unsafe(no_mangle)]
pub extern "C" fn engine_add_hitpoint(
    clip_id: u64,
    position_samples: u64,
    strength: f32,
) -> u64 {
    // Store hitpoint in clip metadata
    let hitpoint_id = TRACK_MANAGER.add_clip_hitpoint(
        ClipId(clip_id),
        position_samples,
        strength,
    );
    hitpoint_id.unwrap_or(0)
}

/// Delete a hitpoint
#[unsafe(no_mangle)]
pub extern "C" fn engine_delete_hitpoint(clip_id: u64, hitpoint_id: u64) -> i32 {
    TRACK_MANAGER.delete_clip_hitpoint(ClipId(clip_id), hitpoint_id);
    1
}

/// Move a hitpoint
#[unsafe(no_mangle)]
pub extern "C" fn engine_move_hitpoint(
    clip_id: u64,
    hitpoint_id: u64,
    new_position_samples: u64,
) -> i32 {
    TRACK_MANAGER.move_clip_hitpoint(ClipId(clip_id), hitpoint_id, new_position_samples);
    1
}

/// Get all hitpoints for a clip
/// Returns count, fills out_positions and out_ids
#[unsafe(no_mangle)]
pub extern "C" fn engine_get_hitpoints(
    clip_id: u64,
    out_positions: *mut u64,
    out_ids: *mut u64,
    out_strengths: *mut f32,
    out_capacity: u32,
) -> u32 {
    let hitpoints = TRACK_MANAGER.get_clip_hitpoints(ClipId(clip_id));
    let count = hitpoints.len().min(out_capacity as usize);

    unsafe {
        for (i, hp) in hitpoints.iter().take(count).enumerate() {
            *out_positions.add(i) = hp.position;
            *out_ids.add(i) = hp.id;
            *out_strengths.add(i) = hp.strength;
        }
    }

    count as u32
}
```

### B2. Hitpoint Storage u TrackManager

**Fajl:** `crates/rf-engine/src/track_manager.rs`

**Dodati strukture:**
```rust
/// Hitpoint marker for audio slicing
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Hitpoint {
    pub id: u64,
    pub position: u64,      // Sample position
    pub strength: f32,      // Detection confidence
    pub user_adjusted: bool, // Manual vs auto
}

/// Clip metadata extension
impl Clip {
    // Existing fields...
    pub hitpoints: Vec<Hitpoint>,
}
```

**Dodati metode:**
```rust
impl TrackManager {
    pub fn add_clip_hitpoint(&self, clip_id: ClipId, position: u64, strength: f32) -> Option<u64> {
        let mut clips = self.clips.write();
        if let Some(clip) = clips.get_mut(&clip_id) {
            let id = self.next_hitpoint_id.fetch_add(1, Ordering::Relaxed);
            clip.hitpoints.push(Hitpoint {
                id,
                position,
                strength,
                user_adjusted: true,
            });
            Some(id)
        } else {
            None
        }
    }

    pub fn delete_clip_hitpoint(&self, clip_id: ClipId, hitpoint_id: u64) {
        let mut clips = self.clips.write();
        if let Some(clip) = clips.get_mut(&clip_id) {
            clip.hitpoints.retain(|hp| hp.id != hitpoint_id);
        }
    }

    pub fn move_clip_hitpoint(&self, clip_id: ClipId, hitpoint_id: u64, new_position: u64) {
        let mut clips = self.clips.write();
        if let Some(clip) = clips.get_mut(&clip_id) {
            if let Some(hp) = clip.hitpoints.iter_mut().find(|hp| hp.id == hitpoint_id) {
                hp.position = new_position;
                hp.user_adjusted = true;
            }
        }
    }

    pub fn get_clip_hitpoints(&self, clip_id: ClipId) -> Vec<Hitpoint> {
        self.clips.read()
            .get(&clip_id)
            .map(|c| c.hitpoints.clone())
            .unwrap_or_default()
    }
}
```

---

## PART C: FLUTTER FFI BINDINGS

### C1. Native FFI Dart Wrapper

**Fajl:** `flutter_ui/lib/src/rust/native_ffi.dart`

**Dodati tipove (oko linije 200):**
```dart
// Transient detection
typedef EngineDetectTransientsNative = Uint32 Function(
  Uint64 clipId,
  Float sensitivity,
  Uint32 algorithm,
  Float minGapMs,
  Pointer<Uint64> outPositions,
  Pointer<Float> outStrengths,
  Uint32 outCapacity,
);
typedef EngineDetectTransientsDart = int Function(
  int clipId,
  double sensitivity,
  int algorithm,
  double minGapMs,
  Pointer<Uint64> outPositions,
  Pointer<Float> outStrengths,
  int outCapacity,
);

typedef EngineGetCachedTransientsNative = Uint32 Function(
  Uint64 clipId,
  Float threshold,
  Pointer<Uint64> outPositions,
  Pointer<Float> outStrengths,
  Uint32 outCapacity,
);

typedef EngineAddHitpointNative = Uint64 Function(Uint64 clipId, Uint64 position, Float strength);
typedef EngineDeleteHitpointNative = Int32 Function(Uint64 clipId, Uint64 hitpointId);
typedef EngineMoveHitpointNative = Int32 Function(Uint64 clipId, Uint64 hitpointId, Uint64 newPosition);
typedef EngineGetHitpointsNative = Uint32 Function(
  Uint64 clipId,
  Pointer<Uint64> outPositions,
  Pointer<Uint64> outIds,
  Pointer<Float> outStrengths,
  Uint32 outCapacity,
);
```

**Dodati lookup i metode (oko linije 1100):**
```dart
// Lookup
late final EngineDetectTransientsDart _detectTransients;
late final EngineGetCachedTransientsDart _getCachedTransients;
late final EngineAddHitpointDart _addHitpoint;
late final EngineDeleteHitpointDart _deleteHitpoint;
late final EngineMoveHitpointDart _moveHitpoint;
late final EngineGetHitpointsDart _getHitpoints;

// In _lookupFunctions():
_detectTransients = _lib.lookupFunction<EngineDetectTransientsNative, EngineDetectTransientsDart>('engine_detect_transients');
_getCachedTransients = _lib.lookupFunction<EngineGetCachedTransientsNative, EngineGetCachedTransientsDart>('engine_get_cached_transients');
_addHitpoint = _lib.lookupFunction<EngineAddHitpointNative, EngineAddHitpointDart>('engine_add_hitpoint');
_deleteHitpoint = _lib.lookupFunction<EngineDeleteHitpointNative, EngineDeleteHitpointDart>('engine_delete_hitpoint');
_moveHitpoint = _lib.lookupFunction<EngineMoveHitpointNative, EngineMoveHitpointDart>('engine_move_hitpoint');
_getHitpoints = _lib.lookupFunction<EngineGetHitpointsNative, EngineGetHitpointsDart>('engine_get_hitpoints');
```

**Dodati public metode:**
```dart
/// Detect transients in clip
/// Returns list of (position, strength) tuples
List<(int position, double strength)> detectTransients(
  int clipId, {
  double sensitivity = 0.5,
  int algorithm = 0,  // 0=Enhanced, 1=High, 2=Low
  double minGapMs = 20.0,
  int maxCount = 1000,
}) {
  if (!_loaded) return [];

  final positions = calloc<Uint64>(maxCount);
  final strengths = calloc<Float>(maxCount);

  try {
    final count = _detectTransients(
      clipId, sensitivity, algorithm, minGapMs,
      positions, strengths, maxCount,
    );

    final result = <(int, double)>[];
    for (int i = 0; i < count; i++) {
      result.add((positions[i], strengths[i]));
    }
    return result;
  } finally {
    calloc.free(positions);
    calloc.free(strengths);
  }
}

/// Get pre-computed transients from waveform cache (faster)
List<(int position, double strength)> getCachedTransients(
  int clipId, {
  double threshold = 0.3,
  int maxCount = 1000,
}) {
  if (!_loaded) return [];

  final positions = calloc<Uint64>(maxCount);
  final strengths = calloc<Float>(maxCount);

  try {
    final count = _getCachedTransients(clipId, threshold, positions, strengths, maxCount);

    final result = <(int, double)>[];
    for (int i = 0; i < count; i++) {
      result.add((positions[i], strengths[i]));
    }
    return result;
  } finally {
    calloc.free(positions);
    calloc.free(strengths);
  }
}

/// Add manual hitpoint
int addHitpoint(int clipId, int positionSamples, double strength) {
  if (!_loaded) return 0;
  return _addHitpoint(clipId, positionSamples, strength);
}

/// Delete hitpoint
bool deleteHitpoint(int clipId, int hitpointId) {
  if (!_loaded) return false;
  return _deleteHitpoint(clipId, hitpointId) != 0;
}

/// Move hitpoint to new position
bool moveHitpoint(int clipId, int hitpointId, int newPositionSamples) {
  if (!_loaded) return false;
  return _moveHitpoint(clipId, hitpointId, newPositionSamples) != 0;
}

/// Get all hitpoints for clip
List<({int id, int position, double strength})> getHitpoints(int clipId, {int maxCount = 500}) {
  if (!_loaded) return [];

  final positions = calloc<Uint64>(maxCount);
  final ids = calloc<Uint64>(maxCount);
  final strengths = calloc<Float>(maxCount);

  try {
    final count = _getHitpoints(clipId, positions, ids, strengths, maxCount);

    final result = <({int id, int position, double strength})>[];
    for (int i = 0; i < count; i++) {
      result.add((id: ids[i], position: positions[i], strength: strengths[i]));
    }
    return result;
  } finally {
    calloc.free(positions);
    calloc.free(ids);
    calloc.free(strengths);
  }
}
```

---

## PART D: CLIP EDITOR UI PROMENE

### D1. Proširenje ClipEditorClip modela

**Fajl:** `flutter_ui/lib/widgets/editor/clip_editor.dart`

**Linija ~22, dodati:**
```dart
class ClipEditorClip {
  // ... existing fields ...

  /// Detected hitpoints (sample position, strength)
  final List<(int position, double strength)> hitpoints;

  /// Show hitpoints toggle
  final bool showHitpoints;

  const ClipEditorClip({
    // ... existing params ...
    this.hitpoints = const [],
    this.showHitpoints = true,
  });
}
```

### D2. Hitpoint Rendering u _WaveformPainter

**Fajl:** `flutter_ui/lib/widgets/editor/clip_editor.dart`

**Dodati u _WaveformPainter (linija ~1406):**
```dart
class _WaveformPainter extends CustomPainter {
  // ... existing fields ...
  final List<(int position, double strength)> hitpoints;
  final int sampleRate;
  final bool showHitpoints;

  // Add to constructor
  _WaveformPainter({
    // ... existing ...
    this.hitpoints = const [],
    this.sampleRate = 48000,
    this.showHitpoints = true,
  });
```

**Dodati paint metodu za hitpointe (posle _drawWaveform poziva, linija ~1474):**
```dart
@override
void paint(Canvas canvas, Size size) {
  // ... existing code ...

  // Waveform
  if (waveform != null && waveform!.isNotEmpty) {
    _drawWaveform(canvas, size, centerY);
  }

  // Hitpoints (after waveform, before hover)
  if (showHitpoints && hitpoints.isNotEmpty) {
    _drawHitpoints(canvas, size);
  }

  // Hover line
  // ...
}

void _drawHitpoints(Canvas canvas, Size size) {
  final hitpointPaint = Paint()
    ..strokeWidth = 1.5
    ..style = PaintingStyle.stroke;

  final trianglePaint = Paint()
    ..style = PaintingStyle.fill;

  for (final (position, strength) in hitpoints) {
    // Convert sample position to time
    final timeSec = position / sampleRate;

    // Check if visible
    if (timeSec < scrollOffset || timeSec > scrollOffset + size.width / zoom) {
      continue;
    }

    final x = (timeSec - scrollOffset) * zoom;

    // Color based on strength (orange to red)
    final color = Color.lerp(
      FluxForgeTheme.accentOrange,
      FluxForgeTheme.errorRed,
      strength,
    )!;

    hitpointPaint.color = color.withValues(alpha: 0.8);
    trianglePaint.color = color;

    // Vertical line
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      hitpointPaint,
    );

    // Top triangle marker
    final trianglePath = Path()
      ..moveTo(x, 0)
      ..lineTo(x - 4, 8)
      ..lineTo(x + 4, 8)
      ..close();
    canvas.drawPath(trianglePath, trianglePaint);

    // Bottom triangle marker
    final bottomTriangle = Path()
      ..moveTo(x, size.height)
      ..lineTo(x - 4, size.height - 8)
      ..lineTo(x + 4, size.height - 8)
      ..close();
    canvas.drawPath(bottomTriangle, trianglePaint);
  }
}
```

### D3. Hitpoint Detection Toolbar

**Fajl:** `flutter_ui/lib/widgets/editor/clip_editor.dart`

**Dodati u toolbar (linija ~280):**
```dart
// In _buildToolbar():
// After existing buttons...

const SizedBox(width: 8),
Container(width: 1, height: 20, color: FluxForgeTheme.borderSubtle),
const SizedBox(width: 8),

// Hitpoint detection button
_ToolbarButton(
  icon: Icons.graphic_eq,
  tooltip: 'Detect Hitpoints',
  onPressed: _detectHitpoints,
),

// Hitpoint visibility toggle
_ToolbarButton(
  icon: _showHitpoints ? Icons.visibility : Icons.visibility_off,
  tooltip: _showHitpoints ? 'Hide Hitpoints' : 'Show Hitpoints',
  active: _showHitpoints,
  onPressed: () => setState(() => _showHitpoints = !_showHitpoints),
),

// Sensitivity slider (when hitpoints visible)
if (_showHitpoints) ...[
  const SizedBox(width: 8),
  SizedBox(
    width: 100,
    child: Slider(
      value: _hitpointSensitivity,
      min: 0.1,
      max: 1.0,
      onChanged: (v) {
        setState(() => _hitpointSensitivity = v);
        _detectHitpoints(); // Re-detect with new sensitivity
      },
    ),
  ),
  Text(
    '${(_hitpointSensitivity * 100).round()}%',
    style: TextStyle(fontSize: 10, color: FluxForgeTheme.textSecondary),
  ),
],
```

### D4. Hitpoint Detection Implementation

**Dodati u ClipEditor State:**
```dart
class _ClipEditorState extends State<ClipEditor> {
  // ... existing fields ...

  bool _showHitpoints = true;
  double _hitpointSensitivity = 0.5;
  List<(int position, double strength)> _hitpoints = [];

  void _detectHitpoints() {
    if (widget.clip == null) return;

    final clipIdInt = int.tryParse(widget.clip!.id) ?? 0;
    if (clipIdInt == 0) return;

    final hitpoints = NativeFFI.instance.detectTransients(
      clipIdInt,
      sensitivity: _hitpointSensitivity,
      algorithm: 0, // Enhanced
      minGapMs: 20.0,
    );

    setState(() => _hitpoints = hitpoints);
  }

  // Call on clip change
  @override
  void didUpdateWidget(ClipEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.clip?.id != oldWidget.clip?.id) {
      _hitpoints.clear();
      if (_showHitpoints && widget.clip != null) {
        _detectHitpoints();
      }
    }
  }
}
```

---

## PART E: SMOOTH ZOOM IMPLEMENTATION

### E1. Zoom-to-Cursor Behavior

**Fajl:** `flutter_ui/lib/widgets/editor/clip_editor.dart`

**Zameniti postojeći zoom handling (linija ~450):**
```dart
void _handleZoom(double delta, Offset localPosition, Size size) {
  if (widget.clip == null) return;

  // Get time at cursor before zoom
  final timeAtCursor = widget.scrollOffset + localPosition.dx / widget.zoom;

  // Calculate new zoom (smooth exponential)
  final zoomFactor = delta > 0 ? 1.15 : 0.87; // ~15% per step
  final newZoom = (widget.zoom * zoomFactor).clamp(8.0, 50000.0);

  // Calculate new scroll to keep cursor position stable
  final newScrollOffset = timeAtCursor - localPosition.dx / newZoom;

  // Clamp scroll to valid range
  final maxScroll = widget.clip!.duration - size.width / newZoom;
  final clampedScroll = newScrollOffset.clamp(0.0, maxScroll.clamp(0.0, double.infinity));

  widget.onZoomChange?.call(newZoom);
  widget.onScrollChange?.call(clampedScroll);
}
```

### E2. Animated Zoom Transitions

**Dodati AnimationController za smooth zoom:**
```dart
class _ClipEditorState extends State<ClipEditor> with SingleTickerProviderStateMixin {
  late AnimationController _zoomController;
  double _targetZoom = 100.0;
  double _startZoom = 100.0;
  double _targetScroll = 0.0;
  double _startScroll = 0.0;

  @override
  void initState() {
    super.initState();
    _zoomController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    )..addListener(_onZoomAnimation);
  }

  void _onZoomAnimation() {
    final t = Curves.easeOutCubic.transform(_zoomController.value);
    final zoom = _startZoom + (_targetZoom - _startZoom) * t;
    final scroll = _startScroll + (_targetScroll - _startScroll) * t;

    widget.onZoomChange?.call(zoom);
    widget.onScrollChange?.call(scroll);
  }

  void _animateZoomTo(double newZoom, double newScroll) {
    _startZoom = widget.zoom;
    _startScroll = widget.scrollOffset;
    _targetZoom = newZoom;
    _targetScroll = newScroll;
    _zoomController.forward(from: 0);
  }
}
```

---

## PART F: INSPECTOR PANEL EXTENSION

### F1. Hitpoints Inspector Section

**Fajl:** `flutter_ui/lib/widgets/layout/channel_inspector_panel.dart`

**Dodati novu sekciju za hitpointe:**
```dart
Widget _buildHitpointsSection() {
  return _CollapsibleSection(
    title: 'Hitpoints',
    icon: Icons.graphic_eq,
    expanded: _hitpointsExpanded,
    onToggle: () => setState(() => _hitpointsExpanded = !_hitpointsExpanded),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Detection controls
        Row(
          children: [
            Expanded(
              child: _MiniButton(
                label: 'Detect',
                icon: Icons.auto_fix_high,
                onTap: () => widget.onDetectHitpoints?.call(),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: _MiniButton(
                label: 'Clear',
                icon: Icons.clear_all,
                onTap: () => widget.onClearHitpoints?.call(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Sensitivity slider
        _SliderRow(
          label: 'Sensitivity',
          value: widget.hitpointSensitivity ?? 0.5,
          min: 0.1,
          max: 1.0,
          onChanged: widget.onHitpointSensitivityChange,
        ),

        // Algorithm dropdown
        _DropdownRow(
          label: 'Algorithm',
          value: widget.hitpointAlgorithm ?? 0,
          items: const [
            (0, 'Enhanced'),
            (1, 'High Freq'),
            (2, 'Low Freq'),
          ],
          onChanged: widget.onHitpointAlgorithmChange,
        ),

        const SizedBox(height: 8),

        // Hitpoint count
        Text(
          '${widget.hitpointCount ?? 0} hitpoints',
          style: TextStyle(
            fontSize: 10,
            color: FluxForgeTheme.textSecondary,
          ),
        ),

        const SizedBox(height: 8),

        // Slice operations
        Row(
          children: [
            Expanded(
              child: _MiniButton(
                label: 'Slice at Hitpoints',
                icon: Icons.content_cut,
                onTap: widget.onSliceAtHitpoints,
              ),
            ),
          ],
        ),

        const SizedBox(height: 4),

        Row(
          children: [
            Expanded(
              child: _MiniButton(
                label: 'Quantize',
                icon: Icons.grid_on,
                onTap: widget.onQuantizeHitpoints,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
```

---

## PART G: TILE CACHING SYSTEM

### G1. Tile Key Definition

**Fajl:** `flutter_ui/lib/services/waveform_cache.dart`

**Proširiti tile key:**
```dart
class WaveformTileKey {
  final String assetId;
  final String clipId;
  final int zoomLevel;  // Quantized, not raw float
  final int tileX;
  final int editorMode; // 0=normal, 1=hitpoints, 2=spectral

  WaveformTileKey({
    required this.assetId,
    required this.clipId,
    required this.zoomLevel,
    required this.tileX,
    this.editorMode = 0,
  });

  /// Quantize zoom to prevent cache explosion
  static int quantizeZoom(double framesPerPixel) {
    // Logarithmic quantization: 1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024...
    if (framesPerPixel <= 1) return 1;
    return math.pow(2, (math.log(framesPerPixel) / math.ln2).floor()).toInt();
  }

  @override
  bool operator ==(Object other) =>
    other is WaveformTileKey &&
    assetId == other.assetId &&
    clipId == other.clipId &&
    zoomLevel == other.zoomLevel &&
    tileX == other.tileX &&
    editorMode == other.editorMode;

  @override
  int get hashCode => Object.hash(assetId, clipId, zoomLevel, tileX, editorMode);
}
```

### G2. Batch Tile Query

**Optimizovani batch query za smooth zoom:**
```dart
/// Query multiple tiles in single FFI call
Future<List<WaveformTile>> queryTilesBatch(List<WaveformTileKey> keys) async {
  if (keys.isEmpty) return [];

  // Check cache first
  final cached = <WaveformTile>[];
  final uncached = <WaveformTileKey>[];

  for (final key in keys) {
    final tile = _tileCache[key];
    if (tile != null) {
      cached.add(tile);
      _touchTile(key); // LRU update
    } else {
      uncached.add(key);
    }
  }

  if (uncached.isEmpty) return cached;

  // Batch FFI call for uncached tiles
  final newTiles = await _fetchTilesBatch(uncached);

  // Store in cache
  for (int i = 0; i < uncached.length && i < newTiles.length; i++) {
    _storeTile(uncached[i], newTiles[i]);
  }

  return [...cached, ...newTiles];
}

Future<List<WaveformTile>> _fetchTilesBatch(List<WaveformTileKey> keys) async {
  // Build query array: [clipId, startFrame, endFrame, pixelWidth] × N
  final queryData = Float64List(keys.length * 4);

  for (int i = 0; i < keys.length; i++) {
    final key = keys[i];
    final clipIdInt = int.tryParse(key.clipId) ?? 0;
    final startFrame = key.tileX * kTileWidth * key.zoomLevel;
    final endFrame = startFrame + kTileWidth * key.zoomLevel;

    queryData[i * 4 + 0] = clipIdInt.toDouble();
    queryData[i * 4 + 1] = startFrame.toDouble();
    queryData[i * 4 + 2] = endFrame.toDouble();
    queryData[i * 4 + 3] = kTileWidth.toDouble();
  }

  // Single FFI call
  final results = NativeFFI.instance.queryWaveformTilesBatch(queryData);

  // Parse results into tiles
  return _parseWaveformResults(results, keys.length);
}
```

---

## TESTING CHECKLIST

### Unit Tests (Rust)

- [ ] `test_transient_detection_impulse` - Detect clear impulses
- [ ] `test_transient_detection_drums` - Detect kick/snare in drum loop
- [ ] `test_hitpoint_crud` - Create/read/update/delete hitpoints
- [ ] `test_waveform_bucket_transient` - Transient field populated
- [ ] `test_lod_level_0_samples` - Raw sample query works

### Integration Tests (Flutter)

- [ ] `test_detect_transients_ffi` - FFI call returns valid data
- [ ] `test_hitpoint_visualization` - Markers render at correct positions
- [ ] `test_zoom_to_cursor` - Zoom maintains cursor position
- [ ] `test_tile_cache_batch` - Batch query faster than individual

### Performance Tests

- [ ] Zoom 8x-50000x within 100ms (no jank)
- [ ] 100 hitpoints render at 60fps
- [ ] 1 hour audio file transient detection < 5s
- [ ] Tile cache hit rate > 90% during normal editing

---

## IMPLEMENTATION ORDER

1. **Phase 1 (Backend):** WaveformBucket extension + Transient FFI exports
2. **Phase 2 (FFI Bindings):** Dart wrappers + basic tests
3. **Phase 3 (UI):** Hitpoint rendering + detection toolbar
4. **Phase 4 (Polish):** Smooth zoom + tile caching + inspector panel
5. **Phase 5 (QA):** Full test suite + performance validation

**Estimated LOC Changes:**
- Rust: ~400 lines
- Dart FFI: ~200 lines
- Flutter UI: ~300 lines
- Tests: ~200 lines

**Total: ~1100 lines of focused changes**
