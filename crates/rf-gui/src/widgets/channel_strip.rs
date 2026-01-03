//! Channel Strip Widget
//!
//! Mixer channel strip with:
//! - Level fader
//! - Stereo meter
//! - Pan knob
//! - Mute/Solo/Arm buttons
//! - Insert slots
//! - Send knobs
//! - Track name and color

use iced::advanced::layout::{self, Layout};
use iced::advanced::renderer;
use iced::advanced::widget::{self, Widget};
use iced::advanced::{Clipboard, Shell};
use iced::mouse;
use iced::{Element, Event, Length, Rectangle, Size};

use crate::theme::{meter_color, Palette};

// ═══════════════════════════════════════════════════════════════════════════════
// CHANNEL STRIP TYPES
// ═══════════════════════════════════════════════════════════════════════════════

/// Channel type
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum ChannelType {
    #[default]
    Audio,
    Instrument,
    Bus,
    Master,
    Aux,
}

/// Insert slot state for channel strip
#[derive(Debug, Clone, Default)]
pub struct ChannelInsertSlot {
    pub occupied: bool,
    pub plugin_name: Option<String>,
    pub bypassed: bool,
}

/// Send state for channel strip
#[derive(Debug, Clone)]
pub struct ChannelSendSlot {
    pub destination: String,
    pub level: f32,  // 0.0 to 1.0
    pub pre_fader: bool,
}

/// Channel strip messages
#[derive(Debug, Clone)]
pub enum ChannelStripMessage {
    /// Volume changed (0.0 to 1.0)
    VolumeChanged(f32),
    /// Pan changed (-1.0 to 1.0)
    PanChanged(f32),
    /// Mute toggled
    ToggleMute,
    /// Solo toggled
    ToggleSolo,
    /// Record arm toggled
    ToggleArm,
    /// Insert slot clicked (slot index)
    InsertClicked(usize),
    /// Send level changed (send index, level)
    SendChanged(usize, f32),
    /// Channel selected
    Selected,
    /// Output routing clicked
    OutputClicked,
}

/// Channel strip data
#[derive(Debug, Clone)]
pub struct ChannelStripData {
    pub id: String,
    pub name: String,
    pub channel_type: ChannelType,
    pub volume: f32,       // 0.0 to 1.0
    pub volume_db: f64,    // in dB
    pub pan: f32,          // -1.0 to 1.0
    pub mute: bool,
    pub solo: bool,
    pub armed: bool,
    pub color: Option<u32>,
    pub level_left: f32,   // 0.0 to 1.0
    pub level_right: f32,  // 0.0 to 1.0
    pub peak_left: f32,
    pub peak_right: f32,
    pub inserts: Vec<ChannelInsertSlot>,
    pub sends: Vec<ChannelSendSlot>,
    pub output: String,
    pub selected: bool,
}

impl Default for ChannelStripData {
    fn default() -> Self {
        Self {
            id: String::new(),
            name: "Track".to_string(),
            channel_type: ChannelType::Audio,
            volume: 0.75,  // ~0dB
            volume_db: 0.0,
            pan: 0.0,
            mute: false,
            solo: false,
            armed: false,
            color: None,
            level_left: 0.0,
            level_right: 0.0,
            peak_left: 0.0,
            peak_right: 0.0,
            inserts: vec![ChannelInsertSlot::default(); 8],
            sends: Vec::new(),
            output: "Master".to_string(),
            selected: false,
        }
    }
}

impl ChannelStripData {
    pub fn new(id: &str, name: &str) -> Self {
        Self {
            id: id.to_string(),
            name: name.to_string(),
            ..Default::default()
        }
    }

    pub fn channel_type(mut self, channel_type: ChannelType) -> Self {
        self.channel_type = channel_type;
        self
    }

    pub fn volume_db_to_linear(db: f64) -> f32 {
        if db <= -96.0 {
            0.0
        } else {
            10.0_f64.powf(db / 20.0) as f32
        }
    }

