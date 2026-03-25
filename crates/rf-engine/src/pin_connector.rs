//! Pin Connector — Per-Plugin Channel Routing Matrix (Reaper-style)
//!
//! Provides flexible multi-channel routing between host and plugin:
//! - Up to 64 internal channels per insert slot
//! - Routing matrix: input channels → plugin channels → output channels
//! - Routing modes: Normal, Multi-Mono, Mid/Side, Surround-per-channel
//! - Zero-allocation audio thread processing (pre-allocated buffers)
//! - Full gain matrix for arbitrary channel mapping
//!
//! # Architecture
//!
//! ```text
//!  Host Channels (2-64)          Plugin Channels (2-64)
//!  ┌─────────────────┐           ┌─────────────────┐
//!  │  In 1 ──────────┼──────────►│  Plugin In 1    │
//!  │  In 2 ──────────┼──╲   ╱──►│  Plugin In 2    │
//!  │  In 3 ──────────┼───╲ ╱───►│  Plugin In 3    │
//!  │  ...            │    ╳     │  ...            │
//!  │  In N ──────────┼───╱ ╲───►│  Plugin In M    │
//!  └─────────────────┘  Routing  └─────────────────┘
//!                       Matrix
//! ```

use rf_core::Sample;
use std::sync::atomic::{AtomicBool, Ordering};

// =============================================================================
// CONSTANTS
// =============================================================================

/// Maximum channels supported per pin connector
pub const MAX_PIN_CHANNELS: usize = 64;

/// Maximum block size for pre-allocated buffers
const MAX_BUFFER_SIZE: usize = 8192;

// =============================================================================
// CHANNEL MAPPING MODE
// =============================================================================

/// Routing mode for the pin connector
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PinRoutingMode {
    /// Normal stereo/multi-channel pass-through (1:1 mapping)
    Normal,
    /// Multi-mono: same mono signal to each plugin input, separate outputs
    /// Used for per-channel processing (e.g. separate compressor per channel)
    MultiMono,
    /// Mid/Side: encode L/R to M/S before plugin, decode after
    MidSide,
    /// Surround per-channel: each surround channel processed independently
    /// through the same stereo plugin (cycling pairs)
    SurroundPerChannel,
    /// Custom matrix: user-defined gain routing
    CustomMatrix,
}

impl Default for PinRoutingMode {
    fn default() -> Self {
        Self::Normal
    }
}

// =============================================================================
// PIN MAPPING ENTRY
// =============================================================================

/// Single routing connection: source channel → destination channel with gain
#[derive(Debug, Clone, Copy)]
pub struct PinMapping {
    /// Source channel index (input side)
    pub src_channel: u8,
    /// Destination channel index (plugin side)
    pub dst_channel: u8,
    /// Gain coefficient (0.0 = disconnected, 1.0 = unity, negative = phase invert)
    pub gain: f64,
}

impl PinMapping {
    pub fn new(src: u8, dst: u8, gain: f64) -> Self {
        Self {
            src_channel: src,
            dst_channel: dst,
            gain,
        }
    }

    /// Unity gain mapping
    pub fn unity(src: u8, dst: u8) -> Self {
        Self::new(src, dst, 1.0)
    }
}

// =============================================================================
// PIN CONNECTOR
// =============================================================================

/// Per-plugin channel routing matrix
///
/// Sits between host audio channels and plugin I/O, allowing arbitrary
/// channel routing with gain control. Two separate matrices:
/// - `input_map`: host channels → plugin input channels
/// - `output_map`: plugin output channels → host channels
///
/// # Audio Thread Safety
/// All buffers are pre-allocated. Processing uses only stack operations.
pub struct PinConnector {
    /// Routing mode
    mode: PinRoutingMode,

    /// Number of host channels (typically 2 for stereo)
    host_channels: u8,

    /// Number of plugin channels (plugin's native I/O count)
    plugin_channels: u8,

    /// Input routing: host → plugin (sparse matrix as Vec for flexibility)
    input_map: Vec<PinMapping>,

    /// Output routing: plugin → host (sparse matrix)
    output_map: Vec<PinMapping>,

    /// Whether output mapping should sum (true) or replace (false)
    output_sum: bool,

    /// Connector enabled
    enabled: AtomicBool,

    // ═══ Pre-allocated Processing Buffers ═══
    // These avoid heap allocation on the audio thread.
    // plugin_in/out buffers: flat [MAX_PIN_CHANNELS * MAX_BUFFER_SIZE]
    // Each channel occupies a contiguous block of MAX_BUFFER_SIZE samples.

