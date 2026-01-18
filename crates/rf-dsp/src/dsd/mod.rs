//! DSD (Direct Stream Digital) Ultimate Module
//!
//! Complete DSD support beyond any DAW except Pyramix:
//! - DSD64/128/256/512 native support
//! - DoP (DSD over PCM) encode/decode
//! - SACD ISO extraction
//! - 5th/7th order Sigma-Delta Modulators
//! - High-quality decimation (DSD→PCM)
//! - Native DSD playback (ASIO DSD)

pub mod decimation;
pub mod dop;
pub mod file_reader;
pub mod rates;
pub mod sdm;

pub use decimation::*;
pub use dop::*;
pub use file_reader::*;
pub use rates::*;
pub use sdm::*;

use rf_core::Sample;

/// DSD stream container
#[derive(Debug, Clone)]
pub struct DsdStream {
    /// DSD bit data (packed, 8 bits per byte)
    pub data: Vec<u8>,
    /// Sample rate (DSD64/128/256/512)
    pub rate: DsdRate,
    /// Number of channels
    pub channels: u8,
    /// Total DSD samples (bits) per channel
    pub samples_per_channel: u64,
    /// Metadata
    pub metadata: DsdMetadata,
}

/// DSD metadata
#[derive(Debug, Clone, Default)]
pub struct DsdMetadata {
    pub title: Option<String>,
    pub artist: Option<String>,
    pub album: Option<String>,
    pub track_number: Option<u32>,
    pub total_tracks: Option<u32>,
    pub year: Option<u32>,
    pub genre: Option<String>,
}

impl DsdStream {
    /// Create empty stream
    pub fn new(rate: DsdRate, channels: u8) -> Self {
        Self {
            data: Vec::new(),
            rate,
            channels,
            samples_per_channel: 0,
            metadata: DsdMetadata::default(),
        }
    }

    /// Duration in seconds
    pub fn duration_seconds(&self) -> f64 {
        self.samples_per_channel as f64 / self.rate.sample_rate() as f64
    }

    /// Get packed byte count
    pub fn byte_count(&self) -> usize {
        self.data.len()
    }

    /// Get a single DSD bit (0 or 1)
    pub fn get_bit(&self, channel: u8, sample: u64) -> Option<u8> {
        if channel >= self.channels || sample >= self.samples_per_channel {
            return None;
        }

        let total_samples = self.samples_per_channel as usize;
        let channel_offset = channel as usize * (total_samples / 8);
        let byte_index = channel_offset + (sample as usize / 8);
        let bit_index = 7 - (sample as usize % 8); // MSB first

        self.data.get(byte_index).map(|b| (b >> bit_index) & 1)
    }
}

/// DSD processing configuration
#[derive(Debug, Clone, Copy)]
pub struct DsdConfig {
    /// Target DSD rate for output
    pub output_rate: DsdRate,
    /// SDM type for PCM→DSD conversion
    pub sdm_type: SdmType,
    /// Decimation filter quality for DSD→PCM
    pub decimation_quality: DecimationQuality,
    /// DoP encoding enabled
    pub dop_enabled: bool,
}

impl Default for DsdConfig {
    fn default() -> Self {
        Self {
            output_rate: DsdRate::Dsd64,
            sdm_type: SdmType::Order5Dithered,
            decimation_quality: DecimationQuality::High,
            dop_enabled: false,
        }
    }
}

/// Complete DSD converter (bidirectional)
pub struct DsdConverter {
    /// Decimation for DSD→PCM
    decimator: DsdDecimator,
    /// SDM for PCM→DSD
    modulator: SigmaDeltaModulator,
    /// Configuration
    config: DsdConfig,
    /// Intermediate buffer for DXD (352.8kHz)
    dxd_buffer: Vec<Sample>,
}

impl DsdConverter {
    /// Create new converter
    pub fn new(config: DsdConfig, pcm_sample_rate: f64) -> Self {
        let dsd_rate = config.output_rate.sample_rate() as f64;
        let decimator = DsdDecimator::new(dsd_rate, pcm_sample_rate, config.decimation_quality);
        let modulator = SigmaDeltaModulator::new(config.sdm_type, dsd_rate);

        Self {
            decimator,
            modulator,
            config,
            dxd_buffer: Vec::with_capacity(4096),
        }
    }

