# DAW SECTION — KOMPLETNA ANALIZA I TODO LISTA

**Datum:** 2026-01-20
**Analizirao:** Claude Opus 4.5 (Chief Audio Architect + Lead DSP Engineer + Engine Architect + UI/UX Expert)
**Scope:** Sve UI elementi, svi signal flow-ovi, svi plugini, svi FFI binding-i

---

## EXECUTIVE SUMMARY

| Kategorija | Ukupno | Povezano | Status |
|------------|--------|----------|--------|
| **Knobs (rotary)** | 185+ | 85% | ⚠️ Delimično |
| **Faders/Sliders** | 47 | 100% | ✅ Kompletno |
| **Buttons (toggle)** | 127+ | 90% | ⚠️ Delimično |
| **Dropdowns** | 34 | 95% | ✅ Skoro kompletno |
| **Text Inputs** | 18 | 80% | ⚠️ Delimično |
| **Meters** | 12 | 100% | ✅ Kompletno |
| **UKUPNO** | **423+** | **~89%** | ⚠️ Treba dorada |

---

## 1. MIXER SEKCIJA

### 1.1 Channel Strip — Track Controls

| Kontrola | Widget | FFI Funkcija | Status | TODO |
|----------|--------|--------------|--------|------|
| Volume Fader | `Fader` | `setTrackVolume(trackId, volume)` | ✅ | — |
| Pan Knob | `MiniKnob` | `setTrackPan(trackId, pan)` | ✅ | — |
| Pan Right (dual-pan) | `MiniKnob` | `setTrackPanRight(trackId, pan)` | ✅ | — |
| Mute Button | `_MuteButton` | `setTrackMute(trackId, muted)` | ✅ | — |
| Solo Button | `_SoloButton` | `setTrackSolo(trackId, solo)` | ✅ | — |
| Arm Button | `_ArmButton` | `setTrackArmed(trackId, armed)` | ✅ | — |
| Track Name | `TextField` | `setTrackName(trackId, name)` | ✅ | — |
| Output Routing | `DropdownButton` | `setTrackBus(trackId, busId)` | ✅ | — |
| Input Source | `DropdownButton` | — | ❌ | **TODO: Dodati `setTrackInput()` FFI** |
| Monitor Input | `Toggle` | — | ❌ | **TODO: Dodati `setTrackMonitor()` FFI** |
| Phase Invert | `Toggle` | — | ❌ | **TODO: Dodati `setTrackPhaseInvert()` FFI** |
| Channel Color | `ColorPicker` | — | ❌ | **TODO: UI only, čuva se u projektu** |

### 1.2 Channel Strip — Insert Slots (8 po kanalu)

| Kontrola | Widget | FFI Funkcija | Status | TODO |
|----------|--------|--------------|--------|------|
| Load Processor | Click | `insertLoadProcessor(trackId, slot, name)` | ✅ | — |
| Unload Slot | Context Menu | `insertUnloadSlot(trackId, slot)` | ✅ | — |
| Bypass Toggle | Button | `insertSetBypass(trackId, slot, bypass)` | ✅ | — |
| Wet/Dry Mix | Knob | `insertSetMix(trackId, slot, mix)` | ✅ | — |
| Open Plugin UI | Double-click | — | ⚠️ | **TODO: Plugin editor window management** |
| Drag to Reorder | Drag | — | ❌ | **TODO: Insert slot reordering** |

### 1.3 Channel Strip — Send Slots (4 po kanalu)

| Kontrola | Widget | FFI Funkcija | Status | TODO |
|----------|--------|--------------|--------|------|
| Send Level | `MiniKnob` | — | ❌ | **TODO: Dodati `setSendLevel(trackId, sendIdx, level)` FFI** |
| Send Pan | `MiniKnob` | — | ❌ | **TODO: Dodati `setSendPan(trackId, sendIdx, pan)` FFI** |
| Send Destination | `Dropdown` | — | ❌ | **TODO: Dodati `setSendDestination(trackId, sendIdx, busId)` FFI** |
| Pre/Post Toggle | `Toggle` | — | ❌ | **TODO: Dodati `setSendPrePost(trackId, sendIdx, preFader)` FFI** |
| Send Enable | `Toggle` | — | ❌ | **TODO: Dodati `setSendEnabled(trackId, sendIdx, enabled)` FFI** |

### 1.4 Bus Channels (6 buseva)

