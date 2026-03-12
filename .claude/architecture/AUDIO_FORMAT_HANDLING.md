# Audio Format Handling — Mixed Sample Rate & Bit Depth

## 1. Kako Reaper radi (referentni standard)

Reaper je referentni DAW za handlovanje mešanih formata u istom projektu:

| Aspekt | Reaper ponašanje |
|--------|-----------------|
| **Interni format** | 64-bit float (sav processing) |
| **Import** | Fajl ostaje nepromenjen na disku, čuva originalni SR/BD |
| **Bit depth mešanje** | Potpuno transparentno — sve se konvertuje u float pri dekodiranju |
| **Sample rate mešanje** | Real-time sinc resampling pri playback-u (fajl se ne menja) |
| **Playback kvalitet** | Configurable resampling mode (Sinc 64pt/512pt/768pt) |
| **Export** | Nezavisan od source formata — biraj bilo koji SR/BD/format |
| **Project SR promena** | Resampluje sve regione automatski |
| **Pitch shift** | Pitch ratio nezavisan od SRC — oba se kombinuju |

**Ključni princip:** Reaper NIKADA ne konvertuje fajlove na disku. Sve konverzije su real-time u audio callback-u. Korisnik može da ubaci 44.1kHz/16-bit, 96kHz/24-bit i 48kHz/32-float fajlove u isti projekat i sve radi bez ikakve intervencije.

---

## 2. FluxForge trenutno stanje

### 2.1 Bit Depth — ODLIČNO (Reaper-nivo)

**Import path** (`rf-engine/src/audio_import.rs:406-546`):

Symphonia dekoder podržava SVE bit depth formate i konvertuje u f32:

| Source format | Konverzija | Normalizacija |
|---------------|-----------|---------------|
| S8 | `sample / 128.0` | -1.0 to ~1.0 |
| U8 | `(sample - 128.0) / 128.0` | -1.0 to ~1.0 |
| S16 | `sample / 32768.0` | -1.0 to ~1.0 |
| U16 | `(sample - 32768.0) / 32768.0` | -1.0 to ~1.0 |
| S24 | `sample.inner() / 8388608.0` | -1.0 to ~1.0 |
| U24 | `(sample.inner() - 8388608.0) / 8388608.0` | -1.0 to ~1.0 |
| S32 | `sample / 2147483648.0` | -1.0 to ~1.0 |
| U32 | `(sample - 2147483648.0) / 2147483648.0` | -1.0 to ~1.0 |
| F32 | direktno (bez konverzije) | već normalizovano |
| F64 | `sample as f32` | cast |

**Processing path:**

Engine interno koristi `f64` bufere za sav audio processing (`playback.rs` output_l/output_r su `&mut [f64]`). Ovo daje >300dB dinamički opseg — više nego dovoljno za profesionalni rad.

**Zaključak:** Možeš mešati 16-bit, 24-bit i 32-bit float fajlove u istom projektu BEZ ikakvih problema. Bit depth je potpuno transparentan.

### 2.2 Sample Rate — Timeline Clips: RADI

**Lokacija:** `rf-engine/src/playback.rs:6150-6250` (`render_clip_audio`)

```rust
let source_sample_rate = audio.sample_rate as f64;
let rate_ratio = source_sample_rate / sample_rate;  // sample_rate = project/engine SR

// Apply time stretch + sample rate conversion with Lanczos-3 sinc interpolation
let source_pos_f64 = clip_offset as f64 * rate_ratio * playback_rate + source_offset_samples;
```

Timeline clip rendering koristi `rate_ratio` za svaki frame:
- Engine sample rate (npr. 48000) vs source file sample rate (npr. 44100)
- `rate_ratio = 44100 / 48000 = 0.91875` — svaki engine frame čita 0.91875 source frames
- Koristi **Lanczos-3 sinc interpolaciju** za visokokvalitetno resampling
- Kombinuje se sa `playback_rate` (time stretch) i `source_offset` (region offset)

Ovo je identično kako Reaper radi — fajl ostaje netaknut, konverzija je real-time.

Isti pattern postoji i u `render_clip_audio_crossfade` (`playback.rs:6621-6622`).

### 2.3 Sample Rate — One-Shot Voices: BUG (NE RADI SRC)

**Lokacija:** `rf-engine/src/playback.rs:1184-1350` (`OneShotVoice::fill_buffer`)

One-shot voices se koriste za:
- SlotLab audio (stage events, middleware playback)
- Browser preview (audio file preview)
- Play-to-bus (FFI: `playback_play_to_bus`, `playback_play_looping_to_bus`)

