//! Audio Streaming System - Lock-Free Disk I/O
//!
//! Professional disk streaming architecture:
//! - Per-stream SPSC ring buffers
//! - Background disk reader thread pool
//! - Priority-based prefetch scheduling
//! - Zero allocation in audio callback
//!
//! Goals:
//! - Audio callback NEVER waits for disk
//! - Audio callback NEVER locks mutex
//! - Audio callback NEVER allocates
//! - All "heavy" work happens in disk thread pool

use std::collections::HashMap;
use std::fs::File;
use std::io::{BufReader, Read, Seek, SeekFrom};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicI64, AtomicU8, AtomicU32, Ordering};
use std::thread::{self, JoinHandle};

use parking_lot::{Mutex, RwLock};

// ═══════════════════════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════

/// Default ring buffer capacity in frames (0.5s @ 48kHz)
pub const DEFAULT_RING_BUFFER_FRAMES: usize = 24000;

/// Low water mark - urgent prefetch needed (2 blocks @ 256)
pub const LOW_WATER_FRAMES: usize = 512;

/// High water mark - target fill level
pub const HIGH_WATER_FRAMES: usize = 24000;

/// Time bin size for event indexing (frames)
pub const EVENT_BIN_SIZE: usize = 2048;

/// Maximum concurrent streams
pub const MAX_STREAMS: usize = 256;

/// Disk read chunk size (frames per read operation)
pub const DISK_READ_CHUNK_FRAMES: usize = 4096;

// ═══════════════════════════════════════════════════════════════════════════
// AUDIO FORMAT
// ═══════════════════════════════════════════════════════════════════════════

/// Audio format specification
#[derive(Debug, Clone, Copy)]
pub struct AudioFormat {
    pub sample_rate: u32,
    pub channels: u8,
    pub bytes_per_sample: u8,
}

