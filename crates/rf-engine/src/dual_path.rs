//! Dual-Path Audio Processing
//!
//! Implements real-time + guard thread processing like Pro Tools HDX:
//! - Real-time path: Low-latency, priority audio processing
//! - Guard path: Async lookahead processing for heavy algorithms
//! - Automatic fallback when guard can't keep up
//!
//! This enables running expensive processors (linear phase EQ, convolution reverb)
//! without affecting real-time performance.
//!
//! # Lock-Free Design
//! - Audio blocks use pre-allocated pool (no heap in audio thread)
//! - Lookahead buffer is circular with pre-allocated blocks
//! - Communication via crossbeam bounded channels (lock-free)

use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering};
use std::thread::{self, JoinHandle};

use crossbeam_channel::{Receiver, Sender, TrySendError, bounded};
use parking_lot::{Mutex, RwLock};
use rf_core::Sample;
use rf_dsp::delay_compensation::LatencySamples;

// ============ Processing Mode ============

/// Processing mode
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProcessingMode {
    /// Real-time only (minimum latency)
    RealTime,
    /// Guard thread with lookahead (higher quality)
    Guard,
    /// Hybrid: use guard when available, fallback to realtime
    Hybrid,
}

// ============ Audio Block ============

/// Maximum block size supported (4096 samples @ 384kHz = ~10.7ms)
pub const MAX_BLOCK_SIZE: usize = 4096;

/// Audio block for passing between threads
/// Uses fixed-size arrays to avoid heap allocation
#[derive(Clone)]
pub struct AudioBlock {
    /// Left channel data (pre-allocated)
    pub left: Vec<Sample>,
    /// Right channel data (pre-allocated)
    pub right: Vec<Sample>,
    /// Actual number of samples used
    pub valid_samples: usize,
    /// Block sequence number
    pub sequence: u64,
    /// Timestamp (sample position)
    pub sample_position: u64,
}

impl AudioBlock {
    /// Create new audio block with given capacity
    /// Call this ONCE during setup, not in audio thread!
    pub fn new(block_size: usize) -> Self {
        Self {
            left: vec![0.0; block_size],
            right: vec![0.0; block_size],
            valid_samples: block_size,
            sequence: 0,
            sample_position: 0,
        }
    }

    /// Create from slices - copies data into pre-allocated block
    /// WARNING: This allocates! Use copy_from_slices() in audio thread instead
    pub fn from_slices(left: &[Sample], right: &[Sample], sequence: u64, position: u64) -> Self {
        Self {
            left: left.to_vec(),
            right: right.to_vec(),
            valid_samples: left.len(),
            sequence,
            sample_position: position,
        }
    }

    /// Copy data into this block without allocation
    /// Use this in audio thread
    #[inline]
    pub fn copy_from_slices(&mut self, left: &[Sample], right: &[Sample], sequence: u64, position: u64) {
        let len = left.len().min(right.len()).min(self.left.len());
        self.left[..len].copy_from_slice(&left[..len]);
        self.right[..len].copy_from_slice(&right[..len]);
        self.valid_samples = len;
        self.sequence = sequence;
        self.sample_position = position;
    }

    /// Copy data out of this block without allocation
    #[inline]
    pub fn copy_to_slices(&self, left: &mut [Sample], right: &mut [Sample]) {
        let len = self.valid_samples.min(left.len()).min(right.len());
        left[..len].copy_from_slice(&self.left[..len]);
        right[..len].copy_from_slice(&self.right[..len]);
    }

    /// Clear the block (fill with zeros)
    #[inline]
    pub fn clear(&mut self) {
        self.left[..self.valid_samples].fill(0.0);
        self.right[..self.valid_samples].fill(0.0);
    }

    pub fn block_size(&self) -> usize {
        self.valid_samples
    }
}

// ============ Audio Block Pool ============

