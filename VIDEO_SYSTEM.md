# VIDEO_SYSTEM.md — FluxForge Studio Ultimate Video Architecture

> **Status:** Architecture Specification
> **Date:** 2026-03-03
> **Scope:** Cross-platform video playback, iMovie-style editing, portfolio/presentation export
> **Platforms:** macOS, Windows, Linux, iOS, Android, Web (progressive)

---

## Table of Contents

1. [Vision & Goals](#1-vision--goals)
2. [Existing Infrastructure Audit](#2-existing-infrastructure-audit)
3. [Architecture Overview](#3-architecture-overview)
4. [Layer 1 — Rust Video Engine (rf-video)](#4-layer-1--rust-video-engine-rf-video)
5. [Layer 2 — FFI Bridge](#5-layer-2--ffi-bridge)
6. [Layer 3 — Flutter Playback (media_kit)](#6-layer-3--flutter-playback-media_kit)
7. [Layer 4 — Editing Engine](#7-layer-4--editing-engine)
8. [Layer 5 — Title & Overlay System](#8-layer-5--title--overlay-system)
9. [Layer 6 — Transition System](#9-layer-6--transition-system)
10. [Layer 7 — Export Pipeline](#10-layer-7--export-pipeline)
11. [Layer 8 — iMovie-Style Editor UI](#11-layer-8--imovie-style-editor-ui)
12. [Cross-Platform Strategy](#12-cross-platform-strategy)
13. [Format Support Matrix](#13-format-support-matrix)
14. [Implementation Phases](#14-implementation-phases)
15. [Dependency Map](#15-dependency-map)
16. [Risk Mitigation](#16-risk-mitigation)

---

## 1. Vision & Goals

FluxForge Studio postaje **full video-capable DAW/NLE hybrid** — ne samo audio, već i video editing, prezentacioni videi, portfolio, slot redesign showcase. Cilj:

- **All-format playback** — MP4, MOV, MKV, AVI, WebM, ProRes, DNxHD, H.264, H.265/HEVC, VP9, AV1
- **iMovie-style editing** — timeline cut/trim/split, transitions (dissolve/wipe/slide/zoom), titles/plaques, Ken Burns, PiP
- **Portfolio/Presentation videos** — title cards, animated text, logo overlays, background music, professional export
- **Cross-platform** — macOS, Windows, Linux, iOS, Android (Web progressive)
- **Zero format gaps** — svaki format koji korisnik baci u app MORA da radi
- **Professional timecode** — SMPTE NDF/DF (already implemented in rf-video)
- **GPU-accelerated** — hardware decode + texture upload where available
- **A/V sync** — sample-accurate audio-video synchronization

---

## 2. Existing Infrastructure Audit

### 2.1 Rust Crate: `rf-video` (2052 LOC)

| Module | Status | What Works | Gaps |
|--------|--------|------------|------|
| `lib.rs` | ✅ Solid | `VideoPlayer`, `VideoEngine`, `VideoTrack`, `VideoClip`, `PlaybackState` | Multi-clip provider wiring |
| `decoder.rs` | ⚠️ Partial | MP4 metadata parsing, `FfmpegDecoder` behind feature gate | FFmpeg feature OFF by default → placeholders only |
| `frame_cache.rs` | ✅ Solid | LRU cache, preload, configurable (120/300/30 frames) | Minor: `get()` uses write lock |
| `timecode.rs` | ✅ Complete | SMPTE NDF/DF, all standard rates, parse/format/arithmetic | `start_timecode` never populated from file |
| `thumbnail.rs` | ✅ Solid | `ThumbnailGenerator`, `ThumbnailStrip`, composite | Real thumbnails need FFmpeg backend |

### 2.2 FFI Layer (`rf-engine/src/ffi.rs`)

`VIDEO_ENGINE` — `lazy_static! RwLock<VideoEngine>`, 10+ C functions exposed:
- `video_add_track`, `video_import`, `video_set_playhead`, `video_get_frame`
- `video_get_info_json`, `video_generate_thumbnails`, `video_clear_all`
- `video_format_timecode`, `video_parse_timecode`

**Status:** All FFI bindings wired in both Rust and Dart. Bridge is complete.

### 2.3 Flutter Layer

| Component | File | Status | Notes |
|-----------|------|--------|-------|
| `VideoProvider` | `video_provider.dart` | ⚠️ Single-clip | Load, trim, seek, preview, serialize — but only 1 clip |
| `VideoTrack` | `video_track.dart` | ✅ Working | Timeline drag, thumbnails, timecode, sync offset |
| `VideoExportPanel` | `video_export_panel.dart` | ⚠️ Screen capture | Records app UI, NOT timeline export |
| `VideoExportService` | `video_export_service.dart` | ⚠️ Screen capture | Frame capture → PNG → FFmpeg subprocess |

### 2.4 Critical Gaps Summary

1. **No real pixel decoding** — FFmpeg feature disabled, all frames are placeholder gradients
2. **No GPU texture display** — `VideoFrame.to_rgba()` exists but no path to Flutter widget
3. **Single clip only** — `VideoProvider` supports 1 clip, `VideoEngine` supports multi-track
4. **No non-MP4 formats** — Pure Rust decoder only reads MP4 containers
5. **No trim handles UI** — `trimVideo()` exists but no visual drag handles
6. **No audio extraction from video** — Metadata parsed but no actual audio demux
7. **Screen recording ≠ NLE export** — No compositing renderer for timeline export
8. **No title/overlay/transition system** — No iMovie-style features
9. **No EDL/AAF import** — Only mentioned in docs
10. **Timecode formatting duplicated** — In provider AND widget, should be single source

---

## 3. Architecture Overview

**Three-Tier Hybrid Architecture — Cross-Platform:**

```
┌─────────────────────────────────────────────────────────────┐
│                     Flutter UI Layer                         │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌─────────────┐ │
│  │ Timeline  │  │ Preview  │  │ Title    │  │ Export      │ │
│  │ Editor    │  │ Monitor  │  │ Editor   │  │ Settings    │ │
│  └─────┬────┘  └────┬─────┘  └────┬─────┘  └──────┬──────┘ │
│        │            │             │               │         │
│  ┌─────┴────────────┴─────────────┴───────────────┴──────┐  │
│  │              VideoEditingProvider (Dart)               │  │
│  │  ┌────────────┐ ┌──────────┐ ┌────────────────────┐   │  │
│  │  │ EditModel   │ │ UndoStack│ │ TransitionManager  │   │  │
│  │  │ (project)   │ │ (cmds)   │ │ (GLSL/shader)      │   │  │
│  │  └────────────┘ └──────────┘ └────────────────────┘   │  │
│  └───────────────────────┬───────────────────────────────┘  │
├──────────────────────────┼──────────────────────────────────┤
│        Playback          │          Export                   │
│  ┌──────────────┐   ┌────┴────────────────┐                 │
│  │  media_kit    │   │  Rust FFmpeg Pipeline│                │
│  │  (libmpv)     │   │  (rf-video-export)   │                │
│  │  Cross-plat   │   │  Cross-plat          │                │
│  └──────────────┘   └─────────────────────┘                 │
├─────────────────────────────────────────────────────────────┤
│                    Rust Engine Layer                         │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌─────────────┐ │
│  │ rf-video  │  │ rf-video │  │ rf-video │  │ rf-video    │ │
│  │ (decode)  │  │ (cache)  │  │ (timecde)│  │ (export)    │ │
│  └──────────┘  └──────────┘  └──────────┘  └─────────────┘ │
│  ┌──────────────────────────────────────────────────────┐   │
│  │         FFmpeg C Libraries (linked via ffmpeg-next)   │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### Why Three Tiers?

| Tier | Technology | Role | Cross-Platform |
|------|-----------|------|----------------|
| **Playback** | `media_kit` (libmpv/FFmpeg) | Real-time preview, all formats | ✅ macOS, Win, Linux, iOS, Android, Web |
| **Decode/Cache** | `rf-video` + FFmpeg | Frame-accurate decode, thumbnail gen | ✅ via FFmpeg libs |
| **Export** | Rust FFmpeg pipeline | Final render with filters, titles, transitions | ✅ FFmpeg is universal |

**Rationale:**
- `media_kit` handles playback effortlessly on all platforms — no need to reinvent
- Rust FFmpeg handles frame-accurate operations (decode specific frame, export with filters)
- Flutter handles UI, editing model, undo/redo, title overlay rendering

---

## 4. Layer 1 — Rust Video Engine (rf-video)

### 4.1 Enable FFmpeg Backend

**Priority: P0 — MUST DO FIRST**

```toml
# crates/rf-video/Cargo.toml
[features]
default = ["ffmpeg"]  # Enable real decoding
ffmpeg = ["dep:ffmpeg-next"]
```

Cross-platform FFmpeg distribution:
- **macOS:** `brew install ffmpeg` or bundle FFmpeg dylibs in app
- **Windows:** Static FFmpeg libs from gyan.dev or BtbN builds
- **Linux:** System FFmpeg (`apt install libavcodec-dev libavformat-dev libavutil-dev libswscale-dev`)
- **iOS/Android:** Pre-built FFmpeg via `ffmpeg-kit` (mobile-specific builds)

### 4.2 Enhanced Decoder

Extend `FfmpegDecoder` za dodatne formate:

```rust
// New capabilities needed in decoder.rs
impl FfmpegDecoder {
    /// Hardware-accelerated decode (platform-specific)
    pub fn open_with_hwaccel(path: &str) -> VideoResult<Self> {
        // Try: VideoToolbox (macOS/iOS), NVDEC (Win/Linux), VAAPI (Linux), MediaCodec (Android)
        // Fallback: software decode
    }

    /// Extract audio stream as PCM samples
    pub fn decode_audio_range(
        &mut self,
        start_sample: u64,
        num_samples: u64,
        target_sample_rate: u32,
    ) -> VideoResult<Vec<f32>> { ... }

    /// Get embedded timecode (ProRes, MXF)
    pub fn read_start_timecode(&self) -> Option<Timecode> { ... }

    /// Probe format without full open
    pub fn probe(path: &str) -> VideoResult<VideoInfo> { ... }
}
```

### 4.3 New: Video Edit Model (Rust side)

```rust
/// Edit Decision — represents one edit operation
pub struct EditDecision {
    pub id: u64,
    pub clip_id: u64,
    pub source_path: String,
    pub source_in: u64,      // frame
    pub source_out: u64,     // frame
    pub timeline_in: u64,    // frame
    pub timeline_out: u64,   // frame
    pub speed: f64,          // 0.25 - 4.0
    pub opacity: f64,        // 0.0 - 1.0
    pub audio_volume: f64,   // 0.0 - 1.0
    pub transitions: (Option<TransitionDef>, Option<TransitionDef>), // in/out
}

/// Transition Definition
pub struct TransitionDef {
    pub kind: TransitionKind,
    pub duration_frames: u32,
}

pub enum TransitionKind {
    CrossDissolve,
    DipToBlack,
    DipToWhite,
    WipeLeft,
    WipeRight,
    WipeUp,
    WipeDown,
    SlideLeft,
    SlideRight,
    ZoomIn,
    ZoomOut,
    Custom(String), // GLSL shader name
}
```

---

## 5. Layer 2 — FFI Bridge

### 5.1 New FFI Functions

Extend existing `VIDEO_ENGINE` FFI with editing + export functions:

```rust
// --- Editing ---
#[no_mangle] pub extern "C" fn video_split_clip(clip_id: u64, at_frame: u64) -> u64;
#[no_mangle] pub extern "C" fn video_trim_clip(clip_id: u64, new_in: u64, new_out: u64) -> bool;
#[no_mangle] pub extern "C" fn video_move_clip(clip_id: u64, new_timeline_start: u64) -> bool;
#[no_mangle] pub extern "C" fn video_delete_clip(clip_id: u64) -> bool;
#[no_mangle] pub extern "C" fn video_set_clip_speed(clip_id: u64, speed: f64) -> bool;
#[no_mangle] pub extern "C" fn video_set_clip_opacity(clip_id: u64, opacity: f64) -> bool;

// --- Transitions ---
#[no_mangle] pub extern "C" fn video_set_transition(
    clip_id: u64, position: u8, // 0=in, 1=out
    kind: *const c_char, duration_frames: u32
) -> bool;
#[no_mangle] pub extern "C" fn video_remove_transition(clip_id: u64, position: u8) -> bool;

// --- Audio from Video ---
#[no_mangle] pub extern "C" fn video_extract_audio(
    clip_id: u64, out_samples: *mut f32, out_count: *mut u64,
    target_sample_rate: u32
) -> bool;

// --- Export ---
#[no_mangle] pub extern "C" fn video_export_start(config_json: *const c_char) -> bool;
#[no_mangle] pub extern "C" fn video_export_progress() -> f32; // 0.0 - 1.0
#[no_mangle] pub extern "C" fn video_export_cancel() -> bool;
#[no_mangle] pub extern "C" fn video_export_status() -> *mut c_char; // JSON status

// --- Frame-accurate seek ---
#[no_mangle] pub extern "C" fn video_decode_frame_rgba(
    clip_id: u64, frame_number: u64,
    target_width: u32, target_height: u32,
    out_data: *mut u8, out_size: *mut u64
) -> bool;
```

---

## 6. Layer 3 — Flutter Playback (media_kit)

### 6.1 Why media_kit

| Feature | media_kit | video_player | fvp | flutter_vlc |
|---------|-----------|-------------|-----|-------------|
| **Engine** | libmpv (FFmpeg) | Platform native | libmdk | libVLC |
| **Formats** | ALL | Limited | ALL | ALL |
| **HW accel** | ✅ Auto | ✅ | ✅ | ✅ |
| **macOS** | ✅ | ✅ | ✅ | ⚠️ |
| **Windows** | ✅ | ✅ | ✅ | ✅ |
| **Linux** | ✅ | ⚠️ | ✅ | ✅ |
| **iOS** | ✅ | ✅ | ✅ | ⚠️ |
| **Android** | ✅ | ✅ | ✅ | ✅ |
| **Web** | ✅ | ✅ | ❌ | ❌ |
| **Alpha/PiP** | ✅ | ❌ | ✅ | ❌ |
| **Frame callback** | ✅ | ❌ | ❌ | ❌ |
| **Seek accuracy** | Frame-level | Keyframe | Frame-level | Keyframe |
| **Texture output** | ✅ Native | ✅ | ✅ | ✅ |
| **Maturity** | ★★★★★ | ★★★★ | ★★★ | ★★★ |

**Winner: `media_kit`** — most complete, best format coverage, frame callbacks, GPU texture output, all platforms.

### 6.2 Integration Plan

```yaml
# pubspec.yaml additions
dependencies:
  media_kit: ^1.1.10
  media_kit_video: ^1.2.4
  media_kit_libs_macos_video: ^1.1.4        # macOS
  media_kit_libs_windows_video: ^1.0.9      # Windows
  media_kit_libs_linux: ^1.1.3              # Linux
  media_kit_libs_ios_video: ^1.1.4          # iOS
  media_kit_libs_android_video: ^1.3.6      # Android
```

### 6.3 VideoPlaybackService (new)

```dart
class VideoPlaybackService {
  late final Player _player;
  late final VideoController _controller;

  // Preview monitor widget
  Widget get previewWidget => Video(controller: _controller);

  Future<void> open(String path) async { ... }
  Future<void> seekToFrame(int frame, double fps) async { ... }
  Future<void> seekToTimecode(Timecode tc) async { ... }
  void setPlaybackRate(double rate) { ... }
  void setVolume(double volume) { ... }

  // Frame extraction for thumbnails
  Stream<Uint8List> frameStream({int width = 160}) { ... }
}
```

---

## 7. Layer 4 — Editing Engine

### 7.1 Project Model (Dart)

```dart
/// Root project model for video editing
class VideoProject {
  String id;
  String name;
  VideoTimeline timeline;
  List<MediaAsset> mediaPool;
  ProjectSettings settings;
  DateTime created;
  DateTime modified;
}

class VideoTimeline {
  List<VideoEditTrack> videoTracks;   // V1, V2, V3...
  List<AudioEditTrack> audioTracks;   // A1, A2, A3...
  TitleTrack titleTrack;              // Overlay titles
  double fps;
  int durationFrames;
}

class VideoEditTrack {
  String id;
  String name;
  List<VideoEditClip> clips;
  bool visible;
  bool locked;
  double opacity; // track-level
}

class VideoEditClip {
  String id;
  String sourceAssetId;       // ref to MediaAsset
  int timelineInFrame;        // where on timeline
  int timelineOutFrame;
  int sourceInFrame;          // in-point in source
  int sourceOutFrame;         // out-point in source
  double speed;               // 0.25 - 4.0
  double opacity;             // 0.0 - 1.0
  double audioVolume;
  TransitionDef? transitionIn;
  TransitionDef? transitionOut;
  KenBurnsEffect? kenBurns;
  List<VideoFilter> filters;
}

class MediaAsset {
  String id;
  String path;
  String name;
  Duration duration;
  double fps;
  int width, height;
  String codec;
  bool hasAudio;
  Uint8List? thumbnail;
}
```

### 7.2 Command Pattern (Undo/Redo)

```dart
abstract class EditCommand {
  String get description;
  void execute(VideoProject project);
  void undo(VideoProject project);
}

class SplitClipCommand extends EditCommand {
  final String clipId;
  final int framePosition;
  // ... stores original state for undo
}

class TrimClipCommand extends EditCommand { ... }
class MoveClipCommand extends EditCommand { ... }
class DeleteClipCommand extends EditCommand { ... }
class AddTransitionCommand extends EditCommand { ... }
class AddTitleCommand extends EditCommand { ... }
class SetSpeedCommand extends EditCommand { ... }
class SetOpacityCommand extends EditCommand { ... }

class UndoStack {
  final List<EditCommand> _undoStack = [];
  final List<EditCommand> _redoStack = [];
  static const int maxUndoLevels = 100;

  void execute(EditCommand cmd, VideoProject project) {
    cmd.execute(project);
    _undoStack.add(cmd);
    _redoStack.clear();
    if (_undoStack.length > maxUndoLevels) _undoStack.removeAt(0);
  }

  void undo(VideoProject project) { ... }
  void redo(VideoProject project) { ... }
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
}
```

### 7.3 VideoEditingProvider

```dart
class VideoEditingProvider extends ChangeNotifier {
  VideoProject? _project;
  final UndoStack _undoStack = UndoStack();
  final VideoPlaybackService _playback;

  // Project management
  void newProject(String name, {double fps = 30.0}) { ... }
  Future<void> openProject(String path) async { ... }
  Future<void> saveProject(String path) async { ... }

  // Media pool
  Future<MediaAsset> importMedia(String path) async { ... }

  // Timeline editing
  void addClipToTimeline(String assetId, String trackId, int framePos) { ... }
  void splitClip(String clipId, int frame) { ... }
  void trimClip(String clipId, {int? newIn, int? newOut}) { ... }
  void moveClip(String clipId, int newFrame, {String? newTrackId}) { ... }
  void deleteClip(String clipId) { ... }
  void setClipSpeed(String clipId, double speed) { ... }

  // Transitions
  void addTransition(String clipId, TransitionDef def, {bool atEnd = false}) { ... }
  void removeTransition(String clipId, {bool atEnd = false}) { ... }

  // Undo/Redo
  void undo() { ... }
  void redo() { ... }

  // Playback
  void play() { ... }
  void pause() { ... }
  void seekToFrame(int frame) { ... }
  int get playheadFrame;
  bool get isPlaying;
}
```

---

## 8. Layer 5 — Title & Overlay System

### 8.1 Title Types (iMovie-style)

```dart
enum TitleStyle {
  // Standard
  standard,         // Centered white text
  lowerThird,       // Bottom-left with bar

  // Cinematic
  fadeIn,           // Fade in center, fade out
  typewriter,       // Character-by-character reveal

  // Fun
  popUp,           // Scale bounce in
  drift,           // Gentle float/drift

  // Professional
  gradient,        // Gradient background bar
  split,           // Split screen text
  endCredits,      // Scrolling end credits

  // Custom
  custom,          // User-defined position, font, animation
}

class TitleClip {
  String id;
  int timelineInFrame;
  int timelineOutFrame;
  TitleStyle style;
  String text;
  String? subtitle;
  TextStyle textStyle;         // Font, size, color, shadow
  Alignment alignment;
  EdgeInsets padding;
  Color? backgroundColor;
  double backgroundOpacity;

  // Animation
  Duration fadeInDuration;
  Duration fadeOutDuration;
  Curve fadeInCurve;
  Curve fadeOutCurve;

  // Logo overlay
  String? logoPath;
  Alignment? logoAlignment;
  Size? logoSize;
}
```

### 8.2 Title Rendering

Two rendering paths:
1. **Preview (Flutter)** — `CustomPainter` renders titles as overlay on `Video` widget
2. **Export (Rust/FFmpeg)** — `drawtext` filter or pre-rendered PNG overlay

```dart
class TitleOverlayPainter extends CustomPainter {
  final TitleClip title;
  final double progress; // 0.0 - 1.0 within title duration

  @override
  void paint(Canvas canvas, Size size) {
    final opacity = _calculateOpacity(progress);
    final position = _calculatePosition(progress, size);
    // Draw background, text, logo with calculated transforms
  }
}
```

### 8.3 Plaque System (Portfolio Presentations)

```dart
class PlaqueTemplate {
  String name;
  Color backgroundColor;
  Color textColor;
  String? backgroundImage;
  double borderRadius;
  List<PlaqueElement> elements; // text, image, shape, logo
  Duration displayDuration;
  TransitionDef? transitionIn;
  TransitionDef? transitionOut;
}

class PlaqueElement {
  PlaqueElementType type; // text, image, shape, divider
  Alignment alignment;
  Offset offset;
  Size size;
  // Type-specific data
  String? text;
  TextStyle? textStyle;
  String? imagePath;
  Color? shapeColor;
}
```

---

## 9. Layer 6 — Transition System

### 9.1 Built-in Transitions

| Category | Transitions | Duration Default |
|----------|------------|------------------|
| **Dissolve** | Cross Dissolve, Dip to Black, Dip to White | 1.0s |
| **Wipe** | Wipe Left/Right/Up/Down, Clock Wipe, Barn Door | 0.75s |
| **Slide** | Slide Left/Right/Up/Down, Push | 0.5s |
| **Zoom** | Zoom In/Out, Zoom Through | 0.75s |
| **Blur** | Blur Dissolve, Gaussian Transition | 1.0s |
| **Page** | Page Curl, Page Turn | 1.0s |

### 9.2 GLSL Shader Transitions

Leveraging **GL Transitions** (open-source, 80+ effects):

```dart
class ShaderTransition {
  final String name;
  final String glslSource;   // Fragment shader
  final Map<String, double> uniforms; // Configurable params
  final Duration defaultDuration;
}

class TransitionRenderer {
  // Preview: Flutter FragmentShader API
  ui.FragmentShader _compile(String glsl) { ... }

  void renderFrame(Canvas canvas, Size size, {
    required ui.Image fromFrame,
    required ui.Image toFrame,
    required double progress, // 0.0 - 1.0
  }) {
    _shader.setFloat(0, progress);
    _shader.setImageSampler(0, fromFrame);
    _shader.setImageSampler(1, toFrame);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..shader = _shader);
  }
}
```

### 9.3 Export Transition Rendering

Za export, dve opcije:
1. **FFmpeg `xfade` filter** — built-in transitions (fade, wipeleft, slideright, etc.)
2. **Pre-rendered frames** — Flutter renders transition frames → feed to FFmpeg as image sequence

```rust
// Rust export pipeline — xfade approach
fn build_transition_filter(kind: &TransitionKind, duration_secs: f64, offset_secs: f64) -> String {
    match kind {
        TransitionKind::CrossDissolve =>
            format!("xfade=transition=fade:duration={}:offset={}", duration_secs, offset_secs),
        TransitionKind::WipeLeft =>
            format!("xfade=transition=wipeleft:duration={}:offset={}", duration_secs, offset_secs),
        TransitionKind::SlideRight =>
            format!("xfade=transition=slideright:duration={}:offset={}", duration_secs, offset_secs),
        // ... etc
        TransitionKind::Custom(shader) =>
            format!("xfade=transition=custom:expr='{}':duration={}:offset={}",
                    shader, duration_secs, offset_secs),
    }
}
```

---

## 10. Layer 7 — Export Pipeline

### 10.1 Architecture

```
┌──────────────────────────────────────────────┐
│              Export Controller (Dart)          │
│  ┌────────────────────────────────────────┐   │
│  │  1. Build FFmpeg filter graph           │   │
│  │  2. Pre-render titles as PNG sequence   │   │
│  │  3. Send config to Rust via FFI         │   │
│  │  4. Monitor progress via FFI callback   │   │
│  └────────────────┬───────────────────────┘   │
├───────────────────┼──────────────────────────┤
│  Rust Export Engine (rf-video-export)          │
│  ┌────────────────┴───────────────────────┐   │
│  │  FFmpeg pipeline:                       │   │
│  │  input₁ → decode → scale →┐             │   │
│  │  input₂ → decode → scale →├→ xfade →┐  │   │
│  │  input₃ → decode → scale →┘          │  │   │
│  │  titles_overlay.png ─────────────────→│  │   │
│  │  audio₁ → decode → amix ────────────→│  │   │
│  │                                ┌──────┘  │   │
│  │                                ▼         │   │
│  │                         encode → mux     │   │
│  │                           ▼              │   │
│  │                      output.mp4/mov/webm │   │
│  └──────────────────────────────────────────┘   │
└──────────────────────────────────────────────┘
```

### 10.2 Export Presets

```dart
enum ExportPreset {
  // Social media
  youtube4K(width: 3840, height: 2160, fps: 60, bitrate: '50M', codec: 'h264'),
  youtube1080(width: 1920, height: 1080, fps: 30, bitrate: '10M', codec: 'h264'),
  instagram(width: 1080, height: 1080, fps: 30, bitrate: '5M', codec: 'h264'),
  instagramStory(width: 1080, height: 1920, fps: 30, bitrate: '5M', codec: 'h264'),
  tiktok(width: 1080, height: 1920, fps: 30, bitrate: '8M', codec: 'h264'),

  // Professional
  prores422(width: 1920, height: 1080, fps: 24, bitrate: null, codec: 'prores'),
  prores4444(width: 1920, height: 1080, fps: 24, bitrate: null, codec: 'prores'),
  dnxhd(width: 1920, height: 1080, fps: 30, bitrate: '185M', codec: 'dnxhd'),

  // Web
  webm(width: 1920, height: 1080, fps: 30, bitrate: '4M', codec: 'vp9'),
  av1(width: 1920, height: 1080, fps: 30, bitrate: '4M', codec: 'av1'),
  gif(width: 640, height: 480, fps: 15, bitrate: null, codec: 'gif'),

  // Custom
  custom;
}
```

### 10.3 Export Configuration

```dart
class ExportConfig {
  ExportPreset preset;
  String outputPath;
  int width, height;
  double fps;
  String videoCodec;        // h264, h265, prores, vp9, av1
  String? videoBitrate;     // e.g., '10M'
  int? crf;                 // quality (lower = better, 0-51)
  String audioCodec;        // aac, pcm_s24le, opus, vorbis
  int audioSampleRate;      // 44100, 48000, 96000
  String audioBitrate;      // '320k', '256k'
  String container;         // mp4, mov, mkv, webm
  bool includeAudio;

  // Range
  int? startFrame;
  int? endFrame;

  // Hardware acceleration
  bool useHwAccel;          // VideoToolbox/NVENC/VAAPI
}
```

---

## 11. Layer 8 — iMovie-Style Editor UI

### 11.1 Main Layout

```
┌─────────────────────────────────────────────────────────────────┐
│  ┌─────────────┐  ┌──────────────────────┐  ┌───────────────┐  │
│  │  Media       │  │  Preview Monitor     │  │  Inspector    │  │
│  │  Browser     │  │  ┌────────────────┐  │  │  ┌─────────┐  │  │
│  │  ┌─────────┐ │  │  │                │  │  │  │ Clip    │  │  │
│  │  │ Import  │ │  │  │   VIDEO        │  │  │  │ Speed   │  │  │
│  │  │ Clips   │ │  │  │   PREVIEW      │  │  │  │ Opacity │  │  │
│  │  │ Titles  │ │  │  │                │  │  │  │ Volume  │  │  │
│  │  │ Audio   │ │  │  │                │  │  │  │ Effects │  │  │
│  │  │ Plaques │ │  │  └────────────────┘  │  │  │ Color   │  │  │
│  │  └─────────┘ │  │  TC: 01:02:03:04     │  │  └─────────┘  │  │
│  └─────────────┘  └──────────────────────┘  └───────────────┘  │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │  Timeline                                                    ││
│  │  V2 ░░░░░░░░░░░░░░░░░░░░░░░░░░░░ (title overlay track)    ││
│  │  V1 ████████████░░░░████████████░░░░██████████████          ││
│  │  A1 ▓▓▓▓▓▓▓▓▓▓▓▓░░░░▓▓▓▓▓▓▓▓▓▓▓▓░░░░▓▓▓▓▓▓▓▓▓▓▓▓▓▓          ││
│  │  A2 ░░░░░░░▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░          ││
│  │  [◀ ▶ ⏸ ⏹]  TC: 01:02:03:04  Duration: 00:05:30:00        ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

### 11.2 Key UI Components

| Component | Description |
|-----------|------------|
| **MediaBrowser** | Import panel with grid/list view, drag-to-timeline |
| **PreviewMonitor** | `media_kit` Video widget with title overlay, timecode display |
| **Inspector** | Context-sensitive: clip properties, title editor, transition picker |
| **Timeline** | Multi-track, drag clips, trim handles, transition zones, thumbnails |
| **TransportBar** | Play/pause/stop, JKL shuttle, timecode scrub, markers |
| **TransitionPicker** | Visual grid of available transitions with preview |
| **TitleEditor** | WYSIWYG title editing with fonts, colors, animations |
| **ExportDialog** | Preset picker, custom settings, progress bar |

### 11.3 Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Space` | Play/Pause |
| `J/K/L` | Rewind/Pause/Forward (shuttle) |
| `I` | Set in-point |
| `O` | Set out-point |
| `B` | Blade (split at playhead) |
| `Delete` | Delete selected clip |
| `⌘Z / Ctrl+Z` | Undo |
| `⌘⇧Z / Ctrl+Y` | Redo |
| `⌘E / Ctrl+E` | Export |
| `⌘T / Ctrl+T` | Add title |
| `⌘I / Ctrl+I` | Import media |
| `←/→` | Frame step |
| `⇧←/⇧→` | 10-frame step |

---

## 12. Cross-Platform Strategy

### 12.1 Platform-Specific Considerations

| Layer | macOS | Windows | Linux | iOS | Android | Web |
|-------|-------|---------|-------|-----|---------|-----|
| **Playback** | media_kit ✅ | media_kit ✅ | media_kit ✅ | media_kit ✅ | media_kit ✅ | media_kit ✅ |
| **HW Decode** | VideoToolbox | DXVA2/D3D11 | VAAPI/VDPAU | VideoToolbox | MediaCodec | Browser |
| **HW Encode** | VideoToolbox | NVENC/QSV/AMF | NVENC/VAAPI | VideoToolbox | MediaCodec | ❌ |
| **FFmpeg libs** | Homebrew/bundled | Static build | System package | ffmpeg-kit | ffmpeg-kit | ❌ |
| **Rust FFI** | dylib ✅ | dll ✅ | so ✅ | static lib ✅ | JNI/so ✅ | WASM ⚠️ |
| **File access** | Full ✅ | Full ✅ | Full ✅ | Sandboxed ⚠️ | Sandboxed ⚠️ | Very limited |
| **GPU shaders** | Metal | D3D/Vulkan | Vulkan/GL | Metal | Vulkan/GL | WebGL |

### 12.2 Mobile Adaptations (iOS/Android)

- **Simplified timeline** — Single video track + single audio track (no multi-track on mobile)
- **Touch gestures** — Pinch zoom on timeline, swipe trim, long-press for context menu
- **Reduced export presets** — No ProRes/DNxHD, focus on H.264/H.265
- **Memory management** — Lower frame cache (30 frames), thumbnail-only preview for long clips
- **ffmpeg-kit** — Pre-compiled FFmpeg for mobile (replaces system FFmpeg)

### 12.3 Web Limitations

- **No Rust FFI** — Must use WASM compilation of rf-video (or JavaScript fallback)
- **No local file system** — Use File API, IndexedDB for project storage
- **Limited export** — Browser-based encoding via WebCodecs API or server-side
- **Progressive enhancement** — Web version focuses on preview + basic editing, export deferred to desktop

### 12.4 FFmpeg Distribution Strategy

```
macOS:
  - Development: brew install ffmpeg
  - Production: Bundle dylibs in .app (libavcodec, libavformat, libavutil, libswscale, libswresample)
  - Signing: Sign bundled libs with app certificate

Windows:
  - Bundle static FFmpeg libs (from BtbN/gyan.dev builds)
  - Or: Ship ffmpeg.exe alongside app for subprocess export

Linux:
  - System FFmpeg: apt/yum/pacman install
  - AppImage: Bundle FFmpeg libs
  - Flatpak/Snap: Include FFmpeg as dependency

iOS:
  - ffmpeg-kit-ios (pod/SPM dependency)
  - Supports VideoToolbox HW accel

Android:
  - ffmpeg-kit-android (gradle dependency)
  - Supports MediaCodec HW accel
```

---

## 13. Format Support Matrix

### 13.1 Container Formats

| Format | Extension | Decode | Encode | Notes |
|--------|-----------|--------|--------|-------|
| MP4 | .mp4 | ✅ | ✅ | Primary format |
| MOV | .mov | ✅ | ✅ | ProRes container |
| MKV | .mkv | ✅ | ✅ | Matroska |
| AVI | .avi | ✅ | ⚠️ Legacy | Legacy support |
| WebM | .webm | ✅ | ✅ | VP9/Opus |
| MXF | .mxf | ✅ | ⚠️ Pro | Broadcast |
| FLV | .flv | ✅ | ❌ | Import only |
| TS | .ts, .m2ts | ✅ | ✅ | Transport stream |
| GIF | .gif | ✅ | ✅ | Animated GIF export |

### 13.2 Video Codecs

| Codec | Decode | Encode | HW Accel | Notes |
|-------|--------|--------|----------|-------|
| H.264/AVC | ✅ | ✅ | ✅ All platforms | Universal |
| H.265/HEVC | ✅ | ✅ | ✅ Most platforms | 50% size savings |
| ProRes 422/4444 | ✅ | ✅ macOS | VideoToolbox | Professional |
| DNxHD/DNxHR | ✅ | ✅ | ❌ Software only | Avid interchange |
| VP9 | ✅ | ✅ | ⚠️ Limited | WebM standard |
| AV1 | ✅ | ✅ | ⚠️ Newer GPUs | Next-gen, slow encode |
| MJPEG | ✅ | ✅ | ❌ | Camera/legacy |
| Cinepak | ✅ | ❌ | ❌ | Legacy import |

### 13.3 Audio Codecs (in video files)

| Codec | Decode | Encode | Notes |
|-------|--------|--------|-------|
| AAC | ✅ | ✅ | MP4 standard |
| PCM (s16/s24/s32/f32) | ✅ | ✅ | Uncompressed |
| MP3 | ✅ | ✅ | Legacy |
| Opus | ✅ | ✅ | WebM standard |
| Vorbis | ✅ | ✅ | OGG/WebM |
| AC3/E-AC3 | ✅ | ✅ | Surround |
| FLAC | ✅ | ✅ | Lossless |
| ALAC | ✅ | ✅ | Apple Lossless |

### 13.4 Image Formats (for overlays/plaques)

| Format | Support | Notes |
|--------|---------|-------|
| PNG | ✅ | Titles, logos (alpha support) |
| JPEG | ✅ | Photos |
| WebP | ✅ | Modern web format |
| TIFF | ✅ | Professional |
| BMP | ✅ | Legacy |
| SVG | ✅ via Flutter | Vector graphics |

---

## 14. Implementation Phases

### Phase 1 — Foundation (P0)
**Goal:** Real video playback + basic import
**Estimated LOC:** ~3,000

- [ ] Enable FFmpeg feature in rf-video (`default = ["ffmpeg"]`)
- [ ] Integrate `media_kit` for cross-platform playback
- [ ] Create `VideoPlaybackService` wrapper
- [ ] Build `PreviewMonitor` widget (media_kit Video + timecode overlay)
- [ ] Upgrade `VideoProvider` to multi-clip support
- [ ] Wire real FFmpeg decode for thumbnails
- [ ] Test: MP4, MOV, MKV, WebM playback on macOS

### Phase 2 — Timeline Editing (P1)
**Goal:** Cut/trim/split/move clips on timeline
**Estimated LOC:** ~4,500

- [ ] Implement `VideoProject` model + JSON serialization
- [ ] Implement `EditCommand` pattern (undo/redo stack)
- [ ] Create `VideoEditingProvider` (project state management)
- [ ] Build multi-track timeline UI (`VideoEditTimeline` widget)
- [ ] Implement trim handles (drag in/out points)
- [ ] Implement blade tool (split at playhead)
- [ ] Implement clip drag/move/reorder
- [ ] Implement clip delete + ripple/overwrite modes
- [ ] Register in GetIt (Layer 6)
- [ ] Keyboard shortcuts (Space, B, I, O, Delete, JKL)

### Phase 3 — Transitions (P2)
**Goal:** Cross-dissolve, wipes, slides between clips
**Estimated LOC:** ~2,500

- [ ] Implement `TransitionDef` model
- [ ] Build transition zone UI on timeline (overlap region)
- [ ] Implement GLSL shader rendering for preview
- [ ] Create `TransitionPicker` panel with visual previews
- [ ] Implement 15+ built-in transitions
- [ ] Add transition duration drag handles
- [ ] Wire to `xfade` FFmpeg filter for export

### Phase 4 — Titles & Plaques (P3)
**Goal:** iMovie-style title cards, lower thirds, end credits
**Estimated LOC:** ~3,000

- [ ] Implement `TitleClip` model
- [ ] Build `TitleEditor` panel (WYSIWYG)
- [ ] Implement `TitleOverlayPainter` (preview rendering)
- [ ] Create 10+ built-in title templates
- [ ] Implement plaque system (`PlaqueTemplate`, `PlaqueElement`)
- [ ] Title animation system (fade, typewriter, slide, pop)
- [ ] Logo overlay support (PNG/SVG)
- [ ] Title track on timeline

### Phase 5 — Export Pipeline (P4)
**Goal:** Professional export with all filters, titles, transitions
**Estimated LOC:** ~4,000

- [ ] Create `rf-video-export` Rust crate (or extend rf-video)
- [ ] Implement FFmpeg filter graph builder
- [ ] Title pre-rendering (Flutter → PNG sequence → overlay)
- [ ] Audio mixing (video audio + timeline audio tracks)
- [ ] Export progress reporting via FFI
- [ ] Export presets (YouTube, Instagram, TikTok, ProRes, etc.)
- [ ] Export dialog UI with preview
- [ ] HW-accelerated encoding (VideoToolbox, NVENC, VAAPI)

### Phase 6 — Advanced Features (P5)
**Goal:** Ken Burns, PiP, speed ramp, color correction
**Estimated LOC:** ~3,500

- [ ] Ken Burns effect (pan/zoom keyframes)
- [ ] Picture-in-Picture (PiP) - resize + position overlay clip
- [ ] Speed changes (constant + variable speed ramp)
- [ ] Basic color correction (brightness, contrast, saturation, temperature)
- [ ] Audio extraction from video files
- [ ] Audio waveform display in video clips
- [ ] Chroma key (green screen) — basic

### Phase 7 — Cross-Platform Polish (P6)
**Goal:** Windows + Linux + mobile support
**Estimated LOC:** ~2,500

- [ ] Windows build + testing
- [ ] Linux build + testing
- [ ] iOS build + testing (simplified UI)
- [ ] Android build + testing (simplified UI)
- [ ] FFmpeg distribution for each platform
- [ ] Platform-specific HW acceleration
- [ ] Touch gesture support for mobile timeline
- [ ] File picker integration per platform

### Phase 8 — Portfolio & Presentation Mode (P7)
**Goal:** Dedicated portfolio video creation workflow
**Estimated LOC:** ~2,000

- [ ] Portfolio project template
- [ ] Plaque gallery (pre-designed templates)
- [ ] Slide show mode (image sequence with transitions)
- [ ] Background music integration (from DAW tracks)
- [ ] One-click export presets for portfolio use cases
- [ ] Project templates (portfolio, demo reel, showcase)

**Total estimated LOC: ~25,000**

---

## 15. Dependency Map

### 15.1 Rust Dependencies

```toml
# rf-video/Cargo.toml (updated)
[dependencies]
ffmpeg-next = "7.1"           # Core decode/encode
mp4 = "0.14"                  # MP4 container fallback
image = "0.25"                # Image handling
parking_lot = "0.12"          # Locks
crossbeam-channel = "0.5"     # Frame preload
serde = { version = "1", features = ["derive"] }
serde_json = "1"
thiserror = "2"

[features]
default = ["ffmpeg"]
ffmpeg = ["dep:ffmpeg-next"]
```

### 15.2 Flutter Dependencies

```yaml
# pubspec.yaml additions
dependencies:
  media_kit: ^1.1.10
  media_kit_video: ^1.2.4
  media_kit_libs_macos_video: ^1.1.4
  media_kit_libs_windows_video: ^1.0.9
  media_kit_libs_linux: ^1.1.3
  media_kit_libs_ios_video: ^1.1.4
  media_kit_libs_android_video: ^1.3.6
```

### 15.3 System Dependencies

| Platform | Required | Optional |
|----------|----------|----------|
| macOS | FFmpeg headers + libs | VideoToolbox (auto) |
| Windows | FFmpeg static libs | NVENC SDK |
| Linux | libavcodec-dev, libavformat-dev, libavutil-dev, libswscale-dev | VAAPI/VDPAU libs |
| iOS | ffmpeg-kit-ios | — |
| Android | ffmpeg-kit-android | — |

---

## 16. Risk Mitigation

### 16.1 Technical Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| FFmpeg linking issues cross-platform | Medium | High | Use pre-built static libs per platform; fallback to subprocess |
| GPU texture upload latency | Low | Medium | Double-buffer frames; use platform texture APIs |
| Large video file memory | Medium | Medium | Stream-based decode; limit cache size; thumbnail-only for long clips |
| GLSL shader compatibility | Medium | Low | Test on OpenGL ES 3.0+; fallback to CPU transitions |
| Mobile performance | Medium | Medium | Simplified UI; reduced preview resolution; proxy editing |
| HW encoder availability | Low | Low | Always have software fallback (libx264, libvpx) |

### 16.2 Architecture Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Playback engine | media_kit (libmpv) | Best cross-platform coverage, all formats, GPU |
| Editing model | Dart-side (not Rust) | Faster iteration, easier UI binding |
| Undo system | Command pattern | Industry standard, proven in NLEs |
| Export pipeline | Rust + FFmpeg | Performance-critical, CPU/GPU acceleration |
| Transitions preview | Flutter GLSL shaders | Real-time, GPU-accelerated |
| Transitions export | FFmpeg xfade filter | Efficient, no frame extraction needed |
| Title rendering | Flutter CustomPainter + pre-render PNG | WYSIWYG preview, export via overlay |
| Project format | JSON | Human-readable, easy debugging |

---

## Appendix A — Existing Code References

| File | LOC | Description |
|------|-----|-------------|
| `crates/rf-video/src/lib.rs` | ~500 | VideoPlayer, VideoEngine, VideoTrack, VideoClip |
| `crates/rf-video/src/decoder.rs` | ~600 | VideoDecoder (MP4), FfmpegDecoder (feature-gated) |
| `crates/rf-video/src/frame_cache.rs` | ~250 | LRU FrameCache, CacheConfig |
| `crates/rf-video/src/timecode.rs` | ~400 | SMPTE Timecode (NDF/DF), FrameRate |
| `crates/rf-video/src/thumbnail.rs` | ~300 | ThumbnailGenerator, ThumbnailStrip |
| `crates/rf-engine/src/ffi.rs` | (section) | VIDEO_ENGINE FFI (10+ functions) |
| `flutter_ui/lib/providers/video_provider.dart` | ~600 | VideoProvider (single-clip) |
| `flutter_ui/lib/widgets/timeline/video_track.dart` | ~800 | VideoTrack widget |
| `flutter_ui/lib/widgets/video/video_export_panel.dart` | ~500 | Screen capture export UI |
| `flutter_ui/lib/services/video_export_service.dart` | ~600 | Frame capture → FFmpeg subprocess |

## Appendix B — Key API Signatures (media_kit)

```dart
// Playback
final player = Player();
await player.open(Media('file:///path/to/video.mp4'));
await player.seek(Duration(milliseconds: 1500));
player.stream.position.listen((position) { ... });
player.stream.duration.listen((duration) { ... });
player.stream.completed.listen((completed) { ... });

// Video output
final controller = VideoController(player);
Video(controller: controller, width: 1920, height: 1080);

// Platform-specific configuration
final player = Player(
  configuration: PlayerConfiguration(
    vid: '--vid=1',         // Video stream index
    vo: '--vo=gpu',         // Video output driver
    hwdec: '--hwdec=auto',  // Hardware decoding
  ),
);
```

## Appendix C — FFmpeg Filter Graph Examples

```bash
# Cross dissolve between two clips
ffmpeg -i clip1.mp4 -i clip2.mp4 \
  -filter_complex "xfade=transition=fade:duration=1:offset=4" \
  -c:v libx264 -crf 23 output.mp4

# Title overlay (pre-rendered PNG)
ffmpeg -i video.mp4 -i title.png \
  -filter_complex "[0:v][1:v]overlay=0:0:enable='between(t,2,5)'" \
  output.mp4

# Ken Burns (pan + zoom)
ffmpeg -loop 1 -i photo.jpg \
  -vf "zoompan=z='min(zoom+0.001,1.5)':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=150" \
  -t 5 -c:v libx264 output.mp4

# Picture-in-Picture
ffmpeg -i main.mp4 -i pip.mp4 \
  -filter_complex "[1:v]scale=320:180[pip];[0:v][pip]overlay=W-w-10:H-h-10" \
  output.mp4

# Speed change (2x)
ffmpeg -i input.mp4 -filter_complex "[0:v]setpts=0.5*PTS[v];[0:a]atempo=2.0[a]" \
  -map "[v]" -map "[a]" output.mp4

# Multiple clips with transitions and titles
ffmpeg -i clip1.mp4 -i clip2.mp4 -i clip3.mp4 -i title.png \
  -filter_complex "
    [0:v][1:v]xfade=transition=wipeleft:duration=0.5:offset=4[v01];
    [v01][2:v]xfade=transition=fade:duration=1:offset=8[v012];
    [v012][3:v]overlay=0:0:enable='between(t,0,3)'[vout];
    [0:a][1:a]acrossfade=d=0.5[a01];
    [a01][2:a]acrossfade=d=1[aout]
  " -map "[vout]" -map "[aout]" -c:v libx264 -c:a aac output.mp4
```

---

*Document generated: 2026-03-03*
*Author: Claude Code — FluxForge Studio*
