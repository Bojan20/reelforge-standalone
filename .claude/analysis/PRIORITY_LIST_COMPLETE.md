# REELFORGE DAW - KOMPLETAN SPISAK PRIORITETA
**Datum:** 2026-01-09
**Ukupno problema:** 17 prioriteta
**Estimirano vreme:** 26-32 sedmice (6-8 meseci)

---

## 📋 BRZI PREGLED - SVE PRIORITETE

| ID | Naziv | Impact | Effort | Prioritet | Sedmica |
|----|-------|--------|--------|-----------|---------|
| **P1** | Plugin Hosting | 🔴🔴🔴🔴🔴 10/10 | 4-6 sed | 🔥 IMMEDIATE | W1-W6 |
| **P2** | Audio Recording | 🔴🔴🔴🔴 8/10 | 2-3 sed | 🔥 URGENT | W7-W9 |
| **P3** | Audio Export | 🔴🔴🔴🔴 8/10 | 1-2 sed | 🔥 URGENT | W10 |
| **P4** | RwLock Audio Thread | 🔴🔴🔴 6/10 | 30min | 🔥 QUICK WIN | W1-Day1 |
| **P5** | EQ Vec Allocation | 🔴🔴 5/10 | 45min | 🔥 QUICK WIN | W1-Day1 |
| **P6** | Meter Rebuild Storm | 🔴🔴 5/10 | 45min | 🔥 QUICK WIN | W1-Day1 |
| **P7** | Timeline Playhead Jitter | 🟠🟠 4/10 | 1h | ⚠️ HIGH | W11-Day1 |
| **P8** | Biquad No SIMD | 🟠🟠🟠 6/10 | 2-3h | ⚠️ HIGH | W11-Day2 |
| **P9** | Dynamic EQ | 🟠🟠🟠 6/10 | 1 sed | ⚠️ HIGH | W12 |
| **P10** | True Peak Limiting | 🟠🟠🟠 6/10 | 3-4 dana | ⚠️ HIGH | W13 |
| **P11** | LUFS Metering UI | 🟡🟡 4/10 | 2 dana | 🟡 MEDIUM | W14 |
| **P12** | Match EQ | 🟡🟡 4/10 | 1 sed | 🟡 MEDIUM | W15 |
| **P13** | Spectral Dynamics | 🟡🟡🟡 5/10 | 2 sed | 🟡 MEDIUM | W16-W17 |
| **P14** | Video Track Playback | 🟡 3/10 | 3-4 sed | 🔵 LOW | W18-W21 |
| **P15** | Chord Track | 🔵 2/10 | 1 sed | 🔵 LOW | W22 |
| **P16** | Tempo Automation | 🔵 2/10 | 3-4 dana | 🔵 LOW | W23 |
| **P17** | Variaudio UI | 🔵🔵 3/10 | 2 sed | 🔵 LOW | W24-W25 |

**UKUPNO:** 26-32 sedmice za kompletnu implementaciju

---

## 🔥 FAZA 0: QUICK WINS (2 SATA - DAN 1)

### P4: Fix RwLock u Audio Thread-u
**Impact:** 🔴🔴🔴 6/10 | **Effort:** ⏱️ 30 minuta | **Priority:** 🔥 IMMEDIATE

**Problem:**
```rust
// TRENUTNO (LOŠ):
pub struct AudioEngine {
    settings: RwLock<EngineSettings>,  // ❌ Blokira audio thread
}

fn audio_callback() {
    let settings = self.settings.read().unwrap();  // ❌ LOCK
    let sample_rate = settings.sample_rate;
}
```

**Rešenje:**
```rust
// NOVO (LOCK-FREE):
pub struct AudioEngine {
    sample_rate: AtomicU32,      // ✅ Zero-lock
    buffer_size: AtomicU32,
}

fn audio_callback() {
    let sample_rate = self.sample_rate.load(Ordering::Relaxed);  // ✅ INSTANT
}
```

**Lokacija:** `crates/rf-audio/src/engine.rs:166`

**ROI:**
- ✅ **Latency:** -2-3ms
- ✅ **Audio glitches:** Eliminisani
- ✅ **Real-time safety:** 100%

**Implementacija:**
1. Zameni `RwLock<EngineSettings>` sa `AtomicU32` fieldovima
2. Update sve `read()` callove sa `load(Ordering::Relaxed)`
3. Update sve `write()` callove sa `store(Ordering::Release)`
4. Test: Run 10 min playback test, verify no glitches

---

### P5: Fix EQ Vec Allocation
**Impact:** 🔴🔴 5/10 | **Effort:** ⏱️ 45 minuta | **Priority:** 🔥 QUICK WIN

**Problem:**
```rust
// TRENUTNO (ALOKACIJA U AUDIO THREAD):
pub fn process(&mut self, samples: &mut [f64]) {
    let mut active_bands = Vec::new();  // ❌ Heap allocation

    for band in &self.bands {
        if band.enabled {
            active_bands.push(band);  // ❌ Može reallocirati
        }
    }
}
```

**Rešenje:**
```rust
// NOVO (ZERO ALLOCATION):
pub struct ParametricEq {
    bands: [EqBand; MAX_BANDS],
    active_indices: [usize; MAX_BANDS],  // ✅ Pre-allocated
    active_count: usize,
}

pub fn process(&mut self, samples: &mut [f64]) {
    self.active_count = 0;
    for (i, band) in self.bands.iter().enumerate() {
        if band.enabled {
            self.active_indices[self.active_count] = i;
            self.active_count += 1;
        }
    }

    for i in 0..self.active_count {
        let idx = self.active_indices[i];
        self.bands[idx].process(samples);
    }
}
```

**Lokacija:** `crates/rf-dsp/src/eq.rs:190`

**ROI:**
- ✅ **CPU:** -3-5%
- ✅ **Allocation stalls:** Eliminisani
- ✅ **Predictable latency:** 100%

**Implementacija:**
1. Add `active_indices: [usize; 64]` field u `ParametricEq`
2. Add `active_count: usize` field
3. Replace `Vec::new()` sa index tracking
4. Benchmark: Measure CPU before/after

---

### P6: Fix Meter Provider Rebuild Storm
**Impact:** 🔴🔴 5/10 | **Effort:** ⏱️ 45 minuta | **Priority:** 🔥 QUICK WIN

**Problem:**
```dart
// TRENUTNO (REBUILD STORM):
class MeterProvider extends ChangeNotifier {
  void _updateMeters() {
    // Runs @60fps
    notifyListeners();  // ❌ Rebuilds SVE meter widgets
  }
}
```

**Rešenje:**
```dart
// NOVO (THROTTLED + ISOLATED):
class MeterProvider extends ChangeNotifier {
  void startMetering() {
    _meterTimer = Timer.periodic(
      Duration(milliseconds: 33),  // ✅ 30fps max (bilo 60fps)
      (_) => _updateMeters(),
    );
  }

  void _updateMeters() {
    // Update meter data
    _updateCounter++;
    if (_updateCounter % 2 == 0) {  // ✅ Throttle notifications
      notifyListeners();
    }
  }
}

// U meter widget-ima:
class ProMeter extends StatefulWidget {
  Widget build(BuildContext context) {
    return RepaintBoundary(  // ✅ Isolate repaints
      child: CustomPaint(painter: MeterPainter(...)),
    );
  }
}
```

**Lokacija:** `flutter_ui/lib/providers/meter_provider.dart:256`

**ROI:**
- ✅ **FPS:** +30% (42fps → 55fps)
- ✅ **UI responsiveness:** Drastično bolje
- ✅ **Battery:** Manja potrošnja