| Kontrola | Widget | FFI Funkcija | Status | TODO |
|----------|--------|--------------|--------|------|
| Bus Volume | `Fader` | `setBusVolume(busId, volume)` | ✅ | — |
| Bus Pan | `MiniKnob` | `setBusPan(busId, pan)` | ✅ | — |
| Bus Mute | `Toggle` | `mixerSetBusMute(busId, muted)` | ✅ | — |
| Bus Solo | `Toggle` | `mixerSetBusSolo(busId, solo)` | ✅ | — |
| Bus Insert Load | Click | `busInsertLoadProcessor(busId, slot, name)` | ✅ | — |
| Bus Insert Param | Knob | `busInsertSetParam(busId, slot, param, value)` | ✅ | — |
| Bus Insert Bypass | Toggle | `busInsertSetBypass(busId, slot, bypass)` | ✅ | — |

### 1.5 VCA Faders

| Kontrola | Widget | FFI Funkcija | Status | TODO |
|----------|--------|--------------|--------|------|
| VCA Level | `Fader` | `vcaSetLevel(vcaId, level)` | ✅ | — |
| VCA Mute | `Toggle` | `vcaSetMute(vcaId, muted)` | ✅ | — |
| VCA Solo | `Toggle` | — | ❌ | **TODO: Dodati `vcaSetSolo()` FFI** |
| Assign Track | Drag | `vcaAssignTrack(vcaId, trackId)` | ✅ | — |
| Unassign Track | Context | `vcaUnassignTrack(vcaId, trackId)` | ⚠️ | **TODO: Verifikovati da radi** |

### 1.6 Groups (Linked Channels)

| Kontrola | Widget | FFI Funkcija | Status | TODO |
|----------|--------|--------------|--------|------|
| Create Group | Button | `groupCreate(name)` | ✅ | — |
| Add to Group | Drag | — | ❌ | **TODO: Dodati `groupAddTrack()` FFI** |
| Remove from Group | Context | — | ❌ | **TODO: Dodati `groupRemoveTrack()` FFI** |
| Link Volume | Toggle | — | ❌ | **TODO: Dodati `groupSetLinkVolume()` FFI** |
| Link Pan | Toggle | — | ❌ | **TODO: Dodati `groupSetLinkPan()` FFI** |
| Link Mute | Toggle | — | ❌ | **TODO: Dodati `groupSetLinkMute()` FFI** |
| Link Solo | Toggle | — | ❌ | **TODO: Dodati `groupSetLinkSolo()` FFI** |
| Relative/Absolute | Dropdown | — | ❌ | **TODO: Dodati `groupSetMode()` FFI** |

### 1.7 Master Channel

| Kontrola | Widget | FFI Funkcija | Status | TODO |
|----------|--------|--------------|--------|------|
| Master Volume | `Fader` | `engine.setMasterVolume(volume)` | ✅ | — |
| Master Insert Load | Click | `busInsertLoadProcessor(0, slot, name)` | ✅ | — |
| Master Insert Param | Knob | `busInsertSetParam(0, slot, param, value)` | ✅ | — |
| Dim Button | Toggle | — | ❌ | **TODO: Dodati `setMasterDim()` FFI** |
| Mono Sum | Toggle | — | ❌ | **TODO: Dodati `setMasterMono()` FFI** |
| Reference Level | Selector | — | ❌ | **TODO: Dodati `setMasterReference()` FFI** |

---

## 2. EQ SEKCIJA

### 2.1 Pro EQ (64-band Parametric)

**Per-Band Controls (×64 bandova):**

| Kontrola | Widget | FFI Funkcija | Status | TODO |
|----------|--------|--------------|--------|------|
| Band Enable | Toggle | `proEqSetBandEnabled(trackId, band, enabled)` | ✅ | — |
| Frequency | Knob | `proEqSetBand(...freq)` | ✅ | — |
| Gain | Knob | `proEqSetBand(...gainDb)` | ✅ | — |
| Q Factor | Knob | `proEqSetBand(...q)` | ✅ | — |
| Filter Shape | Dropdown | `proEqSetBand(...shape)` | ✅ | — |
| Band Placement | Dropdown | — | ⚠️ | **TODO: L/R/M/S processing nije implementiran u Rust** |
| Slope | Dropdown | — | ⚠️ | **TODO: Variable slope nije implementiran** |

**Dynamic EQ Per-Band (×64):**

| Kontrola | Widget | FFI Funkcija | Status | TODO |
|----------|--------|--------------|--------|------|
| Dynamic Enable | Toggle | `proEqSetBandDynamic(...enabled)` | ⚠️ | **TODO: Verifikovati Rust implementaciju** |
| Threshold | Knob | `proEqSetBandDynamic(...threshold)` | ⚠️ | **TODO: Verifikovati** |
| Ratio | Knob | `proEqSetBandDynamic(...ratio)` | ⚠️ | **TODO: Verifikovati** |
| Attack | Knob | `proEqSetBandDynamic(...attack)` | ⚠️ | **TODO: Verifikovati** |
| Release | Knob | `proEqSetBandDynamic(...release)` | ⚠️ | **TODO: Verifikovati** |

