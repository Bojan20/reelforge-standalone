//! Thumbnail Generation
//!
//! Generate thumbnail strips for timeline display.

use std::path::Path;

use crate::{VideoError, VideoResult};
use crate::decoder::{VideoDecoder, VideoFrame};

// ============ Thumbnail ============

/// Single thumbnail image
#[derive(Debug, Clone)]
pub struct Thumbnail {
    /// Frame number this thumbnail represents
    pub frame_number: u64,
    /// Width
    pub width: u32,
    /// Height
    pub height: u32,
    /// RGB data
    pub data: Vec<u8>,
}

impl Thumbnail {
    /// Create from video frame (scaled down)
    pub fn from_frame(frame: &VideoFrame, target_width: u32) -> Self {
        let scale = target_width as f64 / frame.width as f64;
        let target_height = (frame.height as f64 * scale) as u32;

        let mut data = Vec::with_capacity((target_width * target_height * 3) as usize);

        // Simple bilinear downscale
        for y in 0..target_height {
            for x in 0..target_width {
                let src_x = (x as f64 / scale) as u32;
                let src_y = (y as f64 / scale) as u32;
                let (r, g, b) = frame.get_pixel(src_x, src_y);
                data.push(r);
                data.push(g);
                data.push(b);
            }
        }

        Self {
            frame_number: frame.frame_number,
            width: target_width,
            height: target_height,
            data,
        }
    }

    /// Get pixel at position
    pub fn get_pixel(&self, x: u32, y: u32) -> (u8, u8, u8) {
        if x >= self.width || y >= self.height {
            return (0, 0, 0);
        }

        let offset = ((y * self.width + x) * 3) as usize;
        if offset + 2 < self.data.len() {
            (self.data[offset], self.data[offset + 1], self.data[offset + 2])
        } else {
            (0, 0, 0)
        }
    }
}

// ============ Thumbnail Strip ============

/// Strip of thumbnails for timeline display
#[derive(Debug, Clone)]
pub struct ThumbnailStrip {
    /// Thumbnails in order
    pub thumbnails: Vec<Thumbnail>,
    /// Thumbnail width
    pub width: u32,
    /// Thumbnail height
    pub height: u32,
    /// Frame interval between thumbnails
    pub interval_frames: u64,
    /// Source video duration in frames
    pub total_frames: u64,
}

impl ThumbnailStrip {
    /// Get thumbnail for frame (nearest neighbor)
    pub fn thumbnail_for_frame(&self, frame: u64) -> Option<&Thumbnail> {
        if self.thumbnails.is_empty() || self.interval_frames == 0 {
            return None;
        }

        let index = (frame / self.interval_frames) as usize;
        self.thumbnails.get(index.min(self.thumbnails.len() - 1))
    }

    /// Composite all thumbnails into single image (for GPU upload)
    pub fn composite(&self) -> CompositeImage {
        let total_width = self.width * self.thumbnails.len() as u32;
        let mut data = vec![0u8; (total_width * self.height * 3) as usize];

        for (i, thumb) in self.thumbnails.iter().enumerate() {
            let x_offset = i as u32 * self.width;

            for y in 0..self.height.min(thumb.height) {
                for x in 0..self.width.min(thumb.width) {
                    let (r, g, b) = thumb.get_pixel(x, y);
                    let dest_offset = ((y * total_width + x_offset + x) * 3) as usize;
                    if dest_offset + 2 < data.len() {
                        data[dest_offset] = r;
                        data[dest_offset + 1] = g;
                        data[dest_offset + 2] = b;
                    }
                }
            }
        }

        CompositeImage {
            width: total_width,
            height: self.height,
            data,
        }
    }
}

/// Composite image of all thumbnails
#[derive(Debug, Clone)]
pub struct CompositeImage {
    pub width: u32,
    pub height: u32,
    pub data: Vec<u8>,
}

// ============ Thumbnail Generator ============

/// Generator for video thumbnails
pub struct ThumbnailGenerator {
    /// Default thumbnail width
    pub default_width: u32,
    /// Default interval in frames
    pub default_interval: u64,
}

impl ThumbnailGenerator {
    pub fn new() -> Self {
        Self {
            default_width: 160,
            default_interval: 30, // ~1 second at 30fps
        }
    }

    /// Generate thumbnail strip for video
    pub fn generate_strip(
        &self,
        path: &Path,
        width: u32,
        interval_frames: u64,
    ) -> VideoResult<ThumbnailStrip> {
        let mut decoder = VideoDecoder::open(path)?;
        let info = decoder.info();
        let total_frames = info.duration_frames;

        let mut thumbnails = Vec::new();
        let mut current_frame = 0u64;

        while current_frame < total_frames {
            if let Some(frame) = decoder.decode_frame(current_frame)? {
                let thumb = Thumbnail::from_frame(&frame, width);
                thumbnails.push(thumb);
            }
            current_frame += interval_frames;
        }

        let height = if let Some(first) = thumbnails.first() {
            first.height
        } else {
            90 // Default height
        };

        Ok(ThumbnailStrip {
            thumbnails,
            width,
            height,
            interval_frames,
            total_frames,
        })
    }

    /// Generate single thumbnail at specific frame
    pub fn generate_single(
        &self,
        path: &Path,
        frame: u64,
        width: u32,
    ) -> VideoResult<Thumbnail> {
        let mut decoder = VideoDecoder::open(path)?;

        if let Some(video_frame) = decoder.decode_frame(frame)? {
            Ok(Thumbnail::from_frame(&video_frame, width))
        } else {
            Err(VideoError::DecodeFailed(format!("Could not decode frame {}", frame)))
        }
    }
}

impl Default for ThumbnailGenerator {
    fn default() -> Self {
        Self::new()
    }
}

// ============ Tests ============

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_thumbnail_from_frame() {
        let frame = VideoFrame {
            frame_number: 0,
            pts: 0,
            width: 1920,
            height: 1080,
            format: PixelFormat::Rgb24,
            data: vec![128; 1920 * 1080 * 3],
            stride: 1920 * 3,
        };

        let thumb = Thumbnail::from_frame(&frame, 160);

        assert_eq!(thumb.width, 160);
        assert_eq!(thumb.height, 90); // 16:9 aspect ratio
    }
}
