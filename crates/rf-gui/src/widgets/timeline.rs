//! Timeline/Arranger Widget
//!
//! DAW-style timeline with:
//! - Multi-track arrangement view
//! - Clip/region display with waveforms
//! - Playhead and locators
//! - Grid snapping
//! - Zoom and scroll navigation
//! - Track headers with solo/mute/arm

use iced::advanced::layout::{self, Layout};
use iced::advanced::renderer;
use iced::advanced::widget::{self, Widget};
use iced::advanced::{Clipboard, Shell};
use iced::mouse;
use iced::{Element, Event, Length, Rectangle, Size};

use crate::theme::Palette;
use super::waveform::WaveformPoint;

// ═══════════════════════════════════════════════════════════════════════════════
// TIMELINE TYPES
// ═══════════════════════════════════════════════════════════════════════════════

/// Snap grid mode
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum SnapMode {
    #[default]
    Off,
    Bar,
    Beat,
    Subdivision,
    Samples,
}

/// Timeline grid display mode
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum GridMode {
    #[default]
    BarsBeats,
    Timecode,
    Samples,
}

/// Track type for display
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum TimelineTrackType {
    #[default]
    Audio,
    Midi,
    Instrument,
    Bus,
    Master,
}

/// A clip/region on the timeline
#[derive(Debug, Clone)]
pub struct TimelineClip {
    pub id: String,
    pub name: String,
    /// Start position in samples
    pub position: u64,
    /// Length in samples
    pub length: u64,
    /// Offset into source
    pub source_offset: u64,
    /// Gain in dB
    pub gain_db: f64,
    /// Fade in length (samples)
    pub fade_in: u64,
    /// Fade out length (samples)
    pub fade_out: u64,
    /// Waveform data for display
    pub waveform: Vec<WaveformPoint>,
    /// Clip color
    pub color: Option<u32>,
    /// Is selected
    pub selected: bool,
    /// Is muted
    pub muted: bool,
}

impl TimelineClip {
    pub fn new(id: &str, name: &str, position: u64, length: u64) -> Self {
        Self {
            id: id.to_string(),
            name: name.to_string(),
            position,
            length,
            source_offset: 0,
            gain_db: 0.0,
            fade_in: 0,
            fade_out: 0,
            waveform: Vec::new(),
            color: None,
            selected: false,
            muted: false,
        }
    }

    /// End position in samples
    pub fn end_position(&self) -> u64 {
        self.position + self.length
    }
}

/// A track in the timeline
#[derive(Debug, Clone)]
pub struct TimelineTrack {
    pub id: String,
    pub name: String,
    pub track_type: TimelineTrackType,
    pub height: f32,
    pub color: Option<u32>,
    pub mute: bool,
    pub solo: bool,
    pub armed: bool,
    pub clips: Vec<TimelineClip>,
    /// Expanded (show automation lanes)
    pub expanded: bool,
}

impl TimelineTrack {
    pub fn new(id: &str, name: &str) -> Self {
        Self {
            id: id.to_string(),
            name: name.to_string(),
            track_type: TimelineTrackType::Audio,
            height: 80.0,
            color: None,
            mute: false,
            solo: false,
            armed: false,
            clips: Vec::new(),
            expanded: false,
        }
    }

    pub fn track_type(mut self, track_type: TimelineTrackType) -> Self {
        self.track_type = track_type;
        self
    }

    pub fn add_clip(mut self, clip: TimelineClip) -> Self {
        self.clips.push(clip);
        self
    }
}

/// Timeline messages
#[derive(Debug, Clone)]
pub enum TimelineMessage {
    /// Seek playhead to position (samples)
    SeekTo(u64),
    /// Select track by index
    SelectTrack(usize),
    /// Select clip (track_idx, clip_idx)
    SelectClip(usize, usize),
    /// Move clip (track_idx, clip_idx, new_position)
    MoveClip(usize, usize, u64),
    /// Resize clip (track_idx, clip_idx, new_length)
    ResizeClip(usize, usize, u64),
    /// Toggle track mute
    ToggleMute(usize),
    /// Toggle track solo
    ToggleSolo(usize),
    /// Toggle track arm
    ToggleArm(usize),
    /// Set loop region (start, end)
    SetLoopRegion(u64, u64),
    /// Zoom changed (samples per pixel)
    ZoomChanged(f64),
    /// Scroll changed (position in samples)
    ScrollChanged(u64),
    /// Track height changed
    TrackHeightChanged(usize, f32),
}

// ═══════════════════════════════════════════════════════════════════════════════
// TIMELINE WIDGET
// ═══════════════════════════════════════════════════════════════════════════════

/// Timeline arranger widget
pub struct Timeline<'a, Message> {
    /// Tracks
    tracks: &'a [TimelineTrack],
    /// Playhead position (samples)
    playhead: u64,
    /// Sample rate
    sample_rate: u32,
    /// Tempo (BPM)
    tempo: f64,
    /// Time signature numerator
    time_sig_num: u8,
    /// Time signature denominator
    time_sig_denom: u8,
    /// Zoom (samples per pixel)
    samples_per_pixel: f64,
    /// Horizontal scroll position (samples)
    scroll_samples: u64,
    /// Vertical scroll (pixels)
    scroll_y: f32,
    /// Total duration (samples)
    total_duration: u64,
    /// Loop enabled
    loop_enabled: bool,
    /// Loop start (samples)
    loop_start: u64,
    /// Loop end (samples)
    loop_end: u64,
    /// Snap mode
    snap_mode: SnapMode,
    /// Grid mode
    grid_mode: GridMode,
    /// Track header width
    header_width: f32,
    /// Ruler height
    ruler_height: f32,
    /// Selected track index
    selected_track: Option<usize>,
    /// Widget dimensions
    width: f32,
    height: f32,
    /// Message callback
    on_message: Option<Box<dyn Fn(TimelineMessage) -> Message + 'a>>,
}

