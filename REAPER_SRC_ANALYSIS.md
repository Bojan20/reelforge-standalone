# Real-Time Resampling — Reaper Architecture Analysis

## 1. WDL Resampler (Cockos open-source core)

Source: `github.com/justinfrankel/WDL` → `resample.cpp`

### API

- `SetMode(interp, filtercnt, sinc, sinc_size, sinc_interpsize)` — konfiguriše algoritam
- `SetRates(rate_in, rate_out)` — setuje ratio
- `SetFeedMode(input_driven)` — input-driven (real-time) ili output-driven (offline)
- `ResamplePrepare(nsamples, nch, &inbuffer)` — alocira interni buffer
- `ResampleOut(out, nsamples_in, nsamples_out, nch)` — proizvodi output

### Sinc filter

- **Blackman-Harris 4-term window**: `0.35875 - 0.48829*cos(w) + 0.14128*cos(2w) - 0.01168*cos(3w)`
- Pre-computed sinc tabela indeksirana po frakcionoj poziciji
- Template-specijalizovane funkcije: `SincSample` (N-ch), `SincSample1` (mono), `SincSample2` (stereo)
- Cutoff frekvencija = `output_rate / input_rate` (automatski anti-aliasing pri downsample-u)
- **Latency**: `sinc_size / 2` samples (64pt = 32 samples = ~0.7ms @ 44.1kHz)

## 2. Reaper Quality Modes

| Mode | Tehnika | CPU | Upotreba |
|------|---------|-----|----------|
| Point Sampling | Nearest-neighbor | Najniži | Lo-fi efekat |
| Linear | Lerp | Vrlo nizak | Brz preview |
| Fast (IIR + Linear) | IIR lowpass + lerp | Nizak | Quick preview |
| Fast (16pt Sinc) | 16pt windowed sinc | Nizak-Sred | Brz sa OK kvalitetom |
| **Medium (64pt Sinc)** | 64pt windowed sinc | **Srednji** | **Default playback** |
| Good (192pt Sinc) | 192pt sinc | Visok | Render kvalitet |
| Better (384pt Sinc) | 384pt sinc | Viši | High-quality render |
| HQ (512pt Sinc) | 512pt sinc | Visok | Near-reference |
| Extreme HQ (768pt Sinc) | 768pt sinc | Najviši sinc | Reference |
| **r8brain free** | Voxengo r8brain | Efikasan za kvalitet | **Najviši ukupni kvalitet** |

**Dva nezavisna podešavanja:**
- Playback Resample Mode — real-time (tipično 64pt)
- Render Resample Mode — offline bounce (tipično 384pt+ ili r8brain)

## 3. r8brain-free-src (premium opcija)

- 2x oversampled signal → banka kratkih (8-30 tap) polynomial-interpolated sinc delay filtera
- Minimum-phase transform via discrete Hilbert transform u cepstrum domenu
- Header-only C++ biblioteka — moguće portovati u Rust ili wrappovati via FFI
- Ocenjen kao viši kvalitet od 768pt sinc uz manje CPU

## 4. Per-Item Properties

Svaki media item u Reaper-u ima nezavisne parametre:

| Property | Tip | Opis |
|----------|-----|------|
| Playback Rate | f64 (1.0 = normalno) | Speed — bez preserve pitch = tape varispeed |
| Pitch Shift | semitones + cents | Nezavisan od rate-a |
| Preserve Pitch | bool | ON = time-stretch algoritam drži pitch; OFF = varispeed |
| Stretch Algorithm | enum | Elastique Pro/Efficient/Soloist, SoundTouch, Simple Windowed |
| Reverse | bool | Reverse playback |

**Processing lanac per-item:**
```
Source audio (originalni SR)
  → SRC (ako source SR ≠ project SR) — playback resample mode
    → Rate change (varispeed ILI time-stretch ako preserve pitch)
      → Pitch shift (ako je pitch ≠ 0)
        → Output (project SR) → mixer
```

## 5. Time-Stretch Algorithms

| Algoritam | Tip | Za šta | Licenca |
|-----------|-----|--------|---------|
| **Elastique Pro** | Phase vocoder | Polifonski materijal | Proprietary (zplane) |
| **Elastique Efficient** | Phase vocoder (lite) | Niži CPU | Proprietary |
| **Elastique Soloist** | Phase vocoder (mono) | Vokali | Proprietary |
| **SoundTouch** | WSOLA | General purpose | Open-source (LGPL) |
| **Simple Windowed** | OLA | Osnovno | Nizak CPU |
| **Rrreeeaaa** | Granular/spectral | Kreativno/lo-fi | Cockos |

## 6. Master Playback Rate (varispeed)

- Globalni speed slider: pitch i speed su kuplovani (kao traka)
- Automatable playrate envelope na master track-u
- "Preserve pitch" opcija za tempo promenu bez pitch promene
- Koristi project Playback Resample Mode

