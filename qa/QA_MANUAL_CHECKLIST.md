# FluxForge Studio — Manual QA Checklist

> Run after every release candidate. Check each item, mark PASS/FAIL.
> Date: __________ | Build: __________ | Tester: __________

---

## 1. DAW Section

### 1.1 Transport & Playback
- [ ] **Play/Stop** — Click play, audio streams. Click stop, audio stops immediately.
- [ ] **Scrub** — Drag playhead, hear scrub audio proportional to velocity.
- [ ] **Loop** — Enable loop, playback loops between markers.
- [ ] **Record** — Arm track, press record, audio captures to new clip.
- [ ] **Punch In/Out** — Set punch markers, recording starts/stops at markers.

### 1.2 Timeline & Clips
- [ ] **Import audio** — Drag WAV/FLAC/MP3/OGG/AIFF to timeline, waveform renders.
- [ ] **Move clip** — Drag clip to new position, snaps to grid.
- [ ] **Trim clip** — Drag clip edges, clip shortens with fade.
- [ ] **Crossfade** — Overlap two clips, crossfade appears.
- [ ] **Delete clip** — Select clip, press Delete, clip removed.
- [ ] **Multi-select** — Rubber-band select multiple clips.

### 1.3 Mixer
- [ ] **Volume fader** — Drag fader, level changes in meters.
- [ ] **Pan knob** — Turn pan, stereo image shifts.
- [ ] **Mute/Solo** — Mute silences track. Solo isolates track.
- [ ] **Bus routing** — Change output routing, audio goes to correct bus.
- [ ] **Aux sends** — Add send, signal appears on aux bus.
- [ ] **Channel reorder** — Drag channel strip, order persists.

### 1.4 DSP & Processing
- [ ] **Insert EQ** — Add EQ to channel, frequency response changes.
- [ ] **Insert Compressor** — Add compressor, gain reduction meter shows activity.
- [ ] **Insert Limiter** — Add limiter, output never exceeds ceiling.
- [ ] **Bypass toggle** — Bypass processor, audio returns to dry signal.
- [ ] **DSP chain order** — Reorder processors, signal flow changes audibly.

### 1.5 Export
- [ ] **Quick export WAV** — Export renders correct duration, sample rate, bit depth.
- [ ] **Export FLAC** — FLAC file opens in external player.
- [ ] **Export MP3** — MP3 plays correctly with metadata.
- [ ] **Stem export** — Individual bus stems match mix when summed.

---

## 2. Middleware Section

### 2.1 Events
- [ ] **Create event** — New composite event appears in folder.
- [ ] **Add layer** — Audio file added to event as layer.
- [ ] **Remove layer** — Layer removed, event plays without it.
- [ ] **Edit parameters** — Volume/pan/delay sliders affect playback.
- [ ] **Preview event** — Click preview, audio plays to correct bus.
- [ ] **Duplicate event** — Duplicated event is independent copy.
- [ ] **Delete event** — Event removed from folder.

### 2.2 State Groups & Switches
- [ ] **Create state group** — State group with 2+ states.
- [ ] **Set state** — Changing state triggers correct events.
- [ ] **Switch groups** — Per-object switches work independently.

### 2.3 RTPC
- [ ] **Create RTPC** — Define parameter with curve.
- [ ] **Bind to volume** — Moving RTPC slider changes event volume.
- [ ] **Bind to pitch** — RTPC slider changes pitch.
- [ ] **Curve types** — Linear, logarithmic, S-curve all work.

### 2.4 Containers
- [ ] **Blend container** — RTPC crossfades between children.
- [ ] **Random container** — Multiple plays select different children.
- [ ] **Sequence container** — Steps play in defined order.
- [ ] **Deterministic mode** — Same seed produces same results.

### 2.5 Ducking
- [ ] **Add ducking rule** — Source bus ducks target bus.
- [ ] **Attack/Release** — Ducking curve follows configured timing.
- [ ] **Matrix view** — Visual shows correct source→target connections.

