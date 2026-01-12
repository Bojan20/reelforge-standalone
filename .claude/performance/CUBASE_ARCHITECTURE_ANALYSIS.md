# Cubase Architecture Analysis

## Reference document za ReelForge performance optimizaciju

---

## 1) Dve odvojene "mašine": Audio Engine vs UI Engine

### Audio Engine (real-time, hard rules)

- Radi u audio callback ritmu (ASIO / CoreAudio)
- Stroga pravila:
  - **NEMA alokacija memorije**
  - **NEMA lockova (mutex)** koji mogu da blokiraju
  - **NEMA disk I/O** u samom callback-u
  - Sve mora da bude **deterministički i brzo**

### UI Engine (komforan, ali pametan)

- Radi na UI thread-u i pomoćnim thread-ovima
- Sme:
  - Da radi keširanje
  - Da radi dekodovanje i pre-render waveforma
  - Da radi prefetch sa diska
- **Ali nikad ne sme da "spoji" sudbinu audio callback-a sa UI**

> **POENTA:** Audio i UI su **decoupled** - UI može da dropuje frame, audio NE SME.

---

## 2) Kako Cubase "implementira" audio fajl na timeline

### A) Media Pool / Asset Registry

- Fajl dobija `asset_id`
- Snimaju se metapodaci: sample rate, channels, length, bit depth, format, time-stamp
- Ako sample rate ne odgovara projektu:
  - Ili radi **on-the-fly resample**
  - Ili pripremi **cache render** (zavisi od podešavanja)

### B) Event/Clip model (nedestruktivno)

- "Audio event" na timeline-u **NE MENJA fajl**
- Event čuva samo:
  - `sourceRef` (koji fajl)
  - `startOffset` u fajlu
  - `length`
  - fade-in/out krive
  - warp/time-stretch info
  - gain, clip envelopes
  - crossfade linkove

### C) Offline analiza (van audio callback-a)

Odmah nakon importa Cubase tipično radi:
- **Waveform peak build**
- Opcionalno: tempo detection / hitpoints / transient analysis
- Sve ide u cache (posebni fajlovi pored projekta ili u internom cache folderu)

---

## 3) Disk streaming: zašto playback ne "koci"

### Ključ: Read-ahead + Ring Buffer

- Za svaki aktivni audio stream, engine drži **ring buffer u RAM-u**
- Poseban **"disk thread"** radi:
  - Čita unapred (read-ahead) sledeće blokove sa diska
  - Puni ring buffer
- **Audio callback samo "pije" iz ring buffera: ZERO WAIT**

### Prioriteti i granularnost

- Disk čitanje je tipično u većim chunkovima (npr. 64–256 KB ili više)
- Ako projekat ima puno traka:
  - Engine radi **prioritizaciju** (šta uskoro dolazi do playhead-a)
  - Može da smanji kvalitet preview-a ili agresivnije kešira

### Memory mapping (često)

- WAV/AIFF često ide kroz **memory-mapped I/O** (OS radi keširanje)
- Time se smanjuje overhead i latencija

---

## 4) Processing graf: routing, inserti, sendovi, grupe

Cubase-klasa DAW-a radi processing kao **DAG (directed acyclic graph)**:

### Node-ovi

1. Track input node (audio clip reader / instrument output)
2. Insert chain node (plugin chain)
3. Send nodes (to FX buses)
4. Group bus nodes
5. Master bus node
6. Metering node (posebno, često "tap" posle procesa)

### Kako se izvršava

Svaki audio blok (npr. 256 samples) engine:
1. Topološki sortuje graf (ili koristi pre-built schedule)
2. Izvršava node po node

Ako ima paralelizam:
- Nezavisne grane mogu na različite core-ove
- Ali se pazi na latency compensation i sync

### Plugin latencija i PDC

- Svaki plugin prijavi latenciju (samples)
- Engine računa PDC i ubacuje delay line gde treba
- Ovo je razlog što graf mora biti precizno planiran

---

## 5) Automation i "instant" reakcija bez blokiranja

Cubase mora da reaguje na:
- Knob move
- Automation curve
- Mute/solo
- Plugin parameter changes

### Pattern: "Control thread → lock-free queue → Audio thread"

1. UI/control šalje događaje u **lock-free SPSC ring** (single-producer single-consumer)
2. Audio thread na početku svakog bloka:
   - Pročita sve pending param events
   - Primeni ih na DSP state
3. Ako treba smoothing:
   - Radi se param ramp kroz N sample-ova ili kroz blok

---

## 6) Zoom in/out i scroll: kako je "instant"

**Ovo je najbitniji deo za osećaj "DAW ne koci".**

### A) Waveform prikaz NIJE "izračunaj iz audio svaki frame"

Umesto toga, Cubase ima **multi-resolution peak cache (mipmaps za audio)**:

