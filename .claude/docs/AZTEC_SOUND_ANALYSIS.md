# Aztec Theme — Complete Sound Analysis

> Source: `~/Desktop/Aztec asset/sourceSoundFiles/` (93 WAV files)
> Analyzed: 2026-03-12
> Purpose: Blueprint for SFX Pipeline Wizard implementation in SlotLab

---

## Format Summary

| Property | Values Found |
|----------|-------------|
| Codec | PCM (all files) |
| Channels | 2 (stereo, all files) |
| Sample Rate | 48000 Hz (majority), 44100 Hz (Symbol*, UI legacy, Picker, BigWinTier, RollupLow, ScreenShake) |
| Bit Depth | 24-bit (majority), 16-bit (SymbolPreshow1-5, SymbolS12-15, RollupLow, BigWinTier, UiBetDown/Up/Max, UiClick, UiSkip, UiSpin, UiSpinSlam, Win1-7) |

**Mixed format alert**: Two sample rates (44100/48000) and two bit depths (16/24) in same asset pack. SFX Pipeline must normalize to single target format.

---

## Category Breakdown

### 1. MUSIC — Background Loops

| File | Duration | LUFS | RMS dB | Peak dBFS | Bit/SR | Stereo Notes |
|------|----------|------|--------|-----------|--------|--------------|
| AmbBg.wav | 60.00s | -35.2 | -39.60 | -21.38 | 24/48k | L/R delta: 3.6dB peak, very wide ambient |
| BaseGameMusicLoop1.wav | 61.44s | -18.3 | -19.33 | -8.73 | 24/48k | L/R delta: 0.6dB peak, R louder by ~2dB RMS |
| BaseGameMusicLoop2.wav | 61.44s | -18.0 | -20.15 | -8.54 | 24/48k | Balanced, flat factor 14.3 (some limiting) |
| BaseGameMusicLoop3.wav | 61.44s | -16.0 | -17.79 | -6.45 | 24/48k | Hottest loop, flat factor 13.7, L/R: 0.8dB delta |
| PickerMusicLoop.wav | 11.02s | -24.7 | -25.77 | -5.25 | 24/44.1k | L/R delta: 1.6dB peak, quieter loop |
| SpinsLoop1.wav | 6.50s | -22.0 | -25.60 | -7.33 | 24/48k | Very balanced L/R |
| SpinsLoop2.wav | 6.50s | -22.0 | -25.86 | -8.30 | 24/48k | Balanced |
| SpinsLoop3.wav | 6.50s | -21.2 | -24.98 | -8.23 | 24/48k | Balanced |

**Music LUFS range**: -35.2 (AmbBg) to -16.0 (BaseGameMusicLoop3)
**Music target**: Base game loops ~-17 LUFS, Spins loops ~-22 LUFS, Ambient ~-35 LUFS

### 2. WIN CELEBRATIONS

| File | Duration | LUFS | RMS dB | Peak dBFS | Bit/SR | Stereo L/R Peak Delta |
|------|----------|------|--------|-----------|--------|----------------------|
| Win1.wav | 3.26s | -17.4 | -23.07 | -5.26 | 16/48k | 0.42dB — L louder |
| Win2.wav | 3.59s | -15.5 | -19.55 | -5.16 | 16/48k | 0.04dB — balanced |
| Win3.wav | 3.61s | -15.0 | -20.03 | -3.30 | 16/48k | 1.49dB — L much louder |
| Win4.wav | 3.56s | -16.3 | -20.75 | -4.35 | 16/48k | 0.68dB — R slightly louder |
| Win5.wav | 3.61s | -14.8 | -18.74 | -4.31 | 16/48k | 0.21dB — balanced |
| Win6.wav | 4.57s | -12.6 | -17.11 | -1.77 | 16/48k | 0.91dB — L louder |
| Win7.wav | 4.51s | -15.5 | -20.69 | -3.96 | 16/48k | 0.03dB — balanced |

**Win LUFS range**: -17.4 (Win1, smallest) to -12.6 (Win6, biggest)
**Win escalation**: Clear loudness escalation Win1→Win6 (4.8 LUFS range)
**Win6 HOT**: Peak -1.77 dBFS, LUFS -12.6 — near clipping territory
**Win target**: -15 to -13 LUFS, escalating by tier

### 3. BIG WIN

| File | Duration | LUFS | RMS dB | Peak dBFS | Bit/SR | Notes |
|------|----------|------|--------|-----------|--------|-------|
| BigWinAlert.wav | 4.00s | -16.8 | -25.35 | -7.90 | 24/48k | Sparse, high crest factor 7.5 |
| BigWinStart.wav | 32.00s | -14.0 | -16.50 | -5.05 | 24/48k | Long celebration, flat factor 14.8 (limited) |
| BigWinEnd.wav | 3.85s | -13.7 | -18.40 | -5.95 | 24/48k | Punchy ending |
| BigWinTier.wav | 3.27s | -16.3 | -20.53 | -5.93 | 16/44.1k | DIFFERENT FORMAT (16bit/44.1k!) |

**BigWin target**: Alert ~-17, Start ~-14, End ~-14 LUFS

### 4. COIN/ROLLUP

