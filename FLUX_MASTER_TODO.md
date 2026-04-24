# FluxForge Studio — MASTER TODO
> Poslednje ažuriranje: 2026-04-24 | Branch: fix/ci-infra

---

## 🧿 ZAKON — CORTEX OČI I RUKE (UVEK, BEZ IZUZETKA)

> **Nikad macOS. Uvek Cortex.**
> Pre svakog izveštaja: CortexEye snap → CortexHands interakcija → tek onda govorim Boki-ju.
> Boki ne testira. Boki ne klikće. Boki ne gleda. JA gledam. JA klikćem. JA verifikujem.

  GET  http://localhost:26200/eye/snap       - screenshot
  GET  http://localhost:26200/eye/logs       - flutter logs  
  GET  http://localhost:26200/eye/inspect    - widget tree
  POST http://localhost:26200/hands/tap      - klik
  POST http://localhost:26200/hands/input    - unos teksta
  POST http://localhost:26200/hands/swipe    - swipe

---

## ODMAH - Nekomitovani rad (7 fajlova u working tree)

  1  Orb van kartice (standalone, bez Card wrapper-a)         [OK] CortexEye snap verifikovano
  2  Single click kanal = auto-solo (master pattern)          [OK] CortexHands 8/8 state testova pass
  3  Double-tap kanal → VoiceDetailEditor dialog              [!!] BuildContext — treba CortexHands verify
  4  Long-press kanal → Radial dial (4 opcije)                [!!] BuildContext — treba CortexHands verify
  5  CortexEye /eye/voice diagnostic endpoint                 [OK] verifikovano kroz HTTP

Akcija: CortexEye snap MIX tab → CortexHands double-tap + long-press verify → commit

---

## VISOKI PRIORITET — Slot Machine

S1 · Feature Wins završni momenti (verifikacija)
  Urađeno:   FsSummary + UiSkipPress stage-ovi — commit 2b539a0e
  Nedostaje: CortexEye verifikacija da UI overlay triggeruje na FS exit + skip telemetry log
  Fajlovi:   flutter_ui/lib/models/stage_models.dart
             flutter_ui/lib/services/stage_audio_mapper.dart
             crates/rf-stage/src/audio_naming.rs

S2 · Splash → Slot animacija (profi, kinematska)  [BOKI EKSPLICITNO TRAŽIO]
  Šta:    Posle ENTER na splash strani — izuzetno lepa profi slot animacija pre ulaska u SlotLab
  Stil:   IGT/Aristocrat nivo — reel spin-up intro, zlatni sjaj, simboli padaju na mesto,
          dramatski šum → tišina
  Fajlovi: flutter_ui/lib/screens/splash_screen.dart
           flutter_ui/lib/screens/slot_lab_screen.dart

S3 · Reel Loop + Reel Stop audio events
  Šta:      sfx_reel_spin_r0..r5 (loop) i sfx_reel_stop_r0..r5 (stinger) — wire-up u engine
  Referenca: FFNC SPIN CORE sekcija — definicije postoje, integracija nedostaje
  Fajlovi:  crates/rf-stage/src/audio_naming.rs
            flutter_ui/lib/services/stage_audio_mapper.dart
            flutter_ui/lib/screens/slot_lab_screen.dart

S4 · Audio tab Helix lower zone — bug verifikacija
  Šta:    Ranije prijavljeno "ništa se ne prikazuje" u audio tabu
  Akcija: CortexEye snap Helix audio tab → debug → fix
  Fajlovi: flutter_ui/lib/widgets/helix/helix_lower_zone.dart

---

## SREDNJI PRIORITET — OrbMixer

O1 · OrbMixer Phase 10e-2 — Rust FFI ring buffer + WAV export
  Šta:    5s master ring buffer u Rust, WAV export iz Problems Inbox replay
  Fajlovi: crates/rf-bridge/src/orb_mixer_ffi.rs
           flutter_ui/lib/providers/orb_mixer_provider.dart

O2 · OrbMixer per-bus FFT (Phase 10 polish)
  Šta:    Per-bus FFT za precizniji masking + isolate za ghost buffer >100 voices
  Fajlovi: crates/rf-bridge/src/orb_mixer_ffi.rs
           flutter_ui/lib/widgets/slot_lab/orb_mixer_painter.dart

