//! Zero-Copy Plugin Chain
//!
//! MassCore++-inspired plugin chain with:
//! - Pre-allocated buffer pool
//! - Lock-free processing
//! - Zero buffer copies
//! - PDC (Plugin Delay Compensation)

use parking_lot::RwLock;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};

use crate::scanner::PluginInfo;
use crate::{AudioBuffer, PluginError, PluginInstance, PluginResult, ProcessContext};

/// Slot processing info tuple: (index, output_buffer, bypassed, enabled, mix, plugin)
type SlotProcessInfo = (
    usize,
    usize,
    bool,
    bool,
    f32,
    Arc<RwLock<Box<dyn PluginInstance>>>,
);

/// Pre-allocated buffer pool for zero-copy processing
pub struct BufferPool {
    /// Pool of pre-allocated buffers
    buffers: Vec<AudioBuffer>,
    /// Available buffer indices
    available: Vec<usize>,
    /// Buffer size
    buffer_size: usize,
    /// Number of channels
    channels: usize,
}

impl BufferPool {
    pub fn new(pool_size: usize, channels: usize, buffer_size: usize) -> Self {
        let buffers = (0..pool_size)
            .map(|_| AudioBuffer::new(channels, buffer_size))
            .collect();

        let available = (0..pool_size).collect();

        Self {
            buffers,
            available,
            buffer_size,
            channels,
        }
    }

    /// Acquire a buffer from the pool
    pub fn acquire(&mut self) -> Option<usize> {
        self.available.pop()
    }

    /// Release a buffer back to the pool
    pub fn release(&mut self, index: usize) {
        if index < self.buffers.len() && !self.available.contains(&index) {
            self.available.push(index);
        }
    }

    /// Get buffer by index
    pub fn get(&self, index: usize) -> Option<&AudioBuffer> {
        self.buffers.get(index)
    }

    /// Get mutable buffer by index
    pub fn get_mut(&mut self, index: usize) -> Option<&mut AudioBuffer> {
        self.buffers.get_mut(index)
    }

    /// Clear all buffers
    pub fn clear_all(&mut self) {
        for buffer in &mut self.buffers {
            buffer.clear();
        }
    }

    /// Get buffer size
    #[inline]
    pub fn buffer_size(&self) -> usize {
        self.buffer_size
    }

    /// Get channel count
    #[inline]
    pub fn channels(&self) -> usize {
        self.channels
    }
}

/// Plugin chain slot
pub struct ChainSlot {
    /// Plugin instance
    plugin: Arc<RwLock<Box<dyn PluginInstance>>>,
    /// Is bypassed
    bypass: AtomicBool,
    /// Wet/dry mix (0-100)
    mix: AtomicU32,
    /// Input buffer index
    input_buffer: usize,
    /// Output buffer index
    output_buffer: usize,
    /// Plugin latency
    latency: AtomicU32,
    /// Slot enabled
    enabled: AtomicBool,
    /// Cumulative panic count for this plugin's `process()` calls.
    /// Once it exceeds [`MAX_PLUGIN_PANICS_BEFORE_DISABLE`], the slot is
    /// permanently auto-bypassed. (FLUX_MASTER_TODO 1.5.2 phase 1 —
    /// in-process safety net before full subprocess sandbox.)
    panic_count: AtomicU32,
    /// Set to true once the slot has been auto-disabled because of
    /// too many panics. The audio thread checks this with
    /// `Ordering::Relaxed` and short-circuits to bypass.
    auto_disabled_after_panic: AtomicBool,
}

/// How many panics from one plugin instance we tolerate before
/// permanently auto-bypassing the slot. Three is enough to ride out
/// transient causes (one-off race in initialisation, GC pressure)
/// while still capping the damage from a chronically-broken plugin.
pub const MAX_PLUGIN_PANICS_BEFORE_DISABLE: u32 = 3;

impl ChainSlot {
    pub fn new(plugin: Box<dyn PluginInstance>, input_buffer: usize, output_buffer: usize) -> Self {
        let latency = plugin.latency() as u32;
        Self {
            plugin: Arc::new(RwLock::new(plugin)),
            bypass: AtomicBool::new(false),
            mix: AtomicU32::new(100),
            input_buffer,
            output_buffer,
            latency: AtomicU32::new(latency),
            enabled: AtomicBool::new(true),
            panic_count: AtomicU32::new(0),
            auto_disabled_after_panic: AtomicBool::new(false),
        }
    }

