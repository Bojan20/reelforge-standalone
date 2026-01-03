//! Input Monitor Widget
//!
//! Real-time audio input monitoring with:
//! - Level meters per input channel
//! - Peak hold and clip indicators
//! - Input source selection
//! - Gain control
//! - Low-latency waveform display
//! - Record arm state

use iced::advanced::layout::{self, Layout};
use iced::advanced::renderer;
use iced::advanced::widget::{self, Widget};
use iced::advanced::{Clipboard, Shell};
use iced::mouse;
use iced::{Element, Event, Length, Rectangle, Size};

use crate::theme::{meter_color, Palette};

// ═══════════════════════════════════════════════════════════════════════════════
// INPUT MONITOR TYPES
// ═══════════════════════════════════════════════════════════════════════════════

/// Input channel state
#[derive(Debug, Clone, Default)]
pub struct InputChannelState {
    /// Channel name/label
    pub name: String,
    /// Current level (0.0 to 1.0)
    pub level: f32,
    /// Peak hold level
    pub peak: f32,
    /// Has clipped
    pub clipped: bool,
    /// Is mono input
    pub mono: bool,
    /// Hardware input index
    pub hw_input: usize,
    /// Input gain in dB
    pub gain_db: f64,
    /// Is muted
    pub muted: bool,
    /// Is record armed
    pub armed: bool,
    /// Waveform buffer for display (ring buffer of recent samples)
    pub waveform: Vec<f32>,
}

impl InputChannelState {
    pub fn new(name: &str, hw_input: usize) -> Self {
        Self {
            name: name.to_string(),
            hw_input,
            waveform: vec![0.0; 256], // ~5ms at 48kHz
            ..Default::default()
        }
    }

    pub fn stereo(name: &str, hw_input: usize) -> Self {
        Self {
            name: name.to_string(),
            hw_input,
            mono: false,
            waveform: vec![0.0; 256],
            ..Default::default()
        }
    }

    pub fn mono_input(name: &str, hw_input: usize) -> Self {
        Self {
            name: name.to_string(),
            hw_input,
            mono: true,
            waveform: vec![0.0; 128],
            ..Default::default()
        }
    }
}

/// Input monitor messages
#[derive(Debug, Clone)]
pub enum InputMonitorMessage {
    /// Select input source (channel index, hw input index)
    SelectInput(usize, usize),
    /// Toggle arm for recording
    ToggleArm(usize),
    /// Toggle mute
    ToggleMute(usize),
    /// Gain changed (channel index, gain in dB)
    GainChanged(usize, f64),
    /// Clear clip indicator
    ClearClip(usize),
    /// Clear all clips
    ClearAllClips,
}

// ═══════════════════════════════════════════════════════════════════════════════
// INPUT MONITOR WIDGET
// ═══════════════════════════════════════════════════════════════════════════════

/// Input monitor widget
pub struct InputMonitor<'a, Message> {
    /// Input channels
    channels: &'a [InputChannelState],
    /// Available hardware inputs
    available_inputs: &'a [String],
    /// Widget dimensions
    width: f32,
    height: f32,
    /// Show waveforms
    show_waveforms: bool,
    /// Compact mode (meters only)
    compact: bool,
    /// Orientation (vertical or horizontal)
    vertical: bool,
    /// Message callback
    on_message: Option<Box<dyn Fn(InputMonitorMessage) -> Message + 'a>>,
}

impl<'a, Message> InputMonitor<'a, Message> {
    const CHANNEL_WIDTH: f32 = 70.0;
    const HEADER_HEIGHT: f32 = 24.0;
    const METER_HEIGHT: f32 = 150.0;
    const WAVEFORM_HEIGHT: f32 = 40.0;
    const BUTTON_SIZE: f32 = 20.0;
    const GAIN_KNOB_SIZE: f32 = 32.0;
    const PADDING: f32 = 4.0;

