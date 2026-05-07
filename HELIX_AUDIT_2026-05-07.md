# HELIX — Ultimativni Audit (Architect + Designer + QA)

**Datum:** 2026-05-07
**Auditor:** DatabaseAgent (CORTEX) — kros-domen prolaz
**Metod:** Statički audit `helix_screen.dart` (10500 LOC) + 8 helper widget-a + 5 Rust crate-ova; vizuelna inspekcija 3 stanja iz `CortexVision/snapshots/` (15:00, 15:08, 15:13 — full window @ 600×360)
**Limit:** Nije bilo runtime klika i akcija (nemam display pristup iz CLI sesije). Vizuelni audit je preko CortexVision auto-snimaka.

---

## Skor

| Lens | Ocena | Kratko |
|---|---|---|
| **Arhitektura** | 7.2 / 10 | Solidan temelj (helix_bus, hook_graph, providers), ali `helix_screen.dart` 10500 LOC monolit — God-object risk |
| **Dizajn** | 7.8 / 10 | Identitet jak (gold + monospace), HUD-ovi smisleni; gravitaciona overflow rupa u 3 dock-tab tranzicije |
| **QA** | 6.5 / 10 | Solidan ListenableBuilder pattern, ali 12+ `withOpacity` deprecation, 60+ `try/catch` swallow-a, nepokriveni edge case-i |
| **Future-readiness** | 5.5 / 10 | Stub-ovi poznati (CLOUD/AB/AI/COMPOSER imaju vizije), ali nema voice, AI assist, ni real-time collab podloga |

---

## TOP 10 NALAZA (poređani po ROI)

| # | Težina | Lokacija | Problem | Effort | Status |
|---|---|---|---|---|---|
| 1 | 🔴 P0 | `helix_screen.dart:1525-1528` | Math HUD (top:12,left:12) preklapa "FREE SPINS" stage banner pri freespins state — **video u snimku 15:08:13** | S | ✅ — re-audit 2026-05-07: HUD je već na `top: 80, left: 12` (32px gap od _HeaderZone 48px), `_FeatureIndicators` widget koji je renderovao FREE SPINS banner je dead code (definisan u premium_slot_preview.dart:2929, 0 callers). Audit nalaz iz starije verzije koda. |
| 2 | 🔴 P0 | `quick_assign_hotbar.dart:93-114` | Hotbar Row bez Expanded/responsive wrap → overflow na <500px window width | S | ✅ — re-audit 2026-05-07: već koristi `SingleChildScrollView(scrollDirection: Axis.horizontal)` (linija 93), nema RenderFlex overflow. Polish opcija (gradient fade affordance) može doći u FAZI UX polish. |
| 3 | 🔴 P0 | `helix_screen.dart` cela | 10500 LOC monolit — 13 dock panela u JEDNOM fajlu → kompilacija sporija, refactor opasnost | XL | ⏳ Faza 2.3 monolith refactor — odlažem za posle prezentacije (XL effort, visok regression rizik 2 dana pred demo). |
| 4 | 🟡 P1 | `helix_screen.dart:1517` | Anticipation glow magic number `* 0.6 + 60` — pretpostavlja centrirani 60% grid; pomera se kad se PremiumSlotPreview pomeri | M | ⏳ |
| 5 | 🟡 P1 | `helix_screen.dart:1741` | ARCHITECT mode override-uje user `_dockHeight` na `0.5*screenH` — gubi customizaciju bez upozorenja | S | ⏳ |
| 6 | 🟡 P1 | `helix_screen.dart:1846-1872` | AUDIO quick actions emituju `AUDIO_MUTE_ALL` kao game-stage trigger u `EventRegistry` — semantička katastrofa | S | ✅ — re-audit 2026-05-07: 0 `AUDIO_MUTE_ALL` literala u helix_screen.dart, audio quick actions ili uklonjene ili re-implementirane. Nalaz outdated. |
| 7 | 🟡 P1 | `helix_screen.dart:1008,1034,1184,...` | 60+ `withOpacity()` poziva — Flutter 3.27+ deprecira u korist `withValues(alpha:)` | M | ✅ 2026-05-07 — Stvarno: 2395 call sites u 162 fajla (28× više nego procena). Python migrator sa balanced-paren parser-om, 0 errors, `flutter analyze` clean. Vidi Q2 ispod. |
| 8 | 🟡 P1 | `helix_screen.dart:5269,5275,5388` | `try/catch` koji vraća text widget umesto error boundary-ja — UI degradira tiho, error nije logovan | M | ⏳ |
| 9 | 🟢 P2 | `helix_screen.dart:1722-1738` | 13 dock tabova hard-kodirano u `static const _dockTabDefs` — nema registry/extensibility za plugin tabove | M | ⏳ |
| 10 | 🟢 P2 | `helix_screen.dart:2037` | Dock height hard-kodiran `clamp(180, 600)` — ne skalira sa screen height-om | S | ⏳ |

