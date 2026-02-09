//! Control Room - Professional monitor mixer with AFL/PFL, cue mixes, talkback
//!
//! Full control room implementation for professional studio monitoring:
//! - Monitor source selection (master, cue, external)
//! - Independent monitor level with dim and mono
//! - Speaker selection (up to 4 sets with calibration)
//! - Solo modes: SIP, AFL, PFL
//! - 4 independent cue/headphone mixes
//! - Talkback system

use crate::routing::ChannelId;
use parking_lot::RwLock;
use std::collections::{HashMap, HashSet};
use std::sync::atomic::{AtomicBool, AtomicU8, AtomicU32, AtomicU64, Ordering};

/// Sample type alias
pub type Sample = f64;

// ============================================================================
// Monitor Source
// ============================================================================

/// Monitor source selection
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
#[derive(Default)]
pub enum MonitorSource {
    /// Main master bus output
    #[default]
    MasterBus = 0,
    /// Cue mix output (0-3)
    CueMix(u8) = 1,
    /// External input (0-3)
    External(u8) = 2,
}

impl MonitorSource {
    /// Encode to u32 for atomic storage
    pub fn to_u32(self) -> u32 {
        match self {
            Self::MasterBus => 0,
            Self::CueMix(idx) => 0x100 | (idx as u32),
            Self::External(idx) => 0x200 | (idx as u32),
        }
    }

    /// Decode from u32
    pub fn from_u32(v: u32) -> Self {
        match v >> 8 {
            0 => Self::MasterBus,
            1 => Self::CueMix((v & 0xFF) as u8),
            2 => Self::External((v & 0xFF) as u8),
            _ => Self::MasterBus,
        }
    }

    /// Encode to u8 for FFI (0=Master, 1-4=Cue1-4, 5-6=External1-2)
    pub fn to_u8(self) -> u8 {
        match self {
            Self::MasterBus => 0,
            Self::CueMix(idx) => 1 + idx.min(3),
            Self::External(idx) => 5 + idx.min(1),
        }
    }

    /// Decode from u8 for FFI
    pub fn from_u8(v: u8) -> Option<Self> {
        match v {
            0 => Some(Self::MasterBus),
            1..=4 => Some(Self::CueMix(v - 1)),
            5..=6 => Some(Self::External(v - 5)),
            _ => None,
        }
    }
}

// ============================================================================
// Solo Mode
// ============================================================================

/// Solo monitoring mode
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
#[repr(u8)]
pub enum SoloMode {
    /// Solo disabled
    #[default]
    Off = 0,
    /// Solo In Place - mutes other channels in main mix
    SIP = 1,
    /// After Fade Listen - post-fader signal to monitor bus
    AFL = 2,
    /// Pre-Fade Listen - pre-fader signal to monitor bus
    PFL = 3,
}

impl SoloMode {
    pub fn from_u8(v: u8) -> Option<Self> {
        match v {
            0 => Some(Self::Off),
            1 => Some(Self::SIP),
            2 => Some(Self::AFL),
            3 => Some(Self::PFL),
            _ => None,
        }
    }

    pub fn to_u8(self) -> u8 {
        self as u8
    }
}

// ============================================================================
// Cue Send
// ============================================================================

/// Per-channel cue send configuration
#[derive(Debug, Clone)]
pub struct CueSend {
    /// Send level (0.0 - 1.0 linear)
    pub level: f64,
    /// Pan position (-1.0 left to 1.0 right)
    pub pan: f64,
    /// Send enabled
    pub enabled: bool,
    /// Pre-fader (true) or post-fader (false)
    pub pre_fader: bool,
}

impl Default for CueSend {
    fn default() -> Self {
        Self {
            level: 1.0,
            pan: 0.0,
            enabled: true,
            pre_fader: true, // Cue sends are typically pre-fader
        }
    }
}

// ============================================================================
// Cue Mix
// ============================================================================

/// Independent cue/headphone mix
pub struct CueMix {
    /// Cue mix enabled
    pub enabled: AtomicBool,
    /// Master level (stored as f64 bits)
    pub level: AtomicU64,
    /// Master pan (stored as f64 bits)
    pub pan: AtomicU64,

    /// Per-channel cue sends
    pub channel_sends: RwLock<HashMap<ChannelId, CueSend>>,

    /// Output buffers (pre-allocated)
    pub output_l: RwLock<Vec<Sample>>,
    pub output_r: RwLock<Vec<Sample>>,

    /// Peak metering
    pub peak_l: AtomicU64,
    pub peak_r: AtomicU64,

    /// Name for UI
    pub name: RwLock<String>,
}

impl CueMix {
    /// Create a new cue mix
    pub fn new(name: &str, block_size: usize) -> Self {
        Self {
            enabled: AtomicBool::new(true),
            level: AtomicU64::new(1.0_f64.to_bits()),
            pan: AtomicU64::new(0.0_f64.to_bits()),
            channel_sends: RwLock::new(HashMap::new()),
            output_l: RwLock::new(vec![0.0; block_size]),
            output_r: RwLock::new(vec![0.0; block_size]),
            peak_l: AtomicU64::new(0.0_f64.to_bits()),
            peak_r: AtomicU64::new(0.0_f64.to_bits()),
            name: RwLock::new(name.to_string()),
        }
    }

