/// Extension SDK Service (#34)
/// Open SDK for third-party development: extension lifecycle, API reference,
/// template scaffolding, and build/test pipeline.
library;

import 'package:flutter/foundation.dart';

// ─── Enums ───────────────────────────────────────────────────────────────────

/// Extension capability type
enum ExtensionCapability {
  audioProcessor,
  midiProcessor,
  analyzer,
  uiWidget,
  fileFormat,
  automation,
  networking,
}

extension ExtensionCapabilityX on ExtensionCapability {
  String get label => switch (this) {
    ExtensionCapability.audioProcessor => 'Audio Processor',
    ExtensionCapability.midiProcessor => 'MIDI Processor',
    ExtensionCapability.analyzer => 'Analyzer',
    ExtensionCapability.uiWidget => 'UI Widget',
    ExtensionCapability.fileFormat => 'File Format',
    ExtensionCapability.automation => 'Automation',
    ExtensionCapability.networking => 'Networking',
  };
}

/// Extension development language
enum ExtensionLanguage {
  rust,
  lua,
  wasm,
  jsfx,
}

extension ExtensionLanguageX on ExtensionLanguage {
  String get label => switch (this) {
    ExtensionLanguage.rust => 'Rust (Native)',
    ExtensionLanguage.lua => 'Lua (Scripted)',
    ExtensionLanguage.wasm => 'WASM (Sandboxed)',
    ExtensionLanguage.jsfx => 'JSFX (DSP)',
  };
  String get fileExtension => switch (this) {
    ExtensionLanguage.rust => '.rs',
    ExtensionLanguage.lua => '.lua',
    ExtensionLanguage.wasm => '.wasm',
    ExtensionLanguage.jsfx => '.jsfx',
  };
}

/// Extension lifecycle state
enum ExtensionState {
  unloaded,
  loading,
  active,
  error,
  disabled,
}

extension ExtensionStateX on ExtensionState {
  String get label => switch (this) {
    ExtensionState.unloaded => 'Unloaded',
    ExtensionState.loading => 'Loading...',
    ExtensionState.active => 'Active',
    ExtensionState.error => 'Error',
    ExtensionState.disabled => 'Disabled',
  };
}

/// SDK documentation section
enum SdkDocSection {
  gettingStarted,
  apiReference,
  audioApi,
  midiApi,
  uiApi,
  lifecycle,
  manifest,
  examples,
  testing,
  publishing,
}

extension SdkDocSectionX on SdkDocSection {
  String get label => switch (this) {
    SdkDocSection.gettingStarted => 'Getting Started',
    SdkDocSection.apiReference => 'API Reference',
    SdkDocSection.audioApi => 'Audio API',
    SdkDocSection.midiApi => 'MIDI API',
    SdkDocSection.uiApi => 'UI API',
    SdkDocSection.lifecycle => 'Lifecycle',
    SdkDocSection.manifest => 'Manifest Format',
    SdkDocSection.examples => 'Examples',
    SdkDocSection.testing => 'Testing',
    SdkDocSection.publishing => 'Publishing',
  };
  String get content => switch (this) {
    SdkDocSection.gettingStarted => _docGettingStarted,
    SdkDocSection.apiReference => _docApiReference,
    SdkDocSection.audioApi => _docAudioApi,
    SdkDocSection.midiApi => _docMidiApi,
    SdkDocSection.uiApi => _docUiApi,
    SdkDocSection.lifecycle => _docLifecycle,
    SdkDocSection.manifest => _docManifest,
    SdkDocSection.examples => _docExamples,
    SdkDocSection.testing => _docTesting,
    SdkDocSection.publishing => _docPublishing,
  };
}

// ─── Models ──────────────────────────────────────────────────────────────────

/// Extension manifest — metadata for a loaded extension
class ExtensionManifest {
  final String id;
  final String name;
  final String description;
  final String author;
  final String version;
  final ExtensionLanguage language;
  final List<ExtensionCapability> capabilities;
  final String entryPoint;
  final String? homepage;
  final String? license;
  final int minApiVersion;

  const ExtensionManifest({
    required this.id,
    required this.name,
    required this.description,
    required this.author,
    required this.version,
    required this.language,
    required this.capabilities,
    required this.entryPoint,
    this.homepage,
    this.license,
    this.minApiVersion = 1,
  });
}