impl<'a, Message> Timeline<'a, Message> {
    /// Create new timeline
    pub fn new(tracks: &'a [TimelineTrack]) -> Self {
        Self {
            tracks,
            playhead: 0,
            sample_rate: 48000,
            tempo: 120.0,
            time_sig_num: 4,
            time_sig_denom: 4,
            samples_per_pixel: 500.0,
            scroll_samples: 0,
            scroll_y: 0.0,
            total_duration: 48000 * 60 * 5, // 5 minutes default
            loop_enabled: false,
            loop_start: 0,
            loop_end: 0,
            snap_mode: SnapMode::Beat,
            grid_mode: GridMode::BarsBeats,
            header_width: 200.0,
            ruler_height: 32.0,
            selected_track: None,
            width: 1200.0,
            height: 600.0,
            on_message: None,
        }
    }

    pub fn playhead(mut self, position: u64) -> Self {
        self.playhead = position;
        self
    }

    pub fn sample_rate(mut self, rate: u32) -> Self {
        self.sample_rate = rate;
        self
    }

    pub fn tempo(mut self, bpm: f64) -> Self {
        self.tempo = bpm;
        self
    }

    pub fn time_signature(mut self, num: u8, denom: u8) -> Self {
        self.time_sig_num = num;
        self.time_sig_denom = denom;
        self
    }

    pub fn zoom(mut self, samples_per_pixel: f64) -> Self {
        self.samples_per_pixel = samples_per_pixel.max(1.0);
        self
    }

    pub fn scroll(mut self, scroll_samples: u64, scroll_y: f32) -> Self {
        self.scroll_samples = scroll_samples;
        self.scroll_y = scroll_y;
        self
    }

    pub fn total_duration(mut self, duration: u64) -> Self {
        self.total_duration = duration;
        self
    }

    pub fn loop_region(mut self, enabled: bool, start: u64, end: u64) -> Self {
        self.loop_enabled = enabled;
        self.loop_start = start;
        self.loop_end = end;
        self
    }

    pub fn snap_mode(mut self, mode: SnapMode) -> Self {
        self.snap_mode = mode;
        self
    }

    pub fn grid_mode(mut self, mode: GridMode) -> Self {
        self.grid_mode = mode;
        self
    }

    pub fn selected_track(mut self, index: Option<usize>) -> Self {
        self.selected_track = index;
        self
    }

    pub fn size(mut self, width: f32, height: f32) -> Self {
        self.width = width;
        self.height = height;
        self
    }

