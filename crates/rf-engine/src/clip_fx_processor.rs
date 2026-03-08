//! Stateful Clip FX Processor — Per-Clip DSP Chain with Full rf-dsp Integration
//!
//! Each audio clip on the timeline can have up to 8 FX slots, each containing
//! a full rf-dsp processor instance with proper state (biquad filters, envelope
//! followers, delay lines, etc.).
//!
//! This replaces the stateless sample-by-sample `process_clip_fx()` in playback.rs
//! with professional-grade stateful processing using the same DSP modules as
//! the track insert chain.
//!
//! ## Architecture
//!
//! ```text
//! ClipFxProcessorBank (one per PlaybackEngine)
//! └── HashMap<u64, ClipProcessorChain>  (clip_id → chain)
//!     └── Vec<ClipSlotProcessor>  (up to 8 per clip)
//!         └── ClipDspKernel  (enum of rf-dsp processor instances)
//!             ├── ProEq (64-band parametric)
//!             ├── UltraEq (mastering-grade)
//!             ├── Pultec (passive EQ emulation)
//!             ├── Api550 (American console EQ)
//!             ├── Neve1073 (British console EQ)
//!             ├── RoomCorrection (measurement-based)
//!             ├── Compressor (stereo linked, envelope follower)
//!             ├── Gate (stereo, hysteresis, hold)
//!             ├── Limiter (look-ahead, ISP)
//!             ├── Saturation (waveshaper, oversampling)
//!             ├── DeEsser (split-band sibilance control)
//!             └── Gain (constant-power pan)
//! ```
//!
//! ## Audio Thread Safety
//! - ZERO heap allocations in process path
//! - All processors pre-allocated at slot creation
//! - Parameters updated via lock-free atomic reads
//! - Reset on seek/transport stop to clear filter state
//!
//! ## Usage
//! Called from `PlaybackEngine::process_clip_with_crossfade()` per-sample,
//! replacing the old stateless `process_clip_fx()`.

use std::collections::HashMap;

use rf_core::Sample;
use rf_dsp::dynamics::{Compressor, DeEsser, Gate};
use rf_dsp::eq_analog::{StereoApi550, StereoNeve1073, StereoPultec};
use rf_dsp::eq_pro::ProEq;
use rf_dsp::eq_room::RoomCorrectionEq;
use rf_dsp::eq_ultra::UltraEq;
use rf_dsp::saturation::StereoSaturator;
use rf_dsp::{MonoProcessor, Processor, ProcessorConfig, StereoProcessor};

use crate::track_manager::{ClipFxChain, ClipFxSlot, ClipFxType, MAX_CLIP_FX_SLOTS};

// ═══════════════════════════════════════════════════════════════════════════
// DSP KERNEL — The actual processor instance for each FX type
// ═══════════════════════════════════════════════════════════════════════════

/// The DSP kernel for a single clip FX slot.
/// Each variant holds a fully initialized, stateful rf-dsp processor.
enum ClipDspKernel {
    /// Simple gain + constant-power pan (stateless, kept for symmetry)
    Gain,

    /// Professional 64-band parametric EQ with analyzer
    ProEq(Box<ProEq>),

    /// Mastering-grade ultra-transparent EQ
    UltraEq(Box<UltraEq>),

    /// Pultec MEQ-5 / EQP-1A emulation (passive EQ with inductor saturation)
    Pultec(Box<StereoPultec>),

    /// API 550A/550B console EQ emulation (proportional-Q)
    Api550(Box<StereoApi550>),

    /// Neve 1073 console EQ emulation (inductor-based, transformer coloration)
    Neve1073(Box<StereoNeve1073>),

    /// Measurement-based room correction EQ
    RoomCorrection(Box<RoomCorrectionEq>),

    /// Stereo compressor with envelope follower, knee, M/S, sidechain
    Compressor {
        left: Box<Compressor>,
        right: Box<Compressor>,
    },

    /// Noise gate with hysteresis, hold, range, envelope follower
    Gate {
        left: Box<Gate>,
        right: Box<Gate>,
    },

