//! LoopInstanceManager — Owns all active loop instances.
//!
//! Pre-allocated pool of MAX_LOOP_INSTANCES slots. Command queue (UI→audio)
//! and callback queue (audio→UI) use lock-free rtrb ring buffers.
//! No heap allocations during processing.

use crate::loop_asset::{LoopAsset, LoopCrossfadeCurve, SyncMode};
use crate::loop_instance::{
    FadeState, LoopInstance, LoopState, PendingRegionSwitch, MAX_LOOP_INSTANCES,
};
use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;

// ─── Command & Callback Enums ──────────────────────────────

/// Commands sent from UI thread to audio thread via ring buffer.
#[derive(Debug, Clone)]
pub enum LoopCommand {
    /// Start a new loop instance
    Play {
        asset_id: String,
        region: String,
        volume: f32,
        bus: u32,
        use_dual_voice: bool,
        play_pre_entry: Option<bool>,
        fade_in_ms: Option<f32>,
    },
    /// Switch active region
    SetRegion {
        instance_id: u64,
        region: String,
        sync: SyncMode,
        crossfade_ms: f32,
        crossfade_curve: LoopCrossfadeCurve,
    },
    /// Begin exit sequence
    Exit {
        instance_id: u64,
        sync: SyncMode,
        fade_out_ms: f32,
        play_post_exit: Option<bool>,
    },
    /// Hard stop (optional fade)
    Stop {
        instance_id: u64,
        fade_out_ms: f32,
    },
    /// Seek to position (debug/QA only)
    Seek {
        instance_id: u64,
        position_samples: u64,
    },
    /// Set volume
    SetVolume {
        instance_id: u64,
        volume: f32,
        fade_ms: f32,
    },
    /// Set bus routing
    SetBus {
        instance_id: u64,
        bus: u32,
    },
    /// Register a LoopAsset (must be done before Play)
    RegisterAsset {
        asset: Box<LoopAsset>,
    },
    /// Set per-iteration gain factor on active instance
    SetIterationGain {
        instance_id: u64,
        factor: f32,
    },
}

/// Callbacks sent from audio thread to UI thread.
#[derive(Debug, Clone)]
pub enum LoopCallback {
    /// Loop instance started playing
    Started {
        instance_id: u64,
        asset_id: String,
    },
    /// State changed
    StateChanged {
        instance_id: u64,
        new_state: u8,
    },
    /// Loop wrapped (LoopOut → LoopIn)
    Wrap {
        instance_id: u64,
        loop_count: u32,
        at_samples: u64,
    },
    /// Region switched
    RegionSwitched {
        instance_id: u64,
        from_region: String,
        to_region: String,
    },
    /// Custom cue hit
    CueHit {
        instance_id: u64,
        cue_name: String,
        at_samples: u64,
    },
    /// Instance stopped
    Stopped {
        instance_id: u64,
    },
    /// Voice pool warning (dual-voice fallback)
    VoiceStealWarning {
        instance_id: u64,
    },
    /// Error (asset not found, etc.)
    Error {
        message: String,
    },
}

impl LoopCallback {
    pub fn state_byte(state: LoopState) -> u8 {
        match state {
            LoopState::Intro => 0,
            LoopState::Looping => 1,
            LoopState::Exiting => 2,
            LoopState::Stopped => 3,
        }
    }
}

// ─── Audio Data Provider Trait ──────────────────────────────

/// Trait for providing audio sample data to the loop engine.
pub trait AudioDataProvider {
    /// Get a stereo sample pair at the given position.
    fn get_sample_stereo(&self, asset_id: &str, position_samples: u64) -> (f32, f32);
}

// ─── Manager ───────────────────────────────────────────────

/// Manages all active loop instances. Runs on audio thread.
pub struct LoopInstanceManager {
    /// Pre-allocated instance pool
    instances: Vec<Option<LoopInstance>>,
    /// Asset registry (loaded at init, read-only during processing)
    assets: HashMap<String, Arc<LoopAsset>>,
    /// Command queue (UI → audio)
    command_rx: rtrb::Consumer<LoopCommand>,
    /// Callback queue (audio → UI)
    callback_tx: rtrb::Producer<LoopCallback>,
    /// Next instance ID (monotonic)
    next_instance_id: AtomicU64,
    /// Sample rate
    sample_rate: u32,
}