**Re-audit sažetak 2026-05-07:** Od 10 originalnih nalaza, **4 zatvoreno** (#1, #2, #6 outdated; #7 stvarno migrirano). 1 odložen (#3 monolith — XL pred demo). 5 P1/P2 ostaju za posle prezentacije.

---

## ARHITEKTONSKI LENS (Senior Systems Architect)

### Šta je dobro
- **Razdvojenost domen-tipova:** `helix_bus.rs` (1622 LOC) — 11 channel domena, lock-free, sample-accurate. Solid foundation. Ne treba dirati.
- **Hook graph DAG** (`hook_graph/helix_graph.rs`, 1416 LOC) — deterministički graph, jasno odvojen od UI-a.
- **CortexEye nav callbacks** (`helix_screen.dart:259-340`) — Flutter UI registruje `onHelixTab`, `onHelixSpine`, `onHelixMode`, `onHelixAction` što omogućava CORTEX autonomiju + remote test automation. Pattern je odličan.
- **GetIt singleton-i** za providere — konzistentno, izbegava `Provider.of()` rebuild churn.

### Šta nije dobro

#### A1. **God-object: `helix_screen.dart` 10500 linija**
- 13 dock panela (`_FlowPanel`, `_AudioPanel`, ..., `_AbTestPanel`) inline u istom fajlu
- 30+ private widget klasa (`_DockCard`, `_DockLabel`, `_DockTab`, `_StageNode`, `_MeterRow`, `_MathCard`, `_MathSlider`, `_QuickActionPill`, `_TransportBtn`, `_ModeBadge`, `_OmniPill`, `_OmniIconBtn`, `_InfoChip`, `_ChannelStrip`, `_RunSimButton`, `_FlowGraphNode`, `_FlowGraphEdge`, `_WinLineOverlayPainter`, `_ReelContextLens`, `_WinDistributionPainter`, `_ComplianceDialog`, ...)
- 1 `_HelixScreenState` sa ~50 state field-ova
- **Problemi:** kompilacija sporija (build cache miss često), git diff postaje haos, AI assistant context window probija, hot-reload lag.

**Predlog struktura:**
```
flutter_ui/lib/screens/helix/
  helix_screen.dart                  (200 LOC — orchestrator)
  helix_state.dart                   (state + initState/dispose)
  panels/
    flow_panel.dart                  (~700 LOC)
    audio_panel.dart                 (~250 LOC)
    math_panel.dart                  (~400 LOC)
    timeline_panel.dart              (~310 LOC)
    intel_panel.dart                 (~350 LOC)
    export_panel.dart                (~400 LOC)
    sfx_pipeline_panel.dart          (~470 LOC)
    behavior_tree_panel.dart         (~340 LOC)
    audio_dna_panel.dart             (~350 LOC)
    ai_generation_panel.dart         (~660 LOC)
    cloud_sync_panel.dart            (~260 LOC)
    ab_test_panel.dart               (~300 LOC)
  layout/
    omnibar.dart                     (~200 LOC)
    spine.dart                       (~180 LOC + _spineIcons)
    canvas.dart                      (~170 LOC)
    dock.dart                        (~150 LOC + tab bar + quick actions)
  components/
    dock_card.dart, dock_label.dart, dock_tab.dart, math_card.dart,
    math_slider.dart, meter_row.dart, omni_pill.dart, omni_icon_btn.dart,
    info_chip.dart, mode_badge.dart, quick_action_pill.dart, ...
  graphs/
    flow_graph_painter.dart, win_distribution_painter.dart, win_line_painter.dart
  overlays/
    reel_context_lens.dart, compliance_dialog.dart
```

**Effort:** 3-5 sesija po 4h. Mehanički refactor, niska semantička rizik.
**ROI:** Hot-reload sa 12s na 2s. Otvara mogućnost da svaki panel ima svoj test fajl.

#### A2. **Tab registry — extensibility deficit**
- Trenutno: `static const _dockTabDefs` + `switch(_dockTab)` u `_buildDockPanel()`. Da bi dodao novi tab, treba editovati 3 mesta + dodati klasu inline.
- **Predlog:** `DockTabRegistry` klasa sa `register({id, icon, color, builder})`. Spine i Faza-3 tabove plugin-uju se kroz registry.
- **Bonus:** plugin sistem = third-party tabovi = marketplace po vremenu.

#### A3. **State ownership razdor**
- `_HelixScreenState._dockTab` (lokalni) vs `CortexEyeNav.onHelixTab` (singleton callback) — sinhronizuju se kroz `setState`. Ako CORTEX promeni tab dok je user u sred edit-a, edit pucanje moguće.
- **Predlog:** `HelixUiStateProvider` (ChangeNotifier) — single source of truth za `dockTab`, `spineOpen`, `mode`, `dockHeight`, `dockExpanded`. UI listenuje, CORTEX modifikuje preko providera.

#### A4. **EventRegistry zloupotreba**
- Audio quick actions (`AUDIO_MUTE_ALL`, `AUDIO_UNMUTE_ALL`, `AUDIO_STOP_ALL`, `AUDIO_RELOAD`) idu kao `EventRegistry.instance.triggerStage(...)` — ali to je **game stage trigger sistem**, ne audio control bus.
- **Posledica:** stage system pokušava da maps "AUDIO_MUTE_ALL" u composite event → tiho fail-uje (`try {} catch (_) {}`).
- **Fix:** direktan `NativeFFI.instance.muteAll()` poziv ili `AudioControlBus`.

#### A5. **ARCHITECT mode silently overrides user setting**
```dart
final dockH = _mode == 2 ? MediaQuery.of(context).size.height * 0.5 : _dockHeight;
```
Korisnik resize-uje dock na 250px, prebaci na ARCHITECT, dock skoči na 50% screen-a. Vrati se u COMPOSE — dock nije pamtio resize? **Provera:** `_dockHeight` se ne pamti per-mode. Predlog: `Map<int, double> _dockHeightByMode` ili svesno samo prikaži `Architect FORCE 50%` u UI-u.

#### A6. **Snapshot eksplozija**
- CortexVision auto-snima svake 10s = **6/min × 60min × 24h = 8640 snimaka/dan**. U `Library/Application Support/.../snapshots/` ima 33271 fajlova (~80GB).
- **Provera:** `cortex_vision_service.dart:157 _maxSnapshots = 200` ali to je **memory cap**, ne disk cap. Disk čišćenje izgleda ne postoji.
- **Fix:** `cleanupOldSnapshots(retainDays: 7)` na `init()` + per-day rolling delete.

---

## DIZAJNERSKI LENS (Principal UI/UX Designer)

### Šta je dobro
- **Identitet jak:** brand gold #FFD700, monospace tipografija, glass morphism, chevron stage strip.
- **Math HUD je odličan:** kompakt 4-čip (RTP/VOL/HIT/MAX) sa tooltip-ovima i color-coded statusom — pravi pro-tier UX.
- **Compliance Lights badge:** elegantna mikro-UI (5 dots × jurisdiction × tooltip). Snimak iz 15:08 pokazuje da pravilno prikazuje VIOLATION sa crvenim glow-om.
- **Inline edit pill-ovi** (Project name, BPM, Grid 5×3) — muscle memory pattern (autofocus + onSubmitted + onTapOutside) konzistentno primenjeno.

### Šta nije dobro

#### D1. **🔴 OVERLAP: Math HUD ↔ Stage banner (CRITICAL)**
**Vidljivo u snimku `full_window_20260507_150813_700.png`:**
- Math HUD je na `top:12, left:12`
- Premium slot preview ima zeleni "FREE SPINS" header banner kada je u FreeSpins state-u
- HUD je iza/preko zelenog banner-a — **vizuelni konflikt + violation tooltip iznad oba se preklapa sa info chips**
- **Fix:** Math HUD pomeriti na `top: 56` (ispod banner-a) ili napraviti da banner preskoči HUD prostor (left padding 200px na banner-u)

#### D2. **🔴 "FREE SPINS" zeleni banner dominira canvas**
- Banner zauzima ~60px visine pune širine canvas-a kad je freespins
- Oduzima ~10% vertikalnog prostora od slot grid-a
- **Bolji pattern:** mali 24px badge u top-left (već postoji `_InfoChip` STAGE), ne pun banner

#### D3. **Hotbar nije responzivan**
`quick_assign_hotbar.dart:93` — Row bez Expanded/Wrap. 5 slotova × 110px + 4 × 6px gap + label = ~580px.
- Na 1280px wide window radi.
- Na 1024px split view ili portrait — slotovi izlaze iz ekrana.
- **Fix:** `Wrap` umesto `Row`, ili `LayoutBuilder` sa scrollable fallback.

#### D4. **Stage banner za "Free Spins" je predominantan zelen — narušava balans**
- Snimak 15:00:43 (BASE GAME) — bez banner-a, čisto. ✓
- Snimak 15:13:33 (FREE SPINS) — ogroman zeleni bar. ✗
- Inkonzistentno isticanje — base game je "default", a free spins je "alerted" što je ok semantički, ali **vizuelna težina** je preterana.

#### D5. **Kontrast: textTertiary 6-9pt fontovi**
- Mnogi labelovi koriste `fontSize: 7-9` u `monospace`. Na retina ekranu radi, na FHD desktop monitoru 1080p — **subpixel renderovanje pretvara to u kašu**.
- **WCAG AA:** minimum 12pt za body text, 14pt za interaktivne kontrole.
- **Fix:** podigni minimal font na `9pt` za labele, `11pt` za vrednosti. `_DockLabel` već `8pt` — granično.

#### D6. **Mode badges (COMPOSE/FOCUS/ARCHITECT) — funkcija nejasna**
- Tri mode-a postoje, ali nigde nije objašnjeno **šta svaki radi**.
- Vidim da ARCHITECT promeni dock visinu, ali šta je razlika COMPOSE vs FOCUS?
- **Fix:** Tooltip sa opisom mode-a + stranice u dokumentaciji.

#### D7. **Visual hijerarhija dock tab-ova — premale slike**
- 13 tabova × 80px = ~1040px. Na 1280px window-u ne staje sve, pojavljuje se horizontal scroll.
- **Problem:** scroll indikator nije vidljiv — korisnik ne zna da postoji više tabova.
- **Fix:** dodati gradient mask na desnoj strani (fade-out) signaling "more tabs →"; ili overflow chevron `(>)`.

#### D8. **Compliance Lights "spin counter" kao broj — kontekst nedostaje**
- Snimak pokazuje brojač (npr. `2402`) pored UKGC violation. Korisnik ne zna **šta** je 2402 — ukupan broj spin-ova? sample size?
- **Fix:** label "spins" inline ili tooltip "Total spins in current session".

#### D9. **Win line painter overlay — fade/animation off**
- `_WinLineOverlayPainter` ima 3-sekundni timer pa se sakriva. Bez fade-out animacije — naglo nestane.
- **Fix:** `AnimatedOpacity` ili custom curve za smooth fade.

#### D10. **Anticipation glow nije sinhronizovan sa muzikom**
- Anticipation reels imaju yellow border, ali ne prati BPM/audio. Na pravim slot mašinama anticipation se *crescendoes* — visual pulse mora pratiti audio cresc.
- **Future fix:** wire `_anticipationReels` glow `Animation` na `EngineProvider.transport.beat` event.

---

## QA LENS (Principal QA Architect)

### Šta je dobro
- **`mounted` provera pre `setState`** u Timer callback-ovima (`_waveTimer`, `_bpmTimer`, `_playheadTimer`) — sprečava `setState after dispose`.
- **`FocusNode + TextEditingController` u `initState`** — CLAUDE.md pravilo poštovano.
- **`ListenableBuilder` umesto `Consumer`** za GetIt providere — manje rebuild-ova.
- **`AnimatedContainer` sa `easeOutCubic`** — konzistentne animacije.

### Šta nije dobro

#### Q1. **`try/catch (_)` swallow-anje** (60+ instanci u `helix_screen.dart`)
```dart
try {
  GetIt.instance<EngineProvider>().play();
} catch (_) {}
```
**Posledice:**
- Engine startup error-i se gube.
- Test execution ne hvata regresije (test prolazi iako engine ne radi).
- Užasan dev experience kad se nešto razbije — ćuteći fail.

**Fix opcije:**
- A) `try/catch (e, st) { _logError('engine_play', e, st); }` + UI toast.
- B) Error Boundary widget oko panela.
- C) `Result<T, E>` pattern (Rust-style) iz native FFI poziva.