    /// Check if enabled
    pub fn is_enabled(&self) -> bool {
        self.enabled.load(Ordering::Relaxed)
    }

    /// Set enabled state
    pub fn set_enabled(&self, enabled: bool) {
        self.enabled.store(enabled, Ordering::Relaxed);
    }

    /// Get level in linear
    pub fn level(&self) -> f64 {
        f64::from_bits(self.level.load(Ordering::Relaxed))
    }

    /// Set level in linear
    pub fn set_level(&self, level: f64) {
        self.level.store(level.to_bits(), Ordering::Relaxed);
    }

    /// Get level in dB
    pub fn level_db(&self) -> f64 {
        let linear = self.level();
        if linear > 0.0 {
            20.0 * linear.log10()
        } else {
            -144.0
        }
    }

    /// Set level in dB
    pub fn set_level_db(&self, db: f64) {
        let linear = 10.0_f64.powf(db / 20.0);
        self.set_level(linear);
    }

    /// Get pan (-1 to 1)
    pub fn pan(&self) -> f64 {
        f64::from_bits(self.pan.load(Ordering::Relaxed))
    }

    /// Set pan
    pub fn set_pan(&self, pan: f64) {
        self.pan
            .store(pan.clamp(-1.0, 1.0).to_bits(), Ordering::Relaxed);
    }

    /// Get peak (linear)
    pub fn peak(&self) -> (f64, f64) {
        (
            f64::from_bits(self.peak_l.load(Ordering::Relaxed)),
            f64::from_bits(self.peak_r.load(Ordering::Relaxed)),
        )
    }

    /// Get peak in dB
    pub fn peak_db(&self) -> (f64, f64) {
        let (l, r) = self.peak();
        (
            if l > 0.0 {
                20.0 * l.log10()
            } else {
                -f64::INFINITY
            },
            if r > 0.0 {
                20.0 * r.log10()
            } else {
                -f64::INFINITY
            },
        )
    }

    /// Reset peak meters
    pub fn reset_peaks(&self) {
        self.peak_l.store(0.0_f64.to_bits(), Ordering::Relaxed);
        self.peak_r.store(0.0_f64.to_bits(), Ordering::Relaxed);
    }

    /// Clear output buffers
    pub fn clear_buffers(&self) {
        if let Some(mut l) = self.output_l.try_write() {
            l.iter_mut().for_each(|s| *s = 0.0);
        }
        if let Some(mut r) = self.output_r.try_write() {
            r.iter_mut().for_each(|s| *s = 0.0);
        }
    }

    /// Add signal to cue mix with level and pan
    pub fn add_signal(&self, input_l: &[Sample], input_r: &[Sample], send: &CueSend) {
        if !send.enabled || send.level <= 0.0 {
            return;
        }

        let level = send.level;
        // Constant power pan law
        let pan_angle = (send.pan + 1.0) * 0.25 * std::f64::consts::PI;
        let pan_l = pan_angle.cos();
        let pan_r = pan_angle.sin();

        if let (Some(mut out_l), Some(mut out_r)) =
            (self.output_l.try_write(), self.output_r.try_write())
        {
            let len = input_l
                .len()
                .min(input_r.len())
                .min(out_l.len())
                .min(out_r.len());
            for i in 0..len {
                out_l[i] += input_l[i] * level * pan_l;
                out_r[i] += input_r[i] * level * pan_r;
            }
        }
    }

    /// Get send for channel (try_read for audio thread)
    pub fn get_send(&self, channel_id: ChannelId) -> Option<CueSend> {
        self.channel_sends.try_read()?.get(&channel_id).cloned()
    }

    /// Set send for channel (full config)
    pub fn set_send_config(&self, channel_id: ChannelId, send: CueSend) {
        if let Some(mut sends) = self.channel_sends.try_write() {
            sends.insert(channel_id, send);
        }
    }

    /// Set send for channel (convenience for FFI)
    pub fn set_send(&self, channel_id: ChannelId, level: f64, pan: f64) {
        self.set_send_config(
            channel_id,
            CueSend {
                level,
                pan,
                enabled: true,
                pre_fader: true,
            },
        );
    }

    /// Remove send for channel
    pub fn remove_send(&self, channel_id: ChannelId) {
        if let Some(mut sends) = self.channel_sends.try_write() {
            sends.remove(&channel_id);
        }
    }

    /// Update peak meters after processing
    pub fn update_peaks(&self) {
        if let (Some(l), Some(r)) = (self.output_l.try_read(), self.output_r.try_read()) {
            let peak_l = l.iter().map(|s| s.abs()).fold(0.0_f64, f64::max);
            let peak_r = r.iter().map(|s| s.abs()).fold(0.0_f64, f64::max);

            // Peak hold (max)
            let current_l = f64::from_bits(self.peak_l.load(Ordering::Relaxed));
            let current_r = f64::from_bits(self.peak_r.load(Ordering::Relaxed));

            if peak_l > current_l {
                self.peak_l.store(peak_l.to_bits(), Ordering::Relaxed);
            }
            if peak_r > current_r {
                self.peak_r.store(peak_r.to_bits(), Ordering::Relaxed);
            }
        }
    }

