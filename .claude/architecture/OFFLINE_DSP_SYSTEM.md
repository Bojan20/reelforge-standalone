# Offline DSP Processing System — P2.6 Implementation

**Status:** ✅ COMPLETE (2026-01-23)
**Author:** Claude Code
**LOC:** ~2900 total (Rust + Dart)

---

## Overview

FluxForge Offline DSP System enables non-realtime audio processing for:
- **Bounce/Mixdown** — Export timeline to audio file
- **Batch Processing** — Process multiple files in parallel
- **Normalization** — Peak, LUFS, True Peak, NoClip modes
- **Format Conversion** — WAV (16/24/32f), FLAC, MP3

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Flutter UI Layer                              │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │           OfflineProcessingProvider                      │   │
│  │  - Pipeline lifecycle management                         │   │
│  │  - Job configuration & tracking                          │   │
│  │  - Progress monitoring                                   │   │
│  │  - Batch operations                                      │   │
│  └─────────────────────────────────────────────────────────┘   │
└────────────────────────────┬────────────────────────────────────┘
                             │ FFI
┌────────────────────────────▼────────────────────────────────────┐
│                    native_ffi.dart                               │
│  - 20 FFI function bindings                                      │
│  - Type-safe Dart wrappers                                       │
│  - Memory-safe string handling                                   │
└────────────────────────────┬────────────────────────────────────┘
                             │ C ABI
┌────────────────────────────▼────────────────────────────────────┐
│                    offline_ffi.rs (~620 LOC)                     │
│  - Pipeline storage (DashMap)                                    │
│  - Job result storage                                            │
│  - Error handling                                                │
│  - JSON serialization                                            │
└────────────────────────────┬────────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────────┐
│                    rf-offline crate (~1200 LOC)                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │   Pipeline   │  │     Job      │  │  Processors  │          │
│  │  - Process   │  │  - Builder   │  │  - Gain      │          │
│  │  - Batch     │  │  - Config    │  │  - DC Offset │          │
│  │  - Progress  │  │  - Result    │  │  - Fade      │          │
│  └──────────────┘  └──────────────┘  │  - Filter    │          │
│                                       └──────────────┘          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │  Normalize   │  │ Time Stretch │  │   Formats    │          │
│  │  - Peak      │  │  - Vocoder   │  │  - WAV       │          │
│  │  - LUFS      │  │  - WSOLA     │  │  - FLAC      │          │
│  │  - TruePeak  │  │              │  │  - MP3       │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
└─────────────────────────────────────────────────────────────────┘
```

---

## Rust Crate: rf-offline

**Location:** `crates/rf-offline/`

### Module Structure

```
crates/rf-offline/
├── Cargo.toml
└── src/
    ├── lib.rs           # Public exports
    ├── error.rs         # OfflineError enum
    ├── config.rs        # OfflineConfig, OutputFormat
    ├── formats.rs       # Audio format support
    ├── job.rs           # JobBuilder, OfflineJob, JobResult
    ├── normalize.rs     # NormalizationMode, LoudnessMeter
    ├── processors.rs    # OfflineProcessor trait, ProcessorChain
    ├── time_stretch.rs  # PhaseVocoder, WsolaStretcher
    └── pipeline.rs      # OfflinePipeline, BatchProcessor, AudioBuffer
```

### Key Types

#### OfflineConfig

```rust
pub struct OfflineConfig {
    pub buffer_size: usize,        // Default: 8192
    pub num_threads: usize,        // Default: num_cpus
    pub src_quality: SrcQuality,   // Default: High
    pub dither: bool,              // Default: true
    pub normalize_before_encode: bool, // Default: true
}
```

#### OutputFormat

```rust
pub enum OutputFormat {
    Wav(WavConfig),
    Flac(FlacConfig),
    Mp3(Mp3Config),
}