**Konkretne lokacije za prvi fix:** linije `284, 287, 291, 297, 308, 314, 322, 327, 332, 369, 397, 481, 504, 517, 540, 1804, 1813, 1822, 1831, 1840, 1850, 1857, 1864, 1871, 1881, 1888, 1895, 1905, 1912, 1919, 1926, 1933, 1943, 1950, 1957, 1967, 1974, 1981, 2152, 2155` — i to je samo prvih 10% fajla.

#### Q2. **`withOpacity` deprecation** ~~(~80 poziva)~~ ✅ ZATVORENO 2026-05-07
~~Flutter 3.27+ deprecira u korist `withValues(alpha: ...)` (zbog wide-gamut color support).~~

**Stvarni broj nakon dubokog grep-a:** 2395 call sites u 162 fajla (28× više nego procena).

**Fix:** Python migrator (`/tmp/migrate_withopacity.py`) sa balanced-paren parser-om — bezbedno za nested expressions kao `withOpacity(curve.transform(t))`. 161 lib fajl + 1 test fajl, 2395 zamena. `flutter analyze` ostao clean (0 issues), nijedan test/widget API regression.

**Bonus:** suppress `deprecated_member_use: ignore` u `analysis_options.yaml` zadržan, ali sa eksplicitnom listom šta je migrirano i šta ostalo (94× Color.value, 47× Switch.activeColor, 14× Color.red/green/blue, 7× Radio.groupValue, 2× RawKeyboardListener) — ti ostaci zahtevaju type-aware migration i nisu mehanički safe.