/// A loaded extension instance
class ExtensionInstance {
  final String id;
  final ExtensionManifest manifest;
  final ExtensionState state;
  final String? errorMessage;
  final DateTime loadedAt;
  final double cpuPercent;
  final int memoryBytes;

  const ExtensionInstance({
    required this.id,
    required this.manifest,
    this.state = ExtensionState.unloaded,
    this.errorMessage,
    required this.loadedAt,
    this.cpuPercent = 0.0,
    this.memoryBytes = 0,
  });

  String get memoryLabel {
    if (memoryBytes < 1024) return '$memoryBytes B';
    if (memoryBytes < 1024 * 1024) return '${(memoryBytes / 1024).toStringAsFixed(1)} KB';
    return '${(memoryBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static const _unset = Object();

  ExtensionInstance copyWith({
    String? id,
    ExtensionManifest? manifest,
    ExtensionState? state,
    Object? errorMessage = _unset,
    DateTime? loadedAt,
    double? cpuPercent,
    int? memoryBytes,
  }) {
    return ExtensionInstance(
      id: id ?? this.id,
      manifest: manifest ?? this.manifest,
      state: state ?? this.state,
      errorMessage: identical(errorMessage, _unset) ? this.errorMessage : errorMessage as String?,
      loadedAt: loadedAt ?? this.loadedAt,
      cpuPercent: cpuPercent ?? this.cpuPercent,
      memoryBytes: memoryBytes ?? this.memoryBytes,
    );
  }
}

/// Extension project template for scaffolding
class ExtensionTemplate {
  final String id;
  final String name;
  final String description;
  final ExtensionLanguage language;
  final List<ExtensionCapability> capabilities;
  final String scaffoldCode;

  const ExtensionTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.language,
    required this.capabilities,
    required this.scaffoldCode,
  });
}

// ─── Service ─────────────────────────────────────────────────────────────────

class ExtensionSdkService extends ChangeNotifier {
  ExtensionSdkService._();
  static final instance = ExtensionSdkService._();

  final List<ExtensionInstance> _extensions = [];
  final List<ExtensionTemplate> _templates = [];
  String? _selectedExtensionId;
  SdkDocSection _activeDocSection = SdkDocSection.gettingStarted;

  // Getters
  List<ExtensionInstance> get extensions => List.unmodifiable(_extensions);
  List<ExtensionTemplate> get templates => List.unmodifiable(_templates);
  String? get selectedExtensionId => _selectedExtensionId;
  SdkDocSection get activeDocSection => _activeDocSection;

  ExtensionInstance? get selectedExtension {
    if (_selectedExtensionId == null) return null;
    final idx = _extensions.indexWhere((e) => e.id == _selectedExtensionId);
    return idx >= 0 ? _extensions[idx] : null;
  }

  int get activeCount => _extensions.where((e) => e.state == ExtensionState.active).length;
  int get errorCount => _extensions.where((e) => e.state == ExtensionState.error).length;

  // ─── Mutations ─────────────────────────────────────────────────────────────

  void selectExtension(String? id) {
    _selectedExtensionId = id;
    notifyListeners();
  }

  void setActiveDocSection(SdkDocSection section) {
    _activeDocSection = section;
    notifyListeners();
  }

  /// Load/activate an extension
  void activateExtension(String id) {
    final idx = _extensions.indexWhere((e) => e.id == id);
    if (idx < 0) return;
    if (_extensions[idx].state == ExtensionState.loading) return;

    _extensions[idx] = _extensions[idx].copyWith(state: ExtensionState.loading);
    notifyListeners();

    Future.delayed(const Duration(milliseconds: 600), () {
      final current = _extensions.indexWhere((e) => e.id == id);
      if (current < 0) return;
      _extensions[current] = _extensions[current].copyWith(
        state: ExtensionState.active,
        errorMessage: null,
        cpuPercent: 0.1 + (current * 0.05),
        memoryBytes: 32768 + (current * 16384),
      );
      notifyListeners();
    });
  }

  /// Deactivate an extension
  void deactivateExtension(String id) {
    final idx = _extensions.indexWhere((e) => e.id == id);
    if (idx < 0) return;
    _extensions[idx] = _extensions[idx].copyWith(
      state: ExtensionState.disabled,
      cpuPercent: 0.0,
      memoryBytes: 0,
    );
    notifyListeners();
  }

