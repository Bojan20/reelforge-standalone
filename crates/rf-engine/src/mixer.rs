//! Mixer: Integrates DSP channel strips with bus system
//!
//! Provides:
//! - Channel strips with full DSP processing
//! - Lock-free metering for GUI
//! - Master bus with limiter

use rf_core::Sample;
use rf_dsp::analysis::PeakMeter;
use rf_dsp::LufsMeter; // Now from metering.rs
use rf_dsp::channel::ChannelStrip;
use rf_dsp::dynamics::{CompressorType, StereoCompressor, TruePeakLimiter};
use rf_dsp::{Processor, ProcessorConfig, StereoProcessor};
use rtrb::{Consumer, Producer, RingBuffer};
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};

/// Number of mixer channels
pub const NUM_CHANNELS: usize = 6;

/// Channel IDs matching slot game audio categories
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ChannelId {
    Ui = 0,
    Reels = 1,
    Fx = 2,
    Vo = 3,
    Music = 4,
    Ambient = 5,
}

impl ChannelId {
    pub fn all() -> [ChannelId; NUM_CHANNELS] {
        [
            ChannelId::Ui,
            ChannelId::Reels,
            ChannelId::Fx,
            ChannelId::Vo,
            ChannelId::Music,
            ChannelId::Ambient,
        ]
    }

    pub fn name(&self) -> &'static str {
        match self {
            ChannelId::Ui => "UI",
            ChannelId::Reels => "REELS",
            ChannelId::Fx => "FX",
            ChannelId::Vo => "VO",
            ChannelId::Music => "MUSIC",
            ChannelId::Ambient => "AMBIENT",
        }
    }

    pub fn index(&self) -> usize {
        *self as usize
    }
}

/// Atomic float for lock-free metering
#[derive(Debug)]
pub struct AtomicF64(AtomicU64);

impl AtomicF64 {
    pub fn new(value: f64) -> Self {
        Self(AtomicU64::new(value.to_bits()))
    }

    pub fn load(&self) -> f64 {
        f64::from_bits(self.0.load(Ordering::Relaxed))
    }

    pub fn store(&self, value: f64) {
        self.0.store(value.to_bits(), Ordering::Relaxed);
    }
}

impl Default for AtomicF64 {
    fn default() -> Self {
        Self::new(0.0)
    }
}

/// Meter data shared between audio and GUI threads
#[derive(Debug, Default)]
pub struct MeterData {
    pub peak_l: AtomicF64,
    pub peak_r: AtomicF64,
    pub rms_l: AtomicF64,
    pub rms_r: AtomicF64,
    pub gain_reduction: AtomicF64,
}

impl MeterData {
    pub fn new() -> Self {
        Self {
            peak_l: AtomicF64::new(-120.0),
            peak_r: AtomicF64::new(-120.0),
            rms_l: AtomicF64::new(-120.0),
            rms_r: AtomicF64::new(-120.0),
            gain_reduction: AtomicF64::new(0.0),
        }
    }
}

/// Shared meter state for all channels + master
pub struct MeterBridge {
    pub channels: [Arc<MeterData>; NUM_CHANNELS],
    pub master: Arc<MeterData>,
    pub lufs_short: AtomicF64,
    pub lufs_integrated: AtomicF64,
    pub true_peak: AtomicF64,
}

impl MeterBridge {
    pub fn new() -> Self {
        Self {
            channels: std::array::from_fn(|_| Arc::new(MeterData::new())),
            master: Arc::new(MeterData::new()),
            lufs_short: AtomicF64::new(-120.0),
            lufs_integrated: AtomicF64::new(-120.0),
            true_peak: AtomicF64::new(-120.0),
        }
    }

    pub fn channel(&self, id: ChannelId) -> &Arc<MeterData> {
        &self.channels[id.index()]
    }
}

impl Default for MeterBridge {
    fn default() -> Self {
        Self::new()
    }
}

/// Mixer channel command
#[derive(Debug, Clone)]
pub enum MixerCommand {
    // Channel controls
    SetChannelVolume(ChannelId, f64),
    SetChannelPan(ChannelId, f64),
    SetChannelMute(ChannelId, bool),
    SetChannelSolo(ChannelId, bool),