    pub fn linear_to_db(linear: f32) -> f64 {
        if linear <= 0.0 {
            -96.0
        } else {
            20.0 * (linear as f64).log10()
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CHANNEL STRIP WIDGET
// ═══════════════════════════════════════════════════════════════════════════════

/// Channel strip widget
pub struct ChannelStrip<'a, Message> {
    data: &'a ChannelStripData,
    width: f32,
    height: f32,
    show_inserts: bool,
    show_sends: bool,
    compact: bool,
    on_message: Option<Box<dyn Fn(ChannelStripMessage) -> Message + 'a>>,
}

impl<'a, Message> ChannelStrip<'a, Message> {
    pub fn new(data: &'a ChannelStripData) -> Self {
        Self {
            data,
            width: 80.0,
            height: 500.0,
            show_inserts: true,
            show_sends: true,
            compact: false,
            on_message: None,
        }
    }

    pub fn size(mut self, width: f32, height: f32) -> Self {
        self.width = width;
        self.height = height;
        self
    }

    pub fn show_inserts(mut self, show: bool) -> Self {
        self.show_inserts = show;
        self
    }

    pub fn show_sends(mut self, show: bool) -> Self {
        self.show_sends = show;
        self
    }

    pub fn compact(mut self, compact: bool) -> Self {
        self.compact = compact;
        if compact {
            self.width = 60.0;
        }
        self
    }

    pub fn on_message<F>(mut self, callback: F) -> Self
    where
        F: Fn(ChannelStripMessage) -> Message + 'a,
    {
        self.on_message = Some(Box::new(callback));
        self
    }

    // Layout constants
    const HEADER_HEIGHT: f32 = 24.0;
    const BUTTON_SIZE: f32 = 20.0;
    const BUTTON_SPACING: f32 = 4.0;
    const INSERT_SLOT_HEIGHT: f32 = 20.0;
    const SEND_HEIGHT: f32 = 24.0;
    const PAN_SIZE: f32 = 32.0;
    const FADER_WIDTH: f32 = 32.0;
    const METER_WIDTH: f32 = 24.0;
    const PADDING: f32 = 4.0;

    fn get_insert_bounds(&self, index: usize, bounds: &Rectangle) -> Rectangle {
        let y_offset = Self::HEADER_HEIGHT + Self::BUTTON_SIZE + Self::BUTTON_SPACING * 2.0;
        Rectangle {
            x: bounds.x + Self::PADDING,
            y: bounds.y + y_offset + index as f32 * (Self::INSERT_SLOT_HEIGHT + 2.0),
            width: bounds.width - Self::PADDING * 2.0,
            height: Self::INSERT_SLOT_HEIGHT,
        }
    }

    fn get_button_bounds(&self, index: usize, bounds: &Rectangle) -> Rectangle {
        let buttons_start_x = bounds.x + Self::PADDING;
        Rectangle {
            x: buttons_start_x + index as f32 * (Self::BUTTON_SIZE + Self::BUTTON_SPACING),
            y: bounds.y + Self::HEADER_HEIGHT,
            width: Self::BUTTON_SIZE,
            height: Self::BUTTON_SIZE,
        }
    }

    fn get_fader_bounds(&self, bounds: &Rectangle) -> Rectangle {
        let fader_height = 150.0;
        let y_offset = bounds.height - fader_height - 30.0; // Leave room for output
        Rectangle {
            x: bounds.x + Self::PADDING,
            y: bounds.y + y_offset,
            width: Self::FADER_WIDTH,
            height: fader_height,
        }
    }

    fn get_meter_bounds(&self, bounds: &Rectangle) -> Rectangle {
        let fader = self.get_fader_bounds(bounds);
        Rectangle {
            x: fader.x + fader.width + 4.0,
            y: fader.y,
            width: Self::METER_WIDTH,
            height: fader.height,
        }
    }

    fn get_pan_bounds(&self, bounds: &Rectangle) -> Rectangle {
        let fader = self.get_fader_bounds(bounds);
        Rectangle {
            x: bounds.x + (bounds.width - Self::PAN_SIZE) / 2.0,
            y: fader.y - Self::PAN_SIZE - 8.0,
            width: Self::PAN_SIZE,
            height: Self::PAN_SIZE,
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CHANNEL STRIP STATE
// ═══════════════════════════════════════════════════════════════════════════════

#[derive(Default)]
pub struct ChannelStripState {
    dragging_fader: bool,
    dragging_pan: bool,
    hovered_insert: Option<usize>,
    hovered_button: Option<usize>,
}

// ═══════════════════════════════════════════════════════════════════════════════
// WIDGET IMPLEMENTATION
// ═══════════════════════════════════════════════════════════════════════════════

impl<'a, Message, Theme, Renderer> Widget<Message, Theme, Renderer> for ChannelStrip<'a, Message>
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
        let state = tree.state.downcast_ref::<ChannelStripState>();
        let bounds = layout.bounds();

        // Background
        let bg_color = if self.data.selected {
            iced::Color::from_rgba(0.15, 0.15, 0.2, 1.0)
        } else {
            Palette::BG_DEEP
        };

        renderer.fill_quad(
            renderer::Quad {
                bounds,
                border: iced::Border {
                    color: if self.data.selected {
                        Palette::ACCENT_BLUE
                    } else {
                        Palette::BG_SURFACE
                    },
                    width: 1.0,
                    radius: 4.0.into(),
                },
                shadow: Default::default(),
            },
            bg_color,
        );

        // Draw sections
        self.draw_header(renderer, &bounds);
        self.draw_buttons(renderer, &bounds, state);

        if self.show_inserts && !self.compact {
            self.draw_inserts(renderer, &bounds, state);
        }

        self.draw_pan(renderer, &bounds);
        self.draw_fader_and_meter(renderer, &bounds);
        self.draw_output(renderer, &bounds);
    }

    fn tag(&self) -> widget::tree::Tag {
        widget::tree::Tag::of::<ChannelStripState>()
    }

    fn state(&self) -> widget::tree::State {
        widget::tree::State::new(ChannelStripState::default())
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
        let state = tree.state.downcast_mut::<ChannelStripState>();
        let bounds = layout.bounds();

        match event {
            Event::Mouse(mouse::Event::ButtonPressed(mouse::Button::Left)) => {
                if let Some(pos) = cursor.position() {
                    if bounds.contains(pos) {
                        // Check fader
                        let fader = self.get_fader_bounds(&bounds);
                        if fader.contains(pos) {
                            state.dragging_fader = true;
                            let new_value = 1.0 - ((pos.y - fader.y) / fader.height).clamp(0.0, 1.0);
                            if let Some(ref on_message) = self.on_message {
                                shell.publish(on_message(ChannelStripMessage::VolumeChanged(new_value)));
                            }
                            return iced::event::Status::Captured;
                        }

                        // Check pan
                        let pan = self.get_pan_bounds(&bounds);
                        if pan.contains(pos) {
                            state.dragging_pan = true;
                            let new_value = ((pos.x - pan.x) / pan.width * 2.0 - 1.0).clamp(-1.0, 1.0);
                            if let Some(ref on_message) = self.on_message {
                                shell.publish(on_message(ChannelStripMessage::PanChanged(new_value)));
                            }
                            return iced::event::Status::Captured;
                        }

                        // Check buttons (M, S, R)
                        let button_names = [
                            ChannelStripMessage::ToggleMute,
                            ChannelStripMessage::ToggleSolo,
                            ChannelStripMessage::ToggleArm,
                        ];
                        for (i, msg) in button_names.iter().enumerate() {
                            let btn = self.get_button_bounds(i, &bounds);
                            if btn.contains(pos) {
                                if let Some(ref on_message) = self.on_message {
                                    shell.publish(on_message(msg.clone()));
                                }
                                return iced::event::Status::Captured;
                            }
                        }

                        // Check inserts
                        if self.show_inserts && !self.compact {
                            for i in 0..8 {
                                let insert = self.get_insert_bounds(i, &bounds);
                                if insert.contains(pos) {
                                    if let Some(ref on_message) = self.on_message {
                                        shell.publish(on_message(ChannelStripMessage::InsertClicked(i)));
                                    }
                                    return iced::event::Status::Captured;
                                }
                            }
                        }

                        // Select channel
                        if let Some(ref on_message) = self.on_message {
                            shell.publish(on_message(ChannelStripMessage::Selected));
                        }
                        return iced::event::Status::Captured;
                    }
                }
            }

            Event::Mouse(mouse::Event::ButtonReleased(mouse::Button::Left)) => {
                if state.dragging_fader || state.dragging_pan {
                    state.dragging_fader = false;
                    state.dragging_pan = false;
                    return iced::event::Status::Captured;
                }
            }

            Event::Mouse(mouse::Event::CursorMoved { position }) => {
                // Update hovered states
                state.hovered_button = None;
                state.hovered_insert = None;

                if bounds.contains(position) {
                    for i in 0..3 {
                        if self.get_button_bounds(i, &bounds).contains(position) {
                            state.hovered_button = Some(i);
                            break;
                        }
                    }

                    if self.show_inserts && !self.compact {
                        for i in 0..8 {
                            if self.get_insert_bounds(i, &bounds).contains(position) {
                                state.hovered_insert = Some(i);
                                break;
                            }
                        }
                    }
                }

                // Handle fader drag
                if state.dragging_fader {
                    let fader = self.get_fader_bounds(&bounds);
                    let new_value = 1.0 - ((position.y - fader.y) / fader.height).clamp(0.0, 1.0);
                    if let Some(ref on_message) = self.on_message {
                        shell.publish(on_message(ChannelStripMessage::VolumeChanged(new_value)));
                    }
                    return iced::event::Status::Captured;
                }

                // Handle pan drag
                if state.dragging_pan {
                    let pan = self.get_pan_bounds(&bounds);
                    let new_value = ((position.x - pan.x) / pan.width * 2.0 - 1.0).clamp(-1.0, 1.0);
                    if let Some(ref on_message) = self.on_message {
                        shell.publish(on_message(ChannelStripMessage::PanChanged(new_value)));
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
        let state = tree.state.downcast_ref::<ChannelStripState>();
        let bounds = layout.bounds();

        if state.dragging_fader || state.dragging_pan {
            return mouse::Interaction::Grabbing;
        }

        if let Some(pos) = cursor.position() {
            if self.get_fader_bounds(&bounds).contains(pos) || self.get_pan_bounds(&bounds).contains(pos) {
                return mouse::Interaction::Grab;
            }
            if state.hovered_button.is_some() || state.hovered_insert.is_some() {
                return mouse::Interaction::Pointer;
            }
        }

        mouse::Interaction::default()
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DRAWING HELPERS
// ═══════════════════════════════════════════════════════════════════════════════

impl<'a, Message> ChannelStrip<'a, Message>
where
    Message: Clone,
{
    fn draw_header<Renderer: renderer::Renderer>(&self, renderer: &mut Renderer, bounds: &Rectangle) {
        let header = Rectangle {
            x: bounds.x,
            y: bounds.y,
            width: bounds.width,
            height: Self::HEADER_HEIGHT,
        };

        // Color bar
        let color = self.data.color.map(|c| {
            iced::Color::from_rgb(
                ((c >> 16) & 0xFF) as f32 / 255.0,
                ((c >> 8) & 0xFF) as f32 / 255.0,
                (c & 0xFF) as f32 / 255.0,
            )
        }).unwrap_or(Palette::ACCENT_CYAN);

        renderer.fill_quad(
            renderer::Quad {
                bounds: Rectangle {
                    x: header.x,
                    y: header.y,
                    width: header.width,
                    height: 4.0,
                },
                border: iced::Border {
                    radius: iced::border::Radius {
                        top_left: 4.0,
                        top_right: 4.0,
                        bottom_left: 0.0,
                        bottom_right: 0.0,
                    },
                    ..Default::default()
                },
                shadow: Default::default(),
            },
            color,
        );

        // Header background
        renderer.fill_quad(
            renderer::Quad {
                bounds: Rectangle {
                    x: header.x,
                    y: header.y + 4.0,
                    width: header.width,
                    height: header.height - 4.0,
                },
                border: Default::default(),
                shadow: Default::default(),
            },
            Palette::BG_MID,
        );
    }

    fn draw_buttons<Renderer: renderer::Renderer>(
        &self,
        renderer: &mut Renderer,
        bounds: &Rectangle,
        state: &ChannelStripState,
    ) {
        let buttons = [
            ("M", self.data.mute, Palette::ACCENT_ORANGE),
            ("S", self.data.solo, Palette::ACCENT_YELLOW),
            ("R", self.data.armed, Palette::ACCENT_RED),
        ];

        for (i, (_label, active, active_color)) in buttons.iter().enumerate() {
            let btn_bounds = self.get_button_bounds(i, bounds);
            let is_hovered = state.hovered_button == Some(i);

            let bg = if *active {
                *active_color
            } else if is_hovered {
                Palette::BG_SURFACE
            } else {
                Palette::BG_MID
            };

            renderer.fill_quad(
                renderer::Quad {
                    bounds: btn_bounds,
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
    }

    fn draw_inserts<Renderer: renderer::Renderer>(
        &self,
        renderer: &mut Renderer,
        bounds: &Rectangle,
        state: &ChannelStripState,
    ) {
        for (i, insert) in self.data.inserts.iter().enumerate() {
            let insert_bounds = self.get_insert_bounds(i, bounds);
            let is_hovered = state.hovered_insert == Some(i);

            let bg = if insert.occupied {
                if insert.bypassed {
                    Palette::BG_SURFACE
                } else {
                    iced::Color::from_rgba(0.2, 0.3, 0.4, 1.0)
                }
            } else if is_hovered {
                Palette::BG_SURFACE
            } else {
                Palette::BG_DEEPEST
            };

            renderer.fill_quad(
                renderer::Quad {
                    bounds: insert_bounds,
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
    }

    fn draw_pan<Renderer: renderer::Renderer>(&self, renderer: &mut Renderer, bounds: &Rectangle) {
        let pan_bounds = self.get_pan_bounds(bounds);
        let center = pan_bounds.x + pan_bounds.width / 2.0;

        // Pan background
        renderer.fill_quad(
            renderer::Quad {
                bounds: pan_bounds,
                border: iced::Border {
                    color: Palette::BG_SURFACE,
                    width: 1.0,
                    radius: (pan_bounds.width / 2.0).into(),
                },
                shadow: Default::default(),
            },
            Palette::BG_DEEPEST,
        );

        // Pan indicator
        let pan_x = center + self.data.pan * (pan_bounds.width / 2.0 - 4.0);
        renderer.fill_quad(
            renderer::Quad {
                bounds: Rectangle {
                    x: pan_x - 3.0,
                    y: pan_bounds.y + pan_bounds.height / 2.0 - 3.0,
                    width: 6.0,
                    height: 6.0,
                },
                border: iced::Border {
                    color: Palette::ACCENT_BLUE,
                    width: 0.0,
                    radius: 3.0.into(),
                },
                shadow: Default::default(),
            },
            Palette::ACCENT_BLUE,
        );

        // Center line
        renderer.fill_quad(
            renderer::Quad {
                bounds: Rectangle {
                    x: center - 0.5,
                    y: pan_bounds.y + 2.0,
                    width: 1.0,
                    height: pan_bounds.height - 4.0,
                },
                border: Default::default(),
                shadow: Default::default(),
            },
            Palette::BG_SURFACE,
        );
    }

    fn draw_fader_and_meter<Renderer: renderer::Renderer>(&self, renderer: &mut Renderer, bounds: &Rectangle) {
        let fader_bounds = self.get_fader_bounds(bounds);
        let meter_bounds = self.get_meter_bounds(bounds);

        // Fader track
        let track_width = 4.0;
        let track_x = fader_bounds.x + (fader_bounds.width - track_width) / 2.0;
        let track = Rectangle {
            x: track_x,
            y: fader_bounds.y,
            width: track_width,
            height: fader_bounds.height,
        };

        renderer.fill_quad(
            renderer::Quad {
                bounds: track,
                border: iced::Border {
                    color: Palette::BG_SURFACE,
                    width: 0.0,
                    radius: 2.0.into(),
                },
                shadow: Default::default(),
            },
            Palette::BG_DEEPEST,
        );

        // Unity gain marker (0dB)
        let unity_y = fader_bounds.y + fader_bounds.height * 0.25; // ~0dB at 75%
        renderer.fill_quad(
            renderer::Quad {
                bounds: Rectangle {
                    x: fader_bounds.x,
                    y: unity_y - 0.5,
                    width: fader_bounds.width,
                    height: 1.0,
                },
                border: Default::default(),
                shadow: Default::default(),
            },
            Palette::ACCENT_ORANGE,
        );

        // Filled portion
        let filled_height = fader_bounds.height * self.data.volume;
        let filled = Rectangle {
            x: track_x,
            y: track.y + track.height - filled_height,
            width: track_width,
            height: filled_height,
        };

        renderer.fill_quad(
            renderer::Quad {
                bounds: filled,
                border: Default::default(),
                shadow: Default::default(),
            },
            Palette::ACCENT_BLUE,
        );

        // Fader handle
        let handle_height = 20.0;
        let handle_y = fader_bounds.y + fader_bounds.height * (1.0 - self.data.volume) - handle_height / 2.0;
        let handle = Rectangle {
            x: fader_bounds.x,
            y: handle_y.clamp(fader_bounds.y, fader_bounds.y + fader_bounds.height - handle_height),
            width: fader_bounds.width,
            height: handle_height,
        };

        renderer.fill_quad(
            renderer::Quad {
                bounds: handle,
                border: iced::Border {
                    color: Palette::BG_SURFACE,
                    width: 1.0,
                    radius: 3.0.into(),
                },
                shadow: Default::default(),
            },
            Palette::BG_MID,
        );

        // Handle center line
        renderer.fill_quad(
            renderer::Quad {
                bounds: Rectangle {
                    x: handle.x + 4.0,
                    y: handle.y + handle.height / 2.0 - 0.5,
                    width: handle.width - 8.0,
                    height: 1.0,
                },
                border: Default::default(),
                shadow: Default::default(),
            },
            Palette::TEXT_SECONDARY,
        );

        // Draw stereo meter
        let meter_half_width = (meter_bounds.width - 2.0) / 2.0;

        // Meter backgrounds
        for (i, level, peak) in [
            (0, self.data.level_left, self.data.peak_left),
            (1, self.data.level_right, self.data.peak_right),
        ] {
            let m_bounds = Rectangle {
                x: meter_bounds.x + i as f32 * (meter_half_width + 2.0),
                y: meter_bounds.y,
                width: meter_half_width,
                height: meter_bounds.height,
            };

            renderer.fill_quad(
                renderer::Quad {
                    bounds: m_bounds,
                    border: iced::Border {
                        color: Palette::BG_SURFACE,
                        width: 1.0,
                        radius: 2.0.into(),
                    },
                    shadow: Default::default(),
                },
                Palette::BG_DEEPEST,
            );

            // Level segments
            let num_segments = 20;
            let segment_height = m_bounds.height / num_segments as f32;

            for seg in 0..num_segments {
                let segment_level = (num_segments - seg) as f32 / num_segments as f32;
                if segment_level <= level {
                    let seg_bounds = Rectangle {
                        x: m_bounds.x + 1.0,
                        y: m_bounds.y + seg as f32 * segment_height + 1.0,
                        width: m_bounds.width - 2.0,
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
            if peak > 0.0 {
                let peak_y = m_bounds.y + m_bounds.height * (1.0 - peak);
                renderer.fill_quad(
                    renderer::Quad {
                        bounds: Rectangle {
                            x: m_bounds.x + 1.0,
                            y: peak_y - 1.0,
                            width: m_bounds.width - 2.0,
                            height: 2.0,
                        },
                        border: Default::default(),
                        shadow: Default::default(),
                    },
                    if peak > 0.95 { Palette::METER_RED } else { Palette::TEXT_PRIMARY },
                );
            }
        }
    }

    fn draw_output<Renderer: renderer::Renderer>(&self, renderer: &mut Renderer, bounds: &Rectangle) {
        let output_bounds = Rectangle {
            x: bounds.x + Self::PADDING,
            y: bounds.y + bounds.height - 24.0,
            width: bounds.width - Self::PADDING * 2.0,
            height: 20.0,
        };

        renderer.fill_quad(
            renderer::Quad {
                bounds: output_bounds,
                border: iced::Border {
                    color: Palette::BG_SURFACE,
                    width: 1.0,
                    radius: 2.0.into(),
                },
                shadow: Default::default(),
            },
            Palette::BG_DEEPEST,
        );
    }
}

impl<'a, Message, Theme, Renderer> From<ChannelStrip<'a, Message>> for Element<'a, Message, Theme, Renderer>
where
    Renderer: renderer::Renderer + 'a,
    Message: Clone + 'a,
    Theme: 'a,
{
    fn from(strip: ChannelStrip<'a, Message>) -> Self {
        Element::new(strip)
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PALETTE EXTENSION
// ═══════════════════════════════════════════════════════════════════════════════

impl Palette {
    pub const ACCENT_YELLOW_STRIP: iced::Color = iced::Color::from_rgb(1.0, 1.0, 0.25);
}
