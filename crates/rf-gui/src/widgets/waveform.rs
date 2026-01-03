//! Waveform Display Widget
//!
//! Audio waveform visualization with:
//! - Min/max display
//! - Zoom and scroll
//! - RMS overlay
//! - Playhead position

use iced::advanced::layout::{self, Layout};
use iced::advanced::renderer;
use iced::advanced::widget::{self, Widget};
use iced::advanced::{Clipboard, Shell};
use iced::mouse;
use iced::{Element, Event, Length, Rectangle, Size};

use crate::theme::Palette;

/// Waveform data point (min/max pair for a range of samples)
#[derive(Debug, Clone, Copy, Default)]
pub struct WaveformPoint {
    pub min: f32,
    pub max: f32,
    pub rms: f32,
}

/// Waveform display messages
#[derive(Debug, Clone)]
pub enum WaveformMessage {
    /// Playhead position changed (0.0 - 1.0)
    SeekTo(f32),
    /// Selection changed (start, end as 0.0 - 1.0)
    SelectionChanged(f32, f32),
    /// Zoom changed (samples per pixel)
    ZoomChanged(f32),
}

/// Waveform display widget
pub struct WaveformDisplay<'a, Message> {
    /// Waveform data (min/max per display column)
    data: &'a [WaveformPoint],
    /// Playhead position (0.0 - 1.0)
    playhead: f32,
    /// Selection range (start, end)
    selection: Option<(f32, f32)>,
    /// Scroll offset (0.0 - 1.0)
    scroll: f32,
    /// Zoom level (visible portion 0.0 - 1.0)
    zoom: f32,
    /// Widget dimensions
    width: f32,
    height: f32,
    /// Show RMS overlay
    show_rms: bool,
    /// Message callback
    on_message: Option<Box<dyn Fn(WaveformMessage) -> Message + 'a>>,
}

impl<'a, Message> WaveformDisplay<'a, Message> {
    pub fn new(data: &'a [WaveformPoint]) -> Self {
        Self {
            data,
            playhead: 0.0,
            selection: None,
            scroll: 0.0,
            zoom: 1.0,
            width: 800.0,
            height: 100.0,
            show_rms: true,
            on_message: None,
        }
    }

    pub fn playhead(mut self, position: f32) -> Self {
        self.playhead = position.clamp(0.0, 1.0);
        self
    }

    pub fn selection(mut self, start: f32, end: f32) -> Self {
        self.selection = Some((start.clamp(0.0, 1.0), end.clamp(0.0, 1.0)));
        self
    }

    pub fn scroll(mut self, offset: f32) -> Self {
        self.scroll = offset.clamp(0.0, 1.0);
        self
    }

    pub fn zoom(mut self, level: f32) -> Self {
        self.zoom = level.clamp(0.01, 1.0);
        self
    }

    pub fn size(mut self, width: f32, height: f32) -> Self {
        self.width = width;
        self.height = height;
        self
    }

    pub fn show_rms(mut self, show: bool) -> Self {
        self.show_rms = show;
        self
    }

    pub fn on_message<F>(mut self, callback: F) -> Self
    where
        F: Fn(WaveformMessage) -> Message + 'a,
    {
        self.on_message = Some(Box::new(callback));
        self
    }

    // Convert x position to normalized position (0.0 - 1.0)
    fn x_to_position(&self, x: f32, bounds: &Rectangle) -> f32 {
        let t = ((x - bounds.x) / bounds.width).clamp(0.0, 1.0);
        // Account for zoom and scroll
        self.scroll + t * self.zoom
    }

    // Convert normalized position to x
    fn position_to_x(&self, pos: f32, bounds: &Rectangle) -> f32 {
        let t = (pos - self.scroll) / self.zoom;
        bounds.x + t * bounds.width
    }
}

/// Waveform display state
#[derive(Default)]
pub struct WaveformState {
    is_seeking: bool,
    is_selecting: bool,
    selection_start: f32,
}