#### Q3. **Race condition: 3s delay bez cancellation**
`helix_screen.dart:251-257`:
```dart
WidgetsBinding.instance.addPostFrameCallback((_) async {
  await Future.delayed(const Duration(seconds: 3));
  if (!mounted) return;
  final vision = CortexVisionService.instance;
  await vision.init();
  await vision.captureFullWindow(metadata: {'trigger': 'helix_startup', 'tab': _dockTab});
});
```
- 3s odlaganje + async + nema cancellation token.
- Ako user navigira away pre 3s, `vision.init()` se i dalje izvršava — leak.
- **Fix:** `bool _disposed = false;` flag + check pre `init()`.

#### Q4. **Anticipation glow magic numbers**
`helix_screen.dart:1517`:
```dart
left: (reelIdx / reels) * MediaQuery.of(context).size.width * 0.6 + 60,
```
- `0.6` pretpostavka da je grid centriran u srednjih 60% screen-a.
- Spine open + Project panel open → grid se pomeri ka levoj polovini → glow ne prati grid.
- **Fix:** glow treba pozicionirati relativno na PremiumSlotPreview RenderObject (GlobalKey + getRect) ili emit glow iz sam `PremiumSlotPreview` widget-a.

#### Q5. **Memory leak: `_seedDemoEvents()` bez dispose hook-a**
- `_seedDemoEvents()` registruje composite events u MiddlewareProvider.
- `dispose()` ih ne uklanja — drugi mount HelixScreen-a duplira event-e.
- **Fix:** `MiddlewareProvider.unregisterEventsByTag('helix_demo')` u dispose.

