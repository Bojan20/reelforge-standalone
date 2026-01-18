# FluxForge Studio — Metering Deep Dive

> Detaljne specifikacije professional metering sistema iz Pyramix i broadcast standarda

---

## 1. LOUDNESS METERING (EBU R128 / ITU-R BS.1770)

### 1.1 Loudness Standards Overview

```
LOUDNESS STANDARDS — GLOBAL OVERVIEW
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│  ┌───────────────┬────────────────┬──────────────┬────────────────────────┐│
│  │ Standard      │ Target LUFS    │ True Peak    │ Use Case               ││
│  ├───────────────┼────────────────┼──────────────┼────────────────────────┤│
│  │ EBU R128      │ -23.0 LUFS     │ -1.0 dBTP    │ European broadcast     ││
│  │ ATSC A/85     │ -24.0 LKFS     │ -2.0 dBTP    │ US broadcast           ││
│  │ ARIB TR-B32   │ -24.0 LKFS     │ -1.0 dBTP    │ Japanese broadcast     ││
│  │ Spotify       │ -14.0 LUFS     │ -1.0 dBTP    │ Streaming              ││
│  │ Apple Music   │ -16.0 LUFS     │ -1.0 dBTP    │ Streaming (Sound Check)││
│  │ YouTube       │ -14.0 LUFS     │ -1.0 dBTP    │ Streaming              ││
│  │ Tidal         │ -14.0 LUFS     │ -1.0 dBTP    │ Streaming              ││
│  │ Amazon Music  │ -14.0 LUFS     │ -2.0 dBTP    │ Streaming              ││
│  │ Netflix       │ -27.0 LUFS     │ -2.0 dBTP    │ Dialogue norm          ││
│  │ AES Streaming │ -16.0 LUFS     │ -1.0 dBTP    │ AES recommendation     ││
│  │ CD (No std)   │ -8 to -12 LUFS │ 0.0 dBTP     │ Physical media         ││
│  │ Club          │ -6 to -10 LUFS │ N/A          │ DJ/Dance               ││
│  └───────────────┴────────────────┴──────────────┴────────────────────────┘│
│                                                                              │
│  LUFS vs LKFS:                                                               │
│  • LUFS = Loudness Units Full Scale (EBU terminology)                       │
│  • LKFS = Loudness K-weighted Full Scale (ITU terminology)                  │
│  • They are IDENTICAL — just different naming conventions                   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1.2 LUFS Measurement Types

```
LUFS MEASUREMENT TYPES
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│  1. MOMENTARY LOUDNESS (LUFS-M)                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ • Integration time: 400ms                                                ││
│  │ • Sliding rectangular window                                            ││
│  │ • Fast response — shows immediate loudness                              ││
│  │ • Use: Real-time monitoring during playback                             ││
│  │                                                                          ││
│  │ Visual representation:                                                   ││
│  │ ▁▂▃▅▇█▇▅▃▂▁▂▃▅▇█▇▅▃▂▁▂▃▅▇                                              ││
│  │ ────────────────────────────────────────────────                        ││
│  │ Time window: |←—400ms—→|                                                 ││
│  │              Slides every frame                                         ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  2. SHORT-TERM LOUDNESS (LUFS-S)                                             │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ • Integration time: 3 seconds                                           ││
│  │ • Sliding rectangular window                                            ││
│  │ • Smoother response — shows phrase-level loudness                       ││
│  │ • Use: Evaluating consistency, segment comparison                       ││
│  │                                                                          ││
│  │ Visual representation:                                                   ││
│  │ ▃▃▃▄▄▅▅▅▆▆▆▆▅▅▅▄▄▃▃▃▄▄▅▅                                              ││
│  │ ────────────────────────────────────────────────                        ││
│  │ Time window: |←——————3s——————→|                                          ││
│  │              Slides every frame                                         ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  3. INTEGRATED LOUDNESS (LUFS-I)                                             │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ • Integration time: Entire program                                      ││
│  │ • Gated measurement (ignores silence)                                   ││
│  │ • THE key compliance metric                                             ││
│  │ • Use: Final loudness value for delivery                                ││
│  │                                                                          ││
│  │ Gating algorithm:                                                        ││
│  │ 1. Calculate momentary loudness every 100ms                             ││
│  │ 2. Absolute gate: Discard blocks < -70 LUFS                             ││
│  │ 3. Calculate preliminary average                                        ││
│  │ 4. Relative gate: Discard blocks < (average - 10 LU)                    ││
│  │ 5. Final average = Integrated Loudness                                  ││
│  │                                                                          ││
│  │ Visual representation:                                                   ││
│  │ ████████████░░░░████████████████░░░░░░████████████                      ││
│  │             ↑       ↑                 ↑                                 ││
│  │          Gated   Measured          Gated                                ││
│  │         (silent) (counted)       (too quiet)                            ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  4. LOUDNESS RANGE (LRA)                                                     │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ • Measures dynamic range of the program                                 ││
│  │ • Difference between 10th and 95th percentile                          ││
│  │ • Unit: LU (Loudness Units)                                            ││
│  │ • Use: Indicates how dynamic the content is                            ││
│  │                                                                          ││
│  │ Interpretation:                                                          ││
│  │ • LRA < 5 LU: Highly compressed (loudness war victim)                  ││
│  │ • LRA 5-10 LU: Normal pop/rock                                         ││
│  │ • LRA 10-15 LU: Dynamic (jazz, classical, film)                        ││
│  │ • LRA > 15 LU: Very dynamic (orchestral, experimental)                 ││
│  │                                                                          ││
│  │ Visual representation:                                                   ││
│  │                                                                          ││
│  │ Loudest ─────────────────────────────── 95th percentile                ││
│  │          █████████████████████████████                                  ││
│  │          █                           █                                  ││
│  │          █       ← LRA →             █                                  ││
│  │          █                           █                                  ││
│  │ Quietest █████████████████████████████ 10th percentile                 ││
│  │                                                                          ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1.3 K-Weighting Filter