    pub fn new(channels: &'a [InputChannelState], available_inputs: &'a [String]) -> Self {
        Self {
            channels,
            available_inputs,
            width: 400.0,
            height: 300.0,
            show_waveforms: true,
            compact: false,
            vertical: true,
            on_message: None,
        }
    }

    pub fn size(mut self, width: f32, height: f32) -> Self {
        self.width = width;
        self.height = height;
        self
    }

    pub fn show_waveforms(mut self, show: bool) -> Self {
        self.show_waveforms = show;
        self
    }

    pub fn compact(mut self, compact: bool) -> Self {
        self.compact = compact;
        self
    }

    pub fn vertical(mut self, vertical: bool) -> Self {
        self.vertical = vertical;
        self
    }

    pub fn on_message<F>(mut self, callback: F) -> Self
    where
        F: Fn(InputMonitorMessage) -> Message + 'a,
    {
        self.on_message = Some(Box::new(callback));
        self
    }

    fn channel_bounds(&self, index: usize, bounds: &Rectangle) -> Rectangle {
        if self.vertical {
            Rectangle {
                x: bounds.x + index as f32 * Self::CHANNEL_WIDTH,
                y: bounds.y,
                width: Self::CHANNEL_WIDTH,
                height: bounds.height,
            }
        } else {
            let channel_height = bounds.height / self.channels.len().max(1) as f32;
            Rectangle {
                x: bounds.x,
                y: bounds.y + index as f32 * channel_height,
                width: bounds.width,
                height: channel_height,
            }
        }
    }

    fn meter_bounds(&self, channel_bounds: &Rectangle) -> Rectangle {
        if self.compact {
            Rectangle {
                x: channel_bounds.x + Self::PADDING,
                y: channel_bounds.y + Self::HEADER_HEIGHT,
                width: channel_bounds.width - Self::PADDING * 2.0,
                height: channel_bounds.height - Self::HEADER_HEIGHT - Self::PADDING,
            }
        } else {
            Rectangle {
                x: channel_bounds.x + Self::PADDING,
                y: channel_bounds.y + Self::HEADER_HEIGHT + Self::BUTTON_SIZE + Self::PADDING * 2.0,
                width: channel_bounds.width - Self::PADDING * 2.0,
                height: Self::METER_HEIGHT,
            }
        }
    }

    fn arm_button_bounds(&self, channel_bounds: &Rectangle) -> Rectangle {
        Rectangle {
            x: channel_bounds.x + Self::PADDING,
            y: channel_bounds.y + Self::HEADER_HEIGHT,
            width: Self::BUTTON_SIZE,
            height: Self::BUTTON_SIZE,
        }
    }

    fn mute_button_bounds(&self, channel_bounds: &Rectangle) -> Rectangle {
        Rectangle {
            x: channel_bounds.x + Self::PADDING + Self::BUTTON_SIZE + 4.0,
            y: channel_bounds.y + Self::HEADER_HEIGHT,
            width: Self::BUTTON_SIZE,
            height: Self::BUTTON_SIZE,
        }
    }

    fn gain_knob_bounds(&self, channel_bounds: &Rectangle) -> Rectangle {
        let meter = self.meter_bounds(channel_bounds);
        Rectangle {
            x: channel_bounds.x + (channel_bounds.width - Self::GAIN_KNOB_SIZE) / 2.0,
            y: meter.y + meter.height + Self::PADDING,
            width: Self::GAIN_KNOB_SIZE,
            height: Self::GAIN_KNOB_SIZE,
        }
    }

