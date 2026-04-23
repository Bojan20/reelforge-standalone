# DAW Audio Track Tools — Uporedna Analiza & QA

**Datum:** 2026-03-12
**Cilj:** Potpuno funkcionalni toolovi na audio track-ovima kao u Logic Pro X i Cubase

---

## 1. REFERENCA: Logic Pro X & Cubase Toolovi

### 1.1 Selection / Pointer Tool

| Aspekt | Logic Pro X | Cubase |
|--------|------------|--------|
| **Shortcut** | T (cycles tools) | 1 (Object Select) |
| **Klik** | Selektuje region/event | Selektuje event |
| **Drag** | Pomera region | Pomera event |
| **Edge drag** | Resize (trim) levo/desno | Resize levo/desno |
| **Shift+klik** | Dodaj u selekciju | Dodaj u selekciju |
| **Option+drag** | Kopija regiona | Alt+drag = kopija |
| **Cmd+drag** | Fine pozicioniranje (bypass snap) | Ctrl+drag = bypass snap |
| **Double-click** | Otvori editor (Piano Roll / Audio Editor) | Otvori editor |
| **Marquee** | Poseban Marquee tool (T cycles) | Range Selection tool (2) |
| **Kurzor** | Arrow → resize na ivicama | Arrow → resize na ivicama |

### 1.2 Cut / Scissors Tool

| Aspekt | Logic Pro X | Cubase |
|--------|------------|--------|
| **Shortcut** | I (posle T) | 3 (Split) |
| **Klik** | Split na poziciji klika | Split na poziciji klika |
| **Option+klik** | Multiple equal cuts (deli na jednake segmente) | Alt+klik = split na svim trakama |
| **Snap** | Poštuje grid snap | Poštuje grid snap |
| **Cmd+klik** | Bypass snap, precizni split | Ctrl = bypass snap |
| **Na crossfade** | Seče oba klipa | Seče oba klipa |
| **Undo** | Cmd+Z vraća oba dela | Ctrl+Z vraća oba dela |
| **Kurzor** | Makaze ikona | Makaze ikona |

### 1.3 Crossfade

| Aspekt | Logic Pro X | Cubase |
|--------|------------|--------|
| **Kreiranje** | X shortcut na selektovane susedne klipove | Drag preklapanje ili X shortcut |
| **Auto-crossfade** | Preferences → auto | X-Fade edit mode |
| **Tipovi kriva** | Linear, Equal Power, S-Curve (+6 varijanti) | Linear, Equal Power, S-Curve (+custom) |
| **Editovanje** | Double-click otvara Crossfade Editor | Double-click → Crossfade Editor |
| **Resize** | Drag ivice crossfade-a | Drag ivice |
| **Promena krive** | U editoru, klik na preset | U editoru, slajderi |
| **Brisanje** | Select + Delete | Select + Delete |
| **Vizuelni prikaz** | X-pattern overlay na klipu | X-pattern overlay |
| **Audio processing** | Real-time, non-destructive | Real-time, non-destructive |
| **Default dužina** | Preferences → General → Editing | Project Setup → Crossfade duration |

### 1.4 Fade In / Fade Out

| Aspekt | Logic Pro X | Cubase |
|--------|------------|--------|
| **Kreiranje** | Drag Fade handle (gornji ugao klipa) | Drag gornji ugao klipa |
| **Fade In** | Gornji levi ugao → drag desno | Gornji levi → drag desno |
| **Fade Out** | Gornji desni ugao → drag levo | Gornji desni → drag levo |
| **Krive** | Linear, S-Curve, Exp, Log (+custom) | Linear, Exp, Log, S-Curve (+4 varijante) |
| **Editovanje krive** | Double-click na fade → editor | Klik na fade → popup |
| **Region Inspector** | Precizne vrednosti u Inspector-u | Info Line prikazuje fade vrednosti |
| **Interakcija sa Vol** | Fade je pre Volume automation-a | Fade je pre Volume automation-a |
| **Vizuelni prikaz** | Curve overlay na waveform-u | Curve overlay na waveform-u |
| **Batch** | Select više regiona → fade se primeni na sve | Select više → batch fade |
| **Keyboard** | Cmd+Shift+F (Fade In), Option+Shift+F (Fade Out) | — |
| **Default curve** | Preferences → Audio → Editing | Preferences → Editing → Audio |

### 1.5 Glue / Join Tool

| Aspekt | Logic Pro X | Cubase |
|--------|------------|--------|
| **Shortcut** | J (Join) | 5 (Glue) |
| **Klik** | Join sa sledećim regionom | Glue sa sledećim eventom |
| **Susedni** | Kreira container (folder region) | Kreira novi audio fajl (bounce) |
| **Overlapping** | Merge u novi fajl | Merge u novi fajl |
| **Shift+klik** | — | Glue sve na traci |
| **Undo** | Vraća originalne regione | Vraća originalne evente |
| **Audio file** | Kreira novi fajl (flatten) | Cubase: container ILI novi fajl |

### 1.6 Zoom Tool

| Aspekt | Logic Pro X | Cubase |
|--------|------------|--------|
| **Shortcut** | Z | 7 (Zoom) |
| **Klik** | Zoom in na poziciju | Zoom in |
| **Option+klik** | Zoom out | Alt+klik = zoom out |
| **Drag** | Rubber-band zoom na oblast | Rubber-band zoom |
| **Scroll** | Cmd+scroll = horizontal zoom | Ctrl+scroll = horizontal zoom |
| **Ctrl+scroll** | — | Alt+scroll = vertical zoom |
| **Zoom to fit** | Z (double-tap) ili Cmd+F | Ctrl+F = fit all |
| **Kurzor** | Magnifying glass (+/-) | Magnifying glass (+/-) |

### 1.7 Mute Tool

| Aspekt | Logic Pro X | Cubase |
|--------|------------|--------|
| **Shortcut** | M (mute selection) | 8 (Mute tool) |
| **Klik** | Toggle mute na regionu | Toggle mute na eventu |
| **Vizuelni** | Dimmed/grayed region, "X" indikator | Semi-transparent, muted badge |
| **Audio** | Region se ne reprodukuje | Event se ne reprodukuje |
| **Undo** | Cmd+Z | Ctrl+Z |