    /// Resize buffers
    pub fn resize_buffers(&self, block_size: usize) {
        if let Some(mut l) = self.output_l.try_write() {
            l.resize(block_size, 0.0);
        }
        if let Some(mut r) = self.output_r.try_write() {
            r.resize(block_size, 0.0);
        }
    }

    /// Copy output buffers to destination slices (for multi-output)
    ///
    /// Returns true if copy was successful, false if buffers were locked
    pub fn copy_output_to(&self, dest_l: &mut [Sample], dest_r: &mut [Sample]) -> bool {
        if let (Some(l), Some(r)) = (self.output_l.try_read(), self.output_r.try_read()) {
            let len = dest_l.len().min(dest_r.len()).min(l.len()).min(r.len());
            dest_l[..len].copy_from_slice(&l[..len]);
            dest_r[..len].copy_from_slice(&r[..len]);
            true
        } else {
            false
        }
    }

    /// Get output buffers as references (for read-only access)
    ///
    /// Returns None if buffers are locked
    pub fn get_output(
        &self,
    ) -> Option<(
        parking_lot::RwLockReadGuard<'_, Vec<Sample>>,
        parking_lot::RwLockReadGuard<'_, Vec<Sample>>,
    )> {
        let l = self.output_l.try_read()?;
        let r = self.output_r.try_read()?;
        Some((l, r))
    }
}

impl Default for CueMix {
    fn default() -> Self {
        Self::new("Cue", 512)
    }
}

// ============================================================================
// Talkback
// ============================================================================

/// Talkback system
pub struct Talkback {
    /// Talkback enabled (latching or momentary)
    pub enabled: AtomicBool,
    /// Talkback level (stored as f64 bits)
    pub level: AtomicU64,
    /// Destination bitmask (bit 0-3 = cue 1-4)
    pub destinations: AtomicU8,
    /// Talkback input channel ID
    pub input_channel: RwLock<Option<ChannelId>>,
    /// Dim main monitors during talkback
    pub dim_main_on_talk: AtomicBool,
    /// Dim amount in dB (stored as f64 bits)
    pub dim_amount: AtomicU64,
}

impl Talkback {
    /// Create new talkback
    pub fn new() -> Self {
        Self {
            enabled: AtomicBool::new(false),
            level: AtomicU64::new(1.0_f64.to_bits()),
            destinations: AtomicU8::new(0x0F), // All 4 cues by default
            input_channel: RwLock::new(None),
            dim_main_on_talk: AtomicBool::new(true),
            dim_amount: AtomicU64::new((-20.0_f64).to_bits()),
        }
    }

    /// Get level in linear
    pub fn level(&self) -> f64 {
        f64::from_bits(self.level.load(Ordering::Relaxed))
    }

    /// Set level in linear
    pub fn set_level(&self, level: f64) {
        self.level.store(level.to_bits(), Ordering::Relaxed);
    }

    /// Get dim amount in dB
    pub fn dim_amount_db(&self) -> f64 {
        f64::from_bits(self.dim_amount.load(Ordering::Relaxed))
    }

    /// Set dim amount in dB
    pub fn set_dim_amount_db(&self, db: f64) {
        self.dim_amount.store(db.to_bits(), Ordering::Relaxed);
    }

    /// Get dim amount as linear multiplier
    pub fn dim_multiplier(&self) -> f64 {
        let db = self.dim_amount_db();
        10.0_f64.powf(db / 20.0)
    }

    /// Check if cue is a destination
    pub fn sends_to_cue(&self, cue_idx: u8) -> bool {
        let mask = self.destinations.load(Ordering::Relaxed);
        (mask >> cue_idx) & 1 != 0
    }

    /// Set cue destination
    pub fn set_cue_destination(&self, cue_idx: u8, enabled: bool) {
        let mut mask = self.destinations.load(Ordering::Relaxed);
        if enabled {
            mask |= 1 << cue_idx;
        } else {
            mask &= !(1 << cue_idx);
        }
        self.destinations.store(mask, Ordering::Relaxed);
    }

    /// Get input channel
    pub fn input_channel(&self) -> Option<ChannelId> {
        self.input_channel.try_read().and_then(|c| *c)
    }

    /// Set input channel
    pub fn set_input_channel(&self, channel: Option<ChannelId>) {
        if let Some(mut input) = self.input_channel.try_write() {
            *input = channel;
        }
    }
}

impl Default for Talkback {
    fn default() -> Self {
        Self::new()
    }
}

// ============================================================================
// Speaker Set
// ============================================================================

/// Speaker set configuration
pub struct SpeakerSet {
    /// Speaker set enabled
    pub enabled: AtomicBool,
    /// Calibration level in dB (stored as f64 bits)
    pub calibration_db: AtomicU64,
    /// Speaker set name
    pub name: RwLock<String>,
}

impl SpeakerSet {
    /// Create new speaker set
    pub fn new(name: &str, calibration_db: f64) -> Self {
        Self {
            enabled: AtomicBool::new(true),
            calibration_db: AtomicU64::new(calibration_db.to_bits()),
            name: RwLock::new(name.to_string()),
        }
    }

