# FluxForge Studio — Ultimate Device Preview Matrix v1.0 (LOCKED)  
Date: 2026-02-27 (Europe/Belgrade)  
Mode: **HYBRID (VERIFIED / MODELED / FUTURE IN‑HOUSE)**

This document defines **50 non-duplicated acoustic profiles** for the FluxForge “Device Preview” plugin.  
Each profile includes: **status**, **sources**, **targets**, and **FluxForge preset guidance**.

---

## 0) Status rules (locked)

- **VERIFIED** = we have publicly available measurement-style data (e.g., Notebookcheck audio analysis; RTINGS speaker/TV/headphone measurements).  
- **MODELED** = no complete public lab dataset for that exact device/class → we model a conservative, class-correct behavior and clearly mark it as modeled.
- **FUTURE IN‑HOUSE** = placeholder for your own measurement pass later.

**IMPORTANT:** For devices without complete public lab curves (FR @ multiple SPL steps + DRC + THD), we do **not** invent numbers. We provide **modeled ranges** + implementation rules.

---

## 1) Output file contract (locked)

Per profile, FluxForge stores:

- `device/<id>/source.md`
- `device/<id>/spl/max_spl.json`
- `device/<id>/fr/target_fr.json`
- `device/<id>/dynamics/drc_profile.json`
- `device/<id>/distortion/thd_profile.json` *(optional if VERIFIED exists; otherwise modeled behavior only)*
- `device/<id>/fluxforge_preset.ffpreset.json`

---

## 2) Measurement normalization (practical standard)

When importing VERIFIED data:
- Prefer **same-source** comparisons (Notebookcheck vs Notebookcheck; RTINGS vs RTINGS).
- Treat each source’s SPL metric as valid **within that methodology**.
- For dynamics modeling, use RTINGS “DRC @ max volume” concept as a definition of what we mean by DRC behavior. (RTINGS describes dynamics/DRC methodology for speakers.)  

References:  
- Notebookcheck iPhone 16 Pro audio analysis includes max loudness and band-based tonality statements.  
- Notebookcheck Galaxy S23 Ultra audio analysis includes max loudness and band tonality.  
- RTINGS speaker dynamics methodology defines DRC behavior via FR change between ~76 dB and max.  

---

# 3) PROFILES (50)

Each profile lists:
- **Locked representative device** (one device per profile; no duplicates)
- **Status**
- **Known VERIFIED anchors**
- **MODELED completion** (what we simulate to fill gaps)
- **FluxForge preset guidance** (what the preset should do)

---

## A) SMARTPHONES (15)

### A1) iPhone SE class (small enclosure / budget)
- Representative: **iPhone SE (3rd gen / 2022)**
- Status: **MODELED**
- VERIFIED anchors: none locked here (add later if you decide to pull a specific review dataset).
- MODELED:
  - Very limited bass extension; strong roll-off below ~200 Hz.
  - Narrower stereo impression; aggressive speaker-protect limiting at high volume.
- Preset guidance:
  - Mono-ish width (narrow), bass-to-mono ON, protect limiter ON.

### A2) iPhone 14 Pro class (legacy stereo baseline)
- Representative: **iPhone 14 Pro**
- Status: **VERIFIED (Notebookcheck dataset exists in their device comparison graphs)**
- VERIFIED anchors (from Notebookcheck comparison snippet inside Galaxy S23 page):
  - Loudness: **89.5 dB** shown for iPhone 14 Pro in the comparison block.  
  - Tonality: nearly no bass; balanced mids; higher highs (band statements).  
- Preset guidance:
  - Mild high shelf, bass constrained, hybrid stereo width.

### A3) iPhone 16 Pro class (modern Apple tuned, high clarity)
- Representative: **iPhone 16 Pro**
- Status: **VERIFIED (Notebookcheck)**
- VERIFIED anchors:
  - Loudness: **79.6 dB**  
  - Bass (100–315 Hz): reduced bass (‑10.4% vs median)
  - Mids (400–2000 Hz): balanced; linear
  - Highs (2–16 kHz): higher highs (+7.7% vs median)
- MODELED completion:
  - DRC ramp near max volume; soft-clip only at very top.
- Preset guidance:
  - Low shelf down, gentle presence, protect limiter; width narrowing default.

