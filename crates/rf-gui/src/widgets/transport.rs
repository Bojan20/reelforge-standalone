//! Transport Bar Widget
//!
//! Playback controls, time display, and project info

use iced::advanced::layout::{self, Layout};
use iced::advanced::renderer;
use iced::advanced::widget::{self, Widget};
use iced::advanced::{Clipboard, Shell};
use iced::mouse;
use iced::{Element, Event, Length, Rectangle, Size};

use crate::theme::Palette;

/// Transport state
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum TransportState {
    #[default]
    Stopped,
    Playing,
    Recording,
    Paused,
}

/// Transport bar messages
#[derive(Debug, Clone)]
pub enum TransportMessage {
    Play,
    Pause,
    Stop,
    Record,
    Rewind,
    FastForward,
    ToggleLoop,
    ToggleMetronome,
}

/// Transport bar widget
pub struct TransportBar<'a, Message> {
    state: TransportState,
    position_samples: u64,
    sample_rate: u32,
    tempo: f32,
    loop_enabled: bool,
    metronome_enabled: bool,
    width: f32,
    height: f32,
    on_message: Box<dyn Fn(TransportMessage) -> Message + 'a>,
}

impl<'a, Message> TransportBar<'a, Message> {
    pub fn new<F>(state: TransportState, position_samples: u64, on_message: F) -> Self
    where
        F: Fn(TransportMessage) -> Message + 'a,
    {
        Self {
            state,
            position_samples,
            sample_rate: 48000,
            tempo: 120.0,
            loop_enabled: false,
            metronome_enabled: false,
            width: 600.0,
            height: 48.0,
            on_message: Box::new(on_message),
        }
    }

    pub fn sample_rate(mut self, rate: u32) -> Self {
        self.sample_rate = rate;
        self
    }

    pub fn tempo(mut self, bpm: f32) -> Self {
        self.tempo = bpm;
        self
    }

    pub fn loop_enabled(mut self, enabled: bool) -> Self {
        self.loop_enabled = enabled;
        self
    }

    pub fn metronome_enabled(mut self, enabled: bool) -> Self {
        self.metronome_enabled = enabled;
        self
    }

    pub fn size(mut self, width: f32, height: f32) -> Self {
        self.width = width;
        self.height = height;
        self
    }

    const BUTTON_SIZE: f32 = 36.0;
    const BUTTON_SPACING: f32 = 8.0;

    fn format_time(&self) -> String {
        let total_seconds = self.position_samples as f64 / self.sample_rate as f64;
        let minutes = (total_seconds / 60.0) as u32;
        let seconds = (total_seconds % 60.0) as u32;
        let millis = ((total_seconds % 1.0) * 1000.0) as u32;
        format!("{:02}:{:02}.{:03}", minutes, seconds, millis)
    }

    fn format_bars_beats(&self) -> String {
        let total_seconds = self.position_samples as f64 / self.sample_rate as f64;
        let beats_per_second = self.tempo as f64 / 60.0;
        let total_beats = total_seconds * beats_per_second;

        let bars = (total_beats / 4.0) as u32 + 1;  // Assuming 4/4 time
        let beats = ((total_beats % 4.0) as u32) + 1;
        let ticks = ((total_beats % 1.0) * 96.0) as u32;  // 96 ticks per beat

        format!("{:03}:{:01}.{:02}", bars, beats, ticks)
    }

    fn get_button_bounds(&self, index: usize, bounds: &Rectangle) -> Rectangle {
        let start_x = bounds.x + 16.0;
        let button_y = bounds.y + (bounds.height - Self::BUTTON_SIZE) / 2.0;

        Rectangle {
            x: start_x + index as f32 * (Self::BUTTON_SIZE + Self::BUTTON_SPACING),
            y: button_y,
            width: Self::BUTTON_SIZE,
            height: Self::BUTTON_SIZE,
        }
    }
}

/// Transport bar state
#[derive(Default)]
pub struct TransportBarState {
    hovered_button: Option<usize>,
}