    pub fn on_message<F>(mut self, callback: F) -> Self
    where
        F: Fn(TimelineMessage) -> Message + 'a,
    {
        self.on_message = Some(Box::new(callback));
        self
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Coordinate conversions
    // ─────────────────────────────────────────────────────────────────────────────

    /// Convert sample position to x coordinate
    fn samples_to_x(&self, samples: u64, bounds: &Rectangle) -> f32 {
        let content_x = bounds.x + self.header_width;
        let relative_samples = samples.saturating_sub(self.scroll_samples);
        content_x + (relative_samples as f64 / self.samples_per_pixel) as f32
    }

    /// Convert x coordinate to sample position
    fn x_to_samples(&self, x: f32, bounds: &Rectangle) -> u64 {
        let content_x = bounds.x + self.header_width;
        if x < content_x {
            return self.scroll_samples;
        }
        let relative_x = x - content_x;
        self.scroll_samples + (relative_x as f64 * self.samples_per_pixel) as u64
    }

    /// Get track y position
    fn track_y(&self, track_index: usize, bounds: &Rectangle) -> f32 {
        let content_y = bounds.y + self.ruler_height;
        let mut y = content_y - self.scroll_y;

        for i in 0..track_index {
            if i < self.tracks.len() {
                y += self.tracks[i].height;
            }
        }
        y
    }

    /// Find track at y coordinate
    fn track_at_y(&self, y: f32, bounds: &Rectangle) -> Option<usize> {
        let content_y = bounds.y + self.ruler_height;
        if y < content_y {
            return None;
        }

        let mut current_y = content_y - self.scroll_y;
        for (i, track) in self.tracks.iter().enumerate() {
            if y >= current_y && y < current_y + track.height {
                return Some(i);
            }
            current_y += track.height;
        }
        None
    }

    /// Snap position to grid
    fn snap_to_grid(&self, samples: u64) -> u64 {
        match self.snap_mode {
            SnapMode::Off => samples,
            SnapMode::Bar => {
                let samples_per_beat = (self.sample_rate as f64 * 60.0 / self.tempo) as u64;
                let samples_per_bar = samples_per_beat * self.time_sig_num as u64;
                (samples / samples_per_bar) * samples_per_bar
            }
            SnapMode::Beat => {
                let samples_per_beat = (self.sample_rate as f64 * 60.0 / self.tempo) as u64;
                (samples / samples_per_beat) * samples_per_beat
            }
            SnapMode::Subdivision => {
                let samples_per_beat = (self.sample_rate as f64 * 60.0 / self.tempo) as u64;
                let subdivision = samples_per_beat / 4; // 16th notes
                (samples / subdivision) * subdivision
            }
            SnapMode::Samples => samples,
        }
    }

    /// Get samples per beat
    fn samples_per_beat(&self) -> u64 {
        (self.sample_rate as f64 * 60.0 / self.tempo) as u64
    }

    /// Get samples per bar
    fn samples_per_bar(&self) -> u64 {
        self.samples_per_beat() * self.time_sig_num as u64
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Bounds calculations
    // ─────────────────────────────────────────────────────────────────────────────

    fn ruler_bounds(&self, bounds: &Rectangle) -> Rectangle {
        Rectangle {
            x: bounds.x + self.header_width,
            y: bounds.y,
            width: bounds.width - self.header_width,
            height: self.ruler_height,
        }
    }

    fn header_bounds(&self, bounds: &Rectangle) -> Rectangle {
        Rectangle {
            x: bounds.x,
            y: bounds.y + self.ruler_height,
            width: self.header_width,
            height: bounds.height - self.ruler_height,
        }
    }

    fn content_bounds(&self, bounds: &Rectangle) -> Rectangle {
        Rectangle {
            x: bounds.x + self.header_width,
            y: bounds.y + self.ruler_height,
            width: bounds.width - self.header_width,
            height: bounds.height - self.ruler_height,
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TIMELINE STATE
// ═══════════════════════════════════════════════════════════════════════════════

/// Timeline widget state
#[derive(Default)]
pub struct TimelineState {
    /// Is dragging playhead
    dragging_playhead: bool,
    /// Is dragging a clip
    dragging_clip: Option<(usize, usize)>, // (track_idx, clip_idx)
    /// Drag start position
    drag_start_x: f32,
    /// Original clip position when drag started
    drag_original_pos: u64,
    /// Is resizing a clip
    resizing_clip: Option<(usize, usize, bool)>, // (track, clip, from_end)
    /// Is making a selection
    selecting: bool,
    /// Selection start position
    selection_start: u64,
    /// Hovered track
    hovered_track: Option<usize>,
}

// ═══════════════════════════════════════════════════════════════════════════════
// WIDGET IMPLEMENTATION
// ═══════════════════════════════════════════════════════════════════════════════

impl<'a, Message, Theme, Renderer> Widget<Message, Theme, Renderer> for Timeline<'a, Message>
where
    Renderer: renderer::Renderer,
    Message: Clone,
{
    fn size(&self) -> Size<Length> {
        Size::new(Length::Fixed(self.width), Length::Fixed(self.height))
    }

    fn layout(
        &self,
        _tree: &mut widget::Tree,
        _renderer: &Renderer,
        _limits: &layout::Limits,
    ) -> layout::Node {
        layout::Node::new(Size::new(self.width, self.height))
    }

    fn draw(
        &self,
        tree: &widget::Tree,
        renderer: &mut Renderer,
        _theme: &Theme,
        _style: &renderer::Style,
        layout: Layout<'_>,
        _cursor: mouse::Cursor,
        _viewport: &Rectangle,
    ) {
        let _state = tree.state.downcast_ref::<TimelineState>();
        let bounds = layout.bounds();

        // Draw background
        renderer.fill_quad(
            renderer::Quad {
                bounds,
                border: iced::Border {
                    color: Palette::BG_SURFACE,
                    width: 1.0,
                    radius: 0.0.into(),
                },
                shadow: Default::default(),
            },
            Palette::BG_DEEPEST,
        );

        // Draw sections
        self.draw_ruler(renderer, &bounds);
        self.draw_track_headers(renderer, &bounds);
        self.draw_tracks_content(renderer, &bounds);
        self.draw_playhead(renderer, &bounds);

        // Draw loop region
        if self.loop_enabled {
            self.draw_loop_region(renderer, &bounds);
        }
    }

    fn tag(&self) -> widget::tree::Tag {
        widget::tree::Tag::of::<TimelineState>()
    }

    fn state(&self) -> widget::tree::State {
        widget::tree::State::new(TimelineState::default())
    }

    fn on_event(
        &mut self,
        tree: &mut widget::Tree,
        event: Event,
        layout: Layout<'_>,
        cursor: mouse::Cursor,
        _renderer: &Renderer,
        _clipboard: &mut dyn Clipboard,
        shell: &mut Shell<'_, Message>,
        _viewport: &Rectangle,
    ) -> iced::event::Status {
        let state = tree.state.downcast_mut::<TimelineState>();
        let bounds = layout.bounds();
        let ruler = self.ruler_bounds(&bounds);
        let content = self.content_bounds(&bounds);

        match event {
            Event::Mouse(mouse::Event::ButtonPressed(mouse::Button::Left)) => {
                if let Some(pos) = cursor.position() {
                    // Click on ruler - seek
                    if ruler.contains(pos) {
                        let samples = self.x_to_samples(pos.x, &bounds);
                        let snapped = self.snap_to_grid(samples);

                        if let Some(ref on_message) = self.on_message {
                            shell.publish(on_message(TimelineMessage::SeekTo(snapped)));
                        }
                        state.dragging_playhead = true;
                        return iced::event::Status::Captured;
                    }

                    // Click on content - select track or clip
                    if content.contains(pos) {
                        if let Some(track_idx) = self.track_at_y(pos.y, &bounds) {
                            // Check if clicking on a clip
                            let click_samples = self.x_to_samples(pos.x, &bounds);

                            if let Some(clip_idx) = self.find_clip_at(track_idx, click_samples) {
                                if let Some(ref on_message) = self.on_message {
                                    shell.publish(on_message(TimelineMessage::SelectClip(track_idx, clip_idx)));
                                }

                                // Start dragging
                                state.dragging_clip = Some((track_idx, clip_idx));
                                state.drag_start_x = pos.x;
                                state.drag_original_pos = self.tracks[track_idx].clips[clip_idx].position;
                            } else {
                                // Select track
                                if let Some(ref on_message) = self.on_message {
                                    shell.publish(on_message(TimelineMessage::SelectTrack(track_idx)));
                                }
                            }

                            return iced::event::Status::Captured;
                        }
                    }
                }
            }

            Event::Mouse(mouse::Event::ButtonReleased(mouse::Button::Left)) => {
                if state.dragging_playhead || state.dragging_clip.is_some() {
                    state.dragging_playhead = false;
                    state.dragging_clip = None;
                    return iced::event::Status::Captured;
                }
            }

            Event::Mouse(mouse::Event::CursorMoved { position }) => {
                // Update hovered track
                state.hovered_track = self.track_at_y(position.y, &bounds);

                // Dragging playhead
                if state.dragging_playhead {
                    let samples = self.x_to_samples(position.x, &bounds);
                    let snapped = self.snap_to_grid(samples);

                    if let Some(ref on_message) = self.on_message {
                        shell.publish(on_message(TimelineMessage::SeekTo(snapped)));
                    }
                    return iced::event::Status::Captured;
                }

                // Dragging clip
                if let Some((track_idx, clip_idx)) = state.dragging_clip {
                    let delta_x = position.x - state.drag_start_x;
                    let delta_samples = (delta_x as f64 * self.samples_per_pixel) as i64;

                    let new_pos = if delta_samples < 0 {
                        state.drag_original_pos.saturating_sub((-delta_samples) as u64)
                    } else {
                        state.drag_original_pos.saturating_add(delta_samples as u64)
                    };

                    let snapped = self.snap_to_grid(new_pos);

                    if let Some(ref on_message) = self.on_message {
                        shell.publish(on_message(TimelineMessage::MoveClip(track_idx, clip_idx, snapped)));
                    }
                    return iced::event::Status::Captured;
                }
            }

            Event::Mouse(mouse::Event::WheelScrolled { delta }) => {
                if cursor.is_over(bounds) {
                    let scroll_amount = match delta {
                        mouse::ScrollDelta::Lines { x, y } => (x, y),
                        mouse::ScrollDelta::Pixels { x, y } => (x / 50.0, y / 50.0),
                    };

                    // Horizontal scroll with shift or horizontal delta
                    if scroll_amount.0.abs() > 0.01 {
                        let delta_samples = (scroll_amount.0 as f64 * self.samples_per_pixel * 50.0) as i64;
                        let new_scroll = if delta_samples < 0 {
                            self.scroll_samples.saturating_sub((-delta_samples) as u64)
                        } else {
                            self.scroll_samples.saturating_add(delta_samples as u64)
                        };

                        if let Some(ref on_message) = self.on_message {
                            shell.publish(on_message(TimelineMessage::ScrollChanged(new_scroll)));
                        }
                        return iced::event::Status::Captured;
                    }

                    // Vertical scroll or zoom
                    if scroll_amount.1.abs() > 0.01 {
                        // Zoom with ctrl/cmd
                        let new_zoom = self.samples_per_pixel * (1.0 - scroll_amount.1 as f64 * 0.1);
                        let clamped = new_zoom.clamp(1.0, 10000.0);

                        if let Some(ref on_message) = self.on_message {
                            shell.publish(on_message(TimelineMessage::ZoomChanged(clamped)));
                        }
                        return iced::event::Status::Captured;
                    }
                }
            }

            _ => {}
        }

        iced::event::Status::Ignored
    }

    fn mouse_interaction(
        &self,
        tree: &widget::Tree,
        layout: Layout<'_>,
        cursor: mouse::Cursor,
        _viewport: &Rectangle,
        _renderer: &Renderer,
    ) -> mouse::Interaction {
        let state = tree.state.downcast_ref::<TimelineState>();
        let bounds = layout.bounds();

        if state.dragging_playhead || state.dragging_clip.is_some() {
            return mouse::Interaction::Grabbing;
        }

        if let Some(pos) = cursor.position() {
            let ruler = self.ruler_bounds(&bounds);
            if ruler.contains(pos) {
                return mouse::Interaction::Pointer;
            }

            let content = self.content_bounds(&bounds);
            if content.contains(pos) {
                // Check if over clip edge (resize cursor)
                if let Some(track_idx) = self.track_at_y(pos.y, &bounds) {
                    let samples = self.x_to_samples(pos.x, &bounds);
                    if self.is_over_clip_edge(track_idx, samples) {
                        return mouse::Interaction::ResizingHorizontally;
                    }
                    if self.find_clip_at(track_idx, samples).is_some() {
                        return mouse::Interaction::Grab;
                    }
                }
                return mouse::Interaction::Crosshair;
            }
        }

        mouse::Interaction::default()
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DRAWING HELPERS
// ═══════════════════════════════════════════════════════════════════════════════

impl<'a, Message> Timeline<'a, Message>
where
    Message: Clone,
{
    /// Find clip at sample position
    fn find_clip_at(&self, track_idx: usize, samples: u64) -> Option<usize> {
        if track_idx >= self.tracks.len() {
            return None;
        }

        for (i, clip) in self.tracks[track_idx].clips.iter().enumerate() {
            if samples >= clip.position && samples < clip.end_position() {
                return Some(i);
            }
        }
        None
    }

    /// Check if cursor is over clip edge
    fn is_over_clip_edge(&self, track_idx: usize, samples: u64) -> bool {
        if track_idx >= self.tracks.len() {
            return false;
        }

        let edge_threshold = (self.samples_per_pixel * 5.0) as u64;

        for clip in &self.tracks[track_idx].clips {
            if samples.abs_diff(clip.position) < edge_threshold
                || samples.abs_diff(clip.end_position()) < edge_threshold
            {
                return true;
            }
        }
        false
    }

    /// Draw time ruler
    fn draw_ruler<Renderer: renderer::Renderer>(&self, renderer: &mut Renderer, bounds: &Rectangle) {
        let ruler = self.ruler_bounds(bounds);

        // Ruler background
        renderer.fill_quad(
            renderer::Quad {
                bounds: ruler,
                border: Default::default(),
                shadow: Default::default(),
            },
            Palette::BG_MID,
        );

        // Draw grid lines and labels
        let samples_per_bar = self.samples_per_bar();
        let samples_per_beat = self.samples_per_beat();

        // Calculate visible range
        let visible_width = ruler.width;
        let visible_samples = (visible_width as f64 * self.samples_per_pixel) as u64;
        let end_samples = self.scroll_samples + visible_samples;

        // Determine grid spacing based on zoom
        let pixels_per_bar = samples_per_bar as f64 / self.samples_per_pixel;
        let draw_beat_lines = pixels_per_bar > 40.0;
        let draw_subdivision = pixels_per_bar > 160.0;

        // Draw bar lines
        let first_bar = self.scroll_samples / samples_per_bar;
        let mut bar = first_bar;

        loop {
            let bar_samples = bar * samples_per_bar;
            if bar_samples > end_samples {
                break;
            }

            let x = self.samples_to_x(bar_samples, bounds);

            if x >= ruler.x && x <= ruler.x + ruler.width {
                // Bar line
                renderer.fill_quad(
                    renderer::Quad {
                        bounds: Rectangle {
                            x,
                            y: ruler.y,
                            width: 1.0,
                            height: ruler.height,
                        },
                        border: Default::default(),
                        shadow: Default::default(),
                    },
                    Palette::TEXT_SECONDARY,
                );
            }

            // Draw beat lines
            if draw_beat_lines {
                for beat in 1..self.time_sig_num {
                    let beat_samples = bar_samples + beat as u64 * samples_per_beat;
                    let beat_x = self.samples_to_x(beat_samples, bounds);

                    if beat_x >= ruler.x && beat_x <= ruler.x + ruler.width {
                        renderer.fill_quad(
                            renderer::Quad {
                                bounds: Rectangle {
                                    x: beat_x,
                                    y: ruler.y + ruler.height * 0.6,
                                    width: 1.0,
                                    height: ruler.height * 0.4,
                                },
                                border: Default::default(),
                                shadow: Default::default(),
                            },
                            Palette::BG_SURFACE,
                        );
                    }

                    // Subdivisions
                    if draw_subdivision {
                        for sub in 1..4 {
                            let sub_samples = beat_samples + sub * samples_per_beat / 4;
                            let sub_x = self.samples_to_x(sub_samples, bounds);

                            if sub_x >= ruler.x && sub_x <= ruler.x + ruler.width {
                                renderer.fill_quad(
                                    renderer::Quad {
                                        bounds: Rectangle {
                                            x: sub_x,
                                            y: ruler.y + ruler.height * 0.8,
                                            width: 1.0,
                                            height: ruler.height * 0.2,
                                        },
                                        border: Default::default(),
                                        shadow: Default::default(),
                                    },
                                    Palette::BG_SURFACE,
                                );
                            }
                        }
                    }
                }
            }

            bar += 1;
        }

        // Bottom border
        renderer.fill_quad(
            renderer::Quad {
                bounds: Rectangle {
                    x: ruler.x,
                    y: ruler.y + ruler.height - 1.0,
                    width: ruler.width,
                    height: 1.0,
                },
                border: Default::default(),
                shadow: Default::default(),
            },
            Palette::BG_SURFACE,
        );
    }

    /// Draw track headers
    fn draw_track_headers<Renderer: renderer::Renderer>(&self, renderer: &mut Renderer, bounds: &Rectangle) {
        let header_area = self.header_bounds(bounds);

        // Header background
        renderer.fill_quad(
            renderer::Quad {
                bounds: header_area,
                border: Default::default(),
                shadow: Default::default(),
            },
            Palette::BG_DEEP,
        );

        // Draw each track header
        let mut y = header_area.y - self.scroll_y;

        for (i, track) in self.tracks.iter().enumerate() {
            if y + track.height < header_area.y {
                y += track.height;
                continue;
            }
            if y > header_area.y + header_area.height {
                break;
            }

            let track_header = Rectangle {
                x: header_area.x,
                y: y.max(header_area.y),
                width: header_area.width,
                height: track.height.min(header_area.y + header_area.height - y),
            };

            // Selected track highlight
            if self.selected_track == Some(i) {
                renderer.fill_quad(
                    renderer::Quad {
                        bounds: track_header,
                        border: Default::default(),
                        shadow: Default::default(),
                    },
                    iced::Color::from_rgba(0.29, 0.62, 1.0, 0.1),
                );
            }

            // Track color indicator
            let color = track.color.map(|c| {
                iced::Color::from_rgb(
                    ((c >> 16) & 0xFF) as f32 / 255.0,
                    ((c >> 8) & 0xFF) as f32 / 255.0,
                    (c & 0xFF) as f32 / 255.0,
                )
            }).unwrap_or(Palette::ACCENT_CYAN);

            renderer.fill_quad(
                renderer::Quad {
                    bounds: Rectangle {
                        x: track_header.x,
                        y: y,
                        width: 4.0,
                        height: track.height,
                    },
                    border: Default::default(),
                    shadow: Default::default(),
                },
                color,
            );

            // Mute/Solo/Arm buttons
            let button_size = 18.0;
            let button_y = y + (track.height - button_size) / 2.0;
            let button_spacing = 4.0;

            // Mute
            let mute_bounds = Rectangle {
                x: track_header.x + track_header.width - 3.0 * (button_size + button_spacing),
                y: button_y,
                width: button_size,
                height: button_size,
            };
            self.draw_track_button(renderer, &mute_bounds, "M", track.mute, Palette::ACCENT_ORANGE);

            // Solo
            let solo_bounds = Rectangle {
                x: track_header.x + track_header.width - 2.0 * (button_size + button_spacing),
                y: button_y,
                width: button_size,
                height: button_size,
            };
            self.draw_track_button(renderer, &solo_bounds, "S", track.solo, Palette::ACCENT_YELLOW);

            // Arm
            if track.track_type == TimelineTrackType::Audio {
                let arm_bounds = Rectangle {
                    x: track_header.x + track_header.width - (button_size + button_spacing),
                    y: button_y,
                    width: button_size,
                    height: button_size,
                };
                self.draw_track_button(renderer, &arm_bounds, "R", track.armed, Palette::ACCENT_RED);
            }

            // Track separator
            renderer.fill_quad(
                renderer::Quad {
                    bounds: Rectangle {
                        x: track_header.x,
                        y: y + track.height - 1.0,
                        width: track_header.width,
                        height: 1.0,
                    },
                    border: Default::default(),
                    shadow: Default::default(),
                },
                Palette::BG_SURFACE,
            );

            y += track.height;
        }

        // Right border
        renderer.fill_quad(
            renderer::Quad {
                bounds: Rectangle {
                    x: header_area.x + header_area.width - 1.0,
                    y: header_area.y,
                    width: 1.0,
                    height: header_area.height,
                },
                border: Default::default(),
                shadow: Default::default(),
            },
            Palette::BG_SURFACE,
        );
    }

    /// Draw a track button (M/S/R)
    fn draw_track_button<Renderer: renderer::Renderer>(
        &self,
        renderer: &mut Renderer,
        bounds: &Rectangle,
        _label: &str,
        active: bool,
        active_color: iced::Color,
    ) {
        let bg = if active { active_color } else { Palette::BG_MID };

        renderer.fill_quad(
            renderer::Quad {
                bounds: *bounds,
                border: iced::Border {
                    color: Palette::BG_SURFACE,
                    width: 1.0,
                    radius: 2.0.into(),
                },
                shadow: Default::default(),
            },
            bg,
        );
    }

    /// Draw tracks content area
    fn draw_tracks_content<Renderer: renderer::Renderer>(&self, renderer: &mut Renderer, bounds: &Rectangle) {
        let content = self.content_bounds(bounds);

        // Content background with grid
        renderer.fill_quad(
            renderer::Quad {
                bounds: content,
                border: Default::default(),
                shadow: Default::default(),
            },
            Palette::BG_DEEPEST,
        );

        // Draw vertical grid lines
        self.draw_content_grid(renderer, bounds);

        // Draw tracks and clips
        let mut y = content.y - self.scroll_y;

        for (track_idx, track) in self.tracks.iter().enumerate() {
            if y + track.height < content.y {
                y += track.height;
                continue;
            }
            if y > content.y + content.height {
                break;
            }

            // Track lane background
            let lane_bg = if track_idx % 2 == 0 {
                Palette::BG_DEEPEST
            } else {
                iced::Color::from_rgba(0.08, 0.08, 0.1, 1.0)
            };

            let lane_y = y.max(content.y);
            let lane_height = (y + track.height).min(content.y + content.height) - lane_y;

            renderer.fill_quad(
                renderer::Quad {
                    bounds: Rectangle {
                        x: content.x,
                        y: lane_y,
                        width: content.width,
                        height: lane_height,
                    },
                    border: Default::default(),
                    shadow: Default::default(),
                },
                lane_bg,
            );

            // Draw clips
            for (clip_idx, clip) in track.clips.iter().enumerate() {
                self.draw_clip(renderer, bounds, track_idx, clip_idx, clip, y, track.height);
            }

            // Track separator
            renderer.fill_quad(
                renderer::Quad {
                    bounds: Rectangle {
                        x: content.x,
                        y: y + track.height - 1.0,
                        width: content.width,
                        height: 1.0,
                    },
                    border: Default::default(),
                    shadow: Default::default(),
                },
                Palette::BG_SURFACE,
            );

            y += track.height;
        }
    }

    /// Draw content area grid
    fn draw_content_grid<Renderer: renderer::Renderer>(&self, renderer: &mut Renderer, bounds: &Rectangle) {
        let content = self.content_bounds(bounds);
        let samples_per_bar = self.samples_per_bar();

        let visible_samples = (content.width as f64 * self.samples_per_pixel) as u64;
        let end_samples = self.scroll_samples + visible_samples;

        let first_bar = self.scroll_samples / samples_per_bar;
        let mut bar = first_bar;

        loop {
            let bar_samples = bar * samples_per_bar;
            if bar_samples > end_samples {
                break;
            }

            let x = self.samples_to_x(bar_samples, bounds);

            if x >= content.x && x <= content.x + content.width {
                renderer.fill_quad(
                    renderer::Quad {
                        bounds: Rectangle {
                            x,
                            y: content.y,
                            width: 1.0,
                            height: content.height,
                        },
                        border: Default::default(),
                        shadow: Default::default(),
                    },
                    iced::Color::from_rgba(0.2, 0.2, 0.25, 0.5),
                );
            }

            bar += 1;
        }
    }

    /// Draw a clip
    fn draw_clip<Renderer: renderer::Renderer>(
        &self,
        renderer: &mut Renderer,
        bounds: &Rectangle,
        _track_idx: usize,
        _clip_idx: usize,
        clip: &TimelineClip,
        track_y: f32,
        track_height: f32,
    ) {
        let content = self.content_bounds(bounds);

        // Calculate clip bounds
        let clip_x = self.samples_to_x(clip.position, bounds);
        let clip_end_x = self.samples_to_x(clip.end_position(), bounds);

        // Skip if not visible
        if clip_end_x < content.x || clip_x > content.x + content.width {
            return;
        }

        let visible_x = clip_x.max(content.x);
        let visible_end_x = clip_end_x.min(content.x + content.width);
        let visible_width = visible_end_x - visible_x;

        let clip_y = track_y.max(content.y) + 2.0;
        let clip_height = (track_height - 4.0).min(content.y + content.height - clip_y);

        if clip_height <= 0.0 {
            return;
        }

        // Clip color
        let base_color = clip.color.map(|c| {
            iced::Color::from_rgb(
                ((c >> 16) & 0xFF) as f32 / 255.0,
                ((c >> 8) & 0xFF) as f32 / 255.0,
                (c & 0xFF) as f32 / 255.0,
            )
        }).unwrap_or(Palette::ACCENT_CYAN);

        let clip_color = if clip.muted {
            iced::Color::from_rgba(0.3, 0.3, 0.35, 0.8)
        } else if clip.selected {
            iced::Color::from_rgba(
                base_color.r * 1.2,
                base_color.g * 1.2,
                base_color.b * 1.2,
                1.0,
            )
        } else {
            base_color
        };

        // Clip background
        renderer.fill_quad(
            renderer::Quad {
                bounds: Rectangle {
                    x: visible_x,
                    y: clip_y,
                    width: visible_width,
                    height: clip_height,
                },
                border: iced::Border {
                    color: if clip.selected {
                        Palette::ACCENT_BLUE
                    } else {
                        clip_color
                    },
                    width: if clip.selected { 2.0 } else { 1.0 },
                    radius: 4.0.into(),
                },
                shadow: Default::default(),
            },
            iced::Color::from_rgba(clip_color.r * 0.3, clip_color.g * 0.3, clip_color.b * 0.3, 0.9),
        );

        // Draw waveform if available
        if !clip.waveform.is_empty() {
            self.draw_clip_waveform(renderer, clip, visible_x, clip_y, visible_width, clip_height, clip_color);
        }

        // Clip header with name
        let header_height = 16.0_f32.min(clip_height);
        renderer.fill_quad(
            renderer::Quad {
                bounds: Rectangle {
                    x: visible_x,
                    y: clip_y,
                    width: visible_width,
                    height: header_height,
                },
                border: iced::Border {
                    color: clip_color,
                    width: 0.0,
                    radius: iced::border::Radius {
                        top_left: 4.0,
                        top_right: 4.0,
                        bottom_left: 0.0,
                        bottom_right: 0.0,
                    },
                },
                shadow: Default::default(),
            },
            iced::Color::from_rgba(clip_color.r, clip_color.g, clip_color.b, 0.6),
        );

        // Fade in indicator
        if clip.fade_in > 0 {
            let fade_width = ((clip.fade_in as f64 / self.samples_per_pixel) as f32).min(visible_width * 0.3);
            renderer.fill_quad(
                renderer::Quad {
                    bounds: Rectangle {
                        x: visible_x,
                        y: clip_y,
                        width: fade_width,
                        height: clip_height,
                    },
                    border: Default::default(),
                    shadow: Default::default(),
                },
                iced::Color::from_rgba(0.0, 0.0, 0.0, 0.3),
            );
        }

        // Fade out indicator
        if clip.fade_out > 0 {
            let fade_width = ((clip.fade_out as f64 / self.samples_per_pixel) as f32).min(visible_width * 0.3);
            renderer.fill_quad(
                renderer::Quad {
                    bounds: Rectangle {
                        x: visible_end_x - fade_width,
                        y: clip_y,
                        width: fade_width,
                        height: clip_height,
                    },
                    border: Default::default(),
                    shadow: Default::default(),
                },
                iced::Color::from_rgba(0.0, 0.0, 0.0, 0.3),
            );
        }
    }

    /// Draw clip waveform
    fn draw_clip_waveform<Renderer: renderer::Renderer>(
        &self,
        renderer: &mut Renderer,
        clip: &TimelineClip,
        x: f32,
        y: f32,
        width: f32,
        height: f32,
        color: iced::Color,
    ) {
        let waveform_y = y + 18.0; // Below header
        let waveform_height = height - 20.0;

        if waveform_height <= 0.0 {
            return;
        }

        let center_y = waveform_y + waveform_height / 2.0;
        let half_height = waveform_height / 2.0 - 2.0;

        let data_len = clip.waveform.len();
        if data_len == 0 {
            return;
        }

        let num_columns = width as usize;

        for col in 0..num_columns {
            let t = col as f32 / num_columns as f32;
            let data_idx = (t * data_len as f32) as usize;

            if data_idx >= data_len {
                continue;
            }

            let point = &clip.waveform[data_idx];
            let col_x = x + col as f32;

            // Draw min/max
            let min_y = center_y - point.min * half_height;
            let max_y = center_y - point.max * half_height;
            let top = min_y.min(max_y);
            let bar_height = (min_y.max(max_y) - top).max(1.0);

            renderer.fill_quad(
                renderer::Quad {
                    bounds: Rectangle {
                        x: col_x,
                        y: top,
                        width: 1.0,
                        height: bar_height,
                    },
                    border: Default::default(),
                    shadow: Default::default(),
                },
                color,
            );
        }
    }

    /// Draw playhead
    fn draw_playhead<Renderer: renderer::Renderer>(&self, renderer: &mut Renderer, bounds: &Rectangle) {
        let ruler = self.ruler_bounds(bounds);
        let content = self.content_bounds(bounds);

        let playhead_x = self.samples_to_x(self.playhead, bounds);

        // Only draw if visible
        if playhead_x < ruler.x || playhead_x > ruler.x + ruler.width {
            return;
        }

        // Playhead line through content
        renderer.fill_quad(
            renderer::Quad {
                bounds: Rectangle {
                    x: playhead_x - 1.0,
                    y: content.y,
                    width: 2.0,
                    height: content.height,
                },
                border: Default::default(),
                shadow: Default::default(),
            },
            Palette::ACCENT_BLUE,
        );

        // Playhead head in ruler
        renderer.fill_quad(
            renderer::Quad {
                bounds: Rectangle {
                    x: playhead_x - 6.0,
                    y: ruler.y + ruler.height - 12.0,
                    width: 12.0,
                    height: 12.0,
                },
                border: iced::Border {
                    color: Palette::ACCENT_BLUE,
                    width: 0.0,
                    radius: 2.0.into(),
                },
                shadow: Default::default(),
            },
            Palette::ACCENT_BLUE,
        );
    }

    /// Draw loop region
    fn draw_loop_region<Renderer: renderer::Renderer>(&self, renderer: &mut Renderer, bounds: &Rectangle) {
        let ruler = self.ruler_bounds(bounds);
        let content = self.content_bounds(bounds);

        let loop_start_x = self.samples_to_x(self.loop_start, bounds);
        let loop_end_x = self.samples_to_x(self.loop_end, bounds);

        // Loop region highlight
        if loop_end_x > ruler.x && loop_start_x < ruler.x + ruler.width {
            let visible_start = loop_start_x.max(ruler.x);
            let visible_end = loop_end_x.min(ruler.x + ruler.width);
            let width = visible_end - visible_start;

            // Ruler highlight
            renderer.fill_quad(
                renderer::Quad {
                    bounds: Rectangle {
                        x: visible_start,
                        y: ruler.y,
                        width,
                        height: ruler.height,
                    },
                    border: Default::default(),
                    shadow: Default::default(),
                },
                iced::Color::from_rgba(0.25, 0.56, 1.0, 0.3),
            );

            // Content highlight
            renderer.fill_quad(
                renderer::Quad {
                    bounds: Rectangle {
                        x: visible_start,
                        y: content.y,
                        width,
                        height: content.height,
                    },
                    border: Default::default(),
                    shadow: Default::default(),
                },
                iced::Color::from_rgba(0.25, 0.56, 1.0, 0.05),
            );

            // Loop markers
            // Start marker
            if loop_start_x >= ruler.x && loop_start_x <= ruler.x + ruler.width {
                renderer.fill_quad(
                    renderer::Quad {
                        bounds: Rectangle {
                            x: loop_start_x - 1.0,
                            y: ruler.y,
                            width: 2.0,
                            height: ruler.height + content.height,
                        },
                        border: Default::default(),
                        shadow: Default::default(),
                    },
                    Palette::ACCENT_CYAN,
                );
            }

            // End marker
            if loop_end_x >= ruler.x && loop_end_x <= ruler.x + ruler.width {
                renderer.fill_quad(
                    renderer::Quad {
                        bounds: Rectangle {
                            x: loop_end_x - 1.0,
                            y: ruler.y,
                            width: 2.0,
                            height: ruler.height + content.height,
                        },
                        border: Default::default(),
                        shadow: Default::default(),
                    },
                    Palette::ACCENT_CYAN,
                );
            }
        }
    }
}

impl<'a, Message, Theme, Renderer> From<Timeline<'a, Message>> for Element<'a, Message, Theme, Renderer>
where
    Renderer: renderer::Renderer + 'a,
    Message: Clone + 'a,
    Theme: 'a,
{
    fn from(timeline: Timeline<'a, Message>) -> Self {
        Element::new(timeline)
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PALETTE COLORS (if not defined elsewhere)
// ═══════════════════════════════════════════════════════════════════════════════

impl Palette {
    pub const ACCENT_YELLOW: iced::Color = iced::Color::from_rgb(1.0, 1.0, 0.25);
}