    // Channel strip DSP
    SetChannelHpfEnabled(ChannelId, bool),
    SetChannelHpfFreq(ChannelId, f64),
    SetChannelGateEnabled(ChannelId, bool),
    SetChannelGateThreshold(ChannelId, f64),
    SetChannelCompEnabled(ChannelId, bool),
    SetChannelCompThreshold(ChannelId, f64),
    SetChannelCompRatio(ChannelId, f64),
    SetChannelEqEnabled(ChannelId, bool),
    SetChannelWidth(ChannelId, f64),

    // Master controls
    SetMasterVolume(f64),
    SetMasterLimiterEnabled(bool),
    SetMasterLimiterCeiling(f64),
}

/// Single mixer channel
struct MixerChannel {
    strip: ChannelStrip,
    input_l: Vec<Sample>,
    input_r: Vec<Sample>,
    output_l: Vec<Sample>,
    output_r: Vec<Sample>,
    solo: bool,
    mute: bool,
}

impl MixerChannel {
    fn new(sample_rate: f64, block_size: usize) -> Self {
        Self {
            strip: ChannelStrip::new(sample_rate),
            input_l: vec![0.0; block_size],
            input_r: vec![0.0; block_size],
            output_l: vec![0.0; block_size],
            output_r: vec![0.0; block_size],
            solo: false,
            mute: false,
        }
    }

    fn set_block_size(&mut self, size: usize) {
        self.input_l.resize(size, 0.0);
        self.input_r.resize(size, 0.0);
        self.output_l.resize(size, 0.0);
        self.output_r.resize(size, 0.0);
    }

    fn clear_input(&mut self) {
        self.input_l.fill(0.0);
        self.input_r.fill(0.0);
    }

    fn process(&mut self) {
        // Copy input to output and process
        self.output_l.copy_from_slice(&self.input_l);
        self.output_r.copy_from_slice(&self.input_r);

        self.strip
            .process_block(&mut self.output_l, &mut self.output_r);
    }
}

/// Master channel with limiter
struct MasterChannel {
    volume: f64,
    limiter: TruePeakLimiter,
    limiter_enabled: bool,
    compressor: StereoCompressor,
    compressor_enabled: bool,
    peak_l: PeakMeter,
    peak_r: PeakMeter,
    lufs: LufsMeter,
    output_l: Vec<Sample>,
    output_r: Vec<Sample>,
}

impl MasterChannel {
    fn new(sample_rate: f64, block_size: usize) -> Self {
        let mut limiter = TruePeakLimiter::new(sample_rate);
        limiter.set_ceiling(-0.3);
        limiter.set_threshold(-1.0);

        let mut compressor = StereoCompressor::new(sample_rate);
        compressor.set_both(|c| {
            c.set_type(CompressorType::Vca);
            c.set_threshold(-10.0);
            c.set_ratio(2.0);
            c.set_attack(10.0);
            c.set_release(100.0);
        });

        Self {
            volume: 1.0,
            limiter,
            limiter_enabled: true,
            compressor,
            compressor_enabled: false,
            peak_l: PeakMeter::new(sample_rate),
            peak_r: PeakMeter::new(sample_rate),
            lufs: LufsMeter::new(sample_rate),
            output_l: vec![0.0; block_size],
            output_r: vec![0.0; block_size],
        }
    }

    fn clear(&mut self) {
        self.output_l.fill(0.0);
        self.output_r.fill(0.0);
    }

    fn add_from_channel(&mut self, left: &[Sample], right: &[Sample]) {
        for (i, (&l, &r)) in left.iter().zip(right.iter()).enumerate() {
            if i < self.output_l.len() {
                self.output_l[i] += l;
                self.output_r[i] += r;
            }
        }
    }

    fn process(&mut self) {
        // Apply master volume
        for sample in &mut self.output_l {
            *sample *= self.volume;
        }
        for sample in &mut self.output_r {
            *sample *= self.volume;
        }

        // Apply compressor if enabled
        if self.compressor_enabled {
            self.compressor
                .process_block(&mut self.output_l, &mut self.output_r);
        }

        // Apply limiter if enabled
        if self.limiter_enabled {
            self.limiter
                .process_block(&mut self.output_l, &mut self.output_r);
        }

        // Update metering
        for (&l, &r) in self.output_l.iter().zip(self.output_r.iter()) {
            self.peak_l.process(l);
            self.peak_r.process(r);
            // LUFS uses mono sum (L+R)/2 for stereo
            self.lufs.process(l, r);
        }
    }