impl OutputFormat {
    pub fn wav_16() -> Self;
    pub fn wav_24() -> Self;
    pub fn wav_32f() -> Self;
    pub fn flac() -> Self;
    pub fn mp3_320() -> Self;
}
```

#### NormalizationMode

```rust
pub enum NormalizationMode {
    Peak { target_db: f64 },      // Peak normalization (dBFS)
    Lufs { target_lufs: f64 },    // EBU R128 loudness (LUFS)
    TruePeak { target_db: f64 },  // ITU-R BS.1770 true peak (dBTP)
    NoClip,                        // Reduce gain only if clipping
}
```

#### JobBuilder

```rust
let job = JobBuilder::new()
    .input("/path/to/input.wav")
    .output("/path/to/output.flac")
    .sample_rate(48000)
    .normalize(NormalizationMode::Lufs { target_lufs: -14.0 })
    .fade_in(4410)   // 100ms @ 44.1kHz
    .fade_out(4410)
    .time_stretch(1.1)  // 10% slower
    .pitch_shift(2.0)   // +2 semitones
    .build()?;
```

#### OfflinePipeline

```rust
let pipeline = OfflinePipeline::new(OfflineConfig::default())
    .with_output_format(OutputFormat::flac())
    .with_normalization(NormalizationMode::Lufs { target_lufs: -14.0 });

let result = pipeline.process_job(&job)?;
```

#### BatchProcessor

```rust
let processor = BatchProcessor::new(config);
let results = processor.process_all(&jobs); // Parallel via rayon
```

### Pipeline States

```rust
pub enum PipelineState {
    Idle,        // 0 - Ready for new job
    Loading,     // 1 - Reading input file
    Analyzing,   // 2 - Measuring loudness
    Processing,  // 3 - Applying DSP
    Normalizing, // 4 - Applying normalization
    Converting,  // 5 - Sample rate conversion
    Encoding,    // 6 - Encoding to output format
    Writing,     // 7 - Writing output file
    Complete,    // 8 - Job finished successfully
    Failed,      // 9 - Job failed
    Cancelled,   // 10 - Job cancelled by user
}
```

### DSP Processors

| Processor | Description |
|-----------|-------------|
| `GainProcessor` | Linear gain (dB to linear conversion) |
| `DcOffsetProcessor` | DC offset removal via high-pass filter |
| `InvertProcessor` | Phase inversion |
| `FadeProcessor` | Fade in/out with multiple curves |
| `BiquadFilter` | TDF-II biquad (highpass, lowpass) |

#### Fade Curves

```rust
pub enum FadeCurve {
    Linear,       // y = x
    Logarithmic,  // y = log10(x * 9 + 1)
    Exponential,  // y = x²
    SCurve,       // y = (1 - cos(πx)) / 2
    EqualPower,   // y = sin(πx/2)
}
```

### Time Stretch Algorithms

| Algorithm | Use Case | Quality |
|-----------|----------|---------|
| **PhaseVocoder** | Music, tonal content | High |
| **WSOLA** | Speech, percussion | Medium |

---

## FFI Bridge: offline_ffi.rs

**Location:** `crates/rf-bridge/src/offline_ffi.rs`

### Storage

```rust
// Pipeline storage (handle → pipeline)
static PIPELINES: Lazy<DashMap<u64, Arc<RwLock<OfflinePipeline>>>> = ...;

// Job results storage (job_id → result)
static JOB_RESULTS: Lazy<DashMap<u64, JobResult>> = ...;