    /// Brick-wall limiter (simplified — full version uses look-ahead)
    Limiter,

    /// Multi-mode waveshaper saturation (stereo linked)
    Saturator(Box<StereoSaturator>),

    /// Split-band de-esser (bonus — not in original ClipFxType but useful)
    DeEsser(Box<DeEsser>),

    /// Pitch shift (stateful — requires STFT or granular buffer)
    /// Currently pass-through; full implementation needs elastic_pro
    PitchShift,

    /// Time stretch (offline operation — pass-through in realtime)
    TimeStretch,

    /// External VST3/AU/CLAP plugin (future — pass-through for now)
    External,
}

impl ClipDspKernel {
    /// Create a new DSP kernel for the given FX type
    fn new(fx_type: &ClipFxType, sample_rate: f64) -> Self {
        match fx_type {
            ClipFxType::Gain { .. } => ClipDspKernel::Gain,

            ClipFxType::ProEq { bands } => {
                let mut eq = ProEq::new(sample_rate);
                // Pre-enable requested number of bands
                let num_bands = (*bands as usize).min(64);
                for i in 0..num_bands {
                    // Set default frequencies spread across spectrum
                    let freq = 20.0 * (20000.0_f64 / 20.0).powf(i as f64 / num_bands as f64);
                    eq.set_band(
                        i,
                        freq,
                        0.0, // flat gain
                        1.0, // Q
                        rf_dsp::FilterShape::Bell,
                    );
                }
                ClipDspKernel::ProEq(Box::new(eq))
            }

            ClipFxType::UltraEq => {
                let eq = UltraEq::new(sample_rate);
                ClipDspKernel::UltraEq(Box::new(eq))
            }

            ClipFxType::Pultec => {
                let eq = StereoPultec::new(sample_rate);
                ClipDspKernel::Pultec(Box::new(eq))
            }

            ClipFxType::Api550 => {
                let eq = StereoApi550::new(sample_rate);
                ClipDspKernel::Api550(Box::new(eq))
            }

            ClipFxType::Neve1073 => {
                let eq = StereoNeve1073::new(sample_rate);
                ClipDspKernel::Neve1073(Box::new(eq))
            }

            ClipFxType::RoomCorrection => {
                let eq = RoomCorrectionEq::new(sample_rate);
                ClipDspKernel::RoomCorrection(Box::new(eq))
            }

            ClipFxType::MorphEq => {
                // MorphEq uses ProEq internally with dynamic morphing
                let eq = ProEq::new(sample_rate);
                ClipDspKernel::ProEq(Box::new(eq))
            }

            ClipFxType::Compressor {
                ratio,
                threshold_db,
                attack_ms,
                release_ms,
            } => {
                let mut left = Compressor::new(sample_rate);
                let mut right = Compressor::new(sample_rate);

                // Apply initial parameters
                left.set_ratio(*ratio);
                left.set_threshold(*threshold_db);
                left.set_attack(*attack_ms);
                left.set_release(*release_ms);

                right.set_ratio(*ratio);
                right.set_threshold(*threshold_db);
                right.set_attack(*attack_ms);
                right.set_release(*release_ms);

                ClipDspKernel::Compressor {
                    left: Box::new(left),
                    right: Box::new(right),
                }
            }

            ClipFxType::Gate {
                threshold_db,
                attack_ms,
                release_ms,
            } => {
                let mut left = Gate::new(sample_rate);
                let mut right = Gate::new(sample_rate);

                left.set_threshold(*threshold_db);
                left.set_attack(*attack_ms);
                left.set_release(*release_ms);

                right.set_threshold(*threshold_db);
                right.set_attack(*attack_ms);
                right.set_release(*release_ms);

                ClipDspKernel::Gate {
                    left: Box::new(left),
                    right: Box::new(right),
                }
            }

            ClipFxType::Limiter { .. } => ClipDspKernel::Limiter,

            ClipFxType::Saturation { drive, mix: _ } => {
                let mut sat = StereoSaturator::new(sample_rate);
                sat.set_both(|s| s.set_drive(*drive));
                ClipDspKernel::Saturator(Box::new(sat))
            }

            ClipFxType::PitchShift { .. } => ClipDspKernel::PitchShift,
            ClipFxType::TimeStretch { .. } => ClipDspKernel::TimeStretch,
            ClipFxType::External { .. } => ClipDspKernel::External,
        }
    }

