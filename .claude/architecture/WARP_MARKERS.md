# Warp Markers — Architecture Document

**Created:** 2026-03-21
**Status:** Research complete, ready for implementation

---

## Kako to rade veliki DAW-ovi

### Cubase — AudioWarp + Hitpoints

**Workflow:**
1. **Hitpoint Detection** — automatski detektuje transienti u audio fajlu (amplitude peaks)
2. **Hitpoints → Warp Tabs** — konvertuje hitpoints u warp tabove (editabilne markere)
3. **Free Warp** — korisnik može da pomeri bilo koji marker i audio se stretch-uje između markera
4. **Quantize** — automatski snap warp tabova na grid (quantize audio kao MIDI)

**Tri tipa markera:**
- Hitpoints (svetlo plavi) — automatski detektovani
- Warp Tabs (narandžasti) — editabilni, kontrolišu stretch
- Q-Points — koriste se za quantize operacije

**Iza kulisa:** Élastique Pro procesira svaki segment između markera sa različitim stretch ratio-om.

### Reaper — Stretch Markers

**Workflow:**
1. Tab za Dynamic Split detektuje transienti
2. "Create stretch markers at transients" kreira markere
3. Drag marker → audio se stretch-uje na jednoj strani, kompresuje na drugoj
4. Adjacent markeri su granice — audio izvan granica se ne menja

**Unique:** Linked markers across selected tracks — pomeri jedan, svi linked prate.

**Iza kulisa:** Élastique (isti kao Cubase) procesira segmente između markera.

### Pro Tools — Elastic Audio

**Workflow:**
1. Odaberi algoritam na traku (Polyphonic/Rhythmic/Monophonic/Varispeed)
2. Čitav fajl se analizira — automatski Event Markers na transientima
3. "Warp" view — prikazuje markere, korisnik ih pomera
4. Range Warp — kompresuje jednu stranu, ekspandira drugu

**Unique:** X-Form offline rendering sa iZotope Radius za best quality.

### Ableton Live — Warp Markers

**Workflow:**
1. Automatski detektuje transienti (sive tačke na vrhu waveform-a)
2. Pomeri transient → postaje žuti Warp Marker
3. Audio između markera se stretch-uje/kompresuje
4. Seg. BPM pokazuje tempo svakog segmenta

**Unique:** Warp Modes — različiti granular synthesis pristupi (Beats, Tones, Texture, Re-Pitch, Complex, Complex Pro).

### Logic Pro — Flex Time

**Workflow:**
1. Enable Flex na traku → automatska analiza transienata
2. Transient Markers (sivi, automatski) se pojave
3. Klik → Flex Marker (zeleni, editabilni)
4. Drag → audio se stretch-uje

**Unique:** Flex Pitch — monophonic pitch editing (kao Melodyne).

---

## Zajednički pattern u SVIM DAW-ovima

Svi koriste ISTI koncept:

```
Audio Clip
  ├─ Transient Detection → lista momenata (u source samples)
  ├─ Warp Markers → lista parova (source_pos, timeline_pos)
  └─ Stretch Engine → per-segment stretch ratio = timeline_gap / source_gap
```

**Data model:**
```
WarpMarker {
    source_position: f64,    // pozicija u ORIGINALNOM audio fajlu (samples)
    timeline_position: f64,  // pozicija na TIMELINE-u (samples ili seconds)
    is_locked: bool,         // ne može se pomeriti automatski
    marker_type: enum { Auto, Manual, Quantized }
}
```

**Stretch per segment:**
```
segment[i] = between marker[i] and marker[i+1]
source_length[i] = marker[i+1].source_pos - marker[i].source_pos
timeline_length[i] = marker[i+1].timeline_pos - marker[i].timeline_pos
stretch_ratio[i] = timeline_length[i] / source_length[i]
```

**Svaki segment ima SVOJ stretch ratio** — Signalsmith (ili Élastique) procesira svaki segment nezavisno.

---

## FluxForge Ultimativni Dizajn

### Šta radimo bolje od svih:

1. **Hybrid transient detection** — kombiniram spectral flux (aubio-rs Rust bindovi) + energy-based + machine learning (candle za neural onset detection)
2. **Per-segment Signalsmith Stretch** — svaki segment koristi Signalsmith sa sopstvenim pitch/stretch parametrima
3. **Cross-track linked markers** — kao Reaper, ali sa automatskim snapping na MIDI note events
4. **Adaptive stretch quality** — CPU budget tracker automatski menja kvalitet po segmentu
5. **Real-time + offline render** — real-time za playback, r8brain za bounce/export

### Data Model