**Implementacija:**
1. Change timer interval: 16ms → 33ms
2. Add throttle counter: notify every 2nd update
3. Wrap meter widgets u `RepaintBoundary`
4. Test: Profile UI frame times before/after

---

**UKUPNO FAZA 0:** 2 sata = **+10-15% general performance**

---

## 🔥 FAZA 1: CRITICAL BLOCKERS (8-10 SEDMICA)

### P1: Plugin Hosting (VST3/AU/CLAP)
**Impact:** 🔴🔴🔴🔴🔴 10/10 | **Effort:** 🕐🕐🕐🕐🕐🕐🕐 4-6 sedmica | **Priority:** 🔥 IMMEDIATE

**Problem:**
- Nema VST3/AU/CLAP učitavanja
- Ne može se koristiti third-party plugin
- **Blokirano 95% profesionalnih workflow-a**

**Trenutno stanje:**
- `crates/rf-plugin/` - stub (0 funkcionalnosti)
- `flutter_ui/lib/widgets/plugin/` - UI postoji, bez backend-a

**Konkurencija:**
- **Cubase 14:** Full VST3/AU, crash protection, multi-core
- **REAPER:** VST/AU/JS/CLAP, sandboxing, per-plugin routing
- **Pro Tools:** AAX, HDX DSP offload

**Implementacija (6 sedmica):**

#### Nedelja 1-2: VST3 Scanner + Loading
```rust
// crates/rf-plugin/src/vst3_scanner.rs
pub struct Vst3Scanner {
    plugin_paths: Vec<PathBuf>,
    cache: HashMap<String, PluginInfo>,
}

impl Vst3Scanner {
    pub fn scan(&mut self) -> Vec<PluginInfo> {
        let mut plugins = Vec::new();

        // Standard VST3 paths
        #[cfg(target_os = "macos")]
        let paths = vec![
            "/Library/Audio/Plug-Ins/VST3",
            "~/Library/Audio/Plug-Ins/VST3",
        ];

        for path in paths {
            for entry in fs::read_dir(path)? {
                let path = entry?.path();
                if path.extension() == Some("vst3") {
                    if let Ok(info) = self.load_plugin_info(&path) {
                        plugins.push(info);
                    }
                }
            }
        }

        plugins
    }

    fn load_plugin_info(&self, path: &Path) -> Result<PluginInfo> {
        let library = Library::new(path)?;
        let factory = get_plugin_factory(&library)?;

        Ok(PluginInfo {
            name: factory.get_name()?,
            vendor: factory.get_vendor()?,
            version: factory.get_version()?,
            path: path.to_owned(),
            format: PluginFormat::Vst3,
        })
    }
}
```

#### Nedelja 3-4: VST3 Processing
```rust
// crates/rf-plugin/src/vst3_plugin.rs
pub struct Vst3Plugin {
    component: Box<dyn IComponent>,
    processor: Box<dyn IAudioProcessor>,
    process_data: ProcessData,
    latency_samples: usize,
}

impl Vst3Plugin {
    pub fn load(path: &Path) -> Result<Self> {
        let library = Library::new(path)?;
        let factory = get_plugin_factory(&library)?;

        let component = factory.create_instance()?;
        component.initialize()?;

        let processor = component.query_interface::<IAudioProcessor>()?;

        Ok(Self {
            component,
            processor,
            process_data: ProcessData::default(),
            latency_samples: processor.get_latency_samples(),
        })
    }

    pub fn process(&mut self, input: &[f32], output: &mut [f32], block_size: usize) {
        // Setup process data
        self.process_data.inputs[0] = input;
        self.process_data.outputs[0] = output;
        self.process_data.num_samples = block_size;

        // Process
        self.processor.process(&mut self.process_data)?;
    }

    pub fn get_parameter_count(&self) -> usize {
        self.component.get_parameter_count()
    }

    pub fn set_parameter(&mut self, id: u32, value: f64) {
        self.component.set_parameter_normalized(id, value);
    }
}
```

#### Nedelja 5: UI Integration
```dart
// flutter_ui/lib/widgets/plugin/plugin_selector.dart
class PluginSelector extends StatefulWidget {
  final Function(String pluginPath) onPluginSelected;

  Widget build(BuildContext context) {
    return FutureBuilder<List<PluginInfo>>(
      future: EngineApi.instance.scanPlugins(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return CircularProgressIndicator();

        final plugins = snapshot.data!;

        return ListView.builder(
          itemCount: plugins.length,
          itemBuilder: (context, index) {
            final plugin = plugins[index];
            return ListTile(
              title: Text(plugin.name),
              subtitle: Text('${plugin.vendor} - ${plugin.format}'),
              onTap: () {
                widget.onPluginSelected(plugin.path);
                Navigator.pop(context);
              },
            );
          },
        );
      },
    );
  }
}
```

#### Nedelja 6: Parameter Automation
```rust
// crates/rf-plugin/src/automation.rs
pub struct PluginAutomation {
    parameter_values: HashMap<u32, AutomationCurve>,
    sample_rate: f64,
}

impl PluginAutomation {
    pub fn get_value(&self, param_id: u32, time: f64) -> f64 {
        if let Some(curve) = self.parameter_values.get(&param_id) {
            curve.evaluate(time)
        } else {
            0.0
        }
    }

    pub fn add_point(&mut self, param_id: u32, time: f64, value: f64) {
        self.parameter_values
            .entry(param_id)
            .or_insert_with(AutomationCurve::new)
            .add_point(time, value);
    }
}
```

**Testiranje:**
- Load 10 popular plugins (Serum, FabFilter, Waves)
- Verify stable processing (no crashes)
- Verify automation works
- Verify parameter display updates

**ROI:** 🚀 **MASSIVE** - Odblokirava ceo ekosistem

---

### P2: Audio Recording
**Impact:** 🔴🔴🔴🔴 8/10 | **Effort:** 🕐🕐🕐 2-3 sedmice | **Priority:** 🔥 URGENT

**Problem:**
- Ne može se snimiti audio input
- Nema arm/monitor workflow-a
- **Blokirano snimanje voiceover-a, live instrumenata**

**Trenutno stanje:**
- `flutter_ui/lib/providers/recording_provider.dart` - stub (153 linije)
- `crates/rf-audio/src/recording.rs` - **NE POSTOJI**

**Konkurencija:**
- **Pro Tools:** Sample-accurate punch in/out, auto punch, loop recording
- **Logic Pro X:** Auto take folders, comp lanes, pre/post roll
- **Cubase:** ASIO Direct Monitoring, constrain delay compensation

**Implementacija (3 sedmice):**

#### Nedelja 1: Input Device + Arm Workflow
```rust
// crates/rf-audio/src/recording.rs (NOVO)
pub struct RecordingEngine {
    input_device: Option<cpal::Device>,
    input_stream: Option<cpal::Stream>,
    ring_buffer: Arc<RingBuffer<f32>>,
    recording: Arc<AtomicBool>,
    armed_tracks: HashSet<String>,
    latency_compensation: usize,
}

impl RecordingEngine {
    pub fn new() -> Self {
        Self {
            input_device: None,
            input_stream: None,
            ring_buffer: Arc::new(RingBuffer::new(48000 * 10)), // 10s buffer
            recording: Arc::new(AtomicBool::new(false)),
            armed_tracks: HashSet::new(),
            latency_compensation: 0,
        }
    }

    pub fn set_input_device(&mut self, device_name: &str) -> Result<()> {
        let host = cpal::default_host();
        let device = host.input_devices()?
            .find(|d| d.name().unwrap() == device_name)
            .ok_or("Device not found")?;

        self.input_device = Some(device);
        Ok(())
    }

    pub fn arm_track(&mut self, track_id: &str, enabled: bool) {
        if enabled {
            self.armed_tracks.insert(track_id.to_owned());
        } else {
            self.armed_tracks.remove(track_id);
        }
    }

    pub fn start_input_stream(&mut self) -> Result<()> {
        let device = self.input_device.as_ref()
            .ok_or("No input device selected")?;

        let config = device.default_input_config()?;
        let ring_buffer = Arc::clone(&self.ring_buffer);
        let recording = Arc::clone(&self.recording);

        let stream = device.build_input_stream(
            &config.into(),
            move |data: &[f32], _: &_| {
                if recording.load(Ordering::Acquire) {
                    for &sample in data {
                        ring_buffer.push(sample).ok();
                    }
                }
            },
            |err| eprintln!("Input stream error: {}", err),
        )?;

        stream.play()?;
        self.input_stream = Some(stream);

        Ok(())
    }
}
```