// Last error message
static LAST_ERROR: Lazy<RwLock<Option<String>>> = ...;
```

### FFI Functions (20 total)

#### Pipeline Lifecycle

| Function | Signature | Description |
|----------|-----------|-------------|
| `offline_pipeline_create` | `() -> u64` | Create pipeline, returns handle |
| `offline_pipeline_create_with_config` | `(*const c_char) -> u64` | Create with JSON config |
| `offline_pipeline_destroy` | `(u64)` | Destroy pipeline |
| `offline_pipeline_set_normalization` | `(u64, i32, f64)` | Set normalization mode/target |
| `offline_pipeline_set_format` | `(u64, i32)` | Set output format |

#### Job Processing

| Function | Signature | Description |
|----------|-----------|-------------|
| `offline_process_file` | `(u64, *const c_char, *const c_char) -> u64` | Process single file |
| `offline_process_file_with_options` | `(u64, *const c_char) -> u64` | Process with JSON options |

#### Progress & Status

| Function | Signature | Description |
|----------|-----------|-------------|
| `offline_pipeline_get_progress` | `(u64) -> f64` | Get progress (0.0-1.0) |
| `offline_pipeline_get_state` | `(u64) -> i32` | Get pipeline state enum |
| `offline_pipeline_get_progress_json` | `(u64) -> *mut c_char` | Get full progress as JSON |
| `offline_pipeline_cancel` | `(u64)` | Cancel processing |

#### Job Results

| Function | Signature | Description |
|----------|-----------|-------------|
| `offline_get_job_result` | `(u64) -> *mut c_char` | Get result as JSON |
| `offline_job_succeeded` | `(u64) -> bool` | Check if job succeeded |
| `offline_get_job_error` | `(u64) -> *mut c_char` | Get error message |
| `offline_clear_job_result` | `(u64)` | Clear result from storage |

#### Batch Processing

| Function | Signature | Description |
|----------|-----------|-------------|
| `offline_batch_process` | `(*const c_char) -> *mut c_char` | Process multiple files |

#### Utilities

| Function | Signature | Description |
|----------|-----------|-------------|
| `offline_get_last_error` | `() -> *mut c_char` | Get last error message |
| `offline_free_string` | `(*mut c_char)` | Free allocated string |
| `offline_get_supported_formats` | `() -> *mut c_char` | Get formats as JSON |
| `offline_get_normalization_modes` | `() -> *mut c_char` | Get modes as JSON |

---

## Dart FFI Bindings: native_ffi.dart

**Location:** `flutter_ui/lib/src/rust/native_ffi.dart`

### Typedefs Added

```dart
// Pipeline lifecycle
typedef OfflinePipelineCreateNative = Uint64 Function();
typedef OfflinePipelineCreateDart = int Function();

typedef OfflinePipelineDestroyNative = Void Function(Uint64 handle);
typedef OfflinePipelineDestroyDart = void Function(int handle);

// ... 18 more typedefs
```

### Public API Methods

```dart
class NativeFFI {
  // Pipeline lifecycle
  int offlinePipelineCreate();
  int offlinePipelineCreateWithConfig(String configJson);
  void offlinePipelineDestroy(int handle);
  void offlinePipelineSetNormalization(int handle, int mode, double target);
  void offlinePipelineSetFormat(int handle, int format);

  // Job processing
  int offlineProcessFile(int handle, String inputPath, String outputPath);
  int offlineProcessFileWithOptions(int handle, String optionsJson);

  // Progress & status
  double offlinePipelineGetProgress(int handle);
  int offlinePipelineGetState(int handle);
  String? offlinePipelineGetProgressJson(int handle);
  void offlinePipelineCancel(int handle);

  // Job results
  String? offlineGetJobResult(int jobId);
  bool offlineJobSucceeded(int jobId);
  String? offlineGetJobError(int jobId);
  void offlineClearJobResult(int jobId);

  // Batch processing
  String? offlineBatchProcess(String jobsJson);

  // Utilities
  String? offlineGetLastError();
  String? offlineGetSupportedFormats();
  String? offlineGetNormalizationModes();
}
```

---

## Flutter Provider: OfflineProcessingProvider

**Location:** `flutter_ui/lib/providers/offline_processing_provider.dart`

### Enums

```dart
enum OfflineOutputFormat {
  wav16,    // 0
  wav24,    // 1
  wav32f,   // 2
  flac,     // 3
  mp3_320,  // 4
}