```rust
/// Warp marker — maps source position to timeline position
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct WarpMarker {
    /// Unique marker ID
    pub id: WarpMarkerId,
    /// Position in original source audio (samples at source sample rate)
    pub source_pos: f64,
    /// Position on timeline (seconds)
    pub timeline_pos: f64,
    /// Marker type
    pub marker_type: WarpMarkerType,
    /// Locked — won't be moved by auto-quantize
    pub locked: bool,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub enum WarpMarkerType {
    /// Auto-detected transient
    Transient,
    /// User-placed marker
    Manual,
    /// Created by quantize operation
    Quantized,
    /// Clip start boundary (implicit, always at source_pos=0)
    ClipStart,
    /// Clip end boundary (implicit, always at end of source)
    ClipEnd,
}

/// Per-clip warp state
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ClipWarpState {
    /// Ordered list of warp markers (sorted by source_pos)
    pub markers: Vec<WarpMarker>,
    /// Detected transients (from analysis, not editable directly)
    pub transients: Vec<f64>,
    /// Original source tempo (BPM, if detected)
    pub source_tempo: Option<f64>,
    /// Warp enabled
    pub enabled: bool,
}
```

### Segmentiranje i Stretch

```rust
/// Compute per-segment stretch ratios from warp markers
fn compute_segment_ratios(markers: &[WarpMarker], source_sample_rate: f64) -> Vec<SegmentStretch> {
    let mut segments = Vec::new();
    for i in 0..markers.len() - 1 {
        let source_len = markers[i+1].source_pos - markers[i].source_pos;
        let timeline_len = markers[i+1].timeline_pos - markers[i].timeline_pos;
        let ratio = if source_len > 0.0 {
            (timeline_len * source_sample_rate) / source_len
        } else {
            1.0
        };
        segments.push(SegmentStretch {
            source_start: markers[i].source_pos,
            source_end: markers[i+1].source_pos,
            timeline_start: markers[i].timeline_pos,
            timeline_end: markers[i+1].timeline_pos,
            stretch_ratio: ratio,
        });
    }
    segments
}
```

### Audio Thread Processing

U `process_clip_with_crossfade`:
1. Za svaki output sample, nađi u kom segmentu se nalazi (binary search po timeline_pos)
2. Izračunaj source_pos za taj segment: `source = marker[i].source + (timeline - marker[i].timeline) * (source_len / timeline_len)`
3. Sinc interpoliraj na tom source_pos
4. Ako segment ima stretch_ratio != 1.0, Signalsmith Stretch procesira

### Transient Detection

Koristimo `aubio-rs` (Rust bindovi za aubio C library):
- Onset detection: spectral flux + adaptive threshold
- Beat tracking: auto-detect tempo
- Real-time capable (za live preview)
- Offline za full analysis

### Implementacioni plan

#### Faza 1: Data model + basic markers (engine)
- `WarpMarker` struct u `track_manager.rs`
- `ClipWarpState` per clip
- `compute_segment_ratios()` helper
- FFI: `clip_add_warp_marker`, `clip_remove_warp_marker`, `clip_move_warp_marker`
- Serialize/Deserialize za project save

#### Faza 2: Transient detection (engine)
- Dodaj `aubio-rs` dependency
- `TransientDetector` struct sa spectral flux onset detection
- FFI: `clip_detect_transients` (async, ne blokira audio thread)
- Rezultat: lista `f64` pozicija (source samples)
- Auto-create WarpMarkers na transientima

#### Faza 3: Per-segment stretch u playback
- Modifikuj `process_clip_with_crossfade` da koristi `ClipWarpState`
- Binary search za segment lookup (O(log N) per sample)
- Per-segment Signalsmith Stretch instanca
- Fallback na sinc-only ako nema markera

#### Faza 4: Flutter UI
- WarpMarker vizuelizacija u clip_widget.dart
- Drag-to-warp interaction
- Transient display (sive tačke)
- Quantize-to-grid button
- Warp on/off toggle per clip

#### Faza 5: Quantize
- Snap markere na grid (1/4, 1/8, 1/16, triplet, etc.)
- Strength parameter (0-100%) za parcijalni quantize
- Undo/redo podrška

---

## Reference

- [Cubase AudioWarp](https://www.soundonsound.com/techniques/audio-warp)
- [Reaper Stretch Markers](https://www.soundonsound.com/techniques/stretch-time)
- [Pro Tools Elastic Audio](https://www.boomboxpost.com/blog/2016/7/25/elasticaudio)
- [Ableton Warp Markers](https://www.ableton.com/en/manual/audio-clips-tempo-and-warping/)
- [Logic Pro Flex Time](https://support.apple.com/guide/logicpro/flex-time-and-pitch-overview-lgcp15968647/mac)
- [aubio-rs Rust bindings](https://github.com/katyo/aubio-rs)
- [microdsp onset detection](https://github.com/stuffmatic/microdsp)
- [audio-processor-analysis transient detection](https://docs.rs/audio-processor-analysis)
- [Spectral Flux onset detection paper](https://ismir2011.ismir.net/papers/PS2-6.pdf)