impl LoopInstanceManager {
    /// Create a new manager with ring buffer endpoints.
    pub fn new(
        command_rx: rtrb::Consumer<LoopCommand>,
        callback_tx: rtrb::Producer<LoopCallback>,
        sample_rate: u32,
    ) -> Self {
        let mut instances = Vec::with_capacity(MAX_LOOP_INSTANCES);
        for _ in 0..MAX_LOOP_INSTANCES {
            instances.push(None);
        }
        Self {
            instances,
            assets: HashMap::new(),
            command_rx,
            callback_tx,
            next_instance_id: AtomicU64::new(1),
            sample_rate,
        }
    }

    /// Create ring buffer pair for command/callback communication.
    pub fn create_with_queues(
        sample_rate: u32,
    ) -> (
        rtrb::Producer<LoopCommand>,
        rtrb::Consumer<LoopCallback>,
        Self,
    ) {
        let (cmd_tx, cmd_rx) = rtrb::RingBuffer::new(256);
        let (cb_tx, cb_rx) = rtrb::RingBuffer::new(512);
        let manager = Self::new(cmd_rx, cb_tx, sample_rate);
        (cmd_tx, cb_rx, manager)
    }

    /// Register a LoopAsset.
    pub fn register_asset(&mut self, asset: LoopAsset) {
        self.assets.insert(asset.id.clone(), Arc::new(asset));
    }

    /// Get a registered asset by ID.
    pub fn get_asset(&self, id: &str) -> Option<Arc<LoopAsset>> {
        self.assets.get(id).cloned()
    }

    /// Number of active instances.
    pub fn active_count(&self) -> usize {
        self.instances.iter().filter(|s| s.is_some()).count()
    }

    /// Get instance by ID (immutable).
    pub fn get_instance(&self, instance_id: u64) -> Option<&LoopInstance> {
        self.instances
            .iter()
            .filter_map(|slot| slot.as_ref())
            .find(|inst| inst.instance_id == instance_id)
    }

    /// Find first free slot index.
    fn find_free_slot(&self) -> Option<usize> {
        self.instances.iter().position(|slot| slot.is_none())
    }

    /// Process all pending commands (non-blocking drain).
    pub fn process_commands(&mut self) {
        while let Ok(cmd) = self.command_rx.pop() {
            match cmd {
                LoopCommand::RegisterAsset { asset } => {
                    self.assets.insert(asset.id.clone(), Arc::new(*asset));
                }
                LoopCommand::Play {
                    asset_id,
                    region,
                    volume,
                    bus,
                    use_dual_voice,
                    play_pre_entry: _,
                    fade_in_ms,
                } => {
                    self.handle_play(&asset_id, &region, volume, bus, use_dual_voice, fade_in_ms);
                }
                LoopCommand::SetRegion {
                    instance_id,
                    region,
                    sync,
                    crossfade_ms,
                    crossfade_curve,
                } => {
                    self.handle_set_region(instance_id, &region, sync, crossfade_ms, crossfade_curve);
                }
                LoopCommand::Exit {
                    instance_id,
                    sync,
                    fade_out_ms,
                    play_post_exit,
                } => {
                    self.handle_exit(instance_id, sync, fade_out_ms, play_post_exit.unwrap_or(false));
                }
                LoopCommand::Stop {
                    instance_id,
                    fade_out_ms,
                } => {
                    self.handle_stop(instance_id, fade_out_ms);
                }
                LoopCommand::Seek {
                    instance_id,
                    position_samples,
                } => {
                    if let Some(inst) = self.instances.iter_mut().filter_map(|s| s.as_mut()).find(|i| i.instance_id == instance_id) {
                        inst.playhead_samples = position_samples;
                    }
                }
                LoopCommand::SetVolume {
                    instance_id,
                    volume,
                    fade_ms,
                } => {
                    let sr = self.sample_rate;
                    if let Some(inst) = self.instances.iter_mut().filter_map(|s| s.as_mut()).find(|i| i.instance_id == instance_id) {
                        let fade_samples = (fade_ms * sr as f32 / 1000.0) as u64;
                        inst.volume = volume;
                        inst.fade.start(volume * inst.iteration_gain, fade_samples);
                    }
                }
                LoopCommand::SetBus { instance_id, bus } => {
                    if let Some(inst) = self.instances.iter_mut().filter_map(|s| s.as_mut()).find(|i| i.instance_id == instance_id) {
                        inst.output_bus = bus;
                    }
                }
                LoopCommand::SetIterationGain {
                    instance_id,
                    factor,
                } => {
                    if let Some(inst) = self.instances.iter_mut().filter_map(|s| s.as_mut()).find(|i| i.instance_id == instance_id) {
                        inst.iteration_gain = factor;
                        inst.gain = inst.volume * inst.iteration_gain;
                    }
                }
            }
        }
    }

