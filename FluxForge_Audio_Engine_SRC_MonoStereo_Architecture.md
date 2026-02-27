# FluxForge Studio — Audio Engine: Sample Rate Conversion & Mono/Stereo Architecture

## Referentni dokument za implementaciju mixed sample rate sesija i unified mono/stereo track modela

**Verzija:** 1.0
**Datum:** 2026-02-27
**Referenca:** REAPER DAW (Cockos) — industry standard za flexible audio engine

---

## SADRŽAJ

1. [REAPER Referenca — Kako to radi](#1-reaper-referenca)
2. [FluxForge Trenutno Stanje — Šta imamo](#2-fluxforge-trenutno-stanje)
3. [GAP Analiza — Šta fali](#3-gap-analiza)
4. [Implementacioni Plan](#4-implementacioni-plan)
5. [Rizici i Degradacija](#5-rizici-i-degradacija)

---

## 1. REAPER Referenca

### 1.1 Mixed Sample Rates — Kompletni Pipeline

REAPER **nikada ne menja originalne fajlove na disku**. Svaki audio fajl ostaje na svom native sample rate-u (44.1kHz, 48kHz, 96kHz...). Projekat ima jedan **project sample rate** na kome radi ceo mix engine.

#### Signal Flow (tačan redosled):

```
1. Media Source Read (fajl na NATIVE sample rate)
2. ★ SAMPLE RATE CONVERSION → project rate ★  ← Pre svega!
3. Take Channel Mode (mono L, mono R, reverse stereo...)
4. Take FX chain (item-level FX)
5. Take Volume envelope
6. Item Volume / Fades / Crossfades
7. Track sum (items na istom tracku)
8. Track FX chain
9. Track Volume / Pan / Width
10. Sends → Buses → Master → Output
```

**Ključno:** SRC se dešava na koraku 2 — posle čitanja fajla, PRE svih FX-ova. Od tog trenutka sav processing radi na project rate-u.

#### Dva odvojena SRC moda:

| Mod | Algoritam | Kvalitet | CPU | Upotreba |
|-----|-----------|----------|-----|----------|
| **Playback** | 64pt Sinc (default) | -96dB noise floor | Nizak | Real-time monitoring |
| **Render** | r8brain-free-src | Highest quality | Srednji | Offline bounce/export |

#### SRC Algoritmi (REAPER nudi sve):

| Algoritam | Tapova | Noise Floor | Latency | Upotreba |
|-----------|--------|-------------|---------|----------|
| Point Sampling | 1 | -20 dB | 0 | Lo-fi efekti |
| Linear Interpolation | 2 | -45 dB | ~1 sample | Draft |
| 16pt Sinc | 16 | -45 dB | ~8 samples | Quick preview |
| **64pt Sinc** | **64** | **-96 dB** | **~38 samples** | **Default playback** |
| 192pt Sinc | 192 | -84 dB | ~96 samples | HQ playback |
| 384pt Sinc | 384 | -80 dB | ~192 samples | Quality render |
| 512pt Sinc | 512 | -85 dB | ~256 samples | HQ render |
| 768pt Sinc | 768 | -85 dB | ~384 samples | Mastering |
| **r8brain-free-src** | Adaptive | Best overall | Adaptive | **Recommended render** |

#### r8brain-free-src Arhitektura (Voxengo):

Dvostepeni pristup:
1. **Power-of-2 halfband filter** za oversampling (efikasan za celobrojne odnose)
2. **Kratki polinom-interpolirani sinc fractional delay filteri** (8-30 tapova)

Specifikacije:
- Kaiser power-raised window (Beta=9.5945, Power=1.97)
- Stopband attenuation: 49 do 218 dB (konfiguriše se)
- Latency automatski kompenzovana
- Power-of-2 ratios (2x, 4x, 8x) koriste **dedicated fast paths**

#### Promena project rate-a mid-session:

- Items se **NE re-renderuju** — ostaju reference na original
- Playback odmah koristi novi rate (SRC se prilagodi)
- Peak fajlovi se **NE regenerišu** (peaks su iz originala)
- Item pozicije ostaju tačne (čuvaju se u **sekundama**, ne sample counts)

---

### 1.2 Mono/Stereo — Unified Track Model

#### Fundamentalna odluka: NEMA mono/stereo track tipova

| Osobina | Pro Tools | REAPER | FluxForge (cilj) |
|---------|-----------|--------|-------------------|
| Track tipovi | Fixed: Mono, Stereo | Unified: svi 2+ ch | Unified: svi 2 ch min |
| Default kanali | Odlučuje se pri kreiranju | 2 (stereo), menjivo | 2 (stereo), menjivo |
| Max kanali/track | Format-dependent | 128 | 2 (stereo) za sad |
| Promena channel count | Nov track potreban | Bilo kad | Bilo kad (cilj) |
| Mono fajl na stereo track | Ne može (treba mono track) | Auto L=R duplikacija | Auto L=R duplikacija |

#### Mono fajl na tracku — šta se dešava:

1. **Source read**: Fajl isporuči 1 kanal podataka
2. **Duplikacija**: Ch1 → Ch1 + Ch2 (identični L=R)
3. **Sav processing**: Plugini vide stereo (2 kanala, identičan sadržaj)
4. **Plugini NE MOGU detektovati** da je source bio mono

#### Take Channel Modes (per-take property):

| Mode | Ponašanje |
|------|-----------|
| Normal | Kao u fajlu |
| Reverse Stereo | L↔R swap |
| Mono (Downmix) | L+R sum (-6dB) |
| Mono (Left) | Samo L kanal |
| Mono (Right) | Samo R kanal |
| Mono (L-R) | Difference (side signal za M/S) |

#### Pan Law za mono source:

- Default: "Stereo Balance / Mono Pan"
- Mono: pravi pan pot (redistribuira signal L↔R)
- Stereo: balance control (atenuira jednu stranu)
- Width=0 → forsiraj mono; Width nema efekta na već-mono materijal

---

### 1.3 Waveform Display — .reapeaks Arhitektura

#### Format specifikacija:

**Header (14+ bajtova):**
```
Bajt 0-3:   Magic header (RPKM v1.0 | RPKN v1.1 | RPKL v1.2+)
Bajt 4:     Broj kanala SOURCE fajla (1=mono, 2=stereo)
Bajt 5:     Broj mipmap nivoa (max 16)
Bajt 6-9:   Sample rate SOURCE fajla (NE project rate!)
Bajt 10-13: File modification timestamp
Bajt 14-17: File size
```

**Mipmap LOD nivoi:**
```
Level 1: ~400 peaks/sec (divfactor ~110 @44.1kHz) → Close zoom
Level 2: ~10 peaks/sec  (divfactor ~4410 @44.1kHz) → Medium zoom
Level 3: ~1 peak/sec    (divfactor ~44100 @44.1kHz) → Full overview
+ Spectral, Spectrogram, Loudness nivoi (opcionalno)
```

**Peak data**: min/max parovi po kanalu, 16-bit signed int.

#### Ključne odluke za display:

| Pitanje | Odgovor |
|---------|---------|
| Peaks iz originalnog ili resampleiranog fajla? | **Originalnog** — na native rate-u |
| SRC za display? | **NE** — čist time→pixel mapping |
| Promena project rate regeneriše peaks? | **NE** — peaks su validni uvek |
| Extreme zoom (sample level)? | Čita direktno iz source fajla |
| Mono fajl display? | **Jedan waveform centriran** (nema L/R podele) |
| Stereo fajl display? | **Dva waveforma** (L gore, R dole) na dovoljnoj visini |
| Track height utiče? | Da — mali height može prikazati stereo kao jedan waveform |

#### Cache invalidacija:
- Regeneracija SAMO ako se source fajl **promeni** (timestamp/size mismatch)
- Brisanje peak fajlova je safe — auto-regeneracija

---

## 2. FluxForge Trenutno Stanje

### 2.1 Sample Rate Handling — Šta IMAMO

#### ✅ Čitanje native sample rate iz fajla

**Fajl:** `crates/rf-engine/src/audio_import.rs`
```rust
// Linija 330-331
let sample_rate = codec_params.sample_rate.unwrap_or(48000);
let channels = codec_params.channels.map(|c| c.count()).unwrap_or(2) as u8;
```

Symphonia dekoder pravilno čita sample rate iz svih formata (WAV, MP3, FLAC, OGG, AAC, ALAC, AIFF).

#### ✅ Sample rate čuvan u ImportedAudio

**Fajl:** `crates/rf-engine/src/audio_import.rs`
```rust
// Linija 55-68
pub struct ImportedAudio {
    pub samples: Vec<f32>,      // Interleaved [L0,R0,L1,R1,...]
    pub sample_rate: u32,       // Source native rate
    pub channels: u8,           // 1=mono, 2=stereo
    pub duration_secs: f64,
    pub sample_count: usize,    // Per-channel
}
```

#### ✅ Rate ratio u playback engine-u

**Fajl:** `crates/rf-engine/src/playback.rs`
```rust
// Linija 5258-5275
let source_sample_rate = audio.sample_rate as f64;
let rate_ratio = source_sample_rate / sample_rate;  // e.g., 44100/48000 = 0.9188
let source_pos_f64 = clip_offset as f64 * rate_ratio * playback_rate + source_offset_samples;
```

Ovo je **linearna interpolacija** između source samplea — funkcioniše, ali nije highest quality.

#### ✅ SampleRateConverter postoji (ali se NE KORISTI u playbacku!)

**Fajl:** `crates/rf-engine/src/audio_import.rs`, linije 622-741
- `convert_linear()` — Linearna interpolacija (brza, niži kvalitet)
- `convert_sinc()` — **Lanczos-3 kernel** (6-tap sinc, profesionalni kvalitet)
- Obe funkcije su implementirane, testirane, ali **ne pozivaju se** tokom playbacka

#### ✅ Waveform generisan iz originalnog fajla na native rate-u

**Fajl:** `crates/rf-engine/src/ffi.rs`, linije 1411-1417
```rust
if imported.channels == 1 {
    StereoWaveformPeaks::from_mono(&imported.samples, imported.sample_rate)
} else {
    StereoWaveformPeaks::from_interleaved(&imported.samples, imported.sample_rate)
}
```

Peak-ovi se generišu iz originala — ISTO kao REAPER.

---

### 2.2 Mono/Stereo Handling — Šta IMAMO

#### ✅ Mono fajlovi se pravilno reprodukuju (mono→stereo duplikacija)

**Fajl:** `crates/rf-engine/src/playback.rs`, linije 1204-1208
```rust
let s0_l = self.audio.samples[src_frame * channels_src];
let s0_r = if channels_src > 1 {
    self.audio.samples[src_frame * channels_src + 1]
} else {
    s0_l  // Mono: koristi levi za oba kanala
};
```

#### ✅ Stereo waveform generisan per-channel

**Fajl:** `crates/rf-engine/src/waveform.rs`, linije 313-361
```rust
pub fn from_interleaved(samples: &[f32], sample_rate: u32) -> Self {
    // Deinterleave L/R → zasebni WaveformData
    Self { left: WaveformData::from_samples(&left, sr), right: ... }
}

pub fn from_mono(samples: &[f32], sample_rate: u32) -> Self {
    let data = WaveformData::from_samples(samples, sr);
    Self { left: data.clone(), right: data }  // Identični L=R
}
```

#### ✅ 11-level LOD mipmap sistem

**Fajl:** `crates/rf-engine/src/waveform.rs`, linije 28-38
```
Level 0:  4 samples/bucket   → Ultra-fine zoom (transient detail)
Level 1:  8 samples/bucket
Level 2:  16 samples/bucket
Level 3:  32 samples/bucket
Level 4:  64 samples/bucket   → Standard zoom
Level 5:  128 samples/bucket
Level 6:  256 samples/bucket
Level 7:  512 samples/bucket
Level 8:  1024 samples/bucket  → Overview
Level 9:  2048 samples/bucket
Level 10: 4096 samples/bucket  → Full project overview
```

#### ✅ Pixel-exact waveform query

**Fajl:** `crates/rf-engine/src/waveform.rs`, linije 226-268
- Bira najfiniji LOD gde `bucket_samples ≤ frames_per_pixel`
- Sprečava gubitak peak-ova (nikad ne koristi grublji LOD nego što pixel zahteva)
- WaveformBucket čuva: `min`, `max`, `rms` po bucketu

#### ✅ Waveform cache u memoriji

**Fajl:** `crates/rf-engine/src/waveform.rs`, linije 481-576
- `HashMap<String, Arc<StereoWaveformData>>`
- Per-clip keš sa lazy computation

---

### 2.3 Šta RADI ali MOŽE BOLJE

| Aspekt | Trenutno | Cilj (REAPER nivo) |
|--------|----------|---------------------|
| Playback SRC | Linearna interpolacija (rate_ratio) | Sinc interpolacija (Lanczos ili 64pt+) |
| SRC kvalitet opcije | Nema — jedan fixed metod | Playback vs Render mod |
| Waveform za stretch | Originalni peaks | Post-stretch peaks (vizuelna tačnost) |
| Mono waveform display | L=R duplikat (2 ista waveforma) | 1 centriran waveform za mono |

---

## 3. GAP Analiza

### 3.1 Šta FALI (poređenje sa REAPER)

| # | Gap | Opis | Prioritet |
|---|-----|------|-----------|
| G1 | **Playback SRC kvalitet** | Linearna interpolacija umesto sinc. Za bliske rate-ove (44.1↔48k) jedva čujno, ali za extreme (8kHz→96kHz) degradira kvalitet | P1 |
| G2 | **Nekonzistentni fallback** | `rf-engine` koristi 48000, `rf-file` i `rf-offline` koriste 44100 | P0 |
| G3 | **Mono waveform display** | Flutter UI prikazuje 2 identična waveforma za mono; treba 1 centriran | P1 |
| G4 | **SRC quality opcije** | Nema korisničkog izbora kvaliteta SRC | P2 |
| G5 | **Project sample rate** | Nema eksplicitnog "project sample rate" koncepta u UI | P2 |

### 3.2 Šta NEMAMO ALI NE TREBA (za sada)

| Aspekt | REAPER ima | FluxForge ne treba (još) | Razlog |
|--------|-----------|---------------------------|--------|
| 128 kanala po tracku | Da | Ne | Overkill za audio produkciju |
| Per-FX oversampling | Da (16x) | Ne | Naši plugini su interni |
| r8brain-free-src | Da | Ne (Lanczos-3 dovoljno) | Lanczos-3 je -90dB+, profesionalni kvalitet |
| .reapeaks disk format | Da | Ne (in-memory cache) | Naš LOD sistem radi u memoriji |
| Take Channel Mode UI | 7 modova | Ne (za sada) | Mono/Stereo je automatski |

---

## 4. Implementacioni Plan

### Faza 1: Zero-Risk Fixes (P0) — Nema degradacije

#### F1.1: Konzistentni sample rate fallback
**Fajlovi:** `rf-file/audio_file.rs`, `rf-offline/decoder.rs`
**Promena:** Svi `unwrap_or(44100)` → `unwrap_or(48000)`
**Rizik:** NULA — ovo je samo fallback za fajlove bez metapodataka

#### F1.2: Mono waveform display u Flutter UI
**Fajl:** `flutter_ui/lib/widgets/waveform/ultimate_waveform.dart`
**Promena:** Ako `isStereo == false`, prikaži 1 centriran waveform umesto 2
**Rizik:** NULA — čisto vizuelna promena, ne utiče na audio

### Faza 2: Kvalitetno Unapređenje (P1) — Strogo backward-compatible

#### F2.1: Sinc SRC u playback Voice
**Fajl:** `crates/rf-engine/src/playback.rs`
**Promena:** Zameni linearnu interpolaciju sa Lanczos-3 kernel interpolacijom za `rate_ratio != 1.0`
**Strategija:**
1. Ako `source_sample_rate == engine_sample_rate` → SKIP (fast path, nema promene)
2. Ako ratio blizu 1.0 (±5%) → linearna interpolacija (nečujna razlika)
3. Inače → Lanczos-3 (6-tap sinc)
**Rizik:** NIZAK — fast path za identične rate-ove čuva performanse

### Faza 3: UI Features (P2)

#### F3.1: Project Sample Rate u Settings
**UI:** Project Settings dijalog
**Opcije:** 44100, 48000, 88200, 96000, 176400, 192000
**Default:** 48000

#### F3.2: SRC Quality opcije
**UI:** Project Settings dijalog
**Opcije:**
- Playback: Linear | Sinc-16 | **Sinc-64** (default) | Sinc-192
- Render: Sinc-64 | Sinc-192 | **Sinc-384** (default) | Sinc-768

---

## 5. Rizici i Degradacija — Šta NE SME da se pokvari

### 5.1 Trenutni kvalitet koji MORAMO sačuvati

| Aspekt | Trenutni status | Zaštita |
|--------|----------------|---------|
| ✅ Mono playback (L=R duplikacija) | Radi perfektno | NE DIRAJ playback.rs:1204-1208 |
| ✅ Stereo playback | Radi perfektno | NE DIRAJ interleaving logiku |
| ✅ 11-level LOD waveform | Profesionalni kvalitet | NE DIRAJ waveform.rs bucket sistem |
| ✅ Pixel-exact peak query | Sprečava gubitak peak-ova | NE DIRAJ query_pixels algoritam |
| ✅ Native rate peak generation | Peaks iz originala | NE DIRAJ ffi.rs:1411-1417 |
| ✅ Symphonia codec support | WAV/MP3/FLAC/OGG/AAC/ALAC/AIFF | NE DIRAJ decoder pipeline |
| ✅ Zero-allocation audio thread | Real-time safe | NE DODAJ alokacije u process() |
| ✅ Rate ratio playback | Funkcionalan za sve rate-ove | ZAMENI samo interpolaciju, ne logiku |

### 5.2 Potencijalne degradacije i kako ih izbeći

| Potencijalna degradacija | Uzrok | Prevencija |
|--------------------------|-------|------------|
| CPU spike pri playbacku | Sinc SRC je skuplji | Fast path za identične rate-ove |
| Audio glitch pri rate promeni | SRC buffer reset | Graceful crossfade pri promeni |
| Waveform neslaganje | Peaks iz originala vs resampled audio | NE menjaj peak generaciju |
| Memory blowup | Pre-computed SRC za sve klipove | NIKAD pre-compute; uvek real-time |
| Latency | Sinc filter delay | PDC kompenzacija (već imamo) |

### 5.3 Testiranje pre puštanja

```
1. Import 44.1kHz stereo WAV → playback na 48kHz → zvuk mora biti čist
2. Import 96kHz stereo WAV → playback na 48kHz → zvuk mora biti čist
3. Import 44.1kHz MONO WAV → playback na 48kHz → L=R, čist zvuk
4. Import 8kHz mono WAV → playback na 48kHz → čist zvuk (extreme case)
5. Import mix: 44.1kHz + 48kHz + 96kHz u istu sesiju → svi moraju svirati
6. Waveform display za mono → 1 centriran waveform
7. Waveform display za stereo → 2 waveforma (L/R)
8. flutter analyze = 0 errors
9. cargo test = 100% pass
10. CPU usage: ne sme da poraste >5% za identične rate fajlove
```

---

## Appendix A: Fajl Reference Mapa

```
AUDIO IMPORT:
  crates/rf-engine/src/audio_import.rs
    L55-84:   ImportedAudio struct (samples, sample_rate, channels)
    L267-296: AudioImporter::import() entry point
    L299-403: Symphonia decode pipeline
    L406-546: Sample format conversion (11 buffer types)
    L622-671: SampleRateConverter::convert_linear()
    L675-724: SampleRateConverter::convert_sinc() [Lanczos-3]
    L727-740: Lanczos kernel implementation

PLAYBACK:
  crates/rf-engine/src/playback.rs
    L1099-1232: Voice struct — clip rendering
    L1204-1208: Mono→stereo duplikacija
    L3958:      Main process() — stereo output
    L5257-5275: Rate ratio calculation & sample position

TRACK MANAGER:
  crates/rf-engine/src/track_manager.rs
    L422-423:  Take source_offset, source_duration
    L769-770:  Clip start_time, duration
    L869-872:  effective_playback_rate()

WAVEFORM:
  crates/rf-engine/src/waveform.rs
    L28-38:    11 LOD levels (4 to 4096 samples/bucket)
    L44-118:   WaveformBucket (min, max, rms)
    L140-153:  WaveformData struct
    L226-268:  query_pixels() — pixel-exact LOD selection
    L313-361:  StereoWaveformData (from_interleaved, from_mono)
    L481-576:  WaveformCache (HashMap + lazy compute)

FFI:
  crates/rf-engine/src/ffi.rs
    L777-787:  Track channel get/set
    L1293-1425: engine_import_audio (import + waveform gen)
    L1926-2216: Waveform query FFI
    L2751-2752: Engine sample rate query

FLUTTER UI:
  flutter_ui/lib/widgets/waveform/ultimate_waveform.dart
    L62-83:    UltimateWaveformData struct
    L94-136:   fromSamples() factory
    L179-199:  Downsampling (min/max preservation)

  flutter_ui/lib/services/waveform_cache_service.dart
    L37:       Max 100 waveforms in-memory
    L41:       Max 2048 samples per cached waveform
    L47-51:    Disk quota 2GB max

OTHER CRATES:
  crates/rf-file/src/audio_file.rs
    L443, L642: unwrap_or(44100) ← NEKONZISTENTNO
  crates/rf-offline/src/decoder.rs
    L66, L264:  unwrap_or(44100) ← NEKONZISTENTNO
```

---

## Appendix B: Ukratko — REAPER vs FluxForge

| Aspekt | REAPER | FluxForge (sada) | FluxForge (cilj) |
|--------|--------|-------------------|-------------------|
| Mixed SR u sesiji | ✅ Potpuno | ✅ Radi (linearna interp) | ✅ Sinc interp (P1) |
| SRC pre FX-ova | ✅ | ✅ (u Voice) | ✅ (ne menjamo) |
| Original fajl nepromenjen | ✅ | ✅ | ✅ |
| Peaks iz originala | ✅ | ✅ | ✅ |
| Mono→Stereo auto | ✅ | ✅ | ✅ |
| Unified track model | ✅ (2-128 ch) | ✅ (2 ch) | ✅ (2 ch) |
| SRC quality opcije | ✅ (10+ nivoa) | ❌ | ✅ P2 |
| Project SR setting | ✅ | ❌ (hardcoded 48k) | ✅ P2 |
| Mono waveform display | ✅ (1 centriran) | ❌ (2 identična) | ✅ P1 |
| Fallback konzistentnost | ✅ | ❌ (48k vs 44.1k) | ✅ P0 |
| 11-level LOD peaks | N/A (3 nivoa) | ✅ (11 nivoa!) | ✅ (bolje od REAPER-a!) |
| Per-channel peaks | ✅ | ✅ | ✅ |
| Pixel-exact query | ✅ | ✅ | ✅ |

**Zaključak:** FluxForge audio engine je **90% na nivou REAPER-a**. Potrebne su 3 male intervencije (P0: fallback fix, P1: sinc SRC + mono display) da dostignemo potpunu parnost. Naš 11-level LOD sistem je **superiorniji** od REAPER-ovog 3-level pristupa.