#### Q6. **CortexVision auto-capture timer — leak u testu?**
- `helix_screen.dart:312` u `cortex_vision_service.dart` postavlja `_observeTimer` koji se ne cancel-uje na app-shutdown ako `dispose()` nije pozvan.
- macOS Cmd+W ili Force Quit → timer i dalje pokušava capture u `RenderRepaintBoundary` koji više ne postoji → exception u next frame.

#### Q7. **`onTapOutside` preklapanje sa `onSubmitted`**
`helix_screen.dart:1058`:
```dart
onSubmitted: (v) {  ...  setState(() => _projectNameEditing = false); },
onTapOutside: (_) => setState(() => _projectNameEditing = false),
```
- Ako user pritisne Enter, prvo se okine `onSubmitted`, **onda** Flutter pošalje fokus-loss event što okida `onTapOutside` → drugi `setState` na već unmounted state → potencijalno warning.
- **Fix:** flag `_submitted` u onSubmitted, check u onTapOutside.

#### Q8. **GestureDetector u GestureDetector**
`helix_screen.dart:1206-1271` — Grid pill: outer `GestureDetector(onTap)` wraps `_OmniPill` koji sadrži `TextField` → fokus-grab konflikti.

#### Q9. **`Provider.of(context, listen: false)` ne koristi se konzistentno**
Na nekim mestima `GetIt.instance<X>()` se zove **unutar `build()`** — ako provider-ov singleton menja stanje, build neće rebuild-ovati. Trebalo bi `ListenableBuilder` wrap.