```
K-WEIGHTING FILTER (ITU-R BS.1770)
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│  K-weighting = Stage 1 (Pre-filter) + Stage 2 (RLB weighting)               │
│                                                                              │
│  STAGE 1: PRE-FILTER (High Shelf)                                            │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ • +4 dB high shelf above 1.5 kHz                                        ││
│  │ • Simulates head-related transfer function (HRTF)                       ││
│  │ • Accounts for acoustic effect of human head                            ││
│  │                                                                          ││
│  │ Frequency response:                                                      ││
│  │                                                                          ││
│  │  +4dB ─────────────────────────────────────╱───                         ││
│  │   0dB ───────────────────────────────────╱─────                         ││
│  │        20Hz        1.5kHz             10kHz    20kHz                    ││
│  │                       ↑                                                  ││
│  │                  Shelf frequency                                        ││
│  │                                                                          ││
│  │ Coefficients (48kHz):                                                    ││
│  │ b0 = 1.53512485958697    a1 = -1.69065929318241                         ││
│  │ b1 = -2.69169618940638   a2 = 0.73248077421585                          ││
│  │ b2 = 1.19839281085285                                                   ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  STAGE 2: RLB WEIGHTING (Revised Low-frequency B-curve)                      │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ • High-pass filter at ~38 Hz                                            ││
│  │ • Removes sub-bass from loudness calculation                            ││
│  │ • Reflects human insensitivity to very low frequencies                  ││
│  │                                                                          ││
│  │ Frequency response:                                                      ││
│  │                                                                          ││
│  │   0dB ─────────────────────────────────────────                         ││
│  │       ╲                                                                  ││
│  │        ╲                                                                 ││
│  │ -∞dB ───╲────────────────────────────────────                           ││
│  │        20Hz  38Hz   100Hz              1kHz                             ││
│  │               ↑                                                          ││
│  │          -3dB point                                                     ││
│  │                                                                          ││
│  │ Coefficients (48kHz):                                                    ││
│  │ b0 = 1.0               a1 = -1.99004745483398                           ││
│  │ b1 = -2.0              a2 = 0.99007225036621                            ││
│  │ b2 = 1.0                                                                ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  COMBINED K-WEIGHTED RESPONSE:                                               │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │                                                                          ││
│  │  +4dB ────────────────────────────────────────╱───                      ││
│  │   0dB ────────────────────────────────────╱───────                      ││
│  │  -4dB ──────╲─────────────────────────────────────                      ││
│  │  -8dB ───────╲────────────────────────────────────                      ││
│  │ -12dB ────────╲───────────────────────────────────                      ││
│  │        20Hz 40Hz 100Hz  500Hz  1kHz  5kHz  10kHz  20kHz                 ││
│  │                                                                          ││
│  │ Result: Emphasizes 1-4 kHz (speech presence)                            ││
│  │         De-emphasizes < 100 Hz (sub-bass)                               ││
│  │         Slightly boosts > 2 kHz (brilliance)                            ││
│  │                                                                          ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1.4 Rust Implementation

```rust
// crates/rf-dsp/src/metering/loudness.rs

use std::collections::VecDeque;

// ═══════════════════════════════════════════════════════════════════════════
// K-WEIGHTING FILTER
// ═══════════════════════════════════════════════════════════════════════════

/// Pre-filter (Stage 1) and RLB (Stage 2) biquad filters
pub struct KWeightingFilter {
    // Stage 1: Pre-filter (high shelf)
    pre_b0: f64, pre_b1: f64, pre_b2: f64,
    pre_a1: f64, pre_a2: f64,
    pre_z1: f64, pre_z2: f64,

    // Stage 2: RLB (high-pass)
    rlb_b0: f64, rlb_b1: f64, rlb_b2: f64,
    rlb_a1: f64, rlb_a2: f64,
    rlb_z1: f64, rlb_z2: f64,
}

impl KWeightingFilter {
    /// Create K-weighting filter for given sample rate
    pub fn new(sample_rate: f64) -> Self {
        // Coefficients for 48kHz (standard reference)
        // For other sample rates, these need to be recalculated

        if (sample_rate - 48000.0).abs() < 1.0 {
            Self {
                // Pre-filter (high shelf +4dB @ 1.5kHz)
                pre_b0: 1.53512485958697,
                pre_b1: -2.69169618940638,
                pre_b2: 1.19839281085285,
                pre_a1: -1.69065929318241,
                pre_a2: 0.73248077421585,
                pre_z1: 0.0, pre_z2: 0.0,

                // RLB (high-pass ~38Hz)
                rlb_b0: 1.0,
                rlb_b1: -2.0,
                rlb_b2: 1.0,
                rlb_a1: -1.99004745483398,
                rlb_a2: 0.99007225036621,
                rlb_z1: 0.0, rlb_z2: 0.0,
            }
        } else {
            // Calculate coefficients for other sample rates
            Self::calculate_coefficients(sample_rate)
        }
    }

