//! Dual-Path Audio Processing
//!
//! Implements real-time + guard thread processing like Pro Tools HDX:
//! - Real-time path: Low-latency, priority audio processing
//! - Guard path: Async lookahead processing for heavy algorithms
//! - Automatic fallback when guard can't keep up
//!
//! This enables running expensive processors (linear phase EQ, convolution reverb)
//! without affecting real-time performance.

use std::sync::atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering};
use std::sync::Arc;
use std::thread::{self, JoinHandle};

use crossbeam_channel::{bounded, Receiver, Sender, TrySendError};
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

/// Audio block for passing between threads
#[derive(Clone)]
pub struct AudioBlock {
    /// Left channel data
    pub left: Vec<Sample>,
    /// Right channel data
    pub right: Vec<Sample>,
    /// Block sequence number
    pub sequence: u64,
    /// Timestamp (sample position)
    pub sample_position: u64,
}

impl AudioBlock {
    pub fn new(block_size: usize) -> Self {
        Self {
            left: vec![0.0; block_size],
            right: vec![0.0; block_size],
            sequence: 0,
            sample_position: 0,
        }
    }

    pub fn from_slices(left: &[Sample], right: &[Sample], sequence: u64, position: u64) -> Self {
        Self {
            left: left.to_vec(),
            right: right.to_vec(),
            sequence,
            sample_position: position,
        }
    }

    pub fn block_size(&self) -> usize {
        self.left.len()
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
                            stats.guard_process_time_us.store(elapsed, Ordering::Relaxed);
                            stats.guard_blocks.fetch_add(1, Ordering::Relaxed);

                            if let Err(_) = guard_output_tx.try_send(block) {
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
    /// In Guard/Hybrid mode:
    /// 1. Send current block to guard thread
    /// 2. Try to receive processed block from guard
    /// 3. If no processed block, use fallback or pass through
    pub fn process(&self, left: &mut [Sample], right: &mut [Sample]) {
        let seq = self.sequence.fetch_add(1, Ordering::Relaxed);
        let pos = self.sample_position.fetch_add(left.len() as u64, Ordering::Relaxed);

        match self.mode {
            ProcessingMode::RealTime => {
                // Direct processing with fallback
                if let Some(ref mut fallback) = *self.fallback.lock() {
                    let mut block = AudioBlock::from_slices(left, right, seq, pos);
                    fallback.process(&mut block);
                    left.copy_from_slice(&block.left);
                    right.copy_from_slice(&block.right);
                }
            }

            ProcessingMode::Guard | ProcessingMode::Hybrid => {
                // Send to guard thread
                let block = AudioBlock::from_slices(left, right, seq, pos);

                match self.guard_tx.try_send(block) {
                    Ok(_) => {
                        self.stats.queue_depth.fetch_add(1, Ordering::Relaxed);
                    }
                    Err(TrySendError::Full(_)) => {
                        // Queue full, guard is falling behind
                        self.stats.underruns.fetch_add(1, Ordering::Relaxed);
                        log::debug!("Guard queue full, underrun");
                    }
                    Err(TrySendError::Disconnected(_)) => {
                        log::warn!("Guard thread disconnected");
                    }
                }

                // Try to receive processed block
                match self.guard_rx.try_recv() {
                    Ok(processed) => {
                        self.stats.queue_depth.fetch_sub(1, Ordering::Relaxed);

                        // Copy processed data
                        let len = left.len().min(processed.left.len());
                        left[..len].copy_from_slice(&processed.left[..len]);
                        right[..len].copy_from_slice(&processed.right[..len]);
                    }
                    Err(_) => {
                        // No processed block available
                        if self.mode == ProcessingMode::Hybrid {
                            // Use fallback
                            self.stats.fallback_blocks.fetch_add(1, Ordering::Relaxed);

                            if let Some(ref mut fallback) = *self.fallback.lock() {
                                let mut block = AudioBlock::from_slices(left, right, seq, pos);
                                fallback.process(&mut block);
                                left.copy_from_slice(&block.left);
                                right.copy_from_slice(&block.right);
                            }
                        }
                        // In pure Guard mode, we'd introduce latency (use lookahead buffer)
                    }
                }
            }
        }
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
            blocks: (0..num_blocks).map(|_| AudioBlock::new(block_size)).collect(),
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