  /// Toggle extension active state
  void toggleExtension(String id) {
    final idx = _extensions.indexWhere((e) => e.id == id);
    if (idx < 0) return;
    final ext = _extensions[idx];
    if (ext.state == ExtensionState.active) {
      deactivateExtension(id);
    } else {
      activateExtension(id);
    }
  }

  /// Remove an extension
  void removeExtension(String id) {
    _extensions.removeWhere((e) => e.id == id);
    if (_selectedExtensionId == id) _selectedExtensionId = null;
    notifyListeners();
  }

  /// Reload an errored extension
  void reloadExtension(String id) {
    activateExtension(id);
  }

  // ─── Factory Data ──────────────────────────────────────────────────────────

  void loadFactoryData() {
    if (_extensions.isNotEmpty || _templates.isNotEmpty) return;

    final now = DateTime.now();

    _extensions.addAll([
      ExtensionInstance(
        id: 'ext-loudness-meter',
        manifest: const ExtensionManifest(
          id: 'ext-loudness-meter',
          name: 'Loudness Meter Pro',
          description: 'Real-time EBU R128 / ITU-R BS.1770 loudness measurement with gating and true peak detection.',
          author: 'FluxForge',
          version: '1.2.0',
          language: ExtensionLanguage.rust,
          capabilities: [ExtensionCapability.analyzer, ExtensionCapability.uiWidget],
          entryPoint: 'src/lib.rs',
          license: 'MIT',
        ),
        state: ExtensionState.active,
        loadedAt: now.subtract(const Duration(hours: 2)),
        cpuPercent: 0.3,
        memoryBytes: 65536,
      ),
      ExtensionInstance(
        id: 'ext-midi-chord',
        manifest: const ExtensionManifest(
          id: 'ext-midi-chord',
          name: 'MIDI Chord Generator',
          description: 'Generate chord progressions from single MIDI notes. Supports major/minor/7th/dim/aug voicings.',
          author: 'FluxForge',
          version: '0.9.0',
          language: ExtensionLanguage.lua,
          capabilities: [ExtensionCapability.midiProcessor],
          entryPoint: 'main.lua',
          license: 'MIT',
        ),
        state: ExtensionState.active,
        loadedAt: now.subtract(const Duration(hours: 1)),
        cpuPercent: 0.05,
        memoryBytes: 16384,
      ),
      ExtensionInstance(
        id: 'ext-wwise-bridge',
        manifest: const ExtensionManifest(
          id: 'ext-wwise-bridge',
          name: 'Wwise Integration Bridge',
          description: 'Direct connection to Wwise Authoring API. Import/export SoundBanks, events, and game syncs.',
          author: 'middleware_tools',
          version: '1.0.0',
          language: ExtensionLanguage.rust,
          capabilities: [ExtensionCapability.networking, ExtensionCapability.fileFormat],
          entryPoint: 'src/lib.rs',
          homepage: 'https://github.com/middleware-tools/wwise-bridge',
          license: 'MIT',
        ),
        state: ExtensionState.disabled,
        loadedAt: now.subtract(const Duration(days: 3)),
      ),
      ExtensionInstance(
        id: 'ext-spectrum-viz',
        manifest: const ExtensionManifest(
          id: 'ext-spectrum-viz',
          name: 'Spectrum Visualizer',
          description: 'GPU-accelerated 3D spectrogram with waterfall display, peak hold, and slope adjustment.',
          author: 'viz_studio',
          version: '0.5.0',
          language: ExtensionLanguage.wasm,
          capabilities: [ExtensionCapability.analyzer, ExtensionCapability.uiWidget],
          entryPoint: 'spectrum.wasm',
          license: 'GPL-3.0',
        ),
        state: ExtensionState.error,
        errorMessage: 'WASM runtime not available — requires WebAssembly feature flag',
        loadedAt: now.subtract(const Duration(days: 1)),
      ),
      ExtensionInstance(
        id: 'ext-auto-gain',
        manifest: const ExtensionManifest(
          id: 'ext-auto-gain',
          name: 'Auto Gain Staging',
          description: 'Automatic gain staging for insert chains. Targets -18dBFS RMS per processor slot.',
          author: 'FluxForge',
          version: '1.0.0',
          language: ExtensionLanguage.rust,
          capabilities: [ExtensionCapability.audioProcessor, ExtensionCapability.automation],
          entryPoint: 'src/lib.rs',
          license: 'MIT',
        ),
        state: ExtensionState.unloaded,
        loadedAt: now,
      ),
    ]);

    _templates.addAll([
      const ExtensionTemplate(
        id: 'tpl-audio-fx',
        name: 'Audio Effect',
        description: 'Basic audio processor with input/output buffers and parameter controls.',
        language: ExtensionLanguage.rust,
        capabilities: [ExtensionCapability.audioProcessor],
        scaffoldCode: _scaffoldAudioFx,
      ),
      const ExtensionTemplate(
        id: 'tpl-midi-proc',
        name: 'MIDI Processor',
        description: 'MIDI event filter/generator with note, CC, and program change handling.',
        language: ExtensionLanguage.lua,
        capabilities: [ExtensionCapability.midiProcessor],
        scaffoldCode: _scaffoldMidiProc,
      ),
      const ExtensionTemplate(
        id: 'tpl-analyzer',
        name: 'Audio Analyzer',
        description: 'Real-time audio analyzer with FFT, peak detection, and UI widget.',
        language: ExtensionLanguage.rust,
        capabilities: [ExtensionCapability.analyzer, ExtensionCapability.uiWidget],
        scaffoldCode: _scaffoldAnalyzer,
      ),
      const ExtensionTemplate(
        id: 'tpl-file-format',
        name: 'File Format Importer',
        description: 'Custom audio/project file format reader with metadata extraction.',
        language: ExtensionLanguage.rust,
        capabilities: [ExtensionCapability.fileFormat],
        scaffoldCode: _scaffoldFileFormat,
      ),
    ]);

    notifyListeners();
  }