### 1.8 Eraser / Delete Tool

| Aspekt | Logic Pro X | Cubase |
|--------|------------|--------|
| **Shortcut** | Delete key (sa selection) | 6 (Erase tool) |
| **Klik** | — (Logic nema eraser tool, koristi Delete key) | Klik = briše event |
| **Option+klik** | — | — |
| **Kurzor** | — | Eraser ikona |

### 1.9 Slip / Trim Editing

| Aspekt | Logic Pro X | Cubase |
|--------|------------|--------|
| **Slip edit** | Option+drag u regionu | Alt+Shift+drag (Sizing Moves Contents) |
| **Trim** | Edge drag (pointer tool) | Edge drag (pointer tool) |
| **Razlika** | Slip: pomera audio unutar granica klipa | Isti koncept |
| **Alt+trim** | — | Cubase: Alt+drag ivice = Sizing Moves Contents |
| **Kurzor** | H-resize na ivicama | H-resize na ivicama |

### 1.10 Range / Marquee Selection

| Aspekt | Logic Pro X | Cubase |
|--------|------------|--------|
| **Shortcut** | Marquee tool (Cmd+click u track area) | 2 (Range Selection) |
| **Drag** | Selektuje vremenski opseg | Selektuje vremenski opseg |
| **Across tracks** | Da, prelazi više traka | Da |
| **Cut** | Cmd+X izseče range | Ctrl+X |
| **Copy** | Cmd+C kopira | Ctrl+C |
| **Delete** | Delete briše sadržaj u range-u | Delete |
| **Bounce** | Ctrl+B bounce in place | Audio → Bounce Selection |
| **Split** | Cmd+T split na granicama range-a | Split at Selection |

---

## 2. FLUXFORGE STUDIO — Trenutno Stanje

### 2.1 Implementirani Toolovi (VERIFIKOVANO iz koda)

| Tool | Enum | Shortcut | Status | Verifikacija |
|------|------|----------|--------|-------------|
| Smart Tool | `smart` | 1 | **RADI** | 9-zone hit test, clip_widget.dart:437-440 dispatch |
| Object Select | `objectSelect` | 2 | **RADI** | Select/move/resize, full smart tool behavior |
| Range Select | `rangeSelect` | 3 | **STUB** | Toolbar radi, kurzor radi, ALI nema range state u timeline.dart — rubber band selektuje klipove, NE vremenski opseg |
| Split | `split` | 4 | **RADI** | clip_widget.dart:511-526, poziva `onSplitAtPosition`, snap radi |
| Glue | `glue` | 5 | **STUB** | clip_widget.dart:537-540 samo selektuje klip (`onSelect`), NE POSTOJI join logika ni u Dart ni u Rust FFI |
| Erase | `erase` | 6 | **RADI** | clip_widget.dart:527-532, poziva `onDelete`, proverava locked |
| Zoom | `zoom` | 7 | **STUB** | clip_widget.dart:541-544 prazan return, timeline.dart:977 ima klik zoom ali samo u praznom prostoru |
| Mute | `mute` | 8 | **RADI** | clip_widget.dart:533-536, poziva `onMute`, ceo chain wired do FFI |
| Draw | `draw` | 9 | **STUB** | clip_widget.dart:551 falls through to select, NEMA nikakvu logiku |
| Play | `play` | 0 | **PARCIJALAN** | clip_widget.dart:545-549 pomera playhead (`onPlayheadMove`), timeline.dart:985 startuje playback |

**Keyboard dispatch:** timeline.dart:1632-1655, svih 10 tastera (1-0) mapirano. F1-F5 edit modes u main_layout.dart:555-560.

### 2.2 Smart Tool Zone System (9 zona — VERIFIKOVANO)

| Zona | SmartToolMode | Kurzor | Status | Verifikacija |
|------|--------------|--------|--------|-------------|
| Fade In | `fadeIn` | resizeUpLeft | **RADI** | clip_widget.dart:635-642 + 772-784, dual path (smart + FadeHandle widget) |
| Fade Out | `fadeOut` | resizeUpRight | **RADI** | Isto kao Fade In, `onFadeChange` callback, max 0.5× clip duration |
| Volume Handle | `volumeHandle` | resizeUpDown | **RADI** | clip_widget.dart:643-647 + 787-795, `onGainChange` callback, range 0.0-4.0 |
| Trim Left | `trimLeft` | resizeLeft | **RADI** | `onClipResize` FFI wired |
| Trim Right | `trimRight` | resizeRight | **RADI** | `onClipResize` FFI wired |
| Loop Handle | `loopHandle` | resizeRight | **RADI** | toggle + drag |
| Crossfade | `crossfade` | resizeColumn | **DETEKCIJA SAMO** | Zone hit test radi, ALI nema drag state `_isDraggingCrossfade`, nema `onCrossfadeCreate` callback u ClipWidget |
| Range Select (body) | `rangeSelectBody` | text (I-beam) | **CTRL+CLICK SAMO** | clip_widget.dart:665-675, Ctrl+click poziva `onPlayheadMove` (scrub), NEMA drag range selekciju |
| Move/Select (body) | `select` | move | **RADI** | Drag + cross-track + modifier keys |

**Dodatne zone verifikovane:**
| Zona | Status | Verifikacija |
|------|--------|-------------|
| Slip Content | **RADI** | clip_widget.dart:615-619 (Alt+Shift), 840-843 drag, `onSlipEdit` callback |
| Time Stretch | **RADI** | clip_widget.dart:648-655 + 809-823, `onTimeStretch` callback, 0.1s-4× range |

### 2.3 Edit Modes (VERIFIKOVANO)

