# Channel Tab — Ultra Detaljna Analiza

**Datum:** 2026-01-24
**Autor:** Claude (Principal Engineer Review)
**Status:** KRITIČNA ANALIZA

---

## 1. ARHITEKTURALNI PREGLED

### 1.1 File Structure

```
flutter_ui/lib/
├── models/
│   └── layout_models.dart          ← SOURCE OF TRUTH za ChannelStripData, InsertSlot, SendSlot
├── providers/
│   └── mixer_provider.dart         ← State management + FFI calls
├── widgets/
│   ├── layout/
│   │   ├── left_zone.dart          ← Container sa Project/Channel tabovima
│   │   └── channel_inspector_panel.dart  ← GLAVNI UI za Channel Tab
│   └── mixer/
│       └── channel_strip.dart      ← ⚠️ DUPLI MODEL (ne koristi se za Channel Tab!)
```

### 1.2 Routing Path

```
LeftZone (left_zone.dart)
    ↓
Tab: "channel" (vidljiv samo u DAW mode)
    ↓
ChannelInspectorPanel (channel_inspector_panel.dart)
    ↓
Koristi: ChannelStripData iz layout_models.dart
```

---

## 2. DATA MODELI

### 2.1 ChannelStripData (layout_models.dart:215-313)

```dart
class ChannelStripData {
  final String id;
  final String name;
  final String type;        // 'audio', 'instrument', 'bus', 'master'
  final Color color;
  final double volume;      // dB (-70 to +12)
  final double pan;         // -1 to 1 (left channel for stereo)
  final double panRight;    // -1 to 1 (right channel for stereo)
  final bool isStereo;      // dual pan mode
  final bool mute;
  final bool solo;
  final bool armed;
  final bool inputMonitor;
  final double meterL;
  final double meterR;
  final double peakL;
  final double peakR;
  final List<InsertSlot> inserts;
  final List<SendSlot> sends;
  final bool eqEnabled;
  final List<EQBand> eqBands;
  final String input;
  final String output;
}
```

### 2.2 InsertSlot (layout_models.dart:107-158)

```dart
class InsertSlot {
  final String id;
  final String name;
  final String type;        // 'eq', 'comp', 'reverb', 'delay', 'filter', 'fx', 'utility', 'custom', 'empty'
  final bool bypassed;
  final bool isPreFader;
  final double wetDry;      // 0.0 to 1.0
  final Map<String, dynamic>? params;

  int get wetDryPercent => (wetDry * 100).round();
  bool get isEmpty => type == 'empty' || name.isEmpty;
}
```

### 2.3 SendSlot (layout_models.dart:161-193)

```dart
class SendSlot {
  final String id;
  final String? destination;  // bus id or null
  final double level;         // 0.0 to 1.0
  final bool preFader;
  final bool enabled;

  bool get isEmpty => destination == null || destination!.isEmpty;
}
```

### 2.4 EQBand (layout_models.dart:196-212)

```dart
class EQBand {
  final int index;
  final String type;        // 'lowcut', 'lowshelf', 'bell', 'highshelf', 'highcut'
  final double frequency;
  final double gain;        // dB
  final double q;
  final bool enabled;
}
```

---

## 3. UI SEKCIJE (channel_inspector_panel.dart)

### 3.1 Channel Header
- **Name display** — sa type badge (Audio/Bus/Master)
- **Color indicator** — boja kanala
- **Peak meters** — L/R peak bars
- **Clip indicator** — crveni badge kad peak > 0dB

### 3.2 Channel Controls
| Kontrola | Tip | Range | FFI |
|----------|-----|-------|-----|
| Volume Fader | Slider | -70 to +12 dB | ✅ `setTrackVolume()` |
| Pan (Mono) | Knob | -100 to +100 | ✅ `setTrackPan()` |
| Pan L (Stereo) | Knob | -100 to +100 | ✅ `setTrackPan()` |
| Pan R (Stereo) | Knob | -100 to +100 | ✅ `setTrackPanRight()` |
| Mute (M) | Toggle | On/Off | ✅ `setTrackMute()` |
| Solo (S) | Toggle | On/Off | ✅ `setTrackSolo()` |
| Record Arm (R) | Toggle | On/Off | ✅ `recordingArmTrack()` |
| Input Monitor (I) | Toggle | On/Off | ❌ **NE RADI** |