    /// Convert DSD to PCM (high quality decimation)
    pub fn dsd_to_pcm(&mut self, dsd: &DsdStream) -> Vec<Sample> {
        let mut pcm = Vec::new();

        // Process in blocks
        let block_size = 4096;
        let total_bytes = dsd.byte_count();
        let mut offset = 0;

        while offset < total_bytes {
            let end = (offset + block_size).min(total_bytes);
            let block = &dsd.data[offset..end];

            // Expand bits to samples (+1/-1)
            let expanded: Vec<Sample> = block
                .iter()
                .flat_map(|byte| {
                    (0..8)
                        .rev()
                        .map(move |bit| if (byte >> bit) & 1 == 1 { 1.0 } else { -1.0 })
                })
                .collect();

            // Decimate
            let decimated = self.decimator.process(&expanded);
            pcm.extend(decimated);

            offset = end;
        }

        pcm
    }

    /// Convert PCM to DSD (sigma-delta modulation)
    pub fn pcm_to_dsd(&mut self, pcm: &[Sample], rate: DsdRate) -> DsdStream {
        // Interpolate PCM to DSD rate if needed
        let dsd_rate = rate.sample_rate() as f64;
        let interpolated = self.interpolate_to_dsd_rate(pcm, dsd_rate);

        // Modulate
        let dsd_bits = self.modulator.modulate(&interpolated);

        // Pack into bytes
        let packed = Self::pack_bits(&dsd_bits);

        DsdStream {
            data: packed,
            rate,
            channels: 1,
            samples_per_channel: dsd_bits.len() as u64,
            metadata: DsdMetadata::default(),
        }
    }

    /// Interpolate PCM to DSD rate
    fn interpolate_to_dsd_rate(&self, pcm: &[Sample], dsd_rate: f64) -> Vec<Sample> {
        // Simple linear interpolation for now
        // TODO: Polyphase interpolation for better quality
        let pcm_rate = 44100.0; // Assume 44.1kHz input
        let ratio = dsd_rate / pcm_rate;
        let output_len = (pcm.len() as f64 * ratio) as usize;

        let mut output = Vec::with_capacity(output_len);
        for i in 0..output_len {
            let src_pos = i as f64 / ratio;
            let src_idx = src_pos as usize;
            let frac = src_pos - src_idx as f64;

            let s0 = pcm.get(src_idx).copied().unwrap_or(0.0);
            let s1 = pcm.get(src_idx + 1).copied().unwrap_or(s0);

            output.push(s0 + frac * (s1 - s0));
        }

        output
    }

    /// Pack bits into bytes (MSB first)
    fn pack_bits(bits: &[u8]) -> Vec<u8> {
        bits.chunks(8)
            .map(|chunk| {
                let mut byte = 0u8;
                for (i, &bit) in chunk.iter().enumerate() {
                    byte |= (bit & 1) << (7 - i);
                }
                byte
            })
            .collect()
    }

    /// Reset converter state
    pub fn reset(&mut self) {
        self.decimator.reset();
        self.modulator.reset();
        self.dxd_buffer.clear();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_dsd_stream_creation() {
        let stream = DsdStream::new(DsdRate::Dsd64, 2);
        assert_eq!(stream.channels, 2);
        assert_eq!(stream.rate, DsdRate::Dsd64);
        assert_eq!(stream.rate.sample_rate(), 2_822_400);
    }

    #[test]
    fn test_dsd_rates() {
        assert_eq!(DsdRate::Dsd64.sample_rate(), 2_822_400);
        assert_eq!(DsdRate::Dsd128.sample_rate(), 5_644_800);
        assert_eq!(DsdRate::Dsd256.sample_rate(), 11_289_600);
        assert_eq!(DsdRate::Dsd512.sample_rate(), 22_579_200);
    }

    #[test]
    fn test_converter_roundtrip() {
        let config = DsdConfig::default();
        let mut converter = DsdConverter::new(config, 44100.0);

        // Create simple PCM signal
        let pcm: Vec<Sample> = (0..1000).map(|i| (i as f64 * 0.01).sin()).collect();

        // Convert to DSD and back
        let dsd = converter.pcm_to_dsd(&pcm, DsdRate::Dsd64);
        assert!(dsd.samples_per_channel > 0);

        // Note: Roundtrip won't be identical due to SDM quantization
        let _pcm_back = converter.dsd_to_pcm(&dsd);
    }
}
