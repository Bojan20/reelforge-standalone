//! Video Decoder
//!
//! Modular video decoding with optional FFmpeg backend.
//! Default: Pure Rust MP4 container parsing (metadata + placeholder frames)
//! With "ffmpeg" feature: Full codec support via FFmpeg

use std::fs::File;
use std::io::BufReader;
use std::path::Path;

use crate::timecode::FrameRate;
use crate::{VideoError, VideoInfo, VideoResult};

// ============ Pixel Format ============

/// Pixel format for decoded frames
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PixelFormat {
    Rgb24,
    Rgba32,
    Bgr24,
    Bgra32,
    Yuv420p,
    Yuv422p,
    Yuv444p,
}

impl PixelFormat {
    /// Bytes per pixel
    pub fn bytes_per_pixel(&self) -> usize {
        match self {
            PixelFormat::Rgb24 | PixelFormat::Bgr24 => 3,
            PixelFormat::Rgba32 | PixelFormat::Bgra32 => 4,
            PixelFormat::Yuv420p | PixelFormat::Yuv422p | PixelFormat::Yuv444p => 3,
        }
    }

    /// Is planar format
    pub fn is_planar(&self) -> bool {
        matches!(
            self,
            PixelFormat::Yuv420p | PixelFormat::Yuv422p | PixelFormat::Yuv444p
        )
    }
}

// ============ Video Frame ============

/// Decoded video frame
#[derive(Clone)]
pub struct VideoFrame {
    /// Frame number
    pub frame_number: u64,
    /// Presentation timestamp (microseconds)
    pub pts: i64,
    /// Width
    pub width: u32,
    /// Height
    pub height: u32,
    /// Pixel format
    pub format: PixelFormat,
    /// Raw pixel data (RGB24 after conversion)
    pub data: Vec<u8>,
    /// Stride (bytes per row)
    pub stride: usize,
}

impl VideoFrame {
    /// Create empty frame
    pub fn empty(width: u32, height: u32) -> Self {
        Self {
            frame_number: 0,
            pts: 0,
            width,
            height,
            format: PixelFormat::Rgb24,
            data: vec![0; (width * height * 3) as usize],
            stride: (width * 3) as usize,
        }
    }

    /// Create placeholder frame (colored based on frame number)
    pub fn placeholder(frame_number: u64, width: u32, height: u32) -> Self {
        let mut data = Vec::with_capacity((width * height * 3) as usize);

        // Generate gradient based on frame number
        let hue = (frame_number * 10 % 360) as f32;
        let (r, g, b) = hsv_to_rgb(hue, 0.5, 0.3);

        for _ in 0..(width * height) {
            data.push(r);
            data.push(g);
            data.push(b);
        }

        Self {
            frame_number,
            pts: frame_number as i64 * 1000,
            width,
            height,
            format: PixelFormat::Rgb24,
            data,
            stride: (width * 3) as usize,
        }
    }

    /// Get pixel at (x, y) as RGB
    pub fn get_pixel(&self, x: u32, y: u32) -> (u8, u8, u8) {
        if x >= self.width || y >= self.height {
            return (0, 0, 0);
        }

        let offset = (y as usize * self.stride) + (x as usize * 3);
        if offset + 2 < self.data.len() {
            (
                self.data[offset],
                self.data[offset + 1],
                self.data[offset + 2],
            )
        } else {
            (0, 0, 0)
        }
    }

    /// Convert to RGBA data (for GPU upload)
    pub fn to_rgba(&self) -> Vec<u8> {
        let mut rgba = Vec::with_capacity((self.width * self.height * 4) as usize);

        for y in 0..self.height {
            for x in 0..self.width {
                let (r, g, b) = self.get_pixel(x, y);
                rgba.push(r);
                rgba.push(g);
                rgba.push(b);
                rgba.push(255);
            }
        }

        rgba
    }
}