impl<'a, Message, Theme, Renderer> Widget<Message, Theme, Renderer> for TransportBar<'a, Message>
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
        let state = tree.state.downcast_ref::<TransportBarState>();
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

        // Transport buttons
        let buttons = [
            ("rewind", false),
            ("stop", self.state == TransportState::Stopped),
            ("play", self.state == TransportState::Playing),
            ("record", self.state == TransportState::Recording),
            ("forward", false),
        ];

        for (i, (name, active)) in buttons.iter().enumerate() {
            let btn_bounds = self.get_button_bounds(i, &bounds);
            let is_hovered = state.hovered_button == Some(i);

            self.draw_button(renderer, &btn_bounds, name, *active, is_hovered);
        }

        // Time display
        let time_x = bounds.x + 16.0 + 5.0 * (Self::BUTTON_SIZE + Self::BUTTON_SPACING) + 16.0;
        let time_bounds = Rectangle {
            x: time_x,
            y: bounds.y + 4.0,
            width: 120.0,
            height: bounds.height - 8.0,
        };

        // Time display background
        renderer.fill_quad(
            renderer::Quad {
                bounds: time_bounds,
                border: iced::Border {
                    color: Palette::BG_SURFACE,
                    width: 1.0,
                    radius: 4.0.into(),
                },
                shadow: Default::default(),
            },
            Palette::BG_DEEPEST,
        );

        // Bars/Beats display
        let bars_x = time_x + 130.0;
        let bars_bounds = Rectangle {
            x: bars_x,
            y: bounds.y + 4.0,
            width: 100.0,
            height: bounds.height - 8.0,
        };

        renderer.fill_quad(
            renderer::Quad {
                bounds: bars_bounds,
                border: iced::Border {
                    color: Palette::BG_SURFACE,
                    width: 1.0,
                    radius: 4.0.into(),
                },
                shadow: Default::default(),
            },
            Palette::BG_DEEPEST,
        );

        // Tempo display
        let tempo_x = bars_x + 110.0;
        let tempo_bounds = Rectangle {
            x: tempo_x,
            y: bounds.y + 4.0,
            width: 70.0,
            height: bounds.height - 8.0,
        };

        renderer.fill_quad(
            renderer::Quad {
                bounds: tempo_bounds,
                border: iced::Border {
                    color: Palette::BG_SURFACE,
                    width: 1.0,
                    radius: 4.0.into(),
                },
                shadow: Default::default(),
            },
            Palette::BG_DEEPEST,
        );

        // Loop button
        let loop_x = tempo_x + 80.0;
        let loop_bounds = Rectangle {
            x: loop_x,
            y: bounds.y + (bounds.height - Self::BUTTON_SIZE) / 2.0,
            width: Self::BUTTON_SIZE,
            height: Self::BUTTON_SIZE,
        };

        self.draw_toggle_button(renderer, &loop_bounds, "loop", self.loop_enabled, state.hovered_button == Some(5));

        // Metronome button
        let metro_bounds = Rectangle {
            x: loop_x + Self::BUTTON_SIZE + 4.0,
            y: bounds.y + (bounds.height - Self::BUTTON_SIZE) / 2.0,
            width: Self::BUTTON_SIZE,
            height: Self::BUTTON_SIZE,
        };

        self.draw_toggle_button(renderer, &metro_bounds, "metro", self.metronome_enabled, state.hovered_button == Some(6));
    }

    fn tag(&self) -> widget::tree::Tag {
        widget::tree::Tag::of::<TransportBarState>()
    }

    fn state(&self) -> widget::tree::State {
        widget::tree::State::new(TransportBarState::default())
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
        let state = tree.state.downcast_mut::<TransportBarState>();
        let bounds = layout.bounds();

        match event {
            Event::Mouse(mouse::Event::ButtonPressed(mouse::Button::Left)) => {
                if let Some(pos) = cursor.position() {
                    // Check transport buttons
                    let messages = [
                        TransportMessage::Rewind,
                        TransportMessage::Stop,
                        TransportMessage::Play,
                        TransportMessage::Record,
                        TransportMessage::FastForward,
                    ];

                    for (i, msg) in messages.iter().enumerate() {
                        let btn_bounds = self.get_button_bounds(i, &bounds);
                        if btn_bounds.contains(pos) {
                            shell.publish((self.on_message)(msg.clone()));
                            return iced::event::Status::Captured;
                        }
                    }

                    // Check loop button
                    let time_x = bounds.x + 16.0 + 5.0 * (Self::BUTTON_SIZE + Self::BUTTON_SPACING) + 16.0;
                    let loop_x = time_x + 130.0 + 110.0 + 80.0;
                    let loop_bounds = Rectangle {
                        x: loop_x,
                        y: bounds.y + (bounds.height - Self::BUTTON_SIZE) / 2.0,
                        width: Self::BUTTON_SIZE,
                        height: Self::BUTTON_SIZE,
                    };

                    if loop_bounds.contains(pos) {
                        shell.publish((self.on_message)(TransportMessage::ToggleLoop));
                        return iced::event::Status::Captured;
                    }

                    // Check metronome button
                    let metro_bounds = Rectangle {
                        x: loop_x + Self::BUTTON_SIZE + 4.0,
                        y: bounds.y + (bounds.height - Self::BUTTON_SIZE) / 2.0,
                        width: Self::BUTTON_SIZE,
                        height: Self::BUTTON_SIZE,
                    };

                    if metro_bounds.contains(pos) {
                        shell.publish((self.on_message)(TransportMessage::ToggleMetronome));
                        return iced::event::Status::Captured;
                    }
                }
            }

            Event::Mouse(mouse::Event::CursorMoved { position }) => {
                state.hovered_button = None;

                for i in 0..5 {
                    let btn_bounds = self.get_button_bounds(i, &bounds);
                    if btn_bounds.contains(position) {
                        state.hovered_button = Some(i);
                        break;
                    }
                }
            }

            Event::Mouse(mouse::Event::CursorLeft) => {
                state.hovered_button = None;
            }

            _ => {}
        }

        iced::event::Status::Ignored
    }

    fn mouse_interaction(
        &self,
        tree: &widget::Tree,
        _layout: Layout<'_>,
        _cursor: mouse::Cursor,
        _viewport: &Rectangle,
        _renderer: &Renderer,
    ) -> mouse::Interaction {
        let state = tree.state.downcast_ref::<TransportBarState>();

        if state.hovered_button.is_some() {
            mouse::Interaction::Pointer
        } else {
            mouse::Interaction::default()
        }
    }
}