    /// Get calibration in dB
    pub fn calibration_db(&self) -> f64 {
        f64::from_bits(self.calibration_db.load(Ordering::Relaxed))
    }

    /// Set calibration in dB
    pub fn set_calibration_db(&self, db: f64) {
        self.calibration_db.store(db.to_bits(), Ordering::Relaxed);
    }

    /// Get calibration as linear multiplier
    pub fn calibration_linear(&self) -> f64 {
        let db = self.calibration_db();
        10.0_f64.powf(db / 20.0)
    }
}

impl Default for SpeakerSet {
    fn default() -> Self {
        Self::new("Main", 0.0)
    }
}

// ============================================================================
// Control Room
// ============================================================================

/// Full control room implementation
pub struct ControlRoom {
    // ========== Main Monitoring ==========
    /// Monitor source selection
    monitor_source: AtomicU32,
    /// Monitor level in dB (stored as f64 bits) - independent from master
    pub monitor_level: AtomicU64,
    /// Dim enabled
    pub dim_enabled: AtomicBool,
    /// Dim level in dB (stored as f64 bits)
    pub dim_level: AtomicU64,
    /// Mono sum enabled
    pub mono_enabled: AtomicBool,

    // ========== Speaker Selection ==========
    /// Active speaker set index (0-3)
    pub active_speakers: AtomicU8,
    /// Speaker sets (up to 4)
    pub speaker_sets: [SpeakerSet; 4],

    // ========== Solo Monitoring ==========
    /// Solo mode (Off, SIP, AFL, PFL)
    solo_mode: AtomicU8,
    /// Currently soloed channels
    pub soloed_channels: RwLock<HashSet<ChannelId>>,
    /// Solo bus buffers
    pub solo_bus_l: RwLock<Vec<Sample>>,
    pub solo_bus_r: RwLock<Vec<Sample>>,

    // ========== Cue Mixes ==========
    /// 4 independent cue/headphone mixes
    pub cue_mixes: [CueMix; 4],

    // ========== Talkback ==========
    pub talkback: Talkback,

    // ========== Monitor Output ==========
    /// Monitor output buffers
    pub monitor_out_l: RwLock<Vec<Sample>>,
    pub monitor_out_r: RwLock<Vec<Sample>>,

    // ========== Metering ==========
    /// Monitor peak meters
    pub monitor_peak_l: AtomicU64,
    pub monitor_peak_r: AtomicU64,
}

impl ControlRoom {
    /// Create a new control room
    pub fn new(block_size: usize) -> Self {
        Self {
            // Monitoring
            monitor_source: AtomicU32::new(MonitorSource::MasterBus.to_u32()),
            monitor_level: AtomicU64::new(0.0_f64.to_bits()), // 0 dB
            dim_enabled: AtomicBool::new(false),
            dim_level: AtomicU64::new((-20.0_f64).to_bits()),
            mono_enabled: AtomicBool::new(false),

            // Speakers
            active_speakers: AtomicU8::new(0),
            speaker_sets: [
                SpeakerSet::new("Main", 0.0),
                SpeakerSet::new("Alt 1", 0.0),
                SpeakerSet::new("Alt 2", 0.0),
                SpeakerSet::new("Sub", 0.0),
            ],

            // Solo
            solo_mode: AtomicU8::new(SoloMode::Off as u8),
            soloed_channels: RwLock::new(HashSet::new()),
            solo_bus_l: RwLock::new(vec![0.0; block_size]),
            solo_bus_r: RwLock::new(vec![0.0; block_size]),

            // Cue mixes
            cue_mixes: [
                CueMix::new("Cue 1", block_size),
                CueMix::new("Cue 2", block_size),
                CueMix::new("Cue 3", block_size),
                CueMix::new("Cue 4", block_size),
            ],

            // Talkback
            talkback: Talkback::new(),

            // Monitor output
            monitor_out_l: RwLock::new(vec![0.0; block_size]),
            monitor_out_r: RwLock::new(vec![0.0; block_size]),

            // Metering
            monitor_peak_l: AtomicU64::new(0.0_f64.to_bits()),
            monitor_peak_r: AtomicU64::new(0.0_f64.to_bits()),
        }
    }

    // ========== Monitor Source ==========

    /// Get monitor source
    pub fn monitor_source(&self) -> MonitorSource {
        MonitorSource::from_u32(self.monitor_source.load(Ordering::Relaxed))
    }

    /// Set monitor source
    pub fn set_monitor_source(&self, source: MonitorSource) {
        self.monitor_source
            .store(source.to_u32(), Ordering::Relaxed);
    }

    // ========== Monitor Level ==========

    /// Get monitor level in dB
    pub fn monitor_level_db(&self) -> f64 {
        f64::from_bits(self.monitor_level.load(Ordering::Relaxed))
    }

    /// Set monitor level in dB
    pub fn set_monitor_level_db(&self, db: f64) {
        self.monitor_level.store(db.to_bits(), Ordering::Relaxed);
    }

    /// Get monitor level as linear multiplier
    pub fn monitor_level_linear(&self) -> f64 {
        let db = self.monitor_level_db();
        10.0_f64.powf(db / 20.0)
    }

    // ========== Dim ==========