| Mode | Shortcut | Status | Verifikacija |
|------|----------|--------|-------------|
| Shuffle | F1 | **DART→RUST RADI, ALI move_clip() IGNORIŠE mode** | Dart `EditModeProProvider:419` poziva `ffi.editModeSet(2)`. Rust `edit_mode_set` (ffi.rs:8587) čuva u EDIT_CONTEXT. ALI: `move_clip()` (track_manager.rs:2722) NE konsultuje EDIT_CONTEXT — nema ripple logiku. |
| Slip | F2 | **PARCIJALAN** | Alt+Shift slip radi u clip_widget (sourceOffset). Edit mode se šalje Rust-u ali `move_clip()` ga ignoriše. |
| Spot | F3 | **DART→RUST RADI, ALI move_clip() IGNORIŠE** | Isto kao Shuffle — mode se šalje i čuva ali `move_clip()` ga ne konsultuje |
| Grid | F4 | **RADI (Dart snap + Rust grid)** | Snap sistem funkcionalan u Dart-u. `EditModeProProvider` šalje grid settings Rust-u (resolution, enabled, strength). |
| X-Fade | F5 | **AUTO-CROSSFADE POSTOJI nezavisno od mode-a** | `_createAutoCrossfadeIfOverlap` u engine_connected_layout.dart:3410 RADI, ALI nije vezan za X-Fade toolbar toggle |

**F1-F5 keyboard shortcuts:** **POSTOJE** — `main_layout.dart:555-560` mapira F1-F5 na `TimelineEditMode` (Shuffle, Slip, Spot, Grid, X-Fade) i poziva `smartTool.setActiveEditMode()`.

**KRITIČAN NALAZ (potvrđen QA-om):**
1. Edit modes su u provideru — toolbar UI radi (bira mode) ✅
2. Dart šalje mode Rust-u — `EditModeProProvider:419` poziva `ffi.editModeSet()` ✅
3. F1-F5 shortcuts postoje u `main_layout.dart:555-560` ✅
4. ALI: Rust `move_clip()` NE konsultuje EDIT_CONTEXT — jedini nedostatak je Rust-side logika
5. Rezultat: Dart→Rust komunikacija radi, ali Rust ne primenjuje mode na clip operacije

### 2.4 Clip Data Model

**Fajl:** `timeline_models.dart`

| Property | Tip | Status |
|----------|-----|--------|
| `startTime` | double | OK |
| `duration` | double | OK |
| `sourceOffset` | double | OK |
| `sourceDuration` | double? | OK |
| `fadeIn` | double | OK |
| `fadeOut` | double | OK |
| `fadeInCurve` | FadeCurve | OK (8 tipova: linear, log3, sine, log1, invSCurve, sCurve, exp1, exp3) |
| `fadeOutCurve` | FadeCurve | OK |
| `gain` | double | OK (0-2) |
| `muted` | bool | OK |
| `locked` | bool | OK |
| `selected` | bool | OK |
| `loopEnabled` | bool | OK |
| `loopCount` | int | OK |
| `loopCrossfade` | double | OK |
| `stretchRatio` | double | OK |
| `reversed` | bool | OK |
| `snapOffset` | double | OK |
| `channelMode` | ClipChannelMode | OK (6 modova) |

### 2.5 Crossfade Model

**Fajl:** `timeline_models.dart`

```dart
class Crossfade {
  final String id, trackId, clipAId, clipBId;
  final double startTime, duration;
  final CrossfadeCurve curveType; // linear, equalPower, sCurve, logarithmic, exponential
}
```

**Overlay widget:** `crossfade_overlay.dart` — vizuelni X-pattern, resize handles, double-tap delete

**DSP:** `rf-dsp/src/crossfade.rs` — CrossfadeProcessor sa pre-computed fade table (4096 entries)

### 2.6 FFI Clip Operacije (VERIFIKOVANO)

| Operacija | FFI Funkcija | Status |
|-----------|-------------|--------|
| Split | `splitClip(clipId, atTime)` | **RADI** |
| Move | `moveClip(clipId, targetTrackId, startTime)` | **RADI** |
| Resize | `resizeClip(clipId, startTime, duration, sourceOffset)` | **RADI** |
| Duplicate | `duplicateClip(clipId)` | **RADI** |
| Delete | `deleteClip(clipId)` | **RADI** |
| Set Gain | `setClipGain(clipId, gain)` | **RADI** |
| Set Muted | `setClipMuted(clipId, muted)` | **RADI** |
| Loop Enable | `setClipLoopEnabled(clipId, enabled)` | **RADI** |
| Loop Count | `setClipLoopCount(clipId, count)` | **RADI** |
| Loop Crossfade | `setClipLoopCrossfade(clipId, duration)` | **RADI** |
| **Fade In** | `clip_fade_in(clipId, duration, curveType)` | **RADI** (curve param definisan ali NE KORISTI SE u Rust) |
| **Fade Out** | `clip_fade_out(clipId, duration, curveType)` | **RADI** (isti issue sa curve) |
| **Clip Gain dB** | `clip_apply_gain(clipId, gainDb)` | **RADI** (clamp 0.0-4.0 linear) |
| **Create Crossfade** | `engine_create_crossfade(clipAId, clipBId, duration, curve)` | **RADI** — vraća crossfade ID |
| **Update Crossfade** | `engine_update_crossfade(crossfadeId, duration, curve)` | **RADI** |
| **Delete Crossfade** | `engine_delete_crossfade(crossfadeId)` | **RADI** |
| **Edit Mode** | `edit_mode_set(mode)` u Rust ffi.rs:8587 | **DART BINDING POSTOJI** (`editModeSet()` native_ffi.dart:8174, koristi `EditModeProProvider:419`). ALI: `move_clip()` NE konsultuje EDIT_CONTEXT |
| **Glue/Join** | — | **NE POSTOJI** u Rust FFI |

**Razor (Range Selection) — RUST ONLY, NEMA DART BINDING:**

15 funkcija postoji u `rf-engine/src/ffi.rs` (linija 23995+), ALI **nijedna nije bindirana** u `native_ffi.dart` ili `engine_api.dart`.