    fn waveform_bounds(&self, channel_bounds: &Rectangle) -> Rectangle {
        let gain = self.gain_knob_bounds(channel_bounds);
        Rectangle {
            x: channel_bounds.x + Self::PADDING,
            y: gain.y + gain.height + Self::PADDING,
            width: channel_bounds.width - Self::PADDING * 2.0,
            height: Self::WAVEFORM_HEIGHT,
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// INPUT MONITOR STATE
// ═══════════════════════════════════════════════════════════════════════════════

#[derive(Default)]
pub struct InputMonitorState {
    dragging_gain: Option<usize>,
    hovered_channel: Option<usize>,
    hovered_arm: Option<usize>,
    hovered_mute: Option<usize>,
}

// ═══════════════════════════════════════════════════════════════════════════════
// WIDGET IMPLEMENTATION
// ═══════════════════════════════════════════════════════════════════════════════

impl<'a, Message, Theme, Renderer> Widget<Message, Theme, Renderer> for InputMonitor<'a, Message>
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
        let state = tree.state.downcast_ref::<InputMonitorState>();
        let bounds = layout.bounds();

        // Background
        renderer.fill_quad(
            renderer::Quad {
                bounds,
                border: iced::Border {
                    color: Palette::BG_SURFACE,
                    width: 1.0,
                    radius: 4.0.into(),
                },
                shadow: Default::default(),
            },
            Palette::BG_DEEP,
        );

        // Draw each input channel
        for (i, channel) in self.channels.iter().enumerate() {
            let channel_bounds = self.channel_bounds(i, &bounds);
            self.draw_channel(renderer, channel, i, &channel_bounds, state);
        }
    }

    fn tag(&self) -> widget::tree::Tag {
        widget::tree::Tag::of::<InputMonitorState>()
    }

    fn state(&self) -> widget::tree::State {
        widget::tree::State::new(InputMonitorState::default())
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
        let state = tree.state.downcast_mut::<InputMonitorState>();
        let bounds = layout.bounds();

        match event {
            Event::Mouse(mouse::Event::ButtonPressed(mouse::Button::Left)) => {
                if let Some(pos) = cursor.position() {
                    for i in 0..self.channels.len() {
                        let channel_bounds = self.channel_bounds(i, &bounds);

                        // Check arm button
                        let arm = self.arm_button_bounds(&channel_bounds);
                        if arm.contains(pos) {
                            if let Some(ref on_message) = self.on_message {
                                shell.publish(on_message(InputMonitorMessage::ToggleArm(i)));
                            }
                            return iced::event::Status::Captured;
                        }

                        // Check mute button
                        let mute = self.mute_button_bounds(&channel_bounds);
                        if mute.contains(pos) {
                            if let Some(ref on_message) = self.on_message {
                                shell.publish(on_message(InputMonitorMessage::ToggleMute(i)));
                            }
                            return iced::event::Status::Captured;
                        }

                        // Check gain knob
                        if !self.compact {
                            let gain = self.gain_knob_bounds(&channel_bounds);
                            if gain.contains(pos) {
                                state.dragging_gain = Some(i);
                                return iced::event::Status::Captured;
                            }
                        }

                        // Check clip indicator (click to clear)
                        let meter = self.meter_bounds(&channel_bounds);
                        if self.channels[i].clipped {
                            let clip_bounds = Rectangle {
                                x: meter.x,
                                y: meter.y,
                                width: meter.width,
                                height: 10.0,
                            };
                            if clip_bounds.contains(pos) {
                                if let Some(ref on_message) = self.on_message {
                                    shell.publish(on_message(InputMonitorMessage::ClearClip(i)));
                                }
                                return iced::event::Status::Captured;
                            }
                        }
                    }
                }
            }

            Event::Mouse(mouse::Event::ButtonReleased(mouse::Button::Left)) => {
                if state.dragging_gain.is_some() {
                    state.dragging_gain = None;
                    return iced::event::Status::Captured;
                }
            }

            Event::Mouse(mouse::Event::CursorMoved { position }) => {
                // Update hovered states
                state.hovered_channel = None;
                state.hovered_arm = None;
                state.hovered_mute = None;

                for i in 0..self.channels.len() {
                    let channel_bounds = self.channel_bounds(i, &bounds);
                    if channel_bounds.contains(position) {
                        state.hovered_channel = Some(i);

                        let arm = self.arm_button_bounds(&channel_bounds);
                        if arm.contains(position) {
                            state.hovered_arm = Some(i);
                        }

                        let mute = self.mute_button_bounds(&channel_bounds);
                        if mute.contains(position) {
                            state.hovered_mute = Some(i);
                        }
                    }
                }

                // Handle gain dragging
                if let Some(channel_idx) = state.dragging_gain {
                    let channel_bounds = self.channel_bounds(channel_idx, &bounds);
                    let gain = self.gain_knob_bounds(&channel_bounds);
                    let center_y = gain.y + gain.height / 2.0;
                    let delta = center_y - position.y;
                    let new_gain = (self.channels[channel_idx].gain_db + delta as f64 * 0.5)
                        .clamp(-60.0, 24.0);

                    if let Some(ref on_message) = self.on_message {
                        shell.publish(on_message(InputMonitorMessage::GainChanged(channel_idx, new_gain)));
                    }
                    return iced::event::Status::Captured;
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
        let state = tree.state.downcast_ref::<InputMonitorState>();
        let bounds = layout.bounds();

        if state.dragging_gain.is_some() {
            return mouse::Interaction::Grabbing;
        }

        if let Some(pos) = cursor.position() {
            for i in 0..self.channels.len() {
                let channel_bounds = self.channel_bounds(i, &bounds);

                if !self.compact {
                    let gain = self.gain_knob_bounds(&channel_bounds);
                    if gain.contains(pos) {
                        return mouse::Interaction::Grab;
                    }
                }

                let arm = self.arm_button_bounds(&channel_bounds);
                let mute = self.mute_button_bounds(&channel_bounds);
                if arm.contains(pos) || mute.contains(pos) {
                    return mouse::Interaction::Pointer;
                }
            }
        }

        mouse::Interaction::default()
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DRAWING HELPERS
// ═══════════════════════════════════════════════════════════════════════════════

impl<'a, Message> InputMonitor<'a, Message>
where
    Message: Clone,
{
    fn draw_channel<Renderer: renderer::Renderer>(
        &self,
        renderer: &mut Renderer,
        channel: &InputChannelState,
        index: usize,
        bounds: &Rectangle,
        state: &InputMonitorState,
    ) {
        // Channel separator
        if index > 0 {
            renderer.fill_quad(
                renderer::Quad {
                    bounds: Rectangle {
                        x: bounds.x - 0.5,
                        y: bounds.y,
                        width: 1.0,
                        height: bounds.height,
                    },
                    border: Default::default(),
                    shadow: Default::default(),
                },
                Palette::BG_SURFACE,
            );
        }

        // Header with channel name
        let header = Rectangle {
            x: bounds.x,
            y: bounds.y,
            width: bounds.width,
            height: Self::HEADER_HEIGHT,
        };

        renderer.fill_quad(
            renderer::Quad {
                bounds: header,
                border: Default::default(),
                shadow: Default::default(),
            },
            Palette::BG_MID,
        );

        // Arm button
        if !self.compact {
            let arm_bounds = self.arm_button_bounds(bounds);
            let arm_bg = if channel.armed {
                Palette::ACCENT_RED
            } else if state.hovered_arm == Some(index) {
                Palette::BG_SURFACE
            } else {
                Palette::BG_MID
            };

            renderer.fill_quad(
                renderer::Quad {
                    bounds: arm_bounds,
                    border: iced::Border {
                        color: Palette::BG_SURFACE,
                        width: 1.0,
                        radius: 2.0.into(),
                    },
                    shadow: Default::default(),
                },
                arm_bg,
            );

            // Mute button
            let mute_bounds = self.mute_button_bounds(bounds);
            let mute_bg = if channel.muted {
                Palette::ACCENT_ORANGE
            } else if state.hovered_mute == Some(index) {
                Palette::BG_SURFACE
            } else {
                Palette::BG_MID
            };

            renderer.fill_quad(
                renderer::Quad {
                    bounds: mute_bounds,
                    border: iced::Border {
                        color: Palette::BG_SURFACE,
                        width: 1.0,
                        radius: 2.0.into(),
                    },
                    shadow: Default::default(),
                },
                mute_bg,
            );
        }

        // Level meter
        let meter_bounds = self.meter_bounds(bounds);
        self.draw_meter(renderer, channel, &meter_bounds);

        // Gain knob
        if !self.compact {
            let gain_bounds = self.gain_knob_bounds(bounds);
            self.draw_gain_knob(renderer, channel, &gain_bounds);
        }

        // Waveform
        if self.show_waveforms && !self.compact {
            let waveform_bounds = self.waveform_bounds(bounds);
            self.draw_waveform(renderer, channel, &waveform_bounds);
        }
    }

    fn draw_meter<Renderer: renderer::Renderer>(
        &self,
        renderer: &mut Renderer,
        channel: &InputChannelState,
        bounds: &Rectangle,
    ) {
        // Meter background
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
            Palette::BG_DEEPEST,
        );

        // Clip indicator at top
        if channel.clipped {
            renderer.fill_quad(
                renderer::Quad {
                    bounds: Rectangle {
                        x: bounds.x + 1.0,
                        y: bounds.y + 1.0,
                        width: bounds.width - 2.0,
                        height: 8.0,
                    },
                    border: iced::Border {
                        radius: iced::border::Radius {
                            top_left: 2.0,
                            top_right: 2.0,
                            bottom_left: 0.0,
                            bottom_right: 0.0,
                        },
                        ..Default::default()
                    },
                    shadow: Default::default(),
                },
                Palette::ACCENT_RED,
            );
        }

        // Level segments
        let num_segments = 24;
        let segment_height = (bounds.height - 12.0) / num_segments as f32;
        let level = if channel.muted { 0.0 } else { channel.level };

        for i in 0..num_segments {
            let segment_level = (num_segments - i) as f32 / num_segments as f32;
            if segment_level <= level {
                let seg_bounds = Rectangle {
                    x: bounds.x + 2.0,
                    y: bounds.y + 10.0 + i as f32 * segment_height + 1.0,
                    width: bounds.width - 4.0,
                    height: segment_height - 1.0,
                };

                renderer.fill_quad(
                    renderer::Quad {
                        bounds: seg_bounds,
                        border: Default::default(),
                        shadow: Default::default(),
                    },
                    meter_color(segment_level),
                );
            }
        }

        // Peak indicator
        if channel.peak > 0.01 {
            let peak_y = bounds.y + 10.0 + (bounds.height - 12.0) * (1.0 - channel.peak);
            renderer.fill_quad(
                renderer::Quad {
                    bounds: Rectangle {
                        x: bounds.x + 2.0,
                        y: peak_y - 1.0,
                        width: bounds.width - 4.0,
                        height: 2.0,
                    },
                    border: Default::default(),
                    shadow: Default::default(),
                },
                if channel.peak > 0.95 {
                    Palette::ACCENT_RED
                } else {
                    Palette::TEXT_PRIMARY
                },
            );
        }

        // 0dB reference line
        let zero_db_y = bounds.y + 10.0 + (bounds.height - 12.0) * 0.25; // ~75% up
        renderer.fill_quad(
            renderer::Quad {
                bounds: Rectangle {
                    x: bounds.x,
                    y: zero_db_y - 0.5,
                    width: bounds.width,
                    height: 1.0,
                },
                border: Default::default(),
                shadow: Default::default(),
            },
            Palette::ACCENT_ORANGE,
        );
    }

    fn draw_gain_knob<Renderer: renderer::Renderer>(
        &self,
        renderer: &mut Renderer,
        channel: &InputChannelState,
        bounds: &Rectangle,
    ) {
        // Knob background
        renderer.fill_quad(
            renderer::Quad {
                bounds: *bounds,
                border: iced::Border {
                    color: Palette::BG_SURFACE,
                    width: 1.0,
                    radius: (bounds.width / 2.0).into(),
                },
                shadow: Default::default(),
            },
            Palette::BG_DEEPEST,
        );

        // Gain arc
        let center_x = bounds.x + bounds.width / 2.0;
        let center_y = bounds.y + bounds.height / 2.0;
        let radius = bounds.width / 2.0 - 4.0;

        // Normalize gain: -60dB to +24dB -> 0.0 to 1.0
        let gain_normalized = ((channel.gain_db + 60.0) / 84.0).clamp(0.0, 1.0) as f32;

        // Draw arc indicator (simplified as line)
        let angle = -135.0_f32.to_radians() + gain_normalized * 270.0_f32.to_radians();
        let end_x = center_x + angle.cos() * radius;
        let end_y = center_y + angle.sin() * radius;

        renderer.fill_quad(
            renderer::Quad {
                bounds: Rectangle {
                    x: end_x - 3.0,
                    y: end_y - 3.0,
                    width: 6.0,
                    height: 6.0,
                },
                border: iced::Border {
                    radius: 3.0.into(),
                    ..Default::default()
                },
                shadow: Default::default(),
            },
            Palette::ACCENT_BLUE,
        );

        // Center dot
        renderer.fill_quad(
            renderer::Quad {
                bounds: Rectangle {
                    x: center_x - 2.0,
                    y: center_y - 2.0,
                    width: 4.0,
                    height: 4.0,
                },
                border: iced::Border {
                    radius: 2.0.into(),
                    ..Default::default()
                },
                shadow: Default::default(),
            },
            Palette::BG_SURFACE,
        );
    }

    fn draw_waveform<Renderer: renderer::Renderer>(
        &self,
        renderer: &mut Renderer,
        channel: &InputChannelState,
        bounds: &Rectangle,
    ) {
        // Waveform background
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
            Palette::BG_DEEPEST,
        );

        if channel.waveform.is_empty() {
            return;
        }

        let center_y = bounds.y + bounds.height / 2.0;
        let half_height = bounds.height / 2.0 - 2.0;

        let samples_per_pixel = channel.waveform.len() as f32 / bounds.width;

        for x in 0..(bounds.width as usize) {
            let sample_idx = (x as f32 * samples_per_pixel) as usize;
            if sample_idx >= channel.waveform.len() {
                break;
            }

            let sample = channel.waveform[sample_idx];
            let height = (sample.abs() * half_height).max(0.5);

            let color = if channel.muted {
                Palette::BG_SURFACE
            } else {
                Palette::ACCENT_CYAN
            };

            renderer.fill_quad(
                renderer::Quad {
                    bounds: Rectangle {
                        x: bounds.x + x as f32,
                        y: center_y - height,
                        width: 1.0,
                        height: height * 2.0,
                    },
                    border: Default::default(),
                    shadow: Default::default(),
                },
                color,
            );
        }

        // Center line
        renderer.fill_quad(
            renderer::Quad {
                bounds: Rectangle {
                    x: bounds.x,
                    y: center_y - 0.5,
                    width: bounds.width,
                    height: 1.0,
                },
                border: Default::default(),
                shadow: Default::default(),
            },
            Palette::BG_SURFACE,
        );
    }
}

impl<'a, Message, Theme, Renderer> From<InputMonitor<'a, Message>> for Element<'a, Message, Theme, Renderer>
where
    Renderer: renderer::Renderer + 'a,
    Message: Clone + 'a,
    Theme: 'a,
{
    fn from(monitor: InputMonitor<'a, Message>) -> Self {
        Element::new(monitor)
    }
}