#### Nedelja 2: Recording Loop + WAV Writer
```rust
// crates/rf-audio/src/recording.rs (continued)
impl RecordingEngine {
    pub fn start_recording(&mut self, track_id: &str, file_path: &Path) -> Result<JoinHandle<()>> {
        if !self.armed_tracks.contains(track_id) {
            return Err("Track not armed".into());
        }

        self.recording.store(true, Ordering::Release);
        let ring_buffer = Arc::clone(&self.ring_buffer);
        let recording = Arc::clone(&self.recording);
        let file_path = file_path.to_owned();

        let handle = thread::spawn(move || {
            let mut wav_writer = WavWriter::new(&file_path, 48000, 2).unwrap();

            while recording.load(Ordering::Acquire) {
                // Pop from ring buffer
                if let Some(chunk) = ring_buffer.pop_chunk(1024) {
                    // Write to WAV
                    for &sample in &chunk {
                        wav_writer.write_sample(sample).unwrap();
                    }
                }

                // Sleep briefly to avoid tight loop
                thread::sleep(Duration::from_millis(1));
            }

            wav_writer.finalize().unwrap();
        });

        Ok(handle)
    }

    pub fn stop_recording(&mut self) {
        self.recording.store(false, Ordering::Release);
    }
}
```

#### Nedelja 3: Take Management + UI
```dart
// flutter_ui/lib/providers/recording_provider.dart
class RecordingProvider extends ChangeNotifier {
  List<RecordingTake> takes = [];
  String? currentTakeId;
  bool isRecording = false;

  Future<void> startRecording(String trackId) async {
    final takeId = Uuid().v4();
    final filePath = '/path/to/takes/$takeId.wav';

    currentTakeId = takeId;
    isRecording = true;
    notifyListeners();

    await EngineApi.instance.startRecording(trackId, filePath);
  }

  Future<void> stopRecording() async {
    await EngineApi.instance.stopRecording();

    // Add take to list
    takes.add(RecordingTake(
      id: currentTakeId!,
      trackId: currentTrackId,
      filePath: currentFilePath,
      timestamp: DateTime.now(),
    ));

    isRecording = false;
    currentTakeId = null;
    notifyListeners();
  }
}
```

**Testiranje:**
- Record 10 takes, verify audio integrity
- Test punch in/out
- Test loop recording
- Verify latency compensation

**ROI:** ✅ Osnovni DAW workflow kompletiran

---

### P3: Audio Export (WAV/FLAC/MP3)
**Impact:** 🔴🔴🔴🔴 8/10 | **Effort:** 🕐🕐 1-2 sedmice | **Priority:** 🔥 URGENT

**Problem:**
- Ne može se exportovati finalni mix
- Nema offline bounce-a
- **Blokirano delivery krajnjem korisniku**

**Trenutno stanje:**
- `flutter_ui/lib/providers/audio_export_provider.dart` - stub (379 linije)
- `crates/rf-engine/src/export.rs` - **NE POSTOJI**

**Konkurencija:**
- **Logic Pro X:** Bounce in place, stems export, 32-bit float
- **Cubase:** Export audio mixdown, channel batch export
- **Pro Tools:** Bounce to disk, freeze tracks

**Implementacija (2 sedmice):**

#### Nedelja 1: WAV Export (Master Bus)
```rust
// crates/rf-engine/src/export.rs (NOVO)
pub struct AudioExporter {
    engine: Arc<PlaybackEngine>,
    settings: ExportSettings,
}

pub struct ExportSettings {
    pub format: AudioFormat,        // WAV, FLAC, MP3
    pub sample_rate: u32,
    pub bit_depth: BitDepth,        // 16, 24, 32-bit
    pub dither: bool,
    pub normalize: Option<f64>,     // Target dB
    pub start_time: f64,
    pub end_time: f64,
    pub realtime: bool,             // false = offline (faster)
}

pub enum AudioFormat {
    Wav,
    Flac,
    Mp3(u32), // bitrate
}

pub enum BitDepth {
    Int16,
    Int24,
    Float32,
}

impl AudioExporter {
    pub fn export(&self, output_path: &Path) -> Result<()> {
        let mut wav_writer = WavWriter::create(
            output_path,
            self.settings.sample_rate,
            2, // stereo
            self.settings.bit_depth,
        )?;

        let block_size = 1024;
        let mut position = self.settings.start_time;
        let total_samples = ((self.settings.end_time - self.settings.start_time)
            * self.settings.sample_rate as f64) as usize;

        let mut progress = 0usize;

        while position < self.settings.end_time {
            // Render one block (offline, faster than realtime)
            let (left, right) = self.engine.render_block(position, block_size)?;

            // Normalize if requested
            let (left, right) = if let Some(target_db) = self.settings.normalize {
                normalize_block(&left, &right, target_db)
            } else {
                (left, right)
            };

            // Dither if requested
            let (left, right) = if self.settings.dither {
                dither_block(&left, &right, self.settings.bit_depth)
            } else {
                (left, right)
            };

            // Write to file
            for (&l, &r) in left.iter().zip(right.iter()) {
                wav_writer.write_sample_stereo(l, r)?;
            }

            position += block_size as f64 / self.settings.sample_rate as f64;
            progress += block_size;

            // Report progress
            let percent = (progress as f64 / total_samples as f64 * 100.0) as u8;
            self.report_progress(percent);
        }

        wav_writer.finalize()?;
        Ok(())
    }

    fn report_progress(&self, percent: u8) {
        // FFI callback to Flutter
        unsafe {
            export_progress_callback(percent);
        }
    }
}

fn normalize_block(left: &[f64], right: &[f64], target_db: f64) -> (Vec<f64>, Vec<f64>) {
    // Find peak
    let peak = left.iter().chain(right.iter())
        .map(|&s| s.abs())
        .fold(0.0, f64::max);

    // Calculate gain
    let target_linear = db_to_linear(target_db);
    let gain = target_linear / peak;

    // Apply gain
    let left_norm = left.iter().map(|&s| s * gain).collect();
    let right_norm = right.iter().map(|&s| s * gain).collect();

    (left_norm, right_norm)
}

fn dither_block(left: &[f64], right: &[f64], bit_depth: BitDepth) -> (Vec<f64>, Vec<f64>) {
    // TPDF dithering
    let noise_amp = match bit_depth {
        BitDepth::Int16 => 1.0 / 32768.0,
        BitDepth::Int24 => 1.0 / 8388608.0,
        BitDepth::Float32 => 0.0, // No dither for float
    };

    let mut rng = rand::thread_rng();

    let left_dithered = left.iter().map(|&s| {
        let r1 = rng.gen_range(-1.0..1.0);
        let r2 = rng.gen_range(-1.0..1.0);
        let tpdf = (r1 + r2) / 2.0 * noise_amp;
        s + tpdf
    }).collect();

    let right_dithered = right.iter().map(|&s| {
        let r1 = rng.gen_range(-1.0..1.0);
        let r2 = rng.gen_range(-1.0..1.0);
        let tpdf = (r1 + r2) / 2.0 * noise_amp;
        s + tpdf
    }).collect();

    (left_dithered, right_dithered)
}
```