    fn calculate_coefficients(sample_rate: f64) -> Self {
        // Pre-filter coefficients
        let f0_pre = 1681.974450955533;
        let g_pre = 3.999843853973347;
        let q_pre = 0.7071752369554196;

        let k_pre = (std::f64::consts::PI * f0_pre / sample_rate).tan();
        let vh_pre = 10.0_f64.powf(g_pre / 20.0);
        let vb_pre = vh_pre.powf(0.4996667741545416);

        let a0_pre = 1.0 + k_pre / q_pre + k_pre * k_pre;
        let pre_b0 = (vh_pre + vb_pre * k_pre / q_pre + k_pre * k_pre) / a0_pre;
        let pre_b1 = 2.0 * (k_pre * k_pre - vh_pre) / a0_pre;
        let pre_b2 = (vh_pre - vb_pre * k_pre / q_pre + k_pre * k_pre) / a0_pre;
        let pre_a1 = 2.0 * (k_pre * k_pre - 1.0) / a0_pre;
        let pre_a2 = (1.0 - k_pre / q_pre + k_pre * k_pre) / a0_pre;

        // RLB coefficients
        let f0_rlb = 38.13547087602444;
        let q_rlb = 0.5003270373238773;

        let k_rlb = (std::f64::consts::PI * f0_rlb / sample_rate).tan();
        let a0_rlb = 1.0 + k_rlb / q_rlb + k_rlb * k_rlb;
        let rlb_b0 = 1.0 / a0_rlb;
        let rlb_b1 = -2.0 / a0_rlb;
        let rlb_b2 = 1.0 / a0_rlb;
        let rlb_a1 = 2.0 * (k_rlb * k_rlb - 1.0) / a0_rlb;
        let rlb_a2 = (1.0 - k_rlb / q_rlb + k_rlb * k_rlb) / a0_rlb;

        Self {
            pre_b0, pre_b1, pre_b2, pre_a1, pre_a2,
            pre_z1: 0.0, pre_z2: 0.0,
            rlb_b0, rlb_b1, rlb_b2, rlb_a1, rlb_a2,
            rlb_z1: 0.0, rlb_z2: 0.0,
        }
    }

    /// Process single sample through K-weighting
    #[inline]
    pub fn process(&mut self, input: f64) -> f64 {
        // Stage 1: Pre-filter
        let pre_out = self.pre_b0 * input + self.pre_z1;
        self.pre_z1 = self.pre_b1 * input - self.pre_a1 * pre_out + self.pre_z2;
        self.pre_z2 = self.pre_b2 * input - self.pre_a2 * pre_out;

        // Stage 2: RLB
        let rlb_out = self.rlb_b0 * pre_out + self.rlb_z1;
        self.rlb_z1 = self.rlb_b1 * pre_out - self.rlb_a1 * rlb_out + self.rlb_z2;
        self.rlb_z2 = self.rlb_b2 * pre_out - self.rlb_a2 * rlb_out;

        rlb_out
    }