/// HSV to RGB conversion helper
fn hsv_to_rgb(h: f32, s: f32, v: f32) -> (u8, u8, u8) {
    let c = v * s;
    let x = c * (1.0 - ((h / 60.0) % 2.0 - 1.0).abs());
    let m = v - c;

    let (r, g, b) = if h < 60.0 {
        (c, x, 0.0)
    } else if h < 120.0 {
        (x, c, 0.0)
    } else if h < 180.0 {
        (0.0, c, x)
    } else if h < 240.0 {
        (0.0, x, c)
    } else if h < 300.0 {
        (x, 0.0, c)
    } else {
        (c, 0.0, x)
    };

    (
        ((r + m) * 255.0) as u8,
        ((g + m) * 255.0) as u8,
        ((b + m) * 255.0) as u8,
    )
}

// ============ Video Decoder ============

/// Pure Rust MP4 container decoder (metadata + placeholder frames)
/// For actual video decoding, enable the "ffmpeg" feature
pub struct VideoDecoder {
    info: VideoInfo,
    current_frame: u64,
}

impl VideoDecoder {
    pub fn open(path: &Path) -> VideoResult<Self> {
        let file = File::open(path).map_err(|e| VideoError::OpenFailed(e.to_string()))?;

        let size = file.metadata()?.len();
        let reader = BufReader::new(file);
        let mp4 = mp4::Mp4Reader::read_header(reader, size)
            .map_err(|e| VideoError::OpenFailed(e.to_string()))?;

        // Find video track
        let video_track = mp4
            .tracks()
            .values()
            .find(|t| {
                t.track_type()
                    .map(|tt| tt == mp4::TrackType::Video)
                    .unwrap_or(false)
            })
            .ok_or(VideoError::NoVideoStream)?;

        let width = video_track.width() as u32;
        let height = video_track.height() as u32;
        let duration_secs = video_track.duration().as_secs_f64();
        let frame_rate = if video_track.frame_rate() > 0.0 {
            video_track.frame_rate()
        } else {
            24.0 // Default
        };

        let duration_frames = (duration_secs * frame_rate as f64) as u64;

        let frame_rate_enum = if (frame_rate - 24.0).abs() < 0.01 {
            FrameRate::Fps24
        } else if (frame_rate - 23.976).abs() < 0.05 {
            FrameRate::Fps23_976
        } else if (frame_rate - 25.0).abs() < 0.01 {
            FrameRate::Fps25
        } else if (frame_rate - 29.97).abs() < 0.05 {
            FrameRate::Fps29_97
        } else if (frame_rate - 30.0).abs() < 0.01 {
            FrameRate::Fps30
        } else if (frame_rate - 50.0).abs() < 0.01 {
            FrameRate::Fps50
        } else if (frame_rate - 59.94).abs() < 0.05 {
            FrameRate::Fps59_94
        } else if (frame_rate - 60.0).abs() < 0.01 {
            FrameRate::Fps60
        } else {
            FrameRate::Custom(frame_rate as f64)
        };

        // Check for audio
        let has_audio = mp4.tracks().values().any(|t| {
            t.track_type()
                .map(|tt| tt == mp4::TrackType::Audio)
                .unwrap_or(false)
        });

        let (audio_sample_rate, audio_channels) = if let Some(audio_track) =
            mp4.tracks().values().find(|t| {
                t.track_type()
                    .map(|tt| tt == mp4::TrackType::Audio)
                    .unwrap_or(false)
            }) {
            let sample_rate = audio_track
                .sample_freq_index()
                .map(|idx| match idx {
                    mp4::SampleFreqIndex::Freq96000 => 96000,
                    mp4::SampleFreqIndex::Freq88200 => 88200,
                    mp4::SampleFreqIndex::Freq64000 => 64000,
                    mp4::SampleFreqIndex::Freq48000 => 48000,
                    mp4::SampleFreqIndex::Freq44100 => 44100,
                    mp4::SampleFreqIndex::Freq32000 => 32000,
                    mp4::SampleFreqIndex::Freq24000 => 24000,
                    mp4::SampleFreqIndex::Freq22050 => 22050,
                    mp4::SampleFreqIndex::Freq16000 => 16000,
                    mp4::SampleFreqIndex::Freq12000 => 12000,
                    mp4::SampleFreqIndex::Freq11025 => 11025,
                    mp4::SampleFreqIndex::Freq8000 => 8000,
                    mp4::SampleFreqIndex::Freq7350 => 7350,
                })
                .unwrap_or(48000);
            let channels = audio_track
                .channel_config()
                .map(|c| match c {
                    mp4::ChannelConfig::Mono => 1,
                    mp4::ChannelConfig::Stereo => 2,
                    mp4::ChannelConfig::Three => 3,
                    mp4::ChannelConfig::Four => 4,
                    mp4::ChannelConfig::Five => 5,
                    mp4::ChannelConfig::FiveOne => 6,
                    mp4::ChannelConfig::SevenOne => 8,
                })
                .unwrap_or(2);
            (Some(sample_rate), Some(channels))
        } else {
            (None, None)
        };

        let codec = video_track
            .media_type()
            .map(|mt| format!("{:?}", mt))
            .unwrap_or_else(|_| "Unknown".into());

        let info = VideoInfo {
            path: path.to_path_buf(),
            duration_frames,
            duration_secs,
            frame_rate: frame_rate_enum,
            width,
            height,
            pixel_format: PixelFormat::Yuv420p, // Most MP4s are YUV
            codec,
            bitrate: video_track.bitrate() as u64,
            has_audio,
            audio_sample_rate,
            audio_channels,
            start_timecode: None,
        };

        Ok(Self {
            info,
            current_frame: 0,
        })
    }