    /// Plugin input buffers (pre-allocated, MAX_PIN_CHANNELS channels)
    plugin_in: Vec<Sample>,

    /// Plugin output buffers (pre-allocated, MAX_PIN_CHANNELS channels)
    plugin_out: Vec<Sample>,
}

impl std::fmt::Debug for PinConnector {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("PinConnector")
            .field("mode", &self.mode)
            .field("host_channels", &self.host_channels)
            .field("plugin_channels", &self.plugin_channels)
            .field("input_mappings", &self.input_map.len())
            .field("output_mappings", &self.output_map.len())
            .field("enabled", &self.enabled.load(Ordering::Relaxed))
            .finish()
    }
}

impl PinConnector {
    /// Create a new pin connector with the given channel counts
    pub fn new(host_channels: u8, plugin_channels: u8) -> Self {
        let host_ch = (host_channels as usize).min(MAX_PIN_CHANNELS);
        let plugin_ch = (plugin_channels as usize).min(MAX_PIN_CHANNELS);

        // Default: 1:1 mapping for overlapping channels
        let min_ch = host_ch.min(plugin_ch);
        let mut input_map = Vec::with_capacity(min_ch);
        let mut output_map = Vec::with_capacity(min_ch);

        for i in 0..min_ch {
            input_map.push(PinMapping::unity(i as u8, i as u8));
            output_map.push(PinMapping::unity(i as u8, i as u8));
        }

        // Pre-allocate flat buffers for all plugin channels
        let buf_size = plugin_ch * MAX_BUFFER_SIZE;

        Self {
            mode: PinRoutingMode::Normal,
            host_channels: host_ch as u8,
            plugin_channels: plugin_ch as u8,
            input_map,
            output_map,
            output_sum: true,
            enabled: AtomicBool::new(true),
            plugin_in: vec![0.0; buf_size],
            plugin_out: vec![0.0; buf_size],
        }
    }