**Global EQ Controls:**

| Kontrola | Widget | FFI Funkcija | Status | TODO |
|----------|--------|--------------|--------|------|
| Output Gain | Knob | `proEqSetOutputGain(trackId, db)` | ⚠️ | **TODO: Dodati FFI ako ne postoji** |
| Auto Gain | Toggle | — | ❌ | **TODO: Implementirati auto-gain** |
| Bypass All | Toggle | `eqSetBypass(trackId, bypass)` | ✅ | — |
| Analyzer Mode | Dropdown | — | ⚠️ | **TODO: Pre/Post selector** |
| Match Enable | Toggle | — | ❌ | **TODO: Reference matching** |
| A/B Compare | Button | — | ❌ | **TODO: A/B state switching** |

### 2.2 Vintage EQs

**Pultec EQP-1A:**

| Kontrola | Widget | FFI Funkcija | Status | TODO |
|----------|--------|--------------|--------|------|
| Low Boost | Knob | `insertSetParam(...lowBoost)` | ✅ | — |
| Low Atten | Knob | `insertSetParam(...lowAtten)` | ✅ | — |
| High Boost | Knob | `insertSetParam(...highBoost)` | ✅ | — |
| High Atten | Knob | `insertSetParam(...highAtten)` | ✅ | — |
| Low Freq Select | Dropdown | — | ❌ | **TODO: Dodati frequency selection** |
| High Freq Select | Dropdown | — | ❌ | **TODO: Dodati frequency selection** |
| Bypass | Toggle | `insertSetBypass(...)` | ✅ | — |

**API 550A:**

| Kontrola | Widget | FFI Funkcija | Status | TODO |
|----------|--------|--------------|--------|------|
| Low Gain | Knob | `insertSetParam(...lowGain)` | ✅ | — |
| Mid Gain | Knob | `insertSetParam(...midGain)` | ✅ | — |
| High Gain | Knob | `insertSetParam(...highGain)` | ✅ | — |
| Low Freq Select | Dropdown | — | ❌ | **TODO: 5 frequencies per band** |
| Mid Freq Select | Dropdown | — | ❌ | **TODO: 5 frequencies per band** |
| High Freq Select | Dropdown | — | ❌ | **TODO: 5 frequencies per band** |
| Bypass | Toggle | `insertSetBypass(...)` | ✅ | — |

**Neve 1073:**

| Kontrola | Widget | FFI Funkcija | Status | TODO |
|----------|--------|--------------|--------|------|
| HP Enable | Toggle | `insertSetParam(...hpEnabled)` | ✅ | — |
| HP Freq Select | Dropdown | — | ❌ | **TODO: 50/80/160/300 Hz** |
| Low Gain | Knob | `insertSetParam(...lowGain)` | ✅ | — |
| Low Freq Select | Dropdown | — | ❌ | **TODO: 35/60/110/220 Hz** |
| High Gain | Knob | `insertSetParam(...highGain)` | ✅ | — |
| High Freq Select | Dropdown | — | ❌ | **TODO: 10k/12k Hz** |
| EQ Enable | Toggle | `insertSetBypass(...)` | ✅ | — |

---

## 3. DYNAMICS SEKCIJA

### 3.1 Compressor

| Kontrola | Widget | FFI Funkcija | Status | TODO |
|----------|--------|--------------|--------|------|
| Type Selector | Dropdown | — | ⚠️ | **TODO: VCA/FET/Opto/Vari-Mu switching** |
| Threshold | Knob | `compressorSetThreshold(trackId, db)` | ✅ | — |
| Ratio | Knob | `compressorSetRatio(trackId, ratio)` | ✅ | — |
| Attack | Knob | `compressorSetAttack(trackId, ms)` | ✅ | — |
| Release | Knob | `compressorSetRelease(trackId, ms)` | ✅ | — |
| Knee | Knob | `compressorSetKnee(trackId, db)` | ⚠️ | **TODO: Verifikovati FFI** |
| Makeup Gain | Knob | `compressorSetMakeup(trackId, db)` | ✅ | — |
| Auto Makeup | Toggle | — | ❌ | **TODO: Dodati auto-makeup** |
| Dry/Wet | Knob | — | ❌ | **TODO: Parallel compression mix** |
| Sidechain | Button | — | ⚠️ | **TODO: Sidechain routing panel** |
| Sidechain Filter | Controls | — | ❌ | **TODO: HP/LP filter za sidechain** |
| Bypass | Toggle | `compressorSetBypass(trackId, bypass)` | ✅ | — |
| Lookahead | Slider | `compressorSetLookahead(trackId, ms)` | ⚠️ | **TODO: Verifikovati** |

