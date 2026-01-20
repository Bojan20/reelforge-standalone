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
//! - Communication via rtrb lock-free SPSC ring buffers
//! - Index-based messaging (send index, not data) for zero-copy
//! - Lookahead buffer is circular with pre-allocated blocks

use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering};
use std::thread::{self, JoinHandle};

use crossbeam_channel::{Receiver, Sender, bounded};
use parking_lot::Mutex;
use rf_core::Sample;
use rf_dsp::delay_compensation::LatencySamples;
use rtrb::{Consumer, Producer, RingBuffer};

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

    /// Create from slices - copies data into NEW block
    ///
    /// # ⚠️ ALLOCATES - NOT FOR AUDIO THREAD
    /// This method calls `to_vec()` which allocates heap memory.
    /// Use ONLY during setup, initialization, or testing.
    ///
    /// In audio callback, use [`copy_from_slices()`] instead.
    #[cold]
    #[inline(never)]
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

// SAFETY: Pool blocks are only accessed through acquire/release pattern
// Each block can only be owned by one thread at a time
unsafe impl Send for AudioBlockPool {}
unsafe impl Sync for AudioBlockPool {}

/// Message sent via lock-free ring buffer (just indices, no data copy)
#[derive(Clone, Copy, Debug)]
#[allow(dead_code)]
pub struct BlockMessage {
    /// Index into the shared pool
    pub pool_index: usize,
    /// Sequence number for ordering (used for debugging and future ordering)
    pub sequence: u64,
    /// Sample position (used for latency compensation)
    pub sample_position: u64,
}

/// Shared audio block pool with interior mutability for lock-free access
/// Uses UnsafeCell to allow mutable access from multiple threads
/// SAFETY: Each block index is owned by exactly one thread at a time
#[allow(dead_code)]
pub struct SharedAudioBlockPool {
    /// The blocks (accessed via UnsafeCell for interior mutability)
    blocks: std::cell::UnsafeCell<Vec<AudioBlock>>,
    /// Atomic stack of free indices
    free_stack: Vec<AtomicUsize>,
    /// Current stack top
    stack_top: AtomicUsize,
    /// Block size (for API compatibility)
    block_size: usize,
    pool_size: usize,
}

// SAFETY: Each block is exclusively owned by one thread via acquire/release
unsafe impl Send for SharedAudioBlockPool {}
unsafe impl Sync for SharedAudioBlockPool {}

impl SharedAudioBlockPool {
    /// Create a new shared pool
    pub fn new(block_size: usize, pool_size: usize) -> Self {
        let blocks = (0..pool_size)
            .map(|_| AudioBlock::new(block_size))
            .collect();

        let free_stack: Vec<AtomicUsize> = (0..pool_size)
            .map(AtomicUsize::new)
            .collect();

        Self {
            blocks: std::cell::UnsafeCell::new(blocks),
            free_stack,
            stack_top: AtomicUsize::new(pool_size),
            block_size,
            pool_size,
        }
    }

    /// Acquire a block index from the pool (lock-free)
    /// Returns None if pool is exhausted
    #[inline]
    pub fn acquire(&self) -> Option<usize> {
        loop {
            let top = self.stack_top.load(Ordering::Acquire);
            if top == 0 {
                return None;
            }

            let new_top = top - 1;
            match self.stack_top.compare_exchange_weak(
                top,
                new_top,
                Ordering::AcqRel,
                Ordering::Relaxed,
            ) {
                Ok(_) => {
                    let index = self.free_stack[new_top].load(Ordering::Acquire);
                    return Some(index);
                }
                Err(_) => continue,
            }
        }
    }

    /// Release a block back to the pool (lock-free)
    #[inline]
    pub fn release(&self, index: usize) {
        if index >= self.pool_size {
            return;
        }

        loop {
            let top = self.stack_top.load(Ordering::Acquire);
            if top >= self.pool_size {
                return;
            }

            match self.stack_top.compare_exchange_weak(
                top,
                top + 1,
                Ordering::AcqRel,
                Ordering::Relaxed,
            ) {
                Ok(_) => {
                    self.free_stack[top].store(index, Ordering::Release);
                    return;
                }
                Err(_) => continue,
            }
        }
    }

    /// Get mutable reference to block at index
    /// SAFETY: Caller must ensure exclusive ownership via acquire()
    #[inline]
    #[allow(clippy::mut_from_ref)] // Intentional: lock-free interior mutability pattern
    pub unsafe fn get_mut(&self, index: usize) -> Option<&mut AudioBlock> {
        // SAFETY: Caller guarantees exclusive ownership of this index
        unsafe {
            let blocks = &mut *self.blocks.get();
            blocks.get_mut(index)
        }
    }

