//! Transport utilities

use crate::TransportState;

impl TransportState {
    /// Get position in bars.beats.ticks
    pub fn position_bars_beats(&self) -> (u32, u32, u32) {
        let beats_per_second = self.tempo / 60.0;
        let total_beats = self.position_seconds * beats_per_second;
        let beats_per_bar = self.time_sig_num as f64;

        let bars = (total_beats / beats_per_bar).floor() as u32 + 1;
        let beats = (total_beats % beats_per_bar).floor() as u32 + 1;
        let ticks = ((total_beats % 1.0) * 480.0).floor() as u32;

        (bars, beats, ticks)
    }

    /// Get position as timecode (HH:MM:SS:FF)
    pub fn position_timecode(&self, fps: f64) -> (u32, u32, u32, u32) {
        let total_seconds = self.position_seconds;
        let hours = (total_seconds / 3600.0).floor() as u32;
        let minutes = ((total_seconds % 3600.0) / 60.0).floor() as u32;
        let seconds = (total_seconds % 60.0).floor() as u32;
        let frames = ((total_seconds % 1.0) * fps).floor() as u32;

        (hours, minutes, seconds, frames)
    }

    /// Format position for display
    pub fn format_bars_beats(&self) -> String {
        let (bars, beats, ticks) = self.position_bars_beats();
        format!("{:3}.{}.{:03}", bars, beats, ticks)
    }

    /// Format timecode for display
    pub fn format_timecode(&self) -> String {
        let (h, m, s, f) = self.position_timecode(30.0);
        format!("{:02}:{:02}:{:02}:{:02}", h, m, s, f)
    }
}