/// Lock-free pre-allocated pool of audio blocks
/// Uses atomic stack for O(1) acquire/release without locks
pub struct AudioBlockPool {
    blocks: Vec<AudioBlock>,
    /// Atomic stack of free indices (LIFO for cache locality)
    /// Uses AtomicUsize for lock-free push/pop
    /// Index value of usize::MAX means "empty slot"
    free_stack: Vec<AtomicUsize>,
    /// Current stack top (atomic for lock-free access)
    stack_top: AtomicUsize,
    block_size: usize,
    pool_size: usize,
}

impl AudioBlockPool {
    /// Create pool with given number of pre-allocated blocks
    pub fn new(block_size: usize, pool_size: usize) -> Self {
        let blocks = (0..pool_size)
            .map(|_| AudioBlock::new(block_size))
            .collect();

        // Initialize free stack with all indices
        let free_stack: Vec<AtomicUsize> = (0..pool_size)
            .map(AtomicUsize::new)
            .collect();

        Self {
            blocks,
            free_stack,
            stack_top: AtomicUsize::new(pool_size), // All blocks free initially
            block_size,
            pool_size,
        }
    }

    /// Get a free block index (returns None if pool exhausted)
    /// Lock-free using atomic CAS
    #[inline]
    pub fn acquire(&self) -> Option<usize> {
        loop {
            let top = self.stack_top.load(Ordering::Acquire);
            if top == 0 {
                return None; // Pool exhausted
            }

            let new_top = top - 1;
            // Try to decrement stack_top atomically
            match self.stack_top.compare_exchange_weak(
                top,
                new_top,
                Ordering::AcqRel,
                Ordering::Relaxed,
            ) {
                Ok(_) => {
                    // Successfully decremented, get the index
                    let index = self.free_stack[new_top].load(Ordering::Acquire);
                    return Some(index);
                }
                Err(_) => {
                    // CAS failed, another thread modified stack_top, retry
                    continue;
                }
            }
        }
    }

    /// Return a block to the pool
    /// Lock-free using atomic CAS
    #[inline]
    pub fn release(&self, index: usize) {
        if index >= self.pool_size {
            return; // Invalid index
        }

        loop {
            let top = self.stack_top.load(Ordering::Acquire);
            if top >= self.pool_size {
                return; // Stack full (shouldn't happen if used correctly)
            }

            // Try to increment stack_top atomically
            match self.stack_top.compare_exchange_weak(
                top,
                top + 1,
                Ordering::AcqRel,
                Ordering::Relaxed,
            ) {
                Ok(_) => {
                    // Successfully incremented, store the index
                    self.free_stack[top].store(index, Ordering::Release);
                    return;
                }
                Err(_) => {
                    // CAS failed, retry
                    continue;
                }
            }
        }
    }

    /// Get block by index (for reading/writing)
    #[inline]
    pub fn get(&self, index: usize) -> Option<&AudioBlock> {
        self.blocks.get(index)
    }

    /// Get mutable block by index
    #[inline]
    pub fn get_mut(&mut self, index: usize) -> Option<&mut AudioBlock> {
        self.blocks.get_mut(index)
    }

    /// Number of free blocks (approximate, may be slightly off due to concurrent access)
    #[inline]
    pub fn available(&self) -> usize {
        self.stack_top.load(Ordering::Relaxed)
    }

    /// Block size
    #[inline]
    pub fn block_size(&self) -> usize {
        self.block_size
    }
}

// ============ Guard Processor Trait ============

/// Trait for processors that can run on the guard thread
pub trait GuardProcessor: Send + Sync {
    /// Process a block (can be heavy, runs on guard thread)
    fn process(&mut self, block: &mut AudioBlock);

    /// Get lookahead requirement in samples
    fn lookahead(&self) -> LatencySamples;

    /// Reset processor state
    fn reset(&mut self);

    /// Set sample rate
    fn set_sample_rate(&mut self, sample_rate: f64);
}

// ============ Dual Path Engine ============