enum NormalizationMode {
  none,      // 0
  peak,      // 1
  lufs,      // 2
  truePeak,  // 3
  noClip,    // 4
}

enum PipelineState {
  idle,        // 0
  loading,     // 1
  analyzing,   // 2
  processing,  // 3
  normalizing, // 4
  converting,  // 5
  encoding,    // 6
  writing,     // 7
  complete,    // 8
  failed,      // 9
  cancelled,   // 10
}
```

### Data Classes

```dart
class OfflineJobConfig {
  final String inputPath;
  final String outputPath;
  final int? sampleRate;
  final OfflineOutputFormat format;
  final NormalizationMode normalization;
  final double? normalizationTarget;
  final int? fadeInSamples;
  final int? fadeOutSamples;
  final double? timeStretchRatio;
  final double? pitchShiftSemitones;
}

class OfflineJobResult {
  final int jobId;
  final bool success;
  final String? error;
  final int inputSize;
  final int outputSize;
  final Duration duration;
  final double peakLevel;
  final double truePeak;
  final double loudness;
}

class OfflineProgress {
  final PipelineState state;
  final String stage;
  final double stageProgress;
  final double overallProgress;
  final int samplesProcessed;
  final int totalSamples;
  final Duration elapsed;
  final Duration? estimatedRemaining;
}
```

### Provider API

```dart
class OfflineProcessingProvider extends ChangeNotifier {
  // Pipeline management
  Future<bool> createPipeline();
  Future<void> destroyPipeline();
  bool get hasPipeline;

  // Configuration
  void setOutputFormat(OfflineOutputFormat format);
  void setNormalization(NormalizationMode mode, {double? target});

  // Processing
  Future<int?> processFile(String inputPath, String outputPath);
  Future<int?> processFileWithConfig(OfflineJobConfig config);
  Future<List<OfflineJobResult>?> batchProcess(List<OfflineJobConfig> jobs);

  // Progress
  OfflineProgress? get progress;
  Stream<OfflineProgress> get progressStream;
  void cancel();

  // Results
  OfflineJobResult? getResult(int jobId);
  void clearResult(int jobId);

  // State
  PipelineState get state;
  bool get isProcessing;
  String? get lastError;

  // Static info
  static List<Map<String, dynamic>> get supportedFormats;
  static List<Map<String, dynamic>> get normalizationModes;
}
```

---

## Usage Examples

### Simple File Conversion

```dart
final provider = OfflineProcessingProvider(ffi);

await provider.createPipeline();
provider.setOutputFormat(OfflineOutputFormat.flac);

final jobId = await provider.processFile(
  '/path/to/input.wav',
  '/path/to/output.flac',
);

// Wait for completion
while (provider.isProcessing) {
  await Future.delayed(Duration(milliseconds: 100));
  print('Progress: ${(provider.progress?.overallProgress ?? 0) * 100}%');
}

final result = provider.getResult(jobId!);
print('Output: ${result?.outputSize} bytes');

await provider.destroyPipeline();
```

### Batch Normalization

```dart
final jobs = audioFiles.map((path) => OfflineJobConfig(
  inputPath: path,
  outputPath: path.replaceAll('.wav', '_normalized.wav'),
  normalization: NormalizationMode.lufs,
  normalizationTarget: -14.0,  // Streaming standard
)).toList();

final results = await provider.batchProcess(jobs);