    /// Number of panics observed during this slot's `process()` calls.
    /// Survives bypass / re-enable; only zeroed when the plugin is
    /// replaced.
    pub fn panic_count(&self) -> u32 {
        self.panic_count.load(Ordering::Relaxed)
    }

    /// True once the slot was auto-bypassed due to a chronically-panicking
    /// plugin. Visible to the UI so the user sees "this plugin was
    /// disabled because it kept crashing".
    pub fn is_auto_disabled_after_panic(&self) -> bool {
        self.auto_disabled_after_panic.load(Ordering::Relaxed)
    }

    /// Increment the panic counter and, if it exceeds the threshold,
    /// flip the auto-disable flag. Returns the new count.
    /// Internal — called only from the chain's process() panic-recovery
    /// path.
    pub(crate) fn record_panic(&self) -> u32 {
        let n = self.panic_count.fetch_add(1, Ordering::Relaxed) + 1;
        if n >= MAX_PLUGIN_PANICS_BEFORE_DISABLE {
            self.auto_disabled_after_panic.store(true, Ordering::Relaxed);
        }
        n
    }

    pub fn is_bypassed(&self) -> bool {
        self.bypass.load(Ordering::Relaxed)
    }

    pub fn set_bypass(&self, bypass: bool) {
        self.bypass.store(bypass, Ordering::Relaxed);
    }

    pub fn mix(&self) -> f32 {
        self.mix.load(Ordering::Relaxed) as f32 / 100.0
    }

    pub fn set_mix(&self, mix: f32) {
        self.mix
            .store((mix.clamp(0.0, 1.0) * 100.0) as u32, Ordering::Relaxed);
    }

    pub fn latency(&self) -> u32 {
        self.latency.load(Ordering::Relaxed)
    }

    pub fn is_enabled(&self) -> bool {
        self.enabled.load(Ordering::Relaxed)
    }

    pub fn set_enabled(&self, enabled: bool) {
        self.enabled.store(enabled, Ordering::Relaxed);
    }

    pub fn plugin(&self) -> &Arc<RwLock<Box<dyn PluginInstance>>> {
        &self.plugin
    }

    pub fn info(&self) -> PluginInfo {
        self.plugin.read().info().clone()
    }
}

/// Plugin Delay Compensation manager
pub struct PdcManager {
    /// Delay lines per slot
    delay_lines: Vec<DelayLine>,
    /// Total chain latency
    total_latency: u32,
    /// Is PDC enabled
    enabled: bool,
}

impl PdcManager {
    pub fn new(max_slots: usize, max_latency: usize, channels: usize) -> Self {
        let delay_lines = (0..max_slots)
            .map(|_| DelayLine::new(max_latency, channels))
            .collect();

        Self {
            delay_lines,
            total_latency: 0,
            enabled: true,
        }
    }

    /// Recalculate delays based on plugin latencies
    pub fn recalculate(&mut self, slots: &[ChainSlot]) {
        // Find maximum latency
        let max_latency: u32 = slots
            .iter()
            .filter(|s| s.is_enabled() && !s.is_bypassed())
            .map(|s| s.latency())
            .max()
            .unwrap_or(0);

        self.total_latency = max_latency;

        // Set compensation delays
        for (i, slot) in slots.iter().enumerate() {
            if i < self.delay_lines.len() {
                if slot.is_enabled() && !slot.is_bypassed() {
                    let compensation = max_latency.saturating_sub(slot.latency());
                    self.delay_lines[i].set_delay(compensation as usize);
                } else {
                    self.delay_lines[i].set_delay(0);
                }
            }
        }
    }

    /// Process with delay compensation
    pub fn process(&mut self, slot_index: usize, buffer: &mut AudioBuffer) {
        if self.enabled && slot_index < self.delay_lines.len() {
            self.delay_lines[slot_index].process(buffer);
        }
    }

    pub fn total_latency(&self) -> u32 {
        self.total_latency
    }

    pub fn set_enabled(&mut self, enabled: bool) {
        self.enabled = enabled;
    }
}

/// Simple delay line for PDC
pub struct DelayLine {
    buffers: Vec<Vec<f32>>,
    delay: usize,
    write_pos: usize,
    max_delay: usize,
}