impl Default for AudioFormat {
    fn default() -> Self {
        Self {
            sample_rate: 48000,
            channels: 2,
            bytes_per_sample: 4, // f32
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// SPSC RING BUFFER (Lock-Free, Wait-Free)
// ═══════════════════════════════════════════════════════════════════════════

/// Single-Producer Single-Consumer lock-free ring buffer for audio streaming
///
/// Producer: Disk thread (writes decoded audio)
/// Consumer: Audio callback (reads for playback)
pub struct AudioRingBuffer {
    /// Interleaved audio data [capacity_frames * channels]
    data: Box<[f32]>,
    /// Capacity in frames
    capacity_frames: usize,
    /// Number of channels
    channels: usize,
    /// Write position in frames (producer only)
    write_pos: AtomicU32,
    /// Read position in frames (consumer only)
    read_pos: AtomicU32,
}

impl AudioRingBuffer {
    /// Create new ring buffer with given capacity
    pub fn new(capacity_frames: usize, channels: usize) -> Self {
        let total_samples = capacity_frames * channels;
        let data = vec![0.0f32; total_samples].into_boxed_slice();

        Self {
            data,
            capacity_frames,
            channels,
            write_pos: AtomicU32::new(0),
            read_pos: AtomicU32::new(0),
        }
    }

    /// Available frames for reading (consumer)
    #[inline]
    pub fn available_read(&self) -> usize {
        let w = self.write_pos.load(Ordering::Acquire) as i32;
        let r = self.read_pos.load(Ordering::Acquire) as i32;
        let mut diff = w - r;
        if diff < 0 {
            diff += self.capacity_frames as i32;
        }
        diff as usize
    }

    /// Available frames for writing (producer)
    /// Leaves 1 frame gap to distinguish full from empty
    #[inline]
    pub fn available_write(&self) -> usize {
        self.capacity_frames
            .saturating_sub(1)
            .saturating_sub(self.available_read())
    }

    /// Read frames from ring buffer (audio callback - RT safe)
    /// Returns actual frames read (may be less if underflow)
    #[inline]
    pub fn read(&self, output: &mut [f32], frames: usize) -> usize {
        let avail = self.available_read();
        let to_read = frames.min(avail);

        if to_read == 0 {
            // Underflow: fill with zeros
            let samples_needed = frames * self.channels;
            output[..samples_needed].fill(0.0);
            return 0;
        }

        let r = self.read_pos.load(Ordering::Relaxed) as usize;
        let ch = self.channels;

        for i in 0..to_read {
            let idx = (r + i) % self.capacity_frames;
            let src_offset = idx * ch;
            let dst_offset = i * ch;

            for c in 0..ch {
                output[dst_offset + c] = self.data[src_offset + c];
            }
        }

        // Update read position
        let new_r = (r + to_read) % self.capacity_frames;
        self.read_pos.store(new_r as u32, Ordering::Release);

        to_read
    }

    /// Write frames to ring buffer (disk thread)
    /// Returns actual frames written (may be less if full)
    #[inline]
    pub fn write(&self, input: &[f32], frames: usize) -> usize {
        let avail = self.available_write();
        let to_write = frames.min(avail);

        if to_write == 0 {
            return 0;
        }

        let w = self.write_pos.load(Ordering::Relaxed) as usize;
        let ch = self.channels;

        // SAFETY: We're the only writer (SPSC guarantee)
        let data_ptr = self.data.as_ptr() as *mut f32;

        for i in 0..to_write {
            let idx = (w + i) % self.capacity_frames;
            let dst_offset = idx * ch;
            let src_offset = i * ch;

            for c in 0..ch {
                unsafe {
                    *data_ptr.add(dst_offset + c) = input[src_offset + c];
                }
            }
        }

        // Update write position
        let new_w = (w + to_write) % self.capacity_frames;
        self.write_pos.store(new_w as u32, Ordering::Release);

        to_write
    }

    /// Clear/reset the ring buffer
    pub fn clear(&self) {
        self.write_pos.store(0, Ordering::Release);
        self.read_pos.store(0, Ordering::Release);
    }

    /// Get buffer fill percentage (0.0 - 1.0)
    #[inline]
    pub fn fill_level(&self) -> f32 {
        self.available_read() as f32 / self.capacity_frames as f32
    }
}

// SAFETY: Ring buffer is designed for single-producer single-consumer
// The write side is only accessed by disk thread, read side only by audio thread
unsafe impl Send for AudioRingBuffer {}
unsafe impl Sync for AudioRingBuffer {}

// ═══════════════════════════════════════════════════════════════════════════
// STREAM STATE
// ═══════════════════════════════════════════════════════════════════════════

/// Stream state for real-time tracking
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum StreamState {
    /// Stream is inactive
    Stopped = 0,
    /// Stream is priming (filling buffer before playback)
    Priming = 1,
    /// Stream is running normally
    Running = 2,
    /// Stream is starved (buffer underrun)
    Starved = 3,
}

impl From<u8> for StreamState {
    fn from(value: u8) -> Self {
        match value {
            1 => Self::Priming,
            2 => Self::Running,
            3 => Self::Starved,
            _ => Self::Stopped,
        }
    }
}

/// Real-time stream state (per active audio event)
pub struct StreamRT {
    /// Unique stream ID
    pub stream_id: u32,
    /// Track ID this stream belongs to
    pub track_id: u32,
    /// Asset ID (which audio file)
    pub asset_id: u32,

    /// Next frame to read from disk (source file position)
    pub src_read_frame: AtomicI64,
    /// Next frame for audio callback to consume
    pub src_play_frame: AtomicI64,

    /// Timeline start frame of this event
    pub tl_start_frame: i64,
    /// Timeline end frame of this event
    pub tl_end_frame: i64,
    /// Source file start frame offset
    pub src_start_frame: i64,

    /// Current stream state
    pub state: AtomicU8,

    /// Clip gain (linear)
    pub gain: f32,

    /// Ring buffer for this stream
    pub ring_buffer: AudioRingBuffer,
}

impl StreamRT {
    /// Create new stream
    pub fn new(
        stream_id: u32,
        track_id: u32,
        asset_id: u32,
        tl_start_frame: i64,
        tl_end_frame: i64,
        src_start_frame: i64,
        gain: f32,
        channels: usize,
    ) -> Self {
        Self {
            stream_id,
            track_id,
            asset_id,
            src_read_frame: AtomicI64::new(src_start_frame),
            src_play_frame: AtomicI64::new(src_start_frame),
            tl_start_frame,
            tl_end_frame,
            src_start_frame,
            state: AtomicU8::new(StreamState::Stopped as u8),
            gain,
            ring_buffer: AudioRingBuffer::new(DEFAULT_RING_BUFFER_FRAMES, channels),
        }
    }

    /// Get current state
    #[inline]
    pub fn get_state(&self) -> StreamState {
        StreamState::from(self.state.load(Ordering::Relaxed))
    }

    /// Set state
    #[inline]
    pub fn set_state(&self, state: StreamState) {
        self.state.store(state as u8, Ordering::Relaxed);
    }

    /// Check if stream is active at given timeline frame
    #[inline]
    pub fn is_active_at(&self, tl_frame: i64) -> bool {
        tl_frame >= self.tl_start_frame && tl_frame < self.tl_end_frame
    }

    /// Calculate source frame from timeline frame
    #[inline]
    pub fn tl_to_src_frame(&self, tl_frame: i64) -> i64 {
        self.src_start_frame + (tl_frame - self.tl_start_frame)
    }

    /// Reset stream for seek operation
    pub fn seek(&self, new_tl_frame: i64) {
        let new_src_frame = self.tl_to_src_frame(new_tl_frame);
        self.src_read_frame.store(new_src_frame, Ordering::Relaxed);
        self.src_play_frame.store(new_src_frame, Ordering::Relaxed);
        self.ring_buffer.clear();
        self.set_state(StreamState::Priming);
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// TRACK RT STATE (Real-Time Safe)
// ═══════════════════════════════════════════════════════════════════════════

/// Real-time safe track state
pub struct TrackRT {
    /// Mute state
    pub mute: AtomicBool,
    /// Solo state
    pub solo: AtomicBool,
    /// Fader value (linear, stored as u32 bits)
    fader_bits: AtomicU32,
    /// Pan value (-1 to +1, stored as i32 * 1000000)
    pan_scaled: AtomicU32,
}

impl TrackRT {
    pub fn new() -> Self {
        Self {
            mute: AtomicBool::new(false),
            solo: AtomicBool::new(false),
            fader_bits: AtomicU32::new(1.0f32.to_bits()),
            pan_scaled: AtomicU32::new(500000), // 0.0 center
        }
    }

    #[inline]
    pub fn get_fader(&self) -> f32 {
        f32::from_bits(self.fader_bits.load(Ordering::Relaxed))
    }

    #[inline]
    pub fn set_fader(&self, value: f32) {
        self.fader_bits.store(value.to_bits(), Ordering::Relaxed);
    }

    #[inline]
    pub fn get_pan(&self) -> f32 {
        let scaled = self.pan_scaled.load(Ordering::Relaxed) as i32;
        (scaled as f32 - 500000.0) / 500000.0
    }

    #[inline]
    pub fn set_pan(&self, value: f32) {
        let scaled = ((value.clamp(-1.0, 1.0) * 500000.0) + 500000.0) as u32;
        self.pan_scaled.store(scaled, Ordering::Relaxed);
    }
}

impl Default for TrackRT {
    fn default() -> Self {
        Self::new()
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// EVENT INDEX (Time Bins for Fast Lookup)
// ═══════════════════════════════════════════════════════════════════════════

/// Event index using time bins for O(k) active stream lookup
pub struct EventIndex {
    /// Bin ID → list of stream IDs that overlap this bin
    bins: RwLock<Vec<Vec<u32>>>,
    /// Total timeline length in frames
    timeline_frames: AtomicI64,
}

impl EventIndex {
    pub fn new() -> Self {
        Self {
            bins: RwLock::new(Vec::new()),
            timeline_frames: AtomicI64::new(0),
        }
    }

    /// Rebuild index from streams
    pub fn rebuild(&self, streams: &[Arc<StreamRT>], timeline_frames: i64) {
        self.timeline_frames
            .store(timeline_frames, Ordering::Relaxed);

        let num_bins = (timeline_frames as usize / EVENT_BIN_SIZE) + 1;
        let mut bins = vec![Vec::new(); num_bins];

        for stream in streams {
            let start_bin = (stream.tl_start_frame as usize) / EVENT_BIN_SIZE;
            let end_bin = (stream.tl_end_frame as usize) / EVENT_BIN_SIZE;

            for bin_id in start_bin..=end_bin.min(num_bins - 1) {
                bins[bin_id].push(stream.stream_id);
            }
        }

        *self.bins.write() = bins;
    }

    /// Get candidate stream IDs for given timeline frame
    #[inline]
    pub fn get_candidates(&self, tl_frame: i64) -> Vec<u32> {
        let bin_id = (tl_frame as usize) / EVENT_BIN_SIZE;
        let bins = self.bins.read();

        if bin_id < bins.len() {
            bins[bin_id].clone()
        } else {
            Vec::new()
        }
    }
}

impl Default for EventIndex {
    fn default() -> Self {
        Self::new()
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// DISK JOB (Prefetch Request)
// ═══════════════════════════════════════════════════════════════════════════

/// Disk read job for prefetch scheduler
#[derive(Debug, Clone)]
pub struct DiskJob {
    /// Stream ID to fill
    pub stream_id: u32,
    /// Asset ID (file to read)
    pub asset_id: u32,
    /// Source frame to read from
    pub src_frame: i64,
    /// Number of frames to read
    pub frames: usize,
    /// Priority (higher = more urgent)
    pub priority: i32,
}

impl DiskJob {
    /// Calculate priority based on buffer health
    pub fn calculate_priority(
        available_read: usize,
        tl_start_frame: i64,
        current_tl_frame: i64,
    ) -> i32 {
        let need = HIGH_WATER_FRAMES.saturating_sub(available_read) as i32;
        let urgency = LOW_WATER_FRAMES.saturating_sub(available_read).max(0) as i32;
        let distance = (tl_start_frame - current_tl_frame).abs() as i32;

        // Urgency dominates, then need, distance is least important
        urgency * 1000 + need * 10 - distance / 64
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// ASSET CATALOG (Open File Handles)
// ═══════════════════════════════════════════════════════════════════════════

/// Cached file information for streaming
pub struct AssetInfo {
    /// File path
    pub path: String,
    /// Total frames in file
    pub total_frames: i64,
    /// Sample rate
    pub sample_rate: u32,
    /// Number of channels
    pub channels: u8,
    /// Byte offset to audio data start
    pub data_offset: u64,
    /// Bytes per sample (typically 4 for f32)
    pub bytes_per_sample: u8,
}

/// Asset catalog for managing open file handles
pub struct AssetCatalog {
    /// Asset ID → Asset info
    assets: RwLock<HashMap<u32, AssetInfo>>,
    /// Next asset ID
    next_id: AtomicU32,
}

impl AssetCatalog {
    pub fn new() -> Self {
        Self {
            assets: RwLock::new(HashMap::new()),
            next_id: AtomicU32::new(1),
        }
    }

    /// Register asset and return ID
    pub fn register(&self, info: AssetInfo) -> u32 {
        let id = self.next_id.fetch_add(1, Ordering::Relaxed);
        self.assets.write().insert(id, info);
        id
    }

    /// Get asset info
    pub fn get(&self, id: u32) -> Option<AssetInfo> {
        self.assets.read().get(&id).map(|info| AssetInfo {
            path: info.path.clone(),
            total_frames: info.total_frames,
            sample_rate: info.sample_rate,
            channels: info.channels,
            data_offset: info.data_offset,
            bytes_per_sample: info.bytes_per_sample,
        })
    }

    /// Remove asset
    pub fn remove(&self, id: u32) {
        self.assets.write().remove(&id);
    }
}

impl Default for AssetCatalog {
    fn default() -> Self {
        Self::new()
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// DISK READER THREAD POOL
// ═══════════════════════════════════════════════════════════════════════════

/// Message to disk reader threads
pub enum DiskCommand {
    /// Read audio data for a stream
    Read(DiskJob),
    /// Shutdown the thread
    Shutdown,
}

/// Disk reader thread pool for background I/O
pub struct DiskReaderPool {
    /// Job queue (priority queue would be better, but Vec works for MVP)
    job_queue: Arc<Mutex<Vec<DiskJob>>>,
    /// Worker thread handles
    workers: Vec<JoinHandle<()>>,
    /// Shutdown flag
    shutdown: Arc<AtomicBool>,
}

impl DiskReaderPool {
    /// Create new disk reader pool with N workers
    pub fn new(
        num_workers: usize,
        assets: Arc<AssetCatalog>,
        streams: Arc<RwLock<HashMap<u32, Arc<StreamRT>>>>,
    ) -> Self {
        let job_queue = Arc::new(Mutex::new(Vec::new()));
        let shutdown = Arc::new(AtomicBool::new(false));
        let mut workers = Vec::with_capacity(num_workers);

        for i in 0..num_workers {
            let queue = Arc::clone(&job_queue);
            let flag = Arc::clone(&shutdown);
            let assets = Arc::clone(&assets);
            let streams = Arc::clone(&streams);

            match thread::Builder::new()
                .name(format!("disk-reader-{}", i))
                .spawn(move || {
                    Self::worker_loop(queue, flag, assets, streams);
                }) {
                Ok(handle) => workers.push(handle),
                Err(e) => {
                    log::error!(
                        "Failed to spawn disk reader thread {}: {}. Streaming may be degraded.",
                        i,
                        e
                    );
                }
            }
        }

        Self {
            job_queue,
            workers,
            shutdown,
        }
    }

    /// Worker thread main loop
    fn worker_loop(
        queue: Arc<Mutex<Vec<DiskJob>>>,
        shutdown: Arc<AtomicBool>,
        assets: Arc<AssetCatalog>,
        streams: Arc<RwLock<HashMap<u32, Arc<StreamRT>>>>,
    ) {
        let mut read_buffer = vec![0.0f32; DISK_READ_CHUNK_FRAMES * 2]; // stereo

        loop {
            if shutdown.load(Ordering::Relaxed) {
                break;
            }

            // Get highest priority job
            let job = {
                let mut jobs = queue.lock();
                if jobs.is_empty() {
                    None
                } else {
                    // Find highest priority
                    let max_idx = jobs
                        .iter()
                        .enumerate()
                        .max_by_key(|(_, j)| j.priority)
                        .map(|(i, _)| i);

                    max_idx.map(|idx| jobs.remove(idx))
                }
            };

            match job {
                Some(job) => {
                    Self::process_job(&job, &assets, &streams, &mut read_buffer);
                }
                None => {
                    // No work, sleep briefly
                    thread::sleep(std::time::Duration::from_micros(500));
                }
            }
        }
    }

    /// Process a disk read job
    fn process_job(
        job: &DiskJob,
        assets: &AssetCatalog,
        streams: &RwLock<HashMap<u32, Arc<StreamRT>>>,
        read_buffer: &mut [f32],
    ) {
        // Get asset info
        let asset = match assets.get(job.asset_id) {
            Some(a) => a,
            None => return,
        };

        // Get stream
        let stream = match streams.read().get(&job.stream_id) {
            Some(s) => Arc::clone(s),
            None => return,
        };

        // Open file and seek
        let file = match File::open(&asset.path) {
            Ok(f) => f,
            Err(e) => {
                log::error!("Failed to open file {}: {}", asset.path, e);
                return;
            }
        };

        let mut reader = BufReader::new(file);

        // Calculate byte position
        let frame_size = asset.channels as u64 * asset.bytes_per_sample as u64;
        let byte_offset = asset.data_offset + (job.src_frame as u64 * frame_size);

        if reader.seek(SeekFrom::Start(byte_offset)).is_err() {
            return;
        }

        // Read frames
        let frames_to_read = job.frames.min(DISK_READ_CHUNK_FRAMES);
        let bytes_to_read =
            frames_to_read * asset.channels as usize * asset.bytes_per_sample as usize;

        let mut byte_buffer = vec![0u8; bytes_to_read];
        if reader.read_exact(&mut byte_buffer).is_err() {
            return;
        }

        // Convert to f32 (assuming file is already f32)
        // For WAV files, this would need proper decoding
        for (i, chunk) in byte_buffer.chunks_exact(4).enumerate() {
            read_buffer[i] = f32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]);
        }

        // Write to ring buffer
        let written = stream.ring_buffer.write(read_buffer, frames_to_read);

        // Update read position
        let old_pos = stream.src_read_frame.load(Ordering::Relaxed);
        stream
            .src_read_frame
            .store(old_pos + written as i64, Ordering::Relaxed);

        // Update state if was priming and now has enough data
        if stream.get_state() == StreamState::Priming
            && stream.ring_buffer.available_read() >= LOW_WATER_FRAMES
        {
            stream.set_state(StreamState::Running);
        }
    }

    /// Submit a job to the queue
    pub fn submit(&self, job: DiskJob) {
        self.job_queue.lock().push(job);
    }

    /// Submit multiple jobs
    pub fn submit_batch(&self, jobs: Vec<DiskJob>) {
        let mut queue = self.job_queue.lock();
        queue.extend(jobs);
    }

    /// Shutdown the pool
    pub fn shutdown(&mut self) {
        self.shutdown.store(true, Ordering::Relaxed);

        for handle in self.workers.drain(..) {
            let _ = handle.join();
        }
    }
}

impl Drop for DiskReaderPool {
    fn drop(&mut self) {
        self.shutdown();
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// STREAMING ENGINE (Main Interface)
// ═══════════════════════════════════════════════════════════════════════════

/// Main streaming engine - coordinates disk I/O and audio callback
pub struct StreamingEngine {
    /// Asset catalog
    pub assets: Arc<AssetCatalog>,
    /// Active streams
    pub streams: Arc<RwLock<HashMap<u32, Arc<StreamRT>>>>,
    /// Event index for fast lookup
    pub event_index: Arc<EventIndex>,
    /// Disk reader pool
    disk_reader: Option<DiskReaderPool>,
    /// Next stream ID
    next_stream_id: AtomicU32,
    /// Sample rate
    sample_rate: u32,
    /// Current timeline position (frames)
    current_frame: AtomicI64,
    /// Is engine running
    running: AtomicBool,
}

impl StreamingEngine {
    /// Create new streaming engine
    pub fn new(sample_rate: u32, num_disk_workers: usize) -> Self {
        let assets = Arc::new(AssetCatalog::new());
        let streams = Arc::new(RwLock::new(HashMap::new()));
        let event_index = Arc::new(EventIndex::new());

        let disk_reader =
            DiskReaderPool::new(num_disk_workers, Arc::clone(&assets), Arc::clone(&streams));

        Self {
            assets,
            streams,
            event_index,
            disk_reader: Some(disk_reader),
            next_stream_id: AtomicU32::new(1),
            sample_rate,
            current_frame: AtomicI64::new(0),
            running: AtomicBool::new(false),
        }
    }

    /// Register an audio asset
    pub fn register_asset(&self, path: &str, total_frames: i64, channels: u8) -> u32 {
        self.assets.register(AssetInfo {
            path: path.to_string(),
            total_frames,
            sample_rate: self.sample_rate,
            channels,
            data_offset: 44, // Standard WAV header (simplified)
            bytes_per_sample: 4,
        })
    }

    /// Create a stream for an audio event
    pub fn create_stream(
        &self,
        track_id: u32,
        asset_id: u32,
        tl_start_frame: i64,
        tl_end_frame: i64,
        src_start_frame: i64,
        gain: f32,
    ) -> u32 {
        let stream_id = self.next_stream_id.fetch_add(1, Ordering::Relaxed);

        // Get channel count from asset
        let channels = self
            .assets
            .get(asset_id)
            .map(|a| a.channels as usize)
            .unwrap_or(2);

        let stream = Arc::new(StreamRT::new(
            stream_id,
            track_id,
            asset_id,
            tl_start_frame,
            tl_end_frame,
            src_start_frame,
            gain,
            channels,
        ));

        self.streams.write().insert(stream_id, stream);
        stream_id
    }

    /// Remove a stream
    pub fn remove_stream(&self, stream_id: u32) {
        self.streams.write().remove(&stream_id);
    }

    /// Rebuild event index
    pub fn rebuild_index(&self, timeline_frames: i64) {
        let streams: Vec<_> = self.streams.read().values().cloned().collect();
        self.event_index.rebuild(&streams, timeline_frames);
    }

    /// Seek to new position
    pub fn seek(&self, frame: i64) {
        self.current_frame.store(frame, Ordering::Relaxed);

        // Reset all active streams
        for stream in self.streams.read().values() {
            if stream.is_active_at(frame) {
                stream.seek(frame);
            }
        }
    }

    /// Start playback
    pub fn start(&self) {
        self.running.store(true, Ordering::Relaxed);

        let frame = self.current_frame.load(Ordering::Relaxed);

        // Prime all streams that will be active soon
        for stream in self.streams.read().values() {
            if stream.is_active_at(frame)
                || stream.tl_start_frame <= frame + HIGH_WATER_FRAMES as i64
            {
                stream.set_state(StreamState::Priming);
            }
        }
    }

    /// Stop playback
    pub fn stop(&self) {
        self.running.store(false, Ordering::Relaxed);

        for stream in self.streams.read().values() {
            stream.set_state(StreamState::Stopped);
        }
    }

    /// Schedule prefetch jobs based on current position
    pub fn schedule_prefetch(&self) {
        if !self.running.load(Ordering::Relaxed) {
            return;
        }

        let current_frame = self.current_frame.load(Ordering::Relaxed);
        let mut jobs = Vec::new();

        for stream in self.streams.read().values() {
            let state = stream.get_state();
            if state == StreamState::Stopped {
                continue;
            }

            let available = stream.ring_buffer.available_read();

            // Need more data?
            if available < HIGH_WATER_FRAMES {
                let need_frames = (HIGH_WATER_FRAMES - available).min(DISK_READ_CHUNK_FRAMES);
                let src_frame = stream.src_read_frame.load(Ordering::Relaxed);

                let priority =
                    DiskJob::calculate_priority(available, stream.tl_start_frame, current_frame);

                jobs.push(DiskJob {
                    stream_id: stream.stream_id,
                    asset_id: stream.asset_id,
                    src_frame,
                    frames: need_frames,
                    priority,
                });
            }
        }

        // Sort by priority and submit
        jobs.sort_by(|a, b| b.priority.cmp(&a.priority));

        if let Some(ref reader) = self.disk_reader {
            reader.submit_batch(jobs);
        }
    }

    /// Process audio block (called from audio callback)
    /// Returns mixed stereo output
    #[inline]
    pub fn process_block(&self, output_l: &mut [f64], output_r: &mut [f64], frames: usize) {
        let current_frame = self.current_frame.load(Ordering::Relaxed);

        // Clear output
        output_l[..frames].fill(0.0);
        output_r[..frames].fill(0.0);

        if !self.running.load(Ordering::Relaxed) {
            return;
        }

        // Get candidate streams for this time region
        let candidates = self.event_index.get_candidates(current_frame);

        // Temp buffer for reading
        let mut temp = [0.0f32; 1024 * 2]; // Max block size * stereo

        let streams = self.streams.read();

        for stream_id in candidates {
            let stream = match streams.get(&stream_id) {
                Some(s) => s,
                None => continue,
            };

            // Skip if not actually active
            if !stream.is_active_at(current_frame) {
                continue;
            }

            let state = stream.get_state();
            if state == StreamState::Stopped {
                continue;
            }

            // Read from ring buffer
            let read_frames = stream.ring_buffer.read(&mut temp, frames);

            if read_frames == 0 && state != StreamState::Priming {
                stream.set_state(StreamState::Starved);
                continue;
            }

            // Mix to output with gain
            let gain = stream.gain as f64;
            for i in 0..read_frames {
                output_l[i] += temp[i * 2] as f64 * gain;
                output_r[i] += temp[i * 2 + 1] as f64 * gain;
            }

            // Update play position
            let old_pos = stream.src_play_frame.load(Ordering::Relaxed);
            stream
                .src_play_frame
                .store(old_pos + read_frames as i64, Ordering::Relaxed);
        }

        // Advance position
        self.current_frame
            .fetch_add(frames as i64, Ordering::Relaxed);
    }

    /// Get current position in seconds
    pub fn position_seconds(&self) -> f64 {
        self.current_frame.load(Ordering::Relaxed) as f64 / self.sample_rate as f64
    }

    /// Get stream count
    pub fn stream_count(&self) -> usize {
        self.streams.read().len()
    }
}

impl Drop for StreamingEngine {
    fn drop(&mut self) {
        self.stop();
        self.disk_reader.take(); // Triggers DiskReaderPool::drop
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// CONTROL QUEUE (Lock-Free Commands from UI → Audio)
// ═══════════════════════════════════════════════════════════════════════════

/// Control command types for audio thread
#[derive(Debug, Clone, Copy)]
#[repr(u8)]
pub enum ControlCommandType {
    Play = 0,
    Stop = 1,
    Pause = 2,
    Seek = 3,
    SetTrackMute = 4,
    SetTrackSolo = 5,
    SetTrackVolume = 6,
    SetTrackPan = 7,
    SetMasterVolume = 8,
}

/// Control command for audio thread (fixed size, no heap)
#[derive(Debug, Clone, Copy)]
#[repr(C)]
pub struct ControlCommand {
    /// Command type
    pub cmd_type: u8,
    /// Track ID (for track commands)
    pub track_id: u32,
    /// Value (frame position for seek, or float bits for volume/pan)
    pub value: i64,
}

impl ControlCommand {
    /// Create Play command
    #[inline]
    pub fn play() -> Self {
        Self {
            cmd_type: ControlCommandType::Play as u8,
            track_id: 0,
            value: 0,
        }
    }

    /// Create Stop command
    #[inline]
    pub fn stop() -> Self {
        Self {
            cmd_type: ControlCommandType::Stop as u8,
            track_id: 0,
            value: 0,
        }
    }

    /// Create Pause command
    #[inline]
    pub fn pause() -> Self {
        Self {
            cmd_type: ControlCommandType::Pause as u8,
            track_id: 0,
            value: 0,
        }
    }

    /// Create Seek command
    #[inline]
    pub fn seek(frame: i64) -> Self {
        Self {
            cmd_type: ControlCommandType::Seek as u8,
            track_id: 0,
            value: frame,
        }
    }

    /// Create SetTrackMute command
    #[inline]
    pub fn set_track_mute(track_id: u32, muted: bool) -> Self {
        Self {
            cmd_type: ControlCommandType::SetTrackMute as u8,
            track_id,
            value: muted as i64,
        }
    }

    /// Create SetTrackSolo command
    #[inline]
    pub fn set_track_solo(track_id: u32, soloed: bool) -> Self {
        Self {
            cmd_type: ControlCommandType::SetTrackSolo as u8,
            track_id,
            value: soloed as i64,
        }
    }

    /// Create SetTrackVolume command (volume as f32 bits stored in i64)
    #[inline]
    pub fn set_track_volume(track_id: u32, volume: f32) -> Self {
        Self {
            cmd_type: ControlCommandType::SetTrackVolume as u8,
            track_id,
            value: volume.to_bits() as i64,
        }
    }

    /// Create SetTrackPan command (pan as f32 bits stored in i64)
    #[inline]
    pub fn set_track_pan(track_id: u32, pan: f32) -> Self {
        Self {
            cmd_type: ControlCommandType::SetTrackPan as u8,
            track_id,
            value: pan.to_bits() as i64,
        }
    }

    /// Create SetMasterVolume command
    #[inline]
    pub fn set_master_volume(volume: f32) -> Self {
        Self {
            cmd_type: ControlCommandType::SetMasterVolume as u8,
            track_id: 0,
            value: volume.to_bits() as i64,
        }
    }
}

/// Lock-free SPSC control queue for UI → Audio commands
///
/// Uses a simple ring buffer with atomic indices.
/// UI thread writes commands, audio thread reads them.
pub struct ControlQueue {
    /// Command ring buffer (power of 2 size)
    commands: Box<[ControlCommand]>,
    /// Capacity (power of 2)
    capacity: usize,
    /// Write position (UI thread only)
    write_pos: AtomicU32,
    /// Read position (audio thread only)
    read_pos: AtomicU32,
}

impl ControlQueue {
    /// Create new control queue with given capacity (rounded up to power of 2)
    pub fn new(capacity: usize) -> Self {
        let capacity = capacity.next_power_of_two();
        let commands = vec![
            ControlCommand {
                cmd_type: 0,
                track_id: 0,
                value: 0
            };
            capacity
        ]
        .into_boxed_slice();

        Self {
            commands,
            capacity,
            write_pos: AtomicU32::new(0),
            read_pos: AtomicU32::new(0),
        }
    }

    /// Available slots for writing
    #[inline]
    pub fn available_write(&self) -> usize {
        let w = self.write_pos.load(Ordering::Relaxed) as usize;
        let r = self.read_pos.load(Ordering::Acquire) as usize;
        self.capacity - 1 - ((w.wrapping_sub(r)) & (self.capacity - 1))
    }

    /// Available commands for reading
    #[inline]
    pub fn available_read(&self) -> usize {
        let w = self.write_pos.load(Ordering::Acquire) as usize;
        let r = self.read_pos.load(Ordering::Relaxed) as usize;
        (w.wrapping_sub(r)) & (self.capacity - 1)
    }

    /// Push command to queue (UI thread)
    /// Returns true if successful, false if queue full
    #[inline]
    pub fn push(&self, cmd: ControlCommand) -> bool {
        if self.available_write() == 0 {
            return false;
        }

        let w = self.write_pos.load(Ordering::Relaxed) as usize;
        let idx = w & (self.capacity - 1);

        // SAFETY: We're the only writer (SPSC)
        unsafe {
            let ptr = self.commands.as_ptr() as *mut ControlCommand;
            std::ptr::write(ptr.add(idx), cmd);
        }

        self.write_pos.store((w + 1) as u32, Ordering::Release);
        true
    }

    /// Pop command from queue (audio thread)
    /// Returns None if queue empty
    #[inline]
    pub fn pop(&self) -> Option<ControlCommand> {
        if self.available_read() == 0 {
            return None;
        }

        let r = self.read_pos.load(Ordering::Relaxed) as usize;
        let idx = r & (self.capacity - 1);

        let cmd = self.commands[idx];

        self.read_pos.store((r + 1) as u32, Ordering::Release);
        Some(cmd)
    }

    /// Drain all available commands (audio thread)
    /// Calls handler for each command
    #[inline]
    pub fn drain<F>(&self, mut handler: F)
    where
        F: FnMut(ControlCommand),
    {
        while let Some(cmd) = self.pop() {
            handler(cmd);
        }
    }
}

// SAFETY: ControlQueue is SPSC - write side UI only, read side audio only
unsafe impl Send for ControlQueue {}
unsafe impl Sync for ControlQueue {}

// ═══════════════════════════════════════════════════════════════════════════
// AUDIO EVENT (Non-Destructive Timeline Reference)
// ═══════════════════════════════════════════════════════════════════════════

/// Non-destructive audio event on timeline
///
/// One audio file can have multiple events (instances) on the timeline.
/// This is the "clip" in DAW terminology.
#[derive(Debug, Clone)]
pub struct AudioEvent {
    /// Unique event ID
    pub event_id: u32,
    /// Asset ID (source audio file)
    pub asset_id: u32,
    /// Track ID this event belongs to
    pub track_id: u32,
    /// Timeline start position (frames)
    pub tl_start: i64,
    /// Event length (frames)
    pub length: i64,
    /// Source file offset (frames) - for trimmed clips
    pub src_start: i64,
    /// Clip gain (linear 0.0 - 2.0)
    pub gain: f32,
    /// Fade in length (frames)
    pub fade_in: i64,
    /// Fade out length (frames)
    pub fade_out: i64,
    /// Is event muted
    pub muted: bool,
}

impl AudioEvent {
    /// Calculate timeline end position
    #[inline]
    pub fn tl_end(&self) -> i64 {
        self.tl_start + self.length
    }

    /// Check if event overlaps with given timeline range
    #[inline]
    pub fn overlaps(&self, range_start: i64, range_end: i64) -> bool {
        self.tl_start < range_end && self.tl_end() > range_start
    }

    /// Calculate fade gain at given position within event
    #[inline]
    pub fn fade_gain_at(&self, local_frame: i64) -> f32 {
        let mut gain = 1.0f32;

        // Fade in
        if self.fade_in > 0 && local_frame < self.fade_in {
            gain *= local_frame as f32 / self.fade_in as f32;
        }

        // Fade out
        let frames_from_end = self.length - local_frame;
        if self.fade_out > 0 && frames_from_end < self.fade_out {
            gain *= frames_from_end as f32 / self.fade_out as f32;
        }

        gain
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_ring_buffer_basic() {
        let rb = AudioRingBuffer::new(1024, 2);

        assert_eq!(rb.available_read(), 0);
        assert_eq!(rb.available_write(), 1023);

        let input = vec![1.0f32; 256 * 2];
        let written = rb.write(&input, 256);
        assert_eq!(written, 256);
        assert_eq!(rb.available_read(), 256);

        let mut output = vec![0.0f32; 256 * 2];
        let read = rb.read(&mut output, 256);
        assert_eq!(read, 256);
        assert_eq!(rb.available_read(), 0);
    }

    #[test]
    fn test_ring_buffer_wrap() {
        let rb = AudioRingBuffer::new(64, 2);

        // Fill partially
        let input = vec![1.0f32; 32 * 2];
        rb.write(&input, 32);

        // Read some
        let mut output = vec![0.0f32; 16 * 2];
        rb.read(&mut output, 16);

        // Write more (should wrap)
        let input2 = vec![2.0f32; 32 * 2];
        let written = rb.write(&input2, 32);
        assert_eq!(written, 32);

        // Should have 16 + 32 = 48 frames
        assert_eq!(rb.available_read(), 48);
    }

    #[test]
    fn test_stream_state() {
        let stream = StreamRT::new(1, 1, 1, 0, 48000, 0, 1.0, 2);

        assert_eq!(stream.get_state(), StreamState::Stopped);

        stream.set_state(StreamState::Running);
        assert_eq!(stream.get_state(), StreamState::Running);

        assert!(stream.is_active_at(24000));
        assert!(!stream.is_active_at(50000));
    }

    #[test]
    fn test_priority_calculation() {
        // Urgent case
        let urgent = DiskJob::calculate_priority(100, 0, 0);

        // Normal case
        let normal = DiskJob::calculate_priority(12000, 0, 0);

        // Far in future
        let future = DiskJob::calculate_priority(12000, 100000, 0);

        assert!(urgent > normal);
        assert!(normal > future);
    }
}
