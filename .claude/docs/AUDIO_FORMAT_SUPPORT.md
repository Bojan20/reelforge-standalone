# Audio Format Support — FluxForge Studio

**Version:** 1.0
**Date:** 2026-01-26
**Status:** Production Ready

---

## Overview

FluxForge Studio provides comprehensive audio format support for both **import** (upload/decode) and **export** (encode) operations. This document details all supported formats, their capabilities, and implementation details.

---

## Import (Decode) Support

All import functionality is powered by the **Symphonia** library (v0.5) — a pure Rust audio decoding library with no external dependencies.

### Supported Import Formats

| Format | Extension(s) | Container | Codec | Quality | Notes |
|--------|--------------|-----------|-------|---------|-------|
| **WAV** | .wav | RIFF | PCM | Lossless | 8/16/24/32-bit, float |
| **AIFF** | .aiff, .aif | AIFF | PCM | Lossless | Big-endian, 8/16/24/32-bit |
| **FLAC** | .flac | FLAC | FLAC | Lossless | Up to 24-bit, 192kHz |
| **ALAC** | .m4a | MP4/M4A | Apple Lossless | Lossless | Apple ecosystem |
| **MP3** | .mp3 | — | MPEG Layer III | Lossy | All bitrates, VBR/CBR |
| **OGG/Vorbis** | .ogg | OGG | Vorbis | Lossy | Free/open format |
| **AAC** | .aac, .m4a, .mp4 | ADTS/MP4 | AAC-LC | Lossy | Streaming, Apple Music |
| **M4A** | .m4a | MP4/ISO | AAC/ALAC | Both | Apple container format |

### Import Implementation

**Location:** `crates/rf-engine/src/ffi.rs` — `audio_get_metadata()`, `audio_decode_file()`

**Symphonia Features (Cargo.toml):**
```toml
symphonia = { version = "0.5", features = [
    "aac",      # AAC decoder (includes ADTS stream support)
    "aiff",     # AIFF container
    "alac",     # Apple Lossless
    "flac",     # FLAC
    "isomp4",   # M4A container (AAC, ALAC)
    "mp3",      # MP3
    "ogg",      # OGG container
    "pcm",      # PCM codec
    "vorbis",   # Vorbis decoder
    "wav",      # WAV container
] }
```

### Duration Detection (3-Tier Fallback)

For formats where duration isn't immediately available (MP3, VBR files), a 3-tier fallback system is used:

| Tier | Method | Accuracy | Speed |
|------|--------|----------|-------|
| 1 | `codec_params.n_frames` | Exact | Instant |
| 2 | `time_base + n_frames` calculation | Exact | Instant |
| 3 | Packet scan (frame counting) | Exact | ~50ms |

**Implementation:** `crates/rf-engine/src/ffi.rs:audio_get_metadata()`

---

## Export (Encode) Support

Export uses a combination of **native Rust encoders** and **FFmpeg fallback** for lossy formats.

### Supported Export Formats

| Format | Extension | Quality | Encoder | Native | Notes |
|--------|-----------|---------|---------|--------|-------|
| **WAV** | .wav | Lossless | hound | ✅ Yes | 16/24/32-bit, float |
| **AIFF** | .aiff | Lossless | Custom | ✅ Yes | Big-endian, 8/16/24/32-bit |
| **FLAC** | .flac | Lossless | flac-bound | ✅ Yes | Compression 0-8 |
| **MP3** | .mp3 | Lossy | mp3lame-encoder | ✅ Yes | CBR 128/192/256/320, VBR 0-9 |
| **OGG/Vorbis** | .ogg | Lossy | vorbis-encoder | ✅ Yes | Quality -1 to 10 |
| **Opus** | .opus | Lossy | audiopus | ✅ Yes | 6-510 kbps, complexity 0-10 |
| **AAC** | .m4a | Lossy | FFmpeg | ❌ No | 128/192/256/320 kbps |

### Native Encoders (No External Dependencies)

#### WAV Encoder
- **Library:** hound v3.5
- **Bit Depths:** 16-bit, 24-bit, 32-bit integer, 32-bit float
- **Dithering:** None, TPDF, Shaped
- **Location:** `crates/rf-offline/src/encoder.rs` — `WavEncoder`

#### AIFF Encoder
- **Library:** Custom Rust implementation
- **Bit Depths:** 8-bit, 16-bit, 24-bit, 32-bit
- **Byte Order:** Big-endian (network order)
- **Sample Rate:** 80-bit IEEE 754 extended precision
- **Location:** `crates/rf-offline/src/encoder.rs` — `AiffEncoder`