| File | Duration | LUFS | RMS dB | Peak dBFS | Bit/SR | Notes |
|------|----------|------|--------|-----------|--------|-------|
| CoinLoop.wav | 3.00s | -26.9 | -33.00 | -6.46 | 24/48k | Very quiet RMS, sharp transients (crest 19.7) |
| CoinLoopEnd.wav | 2.33s | -26.2 | -33.43 | -6.83 | 24/48k | Same character, crest 21.2 |
| RollupLow.wav | 0.60s | -20.3 | -23.00 | -10.10 | 16/44.1k | Short, different format |
| Payline.wav | 3.25s | -20.1 | -25.53 | -6.25 | 24/48k | Moderate |

**Coin/Rollup target**: -20 to -27 LUFS (sits under wins)

### 5. REEL MECHANICS

| File | Duration | LUFS | RMS dB | Peak dBFS | Bit/SR | Notes |
|------|----------|------|--------|-----------|--------|-------|
| ReelLand1.wav | 2.67s | -30.9 | -35.54 | -9.23 | 24/48k | Very quiet, high crest 20.4 |
| ReelLand2.wav | 2.67s | -31.3 | -36.55 | -9.85 | 24/48k | Quietest |
| ReelLand3.wav | 2.67s | -31.4 | -38.20 | -8.32 | 24/48k | |
| ReelLand4.wav | 2.67s | -33.4 | -38.57 | -11.38 | 24/48k | Quietest of set |
| ReelLand5.wav | 2.67s | -30.6 | -35.66 | -7.38 | 24/48k | Loudest of set |

**Reel LUFS range**: -33.4 to -30.6 — very quiet, background texture
**Reel target**: ~-31 LUFS

### 6. SYMBOL SOUNDS — Standard (S01-S15)

| File | Duration | LUFS | RMS dB | Peak dBFS | Bit/SR | DC Offset |
|------|----------|------|--------|-----------|--------|-----------|
| SymbolS01.wav | 0.84s | -20.5 | -24.02 | -4.99 | 24/44.1k | 0.0025 (R!) |
| SymbolS02.wav | 0.80s | -20.8 | -24.80 | -4.99 | 24/44.1k | 0.0024 |
| SymbolS03.wav | 0.76s | -21.0 | -24.77 | -4.99 | 24/44.1k | 0.0019 |
| SymbolS04.wav | 0.76s | -20.4 | -24.11 | -4.99 | 24/44.1k | 0.0016 |
| SymbolS05.wav | 0.81s | -20.6 | -24.39 | -4.99 | 24/44.1k | 0.0015 |
| SymbolS06.wav | 0.76s | -20.9 | -25.02 | -4.99 | 24/44.1k | 0.0011 |
| SymbolS07.wav | 0.77s | -19.6 | -23.72 | -4.99 | 24/44.1k | -0.0002 |
| SymbolS08.wav | 0.72s | -20.7 | -23.94 | -4.99 | 24/44.1k | 0.0016 |
| SymbolS09.wav | 0.87s | -20.2 | -23.77 | -4.99 | 24/44.1k | 0.0007 |
| SymbolS10.wav | 0.55s | -21.5 | -25.38 | -4.99 | 24/44.1k | 0.0017 |
| SymbolS11.wav | 0.60s | -20.2 | -23.73 | -4.99 | 24/44.1k | 0.0025 |
| SymbolS12.wav | 1.08s | -20.8 | -24.44 | -0.10 | **16**/44.1k | 0.0042 (HIGH!) |
| SymbolS13.wav | 1.27s | -21.4 | -24.30 | -0.10 | **16**/44.1k | 0.0033 |
| SymbolS14.wav | 1.33s | -19.8 | -22.95 | -0.10 | **16**/44.1k | 0.0035 |
| SymbolS15.wav | 1.27s | -20.6 | -23.82 | -0.10 | **16**/44.1k | 0.0035 |

**CRITICAL**: S12-S15 peak at -0.10 dBFS (near 0!) while S01-S11 peak at -4.99 dBFS. Two different mastering passes.
**DC offset problem**: All SymbolS files have measurable DC offset on R channel (up to 0.004), needs HP filter.
**ALL SymbolS files**: Perfect L/R stereo balance (essentially dual-mono with tiny L/R offset).
**Symbol LUFS range**: -19.6 to -21.5 — very consistent.
**Symbol target**: -20.5 LUFS

### 7. SYMBOL SOUNDS — Special