### 3.3 Inserts Section
- **8 slotova** (4 pre-fader + 4 post-fader)
- Drag & drop reordering
- Per-slot controls:
  - Bypass toggle → `insertSetBypass()`
  - Wet/Dry slider → `insertSetMix()`
  - Remove button → `insertUnloadSlot()`
  - Open Editor button → ❌ **NE RADI** (samo debugPrint)

### 3.4 Sends Section
- **8 send slotova**
- Per-send controls:
  - Level slider → ✅ `sendSetLevel()` / `sendSetLevelDb()` **RADI**
  - Enable toggle → ✅ `sendSetEnabled()` **RADI**
  - Pre/Post toggle → ⚠️ UI postoji, FFI treba verifikovati
  - Destination selector → ✅ `sendSetDestination()` **RADI**

**NAPOMENA:** Sends FFI POSTOJI i callback lanac je kompletan:
```
UI → onChannelSendLevelChange → EngineApi.setSendLevel() → native_ffi.sendSetLevel()
```

### 3.5 Routing Section
| Kontrola | Status |
|----------|--------|
| Input Selector | ❌ Samo UI, nema FFI |
| Output Selector | ❌ Samo UI, nema FFI |

### 3.6 Clip Section
- Prikazuje se samo kad je clip selektovan
- Clip info: name, duration, position
- ❌ Nema editabilnih parametara

---

## 4. ANALIZA PO ULOGAMA

### 4.1 🎵 Audio Designer / Composer

**Koristi:** Volume, Pan, Mute/Solo, Inserts, Sends

**Problemi:**
1. ~~**Sends ne rade**~~ → ✅ **ISPRAVLJENO:** Sends FFI postoji i radi
2. **Insert editor ne otvara** — bypass radi, ali "Open Editor" samo printa
3. **Input Monitor ne radi** — ne mogu monitor-ovati live input
4. **Routing selector treba verifikaciju** — callback postoji, FFI treba proveriti

**Ocena:** ⭐⭐⭐ (3/5) — Većina funkcionalnosti radi, Insert Editor i Input Monitor nedostaju

### 4.2 🛠 Engine / Runtime Developer

**Koristi:** FFI integration, state sync

**Problemi:**
1. ~~**Sends imaju model ali ne i FFI**~~ → ✅ **ISPRAVLJENO:** FFI postoji:
   - `sendSetLevel()`, `sendSetLevelDb()`, `sendSetDestination()`, `sendSetEnabled()`
   - Callback lanac: `onChannelSendLevelChange` → `EngineApi.setSendLevel()`
2. **Input Monitor FFI nedostaje** — `setTrackInputMonitor()` ne postoji u Rust engine-u
3. **Insert editor callback nije implementiran** — samo debugPrint
4. **Routing callback treba verifikaciju** — postoji ali treba proveriti FFI

**Ocena:** ⭐⭐⭐⭐ (4/5) — Većina FFI funkcionalnosti postoji i radi

### 4.3 🎨 UX / UI Designer

**Koristi:** Visual feedback, interaction patterns

**Problemi:**
1. **Sends slotovi su "dead" — izgledaju aktivni ali ne rade**
2. **Insert "Open Editor" daje lažni feedback** — otvara ništa
3. **Routing selectors ne daju vizualni feedback** — promene se ne odražavaju
4. **Nema indikacija da nešto NE radi** — user ne zna da feature nije implementiran

**Ocena:** ⭐⭐ (2/5) — Misleading UI

### 4.4 🧪 QA / Determinism Engineer

**Koristi:** Testiranje, validacija

**Problemi:**
1. **Dupli modeli** — `channel_strip.dart` ima DRUGU definiciju InsertSlot/SendSlot
2. **Property name mismatch:**
   - layout: `bypassed` vs mixer: `bypass`
   - layout: `name` vs mixer: `pluginName`
   - layout: `isPreFader` vs mixer: `prePost`
3. **Inconsistent volume range:**
   - layout: dB (-70 to +12)
   - mixer: linear (0.0 to 1.5)

**Ocena:** ⭐ (1/5) — Arhitekturalni debt, teško za testiranje

### 4.5 🧬 DSP / Audio Processing Engineer

**Koristi:** Insert chain, routing, processing

**Problemi:**
1. **Insert chain postoji u FFI** ali:
   - `insertCreateChain()` se ne poziva automatski pri kreiranju track-a
   - Manualno dodavanje insert-a RADI