**AIFF Structure:**
```
FORM chunk (container)
├── AIFF type identifier
├── COMM chunk (18 bytes)
│   ├── num_channels (2 bytes)
│   ├── num_sample_frames (4 bytes)
│   ├── sample_size (2 bytes)
│   └── sample_rate (10 bytes, 80-bit extended)
└── SSND chunk (audio data)
    ├── offset (4 bytes)
    ├── block_size (4 bytes)
    └── sound_data (variable)
```

#### FLAC Encoder
- **Library:** flac-bound v0.5
- **Bit Depths:** 16-bit, 24-bit
- **Compression:** Level 0 (fastest) to 8 (best)
- **Location:** `crates/rf-offline/src/encoder.rs` — `FlacEncoder`

#### MP3 Encoder (Native LAME)
- **Library:** mp3lame-encoder v0.1 (LAME bindings)
- **Bit Rates:** CBR 96/112/128/160/192/224/256/320 kbps
- **VBR Quality:** 0 (best) to 9 (smallest)
- **Channels:** Mono, Stereo
- **Sample Rates:** 8kHz - 48kHz
- **Location:** `crates/rf-offline/src/encoder.rs` — `LameMp3Encoder`
- **No FFmpeg required!** ✅

**LAME Quality Levels (VBR):**
| Quality | Setting | Description |
|---------|---------|-------------|
| 0 | Best | Highest quality, largest files |
| 1-2 | NearBest | Excellent quality |
| 3-4 | VeryNice | Very good quality |
| 5 | Good | Good quality (default) |
| 6-7 | Decent | Acceptable quality |
| 8-9 | Worst | Smallest files |

#### OGG/Vorbis Encoder (Native libvorbis)
- **Library:** vorbis-encoder v0.1 (libvorbis bindings)
- **Quality Levels:** -1 (lowest ~45kbps) to 10 (highest ~500kbps)
- **Channels:** Mono, Stereo
- **Sample Rates:** Standard rates (44.1kHz, 48kHz, etc.)
- **Location:** `crates/rf-offline/src/encoder.rs` — `NativeOggEncoder`
- **No FFmpeg required!** ✅

**OGG Quality Levels:**
| Quality | Approx Bitrate | Description |
|---------|----------------|-------------|
| -1 | ~45 kbps | Lowest quality |
| 0-2 | ~64-96 kbps | Low quality |
| 3-4 | ~112-128 kbps | Medium quality |
| 5-6 | ~160-192 kbps | Good quality |
| 7-8 | ~224-256 kbps | High quality (default: 8) |
| 9-10 | ~320-500 kbps | Best quality |

#### Opus Encoder (Native libopus)
- **Library:** audiopus v0.3 (libopus bindings)
- **Bitrates:** 6-510 kbps (default: 256 kbps)
- **Complexity:** 0 (fastest) to 10 (best quality, default)
- **Channels:** Mono, Stereo
- **Sample Rate:** 48kHz (automatic resampling from other rates)
- **Container:** OGG with RFC 7845 compliant headers
- **Location:** `crates/rf-offline/src/encoder.rs` — `NativeOpusEncoder`
- **No FFmpeg required!** ✅
- **Build Requirement:** libopus via pkg-config (`brew install opus` on macOS)

**Opus Bitrate Guidelines:**
| Bitrate | Use Case | Description |
|---------|----------|-------------|
| 6-24 kbps | VoIP | Speech only, very low quality |
| 32-64 kbps | Streaming speech | Good speech quality |
| 96-128 kbps | Music streaming | Good music quality |
| 160-256 kbps | High-quality music | Excellent quality (default: 256) |
| 320-510 kbps | Archival | Transparent quality |

### FFmpeg Fallback Encoders

For AAC encoding, FFmpeg is used via subprocess call (no good native Rust AAC encoder exists).

**Requirements:**
- FFmpeg must be installed and in PATH
- Detection: `ffmpeg -version`

**Location:** `crates/rf-offline/src/encoder.rs` — `AacEncoder`

**Availability Check:**
```rust
pub fn available_encoders() -> Vec<&'static str> {
    // Native encoders (always available - no external dependencies!)
    let mut available = vec!["wav", "aiff", "flac", "mp3", "ogg", "opus"];

    // FFmpeg-based encoders (require ffmpeg)
    if FfmpegMp3Encoder::is_available() {
        available.push("aac");
    }

    available
}
```

---

## Configuration Types

**Location:** `crates/rf-offline/src/formats.rs`

### WavConfig
```rust
pub struct WavConfig {
    pub bit_depth: u8,       // 16, 24, 32
    pub use_float: bool,     // Use 32-bit float
    pub dithering: DitheringMode,
}
```

### AiffConfig
```rust
pub struct AiffConfig {
    pub bit_depth: u8,       // 8, 16, 24, 32
    pub dithering: DitheringMode,
}
```