    /// Create stereo pin connector (most common case)
    pub fn stereo() -> Self {
        Self::new(2, 2)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONFIGURATION (UI thread)
    // ═══════════════════════════════════════════════════════════════════════

    /// Set routing mode and rebuild default mappings
    pub fn set_mode(&mut self, mode: PinRoutingMode) {
        self.mode = mode;
        self.rebuild_default_mappings();
    }

    /// Get current routing mode
    pub fn mode(&self) -> PinRoutingMode {
        self.mode
    }

    /// Set number of host channels (reconfigures mappings)
    pub fn set_host_channels(&mut self, channels: u8) {
        self.host_channels = (channels as usize).min(MAX_PIN_CHANNELS) as u8;
        self.rebuild_default_mappings();
    }

    /// Set number of plugin channels (reconfigures mappings + buffers)
    pub fn set_plugin_channels(&mut self, channels: u8) {
        let ch = (channels as usize).min(MAX_PIN_CHANNELS);
        self.plugin_channels = ch as u8;

        // Resize buffers if needed
        let needed = ch * MAX_BUFFER_SIZE;
        if self.plugin_in.len() < needed {
            self.plugin_in.resize(needed, 0.0);
            self.plugin_out.resize(needed, 0.0);
        }

        self.rebuild_default_mappings();
    }

    /// Get host channel count
    pub fn host_channels(&self) -> u8 {
        self.host_channels
    }

    /// Get plugin channel count
    pub fn plugin_channels(&self) -> u8 {
        self.plugin_channels
    }

    /// Enable/disable the pin connector (bypasses all routing when disabled)
    pub fn set_enabled(&self, enabled: bool) {
        self.enabled.store(enabled, Ordering::Relaxed);
    }

    /// Check if enabled
    pub fn is_enabled(&self) -> bool {
        self.enabled.load(Ordering::Relaxed)
    }

    /// Clear all input mappings
    pub fn clear_input_map(&mut self) {
        self.input_map.clear();
    }

    /// Clear all output mappings
    pub fn clear_output_map(&mut self) {
        self.output_map.clear();
    }

    /// Add input mapping (host channel → plugin channel)
    pub fn add_input_mapping(&mut self, src: u8, dst: u8, gain: f64) {
        if (src as usize) < MAX_PIN_CHANNELS && (dst as usize) < MAX_PIN_CHANNELS {
            self.input_map.push(PinMapping::new(src, dst, gain));
        }
    }

    /// Add output mapping (plugin channel → host channel)
    pub fn add_output_mapping(&mut self, src: u8, dst: u8, gain: f64) {
        if (src as usize) < MAX_PIN_CHANNELS && (dst as usize) < MAX_PIN_CHANNELS {
            self.output_map.push(PinMapping::new(src, dst, gain));
        }
    }

    /// Remove input mapping at index
    pub fn remove_input_mapping(&mut self, index: usize) {
        if index < self.input_map.len() {
            self.input_map.remove(index);
        }
    }

    /// Remove output mapping at index
    pub fn remove_output_mapping(&mut self, index: usize) {
        if index < self.output_map.len() {
            self.output_map.remove(index);
        }
    }

    /// Set gain on existing input mapping
    pub fn set_input_gain(&mut self, src: u8, dst: u8, gain: f64) {
        for m in &mut self.input_map {
            if m.src_channel == src && m.dst_channel == dst {
                m.gain = gain;
                return;
            }
        }
        // If not found, add it
        self.add_input_mapping(src, dst, gain);
    }

    /// Set gain on existing output mapping
    pub fn set_output_gain(&mut self, src: u8, dst: u8, gain: f64) {
        for m in &mut self.output_map {
            if m.src_channel == src && m.dst_channel == dst {
                m.gain = gain;
                return;
            }
        }
        self.add_output_mapping(src, dst, gain);
    }

    /// Get input gain for a specific src→dst pair (0.0 if not mapped)
    pub fn get_input_gain(&self, src: u8, dst: u8) -> f64 {
        self.input_map
            .iter()
            .find(|m| m.src_channel == src && m.dst_channel == dst)
            .map(|m| m.gain)
            .unwrap_or(0.0)
    }

    /// Get output gain for a specific src→dst pair
    pub fn get_output_gain(&self, src: u8, dst: u8) -> f64 {
        self.output_map
            .iter()
            .find(|m| m.src_channel == src && m.dst_channel == dst)
            .map(|m| m.gain)
            .unwrap_or(0.0)
    }

    /// Get all input mappings
    pub fn input_mappings(&self) -> &[PinMapping] {
        &self.input_map
    }

    /// Get all output mappings
    pub fn output_mappings(&self) -> &[PinMapping] {
        &self.output_map
    }

    /// Set output sum mode (true = sum into host channels, false = replace)
    pub fn set_output_sum(&mut self, sum: bool) {
        self.output_sum = sum;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // DEFAULT MAPPING GENERATORS
    // ═══════════════════════════════════════════════════════════════════════

    /// Rebuild default mappings based on current mode and channel counts
    fn rebuild_default_mappings(&mut self) {
        self.input_map.clear();
        self.output_map.clear();

        match self.mode {
            PinRoutingMode::Normal => self.build_normal_mapping(),
            PinRoutingMode::MultiMono => self.build_multi_mono_mapping(),
            PinRoutingMode::MidSide => self.build_mid_side_mapping(),
            PinRoutingMode::SurroundPerChannel => self.build_surround_per_channel_mapping(),
            PinRoutingMode::CustomMatrix => {
                // Custom: start with 1:1 diagonal
                self.build_normal_mapping();
            }
        }
    }

    /// Normal 1:1 mapping (stereo or multi-channel pass-through)
    fn build_normal_mapping(&mut self) {
        let min_ch = (self.host_channels as usize).min(self.plugin_channels as usize);
        for i in 0..min_ch {
            self.input_map.push(PinMapping::unity(i as u8, i as u8));
            self.output_map.push(PinMapping::unity(i as u8, i as u8));
        }
    }

    /// Multi-mono: each host channel → its own plugin mono instance
    /// For a stereo plugin on 6-channel audio:
    ///   Host ch 0 → Plugin ch 0, Host ch 1 → Plugin ch 1, etc.
    fn build_multi_mono_mapping(&mut self) {
        let min_ch = (self.host_channels as usize).min(self.plugin_channels as usize);
        for i in 0..min_ch {
            self.input_map.push(PinMapping::unity(i as u8, i as u8));
            self.output_map.push(PinMapping::unity(i as u8, i as u8));
        }
    }

    /// Mid/Side encoding: L/R → M/S before plugin, M/S → L/R after
    /// Input:  L → M (gain 0.5), R → M (gain 0.5), L → S (gain 0.5), R → S (gain -0.5)
    /// Output: M → L (gain 1.0), S → L (gain 1.0), M → R (gain 1.0), S → R (gain -1.0)
    fn build_mid_side_mapping(&mut self) {
        // Requires at least 2 channels on both sides
        if self.host_channels < 2 || self.plugin_channels < 2 {
            self.build_normal_mapping();
            return;
        }

        // Input: L/R → M/S encoding matrix
        // M = (L + R) * 0.5
        // S = (L - R) * 0.5
        self.input_map.push(PinMapping::new(0, 0, 0.5));  // L → M (0.5)
        self.input_map.push(PinMapping::new(1, 0, 0.5));  // R → M (0.5)
        self.input_map.push(PinMapping::new(0, 1, 0.5));  // L → S (0.5)
        self.input_map.push(PinMapping::new(1, 1, -0.5)); // R → S (-0.5)

        // Output: M/S → L/R decoding matrix
        // L = M + S
        // R = M - S
        self.output_map.push(PinMapping::new(0, 0, 1.0));  // M → L (1.0)
        self.output_map.push(PinMapping::new(1, 0, 1.0));  // S → L (1.0)
        self.output_map.push(PinMapping::new(0, 1, 1.0));  // M → R (1.0)
        self.output_map.push(PinMapping::new(1, 1, -1.0)); // S → R (-1.0)
    }

    /// Surround per-channel: process each surround channel independently
    /// through the plugin as a mono stream (one channel at a time)
    fn build_surround_per_channel_mapping(&mut self) {
        // Each host channel maps to its own plugin channel 1:1
        // The key difference is that process_multichannel will process
        // each channel independently through the processor
        let min_ch = (self.host_channels as usize).min(self.plugin_channels as usize);
        for i in 0..min_ch {
            self.input_map.push(PinMapping::unity(i as u8, i as u8));
            self.output_map.push(PinMapping::unity(i as u8, i as u8));
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // AUDIO THREAD PROCESSING (zero-alloc)
    // ═══════════════════════════════════════════════════════════════════════

    /// Apply input routing: copy host channels → plugin input buffers
    ///
    /// # Audio Thread Safety
    /// Uses only pre-allocated buffers. No heap allocation.
    ///
    /// # Parameters
    /// - `host_left`, `host_right`: stereo host buffers
    /// - `num_frames`: number of samples to process
    ///
    /// After calling this, plugin_in buffers are filled according to input_map.
    #[inline]
    pub fn route_input_stereo(&mut self, host_left: &[Sample], host_right: &[Sample], num_frames: usize) {
        let frames = num_frames.min(MAX_BUFFER_SIZE);
        let plugin_ch = self.plugin_channels as usize;

        // Clear plugin input buffers
        for ch in 0..plugin_ch {
            let offset = ch * MAX_BUFFER_SIZE;
            for i in 0..frames {
                self.plugin_in[offset + i] = 0.0;
            }
        }

        // Apply input routing matrix
        for mapping in &self.input_map {
            let src_ch = mapping.src_channel as usize;
            let dst_ch = mapping.dst_channel as usize;
            let gain = mapping.gain;

            if dst_ch >= plugin_ch {
                continue;
            }

            let dst_offset = dst_ch * MAX_BUFFER_SIZE;

            // Select source buffer (0 = left, 1 = right, others = silence for stereo host)
            let src_buf: &[Sample] = match src_ch {
                0 => host_left,
                1 => host_right,
                _ => continue, // Stereo host only has 2 channels
            };

            // Accumulate with gain
            let src_len = src_buf.len().min(frames);
            for i in 0..src_len {
                self.plugin_in[dst_offset + i] += src_buf[i] * gain;
            }
        }
    }

    /// Apply output routing: copy plugin output buffers → host channels
    ///
    /// # Audio Thread Safety
    /// Uses only pre-allocated buffers. No heap allocation.
    #[inline]
    pub fn route_output_stereo(
        &self,
        host_left: &mut [Sample],
        host_right: &mut [Sample],
        num_frames: usize,
    ) {
        let frames = num_frames.min(MAX_BUFFER_SIZE);

        // Clear host output if not summing
        if !self.output_sum {
            for i in 0..frames.min(host_left.len()) {
                host_left[i] = 0.0;
            }
            for i in 0..frames.min(host_right.len()) {
                host_right[i] = 0.0;
            }
        }

        // Apply output routing matrix
        for mapping in &self.output_map {
            let src_ch = mapping.src_channel as usize;
            let dst_ch = mapping.dst_channel as usize;
            let gain = mapping.gain;
            let plugin_ch = self.plugin_channels as usize;

            if src_ch >= plugin_ch {
                continue;
            }

            let src_offset = src_ch * MAX_BUFFER_SIZE;

            // Select destination buffer (0 = left, 1 = right)
            match dst_ch {
                0 => {
                    let len = frames.min(host_left.len());
                    if self.output_sum {
                        for i in 0..len {
                            host_left[i] += self.plugin_out[src_offset + i] * gain;
                        }
                    } else {
                        for i in 0..len {
                            host_left[i] = self.plugin_out[src_offset + i] * gain;
                        }
                    }
                }
                1 => {
                    let len = frames.min(host_right.len());
                    if self.output_sum {
                        for i in 0..len {
                            host_right[i] += self.plugin_out[src_offset + i] * gain;
                        }
                    } else {
                        for i in 0..len {
                            host_right[i] = self.plugin_out[src_offset + i] * gain;
                        }
                    }
                }
                _ => {} // Stereo host only has 2 channels
            }
        }
    }

    /// Get reference to plugin input channel buffer
    ///
    /// Returns a slice of `num_frames` samples for the given channel.
    /// Channel is clamped to valid range (0..plugin_channels-1).
    #[inline]
    pub fn plugin_input_channel(&self, channel: usize, num_frames: usize) -> &[Sample] {
        let frames = num_frames.min(MAX_BUFFER_SIZE);
        let ch = channel.min((self.plugin_channels as usize).saturating_sub(1));
        let offset = ch * MAX_BUFFER_SIZE;
        &self.plugin_in[offset..offset + frames]
    }

    /// Get mutable reference to plugin output channel buffer (for processor to write to)
    /// Channel is clamped to valid range (0..plugin_channels-1).
    #[inline]
    pub fn plugin_output_channel_mut(&mut self, channel: usize, num_frames: usize) -> &mut [Sample] {
        let frames = num_frames.min(MAX_BUFFER_SIZE);
        let ch = channel.min((self.plugin_channels as usize).saturating_sub(1));
        let offset = ch * MAX_BUFFER_SIZE;
        &mut self.plugin_out[offset..offset + frames]
    }

    /// Get immutable reference to plugin output channel buffer (for reading multi-channel output).
    /// Returns None if channel is out of range.
    #[inline]
    pub fn plugin_output_channel(&self, channel: usize, num_frames: usize) -> Option<&[Sample]> {
        if channel >= self.plugin_channels as usize {
            return None;
        }
        let frames = num_frames.min(MAX_BUFFER_SIZE);
        let offset = channel * MAX_BUFFER_SIZE;
        Some(&self.plugin_out[offset..offset + frames])
    }

    /// Get stereo pair from plugin input buffers (channels 0 and 1)
    /// Returns (&left, &right) slices.
    /// Requires plugin_channels >= 2. Returns (ch0, ch0) if mono plugin.
    #[inline]
    pub fn plugin_input_stereo(&self, num_frames: usize) -> (&[Sample], &[Sample]) {
        let frames = num_frames.min(MAX_BUFFER_SIZE);
        let left = &self.plugin_in[0..frames];
        if self.plugin_channels >= 2 {
            let right_offset = MAX_BUFFER_SIZE;
            let right = &self.plugin_in[right_offset..right_offset + frames];
            (left, right)
        } else {
            // Mono plugin: return same channel for both
            (left, left)
        }
    }

    /// Get mutable stereo pair from plugin input buffers for in-place processing.
    /// Returns two non-overlapping mutable slices using split_at_mut.
    /// Requires plugin_channels >= 2. Panics if mono plugin (use plugin_input_channel instead).
    #[inline]
    pub fn plugin_input_stereo_mut(&mut self, num_frames: usize) -> (&mut [Sample], &mut [Sample]) {
        debug_assert!(self.plugin_channels >= 2, "plugin_input_stereo_mut requires >= 2 channels");
        let frames = num_frames.min(MAX_BUFFER_SIZE);
        let (first_half, second_half) = self.plugin_in.split_at_mut(MAX_BUFFER_SIZE);
        (&mut first_half[..frames], &mut second_half[..frames])
    }

    /// Copy plugin input to plugin output (for in-place processors that modify the input buffer)
    #[inline]
    pub fn copy_input_to_output(&mut self, num_frames: usize) {
        let frames = num_frames.min(MAX_BUFFER_SIZE);
        let plugin_ch = self.plugin_channels as usize;
        for ch in 0..plugin_ch {
            let offset = ch * MAX_BUFFER_SIZE;
            // Use ptr::copy_nonoverlapping for guaranteed safety (non-overlapping regions)
            unsafe {
                std::ptr::copy_nonoverlapping(
                    self.plugin_in.as_ptr().add(offset),
                    self.plugin_out.as_mut_ptr().add(offset),
                    frames,
                );
            }
        }
    }

    /// Clear plugin output buffers
    #[inline]
    pub fn clear_output(&mut self, num_frames: usize) {
        let frames = num_frames.min(MAX_BUFFER_SIZE);
        let plugin_ch = self.plugin_channels as usize;
        for ch in 0..plugin_ch {
            let offset = ch * MAX_BUFFER_SIZE;
            for i in 0..frames {
                self.plugin_out[offset + i] = 0.0;
            }
        }
    }

    /// Full stereo processing pipeline:
    /// 1. Route host stereo → plugin input buffers (via input matrix)
    /// 2. Copy routed input to output buffers (processor will modify in-place)
    /// 3. Return mutable stereo pair for processor to work on
    ///
    /// After processor is done, call route_output_stereo() to route back.
    #[inline]
    pub fn prepare_for_processing(
        &mut self,
        host_left: &[Sample],
        host_right: &[Sample],
        num_frames: usize,
    ) {
        self.route_input_stereo(host_left, host_right, num_frames);
        self.copy_input_to_output(num_frames);
    }

    /// Get the plugin output as a stereo pair for the processor to modify in-place.
    /// Call this after prepare_for_processing().
    /// Requires plugin_channels >= 2.
    #[inline]
    pub fn plugin_output_stereo_mut(&mut self, num_frames: usize) -> (&mut [Sample], &mut [Sample]) {
        debug_assert!(self.plugin_channels >= 2, "plugin_output_stereo_mut requires >= 2 channels");
        let frames = num_frames.min(MAX_BUFFER_SIZE);
        let (first_half, second_half) = self.plugin_out.split_at_mut(MAX_BUFFER_SIZE);
        (&mut first_half[..frames], &mut second_half[..frames])
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MULTI-CHANNEL PROCESSING (for plugins with >2 channels)
    // ═══════════════════════════════════════════════════════════════════════

    /// Route multi-channel host audio → plugin input buffers
    ///
    /// `host_buffers` is a slice of channel buffers (each &[Sample]).
    #[inline]
    pub fn route_input_multichannel(&mut self, host_buffers: &[&[Sample]], num_frames: usize) {
        let frames = num_frames.min(MAX_BUFFER_SIZE);
        let plugin_ch = self.plugin_channels as usize;

        // Clear plugin input
        for ch in 0..plugin_ch {
            let offset = ch * MAX_BUFFER_SIZE;
            for i in 0..frames {
                self.plugin_in[offset + i] = 0.0;
            }
        }

        // Apply input routing
        for mapping in &self.input_map {
            let src_ch = mapping.src_channel as usize;
            let dst_ch = mapping.dst_channel as usize;
            let gain = mapping.gain;

            if src_ch >= host_buffers.len() || dst_ch >= plugin_ch {
                continue;
            }

            let src_buf = host_buffers[src_ch];
            let dst_offset = dst_ch * MAX_BUFFER_SIZE;
            let len = frames.min(src_buf.len());

            for i in 0..len {
                self.plugin_in[dst_offset + i] += src_buf[i] * gain;
            }
        }
    }

    /// Route plugin output → multi-channel host buffers
    #[inline]
    pub fn route_output_multichannel(
        &self,
        host_buffers: &mut [&mut [Sample]],
        num_frames: usize,
    ) {
        let frames = num_frames.min(MAX_BUFFER_SIZE);
        let plugin_ch = self.plugin_channels as usize;

        if !self.output_sum {
            for buf in host_buffers.iter_mut() {
                for i in 0..frames.min(buf.len()) {
                    buf[i] = 0.0;
                }
            }
        }

        for mapping in &self.output_map {
            let src_ch = mapping.src_channel as usize;
            let dst_ch = mapping.dst_channel as usize;
            let gain = mapping.gain;

            if src_ch >= plugin_ch || dst_ch >= host_buffers.len() {
                continue;
            }

            let src_offset = src_ch * MAX_BUFFER_SIZE;
            let dst_buf = &mut host_buffers[dst_ch];
            let len = frames.min(dst_buf.len());

            if self.output_sum {
                for i in 0..len {
                    dst_buf[i] += self.plugin_out[src_offset + i] * gain;
                }
            } else {
                for i in 0..len {
                    dst_buf[i] = self.plugin_out[src_offset + i] * gain;
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SERIALIZATION SUPPORT
    // ═══════════════════════════════════════════════════════════════════════

    /// Export routing configuration as JSON-friendly data
    pub fn to_config(&self) -> PinConnectorConfig {
        PinConnectorConfig {
            mode: self.mode,
            host_channels: self.host_channels,
            plugin_channels: self.plugin_channels,
            input_map: self.input_map.clone(),
            output_map: self.output_map.clone(),
            output_sum: self.output_sum,
        }
    }

    /// Import routing configuration
    pub fn from_config(config: &PinConnectorConfig) -> Self {
        let mut pc = Self::new(config.host_channels, config.plugin_channels);
        pc.mode = config.mode;
        pc.input_map = config.input_map.clone();
        pc.output_map = config.output_map.clone();
        pc.output_sum = config.output_sum;
        pc
    }
}

/// Serializable pin connector configuration
#[derive(Debug, Clone)]
pub struct PinConnectorConfig {
    pub mode: PinRoutingMode,
    pub host_channels: u8,
    pub plugin_channels: u8,
    pub input_map: Vec<PinMapping>,
    pub output_map: Vec<PinMapping>,
    pub output_sum: bool,
}

// =============================================================================
// TESTS
// =============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_stereo_passthrough() {
        let mut pc = PinConnector::stereo();
        let left = vec![1.0; 64];
        let right = vec![0.5; 64];

        pc.prepare_for_processing(&left, &right, 64);

        // Plugin output should have the routed input
        let (out_l, out_r) = pc.plugin_output_stereo_mut(64);
        assert!((out_l[0] - 1.0).abs() < 1e-10);
        assert!((out_r[0] - 0.5).abs() < 1e-10);

        // Route output back
        let mut host_l = vec![0.0; 64];
        let mut host_r = vec![0.0; 64];
        pc.route_output_stereo(&mut host_l, &mut host_r, 64);
        assert!((host_l[0] - 1.0).abs() < 1e-10);
        assert!((host_r[0] - 0.5).abs() < 1e-10);
    }

    #[test]
    fn test_mid_side_encoding_decoding() {
        let mut pc = PinConnector::new(2, 2);
        pc.set_mode(PinRoutingMode::MidSide);

        // L=1.0, R=0.0 → M=0.5, S=0.5
        let left = vec![1.0; 64];
        let right = vec![0.0; 64];

        pc.route_input_stereo(&left, &right, 64);

        // Check mid: (1.0 * 0.5) + (0.0 * 0.5) = 0.5
        let mid = pc.plugin_input_channel(0, 64);
        assert!((mid[0] - 0.5).abs() < 1e-10, "Mid should be 0.5, got {}", mid[0]);

        // Check side: (1.0 * 0.5) + (0.0 * -0.5) = 0.5
        let side = pc.plugin_input_channel(1, 64);
        assert!((side[0] - 0.5).abs() < 1e-10, "Side should be 0.5, got {}", side[0]);

        // Now route back through M/S decoding (identity process - copy input to output)
        pc.copy_input_to_output(64);

        let mut out_l = vec![0.0; 64];
        let mut out_r = vec![0.0; 64];
        pc.route_output_stereo(&mut out_l, &mut out_r, 64);

        // L = M + S = 0.5 + 0.5 = 1.0
        // R = M - S = 0.5 - 0.5 = 0.0
        assert!((out_l[0] - 1.0).abs() < 1e-10, "Decoded L should be 1.0, got {}", out_l[0]);
        assert!((out_r[0] - 0.0).abs() < 1e-10, "Decoded R should be 0.0, got {}", out_r[0]);
    }

    #[test]
    fn test_mid_side_roundtrip_both_channels() {
        let mut pc = PinConnector::new(2, 2);
        pc.set_mode(PinRoutingMode::MidSide);

        // L=0.8, R=0.3
        let left = vec![0.8; 64];
        let right = vec![0.3; 64];

        pc.prepare_for_processing(&left, &right, 64);

        // Don't modify plugin output — just route back (identity)
        let mut out_l = vec![0.0; 64];
        let mut out_r = vec![0.0; 64];
        pc.route_output_stereo(&mut out_l, &mut out_r, 64);

        // Should perfectly reconstruct original
        assert!((out_l[0] - 0.8).abs() < 1e-10, "L roundtrip: expected 0.8, got {}", out_l[0]);
        assert!((out_r[0] - 0.3).abs() < 1e-10, "R roundtrip: expected 0.3, got {}", out_r[0]);
    }

    #[test]
    fn test_custom_matrix_routing() {
        let mut pc = PinConnector::new(2, 4);
        pc.set_mode(PinRoutingMode::CustomMatrix);

        // Custom: route L to all 4 plugin channels with different gains
        pc.clear_input_map();
        pc.add_input_mapping(0, 0, 1.0);
        pc.add_input_mapping(0, 1, 0.5);
        pc.add_input_mapping(0, 2, 0.25);
        pc.add_input_mapping(1, 3, 1.0);

        let left = vec![1.0; 32];
        let right = vec![0.8; 32];

        pc.route_input_stereo(&left, &right, 32);

        assert!((pc.plugin_input_channel(0, 32)[0] - 1.0).abs() < 1e-10);
        assert!((pc.plugin_input_channel(1, 32)[0] - 0.5).abs() < 1e-10);
        assert!((pc.plugin_input_channel(2, 32)[0] - 0.25).abs() < 1e-10);
        assert!((pc.plugin_input_channel(3, 32)[0] - 0.8).abs() < 1e-10);
    }

    #[test]
    fn test_phase_invert_via_negative_gain() {
        let mut pc = PinConnector::stereo();
        pc.clear_input_map();
        pc.add_input_mapping(0, 0, 1.0);
        pc.add_input_mapping(1, 1, -1.0); // Phase invert right channel

        let left = vec![0.5; 32];
        let right = vec![0.5; 32];

        pc.route_input_stereo(&left, &right, 32);

        let in_l = pc.plugin_input_channel(0, 32);
        let in_r = pc.plugin_input_channel(1, 32);

        assert!((in_l[0] - 0.5).abs() < 1e-10);
        assert!((in_r[0] - (-0.5)).abs() < 1e-10, "Phase inverted R: expected -0.5, got {}", in_r[0]);
    }

    #[test]
    fn test_multi_mono_mapping() {
        let mut pc = PinConnector::new(4, 4);
        pc.set_mode(PinRoutingMode::MultiMono);

        // Should have 4 1:1 mappings
        assert_eq!(pc.input_mappings().len(), 4);
        assert_eq!(pc.output_mappings().len(), 4);

        for i in 0..4 {
            assert_eq!(pc.get_input_gain(i as u8, i as u8), 1.0);
        }
    }

    #[test]
    fn test_multichannel_routing() {
        let mut pc = PinConnector::new(4, 4);

        let ch0 = vec![1.0; 32];
        let ch1 = vec![2.0; 32];
        let ch2 = vec![3.0; 32];
        let ch3 = vec![4.0; 32];
        let host_bufs: Vec<&[Sample]> = vec![&ch0, &ch1, &ch2, &ch3];

        pc.route_input_multichannel(&host_bufs, 32);
        pc.copy_input_to_output(32);

        let mut out0 = vec![0.0; 32];
        let mut out1 = vec![0.0; 32];
        let mut out2 = vec![0.0; 32];
        let mut out3 = vec![0.0; 32];
        let mut host_out: Vec<&mut [Sample]> = vec![&mut out0, &mut out1, &mut out2, &mut out3];

        pc.route_output_multichannel(&mut host_out, 32);

        assert!((out0[0] - 1.0).abs() < 1e-10);
        assert!((out1[0] - 2.0).abs() < 1e-10);
        assert!((out2[0] - 3.0).abs() < 1e-10);
        assert!((out3[0] - 4.0).abs() < 1e-10);
    }

    #[test]
    fn test_config_roundtrip() {
        let mut pc = PinConnector::new(2, 4);
        pc.set_mode(PinRoutingMode::MidSide);
        pc.set_output_sum(false);

        let config = pc.to_config();
        let pc2 = PinConnector::from_config(&config);

        assert_eq!(pc2.mode(), PinRoutingMode::MidSide);
        assert_eq!(pc2.host_channels(), 2);
        assert_eq!(pc2.plugin_channels(), 4);
        assert_eq!(pc2.input_mappings().len(), pc.input_mappings().len());
    }

    #[test]
    fn test_set_gain_updates_existing() {
        let mut pc = PinConnector::stereo();

        // Modify existing gain
        pc.set_input_gain(0, 0, 0.5);
        assert!((pc.get_input_gain(0, 0) - 0.5).abs() < 1e-10);

        // Non-existing creates new
        pc.set_input_gain(0, 1, 0.3);
        assert!((pc.get_input_gain(0, 1) - 0.3).abs() < 1e-10);
    }

    #[test]
    fn test_disabled_connector() {
        let pc = PinConnector::stereo();
        assert!(pc.is_enabled());

        pc.set_enabled(false);
        assert!(!pc.is_enabled());
    }

    #[test]
    fn test_remove_mapping() {
        let mut pc = PinConnector::stereo();
        assert_eq!(pc.input_mappings().len(), 2);

        pc.remove_input_mapping(0);
        assert_eq!(pc.input_mappings().len(), 1);
    }
}