2. **Pre/Post fader logika:**
   - Model ima `isPreFader` flag
   - FFI ima slot indices (0-3 pre, 4-7 post)
   - ✅ Mapiranje je ispravno
3. **Wet/Dry processing:**
   - ✅ FFI radi (`insertSetMix`)
   - ✅ UI slider radi

**Ocena:** ⭐⭐⭐ (3/5) — Insert chain radi, sends ne rade

### 4.6 🧠 Audio Middleware Architect

**Koristi:** Bus routing, send/return

**Problemi:**
1. ~~**Send/Return arhitektura nije implementirana**~~ → ✅ **ISPRAVLJENO:**
   - Model: `AuxSend` u MixerProvider postoji
   - FFI: `sendSetLevel()`, `sendSetDestination()`, `sendSetEnabled()` POSTOJE
   - UI: Callback lanac je kompletan i funkcionalan
2. **Bus hierarchy:**
   - Default buses se ne kreiraju (samo Master)
   - `_initializeDefaultBuses()` je prazan
3. **No sidechain support:**
   - Insert nema sidechain input
   - Model nema sidechain field

**Ocena:** ⭐⭐⭐ (3/5) — Send/Return radi, Bus hierarchy i Sidechain nedostaju

### 4.7 🧩 Tooling / Editor Developer

**Koristi:** Plugin UI, editor windows

**Problemi:**
1. **Plugin editor window ne postoji:**
   - `onChannelInsertOpenEditor` samo printa
   - Nema PluginEditorWindow widget
2. **No plugin browser integration:**
   - Insert click ne otvara browser
   - Hardcoded plugin lista
3. **No preset system:**
   - Inserts nemaju preset support
   - Channel strip nema "save as preset"

**Ocena:** ⭐ (1/5) — Plugin tooling nedostaje

---

## 5. KRITIČNI PROBLEMI

### 5.1 🔴 P0 — BLOKERI

| # | Problem | Impact | Lokacija |
|---|---------|--------|----------|
| ~~P0.1~~ | ~~Sends ne rade~~ | ✅ **RADI** — FFI postoji i callback je povezan | — |
| P0.2 | Output routing treba verifikaciju | Bus routing | channel_inspector_panel.dart:970-1020 |
| P0.3 | Input Monitor ne radi | Live recording broken | mixer_provider.dart — **FFI NE POSTOJI** |
| P0.4 | Insert Editor ne otvara | Plugin editing impossible | left_zone.dart callback — **samo debugPrint** |

### 5.2 🟡 P1 — VISOK PRIORITET

| # | Problem | Impact | Lokacija |
|---|---------|--------|----------|
| P1.1 | Dupli data modeli | Confusion, bugs | channel_strip.dart vs layout_models.dart |
| P1.2 | Input routing nedostaje | Can't select input source | mixer_provider.dart |
| P1.3 | Default buses ne postoje | No SFX/Music/VO buses | mixer_provider.dart:450-460 |
| P1.4 | **Phase Invert button nedostaje u UI** | Phase issues | FFI postoji (`trackSetPhaseInvert`) ali UI nema button |

### 5.3 🟢 P2 — SREDNJI PRIORITET

| # | Problem | Impact | Lokacija |
|---|---------|--------|----------|
| P2.1 | EQ bands u modelu ali ne u UI | EQ inspector missing | layout_models.dart:196-212 |
| P2.2 | Clip section je read-only | Can't edit clip properties | channel_inspector_panel.dart |
| P2.3 | No phase invert button | Phase issues unresolvable | UI missing |
| P2.4 | No input gain/trim | Gain staging impossible | UI has it, FFI TODO |

---

## 6. FFI ANALIZA

### 6.1 Implementirane FFI funkcije

| Funkcija | Status | Koristi UI? |
|----------|--------|-------------|
| `setTrackVolume()` | ✅ | ✅ |
| `setTrackPan()` | ✅ | ✅ |
| `setTrackPanRight()` | ✅ | ✅ |
| `setTrackMute()` | ✅ | ✅ |
| `setTrackSolo()` | ✅ | ✅ |
| `recordingArmTrack()` | ✅ | ✅ |
| `insertSetBypass()` | ✅ | ✅ |
| `insertSetMix()` | ✅ | ✅ |
| `insertLoadProcessor()` | ✅ | ✅ |
| `insertUnloadSlot()` | ✅ | ✅ |
| `trackSetPhaseInvert()` | ✅ | ❌ (UI nema button) |