#### Nedelja 2: FLAC/MP3 Encoding + Stems Export
```rust
// crates/rf-engine/src/export.rs (continued)
impl AudioExporter {
    pub fn export_stems(&self, output_dir: &Path, track_ids: &[String]) -> Result<()> {
        for track_id in track_ids {
            let output_path = output_dir.join(format!("{}.wav", track_id));

            // Solo this track
            self.engine.solo_track(track_id, true)?;

            // Export
            self.export(&output_path)?;

            // Unsolo
            self.engine.solo_track(track_id, false)?;
        }

        Ok(())
    }

    pub fn export_flac(&self, output_path: &Path) -> Result<()> {
        use flac_bound::FlacEncoder;

        let mut encoder = FlacEncoder::new()
            .sample_rate(self.settings.sample_rate)
            .channels(2)
            .bits_per_sample(match self.settings.bit_depth {
                BitDepth::Int16 => 16,
                BitDepth::Int24 => 24,
                BitDepth::Float32 => 24, // Convert to 24-bit
            })
            .compression_level(8) // Max compression
            .init_file(output_path)?;

        // Render and encode (same loop as WAV)
        // ...

        encoder.finish()?;
        Ok(())
    }

    pub fn export_mp3(&self, output_path: &Path, bitrate: u32) -> Result<()> {
        use lame::Lame;

        let mut encoder = Lame::new()?;
        encoder.set_num_channels(2)?;
        encoder.set_sample_rate(self.settings.sample_rate)?;
        encoder.set_bitrate(bitrate)?;
        encoder.set_quality(2)?; // High quality
        encoder.init_params()?;

        let mut mp3_buffer = vec![0u8; 8192];
        let output_file = File::create(output_path)?;

        // Render and encode (same loop)
        // ...

        encoder.flush(&mut mp3_buffer)?;
        output_file.write_all(&mp3_buffer)?;

        Ok(())
    }
}
```

**Testiranje:**
- Export 5min track to WAV/FLAC/MP3
- Verify audio integrity (spectral analysis)
- Test normalize + dither
- Test stems export (8 tracks)

**ROI:** ✅ Delivery workflow kompletiran

---

**KRAJ FAZE 1:** 8-10 sedmica = **Production-ready beta**

---

## ⚠️ FAZA 2: COMPETITIVE PARITY (6-8 SEDMICA)

### P7: Timeline Playhead Jitter
**Impact:** 🟠🟠 4/10 | **Effort:** 🕐 1 sat | **Priority:** ⚠️ HIGH

**Problem:**
- Playhead update nije synced sa vsync
- Vizuelni stutter tokom playback-a

**Lokacija:** `flutter_ui/lib/providers/timeline_playback_provider.dart:175`

**Rešenje:**
```dart
class TimelinePlaybackProvider extends ChangeNotifier with TickerProviderStateMixin {
  late Ticker _ticker;

  void startPlayback() {
    _ticker = createTicker((elapsed) {
      // Synced to vsync (60fps)
      final position = EngineApi.getTransportPosition();
      _playheadPosition = position;
      notifyListeners();
    });
    _ticker.start();
  }

  void stopPlayback() {
    _ticker.stop();
  }
}
```

**ROI:** ✅ Smooth playback visualization

---

### P8: Biquad SIMD Implementation
**Impact:** 🟠🟠🟠 6/10 | **Effort:** 🕐🕐 2-3 sata | **Priority:** ⚠️ HIGH

**Problem:**
- Scalar processing only
- 20-40% sporije nego moguće
- EQ nije competitive sa FabFilter

**Lokacija:** `crates/rf-dsp/src/biquad.rs:45`

**Rešenje:**
```rust
#[cfg(target_arch = "x86_64")]
pub fn process_avx512(&mut self, input: &[f64], output: &mut [f64]) {
    unsafe {
        use std::arch::x86_64::*;

        // Load coefficients
        let b0 = _mm512_set1_pd(self.b0);
        let b1 = _mm512_set1_pd(self.b1);
        let b2 = _mm512_set1_pd(self.b2);
        let a1 = _mm512_set1_pd(self.a1);
        let a2 = _mm512_set1_pd(self.a2);

        let mut z1 = _mm512_set1_pd(self.z1);
        let mut z2 = _mm512_set1_pd(self.z2);

        // Process 8 samples at once
        for chunk in input.chunks_exact(8) {
            let x = _mm512_loadu_pd(chunk.as_ptr());

            // y[n] = b0*x[n] + z1
            let y = _mm512_fmadd_pd(b0, x, z1);

            // z1 = b1*x[n] - a1*y[n] + z2
            let temp1 = _mm512_mul_pd(b1, x);
            let temp2 = _mm512_fnmadd_pd(a1, y, temp1);
            z1 = _mm512_add_pd(temp2, z2);

            // z2 = b2*x[n] - a2*y[n]
            let temp3 = _mm512_mul_pd(b2, x);
            z2 = _mm512_fnmadd_pd(a2, y, temp3);

            _mm512_storeu_pd(output.as_mut_ptr(), y);
        }

        // Store state
        self.z1 = _mm512_reduce_add_pd(z1) / 8.0;
        self.z2 = _mm512_reduce_add_pd(z2) / 8.0;
    }
}

pub fn process(&mut self, samples: &mut [f64]) {
    #[cfg(target_arch = "x86_64")]
    if is_x86_feature_detected!("avx512f") {
        return unsafe { self.process_avx512(samples, samples) };
    }

    // Fallback to scalar
    self.process_scalar(samples);
}
```

**ROI:** 🚀 **+20-40% EQ performance**

---

### P9: Dynamic EQ Implementation
**Impact:** 🟠🟠🟠 6/10 | **Effort:** 🕐🕐🕐 1 sedmica | **Priority:** ⚠️ HIGH

**Problem:**
- Samo static EQ
- FabFilter Pro-Q 4 ima dynamic per band

**Lokacija:** `crates/rf-dsp/src/eq.rs:350`

**Rešenje:**
```rust
pub struct DynamicEqBand {
    filter: BiquadTDF2,
    envelope: EnvelopeFollower,
    params: DynamicEqParams,
    current_gain: f64,
}

pub struct DynamicEqParams {
    pub static_gain_db: f64,
    pub threshold_db: f64,
    pub ratio: f64,
    pub attack_ms: f64,
    pub release_ms: f64,
    pub knee_db: f64,
}

impl DynamicEqBand {
    pub fn process(&mut self, sample: f64, sample_rate: f64) -> f64 {
        let input_level = sample.abs();

        // Envelope follower
        self.envelope.process(input_level, sample_rate);
        let level_db = 20.0 * self.envelope.value.log10();

        // Compute gain reduction
        let over_threshold = level_db - self.params.threshold_db;
        let gain_reduction = if over_threshold > 0.0 {
            // Apply knee
            let knee_factor = if over_threshold < self.params.knee_db {
                over_threshold / self.params.knee_db
            } else {
                1.0
            };

            -over_threshold * (1.0 - 1.0 / self.params.ratio) * knee_factor
        } else {
            0.0
        };

        // Modulate filter gain
        let target_gain = self.params.static_gain_db + gain_reduction;

        // Smooth gain changes
        let alpha = if target_gain < self.current_gain {
            1.0 - (-1.0 / (self.params.attack_ms * 0.001 * sample_rate)).exp()
        } else {
            1.0 - (-1.0 / (self.params.release_ms * 0.001 * sample_rate)).exp()
        };

        self.current_gain += alpha * (target_gain - self.current_gain);
        self.filter.set_gain(self.current_gain);

        // Process
        self.filter.process(sample)
    }
}

pub struct EnvelopeFollower {
    pub value: f64,
}

impl EnvelopeFollower {
    pub fn process(&mut self, input: f64, sample_rate: f64) {
        let attack_alpha = 1.0 - (-1.0 / (10.0 * 0.001 * sample_rate)).exp();
        let release_alpha = 1.0 - (-1.0 / (100.0 * 0.001 * sample_rate)).exp();

        if input > self.value {
            self.value += attack_alpha * (input - self.value);
        } else {
            self.value += release_alpha * (input - self.value);
        }
    }
}
```