    fn handle_play(
        &mut self,
        asset_id: &str,
        region: &str,
        volume: f32,
        bus: u32,
        use_dual_voice: bool,
        fade_in_ms: Option<f32>,
    ) {
        let asset = match self.assets.get(asset_id) {
            Some(a) => a.clone(),
            None => {
                let _ = self.callback_tx.push(LoopCallback::Error {
                    message: format!("Asset '{asset_id}' not found"),
                });
                return;
            }
        };

        if asset.region_by_name(region).is_none() {
            let _ = self.callback_tx.push(LoopCallback::Error {
                message: format!("Region '{region}' not found in asset '{asset_id}'"),
            });
            return;
        }

        let slot_idx = match self.find_free_slot() {
            Some(idx) => idx,
            None => {
                let _ = self.callback_tx.push(LoopCallback::Error {
                    message: "No free loop instance slots".into(),
                });
                return;
            }
        };

        let id = self.next_instance_id.fetch_add(1, Ordering::Relaxed);
        let mut inst = LoopInstance::new(id, asset_id, region, volume, bus, use_dual_voice);
        inst.init_playhead(&asset);

        if let Some(fade_ms) = fade_in_ms
            && fade_ms > 0.0 {
                let fade_samples = (fade_ms * self.sample_rate as f32 / 1000.0) as u64;
                inst.gain = 0.0;
                inst.fade = FadeState::idle(0.0);
                inst.fade.start(volume, fade_samples);
            }

        let asset_id_str = asset_id.to_string();
        self.instances[slot_idx] = Some(inst);

        let _ = self.callback_tx.push(LoopCallback::Started {
            instance_id: id,
            asset_id: asset_id_str,
        });
    }

    fn handle_set_region(
        &mut self,
        instance_id: u64,
        region: &str,
        sync: SyncMode,
        crossfade_ms: f32,
        crossfade_curve: LoopCrossfadeCurve,
    ) {
        if let Some(inst) = self.instances.iter_mut().filter_map(|s| s.as_mut()).find(|i| i.instance_id == instance_id) {
            match inst.state {
                LoopState::Exiting | LoopState::Stopped => return,
                _ => {}
            }
            inst.pending_region = Some(PendingRegionSwitch {
                target_region: region.to_string(),
                sync,
                crossfade_ms,
                crossfade_curve,
            });
        }
    }

    fn handle_exit(
        &mut self,
        instance_id: u64,
        sync: SyncMode,
        fade_out_ms: f32,
        play_post_exit: bool,
    ) {
        let asset_arc = {
            let inst = match self.instances.iter().filter_map(|s| s.as_ref()).find(|i| i.instance_id == instance_id) {
                Some(i) => i,
                None => return,
            };
            match self.assets.get(&inst.asset_id) {
                Some(a) => a.clone(),
                None => return,
            }
        };

        let sr = self.sample_rate;
        if let Some(inst) = self.instances.iter_mut().filter_map(|s| s.as_mut()).find(|i| i.instance_id == instance_id) {
            let region_name = inst.active_region.clone();
            if let Some(region) = asset_arc.region_by_name(&region_name) {
                inst.begin_exit(sync, fade_out_ms, play_post_exit, region, &asset_arc, sr);
            }
        }
    }

    fn handle_stop(&mut self, instance_id: u64, fade_out_ms: f32) {
        let sr = self.sample_rate;
        if let Some(inst) = self.instances.iter_mut().filter_map(|s| s.as_mut()).find(|i| i.instance_id == instance_id) {
            if fade_out_ms > 0.0 {
                let fade_samples = (fade_out_ms * sr as f32 / 1000.0) as u64;
                inst.state = LoopState::Exiting;
                inst.fade.start(0.0, fade_samples);
            } else {
                inst.state = LoopState::Stopped;
            }
        }
    }