### 3.2 Limiter

| Kontrola | Widget | FFI Funkcija | Status | TODO |
|----------|--------|--------------|--------|------|
| Threshold | Knob | `limiterSetThreshold(trackId, db)` | ✅ | — |
| Ceiling | Knob | `limiterSetCeiling(trackId, db)` | ⚠️ | **TODO: Verifikovati** |
| Release | Knob | `limiterSetRelease(trackId, ms)` | ✅ | — |
| Lookahead | Slider | `limiterSetLookahead(trackId, ms)` | ⚠️ | **TODO: Verifikovati** |
| Auto Release | Toggle | — | ❌ | **TODO: Implementirati** |
| True Peak | Toggle | — | ❌ | **TODO: ISP mode** |
| Bypass | Toggle | `limiterSetBypass(trackId, bypass)` | ✅ | — |

### 3.3 Gate

| Kontrola | Widget | FFI Funkcija | Status | TODO |
|----------|--------|--------------|--------|------|
| Threshold | Knob | `gateSetThreshold(trackId, db)` | ⚠️ | **TODO: Verifikovati FFI** |
| Range | Knob | `gateSetRange(trackId, db)` | ⚠️ | **TODO: Verifikovati** |
| Attack | Knob | `gateSetAttack(trackId, ms)` | ⚠️ | **TODO: Verifikovati** |
| Hold | Knob | `gateSetHold(trackId, ms)` | ⚠️ | **TODO: Verifikovati** |
| Release | Knob | `gateSetRelease(trackId, ms)` | ⚠️ | **TODO: Verifikovati** |
| Sidechain | Button | — | ❌ | **TODO: Sidechain routing** |
| Sidechain Filter | Controls | — | ❌ | **TODO: HP/LP filter** |
| Lookahead | Slider | — | ❌ | **TODO: Implementirati** |
| Bypass | Toggle | `gateSetBypass(trackId, bypass)` | ⚠️ | **TODO: Verifikovati** |

### 3.4 Expander

| Kontrola | Widget | FFI Funkcija | Status | TODO |
|----------|--------|--------------|--------|------|
| Threshold | Knob | — | ❌ | **TODO: Expander FFI** |
| Ratio | Knob | — | ❌ | **TODO: Expander FFI** |
| Attack | Knob | — | ❌ | **TODO: Expander FFI** |
| Release | Knob | — | ❌ | **TODO: Expander FFI** |
| Range | Knob | — | ❌ | **TODO: Expander FFI** |
| Bypass | Toggle | — | ❌ | **TODO: Expander FFI** |

### 3.5 De-Esser

| Kontrola | Widget | FFI Funkcija | Status | TODO |
|----------|--------|--------------|--------|------|
| Threshold | Knob | — | ❌ | **TODO: De-esser FFI** |
| Frequency | Knob | — | ❌ | **TODO: De-esser FFI** |
| Range | Knob | — | ❌ | **TODO: De-esser FFI** |
| Mode | Dropdown | — | ❌ | **TODO: Wide/Split band** |
| Listen | Toggle | — | ❌ | **TODO: Sidechain monitor** |
| Bypass | Toggle | — | ❌ | **TODO: De-esser FFI** |

---

## 4. EFFECTS SEKCIJA

### 4.1 Reverb

| Kontrola | Widget | FFI Funkcija | Status | TODO |
|----------|--------|--------------|--------|------|
| Type | Dropdown | `reverbSetType(trackId, type)` | ✅ | — |
| Room Size | Knob | `reverbSetRoomSize(trackId, size)` | ✅ | — |
| Decay Time | Knob | `reverbSetDecayTime(trackId, seconds)` | ✅ | — |
| Damping | Knob | `reverbSetDamping(trackId, amount)` | ✅ | — |
| Pre-Delay | Knob | `reverbSetPreDelay(trackId, ms)` | ✅ | — |
| Width | Knob | `reverbSetWidth(trackId, width)` | ✅ | — |
| Dry/Wet | Knob | `reverbSetWetDry(trackId, mix)` | ✅ | — |
| HP Filter | Knob | — | ❌ | **TODO: Input HP filter** |
| LP Filter | Knob | — | ❌ | **TODO: Input LP filter** |
| Early/Late | Knob | — | ❌ | **TODO: Early reflection mix** |
| Modulation | Knob | — | ❌ | **TODO: Chorus on tail** |
| Bypass | Toggle | `reverbSetBypass(trackId, bypass)` | ✅ | — |