**Problem:** `fill_buffer()` NE koristi `rate_ratio`. Sample position se računa direktno:

```rust
let fractional_pos = self.position as f64 + (frame as f64 * pitch_ratio);
let src_frame = src_pos.floor() as usize;
```

`pitch_ratio` je za pitch shift (semitones), NE za sample rate konverziju.

**Posledica:** Ako engine radi na 48kHz a one-shot fajl je 44.1kHz:
- Zvuk će biti pusten ~8.8% brže (jer se 44100 sempla pusti za 44100/48000 = 0.91875 sec umesto 1 sec)
- Pitch je viši za ~1.5 polutonova
- Trajanje je kraće od očekivanog

**Primer konkretnog uticaja:**

| Source SR | Engine SR | Pitch shift | Duration error |
|-----------|-----------|-------------|----------------|
| 44100 | 48000 | +1.47 semitones | -8.2% kraće |
| 96000 | 48000 | -12.0 semitones (oktava dole) | +100% duže |
| 22050 | 48000 | +13.5 semitones | -54.1% kraće |
| 48000 | 44100 | -1.47 semitones | +8.8% duže |
| 48000 | 48000 | 0 (tačno) | 0% (tačno) |

### 2.4 SampleRateConverter — Postoji, Ne Koristi Se Automatski

**Lokacija:** `rf-engine/src/audio_import.rs:623-741`

Dva algoritma:
- `convert_linear()` — linearna interpolacija (brza, niži kvalitet)
- `convert_sinc()` — Lanczos-3 sinc interpolacija (sporija, visok kvalitet)

Oba su funkcionalna i testirana, ali se **ne pozivaju nigde automatski** pri importu. Ovo je ISPRAVNO ponašanje (Reaper-stil) — fajl se čuva u originalnom formatu, SRC se radi u real-time.

Problem je što one-shot voice path ne radi real-time SRC.

---

## 3. Export sistem — Potpuno funkcionalan

### 3.1 Rust backend (`rf-engine/src/export.rs`)

**ExportEngine** koristi `PlaybackEngine::process_offline()` za rendering:
- Blok-po-blok rendering (default 512 samples)
- Output u f64 bufere (full precision)
- Podržava tail rendering (reverb/delay decay)
- Normalize na -0.1 dBFS (opciono)

**Podržani formati:**

| Format | Varijante | Backend |
|--------|-----------|---------|
| WAV | 16-bit PCM, 24-bit PCM, 32-bit float | `OfflineRenderer::write_wav_*` |
| FLAC | 16-bit, 24-bit | `rf_file::write_flac` |
| MP3 | 128/192/256/320 kbps | `rf_file::write_mp3` |

**Stems export** (`export_stems`):
- Per-track rendering via `process_track_offline()`
- Sanitized filenames
- Per-stem progress tracking
- Optional bus stems

**ExportConfig:**

| Polje | Opis | Default |
|-------|------|---------|
| `output_path` | Output fajl putanja | `export.wav` |
| `format` | ExportFormat enum | `Wav24` |
| `sample_rate` | Target SR (0 = project rate) | 48000 |
| `start_time` | Početak regiona (sec) | 0.0 |
| `end_time` | Kraj regiona (sec) | 60.0 |
| `include_tail` | Reverb/delay tail | true |
| `tail_seconds` | Trajanje tail-a | 3.0s |
| `normalize` | -0.1 dBFS normalize | false |
| `block_size` | Render block size | 512 |

### 3.2 Flutter UI (`flutter_ui/lib/widgets/lower_zone/export_panels.dart`)

**DawExportPanel** — profesionalni export UI:

| Kontrola | Opcije |
|----------|--------|
| Format | WAV, FLAC, MP3, OGG |
| Sample Rate | 44.1 / 48 / 88.2 / 96 / 176.4 / 192 kHz |
| Bit Depth | 16-bit, 24-bit, 32-bit float |
| Normalization | None, Peak (dB), LUFS |
| Norm. Target | Peak: -12 to 0 dB / LUFS: -24 to -8 |
| Include Tail | da/ne |

**ExportService** (`flutter_ui/lib/services/export_service.dart`):
- Progress stream sa ETA
- Cancellation support
- Filename suggestion
- File size estimation per format

### 3.3 rf-offline crate (`crates/rf-offline/`)

Batch processing pipeline:

| Mogućnost | Detalji |
|-----------|---------|
| Import | WAV, AIFF, FLAC, ALAC, MP3, OGG/Vorbis, AAC, M4A (Symphonia) |
| Export Native | WAV (16/24/32f), AIFF, FLAC, MP3, OGG, Opus |
| Export FFmpeg | AAC (zahteva FFmpeg u PATH) |
| Metering | EBU R128 LUFS (integrated/short-term/momentary), True Peak (4x oversampled) |
| Normalization | LUFS target (-14/-16/-23), Peak target, Dynamic range |
| Pipeline | Job queue sa async processing, progress callbacks |

**FFI:** `offline_pipeline_create/set_format/process_file/destroy`, `offline_get_audio_info`

### 3.4 Export — Nedostajući SRC pri exportu

**NAPOMENA:** `ExportEngine::export()` (linija 197-199) koristi project sample rate ako je `config.sample_rate == 0`. Ali ako korisnik odabere drugačiji SR od projekta, **nema resampling koraka** u export pipeline-u — `process_offline()` renderuje na engine sample rate, a `write_output()` piše sa `config.sample_rate` kao metadata ali BEZ stvarne SRC.

Ovo znači da ako projekat radi na 48kHz i korisnik exportuje na 44.1kHz, **fajl će imati pogrešan header** (kaže 44.1kHz ali sadrži 48kHz audio → pitch shift + trajanje greška).

---

## 4. Project Settings Screen

**Lokacija:** `flutter_ui/lib/screens/project/project_settings_screen.dart`

**Audio Settings sekcija** prikazuje Project Sample Rate sa ChoiceChip-ovima:
- 44.1 / 48 / 88.2 / 96 / 176.4 / 192 kHz
- Warning: "Changing sample rate will resample all audio"

**Navigacija:**
- Otvara se sa `Navigator.push(MaterialPageRoute(...))` iz `engine_connected_layout.dart:3704`
- AppBar ima back button (`Navigator.pop()`)
- **NEMA ESC keyboard handler** — na desktopu ESC ne zatvara stranicu

---

## 5. Identifikovani bagovi i nedostaci

### BUG 1: One-Shot Voice nema SRC (KRITIČAN)

| | Detalji |
|--|---------|
| **Lokacija** | `rf-engine/src/playback.rs:1184` — `OneShotVoice::fill_buffer()` |
| **Problem** | Nema `rate_ratio` kompenzaciju za razliku source SR vs engine SR |
| **Uticaj** | Pogrešan pitch i trajanje za sve one-shot zvukove sa SR != engine SR |
| **Pogođeni sistemi** | SlotLab audio, Browser preview, Play-to-bus |
| **Fix** | Dodati `rate_ratio = audio.sample_rate / engine_sample_rate` u position kalkulaciju |
| **Referenca** | Timeline clips (`render_clip_audio` linija 6163) ovo već rade ispravno |

### BUG 2: Export SRC ne postoji

| | Detalji |
|--|---------|
| **Lokacija** | `rf-engine/src/export.rs:172` — `ExportEngine::export()` |
| **Problem** | `process_offline()` renderuje na engine SR, `write_output()` piše `config.sample_rate` kao header bez stvarne konverzije |
| **Uticaj** | Export na SR != project SR daje pogrešan audio (pitch/duration error) |
| **Fix** | Dodati SRC korak između rendering i writing (koristiti `SampleRateConverter::convert_sinc`) |

### NEDOSTAJE: ESC za Project Settings

| | Detalji |
|--|---------|
| **Lokacija** | `flutter_ui/lib/screens/project/project_settings_screen.dart:125` |
| **Problem** | Nema keyboard handler za ESC → `Navigator.pop()` |
| **Uticaj** | Korisnik mora da klikne back button, ne može ESC na desktopu |
| **Fix** | Wrap Scaffold u `KeyboardListener` sa ESC handler, ili koristi `CallbackShortcuts` |

---

## 6. Matrica kompatibilnosti (trenutno stanje)

| Scenario | Timeline Clips | One-Shot Voices | Export |
|----------|---------------|----------------|--------|
| Isti SR kao projekat | OK | OK | OK |
| Različit SR od projekta | OK (SRC) | BUG (nema SRC) | BUG (pogrešan header) |
| Različit bit depth | OK (f32→f64) | OK (f32→f64) | OK |
| Mešani SR u projektu | OK | BUG | N/A |
| Mešani BD u projektu | OK | OK | N/A |
| Export na drugačiji SR | N/A | N/A | BUG |
| Export na drugačiji BD | N/A | N/A | OK |

---

*Poslednji update: 2026-03-11*
*Autor: Claude (istraživanje codebase-a)*