| Operacija | Rust FFI (ffi.rs) | Dart Binding | Status |
|-----------|-------------------|-------------|--------|
| Add Area | `razor_add_area` (L23995) | ❌ NE POSTOJI | Treba dodati |
| Delete | `razor_delete` (L24108) | ❌ NE POSTOJI | Treba dodati |
| Split | `razor_split` (L24117) | ❌ NE POSTOJI | Treba dodati |
| Cut | `razor_cut` (L24128) | ❌ NE POSTOJI | Treba dodati |
| Copy | `razor_copy` (L24139) | ❌ NE POSTOJI | Treba dodati |
| Move | `razor_move` (L24149) | ❌ NE POSTOJI | Treba dodati |
| Reverse | `razor_reverse` (L24163) | ❌ NE POSTOJI | Treba dodati |
| Stretch | `razor_stretch` (L24173) | ❌ NE POSTOJI | Treba dodati |
| Duplicate | `razor_duplicate` (L24183) | ❌ NE POSTOJI | Treba dodati |
| Update Area | `razor_update_area` (L24021) | ❌ NE POSTOJI | Treba dodati |
| Remove Area | `razor_remove_area` (L24031) | ❌ NE POSTOJI | Treba dodati |
| Clear All | `razor_clear_all` (L24041) | ❌ NE POSTOJI | Treba dodati |
| Clear Track | `razor_clear_track` (L24050) | ❌ NE POSTOJI | Treba dodati |
| Has Areas | `razor_has_areas` (L24060) | ❌ NE POSTOJI | Treba dodati |
| Get Areas JSON | `razor_get_areas_json` (L24076) | ❌ NE POSTOJI | Treba dodati |

**Clip Envelope — RUST ONLY, NEMA DART BINDING:**

Funkcije postoje u `rf-engine/src/ffi.rs`, ALI **nisu bindirane** u Dart.

| Operacija | Rust FFI | Dart Binding |
|-----------|----------|-------------|
| Enable Envelope | Postoji u ffi.rs | ❌ NE POSTOJI u native_ffi.dart |
| Add Point | Postoji u ffi.rs | ❌ NE POSTOJI |
| Remove Point | Postoji u ffi.rs | ❌ NE POSTOJI |
| Clear | Postoji u ffi.rs | ❌ NE POSTOJI |
| Get/Set JSON | Postoji u ffi.rs | ❌ NE POSTOJI |

**NOVO OTKRIĆE — Bounce FFI:**

| Operacija | FFI Funkcija | Status |
|-----------|-------------|--------|
| Start Bounce | `bounce_start(path, format, bitDepth, sampleRate, start, end, normalize, target)` | **RADI** |
| Progress | `bounce_get_progress()` | **RADI** (0-100%) |
| Cancel | `bounce_cancel()` | **RADI** |

### 2.7 Undo System (VERIFIKOVANO — 21 akcija ukupno)

**Fajl:** `undo_manager.dart`

**Timeline akcije (8):**
1. `ClipMoveAction` — undo_manager.dart:19
2. `TrackAddAction` — undo_manager.dart:49
3. `TrackDeleteAction` — undo_manager.dart:71
4. `GenericUndoAction` — undo_manager.dart:93 (catch-all)
5. `RegionMoveAction` — undo_manager.dart:115
6. `RegionDeleteAction` — undo_manager.dart:145
7. `RegionAddAction` — undo_manager.dart:171
8. `BatchUndoAction` — undo_manager.dart:195

**Mixer akcije (13) — `mixer_undo_actions.dart`:**
VolumeChange, PanChange, MuteToggle, SoloToggle, SendLevelChange, RouteChange, InsertLoad, InsertUnload, InsertBypass, InputGainChange, SoloSafeToggle, CommentsChange, FolderToggle

**KRITIČAN NALAZ:** engine_connected_layout.dart koristi `GenericUndoAction` na **12 mesta** (linije 1487, 1535, 1573, 1954, 3151, 3187, 6320, 6726, 6825, 7129, 7172, 7359) — NE koristi specijalizovane akcije poput `ClipMoveAction`. Specifične undo klase su potencijalno mrtav kod.

---

## 3. GAP ANALIZA — Šta Nedostaje

### 3.1 KRITIČNI NEDOSTACI (posle verifikacije koda)

| # | Gap | Prioritet | Opis |
|---|-----|-----------|------|
| G1 | **Range Selection — Razor postoji u Rust, NEMA Dart binding** | **P0** | Rust `rf-engine/src/ffi.rs` ima 15 `razor_*` FFI funkcija (linija 23995+). ALI `native_ffi.dart` i `engine_api.dart` ih **NE SADRŽE** — nisu bindirane. Potrebno: 1) Dodati Dart FFI bindinge, 2) Dodati range state u timeline.dart, 3) UI za range selekciju. |
| G2 | **Glue tool — NE POSTOJI ni u Rust ni u Dart** | **P1** | clip_widget.dart:537-540 klik samo poziva `onSelect`. Rust FFI **NEMA** glue/join/merge. Potrebna nova FFI ili Dart-side implementacija. |
| G5 | **Zoom tool — stub na klipovima** | P2 | clip_widget.dart:541-544 prazan return. Timeline.dart:977 ima klik zoom samo u PRAZNOM prostoru. Nema rubber-band zoom, nema Alt+klik zoom out. |
| G6 | **Draw tool — potpuno nedostaje** | P2 | Falls through to select. NEMA kreiranje klipova niti crtanje automation-a. |
| G8 | **Edit modes — Rust `move_clip()` IGNORIŠE EDIT_CONTEXT** | **P1** | Dart→Rust chain RADI: `EditModeProProvider:419` → `ffi.editModeSet()` (native_ffi.dart:8174) → Rust `edit_mode_set` (ffi.rs:8587) čuva u EDIT_CONTEXT. F1-F5 shortcuts postoje (main_layout.dart:555-560). ALI: `move_clip()` (track_manager.rs:2722) **NE KONSULTUJE** EDIT_CONTEXT — slobodno pomera bez shuffle/grid logike. Potrebno: SAMO Rust-side logika u `move_clip()`. |
| G9 | **Crossfade drag-to-create nedostaje** | **P1** | FFI `engine_create_crossfade` radi. Auto-crossfade na overlap radi (`_createAutoCrossfadeIfOverlap`). ALI: nema drag-to-create u crossfade zoni klipa, nema X shortcut na selekciju. |
| G10 | **Fade curve — FFI ignoriše curveType** | P2 | `clip_fade_in/out` FFI primaju `curveType` parametar ali ga Rust engine **IGNORIŠE**. Krive su samo vizuelne (Dart rendering). Audio fade je uvek linear u engine-u. |

### 3.2 ISPRAVLJENI — Ranije prijavljeni kao neispravni, zapravo RADE

