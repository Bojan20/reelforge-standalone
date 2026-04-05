//! LoopInstance — Runtime state machine for an active loop playback.
//!
//! One LoopAsset can have multiple concurrent instances. Each instance
//! owns its own state, playhead, voice references, and iteration counter.
//! All state transitions happen on the audio thread — no locks, no allocations.

use crate::loop_asset::{
    AdvancedLoopRegion, CueType, LoopAsset, LoopCrossfadeCurve, SyncMode, WrapPolicy,
};

// ─── Constants ─────────────────────────────────────────────

/// Maximum concurrent loop instances (pre-allocated pool).
pub const MAX_LOOP_INSTANCES: usize = 32;

/// Arm margin for dual-voice crossfade scheduling (ms).
/// Voice B is started this far ahead of the crossfade to account for
/// decode/buffering latency in web runtimes.
pub const ARM_MARGIN_MS: f32 = 50.0;

// ─── Loop State Machine ────────────────────────────────────

/// Runtime state of a loop instance.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LoopState {
    /// Playing intro (Entry→LoopIn or 0→LoopIn)
    Intro,
    /// Looping body (LoopIn→LoopOut→wrap→LoopIn)
    Looping,
    /// Exiting: playing to Exit Cue or fade-out in progress
    Exiting,
    /// Fully stopped, instance can be reclaimed
    Stopped,
}

/// A pending region switch (queued, applied at sync boundary).
#[derive(Debug, Clone)]
pub struct PendingRegionSwitch {
    pub target_region: String,
    pub sync: SyncMode,
    pub crossfade_ms: f32,
    pub crossfade_curve: LoopCrossfadeCurve,
}

/// Dual-voice crossfade state (for crossfade wrap or region switch).
#[derive(Debug, Clone)]
pub struct CrossfadeState {
    /// Voice B playhead (samples from file start)
    pub voice_b_playhead: u64,
    /// Progress [0.0, 1.0] through the crossfade
    pub progress: f32,
    /// Total crossfade length in samples
    pub crossfade_samples: u64,
    /// Samples elapsed since crossfade began
    pub elapsed_samples: u64,
    /// Crossfade curve
    pub curve: LoopCrossfadeCurve,
    /// Is this a region switch (different region for voice B)?
    pub is_region_switch: bool,
    /// Target region name (for region switch)
    pub target_region: Option<String>,
}

/// Fade state for volume transitions.
#[derive(Debug, Clone, Copy)]
pub struct FadeState {
    /// Current gain (0.0–1.0)
    pub current_gain: f32,
    /// Target gain
    pub target_gain: f32,
    /// Gain increment per sample
    pub increment_per_sample: f32,
    /// Whether fade is active
    pub active: bool,
}

impl FadeState {
    pub fn idle(gain: f32) -> Self {
        Self {
            current_gain: gain,
            target_gain: gain,
            increment_per_sample: 0.0,
            active: false,
        }
    }

    pub fn start(&mut self, target: f32, duration_samples: u64) {
        if duration_samples == 0 {
            self.current_gain = target;
            self.target_gain = target;
            self.active = false;
            return;
        }
        self.target_gain = target;
        self.increment_per_sample = (target - self.current_gain) / duration_samples as f32;
        self.active = true;
    }

    /// Advance fade by one sample, returning current gain.
    #[inline]
    pub fn tick(&mut self) -> f32 {
        if !self.active {
            return self.current_gain;
        }
        self.current_gain += self.increment_per_sample;
        // Check if reached target
        if (self.increment_per_sample > 0.0 && self.current_gain >= self.target_gain)
            || (self.increment_per_sample < 0.0 && self.current_gain <= self.target_gain)
            || self.increment_per_sample == 0.0
        {
            self.current_gain = self.target_gain;
            self.active = false;
        }
        self.current_gain.clamp(0.0, 2.0)
    }
}