  /// Callback for external actions
  void Function(String extensionId, String action)? onExtensionAction;
}

// ─── Scaffold Code Templates ─────────────────────────────────────────────────

const _scaffoldAudioFx = '''use rf_plugin::prelude::*;

#[derive(Default)]
pub struct MyEffect {
    gain: f32,
}

impl Extension for MyEffect {
    fn manifest() -> Manifest {
        Manifest {
            id: "com.example.my-effect",
            name: "My Effect",
            version: "0.1.0",
            capabilities: &[Capability::AudioProcessor],
        }
    }

    fn init(&mut self, ctx: &InitContext) {
        self.gain = 1.0;
        ctx.register_param("gain", 0.0, 2.0, 1.0);
    }

    fn process(&mut self, buffer: &mut AudioBuffer, ctx: &ProcessContext) {
        self.gain = ctx.param("gain");
        for sample in buffer.iter_mut() {
            *sample *= self.gain;
        }
    }
}

rf_plugin::export!(MyEffect);
''';

const _scaffoldMidiProc = '''-- MIDI Processor Extension
-- FluxForge Extension SDK (Lua)

function init(ctx)
    ctx:register_param("transpose", -24, 24, 0)
    ctx:register_param("velocity_scale", 0.0, 2.0, 1.0)
end

function process_midi(event, ctx)
    if event.type == "note_on" or event.type == "note_off" then
        local transpose = math.floor(ctx:param("transpose"))
        event.note = math.max(0, math.min(127, event.note + transpose))

        if event.type == "note_on" then
            local vel_scale = ctx:param("velocity_scale")
            event.velocity = math.floor(math.min(127, event.velocity * vel_scale))
        end
    end
    return event
end
''';

const _scaffoldAnalyzer = '''use rf_plugin::prelude::*;

#[derive(Default)]
pub struct MyAnalyzer {
    peak_l: f32,
    peak_r: f32,
    rms_sum: f64,
    sample_count: usize,
}

impl Extension for MyAnalyzer {
    fn manifest() -> Manifest {
        Manifest {
            id: "com.example.my-analyzer",
            name: "My Analyzer",
            version: "0.1.0",
            capabilities: &[Capability::Analyzer, Capability::UiWidget],
        }
    }

    fn process(&mut self, buffer: &mut AudioBuffer, _ctx: &ProcessContext) {
        for frame in buffer.frames() {
            let l = frame[0].abs();
            let r = frame[1].abs();
            self.peak_l = self.peak_l.max(l);
            self.peak_r = self.peak_r.max(r);
            self.rms_sum += (l * l + r * r) as f64;
            self.sample_count += 1;
        }
    }

    fn ui_data(&self) -> UiData {
        let rms = if self.sample_count > 0 {
            (self.rms_sum / self.sample_count as f64).sqrt() as f32
        } else { 0.0 };
        UiData::new()
            .float("peak_l", self.peak_l)
            .float("peak_r", self.peak_r)
            .float("rms", rms)
    }
}

rf_plugin::export!(MyAnalyzer);
''';