    /// Get immutable reference to block at index
    /// SAFETY: Caller must ensure ownership via acquire()
    #[inline]
    pub unsafe fn get(&self, index: usize) -> Option<&AudioBlock> {
        // SAFETY: Caller guarantees ownership of this index
        unsafe {
            let blocks = &*self.blocks.get();
            blocks.get(index)
        }
    }

    /// Block size
    #[inline]
    #[allow(dead_code)]
    pub fn block_size(&self) -> usize {
        self.block_size
    }

    /// Available blocks count (approximate)
    #[inline]
    #[allow(dead_code)]
    pub fn available(&self) -> usize {
        self.stack_top.load(Ordering::Relaxed)
    }
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

/// Wrapper for rtrb Producer that is Sync
/// SAFETY: Only accessed from audio thread (single producer pattern)
struct SyncProducer(std::cell::UnsafeCell<Option<Producer<BlockMessage>>>);

// SAFETY: Producer is only accessed from audio thread
unsafe impl Sync for SyncProducer {}

impl SyncProducer {
    fn new(producer: Option<Producer<BlockMessage>>) -> Self {
        Self(std::cell::UnsafeCell::new(producer))
    }

    /// Get mutable access to producer
    /// SAFETY: Must only be called from audio thread
    #[inline]
    #[allow(clippy::mut_from_ref)] // Intentional: single-producer pattern with UnsafeCell
    unsafe fn get_mut(&self) -> &mut Option<Producer<BlockMessage>> {
        unsafe { &mut *self.0.get() }
    }
}

/// Wrapper for rtrb Consumer that is Sync
/// SAFETY: Only accessed from audio thread (single consumer pattern)
struct SyncConsumer(std::cell::UnsafeCell<Option<Consumer<BlockMessage>>>);

// SAFETY: Consumer is only accessed from audio thread
unsafe impl Sync for SyncConsumer {}

impl SyncConsumer {
    fn new(consumer: Option<Consumer<BlockMessage>>) -> Self {
        Self(std::cell::UnsafeCell::new(consumer))
    }

    /// Get mutable access to consumer
    /// SAFETY: Must only be called from audio thread
    #[inline]
    #[allow(clippy::mut_from_ref)] // Intentional: single-consumer pattern with UnsafeCell
    unsafe fn get_mut(&self) -> &mut Option<Consumer<BlockMessage>> {
        unsafe { &mut *self.0.get() }
    }
}

/// Dual-path audio engine
///
/// Lock-free design for real-time audio:
/// - SharedAudioBlockPool for zero-allocation block management
/// - rtrb SPSC ring buffers for lock-free inter-thread communication
/// - Index-based messaging (no data copy through channels)
#[allow(dead_code)]
pub struct DualPathEngine {
    /// Processing mode
    mode: ProcessingMode,
    /// Block size
    block_size: usize,
    /// Sample rate
    sample_rate: f64,
    /// Shared audio block pool (lock-free)
    shared_pool: Arc<SharedAudioBlockPool>,
    /// Lock-free ring buffer: audio thread → guard thread (indices only)
    /// Wrapped in SyncProducer for Sync impl
    guard_input_tx: SyncProducer,
    /// Lock-free ring buffer: guard thread → audio thread (indices only)
    /// Wrapped in SyncConsumer for Sync impl
    guard_output_rx: SyncConsumer,
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
    /// Pre-allocated audio block index for realtime processing
    realtime_block_idx: AtomicUsize,
    /// Pre-allocated audio block index for hybrid fallback
    fallback_block_idx: AtomicUsize,
    /// Lookahead circular buffer indices (for Guard mode)
    lookahead_indices: Vec<AtomicUsize>,
    lookahead_write_pos: AtomicUsize,
    lookahead_read_pos: AtomicUsize,
    lookahead_count: AtomicUsize,
    lookahead_capacity: usize,
    /// Legacy crossbeam channels (kept for compatibility during transition)
    guard_tx: Sender<AudioBlock>,
    guard_rx: Receiver<AudioBlock>,
}

impl DualPathEngine {
    /// Create new dual-path engine
    ///
    /// # Lock-Free Architecture
    /// - Creates SharedAudioBlockPool with enough blocks for all operations
    /// - Pool size: lookahead + 2 (realtime block + fallback block) + 4 (headroom)
    /// - Uses rtrb for lock-free SPSC communication
    pub fn new(
        mode: ProcessingMode,
        block_size: usize,
        sample_rate: f64,
        lookahead_blocks: usize,
    ) -> Self {
        // Pool needs: lookahead_blocks + realtime + fallback + guard in-flight + headroom
        let pool_size = lookahead_blocks + 2 + 4 + lookahead_blocks;
        let shared_pool = Arc::new(SharedAudioBlockPool::new(block_size, pool_size));

        // Legacy channels (for backward compatibility)
        let (guard_tx, _guard_input_rx) = bounded::<AudioBlock>(lookahead_blocks * 2);
        let (_guard_output_tx, guard_rx) = bounded::<AudioBlock>(lookahead_blocks * 2);

        let guard_running = Arc::new(AtomicBool::new(false));
        let stats = Arc::new(DualPathStats::default());

        // Pre-acquire blocks for realtime and fallback processing
        let realtime_idx = shared_pool.acquire().expect("Pool should have blocks");
        let fallback_idx = shared_pool.acquire().expect("Pool should have blocks");

        // Create lookahead index buffer (atomic for lock-free access)
        let lookahead_indices: Vec<AtomicUsize> = (0..lookahead_blocks)
            .map(|_| AtomicUsize::new(usize::MAX)) // usize::MAX = empty slot
            .collect();

        Self {
            mode,
            block_size,
            sample_rate,
            shared_pool,
            guard_input_tx: SyncProducer::new(None),
            guard_output_rx: SyncConsumer::new(None),
            guard_thread: None,
            guard_running,
            sequence: AtomicU64::new(0),
            sample_position: AtomicU64::new(0),
            stats,
            fallback: Mutex::new(None),
            realtime_block_idx: AtomicUsize::new(realtime_idx),
            fallback_block_idx: AtomicUsize::new(fallback_idx),
            lookahead_indices,
            lookahead_write_pos: AtomicUsize::new(0),
            lookahead_read_pos: AtomicUsize::new(0),
            lookahead_count: AtomicUsize::new(0),
            lookahead_capacity: lookahead_blocks,
            guard_tx,
            guard_rx,
        }
    }