**Testiranje:**
- De-essing on vocal track
- Threshold sweep verification
- Ratio accuracy test
- Attack/release time verification

**ROI:** ✅ Feature parity sa FabFilter Pro-Q 4

---

### P10: True Peak Limiting
**Impact:** 🟠🟠🟠 6/10 | **Effort:** 🕐🕐 3-4 dana | **Priority:** ⚠️ HIGH

**Problem:**
- Master limiter nije true peak
- Ne sprečava inter-sample peaks
- Fails EBU R128

**Lokacija:** `crates/rf-dsp/src/dynamics.rs:850`

**Rešenje:**
```rust
pub struct TruePeakLimiter {
    oversampler: Oversampler4x,
    lookahead_buffer: VecDeque<f64>,
    lookahead_samples: usize,
    ceiling_db: f64,
    release_ms: f64,
    gain_reduction: f64,
    sample_rate: f64,
}

impl TruePeakLimiter {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            oversampler: Oversampler4x::new(),
            lookahead_buffer: VecDeque::new(),
            lookahead_samples: (0.005 * sample_rate) as usize, // 5ms
            ceiling_db: -0.1,
            release_ms: 100.0,
            gain_reduction: 1.0,
            sample_rate,
        }
    }

    pub fn process(&mut self, input: f64) -> f64 {
        // 1. Add to lookahead buffer
        self.lookahead_buffer.push_back(input);

        if self.lookahead_buffer.len() < self.lookahead_samples {
            return 0.0; // Fill buffer first
        }

        // 2. Oversample lookahead window to 4x
        let oversampled: Vec<f64> = self.lookahead_buffer.iter()
            .flat_map(|&s| self.oversampler.upsample(s))
            .collect();

        // 3. Find true peak in oversampled data
        let true_peak = oversampled.iter()
            .map(|&s| s.abs())
            .fold(0.0, f64::max);

        // 4. Calculate required gain reduction
        let ceiling_linear = db_to_linear(self.ceiling_db);
        let required_gr = if true_peak > ceiling_linear {
            ceiling_linear / true_peak
        } else {
            1.0
        };

        // 5. Smooth gain reduction (ballistics)
        let alpha = 1.0 - (-1.0 / (self.release_ms * 0.001 * self.sample_rate)).exp();
        self.gain_reduction += alpha * (required_gr - self.gain_reduction);

        // 6. Apply to delayed sample
        let delayed = self.lookahead_buffer.pop_front().unwrap();
        delayed * self.gain_reduction
    }

    pub fn get_gain_reduction_db(&self) -> f64 {
        linear_to_db(self.gain_reduction)
    }
}

pub struct Oversampler4x {
    // Polyphase FIR filter for upsampling
    upsample_filter: [f64; 32],
    downsample_filter: [f64; 32],
}

impl Oversampler4x {
    pub fn upsample(&self, input: f64) -> [f64; 4] {
        // Insert zeros + filter
        let mut output = [0.0; 4];
        output[0] = input;

        // Apply FIR filter
        for i in 0..4 {
            for (j, &coeff) in self.upsample_filter.iter().enumerate() {
                if i >= j {
                    output[i] += output[i - j] * coeff;
                }
            }
        }

        output
    }
}
```

**ROI:** ✅ Broadcasting-compliant limiting

---

### P11: LUFS Metering UI Integration
**Impact:** 🟡🟡 4/10 | **Effort:** 🕐 2 dana | **Priority:** 🟡 MEDIUM

**Problem:**
- LUFS backend postoji, UI nepovezan
- Nema histogram, range display

**Lokacija:**
- `crates/rf-dsp/src/metering.rs:1200` - Backend
- `flutter_ui/lib/widgets/meters/loudness_meter.dart:120` - UI stub

**Rešenje:**
```dart
// flutter_ui/lib/widgets/meters/loudness_meter.dart
class LoudnessMeter extends StatefulWidget {
  Widget build(BuildContext context) {
    return Consumer<MeterProvider>(
      builder: (context, meters, child) {
        return Column(
          children: [
            // M (Momentary)
            _LufsBar(
              label: 'M',
              value: meters.lufs_m,
              color: Colors.green,
            ),

            // S (Short-term)
            _LufsBar(
              label: 'S',
              value: meters.lufs_s,
              color: Colors.blue,
            ),

            // I (Integrated)
            Text(
              'I: ${meters.lufs_i.toStringAsFixed(1)} LUFS',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),

            // Histogram
            SizedBox(
              height: 100,
              child: CustomPaint(
                painter: LufsHistogramPainter(meters.lufs_histogram),
              ),
            ),

            // Range
            Text(
              'LRA: ${meters.loudness_range.toStringAsFixed(1)} LU',
              style: TextStyle(fontSize: 14),
            ),
          ],
        );
      },
    );
  }
}

class LufsHistogramPainter extends CustomPainter {
  final List<int> histogram;

  void paint(Canvas canvas, Size size) {
    final barWidth = size.width / histogram.length;

    for (int i = 0; i < histogram.length; i++) {
      final barHeight = (histogram[i] / histogram.max()) * size.height;

      canvas.drawRect(
        Rect.fromLTWH(i * barWidth, size.height - barHeight, barWidth, barHeight),
        Paint()..color = Colors.cyan,
      );
    }
  }
}
```

**FFI Bridge:**
```rust
// crates/rf-engine/src/ffi.rs
#[no_mangle]
pub extern "C" fn get_lufs_momentary() -> f64 {
    ENGINE.lock().unwrap().meter.lufs_m()
}

#[no_mangle]
pub extern "C" fn get_lufs_short_term() -> f64 {
    ENGINE.lock().unwrap().meter.lufs_s()
}

#[no_mangle]
pub extern "C" fn get_lufs_integrated() -> f64 {
    ENGINE.lock().unwrap().meter.lufs_i()
}

#[no_mangle]
pub extern "C" fn get_loudness_range() -> f64 {
    ENGINE.lock().unwrap().meter.loudness_range()
}
```

**ROI:** ✅ Professional loudness monitoring

---

### P12: Match EQ
**Impact:** 🟡🟡 4/10 | **Effort:** 🕐🕐🕐 1 sedmica | **Priority:** 🟡 MEDIUM

**Problem:**
- Nema Match EQ feature
- FabFilter Pro-Q 4 ima "EQ Match"

