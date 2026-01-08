//! Audio frame buffers for ML processing
//!
//! Provides efficient frame-based buffering for streaming ML inference.

use std::collections::VecDeque;

/// Single audio frame for processing
#[derive(Debug, Clone)]
pub struct AudioFrame {
    /// Frame data (mono or interleaved stereo)
    pub data: Vec<f32>,
    /// Number of channels
    pub channels: usize,
    /// Sample rate
    pub sample_rate: u32,
    /// Frame index (for ordering)
    pub index: u64,
}

impl AudioFrame {
    /// Create new mono frame
    pub fn mono(data: Vec<f32>, sample_rate: u32, index: u64) -> Self {
        Self {
            data,
            channels: 1,
            sample_rate,
            index,
        }
    }

    /// Create new stereo frame (interleaved)
    pub fn stereo(data: Vec<f32>, sample_rate: u32, index: u64) -> Self {
        Self {
            data,
            channels: 2,
            sample_rate,
            index,
        }
    }

    /// Number of samples per channel
    pub fn samples_per_channel(&self) -> usize {
        self.data.len() / self.channels
    }

    /// Get left channel (for stereo)
    pub fn left(&self) -> impl Iterator<Item = f32> + '_ {
        self.data.iter().step_by(self.channels).copied()
    }

    /// Get right channel (for stereo, returns copy of left for mono)
    pub fn right(&self) -> Vec<f32> {
        if self.channels >= 2 {
            self.data.iter().skip(1).step_by(self.channels).copied().collect()
        } else {
            // Mono: return left channel
            self.data.iter().copied().collect()
        }
    }

    /// Convert to mono (average channels)
    pub fn to_mono(&self) -> Vec<f32> {
        if self.channels == 1 {
            return self.data.clone();
        }

        let samples = self.samples_per_channel();
        let mut mono = Vec::with_capacity(samples);

        for i in 0..samples {
            let mut sum = 0.0;
            for ch in 0..self.channels {
                sum += self.data[i * self.channels + ch];
            }
            mono.push(sum / self.channels as f32);
        }

        mono
    }

    /// Deinterleave to separate channels
    pub fn deinterleave(&self) -> Vec<Vec<f32>> {
        let samples = self.samples_per_channel();
        let mut channels = vec![Vec::with_capacity(samples); self.channels];

        for i in 0..samples {
            for ch in 0..self.channels {
                channels[ch].push(self.data[i * self.channels + ch]);
            }
        }

        channels
    }

    /// Interleave separate channels
    pub fn interleave(channels: &[Vec<f32>], sample_rate: u32, index: u64) -> Self {
        let num_channels = channels.len();
        let samples = channels.first().map(|c| c.len()).unwrap_or(0);
        let mut data = Vec::with_capacity(samples * num_channels);

        for i in 0..samples {
            for ch in channels {
                data.push(ch.get(i).copied().unwrap_or(0.0));
            }
        }

        Self {
            data,
            channels: num_channels,
            sample_rate,
            index,
        }
    }
}

/// Ring buffer for frame-based streaming
pub struct FrameBuffer {
    /// Internal buffer
    buffer: VecDeque<f32>,
    /// Frame size
    frame_size: usize,
    /// Hop size (overlap = frame_size - hop_size)
    hop_size: usize,
    /// Number of channels
    channels: usize,
    /// Sample rate
    sample_rate: u32,
    /// Current frame index
    frame_index: u64,
    /// Total samples processed
    samples_processed: u64,
}

impl FrameBuffer {
    /// Create new frame buffer
    pub fn new(frame_size: usize, hop_size: usize, channels: usize, sample_rate: u32) -> Self {
        Self {
            buffer: VecDeque::with_capacity(frame_size * channels * 2),
            frame_size,
            hop_size,
            channels,
            sample_rate,
            frame_index: 0,
            samples_processed: 0,
        }
    }

    /// Push samples into buffer
    pub fn push(&mut self, samples: &[f32]) {
        self.buffer.extend(samples);
        self.samples_processed += samples.len() as u64;
    }

    /// Check if a full frame is available
    pub fn has_frame(&self) -> bool {
        self.buffer.len() >= self.frame_size * self.channels
    }