| File | Duration | LUFS | RMS dB | Peak dBFS | Bit/SR | Notes |
|------|----------|------|--------|-----------|--------|-------|
| SymbolB01.wav | 1.25s | -19.4 | -22.66 | -4.99 | 24/44.1k | Bonus symbol, DC offset 0.002 |
| SymbolB01Anticipation.wav | 6.08s | -17.2 | -20.64 | -4.99 | 24/44.1k | Long anticipation build |
| SymbolB01AnticipationEnd.wav | 1.20s | -20.4 | -24.56 | -4.99 | 24/44.1k | DC offset 0.002 |
| SymbolB01Land1.wav | 2.97s | -31.6 | -35.48 | -15.75 | 24/44.1k | Very quiet, L>>R (5.8dB L/R RMS delta!) |
| SymbolB01Land2.wav | 3.07s | -28.0 | -32.81 | -12.70 | 24/44.1k | L>>R (5.1dB delta) |
| SymbolB01Land3.wav | 3.11s | -18.2 | -23.00 | -4.45 | 24/44.1k | L>>R (1.5dB delta) |
| SymbolB01Land4.wav | 3.11s | -17.6 | -23.12 | -4.73 | 24/44.1k | L>>R (1.5dB delta) |
| SymbolB01Land5.wav | 3.11s | -17.1 | -22.97 | -4.74 | 24/44.1k | L>>R (1.5dB delta) |
| SymbolW01.wav | 0.97s | -19.7 | -23.04 | -4.99 | 24/44.1k | Wild symbol |
| SymbolW01Transform.wav | 1.09s | -20.6 | -24.54 | -4.99 | 24/44.1k | Wild transform |
| SymbolPreshow1.wav | 0.18s | -70.0 | -23.83 | -9.57 | **16**/44.1k | LUFS -70 = too short for measurement |
| SymbolPreshow2.wav | 0.19s | -70.0 | -22.56 | -8.21 | **16**/44.1k | Same |
| SymbolPreshow3.wav | 0.16s | -70.0 | -24.52 | -10.53 | **16**/44.1k | Same |
| SymbolPreshow4.wav | 0.19s | -70.0 | -25.03 | -10.67 | **16**/44.1k | Same |
| SymbolPreshow5.wav | 0.19s | -70.0 | -23.96 | -9.41 | **16**/44.1k | Same |

**SymbolB01Land1-5**: Loudness escalation by reel position (Land1=-31.6 → Land5=-17.1, 14.5 LUFS range!)
**SymbolB01Land1-2**: SEVERE L/R imbalance (L is 6-8 dB louder than R in peak)
**SymbolPreshow**: Too short for LUFS measurement, perfect dual-mono

### 8. SYMBOL WIN CELEBRATIONS — High Pay (Hp) & Mid Pay (Mp)

| File | Duration | LUFS | RMS dB | Peak dBFS | Bit/SR | L/R Peak Delta |
|------|----------|------|--------|-----------|--------|----------------|
| SymHp1Win.wav | 6.23s | -17.8 | -25.92 | -5.07 | 24/48k | 0.24dB |
| SymHp2Win.wav | 6.23s | -17.6 | -25.86 | -4.30 | 24/48k | 0.39dB |
| SymHp3Win.wav | 6.23s | -18.4 | -26.08 | -4.84 | 24/48k | 0.20dB |
| SymMp1Win.wav | 5.07s | -20.1 | -28.50 | -5.75 | 24/48k | 0.90dB |
| SymMp2Win.wav | 5.07s | -19.4 | -28.59 | -4.25 | 24/48k | 0.70dB |
| SymMp3Win.wav | 5.07s | -20.3 | -28.31 | -5.97 | 24/48k | 0.37dB |
| SymMp4Win.wav | 5.07s | -19.9 | -29.20 | -6.59 | 24/48k | 0.64dB |
| SymMp5Win.wav | 5.07s | -20.0 | -29.09 | -6.19 | 24/48k | 0.13dB |

**Hp LUFS**: ~-18 (louder = higher value symbols)
**Mp LUFS**: ~-20 (quieter = lower value symbols)
**Good hierarchy**: Hp louder than Mp by ~2 LUFS

### 9. SCATTER

| File | Duration | LUFS | RMS dB | Peak dBFS | Bit/SR | Notes |
|------|----------|------|--------|-----------|--------|-------|
| SymScatterLand1.wav | 5.70s | -18.0 | -24.77 | -4.02 | 24/48k | |
| SymScatterLand2.wav | 5.70s | -18.5 | -25.63 | -4.17 | 24/48k | |
| SymScatterLand3.wav | 5.70s | -17.6 | -22.93 | -4.01 | 24/48k | |
| SymScatterLand4.wav | 5.70s | -17.5 | -23.03 | -4.01 | 24/48k | |
| SymScatterLand5.wav | 5.70s | -16.7 | -22.63 | -4.02 | 24/48k | Loudest scatter |
| SymScatterWin.wav | 6.85s | -16.5 | -23.55 | -4.01 | 24/48k | Scatter win celebration |

**Scatter LUFS**: -18.5 to -16.5 — escalating by count (like SymbolB01Land)
**Scatter target**: ~-17.5 LUFS

### 10. WILD LAND

| File | Duration | LUFS | RMS dB | Peak dBFS | Bit/SR | L/R Peak Delta |
|------|----------|------|--------|-----------|--------|----------------|
| WildLand1.wav | 3.38s | -22.5 | -31.00 | -7.46 | 24/48k | 0.44dB |
| WildLand2.wav | 3.38s | -22.7 | -31.02 | -8.00 | 24/48k | 0.72dB |
| WildLand3.wav | 3.38s | -23.5 | -31.29 | -6.87 | 24/48k | 1.07dB |
| WildLand4.wav | 3.38s | -23.1 | -31.04 | -6.10 | 24/48k | 1.56dB |
| WildLand5.wav | 3.38s | -23.6 | -32.23 | -7.53 | 24/48k | 1.82dB |