impl<'a, Message> TransportBar<'a, Message> {
    fn draw_button<Renderer: renderer::Renderer>(
        &self,
        renderer: &mut Renderer,
        bounds: &Rectangle,
        name: &str,
        active: bool,
        is_hovered: bool,
    ) {
        let bg_color = if active {
            match name {
                "record" => Palette::ACCENT_RED,
                "play" => Palette::ACCENT_GREEN,
                _ => Palette::ACCENT_BLUE,
            }
        } else if is_hovered {
            Palette::BG_SURFACE
        } else {
            Palette::BG_MID
        };

        // Button background
        renderer.fill_quad(
            renderer::Quad {
                bounds: *bounds,
                border: iced::Border {
                    color: if active {
                        bg_color
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

        // Draw icon based on name
        let icon_color = if active {
            Palette::TEXT_PRIMARY
        } else {
            Palette::TEXT_SECONDARY
        };

        let center_x = bounds.x + bounds.width / 2.0;
        let center_y = bounds.y + bounds.height / 2.0;

        match name {
            "rewind" => {
                // Two triangles pointing left
                self.draw_triangle(renderer, center_x - 4.0, center_y, 6.0, true, icon_color);
                self.draw_triangle(renderer, center_x + 4.0, center_y, 6.0, true, icon_color);
            }
            "stop" => {
                // Square
                renderer.fill_quad(
                    renderer::Quad {
                        bounds: Rectangle {
                            x: center_x - 6.0,
                            y: center_y - 6.0,
                            width: 12.0,
                            height: 12.0,
                        },
                        border: Default::default(),
                        shadow: Default::default(),
                    },
                    icon_color,
                );
            }
            "play" => {
                // Triangle pointing right
                self.draw_triangle(renderer, center_x, center_y, 8.0, false, icon_color);
            }
            "record" => {
                // Circle
                renderer.fill_quad(
                    renderer::Quad {
                        bounds: Rectangle {
                            x: center_x - 6.0,
                            y: center_y - 6.0,
                            width: 12.0,
                            height: 12.0,
                        },
                        border: iced::Border {
                            color: icon_color,
                            width: 0.0,
                            radius: 6.0.into(),
                        },
                        shadow: Default::default(),
                    },
                    icon_color,
                );
            }
            "forward" => {
                // Two triangles pointing right
                self.draw_triangle(renderer, center_x - 4.0, center_y, 6.0, false, icon_color);
                self.draw_triangle(renderer, center_x + 4.0, center_y, 6.0, false, icon_color);
            }
            _ => {}
        }
    }

    fn draw_toggle_button<Renderer: renderer::Renderer>(
        &self,
        renderer: &mut Renderer,
        bounds: &Rectangle,
        _name: &str,
        active: bool,
        is_hovered: bool,
    ) {
        let bg_color = if active {
            Palette::ACCENT_CYAN
        } else if is_hovered {
            Palette::BG_SURFACE
        } else {
            Palette::BG_MID
        };

        renderer.fill_quad(
            renderer::Quad {
                bounds: *bounds,
                border: iced::Border {
                    color: if active {
                        Palette::ACCENT_CYAN
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
    }

    fn draw_triangle<Renderer: renderer::Renderer>(
        &self,
        renderer: &mut Renderer,
        x: f32,
        y: f32,
        size: f32,
        left: bool,
        color: iced::Color,
    ) {
        // Approximate triangle with rectangles
        let dir = if left { -1.0 } else { 1.0 };
        let half = size / 2.0;

        for i in 0..(size as i32) {
            let progress = i as f32 / size;
            let width = size * (1.0 - progress);
            let offset = i as f32 * dir;

            renderer.fill_quad(
                renderer::Quad {
                    bounds: Rectangle {
                        x: x + offset - if left { width } else { 0.0 },
                        y: y - width / 2.0,
                        width: 1.0,
                        height: width,
                    },
                    border: Default::default(),
                    shadow: Default::default(),
                },
                color,
            );
        }
    }
}

impl<'a, Message, Theme, Renderer> From<TransportBar<'a, Message>> for Element<'a, Message, Theme, Renderer>
where
    Renderer: renderer::Renderer + 'a,
    Message: Clone + 'a,
    Theme: 'a,
{
    fn from(bar: TransportBar<'a, Message>) -> Self {
        Element::new(bar)
    }
}