## 7. Latency Compensation (PDC)

- Automatski PDC: Reaper meri i kompenzuje plugin latency
- Per-FX latency vidljiv u FX Chain prozoru
- SRC latency: `sinc_size / 2` samples — uključeno u PDC
- ReaInsert: hardware insert round-trip kompenzacija

## 8. Xrun Handling

- Transport area flashuje na underrun
- Project Underrun Monitor — ReaScript markeri na dropout lokacijama
- Recovery: tihi output tokom xrun-a, nastavlja normalno
- Anticipative FX processing: pre-renderuje FX kad je moguće

## 9. Offline vs Real-Time Render

- Playback: niži kvalitet resample-a (CPU saving)
- Render: viši kvalitet (nema real-time ograničenja)
- Full-speed offline: renderuje maksimalnom brzinom
- Render kvalitet NE utiče na file size — samo na vreme renderovanja

## 10. Arhitektura za FluxForge implementaciju

```rust
struct Resampler {
    mode: ResampleMode,          // Point/Linear/Sinc(N)/IIR+Linear
    sinc_table: Vec<f64>,        // Pre-computed Blackman-Harris windowed sinc
    sinc_size: usize,            // 16/64/192/384/512/768
    sinc_interp_size: usize,     // Sub-sample interpolation resolution (32 default)
    ring_buffer: Vec<f64>,       // Circular input buffer
    phase_accumulator: f64,      // Fractional position tracker
    ratio: f64,                  // out_rate / in_rate
    feed_mode: FeedMode,         // InputDriven (real-time) / OutputDriven (offline)
}

enum ResampleMode {
    Point,                       // Nearest-neighbor
    Linear,                      // Lerp
    IirLinear { filter_count: u8 }, // IIR lowpass + lerp
    Sinc { size: u16 },          // Windowed sinc (16/64/192/384/512/768)
}

enum FeedMode {
    InputDriven,                 // Push input → get output (real-time audio callback)
    OutputDriven,                // Request N output samples → pulls input (offline render)
}
```

**Ključne odluke po uzoru na WDL:**
1. Blackman-Harris 4-term window za sinc kernel
2. Pre-computed sinc tabela (ne računaj per-sample)
3. Input-driven za real-time, output-driven za render
4. Zero alokacija u audio path-u — svi bufferi pre-alocirani
5. Odvojeni playback vs render quality settings
6. Per-item resampler instance sa nezavisnim ratio-om
7. IIR filter opcija za brze modove

**Za time-stretch:**
- SoundTouch (WSOLA, open-source) kao baseline
- Elastique je proprietary — zahteva licenciranje od zplane
- Custom phase vocoder sa transient detection za bolji kvalitet

## 11. FluxForge — Prednosti nad Reaperom

### r8brain Rust port (highest quality mode)
- r8brain-free-src je MIT licenca, header-only C++ — portujemo u čist Rust
- Minimum-phase kernel via Hilbert transform → manje pre-ringing od linear sinc
- Bolji kvalitet od WDL 768pt sinc uz manje CPU-a
- Reaper ga koristi kao external opciju — mi ga imamo NATIVNO

### AVX-512 SIMD sinc inner loops
- Reaper WDL: ručni SSE2 template specijalizacije (2× f64 parallel)
- FluxForge: AVX-512 (8× f64 parallel) → 4× brži sinc od Reapera na istom sinc_size
- Auto-dispatch: AVX512 → AVX2 → SSE4.2 → scalar (postojeći rf-dsp pattern)
- Mono/stereo specijalizacije za cache-friendly access patterns

### Adaptive per-voice quality (Reaper NEMA ovo)
- Reaper: fiksiran quality mode za CEO projekat tokom playback-a
- FluxForge: CPU budget tracking per-voice
  - Solo/selected glasovi: UVEK highest quality (r8brain ili Sinc384)
  - Pozadinski glasovi: automatska degradacija Sinc384 → Sinc64 → Linear
  - Vraća se na viši kvalitet čim CPU dozvoli
  - Rezultat: 100+ glasova sa perceived highest quality jer korisnik čuje samo fokusirane

### Formant-preserving phase vocoder (Reaper zahteva Elastique licencu)
- Reaper: formant preservation samo sa Elastique Soloist (proprietary, ~$5K)
- FluxForge: custom phase vocoder sa:
  - Transient-preserving OLA (Driedger/Müller 2014)
  - Spectral peak locking — čistiji harmonici
  - Formant envelope extraction + reapplication — vokali zvuče prirodno pri pitch shift-u
  - Open-source, nula licence

### Zero-copy Rust memory model
- WDL C++: kopira input u interni buffer → procesira → kopira u output
- FluxForge Rust: ring buffer sa direct slice pristupom, nema kopiranja
- Ownership model garantuje thread safety bez runtime lock-ova