### FlacConfig
```rust
pub struct FlacConfig {
    pub bit_depth: u8,       // 16, 24
    pub compression_level: u8, // 0-8
}
```

### Mp3Config
```rust
pub struct Mp3Config {
    pub bitrate: Mp3Bitrate, // Kbps128, Kbps192, Kbps256, Kbps320
    pub vbr: bool,
}
```

### OggConfig
```rust
pub struct OggConfig {
    pub quality: u8,         // 0-10
}
```

### AacConfig
```rust
pub struct AacConfig {
    pub bitrate: u32,        // kbps
    pub profile: AacProfile, // LC, HE, HEv2
}
```

### OpusConfig
```rust
pub struct OpusConfig {
    pub bitrate: u32,        // kbps (6-510)
    pub application: OpusApplication, // Audio, Voip, LowDelay
}
```

---

## FFI Functions

### Import FFI

| Function | Description | Returns |
|----------|-------------|---------|
| `audio_get_metadata(path)` | Get file info (duration, sample_rate, channels) | JSON |
| `audio_decode_file(path)` | Full decode to samples | AudioBuffer |
| `audio_decode_segment(path, start_ms, end_ms)` | Partial decode | AudioBuffer |

### Export FFI

| Function | Description | Returns |
|----------|-------------|---------|
| `offline_process_file(input, output, format_id)` | Convert file | Result |
| `offline_get_available_encoders()` | List available encoders | JSON array |
| `offline_set_format_config(format, config_json)` | Configure encoder | Result |

---

## Dart/Flutter Integration

### Native FFI Bindings

**Location:** `flutter_ui/lib/src/rust/native_ffi.dart`

```dart
// Import metadata
Map<String, dynamic> getAudioMetadata(String path);

// Available export formats
List<String> getAvailableEncoders();

// Process/convert file
bool processAudioFile(String input, String output, int formatId);
```

### Format ID Mapping

| ID | Format | Extension |
|----|--------|-----------|
| 0 | WAV 16-bit | .wav |
| 1 | WAV 24-bit | .wav |
| 2 | WAV 32-bit float | .wav |
| 3 | AIFF 16-bit | .aiff |
| 4 | AIFF 24-bit | .aiff |
| 5 | FLAC | .flac |
| 6 | MP3 320kbps | .mp3 |
| 7 | MP3 256kbps | .mp3 |
| 8 | MP3 192kbps | .mp3 |
| 9 | MP3 128kbps | .mp3 |
| 10 | OGG Q8 | .ogg |
| 11 | OGG Q6 | .ogg |
| 12 | AAC 256kbps | .m4a |
| 13 | AAC 192kbps | .m4a |
| 14 | Opus 128kbps | .opus |

---

## Quality Recommendations

### For Distribution/Streaming
| Use Case | Recommended Format | Reason |
|----------|-------------------|--------|
| Apple Music/iTunes | AAC 256kbps | Native format |
| Spotify/General | OGG Q8 or MP3 320 | Wide compatibility |
| Gaming (web) | OGG Q6 | Small size, good quality |
| Gaming (mobile) | AAC 192kbps | iOS native, Android OK |
| Podcast | MP3 128kbps | Universal support |

### For Archival/Mastering
| Use Case | Recommended Format | Reason |
|----------|-------------------|--------|
| Master archive | WAV 24-bit | Maximum quality |
| Cross-platform | FLAC | Lossless, smaller |
| Apple ecosystem | AIFF 24-bit | Native, metadata |
| Web delivery | FLAC | Modern browsers support |

---

## Limitations

1. **No AAC native encoder** — Requires FFmpeg (no good Rust AAC encoder exists)
2. **No WMA support** — Microsoft proprietary
3. **No DSD support** — Specialized format
4. **ALAC export not supported** — Apple proprietary encoder
5. **Opus requires libopus** — Install via pkg-config (`brew install opus` on macOS)

---

## Future Improvements

- [x] Native MP3 encoder (LAME via mp3lame-encoder) — ✅ DONE 2026-01-26
- [x] Native OGG/Vorbis encoder (vorbis-encoder) — ✅ DONE 2026-01-26
- [x] Native Opus encoder (audiopus + ogg) — ✅ DONE 2026-01-26
- [ ] Native AAC encoder (fdk-aac bindings) — No good Rust encoder exists
- [ ] Batch conversion progress callbacks
- [ ] Audio preview during conversion
- [ ] Format auto-detection from extension

---

## Related Documentation

- `.claude/architecture/SLOT_LAB_SYSTEM.md` — Audio asset workflow
- `.claude/architecture/OFFLINE_DSP_PIPELINE.md` — Batch processing
- `crates/rf-offline/README.md` — Crate documentation