| # | Stavka | Stvarni status | Dokaz |
|---|--------|---------------|-------|
| ~~G3~~ | **Erase tool** | **RADI** | clip_widget.dart:527-532, poziva `onDelete`, proverava locked |
| ~~G4~~ | **Mute tool** | **RADI** | clip_widget.dart:533-536, poziva `onMute`, ceo chain wired do FFI |
| ~~G7~~ | **Play tool** | **PARCIJALAN ALI RADI** | clip_widget:545 pomera playhead, timeline:985 startuje playback u praznom |
| ~~G11~~ | **Volume handle drag** | **RADI** | clip_widget.dart:643-647 + 787-795, `onGainChange`, range 0.0-4.0 |
| ~~G12~~ | **Auto-crossfade na overlap** | **RADI** | `_createAutoCrossfadeIfOverlap` u engine_connected_layout.dart |
| ~~G13~~ | **Slip editing** | **RADI** | clip_widget.dart:615-619 + 840-843, Alt+Shift, `onSlipEdit` |
| ~~G14~~ | **Time stretch handle** | **RADI** | clip_widget.dart:648-655 + 809-823, `onTimeStretch` |

### 3.3 OSTALI VERIFIKOVANI NEDOSTACI

| # | Gap | Opis |
|---|-----|------|
| G11 | **Crossfade drag-to-create u clip zoni** | SmartToolProvider detektuje crossfade zonu, ALI clip_widget nema `_isDraggingCrossfade` flag niti `onCrossfadeCreate` callback |
| G12 | **X-Fade edit mode toggle → efekat** | Auto-crossfade logika postoji ali NIJE vezana za X-Fade toolbar toggle — uvek radi nezavisno od mode-a |
| ~~G13~~ | **F1-F5 edit mode shortcuts** | **POSTOJE** — `main_layout.dart:555-560`, F1=Shuffle, F2=Slip, F3=Spot, F4=Grid, F5=X-Fade |
| G14 | **Edit mode — Rust `move_clip()` ignoriše mode** | Dart→Rust komunikacija RADI (`EditModeProProvider:419` → `ffi.editModeSet()`). Jedini nedostatak: `move_clip()` ne konsultuje EDIT_CONTEXT. |
| G15 | **GenericUndoAction za SVE** | engine_connected_layout.dart:6726,6825,7172 koristi GenericUndoAction. Specijalizovane (ClipMoveAction itd.) su potencijalno mrtav kod |
| G16 | **Keyboard shortcut za fade** | Nema Cmd+Shift+F za fade in/out |
| G17 | **Batch mute (drag-across)** | Mute tool klik radi, ALI nema Cubase-stil drag-across batch mute |
| G18 | **Crossfade curve type change UI** | Overlay prikazuje krive, double-tap briše, ALI nema right-click menu za promenu curve tipa |
| G19 | **Fade curve type selector** | Model ima 8 FadeCurve tipova, ALI nema UI za korisnički izbor krive |
| G20 | **Range Selection ↔ Razor — NEMA DART BINDING** | 15 razor_* funkcija postoji u Rust ffi.rs, ALI native_ffi.dart NEMA NIJEDAN binding. Potrebno dodati 15 FFI bindinga pre UI wiring-a. |

### 3.4 NEDOSTAJUĆE PROFESIONALNE FUNKCIONALNOSTI

| # | Feature | Logic/Cubase | FluxForge |
|---|---------|-------------|-----------|
| G21 | **Crossfade Editor** | Double-click → full editor sa audition | Ne postoji (FFI update radi, nema UI) |
| G22 | **Fade preset library** | Da | Ne |
| G23 | **Bounce in Place** | Select → bounce | FFI `bounce_start()` POSTOJI, ALI nema UI workflow za "Bounce Selection" |
| G24 | **Snap to transients** | Da | Enum postoji u SnapTarget, logika ne |
| G25 | **Marquee → auto-split** | Da (Logic) | Razor FFI ima `razor_split()`, ali nema Dart UI |
| G26 | **Clip Envelope UI** | Automation points na klipu | Rust FFI postoji, ALI **NEMA DART BINDING** u native_ffi.dart. Potrebno: dodati 5+ FFI bindinga + UI. |

---

## 4. DETALJAN QA PLAN

### Faza 1: Toolovi koji ne rade (P0/P1) — tool click actions

**Test 1.1 — Range Selection**
- [ ] Prebaci na Range tool (3)
- [ ] Drag horizontalno na timeline → kreira vizuelni range
- [ ] Range prelazi više traka vertikalno
- [ ] Delete briše sadržaj u range-u
- [ ] Cmd+C kopira range sadržaj
- [ ] Cmd+X izseče range sadržaj
- [ ] Range granice splituju klipove na ivicama

**Test 1.2 — Glue Tool**
- [ ] Prebaci na Glue tool (5)
- [ ] Klik na klip → spaja sa sledećim susednim klipom
- [ ] Rezultat: jedan klip sa kombinovanim trajanjem
- [ ] Undo (Cmd+Z) vraća originalne klipove
- [ ] Klik na klip koji nema suseda → ništa se ne dešava

**Test 1.3 — Erase Tool** ✅ VERIFIKOVANO RADI
- [x] Klik na klip → briše ga (clip_widget.dart:527-532, proverava locked)
- [ ] Undo (Cmd+Z) vraća obrisani klip — TESTIRATI (koristi GenericUndoAction)
- [x] Klik na prazan prostor → ništa se ne dešava
- [x] Kurzor je eraser ikona (disappearing)

**Test 1.4 — Mute Tool** ✅ VERIFIKOVANO RADI
- [x] Klik na klip → toggle mute (clip_widget.dart:533-536)
- [ ] Vizuelno: klip se dimuje (opacity) — TESTIRATI vizuelni feedback
- [ ] Audio: muted klip se ne reprodukuje — TESTIRATI playback
- [x] Ponovo klik → unmute (toggle)

**Test 1.5 — Zoom Tool** ❌ STUB
- [ ] Klik na klip → NIŠTA (prazan return na clip_widget.dart:541-544)
- [ ] Klik u praznom prostoru → zoom in radi (timeline.dart:977)
- [ ] Option+klik → zoom out — TESTIRATI
- [ ] Drag → rubber-band zoom — NE POSTOJI
- [ ] Kurzor: zoomIn (postoji)