    pub fn info(&self) -> &VideoInfo {
        &self.info
    }

    pub fn seek_to_frame(&mut self, frame: u64) -> VideoResult<()> {
        self.current_frame = frame.min(self.info.duration_frames.saturating_sub(1));
        Ok(())
    }

    /// Decode frame - returns placeholder without FFmpeg feature
    /// Enable "ffmpeg" feature for actual video decoding
    pub fn decode_frame(&mut self, frame: u64) -> VideoResult<Option<VideoFrame>> {
        self.current_frame = frame;
        // Return placeholder frame - actual decoding requires FFmpeg
        Ok(Some(VideoFrame::placeholder(
            frame,
            self.info.width,
            self.info.height,
        )))
    }

    pub fn frame_count(&self) -> u64 {
        self.info.duration_frames
    }

    pub fn current_frame(&self) -> u64 {
        self.current_frame
    }
}

// ============ FFmpeg Decoder (optional) ============

#[cfg(feature = "ffmpeg")]
pub mod ffmpeg_backend {
    use super::*;

    /// FFmpeg-based video decoder with full codec support
    pub struct FfmpegDecoder {
        info: VideoInfo,
        input: ffmpeg_next::format::context::Input,
        stream_index: usize,
        decoder: ffmpeg_next::codec::decoder::Video,
        scaler: ffmpeg_next::software::scaling::Context,
        current_frame: u64,
        time_base: ffmpeg_next::Rational,
    }