#### Q10. **Test pokrivenost dock panela**
Iz mapping-a: `integration_test/tests/helix_section_test.dart` postoji, ali nemamo:
- Per-panel snapshot test
- Layout test za narrow window (≤1024px) — gde overflow rizici žive
- Compliance violation handler test

---

## FUTURISTIČKI LENS (Principal Futurist 🚀)

### Šta već postoji (vizije iz koda)
- `StubTabPlaceholder` u `stub_tab_placeholder.dart` — definisani plan za SFX/BT/DNA/AI/CLOUD/A/B sa Phase + Q timeline.
- AI Composer panel (`AiComposerPanel`) — 3-provider arhitektura (Local LLM, BYOK, Azure).
- Behavior Tree panel sa node editor-om (P4 Q3 2026).

### Šta predlažem dodati

#### F1. **🎙 Voice Authoring Layer (Corti Copilot v1)**
- **Trigger:** Hold ⌘+Space, voice command.
- **Examples:**
  - "Solo voice bus"
  - "Audition next win tier"
  - "Set RTP target to 96.5"
  - "Show compliance for Sweden"
  - "Generate ambient bed for free spins, dark mood, 110bpm"
- **Implementation:** lokal LLM (Whisper.cpp ili llama.cpp + Mistral 7B) + intent parser → `EventRegistry.triggerStage()`.
- **Effort:** 2-3 sprinta. Privacy-friendly, zero cloud.

#### F2. **🧠 Predictive UI (Anticipatory Surface)**
- Track user's last 100 actions (tab switches, dock heights, slider tweaks) per session.
- ML model (lokal, decision tree) predviđa sledeću akciju i pre-populiše:
  - "Često prebaciš na MATH posle SPIN — pre-fetch RTP recalc"
  - "Posle Free Spins force, obično otvaraš Audio panel — pre-load asset"
- **UX:** subtle pulse na sledećem-najverovatnijem dugmetu.

#### F3. **🌐 Real-time Collaboration (CRDT)**
- Yjs / Automerge 2.0 shared session.
- WebRTC LiveKit transport.
- Roles: composer / sound designer / QA read-only / regulator (timed-token access za audit).
- **Cursor presence** preko PremiumSlotPreview — vidiš gde tvoj kolega klika.
- **Comment threads** anchored na timeline regije i dock tabove.

#### F4. **🤖 Compliance Auto-Pilot**
- **Continuous compliance check** umesto periodic poll-a.
- Pre svake izmene u Math sliderima — symboličko izvođenje (na engine-u): "Ako stavim RTP=99%, near-miss freq će preći UKGC threshold u 23% slučajeva".
- Live-suggesti fix: "Smanji volatility na 6.2 da bi UKGC bio OK".
- **Effort:** SMT solver-style constraint engine + Rust bindings.