/// Exit configuration (how to leave the loop).
#[derive(Debug, Clone)]
pub struct ExitConfig {
    pub sync: SyncMode,
    pub fade_out_ms: f32,
    pub play_post_exit: bool,
    /// Resolved target sample where exit begins (computed from sync mode)
    pub exit_at_sample: Option<u64>,
}

// ─── Loop Instance ─────────────────────────────────────────

/// Runtime state for an active loop playback.
pub struct LoopInstance {
    /// Unique instance ID (monotonic)
    pub instance_id: u64,
    /// Reference to the LoopAsset ID
    pub asset_id: String,
    /// Currently active region name
    pub active_region: String,
    /// Pending region switch
    pub pending_region: Option<PendingRegionSwitch>,
    /// Current state
    pub state: LoopState,
    /// Playhead position (samples from file start)
    pub playhead_samples: u64,
    /// Number of completed loop iterations
    pub loop_count: u32,
    /// Sample position of last wrap event
    pub last_wrap_at_samples: u64,
    /// Base volume (set by Play command, 0.0–1.0)
    pub volume: f32,
    /// Current effective gain (volume * iteration decay * fade)
    pub gain: f32,
    /// Fade state for volume transitions
    pub fade: FadeState,
    /// Dual-voice crossfade state (None = single-voice mode)
    pub crossfade: Option<CrossfadeState>,
    /// Exit configuration (set by ExitLoop command)
    pub exit_config: Option<ExitConfig>,
    /// Bus routing
    pub output_bus: u32,
    /// Whether to use dual-voice mode for crossfade wraps
    pub use_dual_voice: bool,
    /// Whether intro was already played (for PlayOnceThenLoop)
    pub intro_played: bool,
    /// Random start offset applied (samples)
    pub random_offset: u64,
    /// Per-iteration accumulated gain factor
    pub iteration_gain: f32,
}

impl LoopInstance {
    /// Create a new loop instance.
    pub fn new(
        instance_id: u64,
        asset_id: &str,
        region_name: &str,
        volume: f32,
        output_bus: u32,
        use_dual_voice: bool,
    ) -> Self {
        Self {
            instance_id,
            asset_id: asset_id.to_string(),
            active_region: region_name.to_string(),
            pending_region: None,
            state: LoopState::Intro,
            playhead_samples: 0,
            loop_count: 0,
            last_wrap_at_samples: 0,
            volume,
            gain: volume,
            fade: FadeState::idle(volume),
            crossfade: None,
            exit_config: None,
            output_bus,
            use_dual_voice,
            intro_played: false,
            random_offset: 0,
            iteration_gain: 1.0,
        }
    }

    /// Initialize playhead based on wrap policy.
    pub fn init_playhead(&mut self, asset: &LoopAsset) {
        if let Some(region) = asset.region_by_name(&self.active_region) {
            match region.wrap_policy {
                WrapPolicy::SkipIntro => {
                    // Start directly at LoopIn
                    let offset = self.compute_random_offset(region);
                    self.playhead_samples = region.in_samples + offset;
                    self.random_offset = offset;
                    self.state = LoopState::Looping;
                    self.intro_played = true;
                }
                WrapPolicy::PlayOnceThenLoop | WrapPolicy::IncludeInLoop => {
                    // Start at Entry Cue
                    self.playhead_samples = asset.entry_samples();
                    self.state = LoopState::Intro;
                }
                WrapPolicy::IntroOnly => {
                    // Start at Entry Cue, will stop at LoopIn
                    self.playhead_samples = asset.entry_samples();
                    self.state = LoopState::Intro;
                }
            }
        }
    }

    /// Compute random start offset within allowed range.
    fn compute_random_offset(&self, region: &AdvancedLoopRegion) -> u64 {
        if region.random_start_range == 0 {
            return 0;
        }
        // Deterministic pseudo-random based on instance_id
        // (no heap allocation, no system call)
        let hash = self.instance_id.wrapping_mul(6364136223846793005).wrapping_add(1);
        let max_offset = region
            .random_start_range
            .min(region.length_samples().saturating_sub(1));
        if max_offset == 0 {
            return 0;
        }
        hash % max_offset
    }