    /// Get dim level in dB
    pub fn dim_level_db(&self) -> f64 {
        f64::from_bits(self.dim_level.load(Ordering::Relaxed))
    }

    /// Set dim level in dB
    pub fn set_dim_level_db(&self, db: f64) {
        self.dim_level.store(db.to_bits(), Ordering::Relaxed);
    }

    /// Get effective dim multiplier
    pub fn dim_multiplier(&self) -> f64 {
        if self.dim_enabled.load(Ordering::Relaxed) {
            let db = self.dim_level_db();
            10.0_f64.powf(db / 20.0)
        } else {
            1.0
        }
    }

    /// Get dim enabled state
    pub fn dim_enabled(&self) -> bool {
        self.dim_enabled.load(Ordering::Relaxed)
    }

    /// Set dim enabled state
    pub fn set_dim_enabled(&self, enabled: bool) {
        self.dim_enabled.store(enabled, Ordering::Relaxed);
    }

    /// Get mono enabled state
    pub fn mono_enabled(&self) -> bool {
        self.mono_enabled.load(Ordering::Relaxed)
    }

    /// Set mono enabled state
    pub fn set_mono_enabled(&self, enabled: bool) {
        self.mono_enabled.store(enabled, Ordering::Relaxed);
    }

    // ========== Solo Mode ==========

    /// Get solo mode
    pub fn solo_mode(&self) -> SoloMode {
        SoloMode::from_u8(self.solo_mode.load(Ordering::Relaxed)).unwrap_or(SoloMode::Off)
    }

    /// Set solo mode
    pub fn set_solo_mode(&self, mode: SoloMode) {
        self.solo_mode.store(mode as u8, Ordering::Relaxed);
    }

    /// Check if channel is soloed
    pub fn is_soloed(&self, channel_id: ChannelId) -> bool {
        self.soloed_channels
            .try_read()
            .map(|s| s.contains(&channel_id))
            .unwrap_or(false)
    }

    /// Set channel solo state
    pub fn set_solo(&self, channel_id: ChannelId, soloed: bool) {
        if let Some(mut channels) = self.soloed_channels.try_write() {
            if soloed {
                channels.insert(channel_id);
            } else {
                channels.remove(&channel_id);
            }
        }
    }

    /// Check if any channel is soloed
    pub fn has_solo(&self) -> bool {
        self.soloed_channels
            .try_read()
            .map(|s| !s.is_empty())
            .unwrap_or(false)
    }

    /// Clear all solos
    pub fn clear_all_solos(&self) {
        if let Some(mut channels) = self.soloed_channels.try_write() {
            channels.clear();
        }
    }

    // ========== Solo Bus ==========

    /// Clear solo bus
    pub fn clear_solo_bus(&self) {
        if let Some(mut l) = self.solo_bus_l.try_write() {
            l.iter_mut().for_each(|s| *s = 0.0);
        }
        if let Some(mut r) = self.solo_bus_r.try_write() {
            r.iter_mut().for_each(|s| *s = 0.0);
        }
    }

    /// Add to solo bus (for AFL/PFL)
    pub fn add_to_solo_bus(&self, input_l: &[Sample], input_r: &[Sample]) {
        if let (Some(mut out_l), Some(mut out_r)) =
            (self.solo_bus_l.try_write(), self.solo_bus_r.try_write())
        {
            let len = input_l
                .len()
                .min(input_r.len())
                .min(out_l.len())
                .min(out_r.len());
            for i in 0..len {
                out_l[i] += input_l[i];
                out_r[i] += input_r[i];
            }
        }
    }

    // ========== Cue Mixes ==========

    /// Get cue mix by index
    pub fn cue_mix(&self, index: usize) -> Option<&CueMix> {
        self.cue_mixes.get(index)
    }

    /// Clear all cue mixes
    pub fn clear_all_cue_mixes(&self) {
        for cue in &self.cue_mixes {
            cue.clear_buffers();
        }
    }

    // ========== Speaker Selection ==========

    /// Get active speaker set
    pub fn active_speaker_set(&self) -> &SpeakerSet {
        let idx = self.active_speakers.load(Ordering::Relaxed) as usize;
        &self.speaker_sets[idx.min(3)]
    }

    /// Set active speaker set
    pub fn set_active_speakers(&self, index: u8) {
        self.active_speakers.store(index.min(3), Ordering::Relaxed);
    }

    /// Set active speaker set (FFI-compatible name)
    pub fn set_active_speaker_set(&self, index: u8) {
        self.set_active_speakers(index);
    }

    /// Get active speaker set index
    pub fn active_speaker_set_index(&self) -> u8 {
        self.active_speakers.load(Ordering::Relaxed)
    }

    /// Get speaker calibration for a set
    pub fn speaker_calibration(&self, index: usize) -> f64 {
        self.speaker_sets
            .get(index)
            .map(|s| s.calibration_db())
            .unwrap_or(0.0)
    }

    /// Set speaker calibration for a set
    pub fn set_speaker_calibration(&self, index: usize, db: f64) {
        if let Some(speaker) = self.speaker_sets.get(index) {
            speaker.set_calibration_db(db);
        }
    }

    // ========== Cue Mix Mutators ==========