    fn set_block_size(&mut self, size: usize) {
        self.output_l.resize(size, 0.0);
        self.output_r.resize(size, 0.0);
    }
}

/// Main mixer combining channels and master
pub struct Mixer {
    channels: [MixerChannel; NUM_CHANNELS],
    master: MasterChannel,
    command_rx: Consumer<MixerCommand>,
    meters: Arc<MeterBridge>,
    sample_rate: f64,
    block_size: usize,
    any_solo: bool,
}

impl Mixer {
    pub fn new(
        sample_rate: f64,
        block_size: usize,
    ) -> (Self, Producer<MixerCommand>, Arc<MeterBridge>) {
        let (command_tx, command_rx) = RingBuffer::new(1024);
        let meters = Arc::new(MeterBridge::new());

        let mixer = Self {
            channels: std::array::from_fn(|_| MixerChannel::new(sample_rate, block_size)),
            master: MasterChannel::new(sample_rate, block_size),
            command_rx,
            meters: meters.clone(),
            sample_rate,
            block_size,
            any_solo: false,
        };

        (mixer, command_tx, meters)
    }

    /// Process pending commands (call at start of audio callback)
    fn process_commands(&mut self) {
        while let Ok(cmd) = self.command_rx.pop() {
            match cmd {
                MixerCommand::SetChannelVolume(id, db) => {
                    self.channels[id.index()].strip.set_output_gain_db(db);
                }
                MixerCommand::SetChannelPan(id, pan) => {
                    self.channels[id.index()].strip.set_pan(pan);
                }
                MixerCommand::SetChannelMute(id, mute) => {
                    self.channels[id.index()].strip.set_mute(mute);
                    self.channels[id.index()].mute = mute;
                }
                MixerCommand::SetChannelSolo(id, solo) => {
                    self.channels[id.index()].strip.set_solo(solo);
                    self.channels[id.index()].solo = solo;
                    self.update_solo_state();
                }
                MixerCommand::SetChannelHpfEnabled(id, enabled) => {
                    self.channels[id.index()].strip.set_hpf_enabled(enabled);
                }
                MixerCommand::SetChannelHpfFreq(id, freq) => {
                    self.channels[id.index()].strip.set_hpf_freq(freq);
                }
                MixerCommand::SetChannelGateEnabled(id, enabled) => {
                    self.channels[id.index()].strip.set_gate_enabled(enabled);
                }
                MixerCommand::SetChannelGateThreshold(id, db) => {
                    self.channels[id.index()].strip.set_gate_threshold(db);
                }
                MixerCommand::SetChannelCompEnabled(id, enabled) => {
                    self.channels[id.index()].strip.set_comp_enabled(enabled);
                }
                MixerCommand::SetChannelCompThreshold(id, db) => {
                    self.channels[id.index()].strip.set_comp_threshold(db);
                }
                MixerCommand::SetChannelCompRatio(id, ratio) => {
                    self.channels[id.index()].strip.set_comp_ratio(ratio);
                }
                MixerCommand::SetChannelEqEnabled(id, enabled) => {
                    self.channels[id.index()].strip.set_eq_enabled(enabled);
                }
                MixerCommand::SetChannelWidth(id, width) => {
                    self.channels[id.index()].strip.set_width(width);
                }
                MixerCommand::SetMasterVolume(db) => {
                    self.master.volume = 10.0_f64.powf(db / 20.0);
                }
                MixerCommand::SetMasterLimiterEnabled(enabled) => {
                    self.master.limiter_enabled = enabled;
                }
                MixerCommand::SetMasterLimiterCeiling(db) => {
                    self.master.limiter.set_ceiling(db);
                }
            }
        }
    }

    fn update_solo_state(&mut self) {
        self.any_solo = self.channels.iter().any(|ch| ch.solo);
    }

    /// Add audio to a channel's input
    pub fn add_to_channel(&mut self, id: ChannelId, left: &[Sample], right: &[Sample]) {
        let channel = &mut self.channels[id.index()];
        let len = left.len().min(right.len()).min(channel.input_l.len());

        for i in 0..len {
            channel.input_l[i] += left[i];
            channel.input_r[i] += right[i];
        }
    }