impl<'a, Message, Theme, Renderer> Widget<Message, Theme, Renderer> for WaveformDisplay<'a, Message>
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
        _tree: &widget::Tree,
        renderer: &mut Renderer,
        _theme: &Theme,
        _style: &renderer::Style,
        layout: Layout<'_>,
        _cursor: mouse::Cursor,
        _viewport: &Rectangle,
    ) {
        let bounds = layout.bounds();
        let center_y = bounds.y + bounds.height / 2.0;

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
            Palette::BG_DEEPEST,
        );

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

        // Draw selection
        if let Some((start, end)) = self.selection {
            let x1 = self.position_to_x(start.min(end), &bounds);
            let x2 = self.position_to_x(start.max(end), &bounds);

            if x2 > bounds.x && x1 < bounds.x + bounds.width {
                let sel_x = x1.max(bounds.x);
                let sel_w = (x2.min(bounds.x + bounds.width) - sel_x).max(0.0);

                renderer.fill_quad(
                    renderer::Quad {
                        bounds: Rectangle {
                            x: sel_x,
                            y: bounds.y,
                            width: sel_w,
                            height: bounds.height,
                        },
                        border: Default::default(),
                        shadow: Default::default(),
                    },
                    iced::Color::from_rgba(0.29, 0.62, 1.0, 0.2),
                );
            }
        }

        // Draw waveform
        if !self.data.is_empty() {
            self.draw_waveform(renderer, &bounds);
        }

        // Draw playhead
        let playhead_x = self.position_to_x(self.playhead, &bounds);
        if playhead_x >= bounds.x && playhead_x <= bounds.x + bounds.width {
            renderer.fill_quad(
                renderer::Quad {
                    bounds: Rectangle {
                        x: playhead_x - 1.0,
                        y: bounds.y,
                        width: 2.0,
                        height: bounds.height,
                    },
                    border: Default::default(),
                    shadow: Default::default(),
                },
                Palette::ACCENT_BLUE,
            );

            // Playhead head triangle
            renderer.fill_quad(
                renderer::Quad {
                    bounds: Rectangle {
                        x: playhead_x - 5.0,
                        y: bounds.y,
                        width: 10.0,
                        height: 8.0,
                    },
                    border: iced::Border {
                        color: Palette::ACCENT_BLUE,
                        width: 0.0,
                        radius: 4.0.into(),
                    },
                    shadow: Default::default(),
                },
                Palette::ACCENT_BLUE,
            );
        }
    }

    fn tag(&self) -> widget::tree::Tag {
        widget::tree::Tag::of::<WaveformState>()
    }

    fn state(&self) -> widget::tree::State {
        widget::tree::State::new(WaveformState::default())
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
        let state = tree.state.downcast_mut::<WaveformState>();
        let bounds = layout.bounds();

        match event {
            Event::Mouse(mouse::Event::ButtonPressed(mouse::Button::Left)) => {
                if let Some(pos) = cursor.position() {
                    if bounds.contains(pos) {
                        let position = self.x_to_position(pos.x, &bounds);

                        if let Some(ref on_message) = self.on_message {
                            shell.publish(on_message(WaveformMessage::SeekTo(position)));
                        }

                        state.is_seeking = true;
                        return iced::event::Status::Captured;
                    }
                }
            }

            Event::Mouse(mouse::Event::ButtonPressed(mouse::Button::Right)) => {
                if let Some(pos) = cursor.position() {
                    if bounds.contains(pos) {
                        let position = self.x_to_position(pos.x, &bounds);
                        state.is_selecting = true;
                        state.selection_start = position;
                        return iced::event::Status::Captured;
                    }
                }
            }

            Event::Mouse(mouse::Event::ButtonReleased(mouse::Button::Left)) => {
                if state.is_seeking {
                    state.is_seeking = false;
                    return iced::event::Status::Captured;
                }
            }

            Event::Mouse(mouse::Event::ButtonReleased(mouse::Button::Right)) => {
                if state.is_selecting {
                    state.is_selecting = false;
                    return iced::event::Status::Captured;
                }
            }

            Event::Mouse(mouse::Event::CursorMoved { position }) => {
                if state.is_seeking {
                    let pos = self.x_to_position(position.x, &bounds);
                    if let Some(ref on_message) = self.on_message {
                        shell.publish(on_message(WaveformMessage::SeekTo(pos.clamp(0.0, 1.0))));
                    }
                    return iced::event::Status::Captured;
                }

                if state.is_selecting {
                    let pos = self.x_to_position(position.x, &bounds);
                    if let Some(ref on_message) = self.on_message {
                        shell.publish(on_message(WaveformMessage::SelectionChanged(
                            state.selection_start,
                            pos.clamp(0.0, 1.0),
                        )));
                    }
                    return iced::event::Status::Captured;
                }
            }

            Event::Mouse(mouse::Event::WheelScrolled { delta }) => {
                if cursor.is_over(bounds) {
                    let scroll_amount = match delta {
                        mouse::ScrollDelta::Lines { y, .. } => y * 0.1,
                        mouse::ScrollDelta::Pixels { y, .. } => y * 0.001,
                    };

                    let new_zoom = (self.zoom * (1.0 - scroll_amount)).clamp(0.01, 1.0);

                    if let Some(ref on_message) = self.on_message {
                        shell.publish(on_message(WaveformMessage::ZoomChanged(new_zoom)));
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
        let state = tree.state.downcast_ref::<WaveformState>();

        if state.is_seeking || state.is_selecting {
            mouse::Interaction::Grabbing
        } else if cursor.is_over(layout.bounds()) {
            mouse::Interaction::Pointer
        } else {
            mouse::Interaction::default()
        }
    }
}

impl<'a, Message> WaveformDisplay<'a, Message>
where
    Message: Clone,
{
    fn draw_waveform<Renderer>(&self, renderer: &mut Renderer, bounds: &Rectangle)
    where
        Renderer: renderer::Renderer,
    {
        let center_y = bounds.y + bounds.height / 2.0;
        let half_height = bounds.height / 2.0 - 4.0;

        let visible_start = self.scroll;
        let visible_end = (self.scroll + self.zoom).min(1.0);

        let data_len = self.data.len();
        if data_len == 0 {
            return;
        }

        // Calculate which data points to draw
        let start_idx = (visible_start * data_len as f32) as usize;
        let end_idx = (visible_end * data_len as f32).ceil() as usize;

        let num_columns = bounds.width as usize;

        for col in 0..num_columns {
            let t = col as f32 / num_columns as f32;
            let data_pos = visible_start + t * self.zoom;
            let data_idx = (data_pos * data_len as f32) as usize;

            if data_idx >= data_len {
                continue;
            }

            let point = &self.data[data_idx];
            let x = bounds.x + col as f32;

            // Draw min/max (waveform body)
            let min_y = center_y - point.min * half_height;
            let max_y = center_y - point.max * half_height;

            let top = min_y.min(max_y);
            let height = (min_y.max(max_y) - top).max(1.0);

            // Waveform body color
            renderer.fill_quad(
                renderer::Quad {
                    bounds: Rectangle {
                        x,
                        y: top,
                        width: 1.0,
                        height,
                    },
                    border: Default::default(),
                    shadow: Default::default(),
                },
                Palette::ACCENT_CYAN,
            );

            // Draw RMS (darker overlay)
            if self.show_rms && point.rms > 0.0 {
                let rms_y = center_y - point.rms * half_height;
                let rms_top = center_y.min(rms_y);
                let rms_height = (center_y - rms_y).abs().max(1.0);

                // Only draw RMS within waveform bounds
                let rms_draw_top = rms_top.max(top);
                let rms_draw_height = rms_height.min(height);

                renderer.fill_quad(
                    renderer::Quad {
                        bounds: Rectangle {
                            x,
                            y: rms_draw_top,
                            width: 1.0,
                            height: rms_draw_height,
                        },
                        border: Default::default(),
                        shadow: Default::default(),
                    },
                    iced::Color::from_rgba(0.25, 0.78, 1.0, 0.5),
                );

                // Mirror for negative side
                renderer.fill_quad(
                    renderer::Quad {
                        bounds: Rectangle {
                            x,
                            y: center_y,
                            width: 1.0,
                            height: rms_draw_height,
                        },
                        border: Default::default(),
                        shadow: Default::default(),
                    },
                    iced::Color::from_rgba(0.25, 0.78, 1.0, 0.5),
                );
            }
        }
    }
}

impl<'a, Message, Theme, Renderer> From<WaveformDisplay<'a, Message>> for Element<'a, Message, Theme, Renderer>
where
    Renderer: renderer::Renderer + 'a,
    Message: Clone + 'a,
    Theme: 'a,
{
    fn from(waveform: WaveformDisplay<'a, Message>) -> Self {
        Element::new(waveform)
    }
}