for (final result in results!) {
  print('${result.jobId}: ${result.success ? 'OK' : result.error}');
  print('  Loudness: ${result.loudness.toStringAsFixed(1)} LUFS');
}
```

### Progress Monitoring with Stream

```dart
provider.progressStream.listen((progress) {
  print('${progress.stage}: ${(progress.stageProgress * 100).toInt()}%');
  print('Overall: ${(progress.overallProgress * 100).toInt()}%');
  print('ETA: ${progress.estimatedRemaining?.inSeconds}s');
});
```

---

## Format Support

### Output Formats

| Format | Extension | Bit Depth | Lossless | Notes |
|--------|-----------|-----------|----------|-------|
| WAV 16-bit | .wav | 16 | Yes | CD quality |
| WAV 24-bit | .wav | 24 | Yes | Studio standard |
| WAV 32-bit float | .wav | 32f | Yes | Maximum headroom |
| FLAC | .flac | 16-24 | Yes | Compressed lossless |
| MP3 320kbps | .mp3 | - | No | Maximum quality lossy |

### Sample Rate Conversion

| Quality | Algorithm | CPU | Use Case |
|---------|-----------|-----|----------|
| Fast | Linear | Low | Preview |
| Medium | Cubic | Medium | General |
| High | Sinc | High | Mastering |
| Best | Sinc HQ | Very High | Archival |

---

## Tests

### rf-offline Tests (7 passing)

```
test pipeline::tests::test_audio_buffer_gain ... ok
test pipeline::tests::test_audio_buffer_mono_to_stereo ... ok
test pipeline::tests::test_audio_buffer_peak ... ok
test pipeline::tests::test_audio_buffer_stereo_to_mono ... ok
test time_stretch::tests::test_config_builders ... ok
test time_stretch::tests::test_wsola_double_speed ... ok
test time_stretch::tests::test_wsola_no_stretch ... ok
```

### rf-bridge Tests (2 passing)

```
test offline_ffi::tests::test_pipeline_lifecycle ... ok
test offline_ffi::tests::test_get_formats ... ok
```

---

## Dependencies

### Rust (rf-offline/Cargo.toml)

```toml
[dependencies]
rf-core = { workspace = true }
rf-dsp = { workspace = true }
rf-file = { workspace = true }
symphonia = { workspace = true }   # Audio decoding
hound = { workspace = true }       # WAV I/O
rustfft = { workspace = true }     # FFT for phase vocoder
realfft = { workspace = true }     # Real FFT
rayon = { workspace = true }       # Parallel processing
crossbeam-channel = { workspace = true }
parking_lot = { workspace = true }
serde = { workspace = true }
serde_json = { workspace = true }
thiserror = { workspace = true }
log = { workspace = true }
```

### Rust (rf-bridge additions)

```toml
rf-offline = { path = "../rf-offline" }
dashmap = "6.0"
```

---

## File Summary

| File | LOC | Description |
|------|-----|-------------|
| `crates/rf-offline/src/lib.rs` | ~50 | Module exports |
| `crates/rf-offline/src/error.rs` | ~50 | OfflineError enum |
| `crates/rf-offline/src/config.rs` | ~150 | OfflineConfig, OutputFormat |
| `crates/rf-offline/src/formats.rs` | ~100 | Audio format support |
| `crates/rf-offline/src/job.rs` | ~400 | JobBuilder, OfflineJob, JobResult |
| `crates/rf-offline/src/normalize.rs` | ~200 | NormalizationMode, LoudnessMeter |
| `crates/rf-offline/src/processors.rs` | ~400 | ProcessorChain, DSP processors |
| `crates/rf-offline/src/time_stretch.rs` | ~250 | PhaseVocoder, WSOLA |
| `crates/rf-offline/src/pipeline.rs` | ~550 | OfflinePipeline, BatchProcessor |
| `crates/rf-bridge/src/offline_ffi.rs` | ~620 | FFI bridge |
| `flutter_ui/.../native_ffi.dart` | +200 | FFI bindings (additions) |
| `flutter_ui/.../offline_processing_provider.dart` | ~450 | Flutter provider |
| **Total** | **~2900** | |

---

## Related Documentation

- [UNIFIED_PLAYBACK_SYSTEM.md](UNIFIED_PLAYBACK_SYSTEM.md) — Playback architecture
- [DAW_AUDIO_ROUTING.md](DAW_AUDIO_ROUTING.md) — Audio routing system
- [MIDDLEWARE_DECOMPOSITION.md](MIDDLEWARE_DECOMPOSITION.md) — Provider architecture