**Rešenje:**
```rust
pub fn match_eq(
    reference: &[f64],
    target: &[f64],
    sample_rate: f64,
    num_bands: usize
) -> Vec<EqBand> {
    // 1. FFT both signals
    let ref_spectrum = compute_spectrum(reference);
    let tgt_spectrum = compute_spectrum(target);

    // 2. Compute ratio per frequency bin
    let mut ratio = vec![0.0; ref_spectrum.len()];
    for i in 0..ref_spectrum.len() {
        ratio[i] = if tgt_spectrum[i] > 0.001 {
            ref_spectrum[i] / tgt_spectrum[i]
        } else {
            1.0
        };
    }

    // 3. Smooth to 1/3 octave
    let smoothed = smooth_third_octave(&ratio, sample_rate);

    // 4. Convert to EQ bands
    let mut bands = Vec::new();
    let freq_step = (sample_rate / 2.0).log2() / num_bands as f64;

    for i in 0..num_bands {
        let freq = 20.0 * 2.0f64.powf(i as f64 * freq_step);
        let bin = (freq / (sample_rate / ratio.len() as f64)) as usize;

        let gain_db = linear_to_db(smoothed[bin]);

        bands.push(EqBand {
            frequency: freq,
            gain_db: gain_db.clamp(-12.0, 12.0),
            q: 1.0,
            filter_type: FilterType::Bell,
            enabled: gain_db.abs() > 0.5,
        });
    }

    bands
}

fn compute_spectrum(signal: &[f64]) -> Vec<f64> {
    let mut planner = FftPlanner::new();
    let fft = planner.plan_fft_forward(signal.len());

    let mut complex: Vec<Complex<f64>> = signal.iter()
        .map(|&s| Complex::new(s, 0.0))
        .collect();

    fft.process(&mut complex);

    // Convert to magnitude
    complex.iter()
        .map(|c| c.norm())
        .collect()
}

fn smooth_third_octave(spectrum: &[f64], sample_rate: f64) -> Vec<f64> {
    let mut smoothed = vec![0.0; spectrum.len()];

    for i in 0..spectrum.len() {
        let freq = i as f64 * sample_rate / spectrum.len() as f64;
        let bandwidth = freq / 3.0; // 1/3 octave

        let bin_start = ((freq - bandwidth / 2.0) / (sample_rate / spectrum.len() as f64)) as usize;
        let bin_end = ((freq + bandwidth / 2.0) / (sample_rate / spectrum.len() as f64)) as usize;

        let mut sum = 0.0;
        let mut count = 0;

        for j in bin_start..bin_end {
            if j < spectrum.len() {
                sum += spectrum[j];
                count += 1;
            }
        }

        smoothed[i] = if count > 0 { sum / count as f64 } else { 0.0 };
    }

    smoothed
}
```

**UI Integration:**
```dart
// flutter_ui/lib/widgets/eq/match_eq_dialog.dart
class MatchEqDialog extends StatefulWidget {
  Future<void> matchEq() async {
    // Load reference audio
    final refPath = await FilePicker.getFile();
    final refAudio = await EngineApi.loadAudio(refPath);

    // Load target (current track)
    final targetAudio = await EngineApi.getCurrentTrackAudio();

    // Compute match
    final eqBands = await EngineApi.matchEq(refAudio, targetAudio, 16);

    // Apply to EQ
    eqProvider.setAllBands(eqBands);
  }
}
```

**ROI:** ✅ Advanced mastering workflow

---

### P13: Spectral Dynamics
**Impact:** 🟡🟡🟡 5/10 | **Effort:** 🕐🕐🕐🕐 2 sedmice | **Priority:** 🟡 MEDIUM

**Problem:**
- Nema spectral compressor/gate
- iZotope Ozone 11 ima "Spectral Shaper"

**Rešenje:**
```rust
pub struct SpectralDynamics {
    fft_size: usize,
    hop_size: usize,
    fft_forward: Arc<dyn Fft<f64>>,
    fft_inverse: Arc<dyn Fft<f64>>,
    window: Vec<f64>,
    input_buffer: VecDeque<f64>,
    output_buffer: VecDeque<f64>,
    bands: Vec<SpectralBand>,
}

pub struct SpectralBand {
    pub freq_range: (f64, f64),
    pub threshold_db: f64,
    pub ratio: f64,
    pub attack_ms: f64,
    pub release_ms: f64,
    pub gain_reduction: Vec<f64>,
}

impl SpectralDynamics {
    pub fn process(&mut self, input: &[f64], output: &mut [f64]) {
        // 1. Buffer input
        for &sample in input {
            self.input_buffer.push_back(sample);
        }

        // 2. Process frames
        while self.input_buffer.len() >= self.fft_size {
            let frame: Vec<f64> = self.input_buffer.drain(..self.fft_size).collect();

            // 3. Apply window
            let windowed: Vec<Complex<f64>> = frame.iter()
                .zip(&self.window)
                .map(|(&s, &w)| Complex::new(s * w, 0.0))
                .collect();

            // 4. FFT forward
            let mut spectrum = windowed.clone();
            self.fft_forward.process(&mut spectrum);

            // 5. Apply dynamics per frequency band
            for band in &mut self.bands {
                let bin_start = (band.freq_range.0 / self.sample_rate * self.fft_size as f64) as usize;
                let bin_end = (band.freq_range.1 / self.sample_rate * self.fft_size as f64) as usize;

                for bin in bin_start..bin_end {
                    let magnitude = spectrum[bin].norm();
                    let magnitude_db = 20.0 * magnitude.log10();

                    // Compressor
                    let over_threshold = magnitude_db - band.threshold_db;
                    let gain_reduction = if over_threshold > 0.0 {
                        -over_threshold * (1.0 - 1.0 / band.ratio)
                    } else {
                        0.0
                    };

                    // Apply gain reduction
                    let gain_linear = db_to_linear(gain_reduction);
                    spectrum[bin] *= gain_linear;
                }
            }

            // 6. FFT inverse
            let mut time_frame = spectrum;
            self.fft_inverse.process(&mut time_frame);

            // 7. Overlap-add to output buffer
            for (i, sample) in time_frame.iter().enumerate() {
                let idx = i % self.hop_size;
                if idx < self.output_buffer.len() {
                    self.output_buffer[idx] += sample.re;
                } else {
                    self.output_buffer.push_back(sample.re);
                }
            }
        }

        // 8. Pop output
        for i in 0..output.len() {
            output[i] = self.output_buffer.pop_front().unwrap_or(0.0);
        }
    }
}
```

**ROI:** ✅ Advanced de-essing, de-humming, spectral repair

---

**KRAJ FAZE 2:** 6-8 sedmica = **Professional release**

---

## 🔵 FAZA 3: ADVANCED FEATURES (8-12 SEDMICA)

### P14: Video Track Playback
**Impact:** 🟡 3/10 | **Effort:** 🕐🕐🕐🕐🕐 3-4 sedmice | **Priority:** 🔵 LOW

**Problem:**
- VideoTrack widget postoji (641 linija)
- Nema video decoder-a

**Rešenje:**
```rust
// crates/rf-video/src/decoder.rs (NOVO CRATE)
use ffmpeg_next as ffmpeg;

pub struct VideoDecoder {
    context: ffmpeg::format::context::Input,
    video_stream_index: usize,
    decoder: ffmpeg::decoder::Video,
    frame_cache: HashMap<u64, Frame>,
}

impl VideoDecoder {
    pub fn open(path: &Path) -> Result<Self> {
        let mut context = ffmpeg::format::input(&path)?;
        let video_stream = context.streams()
            .best(ffmpeg::media::Type::Video)
            .ok_or("No video stream")?;

        let video_stream_index = video_stream.index();
        let decoder = video_stream.codec().decoder().video()?;

        Ok(Self {
            context,
            video_stream_index,
            decoder,
            frame_cache: HashMap::new(),
        })
    }

    pub fn get_frame_at_time(&mut self, time: f64) -> Result<Frame> {
        let frame_number = (time * self.decoder.fps()) as u64;

        // Check cache
        if let Some(frame) = self.frame_cache.get(&frame_number) {
            return Ok(frame.clone());
        }

        // Seek + decode
        self.context.seek(time as i64, ..)?;

        for (stream, packet) in self.context.packets() {
            if stream.index() == self.video_stream_index {
                self.decoder.send_packet(&packet)?;

                let mut decoded = ffmpeg::util::frame::video::Video::empty();
                if self.decoder.receive_frame(&mut decoded).is_ok() {
                    let frame = Frame::from_ffmpeg(decoded);
                    self.frame_cache.insert(frame_number, frame.clone());
                    return Ok(frame);
                }
            }
        }

        Err("Failed to decode frame".into())
    }
}

pub struct Frame {
    pub width: usize,
    pub height: usize,
    pub data: Vec<u8>, // RGBA
}
```