**Wild LUFS**: ~-23 — quieter than scatter (background accent)
**Wild target**: -23 LUFS

### 11. ANTICIPATION

| File | Duration | LUFS | RMS dB | Peak dBFS | Bit/SR | Notes |
|------|----------|------|--------|-----------|--------|-------|
| AnticipationLong.wav | 6.57s | -13.5 | -17.53 | -4.01 | 24/48k | DC offset 0.007 (needs HP filter!) |
| AnticipationMed.wav | 6.10s | -14.4 | -18.37 | -4.01 | 24/48k | DC offset 0.005 |
| AnticipationShort.wav | 5.72s | -16.4 | -20.83 | -4.51 | 24/48k | DC offset 0.002 |

**Anticipation LUFS**: -16.4 to -13.5 — loud, escalating with length
**DC offset alert**: AnticipationLong has 0.007 DC offset — HP filter mandatory
**Anticipation target**: -14 to -16 LUFS

### 12. UI SOUNDS

| File | Duration | LUFS | RMS dB | Peak dBFS | Bit/SR | Stereo |
|------|----------|------|--------|-----------|--------|--------|
| UiClick.wav | 0.35s | -70.0 | -29.93 | -7.32 | 16/44.1k | Perfect mono (L=R) |
| UiBetDown.wav | 0.52s | -25.7 | -29.15 | -10.17 | 16/44.1k | Perfect mono |
| UiBetUp.wav | 0.48s | -30.6 | -34.52 | -9.79 | 16/44.1k | Perfect mono |
| UiBetMax.wav | 2.88s | -22.7 | -28.03 | -6.20 | 16/44.1k | Perfect mono |
| UiSpin.wav | 0.90s | -30.9 | -36.63 | -12.21 | 16/44.1k | Near-mono, L slight louder |
| UiSpinSlam.wav | 0.90s | -30.9 | -36.63 | -12.21 | 16/44.1k | IDENTICAL to UiSpin! |
| UiSkip.wav | 1.49s | -16.0 | -20.22 | -0.75 | 16/44.1k | Near-mono, PEAK -0.75! |
| UiOpen.wav | 1.35s | -22.0 | -27.38 | -2.18 | 24/48k | L louder by 1.55dB peak |
| UiClose.wav | 1.35s | -22.9 | -26.81 | -2.78 | 24/48k | L louder by 1.05dB peak |
| UiSelect1.wav | 1.15s | -33.4 | -41.18 | -9.84 | 24/48k | Very quiet |
| UiSelect2.wav | 1.15s | -33.6 | -41.39 | -9.37 | 24/48k | Very quiet |
| UiSelect3.wav | 1.15s | -32.2 | -39.88 | -9.63 | 24/48k | Very quiet |

**UiSpin = UiSpinSlam**: Identical files! Placeholder or bug.
**UiSkip HOT**: Peak -0.75 dBFS — dangerously close to clipping.
**UI LUFS range**: -70 to -16 — ENORMOUS spread (30+ LUFS range)
**Legacy 16-bit**: UiBetDown/Up/Max, UiClick, UiSkip, UiSpin/Slam are 16-bit/44.1k
**Modern 24-bit**: UiOpen, UiClose, UiSelect1-3 are 24-bit/48k
**UI target**: -24 to -28 LUFS for subtle UI, -20 for interactive feedback

### 13. SCREEN EFFECTS

| File | Duration | LUFS | RMS dB | Peak dBFS | Bit/SR | Notes |
|------|----------|------|--------|-----------|--------|-------|
| ScreenShake.wav | 2.22s | -18.0 | -17.65 | -6.11 | 24/44.1k | L/R delta 1.25dB peak |

---

## Global Issues Found

### 1. Mixed Sample Rates
- **48000 Hz**: 57 files (all modern/re-exported sounds)
- **44100 Hz**: 36 files (Symbol*, UI legacy, Picker, BigWinTier, RollupLow, ScreenShake)
- **Pipeline action**: SRC to 48000 Hz (sinc resampling)

### 2. Mixed Bit Depths
- **24-bit**: 69 files
- **16-bit**: 24 files (SymbolPreshow1-5, SymbolS12-15, Win1-7, RollupLow, BigWinTier, UiBet*, UiClick, UiSkip, UiSpin*, SymbolS12-15)
- **Pipeline action**: All processing at 32-bit float, export to target depth

### 3. DC Offset Problems
Files with significant DC offset (>0.001):
- AnticipationLong.wav: **0.007** (worst)
- AnticipationMed.wav: 0.005
- SymbolS12.wav: 0.004
- SymbolS14.wav: 0.004
- SymbolS15.wav: 0.003
- SymbolS13.wav: 0.003
- SymbolS11.wav: 0.003
- SymbolS01.wav: 0.003
- SymbolW01Transform.wav: 0.002
- SymbolB01.wav: 0.002
- SymbolB01AnticipationEnd.wav: 0.002
- AnticipationShort.wav: 0.002
- **Pipeline action**: 20 Hz HP filter on all files