O3 · Orb stabilnost — nestaje kada se menja kanal
  Šta:    Orb se gasi/nestaje kada se zadrži kanal ili promeni selekcija
  Akcija: CortexEye watch orb tokom channel switch → provider state log → fix

---

## SREDNJI PRIORITET — NeuralBindOrb

N1 · NeuralBindOrb Phase 2 — Ghost slot indikatori
  Šta:    Stage-ovi bez audio bindinga prikazuju se kao ghost slots u Orbu
  Fajl:   flutter_ui/lib/widgets/slot_lab/neural_bind_orb.dart  (JEDINI PREOSTALI)
  Logika: SonicDNA::PlacementSolver gap list → feed ghost list → orb ring vizualizacija

---

## NIZAK PRIORITET — Polish & Build

P1 · Podnaslovi podtabova razlikuju se od naslova
  Fajlovi: flutter_ui/lib/widgets/helix/helix_lower_zone.dart

P2 · Full Build + CI Checkpoint
  cargo build --release
  xcodebuild -workspace flutter_ui/macos/Runner.xcworkspace -scheme Runner -configuration Release build
  flutter analyze → 0 errors
  cargo test --workspace → sve pass

P3 · BUG #66 — Room Simulator only first-order reflections
  Feature request (ne bug) — higher-order image source model
  Fajlovi: crates/rf-dsp/src/eq_room.rs
  PRIORITET: Najniži — kad je sve ostalo gotovo

---

## GOTOVO (referenca)

  2026-04-24  Casino Vault brand paleta (5 fajlova)              commit: 2917ae33
  2026-04-24  FsSummary + UiSkipPress stages + skip telemetry    commit: 2b539a0e
  2026-04-24  AnticipationConfig wire-up (sekvencijalna antici.) commit: e7bca3a8
  2026-04-22  Slot Flow IGT Parity — Talas 1/2/3                 commit: 1a3b2af7 3b563438 47d18a27
  2026-04-22  OrbMixer Phase 6-10e (9 commits, 2153 LOC)         višestruki
  2026-04-22  Sonic DNA Classifier Layer 2+3 + FFI + Dart
  2026-04-22  Cortex Eye automation infrastruktura
  2026-04-21  84/84 QA bagova rešeno
  2026-04-21  HELIX Auto-Bind QA + Redesign
  2026-04-21  NeuralBindOrb instant binding
  2026-04-21  CORTEX Organism refaktor

---

## ARHITEKTURA — Ključni fajlovi

  SlotLab ekran          flutter_ui/lib/screens/slot_lab_screen.dart
  OrbMixer widget        flutter_ui/lib/widgets/slot_lab/orb_mixer.dart
  OrbMixer painter       flutter_ui/lib/widgets/slot_lab/orb_mixer_painter.dart
  OrbMixer provider      flutter_ui/lib/providers/orb_mixer_provider.dart
  NeuralBindOrb          flutter_ui/lib/widgets/slot_lab/neural_bind_orb.dart
  Stage audio naming     crates/rf-stage/src/audio_naming.rs
  Stage audio mapper     flutter_ui/lib/services/stage_audio_mapper.dart
  Game flow FSM          flutter_ui/lib/providers/game_flow_provider.dart
  Voice mixer            flutter_ui/lib/widgets/slot_lab/slot_voice_mixer.dart
  Premium slot preview   flutter_ui/lib/widgets/slot_lab/premium_slot_preview.dart
  Orb mixer FFI          crates/rf-bridge/src/orb_mixer_ffi.rs
  Helix lower zone       flutter_ui/lib/widgets/helix/helix_lower_zone.dart
  Theme                  flutter_ui/lib/theme/fluxforge_theme.dart

---

## REDOSLED

  1  ODMAH       Commit nekomitovani rad (#1-5)
  2  VISOKI      S1 Feature wins verifikacija (CortexEye verify)
  3  VISOKI      S2 Splash → Slot animacija (Boki eksplicitno tražio)
  4  VISOKI      S3 Reel loop/stop audio wire-up
  5  VISOKI      S4 Audio tab Helix verifikacija
  6  SREDNJI     O1 OrbMixer ring buffer + WAV export
  7  SREDNJI     O3 Orb stabilnost (kanal switch)
  8  SREDNJI     N1 NeuralBindOrb ghost slots (poslednji DNA layer)
  9  NIZAK       P2 Full build CI checkpoint
  10 NIZAK       P3 BUG #66
