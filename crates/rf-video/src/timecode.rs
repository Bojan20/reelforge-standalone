//! Timecode Handling
//!
//! Professional timecode support for video sync.

use std::fmt;

use serde::{Deserialize, Serialize};

use crate::{VideoError, VideoResult};

// ============ Frame Rate ============

/// Standard frame rates
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub enum FrameRate {
    /// 23.976 fps (24000/1001) - Film pulldown
    Fps23_976,
    /// 24 fps - Film
    Fps24,
    /// 25 fps - PAL
    Fps25,
    /// 29.97 fps (30000/1001) - NTSC
    Fps29_97,
    /// 30 fps
    Fps30,
    /// 50 fps - PAL high frame rate
    Fps50,
    /// 59.94 fps - NTSC high frame rate
    Fps59_94,
    /// 60 fps
    Fps60,
    /// Custom frame rate
    Custom(f64),
}

impl FrameRate {
    /// Get frame rate as f64
    pub fn as_f64(&self) -> f64 {
        match self {
            FrameRate::Fps23_976 => 24000.0 / 1001.0,
            FrameRate::Fps24 => 24.0,
            FrameRate::Fps25 => 25.0,
            FrameRate::Fps29_97 => 30000.0 / 1001.0,
            FrameRate::Fps30 => 30.0,
            FrameRate::Fps50 => 50.0,
            FrameRate::Fps59_94 => 60000.0 / 1001.0,
            FrameRate::Fps60 => 60.0,
            FrameRate::Custom(fps) => *fps,
        }
    }

    /// Get frames per second rounded
    pub fn frames_per_second(&self) -> u32 {
        self.as_f64().round() as u32
    }

    /// Is drop frame compatible (29.97 or 59.94)
    pub fn is_drop_frame_compatible(&self) -> bool {
        matches!(self, FrameRate::Fps29_97 | FrameRate::Fps59_94)
    }

    /// Get frame duration in seconds
    pub fn frame_duration(&self) -> f64 {
        1.0 / self.as_f64()
    }

    /// Get frame duration in samples at given sample rate
    pub fn frame_duration_samples(&self, sample_rate: u32) -> f64 {
        sample_rate as f64 / self.as_f64()
    }
}

impl fmt::Display for FrameRate {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            FrameRate::Fps23_976 => write!(f, "23.976 fps"),
            FrameRate::Fps24 => write!(f, "24 fps"),
            FrameRate::Fps25 => write!(f, "25 fps"),
            FrameRate::Fps29_97 => write!(f, "29.97 fps"),
            FrameRate::Fps30 => write!(f, "30 fps"),
            FrameRate::Fps50 => write!(f, "50 fps"),
            FrameRate::Fps59_94 => write!(f, "59.94 fps"),
            FrameRate::Fps60 => write!(f, "60 fps"),
            FrameRate::Custom(fps) => write!(f, "{:.3} fps", fps),
        }
    }
}

// ============ Timecode Format ============

/// Timecode display format
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum TimecodeFormat {
    /// Non-drop frame (HH:MM:SS:FF)
    NonDropFrame,
    /// Drop frame (HH:MM:SS;FF) - for 29.97/59.94 fps
    DropFrame,
}

// ============ Timecode ============

/// Professional timecode representation
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct Timecode {
    /// Hours (0-23)
    pub hours: u8,
    /// Minutes (0-59)
    pub minutes: u8,
    /// Seconds (0-59)
    pub seconds: u8,
    /// Frames (0-fps)
    pub frames: u8,
    /// Format
    pub format: TimecodeFormat,
}

impl Timecode {
    /// Create new timecode
    pub fn new(hours: u8, minutes: u8, seconds: u8, frames: u8, format: TimecodeFormat) -> Self {
        Self {
            hours,
            minutes,
            seconds,
            frames,
            format,
        }
    }

    /// Create timecode from frame number
    pub fn from_frame_number(frame: u64, frame_rate: &FrameRate) -> Self {
        let fps = frame_rate.frames_per_second() as u64;

        match frame_rate {
            FrameRate::Fps29_97 | FrameRate::Fps59_94 => {
                // Drop frame calculation
                Self::from_frame_drop_frame(frame, frame_rate)
            }
            _ => {
                // Non-drop frame
                let total_seconds = frame / fps;
                let frames = (frame % fps) as u8;
                let seconds = (total_seconds % 60) as u8;
                let minutes = ((total_seconds / 60) % 60) as u8;
                let hours = ((total_seconds / 3600) % 24) as u8;

                Self {
                    hours,
                    minutes,
                    seconds,
                    frames,
                    format: TimecodeFormat::NonDropFrame,
                }
            }
        }
    }