    /// Handle intro → looping transition.
    pub fn check_intro_transition(&mut self, region: &AdvancedLoopRegion) {
        if self.state != LoopState::Intro {
            return;
        }
        if self.playhead_samples >= region.in_samples {
            match region.wrap_policy {
                WrapPolicy::IntroOnly => {
                    self.state = LoopState::Stopped;
                }
                _ => {
                    self.state = LoopState::Looping;
                    self.intro_played = true;
                }
            }
        }
    }

    /// Handle loop wrap (LoopOut → LoopIn).
    /// Returns true if a wrap occurred.
    pub fn check_loop_wrap(&mut self, region: &AdvancedLoopRegion) -> bool {
        if self.state != LoopState::Looping {
            return false;
        }
        if self.playhead_samples >= region.out_samples {
            // Check max_loops
            if let Some(max) = region.max_loops
                && self.loop_count >= max {
                    self.state = LoopState::Exiting;
                    return false;
                }
            // Wrap
            let overshoot = self.playhead_samples - region.out_samples;
            self.playhead_samples = region.in_samples + overshoot;
            self.loop_count += 1;
            self.last_wrap_at_samples = region.out_samples;

            // Apply per-iteration gain decay
            if let Some(factor) = region.iteration_gain_factor {
                self.iteration_gain *= factor;
                // Clamp to prevent denormals
                if self.iteration_gain < 0.0001 {
                    self.iteration_gain = 0.0;
                    self.state = LoopState::Stopped;
                }
            }

            // Update effective gain
            self.gain = self.volume * self.iteration_gain;

            return true;
        }
        false
    }

    /// Resolve sync boundary for exit or region switch.
    pub fn resolve_sync_boundary(
        &self,
        sync: SyncMode,
        region: &AdvancedLoopRegion,
        asset: &LoopAsset,
    ) -> u64 {
        match sync {
            SyncMode::Immediate => self.playhead_samples,
            SyncMode::OnWrap => region.out_samples,
            SyncMode::ExitCue => asset.exit_samples(),
            SyncMode::EntryCue => asset.entry_samples(),
            SyncMode::NextBar => {
                let grid = region
                    .quantize
                    .as_ref()
                    .map(|q| q.grid_samples)
                    .unwrap_or(region.length_samples());
                if grid == 0 {
                    return region.out_samples;
                }
                let next = ((self.playhead_samples / grid) + 1) * grid;
                next.min(region.out_samples)
            }
            SyncMode::NextBeat => {
                let beat_samples = asset
                    .timeline
                    .bpm
                    .map(|bpm| (asset.timeline.sample_rate as f64 * 60.0 / bpm) as u64)
                    .unwrap_or(region.length_samples());
                if beat_samples == 0 {
                    return region.out_samples;
                }
                let next = ((self.playhead_samples / beat_samples) + 1) * beat_samples;
                next.min(region.out_samples)
            }
            SyncMode::NextCue => {
                asset
                    .cues
                    .iter()
                    .filter(|c| c.cue_type == CueType::Custom && c.at_samples > self.playhead_samples)
                    .map(|c| c.at_samples)
                    .min()
                    .unwrap_or(region.out_samples)
            }
            SyncMode::SameTime => {
                // Return relative position for caller to map to new region
                let region_len = region.length_samples();
                if region_len == 0 {
                    return 0;
                }
                (self.playhead_samples.saturating_sub(region.in_samples)) % region_len
            }
        }
    }