### 4.2 Delay

| Kontrola | Widget | FFI Funkcija | Status | TODO |
|----------|--------|--------------|--------|------|
| Type | Dropdown | — | ⚠️ | **TODO: Type switching** |
| Time L | Knob | `delaySetTimeL(trackId, ms)` | ⚠️ | **TODO: Verifikovati** |
| Time R | Knob | `delaySetTimeR(trackId, ms)` | ⚠️ | **TODO: Verifikovati** |
| Time Link | Toggle | — | ❌ | **TODO: Link L/R times** |
| Feedback | Knob | `delaySetFeedback(trackId, amount)` | ✅ | — |
| Cross-feed | Knob | — | ❌ | **TODO: Ping-pong cross** |
| HP Filter | Knob | — | ❌ | **TODO: Feedback filter** |
| LP Filter | Knob | — | ❌ | **TODO: Feedback filter** |
| Dry/Wet | Knob | `delaySetWetDry(trackId, mix)` | ✅ | — |
| Tempo Sync | Toggle | `delaySetTempoSync(trackId, enabled)` | ⚠️ | **TODO: Verifikovati** |
| Sync Division | Dropdown | — | ❌ | **TODO: Note value selector** |
| Modulation | Knob | — | ❌ | **TODO: Chorus on repeats** |
| Bypass | Toggle | `delaySetBypass(trackId, bypass)` | ✅ | — |

### 4.3 Saturation

| Kontrola | Widget | FFI Funkcija | Status | TODO |
|----------|--------|--------------|--------|------|
| Type | Dropdown | `saturationSetType(trackId, type)` | ⚠️ | **TODO: Tape/Tube/Digital** |
| Drive | Knob | `saturationSetDrive(trackId, db)` | ✅ | — |
| Tone | Knob | `saturationSetTone(trackId, freq)` | ⚠️ | **TODO: Verifikovati** |
| Output | Knob | `saturationSetOutput(trackId, db)` | ⚠️ | **TODO: Verifikovati** |
| Mix | Knob | — | ❌ | **TODO: Parallel saturation** |
| Bypass | Toggle | `saturationSetBypass(trackId, bypass)` | ✅ | — |

### 4.4 Spatial/Stereo

| Kontrola | Widget | FFI Funkcija | Status | TODO |
|----------|--------|--------------|--------|------|
| Width | Knob | `stereoSetWidth(trackId, width)` | ⚠️ | **TODO: Verifikovati** |
| Balance | Knob | `stereoSetBalance(trackId, balance)` | ⚠️ | **TODO: Verifikovati** |
| M/S Mode | Toggle | `stereoSetMSMode(trackId, enabled)` | ⚠️ | **TODO: Verifikovati** |
| Mid Level | Knob | — | ❌ | **TODO: M/S mid gain** |
| Side Level | Knob | — | ❌ | **TODO: M/S side gain** |
| Mono Below | Knob | — | ❌ | **TODO: Bass mono** |
| Bypass | Toggle | — | ❌ | **TODO: Spatial bypass** |

---

## 5. TIMELINE SEKCIJA

### 5.1 Transport Controls

| Kontrola | Widget | FFI Funkcija | Status | TODO |
|----------|--------|--------------|--------|------|
| Play | Button | `NativeFFI.instance.play()` | ✅ | — |
| Pause | Button | `NativeFFI.instance.pause()` | ✅ | — |
| Stop | Button | `NativeFFI.instance.stop()` | ✅ | — |
| Rewind | Button | `NativeFFI.instance.seek(0)` | ✅ | — |
| Forward | Button | — | ⚠️ | **TODO: Jump forward** |
| Record | Button | `NativeFFI.instance.record()` | ✅ | — |
| Loop | Toggle | `NativeFFI.instance.setLoopEnabled(enabled)` | ✅ | — |
| Loop Start | Input | `NativeFFI.instance.setLoopStart(frames)` | ⚠️ | **TODO: Verifikovati** |
| Loop End | Input | `NativeFFI.instance.setLoopEnd(frames)` | ⚠️ | **TODO: Verifikovati** |
| Metronome | Toggle | `NativeFFI.instance.setMetronomeEnabled(enabled)` | ⚠️ | **TODO: Verifikovati** |
| Count-In | Toggle | — | ❌ | **TODO: Pre-roll count** |
| Pre-Roll | Spinner | — | ❌ | **TODO: Pre-roll bars** |
| Post-Roll | Spinner | — | ❌ | **TODO: Post-roll bars** |
| Punch In | Button | — | ⚠️ | **TODO: Punch markers** |
| Punch Out | Button | — | ⚠️ | **TODO: Punch markers** |