    impl FfmpegDecoder {
        pub fn open(path: &Path) -> VideoResult<Self> {
            ffmpeg_next::init().map_err(|e| VideoError::FfmpegError(e.to_string()))?;

            let input = ffmpeg_next::format::input(path)
                .map_err(|e| VideoError::OpenFailed(e.to_string()))?;

            let stream = input
                .streams()
                .best(ffmpeg_next::media::Type::Video)
                .ok_or(VideoError::NoVideoStream)?;

            let stream_index = stream.index();
            let time_base = stream.time_base();

            let codec_params = stream.parameters();
            let codec = ffmpeg_next::codec::Context::from_parameters(codec_params)
                .map_err(|e| VideoError::FfmpegError(e.to_string()))?;

            let decoder = codec
                .decoder()
                .video()
                .map_err(|e| VideoError::FfmpegError(e.to_string()))?;

            let width = decoder.width();
            let height = decoder.height();
            let src_format = decoder.format();

            let scaler = ffmpeg_next::software::scaling::Context::get(
                src_format,
                width,
                height,
                ffmpeg_next::format::Pixel::RGB24,
                width,
                height,
                ffmpeg_next::software::scaling::Flags::BILINEAR,
            )
            .map_err(|e| VideoError::FfmpegError(e.to_string()))?;

            let frame_rate = stream.rate();
            let fps = frame_rate.0 as f64 / frame_rate.1 as f64;

            let frame_rate_enum = if (fps - 24.0).abs() < 0.01 {
                FrameRate::Fps24
            } else if (fps - 23.976).abs() < 0.05 {
                FrameRate::Fps23_976
            } else if (fps - 25.0).abs() < 0.01 {
                FrameRate::Fps25
            } else if (fps - 29.97).abs() < 0.05 {
                FrameRate::Fps29_97
            } else if (fps - 30.0).abs() < 0.01 {
                FrameRate::Fps30
            } else {
                FrameRate::Custom(fps)
            };

            let duration_secs = input.duration() as f64 / ffmpeg_next::ffi::AV_TIME_BASE as f64;
            let duration_frames = (duration_secs * fps) as u64;

            let has_audio = input
                .streams()
                .best(ffmpeg_next::media::Type::Audio)
                .is_some();

            let codec_name = decoder
                .codec()
                .map(|c| c.name().to_string())
                .unwrap_or_else(|| "unknown".into());

            let pixel_format = match src_format {
                ffmpeg_next::format::Pixel::YUV420P => PixelFormat::Yuv420p,
                ffmpeg_next::format::Pixel::YUV422P => PixelFormat::Yuv422p,
                ffmpeg_next::format::Pixel::RGB24 => PixelFormat::Rgb24,
                _ => PixelFormat::Yuv420p,
            };

            let info = VideoInfo {
                path: path.to_path_buf(),
                duration_frames,
                duration_secs,
                frame_rate: frame_rate_enum,
                width,
                height,
                pixel_format,
                codec: codec_name,
                bitrate: input.bit_rate() as u64,
                has_audio,
                audio_sample_rate: None,
                audio_channels: None,
                start_timecode: None,
            };

            Ok(Self {
                info,
                input,
                stream_index,
                decoder,
                scaler,
                current_frame: 0,
                time_base,
            })
        }

        pub fn info(&self) -> &VideoInfo {
            &self.info
        }

        pub fn seek_to_frame(&mut self, frame: u64) -> VideoResult<()> {
            let fps = self.info.frame_rate.as_f64();
            let time_secs = frame as f64 / fps;
            let timestamp = (time_secs * ffmpeg_next::ffi::AV_TIME_BASE as f64) as i64;

            self.input
                .seek(timestamp, timestamp..)
                .map_err(|e| VideoError::SeekFailed(e.to_string()))?;

            self.decoder.flush();
            self.current_frame = frame;
            Ok(())
        }

        pub fn decode_frame(&mut self, frame: u64) -> VideoResult<Option<VideoFrame>> {
            if frame != self.current_frame {
                self.seek_to_frame(frame)?;
            }

            let mut decoded = ffmpeg_next::util::frame::Video::empty();
            let mut rgb_frame = ffmpeg_next::util::frame::Video::empty();

            for (stream, packet) in self.input.packets() {
                if stream.index() != self.stream_index {
                    continue;
                }

                self.decoder
                    .send_packet(&packet)
                    .map_err(|e| VideoError::DecodeFailed(e.to_string()))?;

                if self.decoder.receive_frame(&mut decoded).is_ok() {
                    self.scaler
                        .run(&decoded, &mut rgb_frame)
                        .map_err(|e| VideoError::DecodeFailed(e.to_string()))?;

                    let video_frame = VideoFrame {
                        frame_number: self.current_frame,
                        pts: decoded.timestamp().unwrap_or(0),
                        width: rgb_frame.width(),
                        height: rgb_frame.height(),
                        format: PixelFormat::Rgb24,
                        data: rgb_frame.data(0).to_vec(),
                        stride: rgb_frame.stride(0),
                    };

                    self.current_frame += 1;
                    return Ok(Some(video_frame));
                }
            }

            Ok(None)
        }

        pub fn current_frame(&self) -> u64 {
            self.current_frame
        }

        pub fn frame_count(&self) -> u64 {
            self.info.duration_frames
        }
    }
}