    /// Get mutable cue mix by index
    pub fn cue_mix_mut(&mut self, index: usize) -> Option<&mut CueMix> {
        self.cue_mixes.get_mut(index)
    }

    // ========== Solo Channel ==========

    /// Solo a channel
    pub fn solo_channel(&self, channel_id: ChannelId) {
        self.set_solo(channel_id, true);
    }

    /// Unsolo a channel
    pub fn unsolo_channel(&self, channel_id: ChannelId) {
        self.set_solo(channel_id, false);
    }

    // ========== Monitor Metering ==========

    /// Get monitor peak (linear)
    pub fn monitor_peak(&self) -> (f64, f64) {
        (
            f64::from_bits(self.monitor_peak_l.load(Ordering::Relaxed)),
            f64::from_bits(self.monitor_peak_r.load(Ordering::Relaxed)),
        )
    }

    // ========== Talkback Accessors ==========

    /// Get talkback enabled state
    pub fn talkback_enabled(&self) -> bool {
        self.talkback.enabled.load(Ordering::Relaxed)
    }

    /// Set talkback enabled state
    pub fn set_talkback_enabled(&self, enabled: bool) {
        self.talkback.enabled.store(enabled, Ordering::Relaxed);
    }

    /// Get talkback level in dB
    pub fn talkback_level_db(&self) -> f64 {
        self.talkback.level()
    }

    /// Set talkback level in dB
    pub fn set_talkback_level_db(&self, db: f64) {
        self.talkback.set_level(db);
    }

    /// Get talkback destinations (bitmask)
    pub fn talkback_destinations(&self) -> u8 {
        self.talkback.destinations.load(Ordering::Relaxed)
    }

    /// Set talkback destinations (bitmask)
    pub fn set_talkback_destinations(&self, mask: u8) {
        self.talkback.destinations.store(mask, Ordering::Relaxed);
    }

    /// Get talkback dim main on talk state
    pub fn talkback_dim_main_on_talk(&self) -> bool {
        self.talkback.dim_main_on_talk.load(Ordering::Relaxed)
    }

    /// Set talkback dim main on talk state
    pub fn set_talkback_dim_main_on_talk(&self, enabled: bool) {
        self.talkback
            .dim_main_on_talk
            .store(enabled, Ordering::Relaxed);
    }

    // ========== Processing ==========

    /// Process monitor output
    /// Call after all channels have been processed
    pub fn process_monitor_output(&self, master_l: &[Sample], master_r: &[Sample]) {
        let source = self.monitor_source();
        let solo_mode = self.solo_mode();
        let has_solo = self.has_solo();

        // Determine source
        let (src_l, src_r): (&[Sample], &[Sample]) = match source {
            MonitorSource::MasterBus => {
                if has_solo && (solo_mode == SoloMode::AFL || solo_mode == SoloMode::PFL) {
                    // Route solo bus to monitor
                    if let (Some(solo_l), Some(solo_r)) =
                        (self.solo_bus_l.try_read(), self.solo_bus_r.try_read())
                    {
                        // Need to copy because of borrow checker
                        let out_l = self.monitor_out_l.try_write();
                        let out_r = self.monitor_out_r.try_write();
                        if let (Some(mut ol), Some(mut or)) = (out_l, out_r) {
                            let len = solo_l.len().min(solo_r.len()).min(ol.len()).min(or.len());
                            ol[..len].copy_from_slice(&solo_l[..len]);
                            or[..len].copy_from_slice(&solo_r[..len]);
                        }
                        return;
                    }
                    (master_l, master_r)
                } else {
                    (master_l, master_r)
                }
            }
            MonitorSource::CueMix(idx) => {
                if let Some(cue) = self.cue_mixes.get(idx as usize)
                    && let (Some(cue_l), Some(cue_r)) =
                        (cue.output_l.try_read(), cue.output_r.try_read())
                {
                    let out_l = self.monitor_out_l.try_write();
                    let out_r = self.monitor_out_r.try_write();
                    if let (Some(mut ol), Some(mut or)) = (out_l, out_r) {
                        let len = cue_l.len().min(cue_r.len()).min(ol.len()).min(or.len());
                        ol[..len].copy_from_slice(&cue_l[..len]);
                        or[..len].copy_from_slice(&cue_r[..len]);
                    }
                    return;
                }
                (master_l, master_r)
            }
            MonitorSource::External(_) => {
                // External input handling would be done separately
                (master_l, master_r)
            }
        };

        // Apply monitor processing
        let monitor_level = self.monitor_level_linear();
        let dim_mult = self.dim_multiplier();
        let speaker_cal = self.active_speaker_set().calibration_linear();
        let mono = self.mono_enabled.load(Ordering::Relaxed);

        // Talkback dim
        let talkback_dim = if self.talkback.enabled.load(Ordering::Relaxed)
            && self.talkback.dim_main_on_talk.load(Ordering::Relaxed)
        {
            self.talkback.dim_multiplier()
        } else {
            1.0
        };

        let total_gain = monitor_level * dim_mult * speaker_cal * talkback_dim;

        if let (Some(mut out_l), Some(mut out_r)) = (
            self.monitor_out_l.try_write(),
            self.monitor_out_r.try_write(),
        ) {
            let len = src_l
                .len()
                .min(src_r.len())
                .min(out_l.len())
                .min(out_r.len());

            if mono {
                // Mono sum
                for i in 0..len {
                    let mono_sample = (src_l[i] + src_r[i]) * 0.5 * total_gain;
                    out_l[i] = mono_sample;
                    out_r[i] = mono_sample;
                }
            } else {
                // Stereo
                for i in 0..len {
                    out_l[i] = src_l[i] * total_gain;
                    out_r[i] = src_r[i] * total_gain;
                }
            }

            // Update peak meters
            let peak_l = out_l.iter().map(|s| s.abs()).fold(0.0_f64, f64::max);
            let peak_r = out_r.iter().map(|s| s.abs()).fold(0.0_f64, f64::max);

            let current_l = f64::from_bits(self.monitor_peak_l.load(Ordering::Relaxed));
            let current_r = f64::from_bits(self.monitor_peak_r.load(Ordering::Relaxed));

            if peak_l > current_l {
                self.monitor_peak_l
                    .store(peak_l.to_bits(), Ordering::Relaxed);
            }
            if peak_r > current_r {
                self.monitor_peak_r
                    .store(peak_r.to_bits(), Ordering::Relaxed);
            }
        }
    }