    /// Process one audio buffer. Called from audio thread.
    pub fn process(
        &mut self,
        bus_buffers: &mut [Vec<f32>],
        frames: usize,
        audio_data: &dyn AudioDataProvider,
    ) {
        // 1. Drain commands
        self.process_commands();

        let sample_rate = self.sample_rate;

        // 2. Process each active instance
        // We split self to avoid borrow conflicts: iterate instances,
        // use assets + callback_tx separately.
        for slot_idx in 0..self.instances.len() {
            let should_reclaim = {
                let inst = match &mut self.instances[slot_idx] {
                    Some(inst) => inst,
                    None => continue,
                };

                if inst.state == LoopState::Stopped {
                    true
                } else if let Some(asset) = self.assets.get(&inst.asset_id).cloned() {
                    let region_name = inst.active_region.clone();
                    if let Some(region) = asset.region_by_name(&region_name) {
                        process_instance_frames(
                            inst,
                            region,
                            &asset,
                            bus_buffers,
                            frames,
                            audio_data,
                            sample_rate,
                            &mut self.callback_tx,
                        );
                    }
                    inst.state == LoopState::Stopped
                } else {
                    inst.state = LoopState::Stopped;
                    true
                }
            };

            if should_reclaim {
                let inst_id = self.instances[slot_idx]
                    .as_ref()
                    .map(|i| i.instance_id)
                    .unwrap_or(0);
                self.instances[slot_idx] = None;
                if inst_id > 0 {
                    let _ = self.callback_tx.push(LoopCallback::Stopped {
                        instance_id: inst_id,
                    });
                }
            }
        }
    }
}

// ─── Free Function: Process Frames ─────────────────────────
// Extracted as free function to avoid &mut self borrow conflicts.

fn process_instance_frames(
    inst: &mut LoopInstance,
    region: &crate::loop_asset::AdvancedLoopRegion,
    asset: &LoopAsset,
    bus_buffers: &mut [Vec<f32>],
    frames: usize,
    audio_data: &dyn AudioDataProvider,
    sample_rate: u32,
    callback_tx: &mut rtrb::Producer<LoopCallback>,
) {
    let bus_idx = inst.output_bus as usize;
    if bus_idx >= bus_buffers.len() {
        return;
    }

    let seam_fade_samples = (region.seam_fade_ms * sample_rate as f32 / 1000.0) as u64;
    let prev_state = inst.state;

    for frame in 0..frames {
        // 1. Check exit point
        inst.check_exit_point(sample_rate);

        // 2. Check intro → looping transition
        inst.check_intro_transition(region);

        // 3. Tick fade
        let fade_gain = inst.fade.tick();

        // 4. Check loop wrap
        let wrapped = inst.check_loop_wrap(region);
        if wrapped {
            let _ = callback_tx.push(LoopCallback::Wrap {
                instance_id: inst.instance_id,
                loop_count: inst.loop_count,
                at_samples: inst.last_wrap_at_samples,
            });
        }

        // 5. Check exit complete
        inst.check_exit_complete();

        if inst.state == LoopState::Stopped {
            break;
        }

        // 6. Read audio sample (voice A)
        let (sample_l, sample_r) =
            audio_data.get_sample_stereo(&inst.asset_id, inst.playhead_samples);

        // 7. Compute seam fade gain (micro-fade at loop boundaries)
        let seam_gain = if inst.state == LoopState::Looping && seam_fade_samples > 0 {
            compute_seam_fade(
                inst.playhead_samples,
                region.in_samples,
                region.out_samples,
                seam_fade_samples,
            )
        } else {
            1.0
        };

        // 8. Dual-voice crossfade
        let (final_l, final_r) = if let Some(ref mut xf) = inst.crossfade {
            let (xf_l, xf_r) =
                audio_data.get_sample_stereo(&inst.asset_id, xf.voice_b_playhead);
            let t = xf.progress;
            let (gain_a, gain_b) = crossfade_gains(t, xf.curve);

            xf.voice_b_playhead += 1;
            xf.elapsed_samples += 1;
            xf.progress = if xf.crossfade_samples > 0 {
                xf.elapsed_samples as f32 / xf.crossfade_samples as f32
            } else {
                1.0
            };

            (
                sample_l * gain_a * seam_gain + xf_l * gain_b,
                sample_r * gain_a * seam_gain + xf_r * gain_b,
            )
        } else {
            (sample_l * seam_gain, sample_r * seam_gain)
        };

        // 9. Effective gain: volume * iteration_gain, modulated by fade
        let effective_gain = if inst.fade.active {
            fade_gain * inst.iteration_gain
        } else {
            inst.gain
        };

        // 10. Write to bus buffer
        let out_idx = frame * 2;
        if out_idx + 1 < bus_buffers[bus_idx].len() {
            bus_buffers[bus_idx][out_idx] += final_l * effective_gain;
            bus_buffers[bus_idx][out_idx + 1] += final_r * effective_gain;
        }

        // 11. Advance playhead
        inst.playhead_samples += 1;

        // 12. Complete crossfade if done
        if let Some(ref xf) = inst.crossfade
            && xf.progress >= 1.0 {
                if let Some(ref target) = xf.target_region {
                    let old = inst.active_region.clone();
                    inst.active_region = target.clone();
                    inst.playhead_samples = xf.voice_b_playhead;
                    let _ = callback_tx.push(LoopCallback::RegionSwitched {
                        instance_id: inst.instance_id,
                        from_region: old,
                        to_region: target.clone(),
                    });
                }
                inst.crossfade = None;
            }

        // 13. Check pending region switch at sync boundary
        if inst.pending_region.is_some() {
            let pending_sync = inst
                .pending_region
                .as_ref()
                .map(|p| p.sync)
                .unwrap_or(SyncMode::OnWrap);
            let boundary = inst.resolve_sync_boundary(pending_sync, region, asset);
            if inst.playhead_samples >= boundary {
                let _ = inst.apply_pending_region(asset, sample_rate);
            }
        }

        // 14. Check custom cues
        for cue in asset.custom_cues() {
            if inst.playhead_samples == cue.at_samples {
                let _ = callback_tx.push(LoopCallback::CueHit {
                    instance_id: inst.instance_id,
                    cue_name: cue.name.clone(),
                    at_samples: cue.at_samples,
                });
            }
        }
    }

    // State change callback
    if inst.state != prev_state {
        let _ = callback_tx.push(LoopCallback::StateChanged {
            instance_id: inst.instance_id,
            new_state: LoopCallback::state_byte(inst.state),
        });
    }
}