**Test 1.6 — Play Tool** ⚠️ PARCIJALAN
- [x] Klik na klip → pomera playhead (clip_widget.dart:545-549)
- [ ] Klik u praznom prostoru → startuje playback (timeline.dart:985) — TESTIRATI
- [ ] Kurzor: click ikona (postoji)

### Faza 2: Smart Tool zone akcije (P1)

**Test 2.1 — Volume Handle** ✅ VERIFIKOVANO RADI
- [x] Hover gornji centar → kurzor resizeUpDown
- [x] Drag vertikalno → menja gain (clip_widget.dart:787-795, ~0.15dB/px)
- [x] Range 0.0-4.0
- [ ] Vizuelni feedback na waveform-u — TESTIRATI da li waveform prikazuje gain
- [ ] Gain vrednost prikazana tokom drag-a — TESTIRATI tooltip/label
- [ ] Snap na 0dB (unity) — verovatno NE POSTOJI

**Test 2.2 — Crossfade kreiranje** ⚠️ PARCIJALNO
- [x] Auto-crossfade na overlap radi (`_createAutoCrossfadeIfOverlap`)
- [x] Crossfade overlay vidljiv (crossfade_overlay.dart, X-pattern)
- [x] Resize levi/desni handle na overlay-u
- [x] Double-tap → briše crossfade
- [ ] Smart tool: hover između klipova → kurzor resizeColumn — TESTIRATI
- [ ] Drag u crossfade zoni → kreira crossfade — **NE RADI** (nema `_isDraggingCrossfade`)
- [ ] X shortcut na selektovane susedne → kreira crossfade — **NE POSTOJI**

**Test 2.3 — Slip Content** ✅ VERIFIKOVANO RADI
- [x] Alt+Shift+drag menja sourceOffset (clip_widget.dart:615-619 + 840-843)
- [x] Kurzor: resizeLeftRight
- [ ] Waveform se vizuelno pomera — TESTIRATI

**Test 2.4 — Time Stretch** ✅ VERIFIKOVANO RADI
- [x] Drag ivicu u body zoni → stretch (clip_widget.dart:648-655 + 809-823)
- [x] Range: 0.1s do 4× original
- [ ] Audio pitch ostaje isti — TESTIRATI playback

### Faza 3: Edit Modes — Dart ↔ Rust Sync (P1)

**Test 3.1 — Edit Mode FFI Sync** ✅ DART→RUST RADI
- [x] Toolbar Shuffle mode → `editModeSet(2)` pozvan — `EditModeProProvider:419` poziva FFI
- [x] Toolbar Grid mode → `editModeSet(1)` pozvan — isto
- [ ] Pomeri klip u Shuffle mode → ripple efekat — **RUST `move_clip()` NE KONSULTUJE EDIT_CONTEXT**

**Test 3.2 — F-Key Shortcuts** ✅ POSTOJE
- [x] F1 → Shuffle — `main_layout.dart:556`
- [x] F2 → Slip — `main_layout.dart:557`
- [x] F3 → Spot — `main_layout.dart:558`
- [x] F4 → Grid — `main_layout.dart:559`
- [x] F5 → X-Fade — `main_layout.dart:560`

**Test 3.3 — X-Fade Mode Efekat**
- [ ] X-Fade mode aktivan → overlap kreira crossfade — auto-crossfade radi ALI nije vezan za X-Fade toggle

### Faza 4: Fade & Crossfade Editing (P2)

**Test 4.1 — Fade In/Out** ✅ RADI
- [x] Drag gornji levi ugao → fade in (dual path: smart + FadeHandle)
- [x] Drag gornji desni ugao → fade out
- [x] Max 0.5× clip duration
- [ ] Fade curve type change — **NEMA UI** (model ima 8 tipova)
- [ ] Rust engine primenjuje curve type na audio — **NE RADI** (ignoriše curveType param)

**Test 4.2 — Crossfade Curve Change**
- [ ] Right-click na crossfade overlay → context menu — **NE POSTOJI**
- [ ] Promena curve tipa → vizuelni update — overlay podržava 5 tipova, nema UI trigger

### Faza 5: Range Selection ↔ Razor Wiring (P0)

**Test 5.1 — Razor Integration**
- [ ] Range tool (3) aktivan → drag kreira razor area via FFI `razor_add_area()`
- [ ] Vizuelni prikaz selektovanog opsega na timeline-u
- [ ] Delete → `razor_delete()` — briše sadržaj
- [ ] Cmd+X → `razor_cut()` — izseče u clipboard
- [ ] Cmd+C → `razor_copy()` — kopira
- [ ] Range granice → `razor_split()` — splituje klipove
- **STATUS: Rust FFI postoji (15 funkcija), ALI NEMA DART BINDING — potrebno dodati native_ffi.dart + engine_api.dart wrappere PRVO**

### Faza 6: Undo Kvalitet (P1)

**Test 6.1 — Undo Granularnost**
- [ ] Move klip → Cmd+Z vraća — koristi GenericUndoAction (radi ali nema semantiku)
- [ ] Split klip → Cmd+Z vraća — TESTIRATI
- [ ] Resize klip → Cmd+Z vraća — TESTIRATI
- [ ] Delete klip → Cmd+Z vraća — TESTIRATI
- [ ] Fade change → Cmd+Z vraća — TESTIRATI
- [ ] Redo (Cmd+Shift+Z) — TESTIRATI

---

## 5. REVIDIRANI PRIORITETNI PLAN IMPLEMENTACIJE

### Sprint 1: Edit Mode — Rust-side Implementation (P1)
Dart→Rust chain VEĆ RADI (`EditModeProProvider:419` → `editModeSet()` → Rust). F1-F5 shortcuts VEĆ POSTOJE (`main_layout.dart:555-560`). Jedini nedostatak je Rust-side logika:
1. **Rust:** Dodati edit mode logiku u `move_clip()` (track_manager.rs:2722) — grid snap, shuffle ripple, spot dialog
2. **Dart:** Veži X-Fade mode za auto-crossfade logiku (toggle on/off umesto always-on)