    /// Process talkback - add to cue mixes
    pub fn process_talkback(&self, talkback_l: &[Sample], talkback_r: &[Sample]) {
        if !self.talkback.enabled.load(Ordering::Relaxed) {
            return;
        }

        let level = self.talkback.level();
        let destinations = self.talkback.destinations.load(Ordering::Relaxed);

        for (idx, cue) in self.cue_mixes.iter().enumerate() {
            if (destinations >> idx) & 1 != 0
                && let (Some(mut cue_l), Some(mut cue_r)) =
                    (cue.output_l.try_write(), cue.output_r.try_write())
            {
                let len = talkback_l
                    .len()
                    .min(talkback_r.len())
                    .min(cue_l.len())
                    .min(cue_r.len());
                for i in 0..len {
                    cue_l[i] += talkback_l[i] * level;
                    cue_r[i] += talkback_r[i] * level;
                }
            }
        }
    }

    /// Reset all peak meters
    pub fn reset_peaks(&self) {
        self.monitor_peak_l
            .store(0.0_f64.to_bits(), Ordering::Relaxed);
        self.monitor_peak_r
            .store(0.0_f64.to_bits(), Ordering::Relaxed);
        for cue in &self.cue_mixes {
            cue.reset_peaks();
        }
    }

    /// Get monitor peak in dB
    pub fn monitor_peak_db(&self) -> (f64, f64) {
        let l = f64::from_bits(self.monitor_peak_l.load(Ordering::Relaxed));
        let r = f64::from_bits(self.monitor_peak_r.load(Ordering::Relaxed));
        (
            if l > 0.0 {
                20.0 * l.log10()
            } else {
                -f64::INFINITY
            },
            if r > 0.0 {
                20.0 * r.log10()
            } else {
                -f64::INFINITY
            },
        )
    }

    /// Resize all buffers
    pub fn resize_buffers(&self, block_size: usize) {
        if let Some(mut l) = self.solo_bus_l.try_write() {
            l.resize(block_size, 0.0);
        }
        if let Some(mut r) = self.solo_bus_r.try_write() {
            r.resize(block_size, 0.0);
        }
        if let Some(mut l) = self.monitor_out_l.try_write() {
            l.resize(block_size, 0.0);
        }
        if let Some(mut r) = self.monitor_out_r.try_write() {
            r.resize(block_size, 0.0);
        }
        for cue in &self.cue_mixes {
            cue.resize_buffers(block_size);
        }
    }

    /// Clear all buffers before processing
    pub fn clear_all_buffers(&self) {
        self.clear_solo_bus();
        self.clear_all_cue_mixes();
    }

    // ========== Multi-Output Integration ==========

    /// Copy monitor output to destination slices
    ///
    /// Use this to send monitor output to separate speaker device
    /// Returns true if successful, false if buffers were locked
    pub fn copy_monitor_output_to(&self, dest_l: &mut [Sample], dest_r: &mut [Sample]) -> bool {
        if let (Some(l), Some(r)) = (self.monitor_out_l.try_read(), self.monitor_out_r.try_read()) {
            let len = dest_l.len().min(dest_r.len()).min(l.len()).min(r.len());
            dest_l[..len].copy_from_slice(&l[..len]);
            dest_r[..len].copy_from_slice(&r[..len]);
            true
        } else {
            false
        }
    }

    /// Copy cue mix output to destination slices
    ///
    /// Use this to send cue mix to separate headphone output device
    /// Returns true if successful, false if buffers were locked or index invalid
    pub fn copy_cue_output_to(
        &self,
        cue_index: usize,
        dest_l: &mut [Sample],
        dest_r: &mut [Sample],
    ) -> bool {
        if cue_index >= 4 {
            return false;
        }
        self.cue_mixes[cue_index].copy_output_to(dest_l, dest_r)
    }

    /// Check if any cue mix is enabled
    pub fn any_cue_enabled(&self) -> bool {
        self.cue_mixes
            .iter()
            .any(|c| c.enabled.load(Ordering::Relaxed))
    }