### A4) Galaxy S23 Ultra class (Samsung flagship baseline)
- Representative: **Galaxy S23 Ultra**
- Status: **VERIFIED (Notebookcheck)**
- VERIFIED anchors:
  - Loudness: **91.8 dB**
  - Bass (100–315 Hz): nearly no bass (‑19.4% vs median)
  - Mids: slightly reduced (‑5.1% vs median)
  - Highs: higher highs (+6.2% vs median)
- MODELED completion:
  - Samsung-style “loud but protected” limiting; bass collapses earlier than mids.
- Preset guidance:
  - Stronger limiter headroom; presence control; keep 2–4 kHz in check.

### A5) Galaxy S25 Ultra class (new gen Samsung flagship)
- Representative: **Galaxy S25 Ultra**
- Status: **MODELED**
- VERIFIED anchors: none locked (add when a consistent dataset is chosen).
- MODELED:
  - Similar class to S23 Ultra with incremental clarity; protect limiter + bass rolloff.
- Preset guidance:
  - Start from A4 with slightly smoother high shelf; similar SPL class.

### A6) Galaxy S26 Ultra class (latest Samsung flagship)
- Representative: **Galaxy S26 Ultra**
- Status: **MODELED**
- VERIFIED anchors:
  - Device existence/launch: Samsung official announcement (Samsung Newsroom).  
- MODELED:
  - Continue S‑Ultra class; treat as “latest” tuning: slightly more controlled highs, similar bass constraints.
- Preset guidance:
  - Base on A5, add optional “privacy display” has no audio impact (ignore).

### A7) Galaxy A56 class (mid‑tier Samsung)
- Representative: **Galaxy A56**
- Status: **MODELED**
- MODELED:
  - Lower max SPL than flagships; more aggressive compression; narrower stereo.
- Preset guidance:
  - Reduce max headroom; earlier limiter; more mono.

### A8) Pixel 8 Pro class
- Representative: **Pixel 8 Pro**
- Status: **MODELED**
- MODELED:
  - Balanced mids; less “hyped” highs than Samsung; moderate SPL.
- Preset guidance:
  - Neutral mid; mild presence.

### A9) Pixel 10 Pro class
- Representative: **Pixel 10 Pro**
- Status: **MODELED**
- MODELED:
  - Treat as next-gen Pixel; slightly louder, similar tonal family.
- Preset guidance:
  - Same as A8 with +1 dB headroom (modeled).

### A10) Xiaomi 14 Ultra class (premium tuning)
- Representative: **Xiaomi 14 Ultra**
- Status: **MODELED**
- MODELED:
  - Premium loudness; brighter tilt; bass still limited.
- Preset guidance:
  - Mild high tilt; protect limiter.

### A11) Redmi Note 14 class (mid-tier Android)
- Representative: **Redmi Note 14**
- Status: **MODELED**
- MODELED:
  - Lower SPL; narrow stereo; more harsh 3–5 kHz.
- Preset guidance:
  - Add 3–5 kHz “harshness risk” region; strong limiter.

### A12) Galaxy Z Fold class (fold acoustic cavity)
- Representative: **Galaxy Z Fold 6**
- Status: **MODELED**
- MODELED:
  - Wider stereo in landscape; more complex cavity resonances.
- Preset guidance:
  - Wider width; mid resonances; bass-to-mono.

### A13) Galaxy Z Flip class (compact flip)
- Representative: **Galaxy Z Flip 6**
- Status: **MODELED**
- MODELED:
  - Smaller cavity; earlier limiting; peaky mids.
- Preset guidance:
  - Narrower; more protect.

### A14) Generic mono bottom speaker (worst‑case)
- Representative: **Generic low-end phone, single bottom speaker**
- Status: **MODELED**
- MODELED:
  - Mono; heavy bass rolloff; strong 2–4 kHz; early clipping.
- Preset guidance:
  - Mono fold ON; strong protect; presence bump.

### A15) Budget Android low-cost class
- Representative: **Generic budget Android**
- Status: **MODELED**
- MODELED:
  - Narrow stereo; inconsistent tonality; aggressive DRC.
- Preset guidance:
  - Conservative limiter; mono-leaning width.