    /// Pop next frame (with overlap handling)
    pub fn pop_frame(&mut self) -> Option<AudioFrame> {
        if !self.has_frame() {
            return None;
        }

        // Extract frame data
        let frame_samples = self.frame_size * self.channels;
        let data: Vec<f32> = self.buffer.iter().take(frame_samples).copied().collect();

        // Advance by hop_size (not frame_size) to handle overlap
        let hop_samples = self.hop_size * self.channels;
        self.buffer.drain(..hop_samples);

        let frame = AudioFrame {
            data,
            channels: self.channels,
            sample_rate: self.sample_rate,
            index: self.frame_index,
        };

        self.frame_index += 1;
        Some(frame)
    }

    /// Flush remaining samples (zero-pad if needed)
    pub fn flush(&mut self) -> Option<AudioFrame> {
        if self.buffer.is_empty() {
            return None;
        }

        let frame_samples = self.frame_size * self.channels;
        let mut data: Vec<f32> = self.buffer.drain(..).collect();

        // Zero-pad to frame size
        data.resize(frame_samples, 0.0);

        let frame = AudioFrame {
            data,
            channels: self.channels,
            sample_rate: self.sample_rate,
            index: self.frame_index,
        };

        self.frame_index += 1;
        Some(frame)
    }

    /// Reset buffer state
    pub fn reset(&mut self) {
        self.buffer.clear();
        self.frame_index = 0;
        self.samples_processed = 0;
    }

    /// Current buffer length in samples
    pub fn len(&self) -> usize {
        self.buffer.len() / self.channels
    }

    /// Check if buffer is empty
    pub fn is_empty(&self) -> bool {
        self.buffer.is_empty()
    }

    /// Latency in samples
    pub fn latency_samples(&self) -> usize {
        self.frame_size
    }

    /// Latency in milliseconds
    pub fn latency_ms(&self) -> f64 {
        self.frame_size as f64 / self.sample_rate as f64 * 1000.0
    }

    /// Total samples processed
    pub fn total_samples(&self) -> u64 {
        self.samples_processed
    }

    /// Total frames produced
    pub fn total_frames(&self) -> u64 {
        self.frame_index
    }
}

/// Overlap-add output buffer
pub struct OverlapAddBuffer {
    /// Internal buffer
    buffer: Vec<f32>,
    /// Frame size
    frame_size: usize,
    /// Hop size
    hop_size: usize,
    /// Current write position
    write_pos: usize,
    /// Current read position
    read_pos: usize,
    /// Window function for overlap-add
    window: Vec<f32>,
}

impl OverlapAddBuffer {
    /// Create new overlap-add buffer
    pub fn new(frame_size: usize, hop_size: usize) -> Self {
        // Create Hann window for overlap-add
        let window: Vec<f32> = (0..frame_size)
            .map(|i| {
                let phase = std::f32::consts::PI * i as f32 / frame_size as f32;
                phase.sin().powi(2)
            })
            .collect();

        Self {
            buffer: vec![0.0; frame_size * 4], // 4x frame size for safety
            frame_size,
            hop_size,
            write_pos: 0,
            read_pos: 0,
            window,
        }
    }

    /// Add frame with overlap
    pub fn add_frame(&mut self, frame: &[f32]) {
        assert_eq!(frame.len(), self.frame_size);

        // Apply window and add to buffer
        for (i, &sample) in frame.iter().enumerate() {
            let buf_pos = (self.write_pos + i) % self.buffer.len();
            self.buffer[buf_pos] += sample * self.window[i];
        }

        // Advance write position by hop size
        self.write_pos = (self.write_pos + self.hop_size) % self.buffer.len();
    }

    /// Read available output samples
    pub fn read(&mut self, output: &mut [f32]) -> usize {
        let available = self.available();
        let to_read = output.len().min(available);

        for i in 0..to_read {
            let buf_pos = (self.read_pos + i) % self.buffer.len();
            output[i] = self.buffer[buf_pos];
            self.buffer[buf_pos] = 0.0; // Clear after reading
        }

        self.read_pos = (self.read_pos + to_read) % self.buffer.len();
        to_read
    }

    /// Available samples to read
    pub fn available(&self) -> usize {
        if self.write_pos >= self.read_pos {
            self.write_pos - self.read_pos
        } else {
            self.buffer.len() - self.read_pos + self.write_pos
        }
    }