### 4. Hot Peaks (Near Clipping)
- UiSkip.wav: **-0.75 dBFS**
- SymbolS12.wav: **-0.10 dBFS**
- SymbolS13.wav: **-0.10 dBFS**
- SymbolS14.wav: **-0.10 dBFS**
- SymbolS15.wav: **-0.10 dBFS**
- Win6.wav: **-1.77 dBFS**
- UiOpen.wav: -2.18 dBFS
- UiClose.wav: -2.78 dBFS
- **Pipeline action**: TruePeakLimiter with -1.0 dBTP ceiling

### 5. Identical Files
- **UiSpin.wav = UiSpinSlam.wav**: Byte-identical audio content
- **Pipeline action**: Flag for user, likely needs different SFX

### 6. Severe L/R Imbalance
- SymbolB01Land1.wav: L peak -15.75, R peak -24.18 (**8.4 dB delta**)
- SymbolB01Land2.wav: L peak -12.70, R peak -18.68 (**6.0 dB delta**)
- Win1.wav: L RMS -21.96, R RMS -24.57 (2.6 dB delta)
- Win3.wav: L RMS -18.93, R RMS -21.52 (2.6 dB delta)
- **Pipeline action**: Auto-detect imbalance >3dB, warn user

### 7. Flat Factor (Potential Limiting/Clipping Artifacts)
- BigWinStart.wav: 14.84 (multiple consecutive peak samples)
- BaseGameMusicLoop2.wav: 14.30
- BaseGameMusicLoop3.wav: 13.72
- **Pipeline action**: These are pre-limited by source mastering, avoid double-limiting

---

## LUFS Hierarchy Map (Target for SFX Pipeline Wizard)

```
Category                    Source LUFS Range      Recommended Target LUFS
─────────────────────────────────────────────────────────────────────────
Ambient Background          -35.2                  -35
Base Game Music Loops       -18.3 to -16.0         -18
Spins Loops                 -22.0 to -21.2         -22
Picker Music                -24.7                  -24
Reel Land                   -33.4 to -30.6         -31
Symbol Standard (S01-S15)   -21.5 to -19.6         -20
Symbol Bonus (B01)          -19.4                  -19
Symbol Wild (W01)           -19.7                  -20
Symbol Preshow              too short              (use RMS: -24)
Symbol B01 Land (per reel)  -31.6 to -17.1         -31 to -17 (escalating)
Wild Land                   -23.6 to -22.5         -23
Scatter Land (per count)    -18.5 to -16.5         -18 to -17 (escalating)
Scatter Win                 -16.5                  -17
Sym HP Win                  -18.4 to -17.6         -18
Sym MP Win                  -20.3 to -19.4         -20
Anticipation                -16.4 to -13.5         -15
Regular Win (1-7)           -17.4 to -12.6         -16 to -13 (escalating)
Big Win Alert               -16.8                  -17
Big Win Start               -14.0                  -14
Big Win End                 -13.7                  -14
Big Win Tier                -16.3                  -16
Coin Loop                   -26.9                  -27
Coin Loop End               -26.2                  -26
Rollup Low                  -20.3                  -20
Payline                     -20.1                  -20
Screen Shake                -18.0                  -18
UI Click/Bet                -30.6 to -25.7         -28
UI Spin                     -30.9                  -30
UI Open/Close               -22.9 to -22.0         -22
UI Select                   -33.6 to -32.2         -33
UI Skip                     -16.0                  -20 (needs reduction!)
```

---

## SFX Pipeline Wizard — Implementation Requirements

### Auto-Detection Categories (from filename patterns)
```
Pattern                  → Category
AmbBg*                   → MUSIC_AMBIENT
BaseGameMusicLoop*       → MUSIC_BASE
SpinsLoop*               → MUSIC_SPINS
PickerMusicLoop*         → MUSIC_PICKER
ReelLand*                → REEL_LAND
SymbolS*                 → SYMBOL_STANDARD
SymbolB*                 → SYMBOL_BONUS
SymbolW*                 → SYMBOL_WILD
SymbolPreshow*           → SYMBOL_PRESHOW
SymHp*Win                → WIN_HIGH_PAY
SymMp*Win                → WIN_MID_PAY
SymScatterLand*          → SCATTER_LAND
SymScatterWin*           → SCATTER_WIN
WildLand*                → WILD_LAND
Anticipation*            → ANTICIPATION
Win[0-9]*                → WIN_CELEBRATION
BigWin*                  → BIG_WIN
Coin*                    → COIN_ROLLUP
Rollup*                  → COIN_ROLLUP
Payline*                 → PAYLINE
ScreenShake*             → SCREEN_EFFECT
Ui*                      → UI_SOUND
```

### Processing Pipeline Per Category
```
1. FORMAT NORMALIZE
   - SRC to 48000 Hz (sinc interpolation)
   - Convert to 32-bit float for processing

2. DC REMOVAL
   - 20 Hz Butterworth HP filter (2nd order)
   - Apply to ALL files (not just flagged ones)

3. LOUDNESS NORMALIZE
   - Measure integrated LUFS
   - Apply gain to reach category target LUFS
   - Preserve relative loudness within escalating groups (Win1-7, ScatterLand1-5, B01Land1-5)

4. TRUE PEAK LIMIT
   - Ceiling: -1.0 dBTP
   - Only engage on files exceeding ceiling after loudness normalize
   - Skip files with flat_factor > 10 (already limited)

5. STEREO CHECK
   - Flag L/R peak delta > 3.0 dB
   - Flag perfect mono files (inform user, don't auto-fix)

6. EXPORT
   - Target: 48000 Hz, 24-bit PCM WAV (or user-configurable)
   - Filename preservation with category prefix option
```