### Sprint 2: Range Selection ↔ Razor (P0, najveći impact)
Rust Razor FFI postoji (15 funkcija), ALI NIJEDNA nije bindirana u Dart:
1. **Dart FFI:** Dodati 15 razor_* bindinga u `native_ffi.dart` (lookup + typedef + wrapper)
2. **Dart API:** Dodati razor wrappere u `engine_api.dart`
3. **Range state** u timeline.dart (startTime, endTime, affectedTracks)
4. **Drag-to-select** sa Range tool (3)
5. **Vizuelni prikaz** selektovanog opsega
6. **Keyboard operacije**: Delete, Cmd+X, Cmd+C, Split at selection
7. **Wire do `razor_*` FFI** poziva

### Sprint 3: Crossfade Kreiranje + Curve UI
1. **Drag-to-create** u crossfade zoni (dodati `_isDraggingCrossfade` u clip_widget)
2. **X shortcut** na selektovane susedne klipove
3. **Right-click menu** na crossfade overlay za curve type change
4. **Fade curve selector** — popup sa 8 FadeCurve opcija

### Sprint 4: Glue Tool
1. **Opcija A (Dart-side):** Pronađi susedni klip, kreira novi sa kombinovanim bounds, briše stare
2. **Opcija B (Rust FFI):** Dodaj `engine_glue_clips()` u rf-engine/ffi.rs
3. **Undo** za glue operaciju

### Sprint 5: Zoom Tool + Draw Tool + Polish
1. **Zoom tool** — rubber-band zoom, Alt+klik zoom out na klipovima
2. **Draw tool** — kreiranje praznih klipova, crtanje automation
3. **Batch mute** — drag-across za mute tool
4. **0dB snap** na volume handle
5. **Undo** — zameni GenericUndoAction specijalizovanim akcijama

### Sprint 6: Clip Envelopes + Bounce UI + Fade Curve Fix
1. **Dart FFI:** Dodati clip_envelope_* bindinge u native_ffi.dart (5 funkcija)
2. **Clip envelope UI** — automation points na klipu
3. **Bounce Selection UI** — `bounce_start()` binding VEĆ POSTOJI, dodati "Bounce Selection" workflow
4. **Rust fix:** `clip_fade_in/out` u ffi.rs:8299 — dodati `clip.fade_in_curve = curve_type` umesto ignorisanja
5. **Rust fix:** Dodati `fade_in_curve`/`fade_out_curve` polja u Clip struct (track_manager.rs:1150)

---

## 6. KLJUČNI FAJLOVI ZA IMPLEMENTACIJU

| Fajl | Linije | Uloga | Akcija |
|------|--------|-------|--------|
| `smart_tool_provider.dart` | 1117 | Tool state, hit testing, snap | **NE MENJAJ** — čist, dobro dizajniran |
| `clip_widget.dart` | 2800+ | Clip interakcija, tool dispatch | **GLAVNO MESTO** — dodati crossfade drag, zoom wiring |
| `track_lane.dart` | 284 | Track container, prosleđuje callbacks | Dodati `onCrossfadeCreate` callback |
| `timeline.dart` | 1100+ | Timeline container, keyboard handlers | **DODATI:** range state, razor wiring. F1-F5 VEĆ POSTOJE u main_layout.dart. |
| `crossfade_overlay.dart` | 293 | Crossfade vizuelni | **DODATI:** right-click menu za curve type |
| `timeline_edit_toolbar.dart` | 444 | Toolbar UI | **OK** — sve radi |
| `timeline_models.dart` | ~1100 | Data modeli | Možda dodati `TimelineRange` klasu |
| `engine_connected_layout.dart` | veliki | Wiring FFI callbacks | **DODATI:** edit mode FFI sync, razor wiring, glue |
| `engine_api.dart` | 600+ | High-level FFI wrapper | **DODATI:** razor_* wrappere. Edit mode binding VEĆ POSTOJI. |
| `undo_manager.dart` | 250+ | Undo stack (21 akcija) | GenericUndoAction koristi se za sve — razmotriti specijalizaciju |
| `native_ffi.dart` | 21K+ | FFI bindings | **DODATI:** razor_* (15 bindinga), envelope_* (5). Edit mode, crossfade i fade VEĆ POSTOJE. |
| `rf-engine/src/ffi.rs` | 24K+ | Rust FFI exports | **EVENTUALNO:** dodati `engine_glue_clips()` |
| `rf-dsp/src/crossfade.rs` | 300+ | Crossfade DSP | **OK** — lock-free, sample-accurate |
| `rf-core/src/edit_mode.rs` | 150+ | Edit mode definicije | **OK** — Rust strana spremna |

---

## 7. KLJUČNI UVIDI IZ WEB RESEARCH-A (Logic/Cubase specifičnosti)

### Cubase — 3 Sizing Sub-Moda (VAŽNO za implementaciju)
Object Selection tool ima dropdown sa tri moda:
1. **Normal Sizing** — standardni trim (boundary se pomera, audio ostaje)
2. **Sizing Moves Contents** — slip+trim u jednom (boundary I audio se pomeraju)
3. **Sizing Applies Time Stretch** — boundary pomera = time stretch audio

**FluxForge:** Imamo trimLeft/trimRight i timeStretch kao ZASEBNE zone. Cubase ih tretira kao SUB-MODOVE istog tool-a. Naš pristup je bolji (manje skrivene funkcionalnosti).

### Logic — Click Zones (Smart Tool ekvivalent)
Logic nema "Smart Tool" po imenu, već Click Zones (Preferences):
- **Fade Tool Click Zones** — gornji ugao = fade pointer
- **Marquee Click Zones** — donja polovina = marquee
- **Loop Click Zones** — Option u fade zoni = loop
- **Resize zones** — donji ugao = resize

**FluxForge:** Naš 9-zone sistem je SUPERIORNIJI — sve zone su eksplicitno definisane sa konfigurabilnim procentima.

### Cubase Mute Tool — Drag Across
Cubase mute tool ima "mute-as-you-highlight" — drag preko klipova ih sve muti. Logic mute radi samo klik-po-klik.

**FluxForge:** Implementirati oba — klik za toggle, drag za batch mute.