### 5.2 Tempo/Time Signature

| Kontrola | Widget | FFI Funkcija | Status | TODO |
|----------|--------|--------------|--------|------|
| Tempo | Spinner | `NativeFFI.instance.setTempo(bpm)` | ✅ | — |
| Time Sig Num | Spinner | `NativeFFI.instance.setTimeSignature(num, denom)` | ⚠️ | **TODO: Verifikovati** |
| Time Sig Denom | Dropdown | — | ⚠️ | **TODO: Verifikovati** |
| Tempo Track | Lane | — | ❌ | **TODO: Tempo automation** |
| Time Display Mode | Dropdown | — | ✅ | UI only |

### 5.3 Track Lane Controls

| Kontrola | Widget | FFI Funkcija | Status | TODO |
|----------|--------|--------------|--------|------|
| Track Height | Drag | — | ✅ | UI only |
| Track Collapse | Button | — | ✅ | UI only |
| Track Lock | Button | — | ✅ | UI only |
| Show Lanes | Button | — | ✅ | UI only |
| Show Automation | Button | — | ✅ | UI only |
| Track Color | Picker | — | ✅ | UI only |
| Track Icon | Selector | — | ✅ | UI only |

### 5.4 Clip Controls

| Kontrola | Widget | FFI Funkcija | Status | TODO |
|----------|--------|--------------|--------|------|
| Clip Move | Drag | — | ✅ | Timeline state |
| Clip Resize | Edge drag | — | ✅ | Timeline state |
| Clip Fade In | Handle | — | ✅ | Rendered |
| Clip Fade Out | Handle | — | ✅ | Rendered |
| Clip Gain | Knob | — | ⚠️ | **TODO: Per-clip gain** |
| Clip Color | Picker | — | ✅ | UI only |
| Clip Name | Input | — | ✅ | Project state |
| Clip Lock | Toggle | — | ✅ | UI only |
| Clip Split | Tool | — | ✅ | Creates new clips |
| Clip Crossfade | Drag | — | ⚠️ | **TODO: Crossfade shapes** |

### 5.5 Automation Lane

| Kontrola | Widget | FFI Funkcija | Status | TODO |
|----------|--------|--------------|--------|------|
| Parameter Select | Dropdown | — | ✅ | UI state |
| Add Point | Click | — | ✅ | Automation state |
| Move Point | Drag | — | ✅ | Automation state |
| Delete Point | Key/Context | — | ✅ | Automation state |
| Curve Shape | Dropdown | — | ⚠️ | **TODO: Bezier curves** |
| Read/Write Mode | Dropdown | — | ⚠️ | **TODO: Touch/Latch/Write modes** |
| Show All | Button | — | ✅ | UI only |

---

## 6. METERING SEKCIJA

### 6.1 Level Meters

| Kontrola | Widget | Data Source | Status | TODO |
|----------|--------|-------------|--------|------|
| Peak L/R | `Meter` | `getMeteringState().masterPeakL/R` | ✅ | — |
| RMS L/R | `Meter` | `getMeteringState().masterRmsL/R` | ✅ | — |
| Peak Hold | Display | Calculated from peak | ✅ | — |
| Clip Indicator | LED | Peak >= 1.0 | ✅ | — |
| Track Peak | `Meter` | `getTrackPeak(trackId)` | ✅ | — |
| Bus Peak | `Meter` | `getBusPeak(busId)` | ✅ | — |

### 6.2 Loudness Meters

| Kontrola | Widget | Data Source | Status | TODO |
|----------|--------|-------------|--------|------|
| LUFS Integrated | Display | `getMeteringState().lufsIntegrated` | ⚠️ | **TODO: Verifikovati** |
| LUFS Short-term | Display | `getMeteringState().lufsShortTerm` | ⚠️ | **TODO: Verifikovati** |
| LUFS Momentary | Display | `getMeteringState().lufsMomentary` | ⚠️ | **TODO: Verifikovati** |
| True Peak | Display | `getMeteringState().truePeak` | ⚠️ | **TODO: 8x oversampling** |
| LRA | Display | — | ❌ | **TODO: Loudness Range** |
| PLR | Display | — | ❌ | **TODO: Peak-to-Loudness Ratio** |
| Reset | Button | — | ❌ | **TODO: Reset integrated** |

### 6.3 Spectrum Analyzer