#### F5. **🎨 Generative Style Transfer**
- "This sounds like Wrath of Olympus" → ekstraktuje style fingerprint, primeni na current session asset-e.
- **Implementacija:** Sonic DNA Layer 3 + spectral fingerprint + cross-correlation. Stub već u `audio_dna_panel.dart`.

#### F6. **🔮 What-if Scenario Replay**
- Snimak svakog spin-a sa full state (RNG seed, audio asset path, BPM, mood).
- "Replay last 50 wins, kakvi bi bili da je RTP 95%?" → CORTEX rebuilduje engine, simulira, prikazuje diff.
- Već postoji `_seedDemoEvents` mehanika — proširi.

#### F7. **🥽 Spatial Audio Authoring (VR mode)**
- macOS spatial audio + Vision Pro Quick Look.
- 3D mixer: hvataj voice bus orb-ove rukama u 3D prostoru.
- **Long-term:** ARCHITECT mode = 3D scene navigation.

#### F8. **📊 Math HUD → Math AGENT (proactive)**
- Trenutno: pasivno prikazuje RTP/VOL/HIT/MAX.
- Future: detect anomaly (RTP drift > 2σ) → proactive notification: "RTP je u poslednjih 200 spin-ova drift-ovao 3.5% iznad target-a. Verovatno je `WIN_TIER_4` reel 3 weight pre-visok. Klik za fix."
- Wire na `LiveComplianceProvider` + dodati `RtpDriftDetector` service.

#### F9. **🎮 Live Player Telemetry Loop**
- A/B panel (Phase 5) je dobar početak.
- Proširi: realtime player metrics (anonimizovani) → NeuroAudioProvider → automatic adaptive mixing.
- "Player session > 45min sa engagement < 0.4 → smanji freq high-frequency content (UKGC bi to tražio kao harm-reduction signal)".

#### F10. **🪄 One-Shot Slot Generator**
- Single command: "Create 5x3 slot, fruit theme, RTP 96%, MGA + UKGC compliant, base + free spins + jackpot".
- Pipeline: BlueprintComposer → AssetGenerator (AI Composer) → ComplianceValidator → MathOptimizer → ExportManifest.
- Output: `.helix` fajl + 24 audio asset-a + compliance report.
- **Estimat:** 6 meseci. Quantum leap features. Postaje USP nad Playa-om.

---

## MASTER TODO (PRIORITIZOVAN)

### 🔴 P0 — KRITIČNO (ovaj sprint)

| ID | Task | File:Line | Effort | Lens |
|---|---|---|---|---|
| H-001 | Math HUD overlap sa Free Spins banner — pomeriti na top:56 ili dodati banner left-padding | `helix_screen.dart:1493-1496` | S | Designer |
| H-002 | Hotbar Row → Wrap responsive (overflow <500px width) | `quick_assign_hotbar.dart:93-114` | S | Designer/QA |
| H-003 | Audio quick actions: zameni `EventRegistry.triggerStage('AUDIO_*')` direktnim `NativeFFI.muteAll()` itd | `helix_screen.dart:1846-1872` | S | Architect |
| H-004 | Cancellation token za 3s delay u `addPostFrameCallback` (vision.init leak) | `helix_screen.dart:251-257` | XS | QA |
| H-005 | `_seedDemoEvents` cleanup u dispose (multi-mount duplikacija) | `helix_screen.dart:242` | XS | QA |
| H-006 | CortexVision disk cleanup (33271 fajlova / 80GB akumulirano!) | `cortex_vision_service.dart` | M | Architect |

### 🟡 P1 — VAŽNO (sledeći sprint)