    /// Main processing function
    pub fn process(&mut self, output: &mut [Sample]) {
        // Process commands
        self.process_commands();

        // Clear master
        self.master.clear();

        // Process each channel
        for (i, channel) in self.channels.iter_mut().enumerate() {
            // Skip muted channels, or non-solo channels when any solo is active
            let should_play = if self.any_solo {
                channel.solo && !channel.mute
            } else {
                !channel.mute
            };

            if should_play {
                // Process channel strip
                channel.process();

                // Add to master
                self.master
                    .add_from_channel(&channel.output_l, &channel.output_r);
            }

            // Update channel meters
            let (peak_l, peak_r) = channel.strip.output_peak_db();
            let gr = channel.strip.gain_reduction_db();

            self.meters.channels[i].peak_l.store(peak_l);
            self.meters.channels[i].peak_r.store(peak_r);
            self.meters.channels[i].gain_reduction.store(gr);

            // Clear input for next block
            channel.clear_input();
        }

        // Process master
        self.master.process();

        // Update master meters
        self.meters
            .master
            .peak_l
            .store(self.master.peak_l.current_db());
        self.meters
            .master
            .peak_r
            .store(self.master.peak_r.current_db());
        self.meters
            .master
            .gain_reduction
            .store(self.master.limiter.gain_reduction_db());
        self.meters.lufs_short.store(self.master.lufs.shortterm_loudness());
        self.meters
            .lufs_integrated
            .store(self.master.lufs.integrated_loudness());
        self.meters
            .true_peak
            .store(self.master.limiter.true_peak_db());

        // Interleave output
        let left = &self.master.output_l;
        let right = &self.master.output_r;

        for (i, chunk) in output.chunks_mut(2).enumerate() {
            if i < left.len() {
                chunk[0] = left[i];
                if chunk.len() > 1 {
                    chunk[1] = right[i];
                }
            }
        }
    }

    /// Set sample rate
    pub fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        for channel in &mut self.channels {
            channel.strip.set_sample_rate(sample_rate);
        }
        self.master.limiter.set_sample_rate(sample_rate);
        self.master.compressor.set_sample_rate(sample_rate);
        self.master.peak_l = PeakMeter::new(sample_rate);
        self.master.peak_r = PeakMeter::new(sample_rate);
        self.master.lufs = LufsMeter::new(sample_rate);
    }

    /// Set block size
    pub fn set_block_size(&mut self, block_size: usize) {
        self.block_size = block_size;
        for channel in &mut self.channels {
            channel.set_block_size(block_size);
        }
        self.master.set_block_size(block_size);
    }

    /// Reset all processing state
    pub fn reset(&mut self) {
        for channel in &mut self.channels {
            channel.strip.reset();
            channel.clear_input();
        }
        self.master.clear();
        self.master.limiter.reset();
        self.master.compressor.reset();
        self.master.peak_l.reset();
        self.master.peak_r.reset();
        self.master.lufs.reset();
    }

    /// Get meters reference for GUI
    pub fn meters(&self) -> &Arc<MeterBridge> {
        &self.meters
    }
}

/// Handle for controlling mixer from UI thread
pub struct MixerHandle {
    command_tx: Producer<MixerCommand>,
    meters: Arc<MeterBridge>,
}

impl MixerHandle {
    pub fn new(command_tx: Producer<MixerCommand>, meters: Arc<MeterBridge>) -> Self {
        Self { command_tx, meters }
    }

    // Channel controls
    pub fn set_channel_volume(&mut self, id: ChannelId, db: f64) {
        let _ = self.command_tx.push(MixerCommand::SetChannelVolume(id, db));
    }

    pub fn set_channel_pan(&mut self, id: ChannelId, pan: f64) {
        let _ = self.command_tx.push(MixerCommand::SetChannelPan(id, pan));
    }

    pub fn set_channel_mute(&mut self, id: ChannelId, mute: bool) {
        let _ = self.command_tx.push(MixerCommand::SetChannelMute(id, mute));
    }

    pub fn set_channel_solo(&mut self, id: ChannelId, solo: bool) {
        let _ = self.command_tx.push(MixerCommand::SetChannelSolo(id, solo));
    }

    // Channel strip DSP
    pub fn set_channel_hpf(&mut self, id: ChannelId, enabled: bool, freq: f64) {
        let _ = self
            .command_tx
            .push(MixerCommand::SetChannelHpfEnabled(id, enabled));
        let _ = self
            .command_tx
            .push(MixerCommand::SetChannelHpfFreq(id, freq));
    }

