# Pitch Shift & Time Stretch — Architecture Document

**Created:** 2026-03-21
**Status:** Research complete, ready for implementation

---

## Kako to rade veliki DAW-ovi

### Ranking po kvalitetu (2025 konsenzus)

| # | Algoritam | Koristi ga | Tip | Kvalitet | Real-time | Open source |
|---|-----------|-----------|-----|----------|-----------|-------------|
| 1 | **zplane Élastique Pro** | Cubase, Reaper, Bitwig, FL Studio, Cakewalk | Proprietary spectral | ★★★★★ | Da | Ne (skupa licenca) |
| 2 | **Signalsmith Stretch** | Indie DAW-ovi, plugins | Unified spectral mapping | ★★★★☆ | Da | **Da (MIT)** |
| 3 | **Rubber Band R3** | Audacity, Ardour, REAPER (opcija) | Phase vocoder + multi-band | ★★★★☆ | Da (ali CPU heavy) | Da (GPL) |
| 4 | **iZotope Radius** | Pro Tools (X-Form) | Spectral | ★★★★★ | Ne (offline) | Ne |
| 5 | **SoundTouch (TDHS)** | VLC, razni | Time-domain (WSOLA-like) | ★★☆☆☆ | Da (lagan) | Da |
| 6 | **Basic Phase Vocoder** | — | STFT phase manipulation | ★☆☆☆☆ | Da | — |

### Ableton Live
- Koristi **granular synthesis** (ne PV!) za većinu warp modova
- "Complex" i "Complex Pro" koriste proprietarni spectral algorithm
- Dizajniran za DJ/electronic — ne za generalni audio editing
- **NIJE najbolji** za kvalitet — Élastique i Signalsmith su bolji

### Cubase / Nuendo
- Koristi **zplane Élastique Pro** — gold standard industrije
- Tri varijante: Pro (best), Pro Formant (best + formanti), Efficient (lakši)
- Tape mode = čist varispeed (pitch + brzina zajedno)
- **Élastique je licencirani closed-source SDK — ne možemo ga koristiti**

### Pro Tools
- **Elastic Audio** = real-time, više algoritama (Polyphonic, Rhythmic, Monophonic, Varispeed)
- **X-Form** = offline, baziran na iZotope Radius — najbolji kvalitet
- Real-time algoritmi su OK ali ne fantastični

### Logic Pro
- **Flex Time** = time stretch (više algoritama)
- **Flex Pitch** = monophonic pitch editing (kao Melodyne)
- Proprietary, zatvoreni

---

## Ključni uvid: zašto naš Phase Vocoder zvuči loše

### Šta smo probali i zašto ne radi

1. **Phase-only PV** (originalni): menja faze u STFT ali NE pomera binove → pitch se NE MENJA
2. **Frequency bin resampling**: pomera binove → menja pitch ali UNIŠTAVA phase coherence → metallic artifacts, smearing, phasy zvuk

### Zašto PV generalno zvuči loše za pitch shift

- Phase vocoder "smears" transienti kroz STFT prozor
- Gubi phase coherence između binova → metallic/robotic sound
- Frequency aliasing kad se binovi pomeraju
- Timpanski karakter zvuka se menja (formanti se pomeraju uniformno)

### Šta radi Signalsmith Stretch drugačije

Signalsmith NE koristi klasični phase vocoder. Umesto toga:
1. Identifikuje **spektralne pikove** (harmonike)
2. Kreira **nelinearnu frekvencijsku mapu** koja je lokalno 1:1 oko jakih harmonika
3. Jaki harmonici se pomeraju čisto na ciljne frekvencije, okolni spektar ide s njima
4. Između pikova (manje energije, uho manje osetljivo) mapa apsorbuje kompresiju/ekspanziju
5. **Time i pitch mapping rade simultano** — ne dvostepeno (time stretch + resample)

Ovo eliminiše:
- Frequency aliasing (jer se pikovi mapiraju čisto)
- Metallic artifacts (jer se okolni spektar ne distorzuje)
- Compounding artifacts od dva koraka (jer je jedan prolaz)

