//! Dynamic Routing Graph System
//!
//! Professional bus/aux/group architecture inspired by:
//! - Reaper's flexibility (tracks are just tracks)
//! - Cubase's intuitiveness (semantic channel types)
//! - Pro Tools' robustness (master fader architecture)
//!
//! ## Core Principles
//! - No hardcoded bus types (no "SFX bus", "Voice bus" etc)
//! - Dynamic creation/deletion of channels
//! - Full routing graph with feedback prevention
//! - Hierarchical bus routing (bus can feed another bus)
//! - Pre/post fader sends with post-pan option
//!
//! ## Channel Types
//! - Audio: Standard track with clips
//! - Bus: Group/submix channel
//! - Aux: Send effect return
//! - VCA: Level control only (no audio routing)
//! - Master: Final output stage

use rtrb::{Consumer, Producer, RingBuffer};
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet, VecDeque};
use std::sync::atomic::{AtomicBool, AtomicU32, AtomicU64, Ordering};

use rf_core::Sample;
use rf_dsp::channel::ChannelStrip;
use rf_plugin::{AudioBuffer as PluginAudioBuffer, ZeroCopyChain};

// ═══════════════════════════════════════════════════════════════════════════
// CHANNEL-LEVEL PDC (Plugin Delay Compensation)
// ═══════════════════════════════════════════════════════════════════════════

/// Maximum PDC delay in samples (~1 second at 48kHz)
const MAX_PDC_DELAY: usize = 48000;

/// Per-channel delay buffer for PDC (Plugin Delay Compensation)
///
/// When channels in a routing graph have different latencies (due to plugins),
/// channels with lower latency need to be delayed to maintain phase coherence.
///
/// # Audio Thread Safety
/// - Pre-allocated circular buffer (no heap allocation during processing)
/// - O(1) read/write operations
/// - Zero-copy design
#[derive(Debug)]
pub struct ChannelPdcBuffer {
    /// Circular buffer for left channel
    buffer_l: Vec<Sample>,
    /// Circular buffer for right channel
    buffer_r: Vec<Sample>,
    /// Write position in circular buffer
    write_pos: usize,
    /// Current delay in samples
    delay: usize,
    /// Maximum delay capacity
    capacity: usize,
}

impl ChannelPdcBuffer {
    /// Create new PDC buffer with specified capacity
    pub fn new(capacity: usize) -> Self {
        Self {
            buffer_l: vec![0.0; capacity],
            buffer_r: vec![0.0; capacity],
            write_pos: 0,
            delay: 0,
            capacity,
        }
    }

    /// Set delay in samples (clamped to capacity)
    #[inline]
    pub fn set_delay(&mut self, delay: usize) {
        self.delay = delay.min(self.capacity.saturating_sub(1));
    }

    /// Get current delay
    #[inline]
    pub fn delay(&self) -> usize {
        self.delay
    }

    /// Process stereo buffer through delay line (IN-PLACE)
    ///
    /// # Audio Thread Safety
    /// - No allocations
    /// - O(n) where n = buffer length
    #[inline]
    pub fn process(&mut self, left: &mut [Sample], right: &mut [Sample]) {
        if self.delay == 0 {
            return;
        }

        let len = left.len().min(right.len());

        for i in 0..len {
            // Calculate read position (wrap around)
            let read_pos = (self.write_pos + self.capacity - self.delay) % self.capacity;

            // Read delayed samples
            let delayed_l = self.buffer_l[read_pos];
            let delayed_r = self.buffer_r[read_pos];

            // Write current samples to buffer
            self.buffer_l[self.write_pos] = left[i];
            self.buffer_r[self.write_pos] = right[i];

            // Output delayed samples
            left[i] = delayed_l;
            right[i] = delayed_r;

            // Advance write position
            self.write_pos = (self.write_pos + 1) % self.capacity;
        }
    }

