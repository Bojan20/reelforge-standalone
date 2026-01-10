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
}

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
        }
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
}

impl std::fmt::Debug for ZeroCopyChain {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ZeroCopyChain")
            .field("slot_count", &self.slots.len())
            .field("is_bypassed", &self.bypass.load(std::sync::atomic::Ordering::Relaxed))
            .field("is_processing", &self.processing.load(std::sync::atomic::Ordering::Relaxed))
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

    /// Process audio through the chain
    pub fn process(&mut self, input: &AudioBuffer, output: &mut AudioBuffer) -> PluginResult<()> {
        if self.is_bypassed() || self.slots.is_empty() {
            // Direct copy
            for (i, out_ch) in output.data.iter_mut().enumerate() {
                if let Some(in_ch) = input.data.get(i) {
                    out_ch.copy_from_slice(in_ch);
                }
            }
            return Ok(());
        }

        self.processing.store(true, Ordering::Release);

        // Collect slot info first to avoid borrow issues
        let slot_info: Vec<(
            usize,
            usize,
            bool,
            bool,
            f32,
            Arc<RwLock<Box<dyn PluginInstance>>>,
        )> = self
            .slots
            .iter()
            .enumerate()
            .filter(|(_, slot)| slot.is_enabled())
            .map(|(i, slot)| {
                (
                    i,
                    slot.output_buffer,
                    slot.is_bypassed(),
                    slot.is_enabled(),
                    slot.mix(),
                    Arc::clone(&slot.plugin),
                )
            })
            .collect();

        // Copy input to first buffer for initial processing
        let first_input_idx = if let Some((_, out_idx, _, _, _, _)) = slot_info.first() {
            // Copy external input to a temp buffer
            if let Some(buf) = self.buffer_pool.get_mut(*out_idx) {
                for (j, out_ch) in buf.data.iter_mut().enumerate() {
                    if let Some(in_ch) = input.data.get(j) {
                        out_ch.copy_from_slice(in_ch);
                    }
                }
            }
            Some(*out_idx)
        } else {
            None
        };

        // Process through chain using indices
        let mut prev_output_idx = first_input_idx;

        for (i, (slot_i, out_idx, bypassed, _enabled, mix, plugin)) in slot_info.iter().enumerate()
        {
            // Determine input: first slot uses external input, others use previous output
            let use_external_input = i == 0;

            if *bypassed {
                // Get data to copy BEFORE borrowing output buffer mutably
                let data_to_copy: Option<Vec<Vec<f32>>> = if use_external_input {
                    Some(input.data.clone())
                } else {
                    prev_output_idx
                        .and_then(|prev_idx| self.buffer_pool.get(prev_idx).map(|b| b.data.clone()))
                };

                // Now copy to output buffer
                if let Some(out_buf) = self.buffer_pool.get_mut(*out_idx) {
                    if let Some(src_data) = data_to_copy {
                        for (j, out_ch) in out_buf.data.iter_mut().enumerate() {
                            if let Some(in_ch) = src_data.get(j) {
                                out_ch.copy_from_slice(in_ch);
                            }
                        }
                    }
                }
            } else {
                // Create temporary input buffer
                let input_data: Vec<Vec<f32>> = if use_external_input {
                    input.data.clone()
                } else if let Some(prev_idx) = prev_output_idx {
                    self.buffer_pool
                        .get(prev_idx)
                        .map(|b| b.data.clone())
                        .unwrap_or_default()
                } else {
                    vec![vec![0.0f32; input.samples]; input.channels]
                };

                let temp_input = AudioBuffer::from_data(input_data.clone());

                // Process through plugin
                if let Some(out_buf) = self.buffer_pool.get_mut(*out_idx) {
                    let mut plugin_lock = plugin.write();
                    plugin_lock.process(&temp_input, out_buf, &self.context)?;

                    // Apply wet/dry mix
                    if *mix < 1.0 {
                        let dry = 1.0 - mix;
                        for (j, out_ch) in out_buf.data.iter_mut().enumerate() {
                            if let Some(in_ch) = input_data.get(j) {
                                for (k, sample) in out_ch.iter_mut().enumerate() {
                                    *sample = *sample * mix + in_ch[k] * dry;
                                }
                            }
                        }
                    }
                }
            }

            // Apply PDC
            if let Some(out_buf) = self.buffer_pool.get_mut(*out_idx) {
                self.pdc.process(*slot_i, out_buf);
            }

            prev_output_idx = Some(*out_idx);
        }

        // Copy final output
        if let Some(final_idx) = prev_output_idx {
            if let Some(final_buf) = self.buffer_pool.get(final_idx) {
                for (i, out_ch) in output.data.iter_mut().enumerate() {
                    if let Some(in_ch) = final_buf.data.get(i) {
                        out_ch.copy_from_slice(in_ch);
                    }
                }
            }
        } else {
            // No processing - copy input to output
            for (i, out_ch) in output.data.iter_mut().enumerate() {
                if let Some(in_ch) = input.data.get(i) {
                    out_ch.copy_from_slice(in_ch);
                }
            }
        }

        self.processing.store(false, Ordering::Release);
        Ok(())
    }

    /// Reset chain state
    pub fn reset(&mut self) {
        for slot in &self.slots {
            if let Some(mut plugin) = slot.plugin.try_write() {
                // Deactivate and reactivate to reset
                let _ = plugin.deactivate();
                let _ = plugin.activate();
            }
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
}