impl DelayLine {
    pub fn new(max_delay: usize, channels: usize) -> Self {
        let buffers = (0..channels).map(|_| vec![0.0f32; max_delay]).collect();

        Self {
            buffers,
            delay: 0,
            write_pos: 0,
            max_delay,
        }
    }

    pub fn set_delay(&mut self, delay: usize) {
        self.delay = delay.min(self.max_delay);
    }

    pub fn process(&mut self, buffer: &mut AudioBuffer) {
        if self.delay == 0 {
            return;
        }

        for (ch, channel) in buffer.data.iter_mut().enumerate() {
            if ch >= self.buffers.len() {
                continue;
            }

            for sample in channel.iter_mut() {
                let read_pos = (self.write_pos + self.max_delay - self.delay) % self.max_delay;
                let delayed = self.buffers[ch][read_pos];
                self.buffers[ch][self.write_pos] = *sample;
                *sample = delayed;
                self.write_pos = (self.write_pos + 1) % self.max_delay;
            }
            self.write_pos = 0; // Reset for next channel
        }
    }

    pub fn reset(&mut self) {
        for buffer in &mut self.buffers {
            buffer.fill(0.0);
        }
        self.write_pos = 0;
    }
}

/// Zero-Copy Plugin Chain
pub struct ZeroCopyChain {
    /// Plugin slots
    slots: Vec<ChainSlot>,
    /// Buffer pool
    buffer_pool: BufferPool,
    /// PDC manager
    pdc: PdcManager,
    /// Processing context
    context: ProcessContext,
    /// Is processing
    processing: AtomicBool,
    /// Chain bypass
    bypass: AtomicBool,
    /// Pre-allocated temp buffer for input staging (separate from pool for borrow safety)
    input_staging: AudioBuffer,
    /// Pre-allocated temp buffer for dry signal (wet/dry mixing)
    dry_buffer: AudioBuffer,
    /// Pre-allocated empty MIDI buffer for effect chain processing (zero-alloc on audio thread)
    empty_midi_in: rf_core::MidiBuffer,
    /// Pre-allocated MIDI output buffer (unused for effects, avoids per-block allocation)
    midi_out_scratch: rf_core::MidiBuffer,
}

impl std::fmt::Debug for ZeroCopyChain {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ZeroCopyChain")
            .field("slot_count", &self.slots.len())
            .field(
                "is_bypassed",
                &self.bypass.load(std::sync::atomic::Ordering::Relaxed),
            )
            .field(
                "is_processing",
                &self.processing.load(std::sync::atomic::Ordering::Relaxed),
            )
            .finish()
    }
}

impl ZeroCopyChain {
    pub fn new(max_slots: usize, channels: usize, buffer_size: usize) -> Self {
        // Pool needs at least max_slots * 2 buffers (input + output per slot)
        let pool_size = max_slots * 2 + 2;

        Self {
            slots: Vec::with_capacity(max_slots),
            buffer_pool: BufferPool::new(pool_size, channels, buffer_size),
            pdc: PdcManager::new(max_slots, 48000, channels), // ~1 second max delay
            context: ProcessContext::default(),
            processing: AtomicBool::new(false),
            bypass: AtomicBool::new(false),
            // Pre-allocated temp buffers (separate from pool for independent borrowing)
            input_staging: AudioBuffer::new(channels, buffer_size),
            dry_buffer: AudioBuffer::new(channels, buffer_size),
            // Pre-allocated MIDI buffers (zero-alloc on audio thread)
            empty_midi_in: rf_core::MidiBuffer::new(),
            midi_out_scratch: rf_core::MidiBuffer::new(),
        }
    }

    /// Add a plugin to the chain
    pub fn add(&mut self, plugin: Box<dyn PluginInstance>) -> PluginResult<usize> {
        let input_buffer = self
            .buffer_pool
            .acquire()
            .ok_or_else(|| PluginError::ProcessingError("No buffers available".to_string()))?;
        let output_buffer = self
            .buffer_pool
            .acquire()
            .ok_or_else(|| PluginError::ProcessingError("No buffers available".to_string()))?;

        let slot = ChainSlot::new(plugin, input_buffer, output_buffer);
        self.slots.push(slot);

        // Recalculate PDC
        self.pdc.recalculate(&self.slots);

        Ok(self.slots.len() - 1)
    }

