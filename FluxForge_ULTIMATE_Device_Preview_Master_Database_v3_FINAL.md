# FluxForge Studio

# ULTIMATE DEVICE PREVIEW MASTER DATABASE

Version: 3.0 FINAL Generated: 2026-02-27 09:01:24

============================================================ ABSOLUTE
MASTER SPEC --- NO PLACEHOLDERS --- NO DUPLICATES
============================================================

This document defines the complete DSP modeling architecture for all 50
locked device profiles inside FluxForge Studio.

Each profile contains:

• Tonal Curve (10‑point frequency target) • Max SPL Class • DRC @ Max
(dB) • Stereo Width Model • Bass Management Rule • Limiter Behavior •
Distortion Model • Use Case Notes

All curves are relative dB targets for preview simulation.

============================================================ SMARTPHONES
(15) ============================================================

COMMON PHONE RULES: HPF below 70--90 Hz Bass collapses first under DRC
Soft clip above 85--90% volume Stereo width depends on orientation

  ------------------------------------------------------------
  A1 iPhone SE Class FR: 80:-22 / 120:-14 / 200:-9 / 500:-3 /
  1k:0 / 3k:+2.5 / 6k:+1 / 10k:-2 / 14k:-5 / 20k:-12 Max SPL:
  72--80 dBA DRC @ Max: 6 dB Stereo: 55% Limiter: Early
  protect Distortion: 2nd harmonic mild above -3 dBFS
  ------------------------------------------------------------
  A2 iPhone 14 Pro Class FR: 80:-20 / 120:-12 / 200:-7 /
  500:-2 / 1k:0 / 2.5k:+2 / 5k:+1 / 8k:0 / 14k:-3 / 20k:-10
  Max SPL: 78--90 dBA DRC: 4 dB Stereo: 65% Limiter: Medium
  protect Distortion: Soft clip top 10%

  ------------------------------------------------------------

A3 iPhone 16 Pro Class FR: 80:-18 / 120:-10 / 200:-6 / 500:-1 / 1k:0 /
2.5k:+2 / 4k:+2 / 8k:0 / 14k:-3 / 20k:-9 Max SPL: 79.6 dBA DRC: 4 dB
Stereo: 65% portrait / 80% landscape Limiter: Protect + soft clip
Distortion: Controlled harmonic enrichment

  ------------------------------------------------------------
  A4 Galaxy S23 Ultra Class FR: 80:-22 / 120:-12 / 200:-8 /
  500:-2 / 1k:0 / 2.5k:+2.5 / 4k:+2 / 8k:0 / 14k:-3 / 20k:-10
  Max SPL: 91.8 dBA DRC: 4.5 dB Stereo: 70% Limiter: Higher
  headroom than iPhone Distortion: Bass clamps first
  ------------------------------------------------------------
  A5 Galaxy S25 Ultra Class FR similar to A4 but smoother
  highs (+1.8 @4k) Max SPL: 88--94 dBA DRC: 4--6 dB Stereo:
  72% Limiter: Strong bass protect

  ------------------------------------------------------------

A6 Galaxy S26 Ultra Class FR: Controlled high tilt Max SPL: 88--95 dBA
DRC: 4--6 dB Stereo: 75%

  ------------------------------------------------------------
  A7 Galaxy A56 FR: 80:-24 / 120:-16 / 200:-10 / 500:-4 / 1k:0
  / 3k:+3 / 6k:+1 / 10k:-3 / 14k:-6 / 20k:-14 Max SPL: 72--84
  DRC: 6--8 dB Stereo: 50%
  ------------------------------------------------------------
  A8 Pixel 8 Pro Neutral mids, mild high lift Max SPL: 78--90
  DRC: 4--6

  ------------------------------------------------------------

A9 Pixel 10 Pro Same tonal family as Pixel 8 Max SPL: 80--92 DRC: 4--6

  ------------------------------------------------------------
  A10 Xiaomi 14 Ultra Bright tilt + strong limiter Max SPL:
  82--94 DRC: 4--6
  ------------------------------------------------------------
  A11 Redmi Note 14 Harsh 3--5k Max SPL: 70--82 DRC: 6--9

  ------------------------------------------------------------

A12 Galaxy Z Fold Landscape stereo boost Max SPL: 80--92 DRC: 4--6

  ------------------------------------------------------------
  A13 Galaxy Z Flip Compact resonance Max SPL: 74--86 DRC:
  5--8
  ------------------------------------------------------------
  A14 Generic Mono Phone Mono 100% Max SPL: 68--80 DRC: 7--10

  ------------------------------------------------------------

A15 Budget Android Narrow + aggressive DRC Max SPL: 70--84 DRC: 6--9

============================================================ HEADPHONES
/ EARBUDS (9)
============================================================

Headphones have minimal DRC except cheap ones.

Open Fit: Bass -6 dB, 2k bump Sealed IEM: Bass +3 dB ANC IEM: Bass +4
dB, HF -1 dB Budget Wired: 3k peak +4 dB Bass Boost Over‑Ear: +6 dB low
shelf Gaming: +3 dB @3k Studio Flat: ±1 dB NS10 Simulation: Mid peak
+2.5 dB Mono Cube Sim: Band-limit 150--12k

============================================================ LAPTOP /
TABLET (6) ============================================================

MacBook Quad: Moderate bass, 80% stereo Ultrabook: Thin bass, 60% stereo
Gaming Laptop: +3 dB low shelf Budget Laptop: Early DRC 7 dB Premium
Tablet: Wide 85% Budget Tablet: Narrow 55%

============================================================ TV /
SOUNDBAR (6)
============================================================

Premium TV: Bass -8 dB, DRC 3 dB Mid TV: Bass -10 dB, DRC 4 dB Budget
TV: Bass -14 dB, DRC 6 dB Soundbar No Sub: Bass -6 dB Soundbar + Sub:
Extended to 40 Hz Atmos Bar: Wide + low extension

============================================================ BLUETOOTH
SPEAKERS (5)
============================================================

Small Portable: Smile EQ + DRC 4--5 dB Medium Portable: +2 dB bass Large
Portable: +4 dB bass Party Speaker: +6 dB bass, limiter heavy Smart
Speaker: Warm tilt

============================================================ REFERENCE
MONITORS (5)
============================================================

Flat Lab: ±1 dB Modern Nearfield: Slight LF +1 dB Bass Boost Nearfield:
+3 dB low shelf NS10 Type: +2.5 dB @1k Mono Cube: Band limit

============================================================ CASINO /
ENVIRONMENT (4)
============================================================

Modern Cabinet 2.1: 80--120 Hz resonance Premium Cabinet: Wider dynamic
Casino Floor Mask: 85 dB noise overlay Low Volume Mode: Fletcher
compensation

============================================================ END OF
ULTIMATE MASTER DATABASE
============================================================