/// Statistics for dual-path processing
#[derive(Debug, Default)]
pub struct DualPathStats {
    /// Blocks processed by guard
    pub guard_blocks: AtomicU64,
    /// Blocks where fallback was used
    pub fallback_blocks: AtomicU64,
    /// Current guard queue depth
    pub queue_depth: AtomicUsize,
    /// Guard thread processing time (microseconds, moving average)
    pub guard_process_time_us: AtomicU64,
    /// Number of guard underruns
    pub underruns: AtomicU64,
}

/// Dual-path audio engine
#[allow(dead_code)]
pub struct DualPathEngine {
    /// Processing mode
    mode: ProcessingMode,
    /// Block size
    block_size: usize,
    /// Sample rate
    sample_rate: f64,
    /// Lookahead buffer (circular)
    lookahead_buffer: RwLock<LookaheadBuffer>,
    /// Guard input channel
    guard_tx: Sender<AudioBlock>,
    /// Guard output channel
    guard_rx: Receiver<AudioBlock>,
    /// Guard thread handle
    guard_thread: Option<JoinHandle<()>>,
    /// Guard thread running flag
    guard_running: Arc<AtomicBool>,
    /// Current sequence number
    sequence: AtomicU64,
    /// Current sample position
    sample_position: AtomicU64,
    /// Statistics
    stats: Arc<DualPathStats>,
    /// Fallback processor (runs in realtime when guard is behind)
    fallback: Mutex<Option<Box<dyn GuardProcessor>>>,
    /// Pre-allocated audio block for realtime processing (avoids heap alloc)
    realtime_block: Mutex<AudioBlock>,
    /// Pre-allocated audio block for hybrid fallback (avoids heap alloc)
    fallback_block: Mutex<AudioBlock>,
}

impl DualPathEngine {
    /// Create new dual-path engine
    pub fn new(
        mode: ProcessingMode,
        block_size: usize,
        sample_rate: f64,
        lookahead_blocks: usize,
    ) -> Self {
        // Create channels with enough capacity
        let (guard_tx, _guard_input_rx) = bounded::<AudioBlock>(lookahead_blocks * 2);
        let (_guard_output_tx, guard_rx) = bounded::<AudioBlock>(lookahead_blocks * 2);

        let guard_running = Arc::new(AtomicBool::new(false));
        let stats = Arc::new(DualPathStats::default());

        Self {
            mode,
            block_size,
            sample_rate,
            lookahead_buffer: RwLock::new(LookaheadBuffer::new(block_size, lookahead_blocks)),
            guard_tx,
            guard_rx,
            guard_thread: None,
            guard_running,
            sequence: AtomicU64::new(0),
            sample_position: AtomicU64::new(0),
            stats,
            fallback: Mutex::new(None),
            // Pre-allocate audio blocks to avoid heap allocation in process()
            realtime_block: Mutex::new(AudioBlock::new(block_size)),
            fallback_block: Mutex::new(AudioBlock::new(block_size)),
        }
    }

    /// Start the guard thread with a processor
    pub fn start_guard(&mut self, mut processor: Box<dyn GuardProcessor>) {
        if self.guard_thread.is_some() {
            return;
        }

        let running = self.guard_running.clone();
        let stats = self.stats.clone();

        // Create new channels for this processor
        let (guard_tx, guard_input_rx) = bounded::<AudioBlock>(32);
        let (guard_output_tx, guard_rx) = bounded::<AudioBlock>(32);

        self.guard_tx = guard_tx;
        self.guard_rx = guard_rx;

        running.store(true, Ordering::SeqCst);

        let handle = thread::Builder::new()
            .name("rf-guard".into())
            .spawn(move || {
                while running.load(Ordering::Relaxed) {
                    match guard_input_rx.recv_timeout(std::time::Duration::from_millis(100)) {
                        Ok(mut block) => {
                            let start = std::time::Instant::now();

                            processor.process(&mut block);

                            let elapsed = start.elapsed().as_micros() as u64;
                            stats
                                .guard_process_time_us
                                .store(elapsed, Ordering::Relaxed);
                            stats.guard_blocks.fetch_add(1, Ordering::Relaxed);

                            if guard_output_tx.try_send(block).is_err() {
                                // Output queue full - we're producing faster than consuming
                                log::warn!("Guard output queue full");
                            }
                        }
                        Err(crossbeam_channel::RecvTimeoutError::Timeout) => {
                            // No input, just wait
                        }
                        Err(crossbeam_channel::RecvTimeoutError::Disconnected) => {
                            break;
                        }
                    }
                }

                log::info!("Guard thread exiting");
            })
            .expect("Failed to spawn guard thread");

        self.guard_thread = Some(handle);
        log::info!("Guard thread started");
    }