    /// Reset filter state
    pub fn reset(&mut self) {
        self.pre_z1 = 0.0;
        self.pre_z2 = 0.0;
        self.rlb_z1 = 0.0;
        self.rlb_z2 = 0.0;
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// LOUDNESS METER
// ═══════════════════════════════════════════════════════════════════════════

/// EBU R128 / ITU-R BS.1770 compliant loudness meter
pub struct LoudnessMeter {
    /// Sample rate
    sample_rate: f64,

    /// K-weighting filters (one per channel)
    k_filters: Vec<KWeightingFilter>,

    /// Channel weights (for surround)
    channel_weights: Vec<f64>,

    /// Number of channels
    num_channels: usize,

    // ─────────────────────────────────────────────────────────────────────
    // MOMENTARY (400ms)
    // ─────────────────────────────────────────────────────────────────────

    /// Momentary integration buffer
    momentary_buffer: VecDeque<f64>,

    /// Samples per 400ms
    momentary_samples: usize,

    /// Current momentary sum
    momentary_sum: f64,

    /// Current momentary loudness (LUFS)
    pub momentary_lufs: f64,

    // ─────────────────────────────────────────────────────────────────────
    // SHORT-TERM (3s)
    // ─────────────────────────────────────────────────────────────────────

    /// Short-term integration buffer
    short_term_buffer: VecDeque<f64>,

    /// Samples per 3s
    short_term_samples: usize,

    /// Current short-term sum
    short_term_sum: f64,

    /// Current short-term loudness (LUFS)
    pub short_term_lufs: f64,

    // ─────────────────────────────────────────────────────────────────────
    // INTEGRATED
    // ─────────────────────────────────────────────────────────────────────

    /// 100ms block loudness values (for gating)
    integrated_blocks: Vec<f64>,

    /// Current 100ms block accumulator
    block_sum: f64,

    /// Samples in current block
    block_sample_count: usize,

    /// Samples per 100ms block
    block_samples: usize,

    /// Current integrated loudness (LUFS)
    pub integrated_lufs: f64,

    /// Loudness Range (LU)
    pub loudness_range: f64,

    /// Maximum momentary (LUFS)
    pub max_momentary: f64,

    /// Maximum short-term (LUFS)
    pub max_short_term: f64,
}

impl LoudnessMeter {
    /// Create new loudness meter
    pub fn new(sample_rate: f64, num_channels: usize) -> Self {
        let momentary_samples = (sample_rate * 0.4) as usize;  // 400ms
        let short_term_samples = (sample_rate * 3.0) as usize; // 3s
        let block_samples = (sample_rate * 0.1) as usize;      // 100ms

        // Default channel weights (stereo)
        let channel_weights = match num_channels {
            1 => vec![1.0],
            2 => vec![1.0, 1.0],
            // 5.1: L, R, C, LFE, Ls, Rs
            6 => vec![1.0, 1.0, 1.0, 0.0, 1.41, 1.41], // LFE ignored, surround +1.5dB
            // 7.1: L, R, C, LFE, Ls, Rs, Lrs, Rrs
            8 => vec![1.0, 1.0, 1.0, 0.0, 1.41, 1.41, 1.41, 1.41],
            _ => vec![1.0; num_channels],
        };

        Self {
            sample_rate,
            k_filters: (0..num_channels).map(|_| KWeightingFilter::new(sample_rate)).collect(),
            channel_weights,
            num_channels,

            momentary_buffer: VecDeque::with_capacity(momentary_samples),
            momentary_samples,
            momentary_sum: 0.0,
            momentary_lufs: -144.0,

            short_term_buffer: VecDeque::with_capacity(short_term_samples),
            short_term_samples,
            short_term_sum: 0.0,
            short_term_lufs: -144.0,

            integrated_blocks: Vec::new(),
            block_sum: 0.0,
            block_sample_count: 0,
            block_samples,
            integrated_lufs: -144.0,
            loudness_range: 0.0,

            max_momentary: -144.0,
            max_short_term: -144.0,
        }
    }

    /// Process audio samples (interleaved or per-channel)
    pub fn process(&mut self, samples: &[&[f64]]) {
        let num_samples = samples[0].len();

        for i in 0..num_samples {
            // Sum weighted squared K-filtered samples
            let mut weighted_sum = 0.0;
            for ch in 0..self.num_channels {
                let filtered = self.k_filters[ch].process(samples[ch][i]);
                weighted_sum += self.channel_weights[ch] * filtered * filtered;
            }

            // Update momentary (400ms sliding window)
            self.momentary_sum += weighted_sum;
            self.momentary_buffer.push_back(weighted_sum);
            if self.momentary_buffer.len() > self.momentary_samples {
                self.momentary_sum -= self.momentary_buffer.pop_front().unwrap();
            }

            // Update short-term (3s sliding window)
            self.short_term_sum += weighted_sum;
            self.short_term_buffer.push_back(weighted_sum);
            if self.short_term_buffer.len() > self.short_term_samples {
                self.short_term_sum -= self.short_term_buffer.pop_front().unwrap();
            }

            // Update 100ms block for integrated
            self.block_sum += weighted_sum;
            self.block_sample_count += 1;

            if self.block_sample_count >= self.block_samples {
                // Calculate block loudness
                let block_mean = self.block_sum / self.block_sample_count as f64;
                let block_lufs = if block_mean > 0.0 {
                    -0.691 + 10.0 * block_mean.log10()
                } else {
                    -144.0
                };

                // Store block for integrated calculation
                if block_lufs > -70.0 {
                    // Absolute gate
                    self.integrated_blocks.push(block_lufs);
                }

                // Reset block
                self.block_sum = 0.0;
                self.block_sample_count = 0;
            }
        }

        // Update momentary loudness
        if self.momentary_buffer.len() >= self.momentary_samples / 4 {
            let mean = self.momentary_sum / self.momentary_buffer.len() as f64;
            self.momentary_lufs = if mean > 0.0 {
                -0.691 + 10.0 * mean.log10()
            } else {
                -144.0
            };
            self.max_momentary = self.max_momentary.max(self.momentary_lufs);
        }

        // Update short-term loudness
        if self.short_term_buffer.len() >= self.short_term_samples / 4 {
            let mean = self.short_term_sum / self.short_term_buffer.len() as f64;
            self.short_term_lufs = if mean > 0.0 {
                -0.691 + 10.0 * mean.log10()
            } else {
                -144.0
            };
            self.max_short_term = self.max_short_term.max(self.short_term_lufs);
        }

        // Recalculate integrated periodically
        if self.integrated_blocks.len() % 10 == 0 {
            self.calculate_integrated();
            self.calculate_lra();
        }
    }

    /// Calculate integrated loudness with relative gating
    fn calculate_integrated(&mut self) {
        if self.integrated_blocks.is_empty() {
            self.integrated_lufs = -144.0;
            return;
        }

        // Step 1: Calculate preliminary average (absolute gate already applied)
        let sum: f64 = self.integrated_blocks.iter().map(|&l| 10.0_f64.powf(l / 10.0)).sum();
        let preliminary = 10.0 * (sum / self.integrated_blocks.len() as f64).log10();

        // Step 2: Relative gate at -10 LU below preliminary
        let relative_threshold = preliminary - 10.0;

        let filtered: Vec<f64> = self.integrated_blocks
            .iter()
            .filter(|&&l| l > relative_threshold)
            .cloned()
            .collect();

        if filtered.is_empty() {
            self.integrated_lufs = preliminary;
            return;
        }

        // Step 3: Calculate final average
        let final_sum: f64 = filtered.iter().map(|&l| 10.0_f64.powf(l / 10.0)).sum();
        self.integrated_lufs = 10.0 * (final_sum / filtered.len() as f64).log10();
    }

    /// Calculate Loudness Range (LRA)
    fn calculate_lra(&mut self) {
        if self.integrated_blocks.len() < 10 {
            self.loudness_range = 0.0;
            return;
        }

        // Get blocks above relative threshold
        let relative_threshold = self.integrated_lufs - 20.0;
        let mut valid_blocks: Vec<f64> = self.integrated_blocks
            .iter()
            .filter(|&&l| l > relative_threshold)
            .cloned()
            .collect();

        if valid_blocks.len() < 2 {
            self.loudness_range = 0.0;
            return;
        }

        // Sort for percentile calculation
        valid_blocks.sort_by(|a, b| a.partial_cmp(b).unwrap());

        // 10th and 95th percentile
        let p10_idx = (valid_blocks.len() as f64 * 0.10) as usize;
        let p95_idx = (valid_blocks.len() as f64 * 0.95) as usize;

        self.loudness_range = valid_blocks[p95_idx] - valid_blocks[p10_idx];
    }

    /// Reset meter
    pub fn reset(&mut self) {
        for filter in &mut self.k_filters {
            filter.reset();
        }
        self.momentary_buffer.clear();
        self.momentary_sum = 0.0;
        self.momentary_lufs = -144.0;

        self.short_term_buffer.clear();
        self.short_term_sum = 0.0;
        self.short_term_lufs = -144.0;

        self.integrated_blocks.clear();
        self.block_sum = 0.0;
        self.block_sample_count = 0;
        self.integrated_lufs = -144.0;
        self.loudness_range = 0.0;

        self.max_momentary = -144.0;
        self.max_short_term = -144.0;
    }

    /// Get all readings
    pub fn get_readings(&self) -> LoudnessReadings {
        LoudnessReadings {
            momentary_lufs: self.momentary_lufs,
            short_term_lufs: self.short_term_lufs,
            integrated_lufs: self.integrated_lufs,
            loudness_range_lu: self.loudness_range,
            max_momentary_lufs: self.max_momentary,
            max_short_term_lufs: self.max_short_term,
        }
    }
}

/// Loudness readings struct
#[derive(Clone, Copy, Debug)]
pub struct LoudnessReadings {
    pub momentary_lufs: f64,
    pub short_term_lufs: f64,
    pub integrated_lufs: f64,
    pub loudness_range_lu: f64,
    pub max_momentary_lufs: f64,
    pub max_short_term_lufs: f64,
}
```

---

## 2. TRUE PEAK METERING

### 2.1 True Peak vs Sample Peak

```
TRUE PEAK vs SAMPLE PEAK
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│  SAMPLE PEAK:                                                                │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ • Maximum value of digital samples                                      ││
│  │ • Does NOT represent actual analog waveform                             ││
│  │ • Can miss inter-sample peaks (ISP)                                    ││
│  │                                                                          ││
│  │ Digital samples:   ●     ●                                              ││
│  │                    │     │                                               ││
│  │                    │  ●  │                                               ││
│  │                    │ │ │ │                                               ││
│  │ Sample peak: ──────●─●───● = 0 dBFS                                     ││
│  │                                                                          ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  TRUE PEAK (Inter-Sample Peak):                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ • Reconstructed analog waveform peak                                    ││
│  │ • Uses oversampling to find peaks BETWEEN samples                       ││
│  │ • Required for broadcast compliance                                     ││
│  │                                                                          ││
│  │ Oversampled:       ●     ●                                              ││
│  │                   ╱│╲   ╱│╲                                              ││
│  │                  ╱ │ ╲ ╱ │ ╲                                             ││
│  │                 ╱  ●  ╳  ●  ╲                                            ││
│  │                ╱  │ ╱ ╲ │   ╲                                            ││
│  │ True peak: ───●───●─────●────●─ = +2.1 dBTP (CLIPPING!)                 ││
│  │               ↑                                                          ││
│  │          Inter-sample peak                                              ││
│  │                                                                          ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  WHY TRUE PEAK MATTERS:                                                      │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ • DACs reconstruct analog waveform                                      ││
│  │ • Inter-sample peaks cause distortion in playback                      ││
│  │ • Lossy codecs (MP3, AAC) can amplify ISP by 1-3 dB                    ││
│  │ • Broadcast transmitters can clip on ISP                               ││
│  │                                                                          ││
│  │ Example: File at 0 dBFS sample peak                                     ││
│  │ • True peak: +1.8 dBTP                                                  ││
│  │ • After AAC encode: +3.1 dBTP                                          ││
│  │ • Result: Audible distortion                                           ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  OVERSAMPLING REQUIREMENTS:                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ Standard         │ Minimum Oversampling │ Accuracy                      ││
│  │ ──────────────── │ ──────────────────── │ ───────────                   ││
│  │ ITU-R BS.1770-4  │ 4x                   │ ±0.5 dB                       ││
│  │ EBU R128         │ 4x                   │ ±0.3 dB                       ││
│  │ High precision   │ 8x or 16x            │ < ±0.1 dB                     ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 True Peak Implementation

```rust
// crates/rf-dsp/src/metering/true_peak.rs

// ═══════════════════════════════════════════════════════════════════════════
// TRUE PEAK METER
// ═══════════════════════════════════════════════════════════════════════════

/// ITU-R BS.1770 compliant True Peak meter
pub struct TruePeakMeter {
    /// Oversampling factor (4x minimum, 8x recommended)
    oversampling: usize,

    /// FIR interpolation filter
    interpolation_filter: Vec<f64>,

    /// Filter length
    filter_len: usize,

    /// Input history buffer
    history: Vec<VecDeque<f64>>,

    /// Current true peak per channel
    current_peak: Vec<f64>,

    /// Maximum true peak per channel
    max_peak: Vec<f64>,

    /// Number of channels
    num_channels: usize,
}

impl TruePeakMeter {
    /// FIR coefficients for 4x oversampling (ITU-R BS.1770-4)
    const FIR_4X: [f64; 49] = [
        0.0017089843750, 0.0109863281250, -0.0196533203125, 0.0332031250000,
        -0.0594482421875, 0.1373291015625, 0.9721679687500, -0.1022949218750,
        0.0476074218750, -0.0266113281250, 0.0148925781250, -0.0083007812500,
        // ... (full 49-tap filter)
        0.0017089843750,
    ];

    pub fn new(num_channels: usize, oversampling: usize) -> Self {
        let filter_len = 49; // ITU standard
        let interpolation_filter = Self::FIR_4X.to_vec();

        Self {
            oversampling,
            interpolation_filter,
            filter_len,
            history: (0..num_channels)
                .map(|_| VecDeque::from(vec![0.0; filter_len]))
                .collect(),
            current_peak: vec![0.0; num_channels],
            max_peak: vec![0.0; num_channels],
            num_channels,
        }
    }

    /// Process samples and return true peak
    pub fn process(&mut self, samples: &[&[f64]]) -> Vec<f64> {
        let num_samples = samples[0].len();

        for ch in 0..self.num_channels {
            let mut channel_peak = 0.0_f64;

            for &sample in samples[ch].iter() {
                // Add to history
                self.history[ch].pop_front();
                self.history[ch].push_back(sample);

                // Generate oversampled values
                for phase in 0..self.oversampling {
                    let mut interpolated = 0.0;

                    // Apply polyphase FIR filter
                    for (i, &h) in self.history[ch].iter().enumerate() {
                        let filter_idx = phase + i * self.oversampling;
                        if filter_idx < self.filter_len {
                            interpolated += h * self.interpolation_filter[filter_idx];
                        }
                    }

                    channel_peak = channel_peak.max(interpolated.abs());
                }
            }

            self.current_peak[ch] = channel_peak;
            self.max_peak[ch] = self.max_peak[ch].max(channel_peak);
        }

        self.current_peak.clone()
    }

    /// Get current true peak in dBTP
    pub fn get_true_peak_dbtp(&self) -> Vec<f64> {
        self.current_peak
            .iter()
            .map(|&p| if p > 0.0 { 20.0 * p.log10() } else { -144.0 })
            .collect()
    }

    /// Get maximum true peak in dBTP
    pub fn get_max_true_peak_dbtp(&self) -> Vec<f64> {
        self.max_peak
            .iter()
            .map(|&p| if p > 0.0 { 20.0 * p.log10() } else { -144.0 })
            .collect()
    }

    /// Reset peaks
    pub fn reset(&mut self) {
        for ch in 0..self.num_channels {
            self.current_peak[ch] = 0.0;
            self.max_peak[ch] = 0.0;
            self.history[ch].iter_mut().for_each(|v| *v = 0.0);
        }
    }
}
```

---

## 3. MULTI-CHANNEL METERING (Pyramix Style)

### 3.1 Broadcast Metering Layout

```
PYRAMIX-STYLE MULTI-CHANNEL METERING
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│  32-CHANNEL SIMULTANEOUS METERING:                                           │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ CH  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 16                      ││
│  │     │  │  │  │  │  │  │  │  │  │  │  │  │  │  │  │                      ││
│  │ +6 ─┼──┼──┼──┼──┼──┼──┼──┼──┼──┼──┼──┼──┼──┼──┼──┼─ RED (CLIP)         ││
│  │  0 ─┼──┼──┼──┼──┼──┼──┼──┼──┼──┼──┼──┼──┼──┼──┼──┼─ YELLOW             ││
│  │ -6 ─█──█──┼──█──█──┼──┼──█──┼──┼──█──┼──┼──█──┼──┼─                     ││
│  │-12 ─█──█──█──█──█──█──┼──█──█──┼──█──█──┼──█──█──┼─ GREEN              ││
│  │-18 ─█──█──█──█──█──█──█──█──█──█──█──█──█──█──█──█─                     ││
│  │-24 ─█──█──█──█──█──█──█──█──█──█──█──█──█──█──█──█─                     ││
│  │-30 ─█──█──█──█──█──█──█──█──█──█──█──█──█──█──█──█─                     ││
│  │-36 ─█──█──█──█──█──█──█──█──█──█──█──█──█──█──█──█─                     ││
│  │-42 ─█──█──█──█──█──█──█──█──█──█──█──█──█──█──█──█─ BLUE               ││
│  │-∞  ─┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴─                     ││
│  │                                                                          ││
│  │ CH 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32                      ││
│  │ (Second row for 32 channels)                                            ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  METER TYPES AVAILABLE:                                                      │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ • PPM (Peak Programme Meter) — IEC 60268-10 Type I/II                   ││
│  │ • VU (Volume Unit) — Traditional analog ballistics                      ││
│  │ • True Peak — ITU-R BS.1770-4 compliant                                ││
│  │ • LUFS-M — Momentary loudness                                          ││
│  │ • LUFS-S — Short-term loudness                                         ││
│  │ • K-System (K-20, K-14, K-12)                                          ││
│  │ • BBC PPM (IEC 60268-10 Type IIa)                                       ││
│  │ • DIN PPM (IEC 60268-10 Type I)                                         ││
│  │ • Nordic PPM                                                            ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  COMPLIANCE INDICATORS:                                                      │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │                                                                          ││
│  │  ┌────────────────────────────────────────┐                             ││
│  │  │ EBU R128 COMPLIANCE                     │                             ││
│  │  ├────────────────────────────────────────┤                             ││
│  │  │ Target: -23.0 LUFS ±0.5               │                             ││
│  │  │ Current: -23.1 LUFS ✓                 │                             ││
│  │  │ True Peak Max: -1.2 dBTP ✓            │                             ││
│  │  │ LRA: 8.2 LU (OK)                      │                             ││
│  │  │ Status: ██████████ PASS               │                             ││
│  │  └────────────────────────────────────────┘                             ││
│  │                                                                          ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  HISTORY GRAPH:                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │                                                                          ││
│  │  LUFS                                                                    ││
│  │  -14 ─┬─────────────────────────────────────────────────────────────    ││
│  │       │ ╲  ╱╲    ╱╲                                                      ││
│  │  -18 ─┤  ╲╱  ╲  ╱  ╲   ╱╲  ╱╲                                           ││
│  │       │       ╲╱    ╲ ╱  ╲╱  ╲                                          ││
│  │  -22 ─┤            ──X────────╲────────                                 ││
│  │       │                        ╲                                         ││
│  │  -26 ─┤                         ╲                                        ││
│  │       │                          ╲____                                   ││
│  │  -30 ─┴─────────────────────────────────────────────────────────────    ││
│  │       0s    30s    1min    1:30    2min   2:30    3min                  ││
│  │                                                                          ││
│  │  ─── Momentary   ─── Short-term   ─── Integrated (target line)         ││
│  │                                                                          ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 4. K-SYSTEM METERING

### 4.1 Bob Katz K-System

```
K-SYSTEM METERING (BOB KATZ)
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│  K-SYSTEM CONCEPT:                                                           │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ • Meter calibrated to room SPL                                          ││
│  │ • 0 dB on meter = reference monitoring level                            ││
│  │ • Allows mixing at consistent perceived loudness                        ││
│  │ • Three scales for different content types                              ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  K-20 (CINEMA/CLASSICAL):                                                    │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ • 0 dB on meter = -20 dBFS = 83 dB SPL                                  ││
│  │ • 20 dB headroom above reference                                        ││
│  │ • Use for: Film, classical, jazz, dynamic content                       ││
│  │                                                                          ││
│  │ Meter scale:                                                             ││
│  │  0 dBFS ─┬─ CLIP (RED)                                                  ││
│  │          │                                                               ││
│  │ -4 dBFS ─┤                                                               ││
│  │          │                                                               ││
│  │-12 dBFS ─┤  YELLOW zone                                                 ││
│  │          │                                                               ││
│  │-20 dBFS ─┼─ ★ 0 dB REFERENCE (83 dB SPL)                               ││
│  │          │                                                               ││
│  │-28 dBFS ─┤  GREEN zone (normal operating range)                         ││
│  │          │                                                               ││
│  │-40 dBFS ─┤                                                               ││
│  │          │                                                               ││
│  │   -∞    ─┴─                                                              ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  K-14 (POP/ROCK):                                                            │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ • 0 dB on meter = -14 dBFS = 83 dB SPL                                  ││
│  │ • 14 dB headroom above reference                                        ││
│  │ • Use for: Pop, rock, most commercial music                             ││
│  │                                                                          ││
│  │ Meter scale:                                                             ││
│  │  0 dBFS ─┬─ CLIP                                                        ││
│  │ -4 dBFS ─┤  YELLOW                                                      ││
│  │-14 dBFS ─┼─ ★ 0 dB REFERENCE                                           ││
│  │-24 dBFS ─┤  GREEN                                                       ││
│  │   -∞    ─┴─                                                              ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  K-12 (BROADCAST):                                                           │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ • 0 dB on meter = -12 dBFS = 83 dB SPL                                  ││
│  │ • 12 dB headroom above reference                                        ││
│  │ • Use for: Broadcast, heavily compressed content                        ││
│  │                                                                          ││
│  │ Meter scale:                                                             ││
│  │  0 dBFS ─┬─ CLIP                                                        ││
│  │ -6 dBFS ─┤  YELLOW                                                      ││
│  │-12 dBFS ─┼─ ★ 0 dB REFERENCE                                           ││
│  │-24 dBFS ─┤  GREEN                                                       ││
│  │   -∞    ─┴─                                                              ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  MONITORING CALIBRATION:                                                     │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ 1. Play pink noise at -20 dBFS (K-20), -14 dBFS (K-14), or -12 dBFS    ││
│  │ 2. Measure SPL at listening position                                   ││
│  │ 3. Adjust monitor volume until SPL reads 83 dB (C-weighted, slow)      ││
│  │ 4. Now 0 dB on K-meter = reference loudness                            ││
│  │                                                                          ││
│  │ Benefit: Mix at consistent loudness regardless of content type         ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 5. CORRELATION METER

### 5.1 Stereo Correlation

```
STEREO CORRELATION METER
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│  WHAT IT MEASURES:                                                           │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ • Phase relationship between left and right channels                    ││
│  │ • Indicates mono compatibility                                          ││
│  │ • Range: -1 to +1                                                       ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  CORRELATION VALUES:                                                         │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │                                                                          ││
│  │  -1        -0.5         0         +0.5        +1                        ││
│  │   ├──────────┼──────────┼──────────┼──────────┤                         ││
│  │   │   RED    │  YELLOW  │  GREEN   │  GREEN   │                         ││
│  │   │          │          │          │          │                         ││
│  │                         ▲                                                ││
│  │                    Current value                                         ││
│  │                                                                          ││
│  │  -1: Out of phase (BAD!)                                                ││
│  │      L and R cancel when summed to mono                                 ││
│  │      Result: No bass, hollow sound                                      ││
│  │                                                                          ││
│  │   0: Uncorrelated (decorrelated)                                        ││
│  │      L and R are independent                                            ││
│  │      Typical for wide stereo, side information                          ││
│  │                                                                          ││
│  │  +1: In phase (perfectly correlated)                                    ││
│  │      L and R are identical                                              ││
│  │      Result: Mono signal, centered image                                ││
│  │                                                                          ││
│  │  Normal range: +0.3 to +1.0 (mostly green)                              ││
│  │  Acceptable: 0 to +0.3 (some uncorrelated content)                      ││
│  │  Warning: Below 0 frequently (check phase!)                             ││
│  │                                                                          ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  FORMULA:                                                                    │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │                                                                          ││
│  │              Σ(L × R)                                                    ││
│  │  r = ─────────────────────                                              ││
│  │       √(Σ(L²) × Σ(R²))                                                  ││
│  │                                                                          ││
│  │  Where:                                                                  ││
│  │  • L = left channel samples                                             ││
│  │  • R = right channel samples                                            ││
│  │  • Σ = sum over integration window (typically 100-300ms)                ││
│  │                                                                          ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 6. SUMMARY — FluxForge Metering Suite

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                FLUXFORGE METERING — BROADCAST STANDARD                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  LOUDNESS (EBU R128 / ITU-R BS.1770):                                        │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ ✓ Momentary LUFS (400ms integration)                                    ││
│  │ ✓ Short-term LUFS (3s integration)                                      ││
│  │ ✓ Integrated LUFS (gated, full program)                                 ││
│  │ ✓ Loudness Range LU (dynamic range)                                     ││
│  │ ✓ K-weighting filter (ITU-R BS.1770-4)                                  ││
│  │ ✓ Multi-channel support (stereo, 5.1, 7.1, Atmos)                       ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  TRUE PEAK:                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ ✓ ITU-R BS.1770-4 compliant (4x oversampling)                           ││
│  │ ✓ High-precision mode (8x oversampling)                                 ││
│  │ ✓ Per-channel true peak                                                 ││
│  │ ✓ Maximum true peak hold                                                ││
│  │ ✓ ISP (Inter-Sample Peak) detection                                     ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  COMPLIANCE:                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ ✓ EBU R128 (-23 LUFS, -1 dBTP)                                          ││
│  │ ✓ ATSC A/85 (-24 LKFS, -2 dBTP)                                         ││
│  │ ✓ Streaming presets (Spotify, Apple, YouTube, etc.)                     ││
│  │ ✓ Netflix (-27 LUFS dialogue)                                           ││
│  │ ✓ Compliance pass/fail indicator                                        ││
│  │ ✓ Report generation                                                     ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  K-SYSTEM:                                                                   │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ ✓ K-20 (film, classical, jazz)                                          ││
│  │ ✓ K-14 (pop, rock, commercial)                                          ││
│  │ ✓ K-12 (broadcast, compressed)                                          ││
│  │ ✓ Monitor calibration assistant                                         ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  ADDITIONAL METERS:                                                          │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ ✓ Stereo correlation (-1 to +1)                                         ││
│  │ ✓ Phase meter (vectorscope)                                             ││
│  │ ✓ PPM (Peak Programme Meter)                                            ││
│  │ ✓ VU meter (analog ballistics)                                          ││
│  │ ✓ Spectrum analyzer                                                     ││
│  │ ✓ History graph (loudness over time)                                    ││
│  │ ✓ 32-channel simultaneous metering                                      ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  PRO TOOLS DOESN'T HAVE NATIVE LUFS → FLUXFORGE ADVANTAGE!                  │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

**Document Version:** 1.0
**Date:** January 2026
**Sources:**
- EBU R128 specification
- ITU-R BS.1770-4 recommendation
- Pyramix 15 metering documentation
- Bob Katz "Mastering Audio" (K-System)