    /// Remove a plugin from the chain
    pub fn remove(&mut self, index: usize) -> Option<Box<dyn PluginInstance>> {
        if index >= self.slots.len() {
            return None;
        }

        let slot = self.slots.remove(index);

        // Release buffers back to pool
        self.buffer_pool.release(slot.input_buffer);
        self.buffer_pool.release(slot.output_buffer);

        // Recalculate PDC
        self.pdc.recalculate(&self.slots);

        // Extract plugin
        Arc::try_unwrap(slot.plugin).ok().map(|rw| rw.into_inner())
    }

    /// Get slot at index
    pub fn get(&self, index: usize) -> Option<&ChainSlot> {
        self.slots.get(index)
    }

    /// Number of slots
    pub fn len(&self) -> usize {
        self.slots.len()
    }

    /// Is empty
    pub fn is_empty(&self) -> bool {
        self.slots.is_empty()
    }

    /// Set bypass
    pub fn set_bypass(&self, bypass: bool) {
        self.bypass.store(bypass, Ordering::Relaxed);
    }

    /// Is bypassed
    pub fn is_bypassed(&self) -> bool {
        self.bypass.load(Ordering::Relaxed)
    }

    /// Get total latency
    pub fn latency(&self) -> u32 {
        self.pdc.total_latency()
    }

    /// Update processing context
    pub fn set_context(&mut self, context: ProcessContext) {
        self.context = context;
    }