    /// Reset buffer
    pub fn reset(&mut self) {
        self.buffer.fill(0.0);
        self.write_pos = 0;
        self.read_pos = 0;
    }
}

/// STFT analysis buffer
pub struct StftBuffer {
    /// Frame buffer for input
    frame_buffer: FrameBuffer,
    /// Window function
    window: Vec<f32>,
    /// FFT planner
    fft: std::sync::Arc<dyn realfft::RealToComplex<f32>>,
    /// Scratch buffer for FFT
    scratch: Vec<num_complex::Complex32>,
}

impl StftBuffer {
    /// Create new STFT buffer
    pub fn new(fft_size: usize, hop_size: usize, sample_rate: u32) -> Self {
        use realfft::RealFftPlanner;

        // Create Hann window
        let window: Vec<f32> = (0..fft_size)
            .map(|i| {
                0.5 * (1.0 - (2.0 * std::f32::consts::PI * i as f32 / fft_size as f32).cos())
            })
            .collect();

        let mut planner = RealFftPlanner::new();
        let fft = planner.plan_fft_forward(fft_size);

        let scratch_len = fft.get_scratch_len();
        let scratch = vec![num_complex::Complex32::new(0.0, 0.0); scratch_len];

        Self {
            frame_buffer: FrameBuffer::new(fft_size, hop_size, 1, sample_rate),
            window,
            fft,
            scratch,
        }
    }

    /// Push samples
    pub fn push(&mut self, samples: &[f32]) {
        self.frame_buffer.push(samples);
    }

    /// Compute next STFT frame
    pub fn next_frame(&mut self) -> Option<Vec<num_complex::Complex32>> {
        let frame = self.frame_buffer.pop_frame()?;

        // Apply window
        let mut windowed: Vec<f32> = frame
            .data
            .iter()
            .zip(self.window.iter())
            .map(|(&s, &w)| s * w)
            .collect();

        // Compute FFT
        let spectrum_len = self.fft.len() / 2 + 1;
        let mut spectrum = vec![num_complex::Complex32::new(0.0, 0.0); spectrum_len];

        self.fft
            .process_with_scratch(&mut windowed, &mut spectrum, &mut self.scratch)
            .ok()?;

        Some(spectrum)
    }

    /// FFT size
    pub fn fft_size(&self) -> usize {
        self.window.len()
    }

    /// Frequency resolution
    pub fn freq_resolution(&self) -> f32 {
        self.frame_buffer.sample_rate as f32 / self.fft_size() as f32
    }

    /// Has frame available
    pub fn has_frame(&self) -> bool {
        self.frame_buffer.has_frame()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_frame_buffer() {
        let mut buffer = FrameBuffer::new(256, 128, 1, 48000);

        // Push less than frame
        buffer.push(&vec![0.0; 100]);
        assert!(!buffer.has_frame());

        // Push more to complete frame
        buffer.push(&vec![1.0; 200]);
        assert!(buffer.has_frame());

        // Pop frame
        let frame = buffer.pop_frame().unwrap();
        assert_eq!(frame.data.len(), 256);
        assert_eq!(frame.index, 0);

        // After pop, we have 300 - 128 (hop_size) = 172 samples left
        // Need 256 for next frame, so should NOT have frame
        assert!(!buffer.has_frame());

        // Push more to get another frame
        buffer.push(&vec![2.0; 128]);
        // Now we have 172 + 128 = 300 samples, should have frame
        assert!(buffer.has_frame());
    }

    #[test]
    fn test_audio_frame_stereo() {
        let data = vec![1.0, 2.0, 3.0, 4.0, 5.0, 6.0]; // 3 samples, stereo
        let frame = AudioFrame::stereo(data, 48000, 0);

        let left: Vec<f32> = frame.left().collect();
        let right: Vec<f32> = frame.right();

        assert_eq!(left, vec![1.0, 3.0, 5.0]);
        assert_eq!(right, vec![2.0, 4.0, 6.0]);
    }

    #[test]
    fn test_overlap_add() {
        let mut buffer = OverlapAddBuffer::new(256, 128);

        // Add two frames
        buffer.add_frame(&vec![1.0; 256]);
        buffer.add_frame(&vec![1.0; 256]);

        // Should have hop_size samples available after second frame
        assert!(buffer.available() >= 128);
    }
}