const _scaffoldFileFormat = '''use rf_plugin::prelude::*;

pub struct MyFormatReader;

impl Extension for MyFormatReader {
    fn manifest() -> Manifest {
        Manifest {
            id: "com.example.my-format",
            name: "My Format Reader",
            version: "0.1.0",
            capabilities: &[Capability::FileFormat],
        }
    }

    fn supported_extensions() -> &'static [&'static str] {
        &["myf", "myformat"]
    }

    fn read_file(path: &std::path::Path) -> Result<AudioData, ExtError> {
        let bytes = std::fs::read(path)?;
        // Parse header, extract audio data
        let sample_rate = 48000;
        let channels = 2;
        let samples: Vec<f32> = vec![0.0; 1024]; // TODO: parse actual data

        Ok(AudioData {
            sample_rate,
            channels,
            samples,
            metadata: Metadata::default(),
        })
    }
}

rf_plugin::export!(MyFormatReader);
''';

// ─── SDK Documentation ──────────────────────────────────────────────────────

const _docGettingStarted = '''# Getting Started with FluxForge Extensions

## Prerequisites
- Rust 1.75+ (for native extensions)
- Lua 5.4 (for scripted extensions)
- FluxForge Studio 2.0+

## Quick Start
1. Open Package Manager → Extension SDK tab
2. Choose a template (Audio Effect, MIDI Processor, etc.)
3. Click "Scaffold Project" to generate starter code
4. Edit the source code in the built-in editor
5. Click "Build & Test" to compile and validate
6. Click "Install" to load into FluxForge

## Extension Types
- **Audio Processor**: Real-time sample-level processing
- **MIDI Processor**: MIDI event filtering and generation
- **Analyzer**: Audio measurement and visualization
- **UI Widget**: Custom panel or meter
- **File Format**: Import/export custom formats
- **Automation**: Parameter automation sources
- **Networking**: External service integration''';

const _docApiReference = '''# API Reference

## Core Types

### Manifest
Required metadata for every extension:
- `id`: Unique reverse-domain identifier
- `name`: Display name
- `version`: Semantic version string
- `capabilities`: Array of Capability flags

### AudioBuffer
Pre-allocated stereo buffer:
- `frames()`: Iterator over [L, R] frame pairs
- `iter_mut()`: Mutable iterator over all samples
- `len()`: Number of frames
- `channels()`: Number of channels (1 or 2)

### ProcessContext
Runtime context per process call:
- `sample_rate()`: Current sample rate (44100/48000/96000)
- `bpm()`: Current project BPM
- `param(name)`: Read parameter value
- `playhead()`: Current playhead position in samples

### InitContext
Setup context during initialization:
- `register_param(name, min, max, default)`: Declare a parameter
- `log(message)`: Debug output to diagnostics panel''';

const _docAudioApi = '''# Audio Processing API

## Buffer Layout
Audio is delivered as interleaved f32 samples:
```rust
fn process(&mut self, buffer: &mut AudioBuffer, ctx: &ProcessContext) {
    let sr = ctx.sample_rate();
    for frame in buffer.frames_mut() {
        let left = &mut frame[0];
        let right = &mut frame[1];
        // Process samples here
    }
}
```

## Rules
1. NO heap allocations in process()
2. NO blocking calls (mutex, I/O, sleep)
3. Pre-allocate all buffers in init()
4. Use SIMD intrinsics for batch operations
5. Keep CPU < 1% per extension''';

const _docMidiApi = '''# MIDI Processing API

## Event Types
- `note_on(note, velocity, channel)`
- `note_off(note, velocity, channel)`
- `cc(controller, value, channel)`
- `program_change(program, channel)`
- `pitch_bend(value, channel)`
- `aftertouch(pressure, channel)`

## Lua Example
```lua
function process_midi(event, ctx)
    if event.type == "note_on" then
        -- Generate chord: root + major third + fifth
        emit(event)
        emit(note_on(event.note + 4, event.velocity, event.channel))
        emit(note_on(event.note + 7, event.velocity, event.channel))
        return nil -- consume original
    end
    return event -- pass through
end
```''';