    /// Get enabled cue mix indices
    pub fn enabled_cue_indices(&self) -> Vec<usize> {
        self.cue_mixes
            .iter()
            .enumerate()
            .filter(|(_, c)| c.enabled.load(Ordering::Relaxed))
            .map(|(i, _)| i)
            .collect()
    }
}

impl Default for ControlRoom {
    fn default() -> Self {
        Self::new(512)
    }
}

// ============================================================================
// Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_monitor_source_encoding() {
        assert_eq!(MonitorSource::MasterBus.to_u32(), 0);
        assert_eq!(MonitorSource::CueMix(2).to_u32(), 0x102);
        assert_eq!(MonitorSource::External(1).to_u32(), 0x201);

        assert_eq!(MonitorSource::from_u32(0), MonitorSource::MasterBus);
        assert_eq!(MonitorSource::from_u32(0x102), MonitorSource::CueMix(2));
        assert_eq!(MonitorSource::from_u32(0x201), MonitorSource::External(1));
    }

    #[test]
    fn test_solo_mode() {
        let room = ControlRoom::new(256);

        assert_eq!(room.solo_mode(), SoloMode::Off);
        room.set_solo_mode(SoloMode::PFL);
        assert_eq!(room.solo_mode(), SoloMode::PFL);
    }

    #[test]
    fn test_channel_solo() {
        let room = ControlRoom::new(256);
        let ch1 = ChannelId(1);
        let ch2 = ChannelId(2);

        assert!(!room.has_solo());
        assert!(!room.is_soloed(ch1));

        room.set_solo(ch1, true);
        assert!(room.has_solo());
        assert!(room.is_soloed(ch1));
        assert!(!room.is_soloed(ch2));

        room.set_solo(ch2, true);
        assert!(room.is_soloed(ch2));

        room.clear_all_solos();
        assert!(!room.has_solo());
    }

    #[test]
    fn test_cue_mix() {
        let cue = CueMix::new("Test Cue", 128);
        let ch1 = ChannelId(1);

        cue.set_send_config(
            ch1,
            CueSend {
                level: 0.5,
                pan: 0.0,
                enabled: true,
                pre_fader: true,
            },
        );

        let send = cue.get_send(ch1).unwrap();
        assert_eq!(send.level, 0.5);
        assert!(send.enabled);
        assert!(send.pre_fader);
    }

    #[test]
    fn test_talkback_destinations() {
        let tb = Talkback::new();

        // Default: all 4 cues
        assert!(tb.sends_to_cue(0));
        assert!(tb.sends_to_cue(1));
        assert!(tb.sends_to_cue(2));
        assert!(tb.sends_to_cue(3));

        tb.set_cue_destination(2, false);
        assert!(tb.sends_to_cue(0));
        assert!(tb.sends_to_cue(1));
        assert!(!tb.sends_to_cue(2));
        assert!(tb.sends_to_cue(3));
    }

    #[test]
    fn test_monitor_processing() {
        let room = ControlRoom::new(128);

        // Set up test signal
        let master_l: Vec<f64> = (0..128).map(|_| 0.5).collect();
        let master_r: Vec<f64> = (0..128).map(|_| 0.5).collect();

        room.process_monitor_output(&master_l, &master_r);

        // Check output
        if let Some(out_l) = room.monitor_out_l.try_read() {
            assert!(out_l.iter().all(|&s| (s - 0.5).abs() < 0.001));
        }
    }

    #[test]
    fn test_dim() {
        let room = ControlRoom::new(128);

        assert_eq!(room.dim_multiplier(), 1.0);

        room.dim_enabled.store(true, Ordering::Relaxed);
        room.set_dim_level_db(-20.0);

        let mult = room.dim_multiplier();
        assert!((mult - 0.1).abs() < 0.001); // -20dB ≈ 0.1
    }

    #[test]
    fn test_speaker_calibration() {
        let room = ControlRoom::new(128);

        room.speaker_sets[1].set_calibration_db(-6.0);
        room.set_active_speakers(1);

        let cal = room.active_speaker_set().calibration_linear();
        assert!((cal - 0.501).abs() < 0.01); // -6dB ≈ 0.5
    }

    #[test]
    fn test_mono_sum() {
        let room = ControlRoom::new(4);

        room.mono_enabled.store(true, Ordering::Relaxed);

        let master_l = vec![1.0, 0.0, 0.5, -0.5];
        let master_r = vec![0.0, 1.0, 0.5, 0.5];

        room.process_monitor_output(&master_l, &master_r);

        if let (Some(out_l), Some(out_r)) =
            (room.monitor_out_l.try_read(), room.monitor_out_r.try_read())
        {
            // Mono: L and R should be equal
            for i in 0..4 {
                assert!((out_l[i] - out_r[i]).abs() < 0.001);
            }
            // Check mono sum values
            assert!((out_l[0] - 0.5).abs() < 0.001); // (1+0)/2
            assert!((out_l[1] - 0.5).abs() < 0.001); // (0+1)/2
            assert!((out_l[2] - 0.5).abs() < 0.001); // (0.5+0.5)/2
            assert!((out_l[3] - 0.0).abs() < 0.001); // (-0.5+0.5)/2
        }
    }
}