// ─── Seam Fade (Micro-Fade at Loop Boundaries) ─────────────

/// Cosine micro-fade at loop boundaries.
#[inline]
pub fn compute_seam_fade(pos: u64, loop_in: u64, loop_out: u64, fade_len: u64) -> f32 {
    if fade_len == 0 {
        return 1.0;
    }
    // Fade out: [loop_out - fade_len, loop_out)
    if pos >= loop_out.saturating_sub(fade_len) && pos < loop_out {
        let t = (loop_out - pos) as f32 / fade_len as f32;
        return 0.5 * (1.0 + (t * std::f32::consts::PI).cos());
    }
    // Fade in: [loop_in, loop_in + fade_len)
    if pos >= loop_in && pos < loop_in + fade_len {
        let t = (pos - loop_in) as f32 / fade_len as f32;
        return 0.5 * (1.0 - (t * std::f32::consts::PI).cos());
    }
    1.0
}

/// Crossfade gain pair (voice A fade-out, voice B fade-in).
#[inline]
pub fn crossfade_gains(t: f32, curve: LoopCrossfadeCurve) -> (f32, f32) {
    let t = t.clamp(0.0, 1.0);
    match curve {
        LoopCrossfadeCurve::EqualPower => {
            let angle = t * std::f32::consts::FRAC_PI_2;
            (angle.cos(), angle.sin())
        }
        LoopCrossfadeCurve::Linear => (1.0 - t, t),
        LoopCrossfadeCurve::SCurve => {
            let s = t * t * (3.0 - 2.0 * t);
            (1.0 - s, s)
        }
        LoopCrossfadeCurve::Logarithmic => {
            let g_in = if t > 0.001 { 1.0 + (t.ln() / 4.0) } else { 0.0 };
            let g_out = if (1.0 - t) > 0.001 { 1.0 + ((1.0 - t).ln() / 4.0) } else { 0.0 };
            (g_out.clamp(0.0, 1.0), g_in.clamp(0.0, 1.0))
        }
        LoopCrossfadeCurve::Exponential => {
            (((1.0 - t) * (1.0 - t)), (t * t))
        }
        LoopCrossfadeCurve::SquareRoot => ((1.0 - t).sqrt(), t.sqrt()),
        LoopCrossfadeCurve::Sine | LoopCrossfadeCurve::CosineHalf
        | LoopCrossfadeCurve::FastAttack | LoopCrossfadeCurve::SlowAttack => {
            // All fall back to equal power
            let angle = t * std::f32::consts::FRAC_PI_2;
            (angle.cos(), angle.sin())
        }
    }
}