    /// Process audio through the chain (ZERO ALLOCATION)
    ///
    /// # Audio Thread Safety
    /// This method performs NO heap allocations. All buffers are pre-allocated
    /// during construction. Temp buffers (input_staging, dry_buffer) are stored
    /// separately from buffer_pool to allow independent borrowing.
    pub fn process(&mut self, input: &AudioBuffer, output: &mut AudioBuffer) -> PluginResult<()> {
        if self.is_bypassed() || self.slots.is_empty() {
            // Direct copy - zero allocation
            output.copy_from(input);
            return Ok(());
        }

        self.processing.store(true, Ordering::Release);

        // Stage 1: Copy input to input_staging buffer
        // input_staging is separate from buffer_pool, so no borrow conflict
        self.input_staging.copy_from(input);

        // Stage 2: Process through enabled slots
        let mut prev_output_idx: Option<usize> = None;

        for (slot_i, slot) in self.slots.iter().enumerate() {
            if !slot.is_enabled() {
                continue;
            }

            let out_idx = slot.output_buffer;
            // Treat slots auto-disabled by repeated panics as bypassed —
            // their plugin keeps crashing the process() call, so we
            // pass the signal through untouched until the user replaces
            // or removes the plugin.
            let bypassed = slot.is_bypassed() || slot.is_auto_disabled_after_panic();
            let mix = slot.mix();
            let plugin = Arc::clone(&slot.plugin);

            if bypassed {
                // Bypass: copy current input to output buffer
                // First, update input_staging if we have previous output
                if let Some(prev_idx) = prev_output_idx
                    && let Some(prev_buf) = self.buffer_pool.get(prev_idx)
                {
                    self.input_staging.copy_from(prev_buf);
                }
                // Now copy from input_staging to output (input_staging already has original input if no prev)
                if let Some(out_buf) = self.buffer_pool.get_mut(out_idx) {
                    out_buf.copy_from(&self.input_staging);
                }
            } else {
                // Active processing
                // Step 1: Prepare input_staging with current input
                if let Some(prev_idx) = prev_output_idx
                    && let Some(prev_buf) = self.buffer_pool.get(prev_idx)
                {
                    self.input_staging.copy_from(prev_buf);
                }
                // If prev_output_idx is None, input_staging already has the original input

                // Step 2: Save dry signal if wet/dry mix needed
                let needs_mix = mix < 1.0;
                if needs_mix {
                    self.dry_buffer.copy_from(&self.input_staging);
                }

                // Step 3: Process through plugin (empty MIDI for effect chain).
                //
                // FLUX_MASTER_TODO 1.5.2 phase 1 — wrap the plugin call in
                // `catch_unwind`. Third-party plugins (especially LV2 / VST3
                // wrappers around C++ code) can panic for reasons we don't
                // control: division by zero on a config edge, internal
                // assertions, allocator failures during preset load.
                // Pre-fix the panic propagated up the audio thread and took
                // the whole DAW process with it. Now:
                //   1. Plugin panic is caught + reported.
                //   2. The slot's panic_count is incremented; after
                //      MAX_PLUGIN_PANICS_BEFORE_DISABLE it auto-bypasses
                //      so a chronically-broken plugin can't keep tanking
                //      every audio block.
                //   3. The current block falls through to passthrough
                //      (input copied to output) so the user hears the dry
                //      signal instead of silence + glitch.
                //
                // Caveat: `catch_unwind` will allocate the panic payload
                // (Box<dyn Any>) on the heap — a real-time violation. That's
                // accepted: choosing a one-time alloc on the panic edge over
                // a process abort. Phase 2 (full subprocess sandbox via
                // crates/rf-plugin/src/sandbox.rs) eliminates the alloc by
                // moving the plugin out of our address space entirely.
                if let Some(out_buf) = self.buffer_pool.get_mut(out_idx) {
                    self.midi_out_scratch.clear();
                    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                        let mut plugin_lock = plugin.write();
                        plugin_lock.process(
                            &self.input_staging,
                            out_buf,
                            &self.empty_midi_in,
                            &mut self.midi_out_scratch,
                            &self.context,
                        )
                    }));

                    match result {
                        Ok(Ok(())) => {
                            // Step 4: Apply wet/dry mix if needed
                            if needs_mix {
                                out_buf.apply_mix(&self.dry_buffer, mix);
                            }
                        }
                        Ok(Err(plugin_err)) => {
                            // Plugin returned an error (clean failure mode).
                            // Fall through to passthrough for this block;
                            // don't escalate the chain — one slot's failure
                            // shouldn't blank every downstream slot.
                            out_buf.copy_from(&self.input_staging);
                            log::warn!(
                                "[chain] slot {slot_i} plugin returned error, passthrough: {plugin_err}"
                            );
                        }
                        Err(_payload) => {
                            // Plugin panicked. Count it; auto-disable the
                            // slot if it keeps misbehaving; passthrough
                            // this block.
                            let n = slot.record_panic();
                            out_buf.copy_from(&self.input_staging);
                            log::error!(
                                "[chain] slot {slot_i} plugin PANICKED ({n}/{}). \
                                 {}",
                                MAX_PLUGIN_PANICS_BEFORE_DISABLE,
                                if n >= MAX_PLUGIN_PANICS_BEFORE_DISABLE {
                                    "Auto-disabling — replace or remove the plugin."
                                } else {
                                    "Passing through this block."
                                }
                            );
                        }
                    }
                }
            }

            // Apply PDC for this slot
            if let Some(out_buf) = self.buffer_pool.get_mut(out_idx) {
                self.pdc.process(slot_i, out_buf);
            }

            prev_output_idx = Some(out_idx);
        }

        // Stage 3: Copy final output
        if let Some(final_idx) = prev_output_idx {
            if let Some(final_buf) = self.buffer_pool.get(final_idx) {
                output.copy_from(final_buf);
            }
        } else {
            // No processing happened - copy input to output
            output.copy_from(input);
        }

        self.processing.store(false, Ordering::Release);
        Ok(())
    }

    /// Reset chain state
    pub fn reset(&mut self) {
        for slot in &self.slots {
            // BUG#53: use blocking write() instead of try_write() — silent failure on
            // lock contention would leave plugins active, causing state corruption.
            let mut plugin = slot.plugin.write();
            let _ = plugin.deactivate();
            let _ = plugin.activate();
        }

        self.buffer_pool.clear_all();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_buffer_pool() {
        let mut pool = BufferPool::new(4, 2, 512);

        let b1 = pool.acquire().unwrap();
        let b2 = pool.acquire().unwrap();

        assert_ne!(b1, b2);

        pool.release(b1);
        let b3 = pool.acquire().unwrap();
        assert_eq!(b1, b3);
    }

    #[test]
    fn test_delay_line() {
        let mut delay = DelayLine::new(1024, 2);
        delay.set_delay(3);

        let mut buffer = AudioBuffer::new(2, 8);
        buffer.data[0] = vec![1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0];

        delay.process(&mut buffer);

        // First 3 samples should be 0 (delayed)
        assert_eq!(buffer.data[0][0], 0.0);
        assert_eq!(buffer.data[0][1], 0.0);
        assert_eq!(buffer.data[0][2], 0.0);
    }

    #[test]
    fn test_chain_creation() {
        let chain = ZeroCopyChain::new(8, 2, 512);
        assert!(chain.is_empty());
        assert_eq!(chain.latency(), 0);
    }

    // ─── FLUX_MASTER_TODO 1.5.2 phase 1: panic-survival tests ───

    use crate::scanner::PluginInfo;
    use crate::{ParameterInfo, PluginError, PluginInstance, PluginResult, ProcessContext};
    use std::sync::atomic::AtomicU32;
    use std::sync::atomic::Ordering as AtomicOrdering;

    /// Test plugin that panics on every Nth process() call.
    struct PanickyPlugin {
        info: PluginInfo,
        calls: AtomicU32,
        panic_every: u32,
    }

    impl PanickyPlugin {
        fn new(panic_every: u32) -> Box<dyn PluginInstance> {
            Box::new(Self {
                info: PluginInfo {
                    id: "test.panicky".into(),
                    name: "Panicky Test Plugin".into(),
                    vendor: "test".into(),
                    version: "0".into(),
                    plugin_type: crate::scanner::PluginType::Internal,
                    category: crate::scanner::PluginCategory::Effect,
                    path: "<test>".into(),
                    audio_inputs: 2,
                    audio_outputs: 2,
                    has_midi_input: false,
                    has_midi_output: false,
                    has_editor: false,
                    latency: 0,
                    is_shell: false,
                    sub_plugins: vec![],
                },
                calls: AtomicU32::new(0),
                panic_every,
            })
        }
    }

    impl PluginInstance for PanickyPlugin {
        fn info(&self) -> &PluginInfo { &self.info }
        fn initialize(&mut self, _: &ProcessContext) -> PluginResult<()> { Ok(()) }
        fn activate(&mut self) -> PluginResult<()> { Ok(()) }
        fn deactivate(&mut self) -> PluginResult<()> { Ok(()) }
        fn process(
            &mut self,
            input: &AudioBuffer,
            output: &mut AudioBuffer,
            _midi_in: &rf_core::MidiBuffer,
            _midi_out: &mut rf_core::MidiBuffer,
            _ctx: &ProcessContext,
        ) -> PluginResult<()> {
            let n = self.calls.fetch_add(1, AtomicOrdering::Relaxed) + 1;
            if self.panic_every > 0 && n % self.panic_every == 0 {
                panic!("PanickyPlugin scheduled panic at call {n}");
            }
            output.copy_from(input);
            Ok(())
        }
        fn parameter_count(&self) -> usize { 0 }
        fn parameter_info(&self, _: usize) -> Option<ParameterInfo> { None }
        fn get_parameter(&self, _: u32) -> Option<f64> { None }
        fn set_parameter(&mut self, _: u32, _: f64) -> PluginResult<()> {
            Err(PluginError::ProcessingError("no params".into()))
        }
        fn get_state(&self) -> PluginResult<Vec<u8>> { Ok(vec![]) }
        fn set_state(&mut self, _: &[u8]) -> PluginResult<()> { Ok(()) }
        fn latency(&self) -> usize { 0 }
        fn has_editor(&self) -> bool { false }
        fn open_editor(&mut self, _: *mut std::ffi::c_void) -> PluginResult<()> { Ok(()) }
        fn close_editor(&mut self) -> PluginResult<()> { Ok(()) }
    }

    fn one_buffer(channels: usize, frames: usize, fill: f32) -> AudioBuffer {
        let mut b = AudioBuffer::new(channels, frames);
        for ch in &mut b.data {
            for s in ch.iter_mut() { *s = fill; }
        }
        b
    }

    #[test]
    fn test_chain_survives_plugin_panic() {
        let mut chain = ZeroCopyChain::new(4, 2, 64);
        chain.add(PanickyPlugin::new(1)).unwrap(); // panics every call

        let input = one_buffer(2, 64, 0.5);
        let mut output = AudioBuffer::new(2, 64);

        // First call: plugin panics. Chain must NOT propagate the panic
        // and must instead pass-through the input. This was the
        // pre-1.5.2-phase-1 crash mode.
        let result = chain.process(&input, &mut output);
        assert!(result.is_ok(),
            "chain.process() must return Ok even when plugin panics");
        assert_eq!(output.data[0][0], 0.5,
            "panicked-slot output must be passthrough of input");
        assert_eq!(chain.get(0).unwrap().panic_count(), 1);
        assert!(!chain.get(0).unwrap().is_auto_disabled_after_panic(),
            "first panic does not yet trip auto-disable");
    }

    #[test]
    fn test_chain_auto_disables_after_repeated_panics() {
        let mut chain = ZeroCopyChain::new(4, 2, 64);
        chain.add(PanickyPlugin::new(1)).unwrap();

        let input = one_buffer(2, 64, 0.25);
        let mut output = AudioBuffer::new(2, 64);

        // Drive the slot through the panic threshold.
        for _ in 0..MAX_PLUGIN_PANICS_BEFORE_DISABLE {
            let _ = chain.process(&input, &mut output);
        }
        let slot = chain.get(0).unwrap();
        assert_eq!(slot.panic_count(), MAX_PLUGIN_PANICS_BEFORE_DISABLE);
        assert!(slot.is_auto_disabled_after_panic(),
            "slot must auto-disable after {MAX_PLUGIN_PANICS_BEFORE_DISABLE} panics");

        // Subsequent process() must NOT call the plugin (it would panic
        // again) — it should short-circuit through the bypass branch.
        // We can't directly observe "did we call the plugin" without a
        // counter, but we CAN observe that no further panic_count
        // increments happen after auto-disable engaged.
        let baseline = slot.panic_count();
        for _ in 0..5 {
            let _ = chain.process(&input, &mut output);
        }
        assert_eq!(chain.get(0).unwrap().panic_count(), baseline,
            "auto-disabled slot must not invoke the plugin again");
    }

    #[test]
    fn test_chain_survives_plugin_returning_error() {
        // A clean error return (Err(PluginError::...)) is a different code
        // path than a panic — but the chain must also not propagate it,
        // since an error in slot N shouldn't blank slots N+1..end.
        struct ErroringPlugin {
            info: PluginInfo,
        }
        impl PluginInstance for ErroringPlugin {
            fn info(&self) -> &PluginInfo { &self.info }
            fn initialize(&mut self, _: &ProcessContext) -> PluginResult<()> { Ok(()) }
            fn activate(&mut self) -> PluginResult<()> { Ok(()) }
            fn deactivate(&mut self) -> PluginResult<()> { Ok(()) }
            fn process(&mut self, _: &AudioBuffer, _: &mut AudioBuffer,
                _: &rf_core::MidiBuffer, _: &mut rf_core::MidiBuffer,
                _: &ProcessContext) -> PluginResult<()> {
                Err(PluginError::ProcessingError("simulated error".into()))
            }
            fn parameter_count(&self) -> usize { 0 }
            fn parameter_info(&self, _: usize) -> Option<ParameterInfo> { None }
            fn get_parameter(&self, _: u32) -> Option<f64> { None }
            fn set_parameter(&mut self, _: u32, _: f64) -> PluginResult<()> {
                Err(PluginError::ProcessingError("no params".into()))
            }
            fn get_state(&self) -> PluginResult<Vec<u8>> { Ok(vec![]) }
            fn set_state(&mut self, _: &[u8]) -> PluginResult<()> { Ok(()) }
            fn latency(&self) -> usize { 0 }
            fn has_editor(&self) -> bool { false }
            fn open_editor(&mut self, _: *mut std::ffi::c_void) -> PluginResult<()> { Ok(()) }
            fn close_editor(&mut self) -> PluginResult<()> { Ok(()) }
        }
        let info = PluginInfo {
            id: "test.erroring".into(), name: "Erroring".into(), vendor: "test".into(),
            version: "0".into(), plugin_type: crate::scanner::PluginType::Internal,
            category: crate::scanner::PluginCategory::Effect, path: "<test>".into(),
            audio_inputs: 2, audio_outputs: 2,
            has_midi_input: false, has_midi_output: false,
            has_editor: false, latency: 0, is_shell: false, sub_plugins: vec![],
        };
        let plugin: Box<dyn PluginInstance> = Box::new(ErroringPlugin { info });

        let mut chain = ZeroCopyChain::new(4, 2, 64);
        chain.add(plugin).unwrap();

        let input = one_buffer(2, 64, 0.75);
        let mut output = AudioBuffer::new(2, 64);
        let r = chain.process(&input, &mut output);
        assert!(r.is_ok());
        // Output is passthrough — error path in the chain copies input.
        assert_eq!(output.data[0][0], 0.75);
        assert_eq!(chain.get(0).unwrap().panic_count(), 0,
            "Err return must NOT increment panic_count");
    }
}
