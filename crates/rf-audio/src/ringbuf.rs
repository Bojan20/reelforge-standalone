//! Lock-Free Ring Buffers for Audio Communication
//!
//! Provides thread-safe, lock-free data transfer between:
//! - Audio thread ↔ UI thread (metering, waveforms)
//! - Audio thread ↔ Disk thread (streaming)
//! - Audio thread ↔ Processing thread (DSP data)
//!
//! CRITICAL: Audio thread must NEVER block. All operations are wait-free.

use std::sync::atomic::{AtomicUsize, Ordering};

use rf_core::Sample;

// ═══════════════════════════════════════════════════════════════════════════════
// SPSC AUDIO RING BUFFER
// ═══════════════════════════════════════════════════════════════════════════════

/// Single-Producer Single-Consumer ring buffer for audio samples
///
/// Wait-free for both producer and consumer.
/// Cache-line padded to prevent false sharing.
#[repr(align(64))]
pub struct AudioRingBuffer {
    /// Buffer storage
    buffer: Box<[Sample]>,
    /// Buffer capacity (power of 2)
    capacity: usize,
    /// Capacity mask for efficient modulo
    mask: usize,
    /// Write position (only modified by producer)
    write_pos: AtomicUsize,
    /// Read position (only modified by consumer)
    read_pos: AtomicUsize,
}

impl AudioRingBuffer {
    /// Create new ring buffer with given capacity (rounded up to power of 2)
    pub fn new(min_capacity: usize) -> Self {
        let capacity = min_capacity.next_power_of_two();
        let buffer = vec![0.0; capacity].into_boxed_slice();

        Self {
            buffer,
            capacity,
            mask: capacity - 1,
            write_pos: AtomicUsize::new(0),
            read_pos: AtomicUsize::new(0),
        }
    }

    /// Get available space for writing
    #[inline]
    pub fn available_write(&self) -> usize {
        let write = self.write_pos.load(Ordering::Relaxed);
        let read = self.read_pos.load(Ordering::Acquire);
        self.capacity - (write.wrapping_sub(read))
    }

    /// Get available samples for reading
    #[inline]
    pub fn available_read(&self) -> usize {
        let write = self.write_pos.load(Ordering::Acquire);
        let read = self.read_pos.load(Ordering::Relaxed);
        write.wrapping_sub(read)
    }

    /// Push samples (producer side - audio thread)
    ///
    /// Returns number of samples actually written
    #[inline]
    pub fn push(&self, samples: &[Sample]) -> usize {
        let available = self.available_write();
        let to_write = samples.len().min(available);

        if to_write == 0 {
            return 0;
        }

        let write = self.write_pos.load(Ordering::Relaxed);

        // Write samples
        for (i, &sample) in samples[..to_write].iter().enumerate() {
            let idx = (write + i) & self.mask;
            // SAFETY: We're the only producer, and idx is always in bounds
            unsafe {
                let ptr = self.buffer.as_ptr() as *mut Sample;
                ptr.add(idx).write(sample);
            }
        }

        // Update write position with release semantics
        self.write_pos
            .store(write.wrapping_add(to_write), Ordering::Release);

        to_write
    }

    /// Pop samples (consumer side - UI/disk thread)
    ///
    /// Returns number of samples actually read
    #[inline]
    pub fn pop(&self, output: &mut [Sample]) -> usize {
        let available = self.available_read();
        let to_read = output.len().min(available);

        if to_read == 0 {
            return 0;
        }

        let read = self.read_pos.load(Ordering::Relaxed);

        // Read samples
        for (i, sample) in output[..to_read].iter_mut().enumerate() {
            let idx = (read + i) & self.mask;
            *sample = self.buffer[idx];
        }

        // Update read position with release semantics
        self.read_pos
            .store(read.wrapping_add(to_read), Ordering::Release);

        to_read
    }

    /// Peek at samples without consuming them
    #[inline]
    pub fn peek(&self, output: &mut [Sample]) -> usize {
        let available = self.available_read();
        let to_read = output.len().min(available);

        if to_read == 0 {
            return 0;
        }

        let read = self.read_pos.load(Ordering::Relaxed);

        for (i, sample) in output[..to_read].iter_mut().enumerate() {
            let idx = (read + i) & self.mask;
            *sample = self.buffer[idx];
        }

        to_read
    }