    /// Convert from frame number with drop frame
    fn from_frame_drop_frame(frame: u64, frame_rate: &FrameRate) -> Self {
        let fps = frame_rate.frames_per_second() as u64;
        let drop_frames = if *frame_rate == FrameRate::Fps29_97 { 2 } else { 4 };

        // Drop frame calculation (SMPTE 12M)
        let frames_per_minute = fps * 60 - drop_frames;
        let frames_per_10_minutes = frames_per_minute * 10 + drop_frames;

        let ten_minute_chunks = frame / frames_per_10_minutes;
        let remainder = frame % frames_per_10_minutes;

        let additional_minutes = if remainder < drop_frames {
            0
        } else {
            (remainder - drop_frames) / frames_per_minute + 1
        };

        let total_minutes = ten_minute_chunks * 10 + additional_minutes;
        let total_dropped = drop_frames * (total_minutes - total_minutes / 10);

        let adjusted_frame = frame + total_dropped;

        let total_seconds = adjusted_frame / fps;
        let frames = (adjusted_frame % fps) as u8;
        let seconds = (total_seconds % 60) as u8;
        let minutes = ((total_seconds / 60) % 60) as u8;
        let hours = ((total_seconds / 3600) % 24) as u8;

        Self {
            hours,
            minutes,
            seconds,
            frames,
            format: TimecodeFormat::DropFrame,
        }
    }

    /// Convert to frame number
    pub fn to_frame_number(&self, frame_rate: &FrameRate) -> u64 {
        let fps = frame_rate.frames_per_second() as u64;

        match self.format {
            TimecodeFormat::NonDropFrame => {
                let total_seconds = self.hours as u64 * 3600
                    + self.minutes as u64 * 60
                    + self.seconds as u64;
                total_seconds * fps + self.frames as u64
            }
            TimecodeFormat::DropFrame => {
                let drop_frames = if *frame_rate == FrameRate::Fps29_97 { 2 } else { 4 };

                let total_minutes = self.hours as u64 * 60 + self.minutes as u64;
                let total_dropped = drop_frames * (total_minutes - total_minutes / 10);

                let total_seconds = self.hours as u64 * 3600
                    + self.minutes as u64 * 60
                    + self.seconds as u64;

                total_seconds * fps + self.frames as u64 - total_dropped
            }
        }
    }

    /// Parse timecode string
    /// Formats: "HH:MM:SS:FF" (NDF) or "HH:MM:SS;FF" (DF)
    pub fn parse(s: &str, format: TimecodeFormat) -> VideoResult<Self> {
        let separator = match format {
            TimecodeFormat::NonDropFrame => ':',
            TimecodeFormat::DropFrame => ';',
        };

        // Handle both separators for flexibility
        let parts: Vec<&str> = s.split(|c| c == ':' || c == ';').collect();

        if parts.len() != 4 {
            return Err(VideoError::InvalidTimecode(
                format!("Expected HH:MM:SS{}FF format, got: {}", separator, s)
            ));
        }

        let hours: u8 = parts[0].parse()
            .map_err(|_| VideoError::InvalidTimecode(format!("Invalid hours: {}", parts[0])))?;
        let minutes: u8 = parts[1].parse()
            .map_err(|_| VideoError::InvalidTimecode(format!("Invalid minutes: {}", parts[1])))?;
        let seconds: u8 = parts[2].parse()
            .map_err(|_| VideoError::InvalidTimecode(format!("Invalid seconds: {}", parts[2])))?;
        let frames: u8 = parts[3].parse()
            .map_err(|_| VideoError::InvalidTimecode(format!("Invalid frames: {}", parts[3])))?;

        if minutes > 59 || seconds > 59 {
            return Err(VideoError::InvalidTimecode(
                format!("Minutes and seconds must be < 60: {}", s)
            ));
        }

        Ok(Self {
            hours,
            minutes,
            seconds,
            frames,
            format,
        })
    }