    /// Stop the guard thread
    pub fn stop_guard(&mut self) {
        self.guard_running.store(false, Ordering::SeqCst);

        if let Some(handle) = self.guard_thread.take() {
            let _ = handle.join();
        }
    }

    /// Set fallback processor (used when guard can't keep up)
    pub fn set_fallback(&self, processor: Box<dyn GuardProcessor>) {
        *self.fallback.lock() = Some(processor);
    }

    /// Process audio block
    ///
    /// # Processing Modes:
    /// - **RealTime**: Direct processing with fallback, minimum latency
    /// - **Guard**: Uses lookahead buffer for latency compensation
    /// - **Hybrid**: Guard when available, fallback when behind
    ///
    /// # Lookahead Operation (Guard/Hybrid mode):
    /// 1. Push current input to lookahead buffer
    /// 2. Send oldest buffered block to guard thread
    /// 3. Receive processed block (delayed by lookahead)
    /// 4. Output processed block (introduces lookahead_blocks * block_size latency)
    pub fn process(&self, left: &mut [Sample], right: &mut [Sample]) {
        let seq = self.sequence.fetch_add(1, Ordering::Relaxed);
        let pos = self
            .sample_position
            .fetch_add(left.len() as u64, Ordering::Relaxed);

        match self.mode {
            ProcessingMode::RealTime => {
                // Direct processing with fallback - minimum latency
                // Use pre-allocated block to avoid heap allocation
                if let Some(ref mut fallback) = *self.fallback.lock() {
                    let mut block = self.realtime_block.lock();
                    block.copy_from_slices(left, right, seq, pos);
                    fallback.process(&mut block);
                    block.copy_to_slices(left, right);
                }
            }

            ProcessingMode::Guard => {
                // Pure guard mode with lookahead buffer
                // This introduces latency but guarantees processed output
                // Note: Guard mode still needs to send blocks through channel,
                // so we create a new block here (channel takes ownership)

                let mut lookahead = self.lookahead_buffer.write();

                // Create input block - must allocate since channel takes ownership
                let input_block = AudioBlock::from_slices(left, right, seq, pos);

                // Push to lookahead buffer, get oldest block if full
                if let Some(oldest) = lookahead.push(input_block) {
                    // Send oldest block to guard thread
                    match self.guard_tx.try_send(oldest) {
                        Ok(_) => {
                            self.stats.queue_depth.fetch_add(1, Ordering::Relaxed);
                        }
                        Err(TrySendError::Full(_)) => {
                            self.stats.underruns.fetch_add(1, Ordering::Relaxed);
                        }
                        Err(TrySendError::Disconnected(_)) => {}
                    }
                }

                // Try to receive processed block
                match self.guard_rx.try_recv() {
                    Ok(processed) => {
                        self.stats.queue_depth.fetch_sub(1, Ordering::Relaxed);
                        processed.copy_to_slices(left, right);
                    }
                    Err(_) => {
                        // Guard not ready yet - output silence during initial fill
                        left.fill(0.0);
                        right.fill(0.0);
                    }
                }
            }

            ProcessingMode::Hybrid => {
                // Hybrid: try guard, fallback if not available
                // Note: Must allocate for channel, but fallback uses pre-allocated block
                let block = AudioBlock::from_slices(left, right, seq, pos);

                // Send to guard thread
                match self.guard_tx.try_send(block) {
                    Ok(_) => {
                        self.stats.queue_depth.fetch_add(1, Ordering::Relaxed);
                    }
                    Err(TrySendError::Full(_)) => {
                        self.stats.underruns.fetch_add(1, Ordering::Relaxed);
                    }
                    Err(TrySendError::Disconnected(_)) => {}
                }

                // Try to receive processed block
                match self.guard_rx.try_recv() {
                    Ok(processed) => {
                        self.stats.queue_depth.fetch_sub(1, Ordering::Relaxed);
                        processed.copy_to_slices(left, right);
                    }
                    Err(_) => {
                        // No processed block - use fallback with pre-allocated block
                        self.stats.fallback_blocks.fetch_add(1, Ordering::Relaxed);

                        if let Some(ref mut fallback) = *self.fallback.lock() {
                            let mut block = self.fallback_block.lock();
                            block.copy_from_slices(left, right, seq, pos);
                            fallback.process(&mut block);
                            block.copy_to_slices(left, right);
                        }
                    }
                }
            }
        }
    }