    /// Clear the buffer
    pub fn clear(&self) {
        let write = self.write_pos.load(Ordering::Relaxed);
        self.read_pos.store(write, Ordering::Release);
    }

    /// Check if buffer is empty
    #[inline]
    pub fn is_empty(&self) -> bool {
        self.available_read() == 0
    }

    /// Check if buffer is full
    #[inline]
    pub fn is_full(&self) -> bool {
        self.available_write() == 0
    }

    /// Get buffer capacity
    #[inline]
    pub fn capacity(&self) -> usize {
        self.capacity
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// STEREO AUDIO RING BUFFER
// ═══════════════════════════════════════════════════════════════════════════════

/// Stereo ring buffer (separate L/R channels)
pub struct StereoRingBuffer {
    left: AudioRingBuffer,
    right: AudioRingBuffer,
}

impl StereoRingBuffer {
    pub fn new(min_capacity: usize) -> Self {
        Self {
            left: AudioRingBuffer::new(min_capacity),
            right: AudioRingBuffer::new(min_capacity),
        }
    }

    /// Push stereo samples
    pub fn push_stereo(&self, left: &[Sample], right: &[Sample]) -> usize {
        let len = left.len().min(right.len());
        let written_l = self.left.push(&left[..len]);
        let written_r = self.right.push(&right[..len]);
        written_l.min(written_r)
    }

    /// Push interleaved stereo samples
    pub fn push_interleaved(&self, samples: &[Sample]) -> usize {
        let frames = samples.len() / 2;
        let available = self
            .left
            .available_write()
            .min(self.right.available_write());
        let to_write = frames.min(available);

        if to_write == 0 {
            return 0;
        }

        // Deinterleave and push
        let mut left_buf = vec![0.0; to_write];
        let mut right_buf = vec![0.0; to_write];

        for i in 0..to_write {
            left_buf[i] = samples[i * 2];
            right_buf[i] = samples[i * 2 + 1];
        }

        self.left.push(&left_buf);
        self.right.push(&right_buf);

        to_write
    }

    /// Pop stereo samples
    pub fn pop_stereo(&self, left: &mut [Sample], right: &mut [Sample]) -> usize {
        let len = left.len().min(right.len());
        let read_l = self.left.pop(&mut left[..len]);
        let read_r = self.right.pop(&mut right[..len]);
        read_l.min(read_r)
    }

    /// Pop as interleaved stereo
    pub fn pop_interleaved(&self, output: &mut [Sample]) -> usize {
        let frames = output.len() / 2;
        let available = self.left.available_read().min(self.right.available_read());
        let to_read = frames.min(available);

        if to_read == 0 {
            return 0;
        }

        let mut left_buf = vec![0.0; to_read];
        let mut right_buf = vec![0.0; to_read];

        self.left.pop(&mut left_buf);
        self.right.pop(&mut right_buf);

        for i in 0..to_read {
            output[i * 2] = left_buf[i];
            output[i * 2 + 1] = right_buf[i];
        }

        to_read
    }

    pub fn available_read(&self) -> usize {
        self.left.available_read().min(self.right.available_read())
    }

    pub fn available_write(&self) -> usize {
        self.left
            .available_write()
            .min(self.right.available_write())
    }

    pub fn clear(&self) {
        self.left.clear();
        self.right.clear();
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// COMMAND RING BUFFER (for control messages)
// ═══════════════════════════════════════════════════════════════════════════════

/// Parameter change command
#[derive(Debug, Clone, Copy)]
pub struct ParamChange {
    /// Parameter ID
    pub id: u32,
    /// New value (normalized 0.0 - 1.0)
    pub value: f64,
    /// Timestamp (sample position)
    pub timestamp: u64,
}

/// Command from UI to audio thread
#[derive(Debug, Clone, Copy)]
pub enum AudioCommand {
    /// Set parameter value
    SetParam(ParamChange),
    /// Set playback position
    Seek(u64),
    /// Start playback
    Play,
    /// Pause playback
    Pause,
    /// Stop and reset
    Stop,
    /// Bypass processing
    Bypass(bool),
}

/// Ring buffer for commands (UI → Audio)
pub struct CommandRingBuffer {
    commands: Box<[Option<AudioCommand>]>,
    capacity: usize,
    mask: usize,
    write_pos: AtomicUsize,
    read_pos: AtomicUsize,
}

impl CommandRingBuffer {
    pub fn new(min_capacity: usize) -> Self {
        let capacity = min_capacity.next_power_of_two();
        let commands = vec![None; capacity].into_boxed_slice();

        Self {
            commands,
            capacity,
            mask: capacity - 1,
            write_pos: AtomicUsize::new(0),
            read_pos: AtomicUsize::new(0),
        }
    }

    /// Push command (UI thread)
    pub fn push(&self, command: AudioCommand) -> bool {
        let write = self.write_pos.load(Ordering::Relaxed);
        let read = self.read_pos.load(Ordering::Acquire);

        if write.wrapping_sub(read) >= self.capacity {
            return false; // Full
        }

        let idx = write & self.mask;

        // SAFETY: We're the only producer
        unsafe {
            let ptr = self.commands.as_ptr() as *mut Option<AudioCommand>;
            ptr.add(idx).write(Some(command));
        }

        self.write_pos
            .store(write.wrapping_add(1), Ordering::Release);
        true
    }

    /// Pop command (Audio thread)
    pub fn pop(&self) -> Option<AudioCommand> {
        let write = self.write_pos.load(Ordering::Acquire);
        let read = self.read_pos.load(Ordering::Relaxed);

        if write == read {
            return None; // Empty
        }

        let idx = read & self.mask;
        let command = self.commands[idx];

        self.read_pos.store(read.wrapping_add(1), Ordering::Release);
        command
    }

    /// Process all pending commands
    pub fn drain<F>(&self, mut handler: F)
    where
        F: FnMut(AudioCommand),
    {
        while let Some(cmd) = self.pop() {
            handler(cmd);
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// METERING RING BUFFER
// ═══════════════════════════════════════════════════════════════════════════════

/// Metering snapshot
#[derive(Debug, Clone, Copy, Default)]
pub struct MeterSnapshot {
    /// Left peak
    pub peak_l: f32,
    /// Right peak
    pub peak_r: f32,
    /// Left RMS
    pub rms_l: f32,
    /// Right RMS
    pub rms_r: f32,
    /// Timestamp (sample position)
    pub timestamp: u64,
}

/// Ring buffer for metering data (Audio → UI)
#[allow(dead_code)]
pub struct MeterRingBuffer {
    snapshots: Box<[MeterSnapshot]>,
    capacity: usize,
    mask: usize,
    write_pos: AtomicUsize,
    read_pos: AtomicUsize,
}

impl MeterRingBuffer {
    pub fn new(min_capacity: usize) -> Self {
        let capacity = min_capacity.next_power_of_two();
        let snapshots = vec![MeterSnapshot::default(); capacity].into_boxed_slice();

        Self {
            snapshots,
            capacity,
            mask: capacity - 1,
            write_pos: AtomicUsize::new(0),
            read_pos: AtomicUsize::new(0),
        }
    }

    /// Push metering snapshot (Audio thread)
    pub fn push(&self, snapshot: MeterSnapshot) -> bool {
        let write = self.write_pos.load(Ordering::Relaxed);
        let _read = self.read_pos.load(Ordering::Acquire);

        // Allow overwrite if full (UI can skip frames)
        let idx = write & self.mask;

        unsafe {
            let ptr = self.snapshots.as_ptr() as *mut MeterSnapshot;
            ptr.add(idx).write(snapshot);
        }

        self.write_pos
            .store(write.wrapping_add(1), Ordering::Release);
        true
    }

    /// Get latest snapshot (UI thread)
    pub fn latest(&self) -> Option<MeterSnapshot> {
        let write = self.write_pos.load(Ordering::Acquire);
        let read = self.read_pos.load(Ordering::Relaxed);

        if write == read {
            return None;
        }

        // Get the most recent
        let idx = (write.wrapping_sub(1)) & self.mask;
        let snapshot = self.snapshots[idx];

        // Mark as read
        self.read_pos.store(write, Ordering::Release);

        Some(snapshot)
    }

    /// Drain all snapshots
    pub fn drain<F>(&self, mut handler: F)
    where
        F: FnMut(MeterSnapshot),
    {
        let write = self.write_pos.load(Ordering::Acquire);
        let mut read = self.read_pos.load(Ordering::Relaxed);

        while read != write {
            let idx = read & self.mask;
            handler(self.snapshots[idx]);
            read = read.wrapping_add(1);
        }

        self.read_pos.store(write, Ordering::Release);
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_audio_ring_buffer_basic() {
        let buffer = AudioRingBuffer::new(1024);

        assert_eq!(buffer.capacity(), 1024);
        assert!(buffer.is_empty());
        assert!(!buffer.is_full());

        let samples = [1.0, 2.0, 3.0, 4.0];
        let written = buffer.push(&samples);
        assert_eq!(written, 4);
        assert_eq!(buffer.available_read(), 4);

        let mut output = [0.0; 4];
        let read = buffer.pop(&mut output);
        assert_eq!(read, 4);
        assert_eq!(output, samples);
    }

    #[test]
    fn test_audio_ring_buffer_wrap() {
        let buffer = AudioRingBuffer::new(8);

        // Fill buffer
        let samples: Vec<Sample> = (0..8).map(|i| i as f64).collect();
        buffer.push(&samples);

        // Read half
        let mut output = [0.0; 4];
        buffer.pop(&mut output);

        // Write more (wrapping)
        let more = [10.0, 11.0, 12.0, 13.0];
        let written = buffer.push(&more);
        assert_eq!(written, 4);

        // Read remaining
        let mut all = [0.0; 8];
        let read = buffer.pop(&mut all);
        assert_eq!(read, 8);
        assert_eq!(&all[..4], &[4.0, 5.0, 6.0, 7.0]);
        assert_eq!(&all[4..], &[10.0, 11.0, 12.0, 13.0]);
    }

    #[test]
    fn test_stereo_ring_buffer() {
        let buffer = StereoRingBuffer::new(1024);

        let left = [1.0, 2.0, 3.0, 4.0];
        let right = [5.0, 6.0, 7.0, 8.0];

        buffer.push_stereo(&left, &right);

        let mut out_l = [0.0; 4];
        let mut out_r = [0.0; 4];
        buffer.pop_stereo(&mut out_l, &mut out_r);

        assert_eq!(out_l, left);
        assert_eq!(out_r, right);
    }

    #[test]
    fn test_command_ring_buffer() {
        let buffer = CommandRingBuffer::new(32);

        assert!(buffer.push(AudioCommand::Play));
        assert!(buffer.push(AudioCommand::SetParam(ParamChange {
            id: 0,
            value: 0.5,
            timestamp: 1000,
        })));

        match buffer.pop() {
            Some(AudioCommand::Play) => {}
            _ => panic!("Expected Play command"),
        }

        match buffer.pop() {
            Some(AudioCommand::SetParam(p)) => {
                assert_eq!(p.id, 0);
                assert_eq!(p.value, 0.5);
            }
            _ => panic!("Expected SetParam command"),
        }

        assert!(buffer.pop().is_none());
    }

    #[test]
    fn test_meter_ring_buffer() {
        let buffer = MeterRingBuffer::new(32);

        buffer.push(MeterSnapshot {
            peak_l: 0.5,
            peak_r: 0.6,
            rms_l: 0.3,
            rms_r: 0.4,
            timestamp: 1000,
        });

        buffer.push(MeterSnapshot {
            peak_l: 0.7,
            peak_r: 0.8,
            rms_l: 0.5,
            rms_r: 0.6,
            timestamp: 2000,
        });

        // Latest should return most recent
        let latest = buffer.latest().unwrap();
        assert_eq!(latest.peak_l, 0.7);
        assert_eq!(latest.timestamp, 2000);
    }
}