---

## Preporuka za FluxForge Studio

### KORISTITI: Signalsmith Stretch

**Zašto:**
- **MIT licenca** — potpuno besplatno, nikakva ograničenja
- **Rust bindovi postoje**: `ssstretch` crate (cxx-based, safe Rust API)
- **Real-time capable** — 50-100% brži od phase vocodera
- **Kvalitet blizu Élastique Pro** — daleko bolji od basic PV
- **Simultani pitch + time** — nema compounding artifacts
- **Polyphonic** — radi za sve tipove audio-a (ne samo mono/voice)
- **Header-only C++** — lako za integraciju

**API je jednostavan:**
```rust
let mut stretch = Stretch::<2>::new(48000.0); // stereo, 48kHz
stretch.set_transpose_semitones(3.0, None);   // +3 semitones
stretch.process(&input, input_len, &mut output, output_len);
```

### NE KORISTITI:
- **Naš Phase Vocoder** — kvalitet je neprihvatljiv za produkcijski DAW
- **SoundTouch** — loš kvalitet, udvaja/preskače transienti
- **Rubber Band** — GPL licenca (virusna, nekompatibilna sa komercijalnim softverom)
- **zplane Élastique** — zatvoreni, skupa licenca

---

## Implementacioni plan

### Faza 1: Integracija ssstretch crate-a

1. Dodaj `ssstretch` u rf-engine Cargo.toml
2. Napravi `SignalsmithStretcher` wrapper u rf-engine sa:
   - Pre-alokacija na UI thread-u (zero alloc na audio thread)
   - Stereo (2-kanalni) instanca per clip
   - `set_transpose_semitones(st)` za pitch shift
   - `process(input, input_len, output, output_len)` za time stretch + pitch
3. Zameni `PhaseVocoder` u `process_clip_with_crossfade_pv` sa Signalsmith
4. `clip_vocoders: HashMap<u64, SignalsmithStretcher>` umesto PV parova

### Faza 2: Ukloni PhaseVocoder

1. `phase_vocoder.rs` → arhiviraj ili obriši
2. Ukloni PV scratch buffere, PV dijagnostiku
3. Signalsmith radi i pitch i time stretch u jednom prolazu — ne treba razdvajati

### Faza 3: UI semantika

**Warp tab** (time stretch):
- Ratio slider → `signalsmith.process(input, N, output, N * ratio)` sa pitch_shift=0
- Brzina se menja, pitch ostaje isti

**Elastic tab** (pitch shift):
- Pitch knob → `signalsmith.set_transpose_semitones(st)`
- `signalsmith.process(input, N, output, N)` — isti input/output length
- Pitch se menja, brzina ostaje ista

**Kombinovano** (stretch + pitch):
- Oba parametra simultano — Signalsmith to radi u jednom prolazu bez artefakata

---

## Reference

- [Signalsmith Stretch - Design blog](https://signalsmith-audio.co.uk/writing/2023/stretch-design/)
- [Signalsmith Stretch - Source (MIT)](https://github.com/Signalsmith-Audio/signalsmith-stretch)
- [ssstretch Rust crate](https://github.com/bmisiak/ssstretch)
- [signalsmith-stretch-rs (alt Rust binding)](https://github.com/colinmarc/signalsmith-stretch-rs)
- [Top DAWs Time-Stretch Algorithms 2025](https://www.widebluesound.com/blog/top-daws-and-their-time%E2%80%91stretch-algorithms-2025/)
- [Signalsmith vs Rubber Band comparison (KVR)](https://www.kvraudio.com/forum/viewtopic.php?t=623537)
- [zplane Élastique Pro SDK docs](https://licensing.zplane.de/uploads/SDK/ELASTIQUE-PRO/V3/manual/elastique_pro_v3_sdk_documentation.pdf)
- [Rubber Band Technical](https://www.breakfastquay.com/rubberband/technical.html)
- [Bungee comparison tool](https://bungee.parabolaresearch.com/compare-audio-stretch-tempo-pitch-change)