    /// Convert to seconds
    pub fn to_seconds(&self, frame_rate: &FrameRate) -> f64 {
        let frame = self.to_frame_number(frame_rate);
        frame as f64 / frame_rate.as_f64()
    }

    /// Convert to samples
    pub fn to_samples(&self, frame_rate: &FrameRate, sample_rate: u32) -> u64 {
        let seconds = self.to_seconds(frame_rate);
        (seconds * sample_rate as f64) as u64
    }

    /// Add frames
    pub fn add_frames(&self, frames: i64, frame_rate: &FrameRate) -> Self {
        let current = self.to_frame_number(frame_rate) as i64;
        let new_frame = (current + frames).max(0) as u64;
        Self::from_frame_number(new_frame, frame_rate)
    }

    /// Subtract two timecodes (in frames)
    pub fn difference(&self, other: &Timecode, frame_rate: &FrameRate) -> i64 {
        self.to_frame_number(frame_rate) as i64 - other.to_frame_number(frame_rate) as i64
    }
}

impl fmt::Display for Timecode {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let separator = match self.format {
            TimecodeFormat::NonDropFrame => ':',
            TimecodeFormat::DropFrame => ';',
        };

        write!(
            f,
            "{:02}:{:02}:{:02}{}{:02}",
            self.hours, self.minutes, self.seconds, separator, self.frames
        )
    }
}

impl Default for Timecode {
    fn default() -> Self {
        Self {
            hours: 0,
            minutes: 0,
            seconds: 0,
            frames: 0,
            format: TimecodeFormat::NonDropFrame,
        }
    }
}

// ============ Timecode Range ============

/// Range of timecodes (for regions, selections)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TimecodeRange {
    pub start: Timecode,
    pub end: Timecode,
}

impl TimecodeRange {
    pub fn new(start: Timecode, end: Timecode) -> Self {
        Self { start, end }
    }

    /// Duration in frames
    pub fn duration_frames(&self, frame_rate: &FrameRate) -> u64 {
        let start_frame = self.start.to_frame_number(frame_rate);
        let end_frame = self.end.to_frame_number(frame_rate);
        end_frame.saturating_sub(start_frame)
    }

    /// Duration in seconds
    pub fn duration_seconds(&self, frame_rate: &FrameRate) -> f64 {
        self.duration_frames(frame_rate) as f64 / frame_rate.as_f64()
    }

    /// Check if frame is in range
    pub fn contains_frame(&self, frame: u64, frame_rate: &FrameRate) -> bool {
        let start_frame = self.start.to_frame_number(frame_rate);
        let end_frame = self.end.to_frame_number(frame_rate);
        frame >= start_frame && frame <= end_frame
    }
}

// ============ Tests ============

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_timecode_ndf() {
        let tc = Timecode::new(1, 0, 0, 0, TimecodeFormat::NonDropFrame);
        let frame = tc.to_frame_number(&FrameRate::Fps30);
        assert_eq!(frame, 30 * 60 * 60); // 1 hour at 30fps

        let back = Timecode::from_frame_number(frame, &FrameRate::Fps30);
        assert_eq!(back.hours, 1);
        assert_eq!(back.minutes, 0);
        assert_eq!(back.seconds, 0);
        assert_eq!(back.frames, 0);
    }

    #[test]
    fn test_timecode_parsing() {
        let tc = Timecode::parse("01:30:45:12", TimecodeFormat::NonDropFrame).unwrap();
        assert_eq!(tc.hours, 1);
        assert_eq!(tc.minutes, 30);
        assert_eq!(tc.seconds, 45);
        assert_eq!(tc.frames, 12);
    }

    #[test]
    fn test_timecode_display() {
        let tc = Timecode::new(1, 2, 3, 4, TimecodeFormat::NonDropFrame);
        assert_eq!(tc.to_string(), "01:02:03:04");

        let tc_df = Timecode::new(1, 2, 3, 4, TimecodeFormat::DropFrame);
        assert_eq!(tc_df.to_string(), "01:02:03;04");
    }

    #[test]
    fn test_frame_rate() {
        assert!((FrameRate::Fps29_97.as_f64() - 29.97).abs() < 0.01);
        assert!(FrameRate::Fps29_97.is_drop_frame_compatible());
        assert!(!FrameRate::Fps24.is_drop_frame_compatible());
    }
}