**UI Integration:**
```dart
// flutter_ui/lib/widgets/timeline/video_track.dart
class VideoTrack extends StatefulWidget {
  Widget build(BuildContext context) {
    return Consumer<TimelinePlaybackProvider>(
      builder: (context, playback, child) {
        return FutureBuilder<ui.Image>(
          future: _getVideoFrame(playback.position),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return CircularProgressIndicator();

            return RawImage(image: snapshot.data);
          },
        );
      },
    );
  }

  Future<ui.Image> _getVideoFrame(double time) async {
    final frameData = await EngineApi.getVideoFrame(videoPath, time);
    return _createImage(frameData);
  }
}
```

**ROI:** ✅ Post-production workflow support

---

### P15: Chord Track
**Impact:** 🔵 2/10 | **Effort:** 🕐🕐 1 sedmica | **Priority:** 🔵 LOW

**Problem:**
- Cubase 14 ima chord track
- Korisno za MIDI arrangement

**Rešenje:**
```rust
pub struct ChordTrack {
    chords: Vec<ChordEvent>,
}

pub struct ChordEvent {
    pub time: f64,
    pub duration: f64,
    pub chord: Chord,
}

pub struct Chord {
    pub root: Note,
    pub quality: ChordQuality,
    pub extensions: Vec<Extension>,
}

pub enum ChordQuality {
    Major,
    Minor,
    Diminished,
    Augmented,
    Dominant7,
    Major7,
    Minor7,
}

impl ChordTrack {
    pub fn detect_chords(midi_notes: &[MidiNote]) -> Vec<ChordEvent> {
        // Simple chord detection algorithm
        let mut chords = Vec::new();
        let time_quantize = 0.5; // Detect chords every 0.5s

        let mut t = 0.0;
        while t < midi_notes.last().unwrap().end_time {
            let active_notes: Vec<_> = midi_notes.iter()
                .filter(|n| n.start_time <= t && n.end_time > t)
                .collect();

            if active_notes.len() >= 3 {
                let chord = analyze_chord(&active_notes);
                chords.push(ChordEvent {
                    time: t,
                    duration: time_quantize,
                    chord,
                });
            }

            t += time_quantize;
        }

        chords
    }
}

fn analyze_chord(notes: &[&MidiNote]) -> Chord {
    let pitches: Vec<u8> = notes.iter().map(|n| n.pitch % 12).collect();

    // Detect root + quality
    if pitches.contains(&0) && pitches.contains(&4) && pitches.contains(&7) {
        Chord {
            root: Note::from_pitch(notes[0].pitch),
            quality: ChordQuality::Major,
            extensions: vec![],
        }
    } else if pitches.contains(&0) && pitches.contains(&3) && pitches.contains(&7) {
        Chord {
            root: Note::from_pitch(notes[0].pitch),
            quality: ChordQuality::Minor,
            extensions: vec![],
        }
    } else {
        // Default to C major
        Chord {
            root: Note::C,
            quality: ChordQuality::Major,
            extensions: vec![],
        }
    }
}
```

**ROI:** ⚠️ Nice-to-have, ne blocker

---

### P16: Tempo Automation
**Impact:** 🔵 2/10 | **Effort:** 🕐 3-4 dana | **Priority:** 🔵 LOW

**Problem:**
- Tempo je fixed
- Ne može se automati zovati tempo changes

**Rešenje:**
```rust
pub struct TempoTrack {
    tempo_events: Vec<TempoEvent>,
}

pub struct TempoEvent {
    pub time: f64,
    pub tempo: f64,
    pub curve: CurveType,
}

pub enum CurveType {
    Linear,
    Exponential,
    Logarithmic,
}

impl TempoTrack {
    pub fn get_tempo_at(&self, time: f64) -> f64 {
        // Find surrounding events
        let before = self.tempo_events.iter()
            .rev()
            .find(|e| e.time <= time);

        let after = self.tempo_events.iter()
            .find(|e| e.time > time);

        match (before, after) {
            (Some(b), Some(a)) => {
                // Interpolate
                let t = (time - b.time) / (a.time - b.time);
                interpolate_tempo(b.tempo, a.tempo, t, b.curve)
            },
            (Some(b), None) => b.tempo,
            _ => 120.0, // Default
        }
    }
}

fn interpolate_tempo(start: f64, end: f64, t: f64, curve: CurveType) -> f64 {
    match curve {
        CurveType::Linear => start + (end - start) * t,
        CurveType::Exponential => start * (end / start).powf(t),
        CurveType::Logarithmic => start + (end - start) * t.sqrt(),
    }
}
```

**ROI:** ⚠️ Film scoring feature

---

### P17: Variaudio UI (Pitch Correction)
**Impact:** 🔵🔵 3/10 | **Effort:** 🕐🕐🕐 2 sedmice | **Priority:** 🔵 LOW

**Problem:**
- Pitch shift backend postoji
- Nema UI za note-by-note editing

**Rešenje:**
```dart
// flutter_ui/lib/widgets/audio_editor/variaudio_editor.dart
class VariaudioEditor extends StatefulWidget {
  final AudioClip clip;

  Widget build(BuildContext context) {
    return FutureBuilder<List<PitchSegment>>(
      future: _analyzePitch(clip),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return CircularProgressIndicator();

        return CustomPaint(
          painter: PitchCurvePainter(
            segments: snapshot.data!,
            onSegmentDrag: _handlePitchDrag,
          ),
        );
      },
    );
  }

  Future<List<PitchSegment>> _analyzePitch(AudioClip clip) async {
    return await EngineApi.analyzePitch(clip.id);
  }

  void _handlePitchDrag(PitchSegment segment, double newPitch) {
    EngineApi.setPitchShift(clip.id, segment.startTime, newPitch);
  }
}

class PitchSegment {
  double startTime;
  double endTime;
  double detectedPitch;
  double targetPitch;
}
```

**Backend:**
```rust
pub fn analyze_pitch(audio: &[f64], sample_rate: f64) -> Vec<PitchSegment> {
    let mut segments = Vec::new();
    let hop_size = 512;

    for i in (0..audio.len()).step_by(hop_size) {
        let window = &audio[i..i + hop_size];

        // YIN algorithm for pitch detection
        let pitch = yin_pitch_detection(window, sample_rate);

        segments.push(PitchSegment {
            start_time: i as f64 / sample_rate,
            end_time: (i + hop_size) as f64 / sample_rate,
            detected_pitch: pitch,
            target_pitch: pitch, // User can adjust
        });
    }

    segments
}
```

**ROI:** ⚠️ Vocal editing nice-to-have

---

**KRAJ FAZE 3:** 8-12 sedmica = **Competitive edge features**

---

## 🎯 TOTALNI PREGLED

### Po Fazi

| Faza | Trajanje | Deliverable | Priority |
|------|----------|-------------|----------|
| **Faza 0** | 2 sata | Quick wins (+10-15% perf) | 🔥🔥🔥 |
| **Faza 1** | 8-10 sed | Beta release (plugin + rec + export) | 🔥🔥🔥 |
| **Faza 2** | 6-8 sed | Professional (dynamic EQ + peak + LUFS) | ⚠️⚠️ |
| **Faza 3** | 8-12 sed | Advanced (video + chord + variaudio) | 🔵 |