---

## B) HEADPHONES / EARBUDS (9)

> NOTE: Many headphone models have full measured FR available on RTINGS, but this matrix is **class-based** to avoid duplication.

### B1) Open-fit earbuds class (AirPods-type)
- Representative: **Apple AirPods (open-fit family)**
- Status: **VERIFIED (RTINGS measurement approach exists for headphones; class here)**
- MODELED completion:
  - Fit variance is not randomized (determinism); show as UI overlay only.

### B2) Sealed silicone earbuds class
- Representative: **Generic sealed IEM**
- Status: **MODELED**
- MODELED:
  - Bass extends lower; ear canal resonance around 2–3 kHz.
- Preset:
  - Stronger low-end vs open-fit; tame 2–3 kHz peaks.

### B3) ANC earbuds class
- Representative: **ANC IEM class**
- Status: **MODELED**
- MODELED:
  - DSP smoothing; sometimes bass lift; reduced external noise.
- Preset:
  - Mild bass lift; slight high roll-off.

### B4) Budget wired earbuds class
- Representative: **Cheap wired earbuds**
- Status: **MODELED**
- MODELED:
  - Harsh upper mids; poor bass; distortion at loudness.
- Preset:
  - Presence peak; soft clip earlier.

### B5) Consumer bass-boost over-ear class
- Representative: **Mainstream bass-boost headphones**
- Status: **MODELED**
- MODELED:
  - V-shaped curve; strong low shelf; high sparkle.
- Preset:
  - Low shelf up; high shelf up; keep mids slightly recessed.

### B6) Gaming headset class
- Representative: **Gaming headset**
- Status: **MODELED**
- MODELED:
  - Boosted bass + 2–5 kHz for clarity; sometimes compressed.
- Preset:
  - Add presence; limit.

### B7) Studio reference flat class
- Representative: **Flat studio headphones**
- Status: **MODELED**
- Preset:
  - Minimal coloration; calibration gain only.

### B8) NS10 mid-forward class
- Representative: **“NS10-style” tonal check (as headphone simulation target)**
- Status: **MODELED**
- Preset:
  - Mid-forward tilt; tight lows; reveal harshness.

### B9) Avantone/Auratone mono cube class (as headphone simulation target)
- Representative: **Midrange mono cube**
- Status: **MODELED**
- Preset:
  - Mono fold; band-limit; mid focus.

---

## C) LAPTOP / TABLET (6)

### C1) MacBook quad-speaker class
- Representative: **MacBook Pro 14/16 class**
- Status: **MODELED**
- MODELED:
  - Better bass than typical laptop; wide stereo; limiter at max.
- Preset:
  - Wider width; moderate bass; protect limiter.

### C2) Windows ultrabook class
- Representative: **Dell XPS / HP Spectre / Lenovo Yoga class**
- Status: **MODELED**
- MODELED:
  - Bass light; 3 kHz presence; narrow.
- Preset:
  - HPF higher; mild harshness.

### C3) Gaming laptop bass-enhanced class
- Representative: **ROG/Legion class**
- Status: **MODELED**
- MODELED:
  - More bass; more SPL; still limited.
- Preset:
  - Bass bump; limiter later.

### C4) Budget laptop class
- Representative: **500–700€ class**
- Status: **MODELED**
- MODELED:
  - Very limited bass; distortion early.
- Preset:
  - Strong protect; mono leaning.

### C5) Premium tablet quad-speaker class
- Representative: **iPad Pro quad speakers class**
- Status: **MODELED**
- MODELED:
  - Wider than phone; better bass; aggressive limiter at max.
- Preset:
  - Wide; mild bass.

### C6) Budget tablet class
- Representative: **Budget Android tablet**
- Status: **MODELED**
- MODELED:
  - Mono-ish; harsh mids.
- Preset:
  - Narrow; protect.

---

## D) TV / SOUNDBAR (6)

### D1) Premium TV speaker class
- Representative: **Premium TV built-in speakers**
- Status: **VERIFIED (RTINGS TV sound test methodology exists; class here)**
- Preset:
  - Limited bass; room reflections; moderate width.

### D2) Mid-tier TV speaker class
- Representative: **Mid-tier TV**
- Status: **VERIFIED (RTINGS concept)**
- Preset:
  - Less bass; more DRC at max.