### 2.6 Bus Hierarchy
- [ ] **Bus routing** — Audio flows through bus chain to master.
- [ ] **Bus mute/solo** — Mute/solo affects all child buses.
- [ ] **Bus effects** — Insert effects on bus process all children.

---

## 3. SlotLab Section

### 3.1 Slot Machine
- [ ] **Spin** — Reels animate, stop in sequence L→R.
- [ ] **Stop button** — SPACE/STOP immediately stops reels.
- [ ] **Forced outcomes** — Keys 1-7 produce expected results (lose/win/FS/etc).
- [ ] **Win presentation** — Win amounts shown with tier plaque.
- [ ] **Rollup counter** — Counts from 0 to win amount.
- [ ] **Win lines** — Lines drawn through winning positions.
- [ ] **No double spin** — Single SPACE press = single spin.

### 3.2 Audio Integration
- [ ] **Spin sound** — SPIN_START plays on spin button.
- [ ] **Reel stops** — Per-reel stop sounds with stereo panning.
- [ ] **Spin loop** — Continuous loop during spin, fades on stop.
- [ ] **Win audio** — Win tier plays correct celebration audio.
- [ ] **Rollup ticks** — Tick sound plays during rollup.
- [ ] **Feature trigger** — Free spin/bonus trigger sounds play.
- [ ] **Anticipation** — Slow-down audio on anticipated reels.

### 3.3 Audio Authoring
- [ ] **Drop audio on slot** — Drag audio to mockup element → event created.
- [ ] **Quick assign mode** — Click slot → click audio = assigned.
- [ ] **Symbol strip** — Assign audio per symbol, per context.
- [ ] **Music layers** — Assign music per game context.
- [ ] **Audio browser dock** — Browse, preview, multi-select, drag files.
- [ ] **Events panel** — Create/edit/delete events, rename on double-tap.
- [ ] **GDD import** — Import JSON GDD, symbols populate reels.

### 3.4 Features
- [ ] **Free spins** — Enter FS, correct music/sfx, exit FS.
- [ ] **Hold & Win** — Lock symbols, respins, collect.
- [ ] **Cascade** — Symbols fall, escalating pitch/volume.
- [ ] **Big Win** — ≥ threshold shows celebration overlay + music.
- [ ] **Jackpot** — Trigger sequence plays buildup → reveal → celebration.

### 3.5 Export
- [ ] **Template apply** — Select template, systems auto-wire.
- [ ] **Batch export** — All events export to configured format.
- [ ] **Soundbank build** — ZIP archive with converted audio + manifest.
- [ ] **Platform export** — Unity/Unreal/Howler.js code generation.

---

## 4. Cross-Section

### 4.1 Section Isolation
- [ ] **DAW→SlotLab** — Switching to SlotLab pauses DAW playback.
- [ ] **SlotLab→Middleware** — Switching pauses SlotLab.
- [ ] **Browser preview** — Browser playback is always isolated.

### 4.2 Persistence
- [ ] **Project save** — All state persists after save/reload.
- [ ] **Lower zone state** — Tab selection, height persists.
- [ ] **Workspace presets** — Built-in presets apply correctly.

### 4.3 Performance
- [ ] **60fps UI** — No frame drops during normal operation.
- [ ] **Audio latency** — No audible delay on spin/stop events.
- [ ] **Memory** — < 200MB idle, no leaks after 100 spins.

### 4.4 Edge Cases
- [ ] **Missing audio** — Graceful handling when audio file not found.
- [ ] **Large project** — 500+ events load without UI freeze.
- [ ] **Rapid fire** — 10 rapid spins don't crash or desync.

---

## Sign-Off

| Section | PASS/FAIL | Notes |
|---------|-----------|-------|
| DAW | | |
| Middleware | | |
| SlotLab | | |
| Cross-Section | | |

**Overall:** ______ PASS / ______ FAIL

**Blocker Issues:**
1.
2.
3.

**Signed:** _________________________ Date: _____________