const _docUiApi = '''# UI Widget API

## UiData
Extensions expose data to the Flutter UI via UiData:
```rust
fn ui_data(&self) -> UiData {
    UiData::new()
        .float("level", self.level)
        .string("status", "OK")
        .bool("clipping", self.clipping)
}
```

## Custom Panels
Extensions can declare custom UI panels that render in the Lower Zone:
- Width: 200-800px
- Height: determined by Lower Zone
- Update rate: 30fps max (Flutter rebuild throttle)''';

const _docLifecycle = '''# Extension Lifecycle

## States
1. **Unloaded** → Extension discovered but not initialized
2. **Loading** → init() called, allocating resources
3. **Active** → Processing audio/MIDI, UI updates active
4. **Error** → Runtime error caught, extension paused
5. **Disabled** → User-toggled off, resources released

## Callbacks
- `init(ctx)` — One-time setup, register params
- `activate()` — Called when entering Active state
- `deactivate()` — Called when leaving Active state
- `process(buffer, ctx)` — Called per audio block
- `process_midi(event, ctx)` — Called per MIDI event
- `destroy()` — Final cleanup, free all resources

## Error Handling
Runtime errors are caught and the extension enters Error state.
The user can click "Reload" to attempt recovery via init() → activate().''';

const _docManifest = '''# Extension Manifest Format

## manifest.toml
```toml
[extension]
id = "com.author.my-extension"
name = "My Extension"
version = "0.1.0"
author = "Your Name"
description = "What it does"
license = "MIT"
min_api_version = 1

[capabilities]
audio_processor = true
midi_processor = false
analyzer = false
ui_widget = false

[build]
language = "rust"  # rust | lua | wasm
entry_point = "src/lib.rs"

[params]
gain = { min = 0.0, max = 2.0, default = 1.0, label = "Gain" }
mix = { min = 0.0, max = 1.0, default = 1.0, label = "Mix" }
```''';

const _docExamples = '''# Extension Examples

## 1. Simple Gain (Rust)
```rust
impl Extension for GainPlugin {
    fn process(&mut self, buf: &mut AudioBuffer, ctx: &ProcessContext) {
        let gain = ctx.param("gain");
        for s in buf.iter_mut() { *s *= gain; }
    }
}
```

## 2. Velocity Filter (Lua)
```lua
function process_midi(event, ctx)
    local min_vel = ctx:param("min_velocity")
    if event.type == "note_on" and event.velocity < min_vel then
        return nil -- filter out soft notes
    end
    return event
end
```

## 3. Peak Meter (Rust)
```rust
fn process(&mut self, buf: &mut AudioBuffer, _ctx: &ProcessContext) {
    self.peak = buf.iter().fold(0.0f32, |acc, &s| acc.max(s.abs()));
}

fn ui_data(&self) -> UiData {
    UiData::new().float("peak", self.peak)
}
```''';

const _docTesting = '''# Testing Extensions

## Built-in Test Runner
FluxForge includes a test runner for extensions:
1. Generate test audio (sine, noise, silence)
2. Feed through extension
3. Validate output (no NaN, no infinity, expected range)
4. Measure CPU usage and memory
5. Check for audio thread violations

## Test Commands
- `Build` — Compile extension (catches syntax errors)
- `Validate` — Run safety checks (no unsafe APIs)
- `Benchmark` — Measure process() CPU cost
- `Stress Test` — 1000 blocks at 96kHz stereo

## Diagnostics
All test results appear in the Diagnostics panel.''';

const _docPublishing = '''# Publishing Extensions

## Package Format
Extensions are distributed as `.ffext` packages:
```
my-extension.ffext
├── manifest.toml
├── lib/
│   └── my_extension.dylib (or .wasm, .lua)
├── presets/
│   └── default.json
└── README.md
```

## Publishing Steps
1. Build release: `cargo build --release --target-dir dist/`
2. Create manifest.toml with correct metadata
3. Package: `fluxforge-sdk pack ./my-extension`
4. Test: `fluxforge-sdk test ./my-extension.ffext`
5. Publish: `fluxforge-sdk publish ./my-extension.ffext`

## Repository Submission
- Official repo: Submit PR to fluxforge/extensions
- Community repo: Upload to community.fluxforge.dev
- Custom repo: Host on any HTTP server with index.json''';