**Ukupno:** 26-32 sedmice (6-8 meseci)

---

### Po Prioritetu

| Prioritet | Count | Total Effort | Impact Summary |
|-----------|-------|--------------|----------------|
| 🔥 **IMMEDIATE/URGENT** | 6 | 9-12 sed | Blockers + Quick wins |
| ⚠️ **HIGH** | 5 | 2-3 sed | Competitive parity |
| 🟡 **MEDIUM** | 3 | 4-5 sed | Professional features |
| 🔵 **LOW** | 3 | 8-12 sed | Nice-to-have |

---

### Po Impact-u

| Impact | Count | Examples |
|--------|-------|----------|
| **10/10** | 1 | Plugin hosting |
| **8/10** | 2 | Recording, Export |
| **6/10** | 4 | RwLock, Biquad SIMD, Dynamic EQ, True Peak |
| **5/10** | 2 | EQ Vec, Meter storm, Spectral |
| **4/10** | 3 | Jitter, LUFS, Match EQ |
| **3/10** | 2 | Video, Variaudio |
| **2/10** | 2 | Chord, Tempo |

---

### Quick Reference - Top 10 Prioriteta

1. 🔥 **P4** - RwLock fix (30min) → -2-3ms latency
2. 🔥 **P5** - EQ Vec fix (45min) → -3-5% CPU
3. 🔥 **P6** - Meter throttle (45min) → +30% FPS
4. 🔥 **P1** - Plugin hosting (4-6 sed) → Unblocks ecosystem
5. 🔥 **P2** - Recording (2-3 sed) → Core workflow
6. 🔥 **P3** - Export (1-2 sed) → Delivery
7. ⚠️ **P7** - Timeline jitter (1h) → Smooth playback
8. ⚠️ **P8** - Biquad SIMD (2-3h) → +20-40% EQ perf
9. ⚠️ **P9** - Dynamic EQ (1 sed) → FabFilter parity
10. ⚠️ **P10** - True peak (3-4 dana) → Broadcasting std

---

## 📊 ROI ANALIZA

### Najviši ROI (Effort/Impact)

| Task | ROI Score | Reason |
|------|-----------|--------|
| **P4: RwLock fix** | ⭐⭐⭐⭐⭐ 10/10 | 30min = -2-3ms latency |
| **P5: EQ Vec fix** | ⭐⭐⭐⭐⭐ 9/10 | 45min = -3-5% CPU |
| **P6: Meter throttle** | ⭐⭐⭐⭐⭐ 9/10 | 45min = +30% FPS |
| **P8: Biquad SIMD** | ⭐⭐⭐⭐ 8/10 | 2-3h = +20-40% EQ perf |
| **P7: Timeline jitter** | ⭐⭐⭐⭐ 8/10 | 1h = Smooth 60fps |
| **P10: True peak** | ⭐⭐⭐ 7/10 | 3-4 dana = Broadcasting |
| **P3: Export** | ⭐⭐⭐ 7/10 | 1-2 sed = Delivery |
| **P9: Dynamic EQ** | ⭐⭐⭐ 6/10 | 1 sed = FabFilter parity |
| **P2: Recording** | ⭐⭐⭐ 6/10 | 2-3 sed = Core workflow |
| **P1: Plugin hosting** | ⭐⭐ 5/10 | 4-6 sed = Massive unlock |

---

## 🚀 PREPORUČENI REDOSLED IMPLEMENTACIJE

### DAN 1 (2 sata):
1. P4: RwLock fix (30min)
2. P5: EQ Vec fix (45min)
3. P6: Meter throttle (45min)

**Rezultat:** +10-15% overall performance

---

### NEDELJA 1-6 (Plugin Hosting):
4. P1: VST3 scanner + loading + processing + UI + automation

**Rezultat:** Plugin ekosistem otvoren

---

### NEDELJA 7-9 (Recording):
5. P2: Input device + arm + recording loop + take mgmt

**Rezultat:** Core DAW workflow kompletiran

---

### NEDELJA 10 (Export):
6. P3: WAV export + FLAC/MP3 + stems

**Rezultat:** Delivery workflow kompletiran

---

### NEDELJA 11 (Polish):
7. P7: Timeline jitter fix (1h)
8. P8: Biquad SIMD (2-3h)

**Rezultat:** Smooth UI + +20-40% EQ perf

---

### NEDELJA 12-17 (Advanced DSP):
9. P9: Dynamic EQ (1 sed)
10. P10: True peak (3-4 dana)
11. P11: LUFS UI (2 dana)
12. P12: Match EQ (1 sed)
13. P13: Spectral dynamics (2 sed)

**Rezultat:** Professional-grade DSP suite

---

### NEDELJA 18-25 (Optional Advanced):
14. P14: Video (3-4 sed)
15. P15: Chord track (1 sed)
16. P16: Tempo automation (3-4 dana)
17. P17: Variaudio (2 sed)

**Rezultat:** Competitive edge features

---

## 📈 PROGRESS TRACKING

### Week-by-Week Milestones

| Week | Tasks | Milestone |
|------|-------|-----------|
| **W1** | P4, P5, P6 + P1 start | Quick wins complete |
| **W2-6** | P1 continue | Plugin hosting |
| **W7-9** | P2 | Recording |
| **W10** | P3 | **🎉 BETA RELEASE** |
| **W11** | P7, P8 | Polish |
| **W12** | P9 | Dynamic EQ |
| **W13** | P10 | True peak |
| **W14** | P11 | LUFS |
| **W15** | P12 | Match EQ |
| **W16-17** | P13 | **🎉 PROFESSIONAL RELEASE** |
| **W18-25** | P14-P17 | Advanced features |

---

## ✅ DONE CRITERIA

### Per Prioritet

#### P1-P3 (Critical):
- [ ] VST3 plugins load without crash
- [ ] 10 popular plugins tested (Serum, FabFilter, Waves)
- [ ] Recording captures audio with < 10ms latency
- [ ] Export produces bit-perfect WAV files
- [ ] All features have unit tests

#### P4-P6 (Quick Wins):
- [ ] Audio thread never blocks (< 1ms worst case)
- [ ] Zero heap allocations in DSP loop
- [ ] 60fps UI sustained under load

#### P7-P10 (High):
- [ ] Playhead vsync locked (< 1ms jitter)
- [ ] EQ 20-40% faster (benchmark verified)
- [ ] Dynamic EQ matches FabFilter behavior
- [ ] True peak < -0.1dBTP guaranteed

#### P11-P13 (Medium):
- [ ] LUFS displays M/S/I correctly
- [ ] Match EQ produces usable results
- [ ] Spectral dynamics de-esses vocals

#### P14-P17 (Low):
- [ ] Video plays frame-accurately
- [ ] Chord detection 80%+ accurate
- [ ] Tempo automation smooth
- [ ] Variaudio usable for pitch correction

---

## 🎯 FINAL SUMMARY

**Ukupno problema:** 17
**Ukupno vreme:** 26-32 sedmice (6-8 meseci)
**Kritičnih:** 6 problema (blockers)
**Quick Wins:** 3 problema (2 sata)

**Minimalan put do produkcije:** Faza 0 + Faza 1 = **10 sedmica**

**ROI:**
- ✅ Quick Wins: 2h = +10-15% performance
- ✅ Beta: 10 sed = Production-ready DAW
- ✅ Professional: 16-18 sed = Competitive parity
- ✅ Advanced: 26-32 sed = Industry-leading features

---

**Kraj Prioritetnog Spiska**