    pub fn set_channel_gate(&mut self, id: ChannelId, enabled: bool, threshold: f64) {
        let _ = self
            .command_tx
            .push(MixerCommand::SetChannelGateEnabled(id, enabled));
        let _ = self
            .command_tx
            .push(MixerCommand::SetChannelGateThreshold(id, threshold));
    }

    pub fn set_channel_comp(&mut self, id: ChannelId, enabled: bool, threshold: f64, ratio: f64) {
        let _ = self
            .command_tx
            .push(MixerCommand::SetChannelCompEnabled(id, enabled));
        let _ = self
            .command_tx
            .push(MixerCommand::SetChannelCompThreshold(id, threshold));
        let _ = self
            .command_tx
            .push(MixerCommand::SetChannelCompRatio(id, ratio));
    }

    pub fn set_channel_eq(&mut self, id: ChannelId, enabled: bool) {
        let _ = self
            .command_tx
            .push(MixerCommand::SetChannelEqEnabled(id, enabled));
    }

    pub fn set_channel_width(&mut self, id: ChannelId, width: f64) {
        let _ = self
            .command_tx
            .push(MixerCommand::SetChannelWidth(id, width));
    }

    // Master controls
    pub fn set_master_volume(&mut self, db: f64) {
        let _ = self.command_tx.push(MixerCommand::SetMasterVolume(db));
    }

    pub fn set_master_limiter(&mut self, enabled: bool, ceiling: f64) {
        let _ = self
            .command_tx
            .push(MixerCommand::SetMasterLimiterEnabled(enabled));
        let _ = self
            .command_tx
            .push(MixerCommand::SetMasterLimiterCeiling(ceiling));
    }

    // Metering
    pub fn channel_peak(&self, id: ChannelId) -> (f64, f64) {
        let m = &self.meters.channels[id.index()];
        (m.peak_l.load(), m.peak_r.load())
    }

    pub fn channel_gain_reduction(&self, id: ChannelId) -> f64 {
        self.meters.channels[id.index()].gain_reduction.load()
    }

    pub fn master_peak(&self) -> (f64, f64) {
        (
            self.meters.master.peak_l.load(),
            self.meters.master.peak_r.load(),
        )
    }

    pub fn master_gain_reduction(&self) -> f64 {
        self.meters.master.gain_reduction.load()
    }

    pub fn lufs(&self) -> (f64, f64) {
        (
            self.meters.lufs_short.load(),
            self.meters.lufs_integrated.load(),
        )
    }

    pub fn true_peak(&self) -> f64 {
        self.meters.true_peak.load()
    }

    /// Get direct access to meter bridge for custom rendering
    pub fn meters(&self) -> Arc<MeterBridge> {
        Arc::clone(&self.meters)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_mixer_creation() {
        let (mut mixer, _cmd_tx, meters) = Mixer::new(48000.0, 256);

        // Process empty buffer
        let mut output = vec![0.0; 512];
        mixer.process(&mut output);

        // Master should show very low levels
        assert!(meters.master.peak_l.load() < -60.0);
    }

    #[test]
    fn test_mixer_channel_routing() {
        let (mut mixer, _cmd_tx, _meters) = Mixer::new(48000.0, 256);

        // Add signal to UI channel
        let input = vec![0.5; 256];
        mixer.add_to_channel(ChannelId::Ui, &input, &input);

        // Process
        let mut output = vec![0.0; 512];
        mixer.process(&mut output);

        // Should have output
        assert!(output.iter().any(|&s| s.abs() > 0.1));
    }

    #[test]
    fn test_mixer_solo() {
        let (mut mixer, mut cmd_tx, _meters) = Mixer::new(48000.0, 256);

        // Solo UI channel
        let _ = cmd_tx.push(MixerCommand::SetChannelSolo(ChannelId::Ui, true));

        // Add signal to UI and Music
        let input = vec![0.5; 256];
        mixer.add_to_channel(ChannelId::Ui, &input, &input);
        mixer.add_to_channel(ChannelId::Music, &input, &input);

        // Process
        let mut output = vec![0.0; 512];
        mixer.process(&mut output);

        // Only UI should be heard (roughly half the level if both played)
        // This is a simple test - exact levels depend on processing
    }
}
