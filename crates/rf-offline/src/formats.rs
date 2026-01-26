//! Output format definitions

use serde::{Deserialize, Serialize};
use super::config::DitheringMode;

/// Output audio format
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum OutputFormat {
    /// WAV (PCM)
    Wav(WavConfig),

    /// AIFF (PCM)
    Aiff(AiffConfig),

    /// FLAC (lossless)
    Flac(FlacConfig),

    /// MP3 (lossy)
    Mp3(Mp3Config),

    /// OGG Vorbis (lossy)
    Ogg(OggConfig),

    /// Opus (lossy)
    Opus(OpusConfig),

    /// AAC (lossy)
    Aac(AacConfig),
}

impl Default for OutputFormat {
    fn default() -> Self {
        Self::Wav(WavConfig::default())
    }
}

impl OutputFormat {
    /// Get file extension for this format
    pub fn extension(&self) -> &'static str {
        match self {
            Self::Wav(_) => "wav",
            Self::Aiff(_) => "aiff",
            Self::Flac(_) => "flac",
            Self::Mp3(_) => "mp3",
            Self::Ogg(_) => "ogg",
            Self::Opus(_) => "opus",
            Self::Aac(_) => "aac",
        }
    }

    /// Check if format is lossless
    pub fn is_lossless(&self) -> bool {
        matches!(self, Self::Wav(_) | Self::Aiff(_) | Self::Flac(_))
    }

    /// Create WAV 16-bit format
    pub fn wav_16() -> Self {
        Self::Wav(WavConfig { bit_depth: 16, ..Default::default() })
    }

    /// Create WAV 24-bit format
    pub fn wav_24() -> Self {
        Self::Wav(WavConfig { bit_depth: 24, ..Default::default() })
    }

    /// Create WAV 32-bit float format
    pub fn wav_32f() -> Self {
        Self::Wav(WavConfig { bit_depth: 32, float: true, ..Default::default() })
    }

    /// Create FLAC format
    pub fn flac() -> Self {
        Self::Flac(FlacConfig::default())
    }

    /// Create MP3 320kbps format
    pub fn mp3_320() -> Self {
        Self::Mp3(Mp3Config { bitrate: Mp3Bitrate::Cbr(320), ..Default::default() })
    }

    /// Create MP3 VBR format
    pub fn mp3_vbr(quality: u8) -> Self {
        Self::Mp3(Mp3Config { bitrate: Mp3Bitrate::Vbr(quality), ..Default::default() })
    }

    /// Create AIFF 16-bit format
    pub fn aiff_16() -> Self {
        Self::Aiff(AiffConfig { bit_depth: 16, ..Default::default() })
    }

    /// Create AIFF 24-bit format
    pub fn aiff_24() -> Self {
        Self::Aiff(AiffConfig { bit_depth: 24, ..Default::default() })
    }

    /// Create MP3 256kbps format
    pub fn mp3_256() -> Self {
        Self::Mp3(Mp3Config { bitrate: Mp3Bitrate::Cbr(256), ..Default::default() })
    }

    /// Create MP3 192kbps format
    pub fn mp3_192() -> Self {
        Self::Mp3(Mp3Config { bitrate: Mp3Bitrate::Cbr(192), ..Default::default() })
    }

    /// Create MP3 128kbps format
    pub fn mp3_128() -> Self {
        Self::Mp3(Mp3Config { bitrate: Mp3Bitrate::Cbr(128), ..Default::default() })
    }

    /// Create OGG Vorbis Q8 format
    pub fn ogg_q8() -> Self {
        Self::Ogg(OggConfig { quality: 8.0 })
    }

    /// Create OGG Vorbis Q6 format
    pub fn ogg_q6() -> Self {
        Self::Ogg(OggConfig { quality: 6.0 })
    }

    /// Create AAC 256kbps format
    pub fn aac_256() -> Self {
        Self::Aac(AacConfig { bitrate: 256, ..Default::default() })
    }

    /// Create AAC 192kbps format
    pub fn aac_192() -> Self {
        Self::Aac(AacConfig { bitrate: 192, ..Default::default() })
    }

    /// Create Opus 128kbps format
    pub fn opus_128() -> Self {
        Self::Opus(OpusConfig { bitrate: 128, ..Default::default() })
    }
}

/// WAV configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WavConfig {
    /// Bit depth (8, 16, 24, 32)
    pub bit_depth: u8,
    /// Float format (for 32-bit)
    pub float: bool,
    /// Dithering mode (for bit depth reduction)
    pub dithering: DitheringMode,
}

impl Default for WavConfig {
    fn default() -> Self {
        Self {
            bit_depth: 24,
            float: false,
            dithering: DitheringMode::Triangular,
        }
    }
}

/// AIFF configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AiffConfig {
    /// Bit depth (8, 16, 24, 32)
    pub bit_depth: u8,
    /// Dithering mode
    pub dithering: DitheringMode,
}

impl Default for AiffConfig {
    fn default() -> Self {
        Self {
            bit_depth: 24,
            dithering: DitheringMode::Triangular,
        }
    }
}

/// FLAC configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FlacConfig {
    /// Compression level (0-8, higher = smaller file, slower)
    pub compression_level: u8,
    /// Bit depth (16 or 24)
    pub bit_depth: u8,
    /// Dithering mode (for bit depth reduction from 32-bit)
    pub dithering: DitheringMode,
}

impl Default for FlacConfig {
    fn default() -> Self {
        Self {
            compression_level: 5,
            bit_depth: 24,
            dithering: DitheringMode::Triangular,
        }
    }
}

/// MP3 bitrate mode
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum Mp3Bitrate {
    /// Constant bitrate (kbps)
    Cbr(u16),
    /// Variable bitrate (quality 0-9, lower = better)
    Vbr(u8),
    /// Average bitrate (kbps)
    Abr(u16),
}

impl Default for Mp3Bitrate {
    fn default() -> Self {
        Self::Cbr(320)
    }
}

/// MP3 configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Mp3Config {
    /// Bitrate mode
    pub bitrate: Mp3Bitrate,
    /// Joint stereo mode
    pub joint_stereo: bool,
}

impl Default for Mp3Config {
    fn default() -> Self {
        Self {
            bitrate: Mp3Bitrate::Cbr(320),
            joint_stereo: true,
        }
    }
}

/// OGG Vorbis configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OggConfig {
    /// Quality (-1 to 10, higher = better)
    pub quality: f32,
}

impl Default for OggConfig {
    fn default() -> Self {
        Self { quality: 8.0 }
    }
}

/// Opus configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OpusConfig {
    /// Bitrate (kbps)
    pub bitrate: u16,
    /// Complexity (0-10)
    pub complexity: u8,
}

impl Default for OpusConfig {
    fn default() -> Self {
        Self {
            bitrate: 256,
            complexity: 10,
        }
    }
}

/// AAC configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AacConfig {
    /// Bitrate (kbps)
    pub bitrate: u16,
    /// Profile
    pub profile: AacProfile,
}

impl Default for AacConfig {
    fn default() -> Self {
        Self {
            bitrate: 256,
            profile: AacProfile::Lc,
        }
    }
}

/// AAC profile
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum AacProfile {
    /// Low Complexity (most compatible)
    Lc,
    /// High Efficiency v1
    HeV1,
    /// High Efficiency v2
    HeV2,
}

impl Default for AacProfile {
    fn default() -> Self {
        Self::Lc
    }
}