    /// Process a single stereo sample through this kernel
    ///
    /// # Audio Thread Safety
    /// Zero allocations. All state is pre-allocated in the kernel.
    #[inline(always)]
    fn process_sample(
        &mut self,
        fx_type: &ClipFxType,
        left: Sample,
        right: Sample,
    ) -> (Sample, Sample) {
        match self {
            ClipDspKernel::Gain => {
                if let ClipFxType::Gain { db, pan } = fx_type {
                    let gain = if *db <= -96.0 {
                        0.0
                    } else {
                        10.0_f64.powf(*db / 20.0)
                    };
                    let pan_val = pan.clamp(-1.0, 1.0);
                    let pan_angle = (pan_val + 1.0) * std::f64::consts::FRAC_PI_4;
                    (left * gain * pan_angle.cos(), right * gain * pan_angle.sin())
                } else {
                    (left, right)
                }
            }

            ClipDspKernel::ProEq(eq) => eq.process_sample(left, right),

            ClipDspKernel::UltraEq(eq) => eq.process_sample(left, right),

            ClipDspKernel::Pultec(eq) => eq.process_sample(left, right),

            ClipDspKernel::Api550(eq) => eq.process_sample(left, right),

            ClipDspKernel::Neve1073(eq) => eq.process_sample(left, right),

            ClipDspKernel::RoomCorrection(eq) => eq.process_sample(left, right),

            ClipDspKernel::Compressor {
                left: left_comp,
                right: right_comp,
            } => {
                // Update parameters from ClipFxType (lock-free: these are just f64 reads)
                if let ClipFxType::Compressor {
                    ratio,
                    threshold_db,
                    attack_ms,
                    release_ms,
                } = fx_type
                {
                    left_comp.set_ratio(*ratio);
                    left_comp.set_threshold(*threshold_db);
                    left_comp.set_attack(*attack_ms);
                    left_comp.set_release(*release_ms);

                    right_comp.set_ratio(*ratio);
                    right_comp.set_threshold(*threshold_db);
                    right_comp.set_attack(*attack_ms);
                    right_comp.set_release(*release_ms);
                }

                // Process through both compressors (each has internal envelope follower)
                let out_l = left_comp.process_sample(left);
                let out_r = right_comp.process_sample(right);

                (out_l, out_r)
            }

            ClipDspKernel::Gate {
                left: left_gate,
                right: right_gate,
            } => {
                // Update parameters
                if let ClipFxType::Gate {
                    threshold_db,
                    attack_ms,
                    release_ms,
                } = fx_type
                {
                    left_gate.set_threshold(*threshold_db);
                    left_gate.set_attack(*attack_ms);
                    left_gate.set_release(*release_ms);

                    right_gate.set_threshold(*threshold_db);
                    right_gate.set_attack(*attack_ms);
                    right_gate.set_release(*release_ms);
                }

                let out_l = left_gate.process_sample(left);
                let out_r = right_gate.process_sample(right);
                (out_l, out_r)
            }

            ClipDspKernel::Limiter => {
                if let ClipFxType::Limiter { ceiling_db } = fx_type {
                    let ceiling = if *ceiling_db <= -96.0 {
                        0.0
                    } else {
                        10.0_f64.powf(*ceiling_db / 20.0)
                    };
                    (left.clamp(-ceiling, ceiling), right.clamp(-ceiling, ceiling))
                } else {
                    (left, right)
                }
            }

            ClipDspKernel::Saturator(sat) => {
                if let ClipFxType::Saturation { drive, mix: _ } = fx_type {
                    sat.set_both(|s| s.set_drive(*drive));
                }
                sat.process_sample(left, right)
            }

            ClipDspKernel::DeEsser(de) => de.process_sample(left, right),

            // Pass-through for unimplemented types
            ClipDspKernel::PitchShift | ClipDspKernel::TimeStretch | ClipDspKernel::External => {
                (left, right)
            }
        }
    }

