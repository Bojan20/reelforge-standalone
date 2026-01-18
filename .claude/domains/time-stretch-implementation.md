# Time Stretch Implementation Guide

## Pregled DAW Implementacija

### Logic Pro Flex Time

Logic Pro koristi **5 algoritama** za time stretching:

| Algoritam | Tehnika | Materijal | CPU |
|-----------|---------|-----------|-----|
| **Polyphonic** | Phase Vocoder | Akordi, mix, hor | Najviši |
| **Monophonic** | TD-PSOLA | Lead synth, solo inst. | Srednji |
| **Rhythmic** | Slice + Loop | Bubnjevi, ritmika | Nizak |
| **Tempophone** | Granular | FX, kreativno | Srednji |
| **Speed** | Varispeed | Perkusije | Najniži |

**Ključne karakteristike:**
- Automatska transient detekcija pri prvom kliku
- Flex markeri na detektovanim transientima
- Ograničenje: ~10-15% promena tempa bez artefakata
- Značajni artefakti preko 50% promene

**Izvori:**
- [Flex Time algorithms - Apple Support](https://support.apple.com/guide/logicpro-ipad/flex-time-algorithms-and-parameters-lpipab631a74/ipados)
- [Logic Pro X Help](https://logicpro.skydocu.com/en/edit-the-timing-and-pitch-of-audio/edit-the-timing-of-audio/flex-time-algorithms-and-parameters/)

---

### Ableton Live Warp

Ableton koristi **granularnu sintezu** kao osnovu:

> "Live's Warp Modes use different granular synthesis techniques to manipulate time by repeating or omitting segments of the audio; these segments are referred to as grains."

| Mode | Opis | Koristi se za |
|------|------|---------------|
| **Beats** | Slice + Gap adjust | Bubnjevi, perkusije |
| **Tones** | Grain overlap | Monofonski instrumenti |
| **Texture** | Variable grain flux | Atmosfera, pad-ovi |
| **Re-Pitch** | Varispeed | DJ efekti |
| **Complex** | élastique | Polifonija, vokali |
| **Complex Pro** | élastique Pro | Full mix, mastering |

**Warp markeri:**
- Fiksiraju tačku u vremenu
- Između markera se primenjuje stretch
- Svaki region ima svoj stretch ratio

**Izvori:**
- [Ableton Reference Manual](https://www.ableton.com/en/manual/audio-clips-tempo-and-warping/)
- [Sound on Sound - Warping Revisited](https://www.soundonsound.com/techniques/ableton-live-warping-revisited)

---

### zplane élastique (Industrija Standard)

Koriste ga: **Cubase, Cakewalk, Studio One, Ableton (Complex modes)**

#### Verzije:

| Verzija | Namena | Kvalitet |
|---------|--------|----------|
| **Efficient** | Real-time, mobile | Dobar |
| **Pro** | Profesionalna produkcija | Najviši |
| **SOLOIST** | Monofonski materijal | Optimalan za glas |

#### Tehnička implementacija:

```
1. Transient Detection
   - Frekvencijska + vremenska detekcija
   - Visoka tačnost za perkusivne elemente

2. Phase Vocoder sa poboljšanjima:
   - Spectral peak tracking
   - Phase locking (vertikalna koherencija)
   - Transient preservation (ratio=1 tokom transijenata)

3. Formant Preservation:
   - Spectral envelope estimation
   - SetEnvelopeFactor() za nezavisnu kontrolu
   - Order: 8-512 (default 128)
```

**API funkcije:**
- `SetStretchFactor()` - time stretch ratio
- `SetPitchFactor()` - pitch shift
- `SetEnvelopeFactor()` - formant control
- `SetTransientMode()` - transient handling

**Izvori:**
- [élastique PRO SDK Documentation](https://www.licensing.zplane.de/uploads/SDK/ELASTIQUE-PRO/V3/manual/elastique_pro_v3_sdk_documentation.pdf)
- [zplane Technology](https://licensing.zplane.de/technology)

---

## Algoritmi za Time Stretch

### 1. OLA (Overlap-Add)
Najjednostavniji. Kopira segmente sa fiksnih pozicija.
- **Problem:** Ne prilagođava se signalu, može imati glitch-eve

### 2. WSOLA (Waveform-Similarity Overlap-Add)
Poboljšani OLA sa cross-correlation pretragom.
```
Za svaki grain:
  1. Odredi idealnu poziciju (η interval)
  2. Pretraži ±Δ uzoraka za maksimalnu sličnost
  3. Izaberi poziciju sa najboljom korelacijom
  4. Overlap-add sa prethodnim grain-om
```
- **Prednost:** Real-time, mali CPU
- **Mana:** Može "razmazati" transjiente

**Izvor:** [WSOLA Presentation - Umu.se](https://hpac.cs.umu.se/teaching/sem-mus-16/presentations/Schmakeit.pdf)

### 3. Phase Vocoder
Frekvencijski domen pristup:
```
1. STFT analiza (window + FFT)
2. Magnitude preservation
3. Phase accumulation (instantaneous frequency)
4. ISTFT sinteza
```
- **Problem:** "Phasiness" artefakt, transient smearing
- **Rešenje:** Phase locking, transient detection

**Izvor:** [Phase Vocoder Done Right - arXiv](https://arxiv.org/pdf/2202.07382)

### 4. TD-PSOLA (Time-Domain Pitch-Synchronous)
Za monofonski materijal:
```
1. Pitch detection (fundamental)
2. Mark pitch periods
3. Overlap-add pitch periods
4. Adjust overlap za time stretch
```
- **Najbolje za:** Glas, solo instrumenti
- **Zahteva:** Pouzdanu pitch detekciju

### 5. Granular Synthesis
```
Grain size: 1-100ms (tipično 20-50ms)
Density: 100-1000+ grains/sec
Envelope: Hanning, Gaussian

Za time stretch:
- rate < 1.0: Preskoči grain-ove
- rate > 1.0: Ponovi grain-ove
```

**Izvor:** [Granular Synthesis - Wikipedia](https://en.wikipedia.org/wiki/Granular_synthesis)

---

## FluxForge Studio Implementacija

### Trenutno Stanje

```rust
// playback.rs linija 2800
ClipFxType::TimeStretch { ratio: _ } => {
    // Time stretch is typically offline - pass through
    (sample_l, sample_r)
}
```

**PROBLEM:** Time stretch ne radi u real-time! Samo prolazi audio.

### Potrebna Arhitektura

```
┌─────────────────────────────────────────────────────────────┐
│                     CLIP PROCESSING                          │
├─────────────────────────────────────────────────────────────┤
│  1. Read from cache (original samples)                       │
│  2. Apply time stretch (WSOLA/Phase Vocoder)                 │
│  3. Apply pitch shift                                        │
│  4. Apply clip FX chain                                      │
│  5. Mix to track buffer                                      │
└─────────────────────────────────────────────────────────────┘
```

### Implementacija - Dva Pristupa

#### A) Real-Time (za playback)
```rust
// Za svaki clip sa time stretch:
1. Koristi WSOLA za real-time processing
2. Grain size: 20-50ms
3. Search window: ±10ms
4. Cross-correlation za similarity

// Buffer management:
- Pre-buffer stretched audio ahead of playhead
- Ring buffer za smooth playback
- Handle ratio changes gracefully
```

#### B) Offline Render (za bounce/export)
```rust
// Full quality processing:
1. Phase vocoder sa transient preservation
2. Ili STN decomposition (Sines + Transients + Noise)
3. Process each component separately
4. Recombine for final output
```

### Integracija sa ELASTIC_PROCESSORS

```rust
// U process_clip_with_crossfade():
fn process_clip_samples(&mut self, clip: &Clip, audio: &AudioData) {
    // Check if clip has time stretch
    if let Some(ratio) = clip.time_stretch_ratio {
        // Get or create elastic processor
        let proc = self.get_elastic_processor(clip.id);

        // Process through time stretch
        let stretched = proc.process_block(audio_block);

        // Continue with stretched audio
        self.apply_clip_fx(clip, &stretched);
    }
}
```

### Warp Marker System

```rust
pub struct WarpMarker {
    /// Original position in source audio
    pub source_time: f64,

    /// Warped position in timeline
    pub timeline_time: f64,

    /// Is this an anchor (locked) marker
    pub locked: bool,
}

pub struct WarpedClip {
    pub markers: Vec<WarpMarker>,

    /// Get stretch ratio at given timeline position
    pub fn ratio_at(&self, time: f64) -> f64 {
        // Find surrounding markers
        // Interpolate ratio between them
    }
}
```

---

## Preporučena Implementacija za FluxForge Studio

### Faza 1: Basic WSOLA Real-Time
1. Implementirati WSOLA u `rf-dsp/src/timestretch/wsola.rs` ✓ (već postoji)
2. Integrisati u playback.rs
3. Buffer management za smooth playback

### Faza 2: Transient Preservation
1. Transient detection na clip load
2. Force ratio=1.0 na transientima
3. Smooth transition oko transijenata

### Faza 3: Warp Markers UI
1. Timeline overlay sa markerima
2. Drag to adjust timing
3. Per-region stretch ratios

### Faza 4: High-Quality Offline
1. Phase vocoder + phase locking
2. STN decomposition
3. Spectral processing

---

## Reference

1. [PyTSMod - Python TSM Library](https://github.com/KAIST-MACLab/PyTSMod)
2. [TSM Toolbox - AudioLabs](https://www.audiolabs-erlangen.de/resources/MIR/TSMtoolbox)
3. [Driedger TSM Master Thesis](https://audiolabs-erlangen.de/content/05_fau/professor/00_mueller/01_group/2011_DriedgerJonathan_TSM_MasterThesis.pdf)
4. [Top DAWs Time-Stretch 2025](https://www.widebluesound.com/blog/top-daws-and-their-time‑stretch-algorithms-2025/)
5. [Transient Detection in Phase Vocoder](https://quod.lib.umich.edu/i/icmc/bbp2372.2003.074?rgn=main;view=fulltext)