### Escalating Loudness Groups (Wizard Must Preserve)
These groups have intentional loudness escalation — the wizard should normalize the GROUP average to target, then preserve internal ratios:
- **Win1-7**: escalating ~0.7 LUFS per step
- **ScatterLand1-5**: escalating ~0.4 LUFS per step
- **SymbolB01Land1-5**: escalating ~3.6 LUFS per step (dramatic reel-by-reel build)
- **BaseGameMusicLoop1-3**: Layer system, L1 quietest, L3 loudest (2.3 LUFS spread)

---

## sounds.json Sprite Mapping (Reference)

The `sounds.json` defines audio sprites for web playback. Key observations:
- Tags: only "Music" and "SoundEffects" (2 categories)
- Some sounds in JSON are NOT in sourceSoundFiles (BonusSymbol*, BonusMusicLoop, etc.)
- Some source files are NOT in JSON (multiple ReelLand variants, etc.)
- JSON durations often shorter than WAV durations (trimmed for sprite packing)
- BaseMusicLoop in JSON = 101.5s (concatenated from BaseGameMusicLoop1+2+3 ≈ 3×61.4s)

### Sounds in JSON but NOT in source folder:
- BonusGameSpinEnd/Start, BonusMusicLoop/End, BonusRetrigger
- BonusRollup1/2 Start/End, BonusSpinEnd/Start
- BonusSymbolS01-S15, BonusSymbolW01, BonusSymbolWin
- BonusToBaseStart, BaseToBonusStart
- IntroStart, PreBonusLoop
- SymbolF01, SymbolF01Anticipation/End
- PickerSelect, PickerStart
- Rollup1, Rollup1End, Rollup2End, Rollup2Start

These represent BONUS mode sounds that may be in a separate asset package or generated at runtime.

---

## True Peak (Inter-Sample Peak) — Full Table

| File | True Peak dBTP | DANGER |
|------|---------------|--------|
| SymbolS12.wav | **-0.0** | ISP CLIPPING |
| SymbolS13.wav | **-0.0** | ISP CLIPPING |
| SymbolS14.wav | **-0.0** | ISP CLIPPING |
| SymbolS15.wav | **-0.0** | ISP CLIPPING |
| UiSkip.wav | **-0.8** | NEAR CLIP |
| Win6.wav | **-1.8** | HOT |
| UiOpen.wav | -2.2 | |
| UiClose.wav | -2.8 | |
| Win3.wav | -3.3 | |
| SymScatterLand1.wav | -3.7 | |
| Win7.wav | -3.9 | |
| AnticipationLong.wav | -4.0 | |
| AnticipationMed.wav | -4.0 | |
| AnticipationShort.wav | -4.0 | |
| SymScatterLand2-5.wav | -4.0 | |
| SymScatterWin.wav | -4.0 | |
| SymMp2Win.wav | -4.2 | |
| SymHp2Win.wav | -4.3 | |
| Win4.wav | -4.3 | |
| Win5.wav | -4.3 | |
| SymbolB01Land3.wav | -4.4 | |
| SymbolB01Land4-5.wav | -4.7 | |
| SymHp3Win.wav | -4.8 | |
| BigWinStart.wav | -4.9 | |
| SymbolB01*.wav (main) | -4.9 | |
| SymbolS01-S11.wav | -4.9 | |
| SymbolW01*.wav | -4.9 | |
| SymHp1Win.wav | -5.0 | |
| BigWinTier.wav | -5.1 | |
| Win1.wav | -5.3 | |
| Win2.wav | -5.1 | |
| BigWinEnd.wav | -5.6 | |
| SymMp1Win.wav | -5.7 | |
| SymMp3Win.wav | -5.9 | |
| Payline.wav | -5.9 | |
| WildLand4.wav | -5.9 | |
| BaseGameMusicLoop3.wav | -6.1 | |
| ScreenShake.wav | -6.1 | |
| UiBetMax.wav | -6.2 | |
| SymMp5Win.wav | -6.2 | |
| SymMp4Win.wav | -6.4 | |
| CoinLoop.wav | -6.5 | |
| CoinLoopEnd.wav | -6.8 | |
| WildLand3.wav | -6.8 | |
| UiClick.wav | -7.3 | |
| SpinsLoop1.wav | -7.3 | |
| WildLand5.wav | -7.3 | |
| ReelLand5.wav | -7.4 | |
| WildLand1.wav | -7.4 | |
| BigWinAlert.wav | -7.9 | |
| WildLand2.wav | -8.0 | |
| BaseGameMusicLoop2.wav | -8.1 | |
| SymbolPreshow2.wav | -8.2 | |
| SpinsLoop2-3.wav | -8.2 to -8.3 | |
| ReelLand3.wav | -8.3 | |
| BaseGameMusicLoop1.wav | -8.7 | |
| SymbolPreshow1.wav | -9.6 | |
| ReelLand1.wav | -9.2 | |
| UiSelect2-3.wav | -9.2 to -9.3 | |
| SymbolPreshow5.wav | -9.4 | |
| UiBetUp.wav | -9.8 | |
| ReelLand2.wav | -9.8 | |
| UiSelect1.wav | -9.8 | |
| UiBetDown.wav | -10.1 | |
| RollupLow.wav | -10.1 | |
| SymbolPreshow3.wav | -10.5 | |
| SymbolPreshow4.wav | -10.7 | |
| ReelLand4.wav | -11.3 | |
| UiSpin.wav | -11.6 | |
| UiSpinSlam.wav | -11.6 | |
| SymbolB01Land2.wav | -12.7 | |
| SymbolB01Land1.wav | -15.7 | |
| PickerMusicLoop.wav | -5.2 | |
| AmbBg.wav | -21.3 | |