    /// Clear buffer (call on transport stop/reset)
    pub fn clear(&mut self) {
        self.buffer_l.fill(0.0);
        self.buffer_r.fill(0.0);
        self.write_pos = 0;
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// ROUTING COMMANDS (lock-free UI → Audio thread communication)
// ═══════════════════════════════════════════════════════════════════════════

/// Commands for modifying routing graph from UI thread
/// Sent via lock-free ring buffer, processed on audio thread
#[derive(Debug, Clone)]
pub enum RoutingCommand {
    // Channel management
    /// Create new channel (audio thread allocates)
    CreateChannel {
        kind: ChannelKind,
        name: String,
        callback_id: u32,
    },
    /// Delete channel
    DeleteChannel { id: ChannelId },

    // Routing
    /// Set channel output destination
    SetOutput {
        id: ChannelId,
        destination: OutputDestination,
    },
    /// Add send from one channel to another
    AddSend {
        from: ChannelId,
        to: ChannelId,
        pre_fader: bool,
    },
    /// Remove send
    RemoveSend { from: ChannelId, send_index: usize },
    /// Set send level
    SetSendLevel {
        from: ChannelId,
        send_index: usize,
        level_db: f64,
    },
    /// Enable/disable send
    SetSendEnabled {
        from: ChannelId,
        send_index: usize,
        enabled: bool,
    },
    /// Set send pan
    SetSendPan {
        from: ChannelId,
        send_index: usize,
        pan: f64,
    },

    // Mixer state
    /// Set volume (fader)
    SetVolume { id: ChannelId, db: f64 },
    /// Set pan
    SetPan { id: ChannelId, pan: f64 },
    /// Set mute
    SetMute { id: ChannelId, mute: bool },
    /// Set solo
    SetSolo { id: ChannelId, solo: bool },

    // DSP controls
    /// Set input gain
    SetInputGain { id: ChannelId, db: f64 },
    /// Set output gain
    SetOutputGain { id: ChannelId, db: f64 },
    /// Enable/disable HPF
    SetHpfEnabled { id: ChannelId, enabled: bool },
    /// Set HPF frequency
    SetHpfFreq { id: ChannelId, freq: f64 },
    /// Enable/disable gate
    SetGateEnabled { id: ChannelId, enabled: bool },
    /// Set gate threshold
    SetGateThreshold { id: ChannelId, db: f64 },
    /// Enable/disable compressor
    SetCompEnabled { id: ChannelId, enabled: bool },
    /// Set compressor threshold
    SetCompThreshold { id: ChannelId, db: f64 },
    /// Set compressor ratio
    SetCompRatio { id: ChannelId, ratio: f64 },
    /// Set compressor attack
    SetCompAttack { id: ChannelId, ms: f64 },
    /// Set compressor release
    SetCompRelease { id: ChannelId, ms: f64 },
    /// Enable/disable EQ
    SetEqEnabled { id: ChannelId, enabled: bool },
    /// Set EQ low shelf
    SetEqLow { id: ChannelId, freq: f64, gain_db: f64 },
    /// Set EQ low-mid
    SetEqLowMid {
        id: ChannelId,
        freq: f64,
        gain_db: f64,
        q: f64,
    },
    /// Set EQ high-mid
    SetEqHighMid {
        id: ChannelId,
        freq: f64,
        gain_db: f64,
        q: f64,
    },
    /// Set EQ high shelf
    SetEqHigh { id: ChannelId, freq: f64, gain_db: f64 },
    /// Enable/disable limiter
    SetLimiterEnabled { id: ChannelId, enabled: bool },
    /// Set limiter threshold
    SetLimiterThreshold { id: ChannelId, db: f64 },
    /// Set stereo width
    SetWidth { id: ChannelId, width: f64 },

    // Plugin insert chain
    /// Add plugin to insert chain
    AddInsert {
        id: ChannelId,
        plugin_id: String,
        slot_index: Option<usize>,
    },
    /// Remove plugin from insert chain
    RemoveInsert { id: ChannelId, slot_index: usize },
    /// Bypass/unbypass insert slot
    SetInsertBypass {
        id: ChannelId,
        slot_index: usize,
        bypass: bool,
    },
    /// Set insert wet/dry mix (0.0 - 1.0)
    SetInsertMix {
        id: ChannelId,
        slot_index: usize,
        mix: f64,
    },
}

/// Response from audio thread (for async operations)
#[derive(Debug, Clone)]
pub enum RoutingResponse {
    /// Channel was created, returns new ID
    ChannelCreated { callback_id: u32, channel_id: ChannelId },
    /// Channel was deleted
    ChannelDeleted { id: ChannelId },
    /// Error occurred
    Error { message: String },
}

/// Command queue capacity
const COMMAND_QUEUE_SIZE: usize = 1024;
/// Response queue capacity
const RESPONSE_QUEUE_SIZE: usize = 256;

// ═══════════════════════════════════════════════════════════════════════════
// BUFFER POOL (Pre-allocated, O(1) acquisition)
// ═══════════════════════════════════════════════════════════════════════════

/// Pre-allocated buffer pool for dynamic bus allocation
/// Eliminates heap allocation on audio thread
#[derive(Debug)]
pub struct BufferPool {
    /// Pre-allocated stereo buffer pairs (left, right)
    buffers: Vec<(Vec<Sample>, Vec<Sample>)>,
    /// Indices of available buffers
    available: Vec<usize>,
    /// Block size for each buffer
    block_size: usize,
    /// Maximum buffers (capacity)
    capacity: usize,
}

impl BufferPool {
    /// Create new buffer pool with specified capacity
    pub fn new(capacity: usize, block_size: usize) -> Self {
        let mut buffers = Vec::with_capacity(capacity);
        let mut available = Vec::with_capacity(capacity);

        // Pre-allocate all buffers
        for i in 0..capacity {
            buffers.push((vec![0.0; block_size], vec![0.0; block_size]));
            available.push(i);
        }

        Self {
            buffers,
            available,
            block_size,
            capacity,
        }
    }

    /// Acquire a buffer pair (O(1), no allocation)
    /// Returns buffer index if available
    pub fn acquire(&mut self) -> Option<usize> {
        self.available.pop()
    }

    /// Release a buffer back to the pool (O(1))
    pub fn release(&mut self, idx: usize) {
        if idx < self.buffers.len() && !self.available.contains(&idx) {
            // Clear buffer before returning to pool
            self.buffers[idx].0.fill(0.0);
            self.buffers[idx].1.fill(0.0);
            self.available.push(idx);
        }
    }

    /// Get mutable reference to buffer pair
    pub fn get_mut(&mut self, idx: usize) -> Option<(&mut [Sample], &mut [Sample])> {
        self.buffers
            .get_mut(idx)
            .map(|(l, r)| (l.as_mut_slice(), r.as_mut_slice()))
    }

    /// Get immutable reference to buffer pair
    pub fn get(&self, idx: usize) -> Option<(&[Sample], &[Sample])> {
        self.buffers
            .get(idx)
            .map(|(l, r)| (l.as_slice(), r.as_slice()))
    }

    /// Available buffer count
    pub fn available_count(&self) -> usize {
        self.available.len()
    }

    /// Total capacity
    pub fn capacity(&self) -> usize {
        self.capacity
    }

    /// Resize all buffers (call when block size changes)
    pub fn resize(&mut self, new_block_size: usize) {
        self.block_size = new_block_size;
        for (l, r) in &mut self.buffers {
            l.resize(new_block_size, 0.0);
            r.resize(new_block_size, 0.0);
        }
    }

    /// Grow pool capacity (adds more pre-allocated buffers)
    pub fn grow(&mut self, additional: usize) {
        let new_capacity = self.capacity + additional;
        for i in self.capacity..new_capacity {
            self.buffers
                .push((vec![0.0; self.block_size], vec![0.0; self.block_size]));
            self.available.push(i);
        }
        self.capacity = new_capacity;
    }
}

impl Default for BufferPool {
    fn default() -> Self {
        Self::new(64, 256) // 64 buffer pairs, 256 samples each
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// CHANNEL TYPES
// ═══════════════════════════════════════════════════════════════════════════

/// Channel kind (semantic label, not hardcoded behavior)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default, Serialize, Deserialize)]
pub enum ChannelKind {
    /// Standard audio track (has clips)
    #[default]
    Audio,
    /// Bus/Group for submixing
    Bus,
    /// Aux/FX for send effects
    Aux,
    /// VCA (controls levels, no audio routing)
    Vca,
    /// Master output (special, single instance)
    Master,
}

impl ChannelKind {
    /// Get default color for channel kind
    pub fn default_color(&self) -> u32 {
        match self {
            ChannelKind::Audio => 0x4a9eff,  // Blue
            ChannelKind::Bus => 0x40ff90,    // Green
            ChannelKind::Aux => 0xff9040,    // Orange
            ChannelKind::Vca => 0xffff40,    // Yellow
            ChannelKind::Master => 0xff4060, // Red
        }
    }

    /// Get prefix for auto-naming
    pub fn prefix(&self) -> &'static str {
        match self {
            ChannelKind::Audio => "Audio",
            ChannelKind::Bus => "Bus",
            ChannelKind::Aux => "Aux",
            ChannelKind::Vca => "VCA",
            ChannelKind::Master => "Master",
        }
    }
}

/// Pan mode for stereo channels
/// Determines how panning is applied in the routing channel
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum PanMode {
    /// Standard single-knob pan (mono or balance-style)
    /// Routing channel applies pan normally
    #[default]
    Standard,
    /// External dual-pan (Pro Tools style)
    /// Pan is applied externally before routing (e.g., in playback engine)
    /// Routing channel bypasses pan, only applies fader gain
    ExternalDualPan,
    /// Stereo balance mode
    /// Attenuates opposite side instead of repositioning
    Balance,
}

// ═══════════════════════════════════════════════════════════════════════════
// CHANNEL IDENTIFIER
// ═══════════════════════════════════════════════════════════════════════════

/// Type-safe channel identifier
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct ChannelId(pub u32);

impl ChannelId {
    /// Master channel ID (always 0)
    pub const MASTER: ChannelId = ChannelId(0);

    /// Invalid/none channel ID
    pub const NONE: ChannelId = ChannelId(u32::MAX);

    /// Check if this is the master channel
    pub fn is_master(&self) -> bool {
        *self == Self::MASTER
    }
}

impl Default for ChannelId {
    fn default() -> Self {
        Self::NONE
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// OUTPUT DESTINATION
// ═══════════════════════════════════════════════════════════════════════════

/// Output routing destination
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum OutputDestination {
    /// Route to master (default)
    #[default]
    Master,
    /// Route to another channel (bus/aux)
    Channel(ChannelId),
    /// Route to hardware output directly
    HardwareOutput(u32),
    /// No output (sidechain-only source or muted)
    None,
}

impl OutputDestination {
    /// Get target channel ID if routing to a channel
    pub fn target_channel(&self) -> Option<ChannelId> {
        match self {
            OutputDestination::Master => Some(ChannelId::MASTER),
            OutputDestination::Channel(id) => Some(*id),
            _ => None,
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// SEND CONFIGURATION
// ═══════════════════════════════════════════════════════════════════════════

/// Send tap point (where signal is taken from)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum SendTapPoint {
    /// Before fader and pan
    PreFader,
    /// After fader, before pan (default)
    #[default]
    PostFader,
    /// After fader and pan
    PostPan,
}

/// Send configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SendConfig {
    /// Destination channel (usually Aux)
    pub destination: ChannelId,
    /// Send level in dB
    pub level_db: f64,
    /// Send pan (-1.0 to 1.0)
    pub pan: f64,
    /// Tap point
    pub tap_point: SendTapPoint,
    /// Is send enabled
    pub enabled: bool,
}

impl SendConfig {
    /// Create new send
    pub fn new(destination: ChannelId) -> Self {
        Self {
            destination,
            level_db: -6.0, // Default -6dB
            pan: 0.0,
            tap_point: SendTapPoint::PostFader,
            enabled: true,
        }
    }

    /// Create pre-fader send
    pub fn pre_fader(destination: ChannelId) -> Self {
        Self {
            tap_point: SendTapPoint::PreFader,
            ..Self::new(destination)
        }
    }

    /// Get linear gain
    pub fn gain(&self) -> f64 {
        if self.level_db <= -60.0 {
            0.0
        } else {
            10.0_f64.powf(self.level_db / 20.0)
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// CHANNEL
// ═══════════════════════════════════════════════════════════════════════════

/// Complete channel with routing
#[derive(Debug)]
#[allow(dead_code)]
pub struct Channel {
    /// Unique identifier
    pub id: ChannelId,
    /// Channel type
    pub kind: ChannelKind,
    /// Display name
    pub name: String,
    /// Color (RGB)
    pub color: u32,

    // Routing
    /// Output destination
    pub output: OutputDestination,
    /// Send configurations
    pub sends: Vec<SendConfig>,

    // Mixer state (using atomics for lock-free access from audio thread)
    /// Fader level in dB
    fader_db: f64,
    /// Pan (-1.0 to 1.0)
    pan: f64,
    /// Pan mode (determines how pan is applied)
    pan_mode: PanMode,
    /// Mute state
    muted: AtomicBool,
    /// Solo state
    soloed: AtomicBool,
    /// Record arm state
    armed: AtomicBool,
    /// Monitor state
    monitoring: AtomicBool,

    // DSP processing (Phase 1.1: unify with mixer.rs)
    /// Channel strip with full DSP chain (gate, comp, EQ, limiter, etc.)
    pub strip: Option<ChannelStrip>,

    // Plugin hosting (Phase 2: Plugin system foundation)
    /// Plugin insert chain (VST3/CLAP/AU/LV2)
    pub plugin_chain: Option<ZeroCopyChain>,

    // Metering (lock-free atomics for audio thread → UI thread)
    /// Peak level left channel (f64 bits stored as u64)
    pub peak_l: AtomicU64,
    /// Peak level right channel (f64 bits stored as u64)
    pub peak_r: AtomicU64,
    /// RMS level left channel (f64 bits stored as u64)
    pub rms_l: AtomicU64,
    /// RMS level right channel (f64 bits stored as u64)
    pub rms_r: AtomicU64,

    // Internal buffers
    input_left: Vec<Sample>,
    input_right: Vec<Sample>,
    output_left: Vec<Sample>,
    output_right: Vec<Sample>,

    // Send tap point buffers (for pre-fader, post-fader sends)
    /// Pre-fader signal (after DSP, before fader gain)
    prefader_left: Vec<Sample>,
    prefader_right: Vec<Sample>,
    /// Post-fader signal (after fader gain, before pan)
    postfader_left: Vec<Sample>,
    postfader_right: Vec<Sample>,

    // PDC (Plugin Delay Compensation)
    /// Per-channel delay buffer for routing-level PDC
    pdc_buffer: ChannelPdcBuffer,
    /// Channel's own latency (from plugin chain)
    own_latency: u32,
    /// Compensation delay applied to this channel
    pdc_delay: u32,

    // State
    /// Processing order index (computed by topological sort)
    processing_order: u32,
}

impl Channel {
    /// Create new channel
    pub fn new(id: ChannelId, kind: ChannelKind, name: &str, block_size: usize) -> Self {
        Self::with_sample_rate(id, kind, name, block_size, 48000.0)
    }

    /// Create new channel with specific sample rate
    pub fn with_sample_rate(
        id: ChannelId,
        kind: ChannelKind,
        name: &str,
        block_size: usize,
        sample_rate: f64,
    ) -> Self {
        Self {
            id,
            kind,
            name: name.to_string(),
            color: kind.default_color(),
            output: if id.is_master() {
                OutputDestination::HardwareOutput(0)
            } else {
                OutputDestination::Master
            },
            sends: Vec::new(),
            fader_db: 0.0,
            pan: 0.0,
            pan_mode: PanMode::Standard,
            muted: AtomicBool::new(false),
            soloed: AtomicBool::new(false),
            armed: AtomicBool::new(false),
            monitoring: AtomicBool::new(false),
            // Initialize DSP strip (all channels except VCA have processing)
            strip: if kind != ChannelKind::Vca {
                Some(ChannelStrip::new(sample_rate))
            } else {
                None
            },
            // Initialize plugin chain (8 max insert slots, 2 channels, block_size)
            plugin_chain: if kind != ChannelKind::Vca {
                Some(ZeroCopyChain::new(8, 2, block_size))
            } else {
                None
            },
            // Initialize metering to -infinity (0.0 in f64 bits)
            peak_l: AtomicU64::new(0),
            peak_r: AtomicU64::new(0),
            rms_l: AtomicU64::new(0),
            rms_r: AtomicU64::new(0),
            input_left: vec![0.0; block_size],
            input_right: vec![0.0; block_size],
            output_left: vec![0.0; block_size],
            output_right: vec![0.0; block_size],
            // Send tap point buffers
            prefader_left: vec![0.0; block_size],
            prefader_right: vec![0.0; block_size],
            postfader_left: vec![0.0; block_size],
            postfader_right: vec![0.0; block_size],
            // PDC buffer with max 1 second delay at 48kHz
            pdc_buffer: ChannelPdcBuffer::new(MAX_PDC_DELAY),
            own_latency: 0,
            pdc_delay: 0,
            processing_order: 0,
        }
    }

    /// Set fader level in dB
    pub fn set_fader(&mut self, db: f64) {
        self.fader_db = db.clamp(-144.0, 12.0);
    }

    /// Get fader level in dB
    pub fn fader_db(&self) -> f64 {
        self.fader_db
    }

    /// Get fader gain (linear)
    pub fn fader_gain(&self) -> f64 {
        if self.fader_db <= -60.0 {
            0.0
        } else {
            10.0_f64.powf(self.fader_db / 20.0)
        }
    }

    /// Set pan
    pub fn set_pan(&mut self, pan: f64) {
        self.pan = pan.clamp(-1.0, 1.0);
    }

    /// Get pan
    pub fn pan(&self) -> f64 {
        self.pan
    }

    /// Set pan mode
    pub fn set_pan_mode(&mut self, mode: PanMode) {
        self.pan_mode = mode;
    }

    /// Get pan mode
    pub fn pan_mode(&self) -> PanMode {
        self.pan_mode
    }

    /// Set mute (lock-free)
    pub fn set_mute(&self, muted: bool) {
        self.muted.store(muted, Ordering::Release);
    }

    /// Is muted (lock-free)
    pub fn is_muted(&self) -> bool {
        self.muted.load(Ordering::Acquire)
    }

    /// Set solo (lock-free)
    pub fn set_solo(&self, soloed: bool) {
        self.soloed.store(soloed, Ordering::Release);
    }

    /// Is soloed (lock-free)
    pub fn is_soloed(&self) -> bool {
        self.soloed.load(Ordering::Acquire)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // METERING (lock-free audio thread → UI thread)
    // ─────────────────────────────────────────────────────────────────────────

    /// Get peak levels in dB (lock-free read)
    pub fn peak_db(&self) -> (f64, f64) {
        let l = f64::from_bits(self.peak_l.load(Ordering::Relaxed));
        let r = f64::from_bits(self.peak_r.load(Ordering::Relaxed));
        (Self::linear_to_db(l), Self::linear_to_db(r))
    }

    /// Get RMS levels in dB (lock-free read)
    pub fn rms_db(&self) -> (f64, f64) {
        let l = f64::from_bits(self.rms_l.load(Ordering::Relaxed));
        let r = f64::from_bits(self.rms_r.load(Ordering::Relaxed));
        (Self::linear_to_db(l), Self::linear_to_db(r))
    }

    /// Update peak meters (called from audio thread)
    #[inline]
    fn update_peak(&self, left: f64, right: f64) {
        // Atomic store of f64 bits
        self.peak_l.store(left.to_bits(), Ordering::Relaxed);
        self.peak_r.store(right.to_bits(), Ordering::Relaxed);
    }

    /// Update RMS meters (called from audio thread)
    #[inline]
    fn update_rms(&self, left: f64, right: f64) {
        self.rms_l.store(left.to_bits(), Ordering::Relaxed);
        self.rms_r.store(right.to_bits(), Ordering::Relaxed);
    }

    /// Convert linear amplitude to dB
    #[inline]
    fn linear_to_db(linear: f64) -> f64 {
        if linear <= 0.0 {
            -144.0 // Floor
        } else {
            20.0 * linear.log10()
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // DSP ACCESS
    // ─────────────────────────────────────────────────────────────────────────

    /// Get mutable access to channel strip DSP
    pub fn strip_mut(&mut self) -> Option<&mut ChannelStrip> {
        self.strip.as_mut()
    }

    /// Get read access to channel strip DSP
    pub fn strip_ref(&self) -> Option<&ChannelStrip> {
        self.strip.as_ref()
    }

    /// Set sample rate for DSP chain
    pub fn set_sample_rate(&mut self, sample_rate: f64) {
        if let Some(strip) = &mut self.strip {
            use rf_dsp::ProcessorConfig;
            strip.set_sample_rate(sample_rate);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // PDC (Plugin Delay Compensation)
    // ─────────────────────────────────────────────────────────────────────────

    /// Get this channel's own latency (from plugin chain)
    pub fn own_latency(&self) -> u32 {
        if let Some(chain) = &self.plugin_chain {
            chain.latency()
        } else {
            0
        }
    }

    /// Update own latency cache (call after plugin changes)
    pub fn update_own_latency(&mut self) {
        self.own_latency = self.own_latency();
    }

    /// Set PDC compensation delay for this channel
    pub fn set_pdc_delay(&mut self, delay: u32) {
        self.pdc_delay = delay;
        self.pdc_buffer.set_delay(delay as usize);
    }

    /// Get current PDC delay
    pub fn pdc_delay(&self) -> u32 {
        self.pdc_delay
    }

    /// Clear PDC buffer (call on transport stop)
    pub fn clear_pdc(&mut self) {
        self.pdc_buffer.clear();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SENDS
    // ─────────────────────────────────────────────────────────────────────────

    /// Add send
    pub fn add_send(&mut self, destination: ChannelId, pre_fader: bool) {
        let mut send = SendConfig::new(destination);
        if pre_fader {
            send.tap_point = SendTapPoint::PreFader;
        }
        self.sends.push(send);
    }

    /// Remove send
    pub fn remove_send(&mut self, index: usize) {
        if index < self.sends.len() {
            self.sends.remove(index);
        }
    }

    /// Clear input buffers
    pub fn clear_input(&mut self) {
        self.input_left.fill(0.0);
        self.input_right.fill(0.0);
    }

    /// Add to input buffer (for summing from children)
    pub fn add_to_input(&mut self, left: &[Sample], right: &[Sample]) {
        for (i, (&l, &r)) in left.iter().zip(right.iter()).enumerate() {
            if i < self.input_left.len() {
                self.input_left[i] += l;
                self.input_right[i] += r;
            }
        }
    }

    /// Process channel (apply DSP chain, fader, pan, mute)
    ///
    /// # Send Tap Points
    /// This method populates tap point buffers for send routing:
    /// - `prefader_*`: Signal after DSP/plugins, before fader gain
    /// - `postfader_*`: Signal after fader gain, before pan
    /// - `output_*`: Final signal after fader, pan, and PDC (PostPan)
    pub fn process(&mut self, global_solo_active: bool) {
        let len = self.input_left.len().min(self.output_left.len());

        // Check mute/solo
        if self.is_muted() || (global_solo_active && !self.is_soloed()) {
            self.output_left.fill(0.0);
            self.output_right.fill(0.0);
            self.prefader_left.fill(0.0);
            self.prefader_right.fill(0.0);
            self.postfader_left.fill(0.0);
            self.postfader_right.fill(0.0);
            // Update meters with silence
            self.update_peak(0.0, 0.0);
            self.update_rms(0.0, 0.0);
            return;
        }

        // ═══════════════════════════════════════════════════════════════════════
        // STAGE 1: Input → Plugin Chain → DSP Strip → prefader_*
        // ═══════════════════════════════════════════════════════════════════════

        // Copy input to working buffer
        self.output_left[..len].copy_from_slice(&self.input_left[..len]);
        self.output_right[..len].copy_from_slice(&self.input_right[..len]);

        // Process through plugin chain first (if present)
        if let Some(plugin_chain) = &mut self.plugin_chain
            && !plugin_chain.is_empty() {
                // Convert f64 buffers to f32 for plugin API
                let mut plugin_input = PluginAudioBuffer::new(2, len);
                for i in 0..len {
                    plugin_input.data[0][i] = self.output_left[i] as f32;
                    plugin_input.data[1][i] = self.output_right[i] as f32;
                }

                let mut plugin_output = PluginAudioBuffer::new(2, len);

                // Process through plugin chain
                if plugin_chain.process(&plugin_input, &mut plugin_output).is_ok() {
                    // Convert f32 back to f64
                    for i in 0..len {
                        self.output_left[i] = plugin_output.data[0][i] as f64;
                        self.output_right[i] = plugin_output.data[1][i] as f64;
                    }
                }
            }

        // Process with DSP strip after plugins (if present)
        if let Some(strip) = &mut self.strip {
            use rf_dsp::StereoProcessor;
            for i in 0..len {
                let (l, r) = strip.process_sample(self.output_left[i], self.output_right[i]);
                self.output_left[i] = l;
                self.output_right[i] = r;
            }
        }

        // *** TAP POINT: PreFader (after DSP, before fader) ***
        self.prefader_left[..len].copy_from_slice(&self.output_left[..len]);
        self.prefader_right[..len].copy_from_slice(&self.output_right[..len]);

        // ═══════════════════════════════════════════════════════════════════════
        // STAGE 2: Apply Fader Gain → postfader_*
        // ═══════════════════════════════════════════════════════════════════════

        let gain = self.fader_gain();

        for i in 0..len {
            self.output_left[i] *= gain;
            self.output_right[i] *= gain;
        }

        // *** TAP POINT: PostFader (after fader, before pan) ***
        self.postfader_left[..len].copy_from_slice(&self.output_left[..len]);
        self.postfader_right[..len].copy_from_slice(&self.output_right[..len]);

        // ═══════════════════════════════════════════════════════════════════════
        // STAGE 3: Apply Pan → output_*
        // ═══════════════════════════════════════════════════════════════════════

        // Calculate pan gains based on pan mode
        let (pan_left, pan_right) = match self.pan_mode {
            PanMode::ExternalDualPan => {
                // Pan already applied externally (Pro Tools dual-pan)
                (1.0, 1.0)
            }
            PanMode::Balance => {
                // Balance mode: attenuate opposite side
                let left_atten = if self.pan > 0.0 { 1.0 - self.pan } else { 1.0 };
                let right_atten = if self.pan < 0.0 { 1.0 + self.pan } else { 1.0 };
                (left_atten, right_atten)
            }
            PanMode::Standard => {
                // Standard constant power pan
                let pan_angle = (self.pan + 1.0) * 0.25 * std::f64::consts::PI;
                (pan_angle.cos(), pan_angle.sin())
            }
        };

        // Track peak and RMS for metering (after pan, before PDC)
        let mut peak_l = 0.0_f64;
        let mut peak_r = 0.0_f64;
        let mut sum_sq_l = 0.0_f64;
        let mut sum_sq_r = 0.0_f64;

        for i in 0..len {
            let out_l = self.output_left[i] * pan_left;
            let out_r = self.output_right[i] * pan_right;

            self.output_left[i] = out_l;
            self.output_right[i] = out_r;

            // Update metering
            peak_l = peak_l.max(out_l.abs());
            peak_r = peak_r.max(out_r.abs());
            sum_sq_l += out_l * out_l;
            sum_sq_r += out_r * out_r;
        }

        // ═══════════════════════════════════════════════════════════════════════
        // STAGE 4: Apply PDC (output_* is now final: PostPan + PDC)
        // ═══════════════════════════════════════════════════════════════════════

        if self.pdc_delay > 0 {
            self.pdc_buffer.process(&mut self.output_left, &mut self.output_right);
        }

        // Update atomic meters (lock-free)
        self.update_peak(peak_l, peak_r);

        if len > 0 {
            let rms_l = (sum_sq_l / len as f64).sqrt();
            let rms_r = (sum_sq_r / len as f64).sqrt();
            self.update_rms(rms_l, rms_r);
        }
    }

    /// Get output buffers (PostPan + PDC - final signal)
    pub fn output(&self) -> (&[Sample], &[Sample]) {
        (&self.output_left, &self.output_right)
    }

    /// Get pre-fader tap point (after DSP, before fader)
    pub fn prefader(&self) -> (&[Sample], &[Sample]) {
        (&self.prefader_left, &self.prefader_right)
    }

    /// Get post-fader tap point (after fader, before pan)
    pub fn postfader(&self) -> (&[Sample], &[Sample]) {
        (&self.postfader_left, &self.postfader_right)
    }

    /// Get buffer for specified send tap point
    pub fn tap_point_buffer(&self, tap_point: SendTapPoint) -> (&[Sample], &[Sample]) {
        match tap_point {
            SendTapPoint::PreFader => self.prefader(),
            SendTapPoint::PostFader => self.postfader(),
            SendTapPoint::PostPan => self.output(),
        }
    }

    /// Resize buffers
    pub fn resize(&mut self, block_size: usize) {
        self.input_left.resize(block_size, 0.0);
        self.input_right.resize(block_size, 0.0);
        self.output_left.resize(block_size, 0.0);
        self.output_right.resize(block_size, 0.0);
        // Tap point buffers
        self.prefader_left.resize(block_size, 0.0);
        self.prefader_right.resize(block_size, 0.0);
        self.postfader_left.resize(block_size, 0.0);
        self.postfader_right.resize(block_size, 0.0);

        // Recreate plugin chain with new block size
        if self.plugin_chain.is_some() {
            self.plugin_chain = Some(ZeroCopyChain::new(8, 2, block_size));
        }
    }

    /// Get mutable access to plugin chain
    pub fn plugin_chain_mut(&mut self) -> Option<&mut ZeroCopyChain> {
        self.plugin_chain.as_mut()
    }

    /// Get read access to plugin chain
    pub fn plugin_chain_ref(&self) -> Option<&ZeroCopyChain> {
        self.plugin_chain.as_ref()
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// ROUTING GRAPH
// ═══════════════════════════════════════════════════════════════════════════

/// Routing error types
#[derive(Debug, Clone)]
pub enum RoutingError {
    /// Connection would create feedback loop
    WouldCreateCycle { from: ChannelId, to: ChannelId },
    /// Channel not found
    ChannelNotFound(ChannelId),
    /// Cannot route to self
    SelfReference(ChannelId),
    /// Invalid connection (e.g., routing audio track to VCA)
    InvalidConnection {
        from: ChannelId,
        to: ChannelId,
        reason: &'static str,
    },
}

/// Dynamic routing graph with feedback prevention
pub struct RoutingGraph {
    /// All channels indexed by ID
    channels: HashMap<ChannelId, Channel>,
    /// Processing order (topologically sorted)
    processing_order: Vec<ChannelId>,
    /// Next channel ID
    next_id: AtomicU32,
    /// Channel count (atomic for lock-free FFI queries, excludes master)
    channel_count: AtomicU32,
    /// Global solo state
    global_solo_active: AtomicBool,
    /// Graph is dirty (needs re-sorting)
    dirty: AtomicBool,
    /// Block size
    block_size: usize,
    /// Sample rate for DSP
    sample_rate: f64,

    // === Pre-allocated scratch buffers (AUDIO THREAD SAFETY) ===
    // These prevent heap allocations in the audio callback

    /// Scratch buffer for routing output L (avoids .to_vec() allocation)
    scratch_out_l: Vec<Sample>,
    /// Scratch buffer for routing output R
    scratch_out_r: Vec<Sample>,
    /// Scratch buffer for send processing L
    scratch_send_l: Vec<Sample>,
    /// Scratch buffer for send processing R
    scratch_send_r: Vec<Sample>,
}

/// RoutingGraph with integrated command queue for real-time audio thread
/// NOTE: This struct is NOT Sync due to rtrb Consumer/Producer
/// Use this in PlaybackEngine, NOT in lazy_static
pub struct RoutingGraphRT {
    /// The routing graph
    pub graph: RoutingGraph,
    /// Command receiver (consumed on audio thread)
    command_rx: Consumer<RoutingCommand>,
    /// Response sender (produced on audio thread)
    response_tx: Producer<RoutingResponse>,
}

/// Handle for sending commands to RoutingGraph from UI thread
pub struct RoutingCommandSender {
    /// Command sender
    command_tx: Producer<RoutingCommand>,
    /// Response receiver
    response_rx: Consumer<RoutingResponse>,
}

impl RoutingCommandSender {
    /// Send command to routing graph (lock-free, non-blocking)
    pub fn send(&mut self, cmd: RoutingCommand) -> bool {
        self.command_tx.push(cmd).is_ok()
    }

    /// Try to receive response (non-blocking)
    pub fn try_recv(&mut self) -> Option<RoutingResponse> {
        self.response_rx.pop().ok()
    }

    /// Send volume change
    pub fn set_volume(&mut self, id: ChannelId, db: f64) -> bool {
        self.send(RoutingCommand::SetVolume { id, db })
    }

    /// Send pan change
    pub fn set_pan(&mut self, id: ChannelId, pan: f64) -> bool {
        self.send(RoutingCommand::SetPan { id, pan })
    }

    /// Send mute change
    pub fn set_mute(&mut self, id: ChannelId, mute: bool) -> bool {
        self.send(RoutingCommand::SetMute { id, mute })
    }

    /// Send solo change
    pub fn set_solo(&mut self, id: ChannelId, solo: bool) -> bool {
        self.send(RoutingCommand::SetSolo { id, solo })
    }

    /// Request channel creation
    pub fn create_channel(&mut self, kind: ChannelKind, name: String, callback_id: u32) -> bool {
        self.send(RoutingCommand::CreateChannel {
            kind,
            name,
            callback_id,
        })
    }

    /// Request channel deletion
    pub fn delete_channel(&mut self, id: ChannelId) -> bool {
        self.send(RoutingCommand::DeleteChannel { id })
    }

    /// Set output routing
    pub fn set_output(&mut self, id: ChannelId, destination: OutputDestination) -> bool {
        self.send(RoutingCommand::SetOutput { id, destination })
    }

    /// Add send
    pub fn add_send(&mut self, from: ChannelId, to: ChannelId, pre_fader: bool) -> bool {
        self.send(RoutingCommand::AddSend {
            from,
            to,
            pre_fader,
        })
    }

    /// Remove send from channel
    pub fn remove_send(&mut self, from: ChannelId, send_index: usize) -> bool {
        self.send(RoutingCommand::RemoveSend { from, send_index })
    }
}

impl RoutingGraph {
    /// Create new routing graph with master channel
    pub fn new(block_size: usize) -> Self {
        Self::with_sample_rate(block_size, 48000.0)
    }

    /// Create new routing graph with specific sample rate
    pub fn with_sample_rate(block_size: usize, sample_rate: f64) -> Self {
        let mut channels = HashMap::new();

        // Create master channel (always ID 0)
        let master = Channel::with_sample_rate(
            ChannelId::MASTER,
            ChannelKind::Master,
            "Master",
            block_size,
            sample_rate,
        );
        channels.insert(ChannelId::MASTER, master);

        Self {
            channels,
            processing_order: vec![ChannelId::MASTER],
            next_id: AtomicU32::new(1), // Master is 0, start at 1
            channel_count: AtomicU32::new(0), // Excludes master
            global_solo_active: AtomicBool::new(false),
            dirty: AtomicBool::new(false),
            block_size,
            sample_rate,
            // Pre-allocate scratch buffers to avoid audio thread allocations
            scratch_out_l: vec![0.0; block_size],
            scratch_out_r: vec![0.0; block_size],
            scratch_send_l: vec![0.0; block_size],
            scratch_send_r: vec![0.0; block_size],
        }
    }

    /// Create new channel
    pub fn create_channel(&mut self, kind: ChannelKind, name: Option<&str>) -> ChannelId {
        let id = ChannelId(self.next_id.fetch_add(1, Ordering::Relaxed));
        let auto_name = name
            .map(String::from)
            .unwrap_or_else(|| format!("{} {}", kind.prefix(), id.0));

        let channel =
            Channel::with_sample_rate(id, kind, &auto_name, self.block_size, self.sample_rate);
        self.channels.insert(id, channel);
        self.channel_count.fetch_add(1, Ordering::Release);
        self.dirty.store(true, Ordering::Release);

        id
    }

    /// Create bus channel
    pub fn create_bus(&mut self, name: &str) -> ChannelId {
        self.create_channel(ChannelKind::Bus, Some(name))
    }

    /// Create aux channel
    pub fn create_aux(&mut self, name: &str) -> ChannelId {
        self.create_channel(ChannelKind::Aux, Some(name))
    }

    /// Delete channel
    pub fn delete_channel(&mut self, id: ChannelId) -> bool {
        if id.is_master() {
            return false; // Cannot delete master
        }

        if self.channels.remove(&id).is_some() {
            // Re-route any channels that were outputting to this one
            for channel in self.channels.values_mut() {
                if channel.output == OutputDestination::Channel(id) {
                    channel.output = OutputDestination::Master;
                }
                // Remove sends to this channel
                channel.sends.retain(|s| s.destination != id);
            }
            self.channel_count.fetch_sub(1, Ordering::Release);
            self.dirty.store(true, Ordering::Release);
            true
        } else {
            false
        }
    }

    /// Get channel by ID
    pub fn get(&self, id: ChannelId) -> Option<&Channel> {
        self.channels.get(&id)
    }

    /// Get mutable channel by ID
    pub fn get_mut(&mut self, id: ChannelId) -> Option<&mut Channel> {
        self.channels.get_mut(&id)
    }

    /// Get master channel
    pub fn master(&self) -> &Channel {
        self.channels
            .get(&ChannelId::MASTER)
            .expect("Master channel must exist")
    }

    /// Get mutable master channel
    pub fn master_mut(&mut self) -> &mut Channel {
        self.channels
            .get_mut(&ChannelId::MASTER)
            .expect("Master channel must exist")
    }

    /// Set channel output destination with validation
    pub fn set_output(
        &mut self,
        id: ChannelId,
        destination: OutputDestination,
    ) -> Result<(), RoutingError> {
        // Validate
        if id.is_master() {
            return Err(RoutingError::InvalidConnection {
                from: id,
                to: ChannelId::NONE,
                reason: "Cannot change master output",
            });
        }

        if let OutputDestination::Channel(to_id) = destination {
            if to_id == id {
                return Err(RoutingError::SelfReference(id));
            }

            if !self.channels.contains_key(&to_id) {
                return Err(RoutingError::ChannelNotFound(to_id));
            }

            // Check for cycle
            if self.would_create_cycle(id, to_id) {
                return Err(RoutingError::WouldCreateCycle {
                    from: id,
                    to: to_id,
                });
            }
        }

        // Apply
        if let Some(channel) = self.channels.get_mut(&id) {
            channel.output = destination;
            self.dirty.store(true, Ordering::Release);
        }

        Ok(())
    }

    /// Add send with validation
    pub fn add_send(
        &mut self,
        from: ChannelId,
        to: ChannelId,
        pre_fader: bool,
    ) -> Result<(), RoutingError> {
        if from == to {
            return Err(RoutingError::SelfReference(from));
        }

        if !self.channels.contains_key(&from) {
            return Err(RoutingError::ChannelNotFound(from));
        }

        if !self.channels.contains_key(&to) {
            return Err(RoutingError::ChannelNotFound(to));
        }

        // Check for cycle
        if self.would_create_cycle(from, to) {
            return Err(RoutingError::WouldCreateCycle { from, to });
        }

        // Add send
        if let Some(channel) = self.channels.get_mut(&from) {
            channel.add_send(to, pre_fader);
            self.dirty.store(true, Ordering::Release);
        }

        Ok(())
    }

    /// Check if adding edge would create cycle (DFS)
    fn would_create_cycle(&self, from: ChannelId, to: ChannelId) -> bool {
        // Check if 'from' is reachable from 'to' (would create cycle)
        let mut visited = HashSet::new();
        let mut stack = vec![to];

        while let Some(current) = stack.pop() {
            if current == from {
                return true;
            }

            if visited.insert(current)
                && let Some(channel) = self.channels.get(&current) {
                    // Check output
                    if let Some(target) = channel.output.target_channel() {
                        stack.push(target);
                    }
                    // Check sends
                    for send in &channel.sends {
                        stack.push(send.destination);
                    }
                }
        }

        false
    }

    /// Recompute processing order using Kahn's algorithm (topological sort)
    pub fn update_processing_order(&mut self) {
        if !self.dirty.load(Ordering::Acquire) {
            return;
        }

        // Calculate in-degrees
        let mut in_degree: HashMap<ChannelId, usize> = HashMap::new();
        for &id in self.channels.keys() {
            in_degree.insert(id, 0);
        }

        // Count incoming edges
        for channel in self.channels.values() {
            if let Some(target) = channel.output.target_channel() {
                *in_degree.entry(target).or_insert(0) += 1;
            }
            for send in &channel.sends {
                *in_degree.entry(send.destination).or_insert(0) += 1;
            }
        }

        // Start with source nodes (no inputs)
        let mut queue: VecDeque<ChannelId> = VecDeque::new();
        for (&id, &degree) in &in_degree {
            if degree == 0 {
                queue.push_back(id);
            }
        }

        // Process in topological order
        let mut order = Vec::new();
        while let Some(id) = queue.pop_front() {
            order.push(id);

            if let Some(channel) = self.channels.get(&id) {
                // Process output
                if let Some(target) = channel.output.target_channel() {
                    if let Some(deg) = in_degree.get_mut(&target) {
                        *deg -= 1;
                        if *deg == 0 {
                            queue.push_back(target);
                        }
                    }
                }

                // Process sends
                for send in &channel.sends {
                    if let Some(deg) = in_degree.get_mut(&send.destination) {
                        *deg -= 1;
                        if *deg == 0 {
                            queue.push_back(send.destination);
                        }
                    }
                }
            }
        }

        // Update processing order indices
        for (idx, &id) in order.iter().enumerate() {
            if let Some(channel) = self.channels.get_mut(&id) {
                channel.processing_order = idx as u32;
            }
        }

        self.processing_order = order;
        self.dirty.store(false, Ordering::Release);
    }

    /// Process all channels in correct order
    ///
    /// AUDIO THREAD SAFETY: This function uses pre-allocated scratch buffers
    /// to avoid heap allocations during real-time audio processing.
    pub fn process(&mut self) {
        // Update processing order if needed
        self.update_processing_order();

        // Update global solo state
        let solo_active = self.channels.values().any(|c| c.is_soloed());
        self.global_solo_active
            .store(solo_active, Ordering::Release);

        // Clear all inputs
        for channel in self.channels.values_mut() {
            channel.clear_input();
        }

        // Process in topological order
        // NOTE: We iterate by index to avoid cloning processing_order
        let num_channels = self.processing_order.len();
        for idx in 0..num_channels {
            let id = self.processing_order[idx];

            // First pass: process channel and collect routing info into scratch buffers
            let (target_id, num_sends) = {
                let channel = match self.channels.get_mut(&id) {
                    Some(c) => c,
                    None => continue,
                };

                channel.process(solo_active);

                // Copy output to scratch buffers (avoids .to_vec() allocation)
                let (out_l, out_r) = channel.output();
                let len = out_l.len().min(self.scratch_out_l.len());
                self.scratch_out_l[..len].copy_from_slice(&out_l[..len]);
                self.scratch_out_r[..len].copy_from_slice(&out_r[..len]);

                let target = channel.output.target_channel();

                // Count enabled sends (we'll process them in second pass)
                let num_sends = channel.sends.iter().filter(|s| s.enabled).count();

                (target, num_sends)
            };

            // Second pass: route to main destination
            if let Some(tid) = target_id
                && let Some(target) = self.channels.get_mut(&tid) {
                    target.add_to_input(&self.scratch_out_l, &self.scratch_out_r);
                }

            // Third pass: process sends with proper tap points
            if num_sends > 0 {
                // Collect send info with tap points (small stack allocation, max ~8 sends typical)
                let mut send_info: [(ChannelId, f64, SendTapPoint); 16] =
                    [(ChannelId(0), 0.0, SendTapPoint::PostFader); 16];
                let mut send_count = 0;

                if let Some(channel) = self.channels.get(&id) {
                    for send in channel.sends.iter().filter(|s| s.enabled).take(16) {
                        send_info[send_count] = (send.destination, send.gain(), send.tap_point);
                        send_count += 1;
                    }
                }

                // Apply sends using appropriate tap point buffer
                for i in 0..send_count {
                    let (dest_id, gain, tap_point) = send_info[i];

                    // Get source buffer based on tap point
                    let (src_l, src_r) = if let Some(channel) = self.channels.get(&id) {
                        channel.tap_point_buffer(tap_point)
                    } else {
                        continue;
                    };

                    // Scale source into send scratch buffer (avoids .collect() allocation)
                    let len = src_l.len().min(self.scratch_send_l.len());
                    for j in 0..len {
                        self.scratch_send_l[j] = src_l[j] * gain;
                        self.scratch_send_r[j] = src_r[j] * gain;
                    }

                    if let Some(target) = self.channels.get_mut(&dest_id) {
                        target.add_to_input(&self.scratch_send_l, &self.scratch_send_r);
                    }
                }
            }
        }
    }

    /// Get final output from master
    pub fn get_output(&self) -> (&[Sample], &[Sample]) {
        self.master().output()
    }

    /// Get all channels of a specific kind
    pub fn channels_of_kind(&self, kind: ChannelKind) -> Vec<&Channel> {
        self.channels.values().filter(|c| c.kind == kind).collect()
    }

    /// Get all channel IDs
    pub fn all_channel_ids(&self) -> Vec<ChannelId> {
        self.channels.keys().copied().collect()
    }

    /// Get channel count (excluding master)
    pub fn channel_count(&self) -> usize {
        self.channels.len() - 1 // Exclude master
    }

    /// Get channel count (atomic, lock-free for FFI)
    pub fn channel_count_atomic(&self) -> u32 {
        self.channel_count.load(Ordering::Acquire)
    }

    /// Set block size for all channels
    pub fn set_block_size(&mut self, block_size: usize) {
        self.block_size = block_size;
        for channel in self.channels.values_mut() {
            channel.resize(block_size);
        }
        // Resize scratch buffers
        self.scratch_out_l.resize(block_size, 0.0);
        self.scratch_out_r.resize(block_size, 0.0);
        self.scratch_send_l.resize(block_size, 0.0);
        self.scratch_send_r.resize(block_size, 0.0);
    }

    /// Set sample rate for all channels (updates DSP)
    pub fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        for channel in self.channels.values_mut() {
            channel.set_sample_rate(sample_rate);
        }
    }

    /// Get current sample rate
    pub fn sample_rate(&self) -> f64 {
        self.sample_rate
    }

    /// Recalculate PDC (Plugin Delay Compensation) for all channels
    ///
    /// This finds the maximum latency across all channels that route to the same
    /// destination, then sets compensation delays so they all arrive in sync.
    ///
    /// Call this after:
    /// - Adding/removing plugins
    /// - Changing plugin bypass state
    /// - Modifying routing
    pub fn recalculate_pdc(&mut self) {
        // Step 1: Update own_latency for all channels
        for channel in self.channels.values_mut() {
            channel.update_own_latency();
        }

        // Step 2: For each destination, find max latency of sources
        // Build destination -> sources map
        let mut dest_sources: HashMap<ChannelId, Vec<(ChannelId, u32)>> = HashMap::new();

        for (id, channel) in &self.channels {
            if let Some(dest_id) = channel.output.target_channel() {
                let latency = channel.own_latency;
                dest_sources
                    .entry(dest_id)
                    .or_insert_with(Vec::new)
                    .push((*id, latency));
            }
        }

        // Step 3: Calculate compensation delays per destination group
        for (_dest_id, sources) in &dest_sources {
            if sources.len() <= 1 {
                continue; // No compensation needed for single source
            }

            // Find max latency in this group
            let max_latency = sources.iter().map(|(_, lat)| *lat).max().unwrap_or(0);

            // Set compensation delays
            for (src_id, own_lat) in sources {
                let compensation = max_latency.saturating_sub(*own_lat);
                if let Some(channel) = self.channels.get_mut(src_id) {
                    channel.set_pdc_delay(compensation);
                }
            }
        }
    }

    /// Clear all PDC buffers (call on transport stop/reset)
    pub fn clear_all_pdc(&mut self) {
        for channel in self.channels.values_mut() {
            channel.clear_pdc();
        }
    }

    /// Recalculate PDC from cached own_latency values (for testing)
    /// Does NOT call update_own_latency() — uses existing cached values
    #[cfg(test)]
    fn recalculate_pdc_from_cached(&mut self) {
        // Build destination -> sources map
        let mut dest_sources: HashMap<ChannelId, Vec<(ChannelId, u32)>> = HashMap::new();

        for (id, channel) in &self.channels {
            if let Some(dest_id) = channel.output.target_channel() {
                let latency = channel.own_latency;
                dest_sources
                    .entry(dest_id)
                    .or_insert_with(Vec::new)
                    .push((*id, latency));
            }
        }

        // Calculate compensation delays per destination group
        for (_dest_id, sources) in &dest_sources {
            if sources.len() <= 1 {
                continue;
            }

            let max_latency = sources.iter().map(|(_, lat)| *lat).max().unwrap_or(0);

            for (src_id, own_lat) in sources {
                let compensation = max_latency.saturating_sub(*own_lat);
                if let Some(channel) = self.channels.get_mut(src_id) {
                    channel.set_pdc_delay(compensation);
                }
            }
        }
    }

    /// Get bus count
    pub fn bus_count(&self) -> usize {
        self.channels
            .values()
            .filter(|c| c.kind == ChannelKind::Bus)
            .count()
    }

    /// Get aux count
    pub fn aux_count(&self) -> usize {
        self.channels
            .values()
            .filter(|c| c.kind == ChannelKind::Aux)
            .count()
    }

    /// Get iterator over all channels
    pub fn iter_channels(&self) -> impl Iterator<Item = &Channel> {
        self.channels.values()
    }

    /// Get mutable iterator over all channels
    pub fn iter_channels_mut(&mut self) -> impl Iterator<Item = &mut Channel> {
        self.channels.values_mut()
    }
}

impl Default for RoutingGraph {
    fn default() -> Self {
        Self::new(256)
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// ROUTING GRAPH RT (Real-Time version with command queue)
// ═══════════════════════════════════════════════════════════════════════════

impl RoutingGraphRT {
    /// Create new real-time routing graph with command queue
    /// Returns (graph_rt, command_sender) tuple
    pub fn new(block_size: usize) -> (Self, RoutingCommandSender) {
        Self::with_sample_rate(block_size, 48000.0)
    }

    /// Create new real-time routing graph with specific sample rate
    pub fn with_sample_rate(block_size: usize, sample_rate: f64) -> (Self, RoutingCommandSender) {
        let graph = RoutingGraph::with_sample_rate(block_size, sample_rate);

        // Create lock-free ring buffers
        let (command_tx, command_rx) = RingBuffer::new(COMMAND_QUEUE_SIZE);
        let (response_tx, response_rx) = RingBuffer::new(RESPONSE_QUEUE_SIZE);

        let graph_rt = Self {
            graph,
            command_rx,
            response_tx,
        };

        let sender = RoutingCommandSender {
            command_tx,
            response_rx,
        };

        (graph_rt, sender)
    }

    /// Process all pending commands from UI thread
    /// Call this at the START of each audio block
    pub fn process_commands(&mut self) {
        while let Ok(cmd) = self.command_rx.pop() {
            self.execute_command(cmd);
        }
    }

    /// Execute a single routing command
    fn execute_command(&mut self, cmd: RoutingCommand) {
        match cmd {
            RoutingCommand::CreateChannel {
                kind,
                name,
                callback_id,
            } => {
                let id = self.graph.create_channel(kind, Some(&name));
                let _ = self.response_tx.push(RoutingResponse::ChannelCreated {
                    callback_id,
                    channel_id: id,
                });
            }

            RoutingCommand::DeleteChannel { id } => {
                if self.graph.delete_channel(id) {
                    let _ = self.response_tx.push(RoutingResponse::ChannelDeleted { id });
                }
            }

            RoutingCommand::SetOutput { id, destination } => {
                match self.graph.set_output(id, destination) {
                    Ok(()) => {
                        // Routing changed — recalculate PDC for new destination group
                        self.graph.recalculate_pdc();
                    }
                    Err(e) => {
                        let _ = self.response_tx.push(RoutingResponse::Error {
                            message: format!("{:?}", e),
                        });
                    }
                }
            }

            RoutingCommand::AddSend {
                from,
                to,
                pre_fader,
            } => {
                if let Err(e) = self.graph.add_send(from, to, pre_fader) {
                    let _ = self.response_tx.push(RoutingResponse::Error {
                        message: format!("{:?}", e),
                    });
                }
            }

            RoutingCommand::RemoveSend { from, send_index } => {
                if let Some(channel) = self.graph.get_mut(from) {
                    channel.remove_send(send_index);
                }
            }

            RoutingCommand::SetSendLevel {
                from,
                send_index,
                level_db,
            } => {
                if let Some(channel) = self.graph.get_mut(from)
                    && let Some(send) = channel.sends.get_mut(send_index) {
                        send.level_db = level_db.clamp(-60.0, 12.0);
                    }
            }

            RoutingCommand::SetSendEnabled {
                from,
                send_index,
                enabled,
            } => {
                if let Some(channel) = self.graph.get_mut(from)
                    && let Some(send) = channel.sends.get_mut(send_index) {
                        send.enabled = enabled;
                    }
            }

            RoutingCommand::SetSendPan {
                from,
                send_index,
                pan,
            } => {
                if let Some(channel) = self.graph.get_mut(from)
                    && let Some(send) = channel.sends.get_mut(send_index) {
                        send.pan = pan.clamp(-1.0, 1.0);
                    }
            }

            RoutingCommand::SetVolume { id, db } => {
                if let Some(channel) = self.graph.get_mut(id) {
                    channel.set_fader(db);
                }
            }

            RoutingCommand::SetPan { id, pan } => {
                if let Some(channel) = self.graph.get_mut(id) {
                    channel.set_pan(pan);
                }
            }

            RoutingCommand::SetMute { id, mute } => {
                if let Some(channel) = self.graph.get(id) {
                    channel.set_mute(mute);
                }
            }

            RoutingCommand::SetSolo { id, solo } => {
                if let Some(channel) = self.graph.get(id) {
                    channel.set_solo(solo);
                }
            }

            // DSP commands
            RoutingCommand::SetInputGain { id, db } => {
                if let Some(channel) = self.graph.get_mut(id)
                    && let Some(strip) = channel.strip_mut() {
                        strip.set_input_gain_db(db);
                    }
            }

            RoutingCommand::SetOutputGain { id, db } => {
                if let Some(channel) = self.graph.get_mut(id)
                    && let Some(strip) = channel.strip_mut() {
                        strip.set_output_gain_db(db);
                    }
            }

            RoutingCommand::SetHpfEnabled { id, enabled } => {
                if let Some(channel) = self.graph.get_mut(id)
                    && let Some(strip) = channel.strip_mut() {
                        strip.set_hpf_enabled(enabled);
                    }
            }

            RoutingCommand::SetHpfFreq { id, freq } => {
                if let Some(channel) = self.graph.get_mut(id)
                    && let Some(strip) = channel.strip_mut() {
                        strip.set_hpf_freq(freq);
                    }
            }

            RoutingCommand::SetGateEnabled { id, enabled } => {
                if let Some(channel) = self.graph.get_mut(id)
                    && let Some(strip) = channel.strip_mut() {
                        strip.set_gate_enabled(enabled);
                    }
            }

            RoutingCommand::SetGateThreshold { id, db } => {
                if let Some(channel) = self.graph.get_mut(id)
                    && let Some(strip) = channel.strip_mut() {
                        strip.set_gate_threshold(db);
                    }
            }

            RoutingCommand::SetCompEnabled { id, enabled } => {
                if let Some(channel) = self.graph.get_mut(id)
                    && let Some(strip) = channel.strip_mut() {
                        strip.set_comp_enabled(enabled);
                    }
            }

            RoutingCommand::SetCompThreshold { id, db } => {
                if let Some(channel) = self.graph.get_mut(id)
                    && let Some(strip) = channel.strip_mut() {
                        strip.set_comp_threshold(db);
                    }
            }

            RoutingCommand::SetCompRatio { id, ratio } => {
                if let Some(channel) = self.graph.get_mut(id)
                    && let Some(strip) = channel.strip_mut() {
                        strip.set_comp_ratio(ratio);
                    }
            }

            RoutingCommand::SetCompAttack { id, ms } => {
                if let Some(channel) = self.graph.get_mut(id)
                    && let Some(strip) = channel.strip_mut() {
                        strip.set_comp_attack(ms);
                    }
            }

            RoutingCommand::SetCompRelease { id, ms } => {
                if let Some(channel) = self.graph.get_mut(id)
                    && let Some(strip) = channel.strip_mut() {
                        strip.set_comp_release(ms);
                    }
            }

            RoutingCommand::SetEqEnabled { id, enabled } => {
                if let Some(channel) = self.graph.get_mut(id)
                    && let Some(strip) = channel.strip_mut() {
                        strip.set_eq_enabled(enabled);
                    }
            }

            RoutingCommand::SetEqLow { id, freq, gain_db } => {
                if let Some(channel) = self.graph.get_mut(id)
                    && let Some(strip) = channel.strip_mut() {
                        strip.set_eq_low(freq, gain_db);
                    }
            }

            RoutingCommand::SetEqLowMid {
                id,
                freq,
                gain_db,
                q,
            } => {
                if let Some(channel) = self.graph.get_mut(id)
                    && let Some(strip) = channel.strip_mut() {
                        strip.set_eq_low_mid(freq, gain_db, q);
                    }
            }

            RoutingCommand::SetEqHighMid {
                id,
                freq,
                gain_db,
                q,
            } => {
                if let Some(channel) = self.graph.get_mut(id)
                    && let Some(strip) = channel.strip_mut() {
                        strip.set_eq_high_mid(freq, gain_db, q);
                    }
            }

            RoutingCommand::SetEqHigh { id, freq, gain_db } => {
                if let Some(channel) = self.graph.get_mut(id)
                    && let Some(strip) = channel.strip_mut() {
                        strip.set_eq_high(freq, gain_db);
                    }
            }

            RoutingCommand::SetLimiterEnabled { id, enabled } => {
                if let Some(channel) = self.graph.get_mut(id)
                    && let Some(strip) = channel.strip_mut() {
                        strip.set_limiter_enabled(enabled);
                    }
            }

            RoutingCommand::SetLimiterThreshold { id, db } => {
                if let Some(channel) = self.graph.get_mut(id)
                    && let Some(strip) = channel.strip_mut() {
                        strip.set_limiter_threshold(db);
                    }
            }

            RoutingCommand::SetWidth { id, width } => {
                if let Some(channel) = self.graph.get_mut(id)
                    && let Some(strip) = channel.strip_mut() {
                        strip.set_width(width);
                    }
            }

            // Plugin insert chain commands
            // NOTE: These commands trigger PDC recalculation as plugin latency affects routing
            RoutingCommand::AddInsert { id, plugin_id, slot_index } => {
                let mut added = false;
                if let Some(channel) = self.graph.get_mut(id)
                    && let Some(chain) = channel.plugin_chain_mut() {
                        // Load plugin from PLUGIN_HOST
                        if let Ok(plugin) = rf_plugin::load_plugin(&plugin_id) {
                            match slot_index {
                                Some(idx) => {
                                    // Insert at specific index (not supported yet, just add)
                                    let _ = chain.add(plugin);
                                    log::info!("Added plugin {} at slot {} (requested {})", plugin_id, chain.len() - 1, idx);
                                    added = true;
                                }
                                None => {
                                    let _ = chain.add(plugin);
                                    log::info!("Added plugin {} at slot {}", plugin_id, chain.len() - 1);
                                    added = true;
                                }
                            }
                        } else {
                            log::error!("Failed to load plugin {} for insert chain", plugin_id);
                        }
                    }
                // Recalculate PDC after plugin added (latency may have changed)
                if added {
                    self.graph.recalculate_pdc();
                }
            }

            RoutingCommand::RemoveInsert { id, slot_index } => {
                let mut removed = false;
                if let Some(channel) = self.graph.get_mut(id)
                    && let Some(chain) = channel.plugin_chain_mut()
                    && chain.remove(slot_index).is_some()
                {
                    log::info!("Removed plugin from slot {} on channel {:?}", slot_index, id);
                    removed = true;
                }
                // Recalculate PDC after plugin removed
                if removed {
                    self.graph.recalculate_pdc();
                }
            }

            RoutingCommand::SetInsertBypass { id, slot_index, bypass } => {
                let mut changed = false;
                if let Some(channel) = self.graph.get_mut(id)
                    && let Some(chain) = channel.plugin_chain_mut()
                    && let Some(slot) = chain.get(slot_index) {
                        slot.set_bypass(bypass);
                        changed = true;
                    }
                // Recalculate PDC after bypass state changed (affects effective latency)
                if changed {
                    self.graph.recalculate_pdc();
                }
            }

            RoutingCommand::SetInsertMix { id, slot_index, mix } => {
                if let Some(channel) = self.graph.get_mut(id)
                    && let Some(chain) = channel.plugin_chain_mut()
                    && let Some(slot) = chain.get(slot_index) {
                        slot.set_mix(mix as f32);
                    }
            }
        }
    }

    /// Process audio through the routing graph
    pub fn process(&mut self) {
        self.graph.process();
    }

    /// Get final output from master
    pub fn get_output(&self) -> (&[rf_core::Sample], &[rf_core::Sample]) {
        self.graph.get_output()
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_create_bus() {
        let mut graph = RoutingGraph::new(256);

        let bus_id = graph.create_bus("Drums");
        assert!(graph.get(bus_id).is_some());
        assert_eq!(graph.get(bus_id).unwrap().kind, ChannelKind::Bus);
    }

    #[test]
    fn test_routing() {
        let mut graph = RoutingGraph::new(256);

        let drums_bus = graph.create_bus("Drums");
        let kick_track = graph.create_channel(ChannelKind::Audio, Some("Kick"));

        // Route kick to drums bus
        graph
            .set_output(kick_track, OutputDestination::Channel(drums_bus))
            .unwrap();

        assert_eq!(
            graph.get(kick_track).unwrap().output,
            OutputDestination::Channel(drums_bus)
        );
    }

    #[test]
    fn test_cycle_prevention() {
        let mut graph = RoutingGraph::new(256);

        let bus_a = graph.create_bus("Bus A");
        let bus_b = graph.create_bus("Bus B");

        // A -> B (OK)
        graph
            .set_output(bus_a, OutputDestination::Channel(bus_b))
            .unwrap();

        // B -> A (would create cycle)
        let result = graph.set_output(bus_b, OutputDestination::Channel(bus_a));
        assert!(matches!(result, Err(RoutingError::WouldCreateCycle { .. })));
    }

    #[test]
    fn test_self_reference() {
        let mut graph = RoutingGraph::new(256);

        let bus = graph.create_bus("Bus");
        let result = graph.set_output(bus, OutputDestination::Channel(bus));
        assert!(matches!(result, Err(RoutingError::SelfReference(_))));
    }

    #[test]
    fn test_send() {
        let mut graph = RoutingGraph::new(256);

        let reverb_aux = graph.create_aux("Reverb");
        let track = graph.create_channel(ChannelKind::Audio, Some("Vocal"));

        // Add send from track to reverb
        graph.add_send(track, reverb_aux, false).unwrap();

        assert_eq!(graph.get(track).unwrap().sends.len(), 1);
        assert_eq!(graph.get(track).unwrap().sends[0].destination, reverb_aux);
    }

    #[test]
    fn test_processing_order() {
        let mut graph = RoutingGraph::new(256);

        let drums_bus = graph.create_bus("Drums");
        let _music_bus = graph.create_bus("Music");
        let kick = graph.create_channel(ChannelKind::Audio, Some("Kick"));
        let snare = graph.create_channel(ChannelKind::Audio, Some("Snare"));

        // Route kick, snare -> drums bus -> master
        graph
            .set_output(kick, OutputDestination::Channel(drums_bus))
            .unwrap();
        graph
            .set_output(snare, OutputDestination::Channel(drums_bus))
            .unwrap();

        graph.update_processing_order();

        // Kick and snare should process before drums bus
        let kick_order = graph.get(kick).unwrap().processing_order;
        let drums_order = graph.get(drums_bus).unwrap().processing_order;
        let master_order = graph.get(ChannelId::MASTER).unwrap().processing_order;

        assert!(kick_order < drums_order);
        assert!(drums_order < master_order);
    }

    #[test]
    fn test_command_queue_rt() {
        let (mut graph_rt, mut sender) = RoutingGraphRT::new(256);

        // Send command from "UI thread"
        sender.set_volume(ChannelId::MASTER, -6.0);
        sender.set_pan(ChannelId::MASTER, 0.5);

        // Process commands on "audio thread"
        graph_rt.process_commands();

        // Verify changes applied
        assert!((graph_rt.graph.master().fader_db() - (-6.0)).abs() < 0.001);
        assert!((graph_rt.graph.master().pan() - 0.5).abs() < 0.001);
    }

    #[test]
    fn test_create_channel_via_command() {
        let (mut graph_rt, mut sender) = RoutingGraphRT::new(256);

        // Request channel creation
        sender.create_channel(ChannelKind::Bus, "Test Bus".to_string(), 42);

        // Process command
        graph_rt.process_commands();

        // Check response
        if let Some(response) = sender.try_recv() {
            match response {
                RoutingResponse::ChannelCreated {
                    callback_id,
                    channel_id,
                } => {
                    assert_eq!(callback_id, 42);
                    assert!(graph_rt.graph.get(channel_id).is_some());
                    assert_eq!(graph_rt.graph.get(channel_id).unwrap().name, "Test Bus");
                }
                _ => panic!("Expected ChannelCreated response"),
            }
        } else {
            panic!("Expected response");
        }
    }

    #[test]
    fn test_channel_with_dsp() {
        let mut graph = RoutingGraph::new(256);
        let track = graph.create_channel(ChannelKind::Audio, Some("Test"));

        // Audio channel should have DSP strip
        assert!(graph.get(track).unwrap().strip_ref().is_some());

        // VCA should NOT have DSP strip
        let vca = graph.create_channel(ChannelKind::Vca, Some("VCA"));
        assert!(graph.get(vca).unwrap().strip_ref().is_none());
    }

    #[test]
    fn test_metering() {
        let mut graph = RoutingGraph::new(256);
        let track = graph.create_channel(ChannelKind::Audio, Some("Test"));

        // Get initial metering (should be -infinity)
        let (peak_l, peak_r) = graph.get(track).unwrap().peak_db();
        assert!(peak_l < -100.0);
        assert!(peak_r < -100.0);
    }

    #[test]
    fn test_buffer_pool() {
        let mut pool = BufferPool::new(4, 256);

        assert_eq!(pool.capacity(), 4);
        assert_eq!(pool.available_count(), 4);

        // Acquire buffers
        let buf1 = pool.acquire().unwrap();
        let _buf2 = pool.acquire().unwrap();
        assert_eq!(pool.available_count(), 2);

        // Write to buffer
        if let Some((l, r)) = pool.get_mut(buf1) {
            l[0] = 0.5;
            r[0] = -0.5;
        }

        // Release buffer
        pool.release(buf1);
        assert_eq!(pool.available_count(), 3);

        // Buffer should be cleared after release
        if let Some((l, r)) = pool.get(buf1) {
            assert_eq!(l[0], 0.0);
            assert_eq!(r[0], 0.0);
        }
    }

    #[test]
    fn test_buffer_pool_grow() {
        let mut pool = BufferPool::new(2, 128);
        assert_eq!(pool.capacity(), 2);

        pool.grow(3);
        assert_eq!(pool.capacity(), 5);
        assert_eq!(pool.available_count(), 5);
    }

    #[test]
    fn test_dynamic_bus_creation() {
        let mut graph = RoutingGraph::new(256);

        // Create many buses dynamically
        let mut bus_ids = Vec::new();
        for i in 0..20 {
            let id = graph.create_bus(&format!("Bus {}", i));
            bus_ids.push(id);
        }

        // All should exist
        assert_eq!(graph.bus_count(), 20);
        for id in &bus_ids {
            assert!(graph.get(*id).is_some());
        }

        // Delete half
        for id in bus_ids.iter().take(10) {
            graph.delete_channel(*id);
        }
        assert_eq!(graph.bus_count(), 10);
    }

    #[test]
    fn test_channel_pdc_buffer() {
        let mut pdc = ChannelPdcBuffer::new(1024);

        // Initial state: no delay
        assert_eq!(pdc.delay(), 0);

        // Set delay
        pdc.set_delay(100);
        assert_eq!(pdc.delay(), 100);

        // Process with delay
        let mut left = [1.0, 2.0, 3.0, 4.0, 5.0];
        let mut right = [0.5, 1.0, 1.5, 2.0, 2.5];

        pdc.process(&mut left, &mut right);

        // First samples should be delayed (zeros from empty buffer)
        assert_eq!(left[0], 0.0);
        assert_eq!(right[0], 0.0);

        // Clear buffer
        pdc.clear();
        assert_eq!(pdc.delay(), 100); // Delay preserved
    }

    #[test]
    fn test_send_tap_points() {
        let mut graph = RoutingGraph::new(8);

        // Create VCA (no DSP strip) to test pure tap point logic
        let track = graph.create_channel(ChannelKind::Vca, Some("Test VCA"));
        let reverb_aux = graph.create_aux("Reverb");

        // Set track fader to -6dB (~0.5 linear gain)
        if let Some(ch) = graph.get_mut(track) {
            ch.set_fader(-6.0);
            // Set pan mode to external to avoid pan affecting signal
            ch.set_pan_mode(PanMode::ExternalDualPan);
        }

        // Add pre-fader send via graph method
        graph.add_send(track, reverb_aux, true).unwrap(); // pre_fader = true

        // Get mutable access to track
        if let Some(ch) = graph.get_mut(track) {
            // Manually add input
            ch.add_to_input(&[1.0; 8], &[1.0; 8]);
            // Process the channel
            ch.process(false);
        }

        // Now check prefader buffer on track
        let prefader_l = {
            let ch = graph.get(track).unwrap();
            let (l, _) = ch.prefader();
            l[0]
        };
        eprintln!("Track prefader[0] = {}", prefader_l);

        // Prefader should be 1.0 (input signal, before fader)
        // VCA has no DSP strip so input passes through unchanged
        assert!(
            (prefader_l - 1.0).abs() < 0.01,
            "Prefader should be ~1.0 (input signal before fader). Got: {}",
            prefader_l
        );

        // Postfader should be ~0.5 (after -6dB fader = 10^(-6/20) ≈ 0.501)
        let postfader_l = {
            let ch = graph.get(track).unwrap();
            let (l, _) = ch.postfader();
            l[0]
        };
        eprintln!("Track postfader[0] = {}", postfader_l);

        let expected_postfader = 10.0_f64.powf(-6.0 / 20.0); // ~0.501
        assert!(
            (postfader_l - expected_postfader).abs() < 0.01,
            "Postfader should be ~{:.3} (after -6dB fader). Got: {}",
            expected_postfader,
            postfader_l
        );

        // Final output should equal postfader since pan mode is ExternalDualPan
        let output_l = {
            let ch = graph.get(track).unwrap();
            let (l, _) = ch.output();
            l[0]
        };
        eprintln!("Track output[0] = {}", output_l);

        assert!(
            (output_l - expected_postfader).abs() < 0.01,
            "Output should equal postfader with ExternalDualPan. Got: {}",
            output_l
        );
    }

    #[test]
    fn test_pdc_recalculation() {
        let mut graph = RoutingGraph::new(256);

        // Create two audio tracks routing to master
        let track_a = graph.create_channel(ChannelKind::Audio, Some("Track A"));
        let track_b = graph.create_channel(ChannelKind::Audio, Some("Track B"));

        // Both route to master (default)
        assert_eq!(graph.get(track_a).unwrap().output, OutputDestination::Master);
        assert_eq!(graph.get(track_b).unwrap().output, OutputDestination::Master);

        // Manually set own_latency to simulate plugin latency
        // Track A: 100 samples, Track B: 0 samples
        // NOTE: We set own_latency directly and use recalculate_pdc_from_cached()
        // which doesn't call update_own_latency()
        if let Some(ch) = graph.get_mut(track_a) {
            ch.own_latency = 100;
        }
        if let Some(ch) = graph.get_mut(track_b) {
            ch.own_latency = 0;
        }

        // Recalculate PDC from cached latencies (for testing)
        graph.recalculate_pdc_from_cached();

        // Track B should have compensation delay of 100 (to match Track A)
        assert_eq!(graph.get(track_b).unwrap().pdc_delay(), 100);
        // Track A should have 0 compensation (it has max latency)
        assert_eq!(graph.get(track_a).unwrap().pdc_delay(), 0);
    }
}