| Level | Opis |
|-------|------|
| Level 0 | Peak per sample ili per mali prozor |
| Level 1 | Peak per 2x/4x veći prozor |
| Level 2 | Peak per 8x/16x… |
| Level N | …do nivoa gde je 1 pixel ~ mnogo ms |

**Kad zoomiraš:**
- UI samo bira odgovarajući nivo (najbliži pixel density)
- Render je **O(width)** a ne O(audioLength)
- **Zato zoom deluje instant**

### B) Tile-based render + caching

- Timeline se deli u **"tile-ove"** (npr. 256px širine)
- Svaki tile ima cached bitmap waveforma
- Kad scrolluješ, većina tile-ova je već tu
- Novi tile se renderuje **asinkrono** (worker thread)

### C) Progressive refinement

Ako nema keša:
1. Odmah se prikaže **gruba verzija** (coarser mip level)
2. Zatim u pozadini "dotera" finiji nivo kad stigne

### D) Clip boundaries / fades su vektori, ne raster

- Fade krive, selection, grid lines se crtaju **vektorski** i jeftino

---

## 7) Scrub / jog / pre-listen

Scrub mora biti ultra responsivan:
- Koristi poseban **"scrub reader"**
- Često sa manjim bufferom i drugačijim prioritetom
- Može da koristi time-stretch minimalnog kvaliteta (brz algoritam) dok scrubbing traje

---

## 8) Time-stretch / warp / audio alignment bez blokiranja

Kad uključiš warp:
1. Analysis (transients, tempo map) ide **offline**
2. Playback koristi **precomputed markers**
3. Real-time stretch algoritam bira "real-time safe" varijantu
4. Ako je stretch skup:
   - Cubase može da radi **render-in-place** ili **background render cache**

---

## 9) Must-Have arhitektura za ReelForge "Cubase feeling"

### Audio callback thread
- Bez lockova
- Bez alokacija
- Bez file I/O

### Disk streaming thread
- Read-ahead u ring buffere po streamu

### Asset cache
- Decoded PCM cache (opciono)
- **Multi-res peak cache (OBAVEZNO za zoom)**

### UI waveform renderer
- **Tile cache** (bitmap)
- **Worker threads + progressive refinement**

### Control→Audio event queue
- **Lock-free SPSC ring** za param events
- Sample-accurate timestamp u okviru bloka

### Processing graph scheduler
- DAG + pre-built schedule
- PDC sistem (bar osnovni)

---

## Peak Cache Implementation (najveći "instant" trik)

```
Precompute min/max po prozoru:

Level 0: 256 samples window
Level 1: 512 samples window
Level 2: 1024 samples window
Level 3: 2048 samples window
Level 4: 4096 samples window
...

Čuvaj na disk kao svoj format (brz za mmap).
```

### Zoom Level → Peak Level mapping

```
zoom < 10 px/sec   → Level 4+ (coarsest)
zoom 10-50 px/sec  → Level 3
zoom 50-200 px/sec → Level 2
zoom 200-500 px/sec → Level 1
zoom > 500 px/sec  → Level 0 (finest)
```

---

## Trenutno stanje ReelForge vs Cubase

| Feature | Cubase | ReelForge | Status |
|---------|--------|-----------|--------|
| Audio/UI decoupling | ✅ | ✅ | OK - Rust engine odvojen |
| Lock-free param queue | ✅ | ❓ | Treba proveriti |
| Disk streaming | ✅ | ❓ | Treba implementirati |
| Multi-res peak cache | ✅ | ❌ | **KRITIČNO** - nedostaje |
| Tile-based waveform | ✅ | ❌ | **KRITIČNO** - nedostaje |
| Progressive refinement | ✅ | ❌ | Nedostaje |
| DAG processing | ✅ | ✅ | OK - RoutingGraph |
| PDC | ✅ | ✅ | OK - implementirano |

---

## Action Items za ReelForge

### KRITIČNO (uzrokuje kočenje)

1. **Multi-resolution peak cache**
   - Implementirati LOD levels za waveform
   - Keširati na disk (.peaks fajlovi)
   - Instant zoom selection based on pixel density

2. **Tile-based waveform rendering**
   - Podeliti timeline na tile-ove
   - Keširati rendered tiles kao Images
   - Async tile generation

3. **UI rebuild isolation**
   - Consumer<EngineProvider> NE SME da rebuilda ceo UI
   - Koristiti Selector za specifične vrednosti
   - Playhead kao odvojen widget

### SREDNJI PRIORITET

4. **Disk streaming sa ring bufferima**
   - Pre-fetch audio data
   - Background loading

5. **Lock-free control queue**
   - SPSC ring za parameter changes
   - Sample-accurate automation

### NIŽI PRIORITET

6. **Progressive refinement**
   - Prikaži coarse pa refine
   - Smooth UX during zoom

---

## Reference

- Cubase Pro 13 Performance Guide
- JUCE Audio Application Framework
- Steinberg VST3 SDK Documentation
- Real-Time Audio Programming Best Practices