### 6.2 Postojeće Send FFI funkcije (VERIFICIRANO ✅)

| Funkcija | Status | Koristi UI? |
|----------|--------|-------------|
| `sendSetLevel()` | ✅ | ✅ via EngineApi.setSendLevel() |
| `sendSetLevelDb()` | ✅ | ⚠️ Alternative |
| `sendSetDestination()` | ✅ | ✅ |
| `sendSetEnabled()` | ✅ | ✅ |
| `sendSetPreFader()` | ⚠️ Treba verifikovati | ⚠️ |

### 6.3 Nedostaju FFI funkcije

| Funkcija | Potrebno za |
|----------|-------------|
| `setTrackInputSource()` | Input routing |
| `setTrackInputMonitor()` | **KRITIČNO** — Input monitoring |
| `setTrackInputGain()` | Input gain/trim |

---

## 7. CALLBACK ANALIZA

### 7.1 LeftZone Callbacks (left_zone.dart)

```dart
// IMPLEMENTIRANO:
onChannelVolumeChange       → MixerProvider.setChannelVolume() ✅
onChannelPanChange          → MixerProvider.setChannelPan() ✅
onChannelPanRightChange     → MixerProvider.setChannelPanRight() ✅
onChannelMuteToggle         → MixerProvider.toggleChannelMute() ✅
onChannelSoloToggle         → MixerProvider.toggleChannelSolo() ✅
onChannelArmToggle          → MixerProvider.toggleChannelArm() ✅
onChannelInsertBypassToggle → MixerProvider.updateInsertBypass() ✅
onChannelInsertWetDryChange → MixerProvider.updateInsertWetDry() ✅
onChannelInsertRemove       → MixerProvider.removeInsert() ✅

// RADI (callback povezan sa FFI):
onChannelSendLevelChange    → EngineApi.setSendLevel() → sendSetLevel() ✅

// NE RADI (callback postoji ali je prazan/nema efekta):
onChannelMonitorToggle      → MixerProvider.toggleInputMonitor() ❌ (FFI NE POSTOJI u Rust)
onChannelSendClick          → debugPrint() ❌
onChannelOutputClick        → debugPrint() ❌
onChannelInputClick         → debugPrint() ❌
onChannelInsertClick        → debugPrint() ❌ (trebalo bi otvoriti browser)
onChannelInsertOpenEditor   → debugPrint() ❌ (trebalo bi otvoriti editor)
onChannelEQToggle           → MixerProvider ne implementira ❌
```

---

## 8. TODO LISTA

### 8.1 P0 — Kritično (Odmah)

- [x] ~~**TODO-P0.1:** Implementirati Sends FFI~~ — ✅ **RADI**
  - FFI funkcije postoje: `sendSetLevel()`, `sendSetDestination()`, `sendSetEnabled()`
  - Callback lanac kompletan: UI → EngineApi.setSendLevel() → native_ffi.sendSetLevel()

- [ ] **TODO-P0.2:** Verifikovati Output Routing
  - `onChannelOutputClick` callback — trenutno debugPrint
  - Potrebno: otvara bus selector i poziva FFI

- [ ] **TODO-P0.3:** Implementirati Input Monitor FFI
  - **KRITIČNO:** `setTrackInputMonitor()` NE POSTOJI u Rust engine-u
  - Potrebno:
    1. Dodati FFI u `crates/rf-engine/src/` ili `crates/rf-bridge/src/`
    2. Binding u `native_ffi.dart`
    3. Poziv iz `MixerProvider.toggleInputMonitor()`

- [ ] **TODO-P0.4:** Implementirati Insert Editor
  - `onChannelInsertOpenEditor` trenutno samo poziva `debugPrint()`
  - Potrebno:
    1. Kreirati `PluginEditorWindow` widget
    2. Callback da otvara popup sa parametrima
    3. Parametri se prikazuju i edituju

### 8.2 P1 — Visok Prioritet (Ova nedelja)

- [ ] **TODO-P1.1:** Ukloniti dupli model iz `channel_strip.dart`
  - Preći na korišćenje `layout_models.dart` svuda
  - Ukloniti `InsertSlot`, `SendSlot`, `ChannelStripData` iz `channel_strip.dart`