    /// Begin exit sequence.
    pub fn begin_exit(
        &mut self,
        sync: SyncMode,
        fade_out_ms: f32,
        play_post_exit: bool,
        region: &AdvancedLoopRegion,
        asset: &LoopAsset,
        sample_rate: u32,
    ) {
        let exit_at = self.resolve_sync_boundary(sync, region, asset);
        let fade_samples = (fade_out_ms * sample_rate as f32 / 1000.0) as u64;

        self.exit_config = Some(ExitConfig {
            sync,
            fade_out_ms,
            play_post_exit,
            exit_at_sample: Some(exit_at),
        });

        // If immediate, start fade now
        if sync == SyncMode::Immediate {
            self.state = LoopState::Exiting;
            self.fade.start(0.0, fade_samples);
        }
    }

    /// Check if we've reached the exit point.
    pub fn check_exit_point(&mut self, sample_rate: u32) {
        if (self.state == LoopState::Looping || self.state == LoopState::Intro)
            && let Some(ref config) = self.exit_config
                && let Some(exit_at) = config.exit_at_sample
                    && self.playhead_samples >= exit_at {
                        self.state = LoopState::Exiting;
                        let fade_samples =
                            (config.fade_out_ms * sample_rate as f32 / 1000.0) as u64;
                        self.fade.start(0.0, fade_samples);
                    }
    }

    /// Check if exiting fade is complete → stop.
    pub fn check_exit_complete(&mut self) {
        if self.state != LoopState::Exiting {
            return;
        }
        // If fade is done (or never started) and either:
        // - gain is near zero (fade completed), or
        // - no exit_config exists (max_loops triggered exit, no fade)
        if !self.fade.active
            && (self.fade.current_gain <= 0.001 || self.exit_config.is_none()) {
                self.state = LoopState::Stopped;
            }
    }

    /// Apply the pending region switch at the resolved sync boundary.
    pub fn apply_pending_region(
        &mut self,
        asset: &LoopAsset,
        sample_rate: u32,
    ) -> Option<(String, String)> {
        let pending = self.pending_region.take()?;

        // Verify target region exists
        let new_region = asset.region_by_name(&pending.target_region)?;

        let old_region_name = self.active_region.clone();

        if pending.crossfade_ms > 0.0 && self.use_dual_voice {
            // Start dual-voice crossfade
            let crossfade_samples =
                (pending.crossfade_ms * sample_rate as f32 / 1000.0) as u64;
            let voice_b_start = new_region.in_samples;

            self.crossfade = Some(CrossfadeState {
                voice_b_playhead: voice_b_start,
                progress: 0.0,
                crossfade_samples,
                elapsed_samples: 0,
                curve: pending.crossfade_curve,
                is_region_switch: true,
                target_region: Some(pending.target_region.clone()),
            });
        } else {
            // Instant switch
            self.active_region = pending.target_region.clone();
            self.playhead_samples = new_region.in_samples;
        }

        Some((old_region_name, pending.target_region))
    }
}

// ─── Debug Assertions (Dev Builds Only) ────────────────────

#[cfg(debug_assertions)]
pub fn assert_loop_invariants(inst: &LoopInstance, asset: &LoopAsset) {
    // R-01: Playhead in bounds
    debug_assert!(
        inst.playhead_samples <= asset.timeline.length_samples,
        "Playhead {} out of bounds (length {})",
        inst.playhead_samples,
        asset.timeline.length_samples
    );

    // R-02: Active region exists
    debug_assert!(
        asset.regions.iter().any(|r| r.name == inst.active_region),
        "Active region '{}' not found in asset",
        inst.active_region
    );

    // R-03: Looping state implies playhead in region (with tolerance for wrap overshoot)
    if inst.state == LoopState::Looping
        && let Some(region) = asset.region_by_name(&inst.active_region) {
            debug_assert!(
                inst.playhead_samples >= region.in_samples
                    && inst.playhead_samples <= region.out_samples,
                "LOOPING but playhead {} not in region [{}, {})",
                inst.playhead_samples,
                region.in_samples,
                region.out_samples
            );
        }
}