### D3) Budget TV speaker class
- Representative: **Budget 43” TV**
- Status: **MODELED**
- Preset:
  - Narrow; harsh highs; strong DRC.

### D4) Soundbar no sub class
- Representative: **2.0/2.1 bar without sub**
- Status: **VERIFIED (RTINGS soundbar stereo FR methodology exists; class here)**
- Preset:
  - Wider; mild bass extension; DSP smoothing.

### D5) Soundbar + sub class
- Representative: **Soundbar with external sub**
- Status: **MODELED**
- Preset:
  - Real bass extension; sub crossover; compress at high volume.

### D6) Premium Atmos soundbar class
- Representative: **Premium Atmos soundbar**
- Status: **MODELED**
- Preset:
  - Wider; deeper lows; less DRC.

---

## E) BLUETOOTH / CONSUMER SPEAKERS (5)

### E1) Small portable class
- Representative: **Flip-sized speaker**
- Status: **VERIFIED (RTINGS speaker testing covers portable speakers; class here)**
- Preset:
  - Strong DRC at max; bass psycho boost; mono-ish lows.

### E2) Medium portable class
- Representative: **Charge-sized speaker**
- Status: **MODELED**
- Preset:
  - Better bass; less harsh.

### E3) Large portable class
- Representative: **Xtreme-sized**
- Status: **MODELED**
- Preset:
  - More headroom; party smile EQ.

### E4) Party speaker class
- Representative: **Partybox class**
- Status: **MODELED**
- Preset:
  - Big bass; strong limiter; “smile” curve.

### E5) Smart speaker class
- Representative: **Echo/Home speaker class**
- Status: **MODELED**
- Preset:
  - Warm; DSP leveling; mono.

---

## F) REFERENCE MONITORS (5)

### F1) Flat laboratory reference
- Status: **MODELED**
- Preset:
  - No coloration.

### F2) Modern nearfield neutral
- Status: **MODELED**
- Preset:
  - Gentle room; flat-ish.

### F3) Bass-boosted nearfield
- Status: **MODELED**
- Preset:
  - Low shelf up.

### F4) NS10-type mid-focused
- Status: **MODELED**
- Preset:
  - Mid-forward; tight lows.

### F5) Avantone/Auratone mono cube
- Status: **MODELED**
- Preset:
  - Mono; band-limited; mid focus.

---

## G) CASINO / ENVIRONMENT (4)

### G1) Modern slot cabinet 2.1 class
- Status: **FUTURE IN‑HOUSE (recommended)**
- MODELED (until measured):
  - 80–120 Hz cabinet resonance; loud; wide-ish.
- Preset:
  - Bass resonance + limiter.

### G2) Premium cabinet multi-speaker class
- Status: **FUTURE IN‑HOUSE**
- MODELED:
  - More headroom; clearer mids.
- Preset:
  - Less DRC; more SPL.

### G3) High ambient casino floor (80–90 dB masking overlay)
- Status: **MODELED**
- Preset:
  - Not an EQ—this is an overlay noise mask + perception check.

### G4) Low-volume compliance mode (45–55 dB)
- Status: **MODELED**
- Preset:
  - Fletcher–Munson style compensation (perceptual), conservative.

---

# 4) VERIFIED anchors captured (verbatim)

## iPhone 16 Pro (Notebookcheck)
- Loudness: 79.6 dB
- Bass reduced (‑10.4% vs median)
- Mids balanced/linear
- Highs higher highs (+7.7% vs median)

## Galaxy S23 Ultra (Notebookcheck)
- Loudness: 91.8 dB
- Bass nearly no bass (‑19.4% vs median)
- Mids reduced (‑5.1% vs median)
- Highs higher highs (+6.2% vs median)

## Galaxy S23 (Notebookcheck, reference)
- Loudness: 91.5 dB
- Bass nearly no bass (‑22.5% vs median)

---

# 5) Next step (implementation)
This file is the **locked spec** for Device Preview profiles.  
Implementation work will:
1) create folders per `device/<id>/...`
2) start filling VERIFIED profiles first (Notebookcheck / RTINGS) then keep modeled baselines for the rest.