    /// Get lookahead latency in samples
    pub fn lookahead_latency(&self) -> usize {
        self.lookahead_buffer.read().capacity * self.block_size
    }

    /// Get processing statistics
    pub fn stats(&self) -> &DualPathStats {
        &self.stats
    }

    /// Get processing mode
    pub fn mode(&self) -> ProcessingMode {
        self.mode
    }

    /// Set processing mode
    pub fn set_mode(&mut self, mode: ProcessingMode) {
        self.mode = mode;
    }

    /// Check if guard thread is running
    pub fn is_guard_running(&self) -> bool {
        self.guard_running.load(Ordering::Relaxed)
    }

    /// Reset all state
    pub fn reset(&self) {
        self.sequence.store(0, Ordering::Relaxed);
        self.sample_position.store(0, Ordering::Relaxed);
        self.lookahead_buffer.write().clear();

        if let Some(ref mut fallback) = *self.fallback.lock() {
            fallback.reset();
        }

        // Clear channels
        while self.guard_rx.try_recv().is_ok() {}
    }
}

impl Drop for DualPathEngine {
    fn drop(&mut self) {
        self.stop_guard();
    }
}

// ============ Lookahead Buffer ============

/// Circular buffer for lookahead processing
#[allow(dead_code)]
struct LookaheadBuffer {
    /// Stored blocks
    blocks: Vec<AudioBlock>,
    /// Write position
    write_pos: usize,
    /// Read position
    read_pos: usize,
    /// Number of blocks stored
    count: usize,
    /// Capacity
    capacity: usize,
}

#[allow(dead_code)]
impl LookaheadBuffer {
    fn new(block_size: usize, num_blocks: usize) -> Self {
        Self {
            blocks: (0..num_blocks)
                .map(|_| AudioBlock::new(block_size))
                .collect(),
            write_pos: 0,
            read_pos: 0,
            count: 0,
            capacity: num_blocks,
        }
    }

    fn push(&mut self, block: AudioBlock) -> Option<AudioBlock> {
        let old = if self.count == self.capacity {
            // Buffer full, return oldest
            let old = std::mem::replace(&mut self.blocks[self.read_pos], block);
            self.read_pos = (self.read_pos + 1) % self.capacity;
            Some(old)
        } else {
            self.blocks[self.write_pos] = block;
            self.count += 1;
            None
        };

        self.write_pos = (self.write_pos + 1) % self.capacity;
        old
    }