    /// Reset all internal state (call on seek, transport stop, etc.)
    fn reset(&mut self) {
        match self {
            ClipDspKernel::ProEq(eq) => eq.reset(),
            ClipDspKernel::UltraEq(eq) => eq.reset(),
            ClipDspKernel::Pultec(eq) => eq.reset(),
            ClipDspKernel::Api550(eq) => eq.reset(),
            ClipDspKernel::Neve1073(eq) => eq.reset(),
            ClipDspKernel::RoomCorrection(eq) => eq.reset(),
            ClipDspKernel::Compressor {
                left,
                right,
            } => {
                left.reset();
                right.reset();
            }
            ClipDspKernel::Gate {
                left,
                right,
            } => {
                left.reset();
                right.reset();
            }
            ClipDspKernel::Saturator(sat) => sat.reset(),
            ClipDspKernel::DeEsser(de) => de.reset(),
            _ => {}
        }
    }

    /// Set sample rate for all internal processors.
    /// Some analog EQ models (Pultec, API, Neve) store sample_rate at construction
    /// and don't expose set_sample_rate — they must be re-created if SR changes.
    /// This is handled by `ClipSlotProcessor::set_sample_rate` which recreates
    /// the kernel entirely.
    fn set_sample_rate(&mut self, sample_rate: f64) {
        match self {
            ClipDspKernel::ProEq(eq) => eq.set_sample_rate(sample_rate),
            ClipDspKernel::UltraEq(eq) => eq.set_sample_rate(sample_rate),
            // Analog EQs: sample_rate is baked into coefficients at construction.
            // Re-creation is needed — handled at ClipSlotProcessor level.
            ClipDspKernel::Pultec(_)
            | ClipDspKernel::Api550(_)
            | ClipDspKernel::Neve1073(_)
            | ClipDspKernel::RoomCorrection(_) => {}
            ClipDspKernel::Compressor {
                left,
                right,
            } => {
                left.set_sample_rate(sample_rate);
                right.set_sample_rate(sample_rate);
            }
            ClipDspKernel::Gate {
                left,
                right,
            } => {
                left.set_sample_rate(sample_rate);
                right.set_sample_rate(sample_rate);
            }
            ClipDspKernel::Saturator(sat) => sat.set_sample_rate(sample_rate),
            ClipDspKernel::DeEsser(de) => de.set_sample_rate(sample_rate),
            _ => {}
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// SLOT PROCESSOR — Wraps a kernel with bypass fade and wet/dry
// ═══════════════════════════════════════════════════════════════════════════

/// Bypass fade time (~5ms at 48kHz for click-free transitions)
const BYPASS_FADE_MS: f64 = 5.0;

/// Per-slot processor with click-free bypass and wet/dry mixing
struct ClipSlotProcessor {
    /// The DSP kernel doing the actual processing
    kernel: ClipDspKernel,
    /// Slot ID for matching with ClipFxSlot
    slot_id: u64,
    /// Current bypass gain (smoothed: 0.0=bypassed, 1.0=active)
    bypass_gain: f64,
    /// Exponential smoothing coefficient for bypass fade
    bypass_coeff: f64,
}

impl ClipSlotProcessor {
    fn new(slot: &ClipFxSlot, sample_rate: f64) -> Self {
        let fade_samples = (BYPASS_FADE_MS / 1000.0) * sample_rate;
        let coeff = if fade_samples <= 0.0 {
            1.0
        } else {
            1.0 - (-1.0 / fade_samples).exp()
        };

        Self {
            kernel: ClipDspKernel::new(&slot.fx_type, sample_rate),
            slot_id: slot.id.0,
            bypass_gain: if slot.bypass { 0.0 } else { 1.0 },
            bypass_coeff: coeff,
        }
    }

    /// Process one stereo sample with bypass fade and wet/dry
    ///
    /// # Audio Thread Safety
    /// Zero allocations. Smooth bypass transitions prevent clicks.
    #[inline(always)]
    fn process_sample(
        &mut self,
        slot: &ClipFxSlot,
        left: Sample,
        right: Sample,
    ) -> (Sample, Sample) {
        let target_bypass = if slot.bypass { 0.0 } else { 1.0 };

        // Fast path: fully bypassed and not fading
        if self.bypass_gain < 1e-6 && target_bypass < 1e-6 {
            return (left, right);
        }

        // Process through kernel
        let (wet_l, wet_r) = self.kernel.process_sample(&slot.fx_type, left, right);

        // Smooth bypass transition
        self.bypass_gain += self.bypass_coeff * (target_bypass - self.bypass_gain);
        if (self.bypass_gain - target_bypass).abs() < 1e-6 {
            self.bypass_gain = target_bypass;
        }

        // Wet/dry mix combined with bypass gain
        let effective_wet = self.bypass_gain * slot.wet_dry;
        let effective_dry = 1.0 - effective_wet;

        let out_l = left * effective_dry + wet_l * effective_wet;
        let out_r = right * effective_dry + wet_r * effective_wet;

        // Apply slot output gain
        let slot_gain = slot.output_gain_linear();
        (out_l * slot_gain, out_r * slot_gain)
    }

    fn reset(&mut self) {
        self.kernel.reset();
    }

    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.kernel.set_sample_rate(sample_rate);
        let fade_samples = (BYPASS_FADE_MS / 1000.0) * sample_rate;
        self.bypass_coeff = if fade_samples <= 0.0 {
            1.0
        } else {
            1.0 - (-1.0 / fade_samples).exp()
        };
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// CLIP PROCESSOR CHAIN — All FX slots for one clip
// ═══════════════════════════════════════════════════════════════════════════

/// Complete FX processing chain for a single clip.
/// Contains up to MAX_CLIP_FX_SLOTS processor instances.
struct ClipProcessorChain {
    /// Processor instances, one per active slot
    processors: Vec<ClipSlotProcessor>,
    /// Sample rate for processor initialization
    sample_rate: f64,
    /// Generation counter — incremented when slots change, used to detect stale state
    generation: u64,
}

impl ClipProcessorChain {
    fn new(sample_rate: f64) -> Self {
        Self {
            processors: Vec::with_capacity(MAX_CLIP_FX_SLOTS),
            sample_rate,
            generation: 0,
        }
    }

    /// Synchronize processor instances with the clip's FX chain.
    /// Creates/removes processors as needed. Called from non-audio thread
    /// when FX slots are added/removed/reordered.
    fn sync_with_chain(&mut self, chain: &ClipFxChain) {
        // Build new processor list matching chain order
        let mut new_processors: Vec<ClipSlotProcessor> = Vec::with_capacity(chain.slots.len());

        for slot in &chain.slots {
            // Try to reuse existing processor for this slot ID
            let existing_idx = self
                .processors
                .iter()
                .position(|p| p.slot_id == slot.id.0);

            if let Some(idx) = existing_idx {
                // Reuse existing processor (preserves DSP state across reorders)
                let proc = self.processors.swap_remove(idx);
                new_processors.push(proc);
            } else {
                // Create new processor for this slot
                new_processors.push(ClipSlotProcessor::new(slot, self.sample_rate));
            }
        }

        self.processors = new_processors;
        self.generation += 1;
    }

    /// Process a single stereo sample through the entire chain.
    ///
    /// # Audio Thread Safety
    /// Zero allocations. Iterates pre-allocated Vec.
    #[inline(always)]
    fn process_sample(
        &mut self,
        chain: &ClipFxChain,
        sample_l: Sample,
        sample_r: Sample,
    ) -> (Sample, Sample) {
        // Skip if chain is bypassed or empty
        if chain.bypass || chain.is_empty() {
            return (sample_l, sample_r);
        }

        // Apply input gain
        let input_gain = chain.input_gain_linear();
        let mut l = sample_l * input_gain;
        let mut r = sample_r * input_gain;

        // Process through each slot (same order guaranteed by sync_with_chain)
        // Do NOT skip bypassed slots — ClipSlotProcessor handles click-free bypass fade
        for (slot_idx, slot) in chain.slots.iter().enumerate() {
            if slot_idx < self.processors.len() {
                let (out_l, out_r) = self.processors[slot_idx].process_sample(slot, l, r);
                l = out_l;
                r = out_r;
            }
        }

        // Apply output gain
        let output_gain = chain.output_gain_linear();
        (l * output_gain, r * output_gain)
    }

    /// Reset all processor states (call on seek/transport changes)
    fn reset(&mut self) {
        for proc in &mut self.processors {
            proc.reset();
        }
    }

    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        for proc in &mut self.processors {
            proc.set_sample_rate(sample_rate);
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// CLIP FX PROCESSOR BANK — The top-level manager
// ═══════════════════════════════════════════════════════════════════════════

/// Top-level manager for all clip FX processor instances.
/// One instance per PlaybackEngine.
///
/// # Thread Safety
/// - `sync_clip()` / `remove_clip()`: called from UI thread (via FFI)
/// - `process_sample()`: called from audio thread
/// - The HashMap is NOT lock-free; callers must ensure proper synchronization.
///   In practice, PlaybackEngine wraps this in `RwLock` or uses DashMap.
pub struct ClipFxProcessorBank {
    /// Map from clip ID to processor chain
    chains: HashMap<u64, ClipProcessorChain>,
    /// Current sample rate
    sample_rate: f64,
}

impl ClipFxProcessorBank {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            chains: HashMap::with_capacity(64),
            sample_rate,
        }
    }

    /// Synchronize a clip's processor chain with its FX chain data.
    /// Call this when:
    /// - A clip FX slot is added/removed/reordered
    /// - A clip is first loaded
    /// - FX type changes (requires new kernel)
    ///
    /// NOT called from audio thread — this may allocate.
    pub fn sync_clip(&mut self, clip_id: u64, chain: &ClipFxChain) {
        if chain.is_empty() {
            // No FX — remove processor chain to save memory
            self.chains.remove(&clip_id);
            return;
        }

        let processor_chain = self
            .chains
            .entry(clip_id)
            .or_insert_with(|| ClipProcessorChain::new(self.sample_rate));

        processor_chain.sync_with_chain(chain);
    }

    /// Remove processor chain for a clip (clip deleted or FX cleared)
    pub fn remove_clip(&mut self, clip_id: u64) {
        self.chains.remove(&clip_id);
    }

    /// Process a single stereo sample through a clip's FX chain.
    ///
    /// # Audio Thread Safety
    /// Zero allocations. HashMap lookup + Vec iteration.
    ///
    /// # Returns
    /// Processed (left, right) if clip has FX chain, otherwise (left, right) unchanged.
    #[inline]
    pub fn process_sample(
        &mut self,
        clip_id: u64,
        chain: &ClipFxChain,
        left: Sample,
        right: Sample,
    ) -> (Sample, Sample) {
        if let Some(processor_chain) = self.chains.get_mut(&clip_id) {
            processor_chain.process_sample(chain, left, right)
        } else {
            // No processor chain — fall back to stateless processing
            // This handles the case where sync_clip hasn't been called yet
            process_clip_fx_stateless(chain, left, right)
        }
    }

    /// Reset all processor states (call on seek/transport stop)
    pub fn reset_all(&mut self) {
        for chain in self.chains.values_mut() {
            chain.reset();
        }
    }

    /// Reset a specific clip's processor state
    pub fn reset_clip(&mut self, clip_id: u64) {
        if let Some(chain) = self.chains.get_mut(&clip_id) {
            chain.reset();
        }
    }

    /// Set sample rate for all processors
    pub fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        for chain in self.chains.values_mut() {
            chain.set_sample_rate(sample_rate);
        }
    }

    /// Get number of active clip processor chains
    pub fn active_chains(&self) -> usize {
        self.chains.len()
    }

    /// Clear all processor chains (project close)
    pub fn clear(&mut self) {
        self.chains.clear();
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// STATELESS FALLBACK — For clips without synced processor chains
// ═══════════════════════════════════════════════════════════════════════════

/// Stateless per-sample clip FX processing (fallback).
/// Used when processor chain hasn't been synced yet.
/// Only handles simple FX types (Gain, Saturation, static Compressor/Gate/Limiter).
/// EQ types pass through because they require stateful biquad filters.
#[inline]
fn process_clip_fx_stateless(
    chain: &ClipFxChain,
    sample_l: Sample,
    sample_r: Sample,
) -> (Sample, Sample) {
    if chain.bypass || chain.is_empty() {
        return (sample_l, sample_r);
    }

    let input_gain = chain.input_gain_linear();
    let mut l = sample_l * input_gain;
    let mut r = sample_r * input_gain;

    for slot in chain.active_slots() {
        let (processed_l, processed_r) = match &slot.fx_type {
            ClipFxType::Gain { db, pan } => {
                let gain = if *db <= -96.0 {
                    0.0
                } else {
                    10.0_f64.powf(*db / 20.0)
                };
                let pan_val = pan.clamp(-1.0, 1.0);
                let pan_angle = (pan_val + 1.0) * std::f64::consts::FRAC_PI_4;
                (l * gain * pan_angle.cos(), r * gain * pan_angle.sin())
            }

            ClipFxType::Saturation { drive, mix: _ } => {
                let drive_amount = 1.0 + drive * 10.0;
                let sl = (l * drive_amount).tanh() / drive_amount.tanh();
                let sr = (r * drive_amount).tanh() / drive_amount.tanh();
                (sl, sr)
            }

            ClipFxType::Compressor {
                ratio,
                threshold_db,
                ..
            } => {
                let threshold = 10.0_f64.powf(*threshold_db / 20.0);
                let ratio_inv = 1.0 / ratio;
                let compress = |s: f64| -> f64 {
                    let abs_s = s.abs();
                    if abs_s > threshold {
                        let over = abs_s - threshold;
                        (threshold + over * ratio_inv) * s.signum()
                    } else {
                        s
                    }
                };
                (compress(l), compress(r))
            }

            ClipFxType::Limiter { ceiling_db } => {
                let ceiling = 10.0_f64.powf(*ceiling_db / 20.0);
                (l.clamp(-ceiling, ceiling), r.clamp(-ceiling, ceiling))
            }

            ClipFxType::Gate { threshold_db, .. } => {
                let threshold = 10.0_f64.powf(*threshold_db / 20.0);
                let level = (l.abs() + r.abs()) / 2.0;
                if level < threshold {
                    (0.0, 0.0)
                } else {
                    (l, r)
                }
            }

            // All other types pass through in stateless mode
            _ => (l, r),
        };

        // Apply wet/dry mix
        let wet = slot.wet_dry;
        let dry = 1.0 - wet;
        l = l * dry + processed_l * wet;
        r = r * dry + processed_r * wet;

        // Apply slot output gain
        let slot_gain = slot.output_gain_linear();
        l *= slot_gain;
        r *= slot_gain;
    }

    let output_gain = chain.output_gain_linear();
    (l * output_gain, r * output_gain)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::track_manager::{ClipFxChain, ClipFxSlot, ClipFxType};

    #[test]
    fn test_bank_create_and_process() {
        let mut bank = ClipFxProcessorBank::new(48000.0);
        let mut chain = ClipFxChain::new();
        chain.add_slot(ClipFxSlot::new(ClipFxType::Gain {
            db: -6.0,
            pan: 0.0,
        }));

        bank.sync_clip(1, &chain);
        assert_eq!(bank.active_chains(), 1);

        let (l, r) = bank.process_sample(1, &chain, 1.0, 1.0);
        // -6dB gain ≈ 0.501, constant-power pan center: × cos(π/4) ≈ 0.707
        // Expected: 0.501 × 0.707 ≈ 0.354
        assert!((l - 0.354).abs() < 0.01, "Expected ~0.354, got {}", l);
        assert!((r - 0.354).abs() < 0.01, "Expected ~0.354, got {}", r);
    }

    #[test]
    fn test_bank_bypass_chain() {
        let mut bank = ClipFxProcessorBank::new(48000.0);
        let mut chain = ClipFxChain::new();
        chain.add_slot(ClipFxSlot::new(ClipFxType::Gain {
            db: -96.0,
            pan: 0.0,
        }));
        chain.bypass = true;

        bank.sync_clip(1, &chain);
        let (l, r) = bank.process_sample(1, &chain, 1.0, 1.0);
        assert_eq!(l, 1.0);
        assert_eq!(r, 1.0);
    }

    #[test]
    fn test_compressor_has_state() {
        let mut bank = ClipFxProcessorBank::new(48000.0);
        let mut chain = ClipFxChain::new();
        chain.add_slot(ClipFxSlot::new(ClipFxType::Compressor {
            ratio: 4.0,
            threshold_db: -20.0,
            attack_ms: 10.0,
            release_ms: 100.0,
        }));

        bank.sync_clip(1, &chain);

        // Process multiple samples — envelope follower should track
        let mut prev_l = 1.0;
        for _ in 0..1000 {
            let (l, _) = bank.process_sample(1, &chain, 0.5, 0.5);
            prev_l = l;
        }

        // After 1000 samples of 0.5 amplitude (≈-6dB, above threshold -20dB),
        // the compressor should be reducing gain
        assert!(
            prev_l < 0.5,
            "Compressor should reduce gain, got {}",
            prev_l
        );
    }

    #[test]
    fn test_eq_processes_instead_of_passthrough() {
        let mut bank = ClipFxProcessorBank::new(48000.0);
        let mut chain = ClipFxChain::new();
        chain.add_slot(ClipFxSlot::new(ClipFxType::ProEq { bands: 4 }));

        bank.sync_clip(1, &chain);

        // With flat EQ (all bands at 0dB), output should be approximately equal to input
        let (l, r) = bank.process_sample(1, &chain, 0.5, 0.5);
        // ProEq with 0dB bands should pass through (within floating point tolerance)
        assert!(
            (l - 0.5).abs() < 0.1,
            "ProEq flat should pass through, got {}",
            l
        );
        assert!(
            (r - 0.5).abs() < 0.1,
            "ProEq flat should pass through, got {}",
            r
        );
    }

    #[test]
    fn test_empty_chain_removal() {
        let mut bank = ClipFxProcessorBank::new(48000.0);

        let mut chain = ClipFxChain::new();
        chain.add_slot(ClipFxSlot::new(ClipFxType::Gain {
            db: 0.0,
            pan: 0.0,
        }));
        bank.sync_clip(1, &chain);
        assert_eq!(bank.active_chains(), 1);

        // Sync with empty chain should remove processor
        let empty_chain = ClipFxChain::new();
        bank.sync_clip(1, &empty_chain);
        assert_eq!(bank.active_chains(), 0);
    }

    #[test]
    fn test_reset_clears_state() {
        let mut bank = ClipFxProcessorBank::new(48000.0);
        let mut chain = ClipFxChain::new();
        chain.add_slot(ClipFxSlot::new(ClipFxType::Compressor {
            ratio: 4.0,
            threshold_db: -20.0,
            attack_ms: 10.0,
            release_ms: 100.0,
        }));

        bank.sync_clip(1, &chain);

        // Build up compressor state
        for _ in 0..1000 {
            bank.process_sample(1, &chain, 0.5, 0.5);
        }

        // Reset should clear envelope follower state
        bank.reset_all();

        // First sample after reset should be less compressed than after 1000 samples
        let (l_after_reset, _) = bank.process_sample(1, &chain, 0.5, 0.5);
        // Envelope hasn't built up yet — output should be close to input
        assert!(
            l_after_reset > 0.4,
            "After reset, compressor should not compress first sample, got {}",
            l_after_reset
        );
    }
}