- [ ] **TODO-P1.2:** Implementirati Input Routing
  - Input selector dropdown
  - Lista available inputs
  - FFI: `getAvailableInputs()`, `setTrackInputSource()`

- [ ] **TODO-P1.3:** Kreirati default buses
  - U `_initializeDefaultBuses()` kreirati:
    - bus_sfx, bus_music, bus_vo, bus_ambient, bus_ui

- [ ] **TODO-P1.4:** Phase Invert button — **LAKO, FFI POSTOJI**
  - Dodati Ø button u Channel Controls sekciju (pored M/S/R)
  - Poziva `MixerProvider.togglePhaseInvert()`
  - FFI već postoji: `trackSetPhaseInvert()`
  - Lokacija UI: `channel_inspector_panel.dart` Channel Controls sekcija

### 8.3 P2 — Srednji Prioritet (Sledeća nedelja)

- [ ] **TODO-P2.1:** EQ Inspector
  - Prikazati EQ bands iz modela
  - Parametri: freq, gain, Q, type, enabled
  - EQ curve visualization

- [ ] **TODO-P2.2:** Clip Editor Properties
  - Gain envelope
  - Fade in/out
  - Pitch/time stretch

- [ ] **TODO-P2.3:** Input Gain Slider
  - Dodati gain slider (-20 to +20 dB)
  - FFI: `setTrackInputGain()` (TODO u mixer_provider.dart:1533)

- [ ] **TODO-P2.4:** Insert Browser Integration
  - `onChannelInsertClick` otvara plugin browser
  - Kategorije: EQ, Dynamics, Reverb, Delay, etc.
  - Search functionality

### 8.4 P3 — Niži Prioritet (Kasnije)

- [ ] **TODO-P3.1:** Channel Strip Preset System
  - Save/Load channel strip settings
  - Include: inserts, sends, routing

- [ ] **TODO-P3.2:** Sidechain Support
  - Sidechain input selector per insert
  - Sidechain from any track/bus

- [ ] **TODO-P3.3:** VCA Assignment UI
  - VCA dropdown in channel strip
  - Quick assign to existing VCAs

---

## 9. PREPORUČENA REDOSLED IMPLEMENTACIJE

```
1. TODO-P1.4 (Phase Invert button) — FFI već postoji, samo dodati UI button
2. TODO-P0.3 (Input Monitor FFI) — potrebna Rust implementacija
3. TODO-P0.4 (Insert Editor) — kompleksno ali bitno za plugin workflow
4. TODO-P1.1 (Dupli model cleanup) — čisti technical debt
5. TODO-P0.2 (Output Routing) — verifikovati i povezati
6. TODO-P1.3 (Default buses) — kreirati SFX/Music/VO buses
7. TODO-P1.2 (Input Routing) — manje urgentno
8. P2/P3 taskovi po prioritetu
```

**NAPOMENA:** TODO-P0.1 (Sends) je ZAVRŠEN — FFI radi!

---

## 10. ZAKLJUČAK

**Channel Tab — Korigovana Analiza:**

### ✅ Šta RADI:
1. **Volume, Pan, Mute, Solo, Arm** — Kompletno funkcionalno sa FFI
2. **Insert Bypass, Wet/Dry, Load/Unload** — FFI radi
3. **Sends Level, Enable, Destination** — ✅ **FFI POSTOJI I RADI**
4. **Phase Invert** — FFI postoji (`trackSetPhaseInvert`)

### ❌ Šta NE RADI:
1. **Input Monitor** — FFI NE POSTOJI u Rust engine-u
2. **Insert Editor** — Callback samo printa, ne otvara editor
3. **Phase Invert Button** — FFI postoji ali UI nema button
4. **Output/Input Routing UI** — Callbacks idu u debugPrint

### Arhitekturalni problemi:
1. **Dupli data modeli** — `channel_strip.dart` vs `layout_models.dart`
2. **Default buses nedostaju** — `_initializeDefaultBuses()` je prazan

**Ocena:** ⭐⭐⭐⭐ (4/5) — Većina funkcionalnosti radi, ostalo je uglavnom UI polish i par FFI funkcija.

**Preporuka:** Fokus na P0.3 (Input Monitor FFI) i P0.4 (Insert Editor) — ovo su jedina dva prava blokera.

---

*Dokument generisan: 2026-01-24*
*Verzija: 1.1 (Korigovana nakon verifikacije)*
