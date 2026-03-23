# FluxForge Studio — MASTER TODO

## Active Traps

- `slot_lab_screen.dart` — 13K+, NE MOŽE se razbiti
- Audio thread: NULA alokacija, NULA lockova

---

## PENDING: SlotLab Voice Mixer (Per-Layer Mixer)

**Spec:** `.claude/architecture/SLOTLAB_VOICE_MIXER.md`

Per-layer mixer za SlotLab — svaki assignovani zvuk ima permanentni fader strip.
Kanali se auto-kreiraju kad se audio assignuje na event, nestaju kad se ukloni.
Meteri se pale kad voice svira. Full DAW kvalitet: fader, pan, M/S, insert chain, metering.

### Faze

- [ ] **F1: SlotVoiceMixerProvider** — model, rebuild iz composite events, bidirekcioni sync (volume/pan/mute → real-time FFI + composite update), voice mapping 30fps, approximate metering
- [ ] **F2: SlotVoiceMixer widget** — per-channel strip (header, inserts, pan, fader, stereo meter, dB, M/S, bus label), bus group separators, master strip, activity indicators
- [ ] **F3: MIX tab integracija** — dodaj `voices` sub-tab (Q shortcut, prvi/default), wire u slotlab_lower_zone_widget.dart
- [ ] **F4: Per-voice metering** — approximate bus peak * voice volume ratio, peak hold 1500ms decay
- [ ] **F5: Smart features** — audition (click header = preview), snapshot save/load, solo-in-context, batch ops (ctrl+multi-select), search/filter
- [ ] **F6: Real Rust metering** (opciono) — AtomicF64 per voice u playback.rs, FFI getVoicePeakStereo

### Novi fajlovi
- `flutter_ui/lib/providers/slot_lab/slot_voice_mixer_provider.dart`
- `flutter_ui/lib/widgets/slot_lab/slot_voice_mixer.dart`

### Modifikacije
- `lower_zone_types.dart` — `voices` u SlotLabMixSubTab enum
- `slotlab_lower_zone_widget.dart` — wire voices sub-tab
- `service_locator.dart` — register provider kao GetIt singleton
- `main.dart` — expose ChangeNotifierProvider.value()

### KRITIČNO: NE mešati sa DAW mixerom
- DAW = MixerProvider + UltimateMixer (per-track, timeline)
- SlotLab = SlotVoiceMixerProvider + SlotVoiceMixer (per-layer, events)
- Deljeno samo: MixerDSPProvider (bus control) + SharedMeterReader (metering)

---

## IMPLEMENTIRANO (cele 2 sesije)

- **37 crate-ova** | **69 providera** | **170+ servisa** | **3500+ networking linija**
- Signalsmith Stretch (audio_stretcher.rs, MIT ~Élastique)
- Warp Markers (15 testova, end-to-end: model→detection→playback→UI→undo)
- Custom Events (EventRegistry sync, Play, probability, solo, zombie cleanup)
- RTPC (35 params, 9 curves, macros, DSP binding — VEĆ POSTOJEĆI)
- Server Audio Bridge (trigger/rtpc/state/batch/snapshot + jitter + circuit breaker)
- MIDI Trigger (note→event, CC→RTPC, learn mode, live buffer)
- OSC Trigger (rosc crate, UDP server, address→event/RTPC)
- TriggerManager (position, marker, cooldown, seek hysteresis)
- Mock Game Server (echo/auto mode, slot cycle simulation)
- Connection Monitor Panel (bridge/MIDI/OSC stats)
- Dep Upgrade Faza 3+4 (cpal 0.17, wgpu 28, objc2 0.6, Edition 2024)
- 22 QA rundi, 70+ bugova, 447 testova, 0 issues