### Glue Tool — Ključna razlika
- **Logic:** Kreira novi audio fajl (mixdown) ako klipovi nisu iz istog izvora
- **Cubase:** Kreira Part container (referenca, ne novi fajl)

**FluxForge:** Početi sa Cubase pristupom (container/merged clip) — jednostavnije, ne zahteva offline processing.

### Crossfade Editor — Cubase superioran
Cubase Crossfade Editor (double-click): spline interpolation, control points, presets, audition.
Logic koristi Region Inspector parametre.

**FluxForge:** Faza 1 = context menu za curve type. Faza 2 = full editor.

### Undo Granularnost
- Svaka tool akcija = JEDAN undo step
- Drag operacije: state na mouse-down, commit na mouse-up = jedan entry
- Logic ima SEPARATE undo stacks za arrangement/mixer/plugin

**FluxForge:** Implementirati jedan undo entry po drag operaciji, ne po frame-u.

### Clip Gain — Signal Path
Clip gain je PRE-fader, PRE-automation u oba DAW-a. Volume handle drag treba snap na 0dB (unity) kao magnetni punkt.

---

## 8. ARHITEKTURNE NAPOMENE

### Tool Action Flow
```
User Click/Drag
  → clip_widget.dart (Listener.onPointerDown)
    → SmartToolProvider.hitTest() → determines zone/mode
    → clip_widget delegates to appropriate callback:
       onClipMove, onClipResize, onClipFadeChange, onClipSplit...
        → track_lane.dart forwards
          → timeline.dart forwards
            → engine_connected_layout.dart → FFI call
```

### Gde dodati tool-specific logiku
- **clip_widget.dart** — za klikove UNUTAR klipa (erase, mute, volume drag)
- **track_lane.dart** — za klikove IZMEĐU klipova (crossfade kreiranje)
- **timeline.dart** — za klikove VAN klipova (range select, play tool, zoom)
- **engine_connected_layout.dart** — za FFI pozive i undo action kreiranje

### Pravilo: NE menjati SmartToolProvider
SmartToolProvider je čist — samo state i hit testing. Tool AKCIJE idu u widget layer.

### Verifikovani Tool Dispatch Putevi (tačne linije)

```
TOOL CLICK NA KLIPU:
  clip_widget.dart:437-440 → proverava activeTool
  clip_widget.dart:510     → switch(activeTool) {
    :511-526  split     → onSplitAtPosition(clickTime) ili onSplit()
    :527-532  erase     → onDelete() [locked check]
    :533-536  mute      → onMute()
    :537-540  glue      → onSelect() [STUB — nema join]
    :541-544  zoom      → return [STUB — prazan]
    :545-549  play      → onPlayheadMove(clickTime)
    :551      draw      → falls through to select
  }

TOOL CLICK U PRAZNOM PROSTORU:
  timeline.dart:965-1006 → _handleTimelineClick → switch(activeTool) {
    :977  zoom → zoom in/out
    :985  play → move playhead + toggle play
    :991  split → move playhead
  }

SMART TOOL DRAG (9 zona):
  clip_widget.dart:622-687 → switch(smartToolMode) {
    :635-642  fadeIn/fadeOut     → _isDraggingFade = true
    :643-647  volumeHandle      → _isDraggingVolumeHandle = true
    :648-655  timeStretch       → _isDraggingTimeStretch = true
    :615-619  select+Alt+Shift  → _isSlipEditing = true
    :665-675  rangeSelectBody   → Ctrl: scrub, else: STUB
    :676-680  slipContent       → _isSlipEditing = true
  }

KEYBOARD SHORTCUTS:
  timeline.dart:1632-1655 → digit1-digit0 → setActiveTool()
  main_layout.dart:555-560 → F1-F5 → setActiveEditMode() (Shuffle/Slip/Spot/Grid/X-Fade)

FFI CHAIN:
  clip_widget → track_lane → timeline → engine_connected_layout → engine_api → native_ffi → Rust
```

### Ključni FFI — Stanje Rust ↔ Dart bindinga

| FFI Funkcija | Rust (ffi.rs) | Dart Binding (native_ffi.dart) | Koristi se? |
|-------------|--------------|-------------------------------|-------------|
| `edit_mode_set()` | ✅ L8587, čuva u EDIT_CONTEXT | ✅ `editModeSet()` L8174 | ✅ `EditModeProProvider:419` poziva ga |
| `razor_add_area()` | ✅ | ✅ `razorAddArea()` | ✅ RazorEditProvider |
| `razor_delete/cut/copy/split()` | ✅ | ✅ `razorDelete/Cut/Copy/Split()` | ✅ RazorEditProvider.executeAction() |
| `razor_move/reverse/stretch/dup()` | ✅ | ✅ `razorMove/Reverse/Stretch/Duplicate()` | ✅ RazorEditProvider |
| `razor_mute/join/fadeBoth()` | ✅ | ✅ `razorMute/Join/FadeBoth()` | ✅ RazorEditProvider.executeAction() |
| `razor_healSeparation/insertSilence/stripSilence()` | ✅ | ✅ Dart bindings | ✅ RazorEditProvider |
| `razor_paste()` | ✅ | ✅ `razorPaste()` | ✅ RazorEditProvider (clipboard JSON) |
| `clip_envelope_*()` | ✅ | ✅ `clipEnvelope*()` | ✅ ClipEnvelopeFFI extension |
| `clip_fade_in/out()` curveType | ✅ | ✅ Binding postoji | ✅ engine_connected_layout wiring |
| `createCrossfade()` | ✅ | ✅ Binding postoji | ✅ auto-crossfade + curve wiring |
| `bounceStart()` | ✅ | ✅ Binding postoji | ✅ Koristi se za export |

**ZAKLJUČAK (ažurirano 2026-04-21):** Svih 22+ Razor FFI funkcija sada imaju kompletne Dart bindinge i wirovani su kroz RazorEditProvider.executeAction(). Preostale 2 akcije bez FFI (bounce, process) zahtevaju posebne pipeline-ove (DOP dijalog, offline render engine). Crossfade curve i clip fade curve wirovani kroz TrackLane→Timeline→engine_connected_layout. Clip envelope FFI bindinge kompletne.