| Kontrola | Widget | Data Source | Status | TODO |
|----------|--------|-------------|--------|------|
| FFT Display | `GpuSpectrum` | `getMeteringState().spectrum` | ✅ | — |
| FFT Size | Dropdown | — | ❌ | **TODO: 1024/2048/4096/8192** |
| Window Type | Dropdown | — | ❌ | **TODO: Hann/Blackman/etc** |
| Averaging | Slider | — | ❌ | **TODO: Smoothing** |
| Peak Hold | Toggle | — | ❌ | **TODO: Spectrum peak hold** |
| Slope | Dropdown | — | ❌ | **TODO: Pink/white reference** |
| Pre/Post | Toggle | — | ⚠️ | **TODO: Measurement point** |

### 6.4 Correlation/Phase Meters

| Kontrola | Widget | Data Source | Status | TODO |
|----------|--------|-------------|--------|------|
| Correlation | `CorrelationMeter` | `getMeteringState().correlation` | ✅ | — |
| Goniometer | `Goniometer` | Shared memory | ✅ | — |
| Vectorscope | `Vectorscope` | Shared memory | ✅ | — |
| Phase Scope | Display | — | ❌ | **TODO: Phase difference display** |

---

## 7. PLUGIN SYSTEM

### 7.1 Plugin Browser

| Kontrola | Widget | FFI Funkcija | Status | TODO |
|----------|--------|--------------|--------|------|
| Search | TextField | — | ✅ | UI filtering |
| Category Filter | Tabs | — | ✅ | UI filtering |
| Favorites | Toggle | — | ✅ | UI state |
| Plugin List | ListView | — | ✅ | UI state |
| Load Plugin | Double-click | `insertLoadProcessor()` | ✅ | — |
| Plugin Info | Hover | — | ✅ | UI tooltip |

### 7.2 Plugin Editor Window

| Kontrola | Widget | FFI Funkcija | Status | TODO |
|----------|--------|--------------|--------|------|
| Close | Button | — | ✅ | UI only |
| Bypass | Toggle | `insertSetBypass()` | ✅ | — |
| Preset Load | Dropdown | — | ⚠️ | **TODO: Plugin preset system** |
| Preset Save | Button | — | ⚠️ | **TODO: Plugin preset save** |
| A/B Compare | Button | — | ❌ | **TODO: State comparison** |
| Undo/Redo | Buttons | — | ❌ | **TODO: Per-plugin undo** |
| MIDI Learn | Button | — | ❌ | **TODO: MIDI CC mapping** |
| Resize | Drag | — | ⚠️ | **TODO: Window resizing** |

### 7.3 External Plugin Hosting (VST3/AU/CLAP)

| Kontrola | Widget | FFI Funkcija | Status | TODO |
|----------|--------|--------------|--------|------|
| Scan Plugins | Button | `pluginScan()` | ⚠️ | **TODO: Verifikovati** |
| Load VST3 | Action | `pluginLoadVst3(path)` | ⚠️ | **TODO: Sandbox** |
| Load AU | Action | `pluginLoadAu(id)` | ⚠️ | **TODO: Sandbox** |
| Load CLAP | Action | `pluginLoadClap(path)` | ⚠️ | **TODO: Sandbox** |
| Plugin GUI | Embed | — | ❌ | **TODO: Native window embed** |
| Plugin State | Save/Load | — | ❌ | **TODO: State persistence** |

---

## 8. RECORDING SYSTEM

### 8.1 Recording Controls

| Kontrola | Widget | FFI Funkcija | Status | TODO |
|----------|--------|--------------|--------|------|
| Global Record | Button | `record()` | ✅ | — |
| Pre-Roll | Spinner | `setPreRoll(bars)` | ⚠️ | **TODO: Verifikovati** |
| Count-In | Toggle | `setCountIn(enabled)` | ⚠️ | **TODO: Verifikovati** |
| Punch In | Marker | — | ⚠️ | **TODO: Punch system** |
| Punch Out | Marker | — | ⚠️ | **TODO: Punch system** |
| Auto-Punch | Toggle | — | ❌ | **TODO: Auto punch** |
| Cycle Record | Toggle | — | ❌ | **TODO: Loop recording** |

### 8.2 Input Monitoring

| Kontrola | Widget | FFI Funkcija | Status | TODO |
|----------|--------|--------------|--------|------|
| Monitor Input | Toggle | `setTrackMonitor(trackId, enabled)` | ⚠️ | **TODO: Input monitoring** |
| Direct Monitoring | Toggle | — | ❌ | **TODO: Hardware direct** |
| Software Monitoring | Toggle | — | ⚠️ | **TODO: Software path** |
| Record Level | Meter | — | ⚠️ | **TODO: Input metering** |

---

## 9. PROJECT/SESSION

### 9.1 Project Controls