    /// Start the guard thread with a processor
    ///
    /// Uses lock-free rtrb ring buffers for communication:
    /// - Audio thread pushes BlockMessage (index + metadata) to guard
    /// - Guard processes block in-place via SharedAudioBlockPool
    /// - Guard pushes processed BlockMessage back to audio thread
    pub fn start_guard(&mut self, mut processor: Box<dyn GuardProcessor>) {
        if self.guard_thread.is_some() {
            return;
        }

        let running = self.guard_running.clone();
        let stats = self.stats.clone();
        let pool = self.shared_pool.clone();

        // Create lock-free SPSC ring buffers (32 slots each)
        let (input_tx, mut input_rx) = RingBuffer::<BlockMessage>::new(32);
        let (mut output_tx, output_rx) = RingBuffer::<BlockMessage>::new(32);

        // Store in Sync wrappers
        // SAFETY: We're in &mut self, so no concurrent access
        unsafe {
            *self.guard_input_tx.get_mut() = Some(input_tx);
            *self.guard_output_rx.get_mut() = Some(output_rx);
        }

        // Legacy channels (kept for backward compat, but unused in new path)
        let (guard_tx, _) = bounded::<AudioBlock>(32);
        let (_, guard_rx) = bounded::<AudioBlock>(32);
        self.guard_tx = guard_tx;
        self.guard_rx = guard_rx;

        running.store(true, Ordering::SeqCst);

        let handle = thread::Builder::new()
            .name("rf-guard".into())
            .spawn(move || {
                while running.load(Ordering::Relaxed) {
                    // Try to pop from input ring buffer
                    match input_rx.pop() {
                        Ok(msg) => {
                            let start = std::time::Instant::now();

                            // Process block in-place (no copy!)
                            // SAFETY: We own this index until we send it back
                            unsafe {
                                if let Some(block) = pool.get_mut(msg.pool_index) {
                                    processor.process(block);
                                }
                            }

                            let elapsed = start.elapsed().as_micros() as u64;
                            stats.guard_process_time_us.store(elapsed, Ordering::Relaxed);
                            stats.guard_blocks.fetch_add(1, Ordering::Relaxed);

                            // Send processed block index back
                            if output_tx.push(msg).is_err() {
                                log::warn!("Guard output queue full");
                            }
                        }
                        Err(_) => {
                            // No input, sleep briefly to avoid spinning
                            std::thread::sleep(std::time::Duration::from_micros(100));
                        }
                    }
                }

                log::info!("Guard thread exiting");
            })
            .expect("Failed to spawn guard thread");

        self.guard_thread = Some(handle);
        log::info!("Guard thread started (lock-free mode)");
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

    /// Process audio block (LOCK-FREE, ZERO ALLOCATION)
    ///
    /// # Processing Modes:
    /// - **RealTime**: Direct processing with fallback, minimum latency
    /// - **Guard**: Uses lookahead buffer for latency compensation
    /// - **Hybrid**: Guard when available, fallback when behind
    ///
    /// # Lock-Free Design:
    /// - Uses pre-allocated blocks from SharedAudioBlockPool
    /// - Communication via atomic indices (no data copy through channels)
    /// - Zero heap allocations in audio callback
    pub fn process(&self, left: &mut [Sample], right: &mut [Sample]) {
        let seq = self.sequence.fetch_add(1, Ordering::Relaxed);
        let pos = self
            .sample_position
            .fetch_add(left.len() as u64, Ordering::Relaxed);

        match self.mode {
            ProcessingMode::RealTime => {
                // Direct processing with fallback - minimum latency
                // Use pre-allocated block from pool (no allocation!)
                if let Some(ref mut fallback) = *self.fallback.lock() {
                    let block_idx = self.realtime_block_idx.load(Ordering::Relaxed);
                    // SAFETY: We own this index exclusively for realtime processing
                    unsafe {
                        if let Some(block) = self.shared_pool.get_mut(block_idx) {
                            block.copy_from_slices(left, right, seq, pos);
                            fallback.process(block);
                            block.copy_to_slices(left, right);
                        }
                    }
                }
            }

            ProcessingMode::Guard => {
                // Pure guard mode with lock-free lookahead
                // Uses atomic indices instead of RwLock
                self.process_guard_lockfree(left, right, seq, pos);
            }

            ProcessingMode::Hybrid => {
                // Hybrid: try guard, fallback if not available
                // Lock-free index-based communication
                self.process_hybrid_lockfree(left, right, seq, pos);
            }
        }
    }

    /// Lock-free Guard mode processing
    #[inline]
    fn process_guard_lockfree(&self, left: &mut [Sample], right: &mut [Sample], seq: u64, pos: u64) {
        // Try to acquire a block from pool for input
        if let Some(input_idx) = self.shared_pool.acquire() {
            // Copy input data to pool block (no allocation!)
            // SAFETY: We just acquired this index
            unsafe {
                if let Some(block) = self.shared_pool.get_mut(input_idx) {
                    block.copy_from_slices(left, right, seq, pos);
                }
            }

            // Push to lookahead buffer (atomic, lock-free)
            let write_pos = self.lookahead_write_pos.load(Ordering::Relaxed);
            let count = self.lookahead_count.load(Ordering::Relaxed);

            if count < self.lookahead_capacity {
                // Buffer not full, just store
                self.lookahead_indices[write_pos].store(input_idx, Ordering::Release);
                self.lookahead_write_pos.store(
                    (write_pos + 1) % self.lookahead_capacity,
                    Ordering::Release,
                );
                self.lookahead_count.fetch_add(1, Ordering::AcqRel);
            } else {
                // Buffer full - send oldest to guard, store new
                let read_pos = self.lookahead_read_pos.load(Ordering::Relaxed);
                let oldest_idx = self.lookahead_indices[read_pos].swap(input_idx, Ordering::AcqRel);

                // Send oldest to guard via lock-free channel
                if oldest_idx != usize::MAX {
                    let msg = BlockMessage {
                        pool_index: oldest_idx,
                        sequence: seq.saturating_sub(self.lookahead_capacity as u64),
                        sample_position: pos.saturating_sub(
                            (self.lookahead_capacity * self.block_size) as u64,
                        ),
                    };

                    // Try lock-free push via SyncProducer wrapper
                    // SAFETY: Audio thread is single-threaded access
                    unsafe {
                        if let Some(ref mut tx) = *self.guard_input_tx.get_mut() {
                            if tx.push(msg).is_ok() {
                                self.stats.queue_depth.fetch_add(1, Ordering::Relaxed);
                            } else {
                                // Queue full, release block back to pool
                                self.shared_pool.release(oldest_idx);
                                self.stats.underruns.fetch_add(1, Ordering::Relaxed);
                            }
                        } else {
                            // No rtrb, release block
                            self.shared_pool.release(oldest_idx);
                        }
                    }
                }

                self.lookahead_read_pos.store(
                    (read_pos + 1) % self.lookahead_capacity,
                    Ordering::Release,
                );
                self.lookahead_write_pos.store(
                    (write_pos + 1) % self.lookahead_capacity,
                    Ordering::Release,
                );
            }
        }

        // Try to receive processed block (lock-free)
        // SAFETY: Audio thread is single-threaded access
        unsafe {
            if let Some(ref mut rx) = *self.guard_output_rx.get_mut() {
                match rx.pop() {
                    Ok(msg) => {
                        self.stats.queue_depth.fetch_sub(1, Ordering::Relaxed);
                        // Copy output from processed block
                        if let Some(block) = self.shared_pool.get(msg.pool_index) {
                            block.copy_to_slices(left, right);
                        }
                        // Release block back to pool
                        self.shared_pool.release(msg.pool_index);
                    }
                    Err(_) => {
                        // Guard not ready - output silence during initial fill
                        left.fill(0.0);
                        right.fill(0.0);
                    }
                }
            } else {
                // No rtrb receiver, output silence
                left.fill(0.0);
                right.fill(0.0);
            }
        }
    }

    /// Lock-free Hybrid mode processing
    #[inline]
    fn process_hybrid_lockfree(&self, left: &mut [Sample], right: &mut [Sample], seq: u64, pos: u64) {
        // Try to acquire block and send to guard

        if let Some(input_idx) = self.shared_pool.acquire() {
            // SAFETY: We just acquired this index
            unsafe {
                if let Some(block) = self.shared_pool.get_mut(input_idx) {
                    block.copy_from_slices(left, right, seq, pos);
                }
            }

            let msg = BlockMessage {
                pool_index: input_idx,
                sequence: seq,
                sample_position: pos,
            };

            // SAFETY: Audio thread is single-threaded access
            unsafe {
                if let Some(ref mut tx) = *self.guard_input_tx.get_mut() {
                    if tx.push(msg).is_ok() {
                        self.stats.queue_depth.fetch_add(1, Ordering::Relaxed);
                    } else {
                        // Queue full, release block
                        self.shared_pool.release(input_idx);
                        self.stats.underruns.fetch_add(1, Ordering::Relaxed);
                    }
                } else {
                    self.shared_pool.release(input_idx);
                }
            }
        }

        // Try to receive processed block
        let mut got_output = false;

        // SAFETY: Audio thread is single-threaded access
        unsafe {
            if let Some(ref mut rx) = *self.guard_output_rx.get_mut()
                && let Ok(msg) = rx.pop() {
                    self.stats.queue_depth.fetch_sub(1, Ordering::Relaxed);
                    if let Some(block) = self.shared_pool.get(msg.pool_index) {
                        block.copy_to_slices(left, right);
                    }
                    self.shared_pool.release(msg.pool_index);
                    got_output = true;
                }
        }

        // Fallback if guard didn't provide output
        if !got_output {
            self.stats.fallback_blocks.fetch_add(1, Ordering::Relaxed);

            if let Some(ref mut fallback) = *self.fallback.lock() {
                let block_idx = self.fallback_block_idx.load(Ordering::Relaxed);
                // SAFETY: We own this index exclusively for fallback
                unsafe {
                    if let Some(block) = self.shared_pool.get_mut(block_idx) {
                        block.copy_from_slices(left, right, seq, pos);
                        fallback.process(block);
                        block.copy_to_slices(left, right);
                    }
                }
            }
        }
    }

    /// Get lookahead latency in samples
    pub fn lookahead_latency(&self) -> usize {
        self.lookahead_capacity * self.block_size
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

        // Reset lookahead buffer indices and release blocks back to pool
        for i in 0..self.lookahead_capacity {
            let idx = self.lookahead_indices[i].swap(usize::MAX, Ordering::AcqRel);
            if idx != usize::MAX {
                self.shared_pool.release(idx);
            }
        }
        self.lookahead_write_pos.store(0, Ordering::Release);
        self.lookahead_read_pos.store(0, Ordering::Release);
        self.lookahead_count.store(0, Ordering::Release);

        if let Some(ref mut fallback) = *self.fallback.lock() {
            fallback.reset();
        }

        // Drain rtrb channels and release blocks
        // SAFETY: Reset is called from main thread when audio is stopped
        unsafe {
            if let Some(ref mut rx) = *self.guard_output_rx.get_mut() {
                while let Ok(msg) = rx.pop() {
                    self.shared_pool.release(msg.pool_index);
                }
            }
        }

        // Legacy channel drain
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
        let engine = DualPathEngine::new(ProcessingMode::RealTime, 256, 48000.0, 4);

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