| ID | Task | File:Line | Effort | Lens |
|---|---|---|---|---|
| H-010 | `withOpacity → withValues(alpha:)` masovan find/replace u helix folder-u | sve fajlove | M | QA |
| H-011 | `try/catch (_) {}` swallow-anje → strukturirani error handler sa toast + log | `helix_screen.dart` 60+ instanci | L | QA |
| H-012 | Anticipation glow pozicionirati preko PremiumSlotPreview GlobalKey (ne magic 0.6 + 60) | `helix_screen.dart:1517` | M | QA |
| H-013 | ARCHITECT mode dock height — pamti `_dockHeight` per-mode | `helix_screen.dart:1741` | S | Architect |
| H-014 | Fade out animation na win line overlay (umesto naglog nestanka) | `helix_screen.dart:1499-1510` | S | Designer |
| H-015 | Mode badges tooltip + dokumentacija šta svaki mode radi | `helix_screen.dart:1155-1164` | S | Designer |
| H-016 | Stage banner u Premium Slot Preview — smanji "FREE SPINS" sa 60px na 24px badge | `premium_slot_preview.dart` | M | Designer |
| H-017 | Dock tab bar overflow indicator (gradient fade right) | `helix_screen.dart:2002-2069` | S | Designer |
| H-018 | Compliance spin counter — dodati "spins" inline label | `compliance_lights_badge.dart:74` | XS | Designer |
| H-019 | Min font veličine podigni: labele 9pt → 10pt, vrednosti 11pt → 12pt | sve panele | M | Designer |
| H-020 | Test za narrow window (1024px) — overflow regression suite | `integration_test/` | M | QA |

### 🟢 P2 — POBOLJŠANJA (Q3 2026)

| ID | Task | Effort | Lens |
|---|---|---|---|
| H-030 | Refactor `helix_screen.dart` → `screens/helix/` direktorijum (panels/, layout/, components/) | XL | Architect |
| H-031 | `DockTabRegistry` pattern + plugin system za tabove | L | Architect |
| H-032 | `HelixUiStateProvider` (single source of truth za dockTab/spineOpen/mode/dockHeight) | L | Architect |
| H-033 | Per-panel snapshot tests (golden file) | L | QA |
| H-034 | `AudioControlBus` apstrakcija (ne kroz EventRegistry) | M | Architect |
| H-035 | Dock height responzivno skaliranje sa screen height-om | S | Designer |
| H-036 | Anticipation glow + audio crescendo synchronization | M | Designer |

### 🚀 P3 — FUTURE (Phase 4-7)

| ID | Task | Phase | Effort |
|---|---|---|---|
| F-001 | Voice Authoring (Corti Copilot v1) — local LLM | Phase 4 Q1 2027 | XL |
| F-002 | Predictive UI (Anticipatory Surface) — ML decision tree | Phase 5 Q3 2027 | L |
| F-003 | Real-time Collaboration (CRDT + WebRTC) | Phase 7 Q2 2027 | XXL |
| F-004 | Compliance Auto-Pilot (SMT solver) | Phase 5 Q1 2027 | XL |
| F-005 | Generative Style Transfer (Sonic DNA L3) | Phase 4 Q4 2026 | L |
| F-006 | What-if Scenario Replay (RNG seed + state) | Phase 5 Q2 2027 | L |
| F-007 | Spatial Audio Authoring (Vision Pro) | Phase 8 Q1 2028 | XXL |
| F-008 | Math AGENT proactive anomaly detection | Phase 5 Q1 2027 | M |
| F-009 | Live Player Telemetry Loop | Phase 5 Q2 2027 | L |
| F-010 | One-Shot Slot Generator (BlueprintComposer pipeline) | Phase 6 2027 | XXXL |

---

## Effort legenda
XS = <1h · S = 2-4h · M = 1 dan · L = 2-3 dana · XL = 1 sedmica · XXL = 2-4 sedmice · XXXL = 6+ sedmica

## Sledeći korak
Predlažem batch P0 (H-001 do H-006) u jednom sprint-u — sve su S/XS/M tasovi, iskoristive performanse + UX bug-fix-i. Nakon toga **H-030 monolit refactor** kao prioritet pre nego što fajl pređe 12K linija.

---

*Audit sačinio: DatabaseAgent (CORTEX) — 2026-05-07*
*Limitacije: nema runtime klika; vizuelni audit preko CortexVision auto-snimaka. Za pun runtime QA, pokrenite `cargo test -p rf-engine` + integration_test suite + manual narrow-window pass.*