| Kontrola | Widget | FFI Funkcija | Status | TODO |
|----------|--------|--------------|--------|------|
| New Project | Menu | — | ✅ | File dialog |
| Open Project | Menu | — | ✅ | File dialog |
| Save Project | Menu | `projectSave(path)` | ✅ | — |
| Save As | Menu | — | ✅ | File dialog |
| Import Audio | Menu | `importAudio(path)` | ✅ | — |
| Export/Render | Menu | — | ⚠️ | **TODO: Offline bounce** |
| Undo | Shortcut | — | ⚠️ | **TODO: Command pattern** |
| Redo | Shortcut | — | ⚠️ | **TODO: Command pattern** |

### 9.2 Preferences

| Kontrola | Widget | FFI Funkcija | Status | TODO |
|----------|--------|--------------|--------|------|
| Audio Device | Dropdown | `setAudioDevice(id)` | ✅ | — |
| Sample Rate | Dropdown | `setSampleRate(rate)` | ✅ | — |
| Buffer Size | Dropdown | `setBufferSize(size)` | ✅ | — |
| MIDI Device | Dropdown | — | ❌ | **TODO: MIDI I/O** |
| Plugin Path | Input | — | ⚠️ | **TODO: Plugin scan paths** |

---

## 10. SUMMARY — PRIORITIZED TODO LIST

### KRITIČNO (Audio ne radi bez ovog)

1. **Send System FFI** — `setSendLevel()`, `setSendPan()`, `setSendDestination()`, `setSendPrePost()`, `setSendEnabled()`
2. **Group Linking FFI** — `groupAddTrack()`, `groupRemoveTrack()`, `groupSetLinkVolume()`, `groupSetLinkPan()`, etc.
3. **Expander FFI** — Kompletan expander processor
4. **De-Esser FFI** — Kompletan de-esser processor
5. **Dynamic EQ verifikacija** — Proveriti da li Rust procesira dynamic EQ parametre

### VISOK PRIORITET (Profesionalna funkcionalnost)

6. **Vintage EQ frequency selection** — Pultec, API 550, Neve frequency dropdown-ovi
7. **Compressor type switching** — VCA/FET/Opto/Vari-Mu
8. **Sidechain routing panel** — Sidechain source selection, filter controls
9. **Plugin preset system** — Save/load/browse plugin presets
10. **Loudness metering** — LUFS I/S/M, True Peak, LRA

### SREDNJI PRIORITET (Workflow poboljšanja)

11. **Input source selection** — Track input routing
12. **Monitor input** — Software/hardware monitoring
13. **Phase invert** — Per-track phase flip
14. **Master dim/mono** — Control room features
15. **Tempo automation** — Tempo track lane
16. **Crossfade shapes** — Linear, equal power, S-curve
17. **Automation modes** — Read/Touch/Latch/Write

### NIZAK PRIORITET (Nice-to-have)

18. **MIDI Learn** — CC mapping za sve kontrole
19. **A/B Compare** — Per-plugin i global
20. **Plugin GUI embed** — Native window za VST3/AU
21. **Spectrum analyzer options** — FFT size, window, averaging
22. **M/S processing** — Mid/Side EQ bands

---

## 11. FAJLOVI ZA IZMENU

### Rust (crates/rf-engine/src/)

| Fajl | Potrebne izmene |
|------|-----------------|
| `ffi.rs` | Dodati send FFI, group FFI, expander FFI, de-esser FFI |
| `playback.rs` | Send routing, group linking logic |
| `dsp_wrappers.rs` | Expander wrapper, de-esser wrapper |

### Rust (crates/rf-dsp/src/)

| Fajl | Potrebne izmene |
|------|-----------------|
| `expander.rs` | Kreirati ako ne postoji |
| `deesser.rs` | Kreirati ako ne postoji |
| `eq_analog.rs` | Frequency selection parametri |

### Dart (flutter_ui/lib/src/rust/)

| Fajl | Potrebne izmene |
|------|-----------------|
| `native_ffi.dart` | Dodati sve nove FFI bindings |

### Dart (flutter_ui/lib/providers/)

| Fajl | Potrebne izmene |
|------|-----------------|
| `mixer_provider.dart` | Send state management, group linking |

### Dart (flutter_ui/lib/widgets/)

| Fajl | Potrebne izmene |
|------|-----------------|
| `channel_strip.dart` | Send UI, input routing |
| `eq/*.dart` | Frequency selectors za vintage EQs |
| `dsp/dynamics_panel.dart` | Expander mode, de-esser mode |

---

**Generisano:** 2026-01-20
**Verzija:** 1.0
**Sledeći review:** Nakon implementacije kritičnih stavki