---

## QA Verification Results

### File Coverage
- **93/93 source files** documented in tables with all metrics
- **0 files missing** from documentation
- **0 phantom files** (documented but not in folder)

### Audio Integrity
- **No mono files** — all 93 are stereo (2ch)
- **No truncated files** — shortest is SymbolPreshow3 at 0.16s (valid)
- **No silent files** — no file below -60 dBFS RMS

### Identical/Duplicate Files
- **UiSpin.wav vs UiSpinSlam.wav**: Different MD5 hashes BUT identical sox stats (same audio, different WAV header metadata). Pipeline should flag these as "audio-identical".

### Clipping/Limiting Artifacts (flat factor > 0)
- BaseGameMusicLoop2.wav: flat=14.30 (pre-limited at source)
- BaseGameMusicLoop3.wav: flat=13.72 (pre-limited at source)
- BigWinStart.wav: flat=14.84 (pre-limited at source)
- **Pipeline action**: These 3 files should SKIP TruePeakLimiter to avoid double-limiting artifacts

### ISP (Inter-Sample Peak) Clipping
- SymbolS12-15.wav: True peak at **-0.0 dBTP** — these WILL clip on any DAC
- UiSkip.wav: True peak at **-0.8 dBTP** — marginal
- **Pipeline action**: TruePeakLimiter MUST engage on these files (ceiling -1.0 dBTP)

---

## GAP ANALYSIS: Current Pipeline vs Aztec Requirements

### CRITICAL: Category Detection Broken for CamelCase (3/93 = 3.2% detected!)

Current `SfxCategoryExt.fromFilename()` uses **snake_case patterns only** (`ui_`, `reel_`, `win_`, etc.).
Aztec files use **CamelCase** (`UiClick.wav`, `ReelLand1.wav`, `BigWinStart.wav`).

**Result**: Only 3 files detected (BaseGameMusicLoop1-3 match `basegamemusic` pattern). 90 files → `unknown`.

**FIX REQUIRED**: Add CamelCase→snake_case normalization before pattern matching:
```dart
// Before pattern matching:
// "BigWinStart" → "big_win_start"
// "ReelLand1" → "reel_land_1"
// "SymbolS01" → "symbol_s_01"
final normalized = _camelToSnake(filenameWithoutExtension);
```

Plus add missing patterns for Aztec-specific names:
```
CamelCase Pattern      → snake_case equivalent   → Category
UiClick, UiBet*, etc.  → ui_click, ui_bet        → uiClicks ✓ (after normalization)
ReelLand*              → reel_land               → reelMechanics ✓
Win[1-7]               → win_[1-7]               → winCelebrations ✓
WildLand*              → wild_land               → featureTriggers ✓
SymScatter*            → sym_scatter             → featureTriggers (needs pattern)
SymHp*Win              → sym_hp_win              → winCelebrations (needs pattern)
SymMp*Win              → sym_mp_win              → winCelebrations (needs pattern)
SymbolS*               → symbol_s                → reelMechanics (needs pattern: symbol_)
SymbolB01*             → symbol_b_01             → featureTriggers (needs pattern)
SymbolW01*             → symbol_w                → featureTriggers (needs pattern: symbol_w)
SymbolPreshow*         → symbol_preshow          → reelMechanics (needs pattern)
Anticipation*          → anticipation            → anticipation ✓
BigWin*                → big_win                 → winCelebrations ✓ (big_ pattern)
BigWinAlert/Start/End  → big_win_alert/start/end → musicBigWin? or winCelebrations?
SpinsLoop*             → spins_loop              → ambientLoops (needs pattern: spins_loop)
AmbBg*                 → amb_bg                  → ambientLoops ✓ (amb_ pattern)
BaseGameMusicLoop*     → base_game_music_loop    → musicBase ✓
PickerMusicLoop*       → picker_music_loop       → musicFeature (needs pattern: picker_music)
CoinLoop*              → coin_loop               → winCelebrations (needs pattern: coin_)
Payline*               → payline                 → winCelebrations (needs pattern: payline)
RollupLow*             → rollup_low              → winCelebrations ✓ (rollup_ pattern)
ScreenShake*           → screen_shake            → featureTriggers (needs pattern: screen_shake)
```

### Missing Categories in SfxCategory Enum

Current enum has 11 categories. Aztec analysis reveals need for finer granularity:

| Missing Sub-Category | Current Catch-All | Why It Matters |
|----------------------|-------------------|----------------|
| symbolLand | reelMechanics | SymbolS01-15, SymbolB01Land — different LUFS than reel mechanics |
| symbolPreshow | reelMechanics | 0.18s clicks, -70 LUFS — need special handling |
| scatterLand | featureTriggers | Escalating loudness per count — different from generic feature |
| wildLand | featureTriggers | -23 LUFS, much quieter than scatter |
| coinRollup | winCelebrations | -27 LUFS, much quieter than win fanfares |
| payline | winCelebrations | -20 LUFS, mid-tier sound |
| screenEffect | featureTriggers | One-shots, not looping |
| musicSpins | ambientLoops | 6.5s loops, different LUFS target than ambient |
| musicPicker | musicFeature | 11s loop, specific LUFS target |

### Missing Feature: Escalating Loudness Groups

Current pipeline normalizes ALL files in a category to the SAME LUFS target. But Aztec data shows:
- Win1→Win7: intentional 4.8 LUFS escalation
- ScatterLand1→5: intentional 1.8 LUFS escalation
- SymbolB01Land1→5: intentional 14.5 LUFS escalation
- BaseGameMusicLoop1→3: intentional 2.3 LUFS layer spread

**FIX REQUIRED**: Pipeline needs "group normalize" mode:
1. Detect numbered file groups (Win1-7, ScatterLand1-5, etc.)
2. Measure group LUFS average
3. Apply single gain to reach group target
4. Preserve internal relative loudness ratios

### Missing Feature: Stereo Imbalance Detection/Warning

Current pipeline tracks `channels` and `dcOffset` per file, but does NOT analyze:
- L/R peak delta (SymbolB01Land1-2 have 6-8 dB imbalance)
- L/R RMS delta
- "Audio-identical" detection (UiSpin ≈ UiSpinSlam)

**FIX REQUIRED**: Add to `SfxScanResult`:
```dart
final double peakLrDelta;     // |L_peak - R_peak| in dB
final double rmsLrDelta;      // |L_rms - R_rms| in dB
final bool isMono;            // true if L==R content
final String? duplicateOf;    // filename if audio-identical to another file
```

### Missing Feature: True Peak per File in Scan Results

`SfxScanResult` has `peakDbfs` (sample peak) but NOT `truePeakDbtp` (inter-sample peak).
SymbolS12-15 show -0.10 sample peak but -0.0 true peak — the ISP data is critical for limiter decisions.

**FIX REQUIRED**: Add `truePeakDbtp` to `SfxScanResult`, measure via rf-offline's `LoudnessMeter` which already does 4x oversampling.

### Missing Feature: Flat Factor / Pre-Limited Detection

No detection of already-limited files (BaseGameMusicLoop2-3, BigWinStart all have flat factor >13).
Applying TruePeakLimiter to these will create audible pumping artifacts.

**FIX REQUIRED**: Add `flatFactor` to `SfxScanResult`, skip limiter when >10.

### LUFS Target Mismatch

Current "Slot Game Standard" preset values vs Aztec reality:

| Category | Current Target | Aztec Reality | Delta | Action |
|----------|---------------|---------------|-------|--------|
| uiClicks | -12.0 | -22 to -33 | **10-21 dB!** | WAY too hot. Most UI sounds are -25 to -33. Keep -12 only for primary button clicks |
| reelMechanics | -16.0 | -31 | **15 dB!** | Reel lands are very quiet, not featured sounds |
| winCelebrations | -14.0 | -17 to -13 | ±3 dB | Reasonable, but needs escalation support |
| ambientLoops | -23.0 | -35 (AmbBg) | **12 dB!** | Ambient bed should be much quieter |
| featureTriggers | -14.0 | -17 to -23 | 3-9 dB | Varies wildly by type (scatter vs wild vs symbol) |
| anticipation | -18.0 | -14 to -16 | 2-4 dB | Aztec anticipation is louder than preset |
| musicBase | -23.0 | -18 to -16 | **5-7 dB!** | Base game music is much louder than -23 |

**Conclusion**: The "Slot Game Standard" preset needs a "Realistic Slot Mix" alternative based on actual production data, or per-sub-category overrides.

---

## Recommended Changes Summary (Priority Order)

### P0 — Must Fix (Wizard Broken Without These)
1. **CamelCase normalization** in `fromFilename()` — camelToSnake before pattern matching
2. **Add CamelCase-native patterns** as fallback for common naming conventions
3. **Add `truePeakDbtp` to SfxScanResult** — needed for limiter decisions

### P1 — Important (Significant Quality Impact)
4. **Group normalize** for escalating loudness groups (Win1-7, ScatterLand1-5, etc.)
5. **Stereo imbalance detection** (`peakLrDelta`, `rmsLrDelta`) in scan results
6. **Flat factor detection** to skip limiter on pre-limited files
7. **Revise LUFS presets** — current values are disconnected from real-world Aztec data

### P2 — Nice to Have
8. **New sub-categories** (symbolLand, scatterLand, wildLand, coinRollup, etc.)
9. **Audio-identical detection** (hash-based duplicate finder)
10. **"Realistic Slot Mix" preset** derived from this Aztec analysis