    fn pop(&mut self) -> Option<AudioBlock> {
        if self.count == 0 {
            return None;
        }

        let block = std::mem::replace(&mut self.blocks[self.read_pos], AudioBlock::new(0));
        self.read_pos = (self.read_pos + 1) % self.capacity;
        self.count -= 1;
        Some(block)
    }

    fn clear(&mut self) {
        self.write_pos = 0;
        self.read_pos = 0;
        self.count = 0;
    }

    fn len(&self) -> usize {
        self.count
    }

    fn is_full(&self) -> bool {
        self.count == self.capacity
    }
}

// ============ Guard Processor Wrapper ============

/// Wrapper to create a GuardProcessor from a function
pub struct FnGuardProcessor<F>
where
    F: FnMut(&mut AudioBlock) + Send + Sync,
{
    process_fn: F,
    lookahead: LatencySamples,
    sample_rate: f64,
}

impl<F> FnGuardProcessor<F>
where
    F: FnMut(&mut AudioBlock) + Send + Sync,
{
    pub fn new(process_fn: F, lookahead: LatencySamples) -> Self {
        Self {
            process_fn,
            lookahead,
            sample_rate: 48000.0,
        }
    }
}

impl<F> GuardProcessor for FnGuardProcessor<F>
where
    F: FnMut(&mut AudioBlock) + Send + Sync,
{
    fn process(&mut self, block: &mut AudioBlock) {
        (self.process_fn)(block);
    }

    fn lookahead(&self) -> LatencySamples {
        self.lookahead
    }

    fn reset(&mut self) {}

    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
    }
}

// ============ Tests ============

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_audio_block() {
        let block = AudioBlock::new(256);
        assert_eq!(block.block_size(), 256);
        assert_eq!(block.left.len(), 256);
        assert_eq!(block.right.len(), 256);
    }

    #[test]
    fn test_lookahead_buffer() {
        let mut buffer = LookaheadBuffer::new(256, 4);

        // Push some blocks
        for i in 0..4 {
            let mut block = AudioBlock::new(256);
            block.sequence = i;
            assert!(buffer.push(block).is_none());
        }

        assert!(buffer.is_full());
        assert_eq!(buffer.len(), 4);

        // Pop should return in order
        let block = buffer.pop().unwrap();
        assert_eq!(block.sequence, 0);
    }

    #[test]
    fn test_dual_path_realtime_mode() {
        let mut engine = DualPathEngine::new(ProcessingMode::RealTime, 256, 48000.0, 4);

        // Set a simple gain processor as fallback
        let processor = FnGuardProcessor::new(
            |block: &mut AudioBlock| {
                for s in &mut block.left {
                    *s *= 0.5;
                }
                for s in &mut block.right {
                    *s *= 0.5;
                }
            },
            0,
        );
        engine.set_fallback(Box::new(processor));

        // Process
        let mut left = vec![1.0; 256];
        let mut right = vec![1.0; 256];
        engine.process(&mut left, &mut right);

        // Should be halved
        assert!((left[0] - 0.5).abs() < 1e-10);
    }

    #[test]
    fn test_guard_thread_lifecycle() {
        let mut engine = DualPathEngine::new(ProcessingMode::Guard, 256, 48000.0, 4);

        assert!(!engine.is_guard_running());

        // Create a simple passthrough processor
        let processor = FnGuardProcessor::new(|_block: &mut AudioBlock| {}, 0);
        engine.start_guard(Box::new(processor));

        assert!(engine.is_guard_running());

        engine.stop_guard();

        // Give thread time to stop
        std::thread::sleep(std::time::Duration::from_millis(200));
        assert!(!engine.is_guard_running());
    }

    #[test]
    fn test_stats() {
        let engine = DualPathEngine::new(ProcessingMode::RealTime, 256, 48000.0, 4);

        let stats = engine.stats();
        assert_eq!(stats.guard_blocks.load(Ordering::Relaxed), 0);
        assert_eq!(stats.underruns.load(Ordering::Relaxed), 0);
    }
}
