//! EQ Editor Widget
//!
//! Interactive 64-band parametric EQ editor with:
//! - Draggable band nodes
//! - Frequency response curve display
//! - Band enable/disable
//! - Filter type selection per band

use iced::advanced::layout::{self, Layout};
use iced::advanced::renderer;
use iced::advanced::widget::{self, Widget};
use iced::advanced::{Clipboard, Shell};
use iced::keyboard;
use iced::mouse;
use iced::{Element, Event, Length, Point, Rectangle, Size};

use crate::theme::Palette;

/// EQ filter types
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum FilterType {
    #[default]
    Bell,
    LowShelf,
    HighShelf,
    LowCut,
    HighCut,
    Notch,
    Bandpass,
    TiltShelf,
}

impl FilterType {
    pub fn name(&self) -> &'static str {
        match self {
            FilterType::Bell => "Bell",
            FilterType::LowShelf => "Low Shelf",
            FilterType::HighShelf => "High Shelf",
            FilterType::LowCut => "Low Cut",
            FilterType::HighCut => "High Cut",
            FilterType::Notch => "Notch",
            FilterType::Bandpass => "Bandpass",
            FilterType::TiltShelf => "Tilt",
        }
    }

    pub fn color(&self) -> iced::Color {
        match self {
            FilterType::Bell => Palette::ACCENT_ORANGE,
            FilterType::LowShelf => Palette::ACCENT_CYAN,
            FilterType::HighShelf => Palette::ACCENT_CYAN,
            FilterType::LowCut => Palette::ACCENT_RED,
            FilterType::HighCut => Palette::ACCENT_RED,
            FilterType::Notch => Palette::ACCENT_GREEN,
            FilterType::Bandpass => Palette::ACCENT_BLUE,
            FilterType::TiltShelf => Palette::TEXT_SECONDARY,
        }
    }
}

/// Single EQ band configuration
#[derive(Debug, Clone)]
pub struct EqBandConfig {
    pub enabled: bool,
    pub filter_type: FilterType,
    pub frequency: f32,  // Hz, 20-20000
    pub gain_db: f32,    // dB, -30 to +30
    pub q: f32,          // 0.1 to 30
}

impl Default for EqBandConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            filter_type: FilterType::Bell,
            frequency: 1000.0,
            gain_db: 0.0,
            q: 1.0,
        }
    }
}

/// Messages from the EQ editor
#[derive(Debug, Clone)]
pub enum EqMessage {
    /// Band frequency changed (index, Hz)
    FrequencyChanged(usize, f32),
    /// Band gain changed (index, dB)
    GainChanged(usize, f32),
    /// Band Q changed (index, Q)
    QChanged(usize, f32),
    /// Band enabled/disabled (index, enabled)
    EnabledChanged(usize, bool),
    /// Band filter type changed (index, type)
    FilterTypeChanged(usize, FilterType),
    /// Band selected (index)
    BandSelected(Option<usize>),
    /// Band added at position
    BandAdded(f32, f32),  // freq, gain
}

/// EQ Editor widget
pub struct EqEditor<'a, Message> {
    bands: &'a [EqBandConfig],
    frequency_response: &'a [(f32, f32)],  // (freq, dB) points
    selected_band: Option<usize>,
    width: f32,
    height: f32,
    min_db: f32,
    max_db: f32,
    on_message: Box<dyn Fn(EqMessage) -> Message + 'a>,
}

impl<'a, Message> EqEditor<'a, Message> {
    pub fn new<F>(
        bands: &'a [EqBandConfig],
        frequency_response: &'a [(f32, f32)],
        on_message: F,
    ) -> Self
    where
        F: Fn(EqMessage) -> Message + 'a,
    {
        Self {
            bands,
            frequency_response,
            selected_band: None,
            width: 800.0,
            height: 300.0,
            min_db: -24.0,
            max_db: 24.0,
            on_message: Box::new(on_message),
        }
    }

    pub fn selected_band(mut self, index: Option<usize>) -> Self {
        self.selected_band = index;
        self
    }

    pub fn size(mut self, width: f32, height: f32) -> Self {
        self.width = width;
        self.height = height;
        self
    }

    pub fn db_range(mut self, min: f32, max: f32) -> Self {
        self.min_db = min;
        self.max_db = max;
        self
    }

    // Convert frequency to x position (log scale)
    fn freq_to_x(&self, freq: f32, bounds: &Rectangle) -> f32 {
        let log_min = 20.0_f32.ln();
        let log_max = 20000.0_f32.ln();
        let t = (freq.ln() - log_min) / (log_max - log_min);
        bounds.x + t * bounds.width
    }

    // Convert x position to frequency
    fn x_to_freq(&self, x: f32, bounds: &Rectangle) -> f32 {
        let log_min = 20.0_f32.ln();
        let log_max = 20000.0_f32.ln();
        let t = ((x - bounds.x) / bounds.width).clamp(0.0, 1.0);
        (log_min + t * (log_max - log_min)).exp()
    }

    // Convert dB to y position
    fn db_to_y(&self, db: f32, bounds: &Rectangle) -> f32 {
        let db_range = self.max_db - self.min_db;
        let t = (db - self.min_db) / db_range;
        bounds.y + (1.0 - t) * bounds.height
    }

    // Convert y position to dB
    fn y_to_db(&self, y: f32, bounds: &Rectangle) -> f32 {
        let db_range = self.max_db - self.min_db;
        let t = 1.0 - ((y - bounds.y) / bounds.height).clamp(0.0, 1.0);
        self.min_db + t * db_range
    }

    // Find band near a point
    fn find_band_at(&self, pos: Point, bounds: &Rectangle) -> Option<usize> {
        const HIT_RADIUS: f32 = 12.0;

        for (i, band) in self.bands.iter().enumerate() {
            if !band.enabled {
                continue;
            }

            let band_x = self.freq_to_x(band.frequency, bounds);
            let band_y = self.db_to_y(band.gain_db, bounds);

            let dx = pos.x - band_x;
            let dy = pos.y - band_y;
            let dist = (dx * dx + dy * dy).sqrt();

            if dist < HIT_RADIUS {
                return Some(i);
            }
        }

        None
    }
}

/// EQ Editor state
#[derive(Default)]
pub struct EqEditorState {
    dragging_band: Option<usize>,
    drag_mode: DragMode,
    last_pos: Point,
    fine_mode: bool,
    hovered_band: Option<usize>,
}

#[derive(Default, Clone, Copy, PartialEq)]
enum DragMode {
    #[default]
    FreqGain,  // Normal drag: frequency + gain
    Q,         // Right-drag or alt: Q adjustment
}

impl<'a, Message, Theme, Renderer> Widget<Message, Theme, Renderer> for EqEditor<'a, Message>
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
        let state = tree.state.downcast_ref::<EqEditorState>();
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
            Palette::BG_DEEPEST,
        );

        // Draw grid
        self.draw_grid(renderer, &bounds);

        // Draw frequency response curve
        self.draw_response_curve(renderer, &bounds);

        // Draw band nodes
        for (i, band) in self.bands.iter().enumerate() {
            if band.enabled {
                self.draw_band_node(renderer, &bounds, i, band, state);
            }
        }

        // Draw 0dB line (center reference)
        let zero_y = self.db_to_y(0.0, &bounds);
        renderer.fill_quad(
            renderer::Quad {
                bounds: Rectangle {
                    x: bounds.x,
                    y: zero_y - 0.5,
                    width: bounds.width,
                    height: 1.0,
                },
                border: Default::default(),
                shadow: Default::default(),
            },
            Palette::TEXT_DISABLED,
        );
    }

    fn tag(&self) -> widget::tree::Tag {
        widget::tree::Tag::of::<EqEditorState>()
    }

    fn state(&self) -> widget::tree::State {
        widget::tree::State::new(EqEditorState::default())
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
        let state = tree.state.downcast_mut::<EqEditorState>();
        let bounds = layout.bounds();

        match event {
            Event::Mouse(mouse::Event::ButtonPressed(mouse::Button::Left)) => {
                if let Some(pos) = cursor.position() {
                    if bounds.contains(pos) {
                        // Check if clicking on existing band
                        if let Some(band_idx) = self.find_band_at(pos, &bounds) {
                            state.dragging_band = Some(band_idx);
                            state.drag_mode = DragMode::FreqGain;
                            state.last_pos = pos;
                            shell.publish((self.on_message)(EqMessage::BandSelected(Some(band_idx))));
                        } else {
                            // Double-click to add new band
                            let freq = self.x_to_freq(pos.x, &bounds);
                            let gain = self.y_to_db(pos.y, &bounds);
                            shell.publish((self.on_message)(EqMessage::BandAdded(freq, gain)));
                        }
                        return iced::event::Status::Captured;
                    }
                }
            }

            Event::Mouse(mouse::Event::ButtonPressed(mouse::Button::Right)) => {
                if let Some(pos) = cursor.position() {
                    if bounds.contains(pos) {
                        if let Some(band_idx) = self.find_band_at(pos, &bounds) {
                            state.dragging_band = Some(band_idx);
                            state.drag_mode = DragMode::Q;
                            state.last_pos = pos;
                            return iced::event::Status::Captured;
                        }
                    }
                }
            }

            Event::Mouse(mouse::Event::ButtonReleased(mouse::Button::Left))
            | Event::Mouse(mouse::Event::ButtonReleased(mouse::Button::Right)) => {
                if state.dragging_band.is_some() {
                    state.dragging_band = None;
                    return iced::event::Status::Captured;
                }
            }

            Event::Mouse(mouse::Event::CursorMoved { position }) => {
                // Update hover state
                state.hovered_band = if bounds.contains(position) {
                    self.find_band_at(position, &bounds)
                } else {
                    None
                };

                // Handle drag
                if let Some(band_idx) = state.dragging_band {
                    let sensitivity = if state.fine_mode { 0.2 } else { 1.0 };

                    match state.drag_mode {
                        DragMode::FreqGain => {
                            let freq = self.x_to_freq(position.x, &bounds);
                            let gain = self.y_to_db(position.y, &bounds);

                            shell.publish((self.on_message)(EqMessage::FrequencyChanged(
                                band_idx,
                                freq.clamp(20.0, 20000.0),
                            )));
                            shell.publish((self.on_message)(EqMessage::GainChanged(
                                band_idx,
                                gain.clamp(-30.0, 30.0),
                            )));
                        }
                        DragMode::Q => {
                            // Vertical drag changes Q
                            let delta_y = state.last_pos.y - position.y;
                            let delta_q = delta_y * 0.05 * sensitivity;

                            if let Some(band) = self.bands.get(band_idx) {
                                let new_q = (band.q + delta_q).clamp(0.1, 30.0);
                                shell.publish((self.on_message)(EqMessage::QChanged(band_idx, new_q)));
                            }
                        }
                    }

                    state.last_pos = position;
                    return iced::event::Status::Captured;
                }
            }

            Event::Mouse(mouse::Event::CursorLeft) => {
                state.hovered_band = None;
            }

            Event::Keyboard(keyboard::Event::ModifiersChanged(modifiers)) => {
                state.fine_mode = modifiers.shift();
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
        let state = tree.state.downcast_ref::<EqEditorState>();

        if state.dragging_band.is_some() {
            mouse::Interaction::Grabbing
        } else if let Some(pos) = cursor.position() {
            if layout.bounds().contains(pos) {
                if self.find_band_at(pos, &layout.bounds()).is_some() {
                    mouse::Interaction::Grab
                } else {
                    mouse::Interaction::Crosshair
                }
            } else {
                mouse::Interaction::default()
            }
        } else {
            mouse::Interaction::default()
        }
    }
}

impl<'a, Message> EqEditor<'a, Message> {
    fn draw_grid<Renderer: renderer::Renderer>(&self, renderer: &mut Renderer, bounds: &Rectangle) {
        // Horizontal lines (dB)
        let db_lines = [-18.0, -12.0, -6.0, 0.0, 6.0, 12.0, 18.0];
        for &db in &db_lines {
            if db >= self.min_db && db <= self.max_db {
                let y = self.db_to_y(db, bounds);
                let color = if db == 0.0 {
                    Palette::BG_SURFACE
                } else {
                    Palette::BG_MID
                };

                renderer.fill_quad(
                    renderer::Quad {
                        bounds: Rectangle {
                            x: bounds.x,
                            y: y - 0.5,
                            width: bounds.width,
                            height: 1.0,
                        },
                        border: Default::default(),
                        shadow: Default::default(),
                    },
                    color,
                );
            }
        }

        // Vertical lines (frequency)
        let freq_lines: [f32; 9] = [50.0, 100.0, 200.0, 500.0, 1000.0, 2000.0, 5000.0, 10000.0, 20000.0];
        for &freq in &freq_lines {
            let x = self.freq_to_x(freq, bounds);

            renderer.fill_quad(
                renderer::Quad {
                    bounds: Rectangle {
                        x: x - 0.5,
                        y: bounds.y,
                        width: 1.0,
                        height: bounds.height,
                    },
                    border: Default::default(),
                    shadow: Default::default(),
                },
                Palette::BG_MID,
            );
        }
    }

    fn draw_response_curve<Renderer: renderer::Renderer>(&self, renderer: &mut Renderer, bounds: &Rectangle) {
        if self.frequency_response.is_empty() {
            return;
        }

        // Draw filled area under curve
        let zero_y = self.db_to_y(0.0, bounds);

        for i in 0..self.frequency_response.len().saturating_sub(1) {
            let (freq1, db1) = self.frequency_response[i];
            let (freq2, db2) = self.frequency_response[i + 1];

            let x1 = self.freq_to_x(freq1, bounds);
            let x2 = self.freq_to_x(freq2, bounds);
            let y1 = self.db_to_y(db1, bounds);
            let y2 = self.db_to_y(db2, bounds);

            // Draw curve line segment
            let mid_x = (x1 + x2) / 2.0;
            let mid_y = (y1 + y2) / 2.0;

            renderer.fill_quad(
                renderer::Quad {
                    bounds: Rectangle {
                        x: mid_x - 1.0,
                        y: mid_y - 1.0,
                        width: 2.0,
                        height: 2.0,
                    },
                    border: iced::Border {
                        color: Palette::ACCENT_ORANGE,
                        width: 0.0,
                        radius: 1.0.into(),
                    },
                    shadow: Default::default(),
                },
                Palette::ACCENT_ORANGE,
            );

            // Draw filled area (boost/cut indication)
            let fill_color = if db1 > 0.0 || db2 > 0.0 {
                iced::Color::from_rgba(1.0, 0.56, 0.25, 0.15)  // Orange tint for boost
            } else {
                iced::Color::from_rgba(0.25, 0.78, 1.0, 0.15)  // Cyan tint for cut
            };

            let rect_y = y1.min(y2).min(zero_y);
            let rect_h = (y1.max(y2) - y1.min(y2).min(zero_y)).max(1.0);

            renderer.fill_quad(
                renderer::Quad {
                    bounds: Rectangle {
                        x: x1,
                        y: rect_y,
                        width: (x2 - x1).max(1.0),
                        height: rect_h,
                    },
                    border: Default::default(),
                    shadow: Default::default(),
                },
                fill_color,
            );
        }
    }

    fn draw_band_node<Renderer: renderer::Renderer>(
        &self,
        renderer: &mut Renderer,
        bounds: &Rectangle,
        index: usize,
        band: &EqBandConfig,
        state: &EqEditorState,
    ) {
        let x = self.freq_to_x(band.frequency, bounds);
        let y = self.db_to_y(band.gain_db, bounds);

        let is_selected = self.selected_band == Some(index);
        let is_hovered = state.hovered_band == Some(index);
        let is_dragging = state.dragging_band == Some(index);

        let node_radius = if is_selected || is_dragging { 10.0 } else { 8.0 };
        let node_color = band.filter_type.color();

        // Outer glow when selected
        if is_selected || is_dragging {
            renderer.fill_quad(
                renderer::Quad {
                    bounds: Rectangle {
                        x: x - node_radius - 4.0,
                        y: y - node_radius - 4.0,
                        width: (node_radius + 4.0) * 2.0,
                        height: (node_radius + 4.0) * 2.0,
                    },
                    border: iced::Border {
                        color: iced::Color::from_rgba(
                            node_color.r,
                            node_color.g,
                            node_color.b,
                            0.3,
                        ),
                        width: 0.0,
                        radius: (node_radius + 4.0).into(),
                    },
                    shadow: Default::default(),
                },
                iced::Color::from_rgba(node_color.r, node_color.g, node_color.b, 0.2),
            );
        }

        // Node circle
        renderer.fill_quad(
            renderer::Quad {
                bounds: Rectangle {
                    x: x - node_radius,
                    y: y - node_radius,
                    width: node_radius * 2.0,
                    height: node_radius * 2.0,
                },
                border: iced::Border {
                    color: if is_hovered || is_dragging {
                        Palette::TEXT_PRIMARY
                    } else {
                        node_color
                    },
                    width: 2.0,
                    radius: node_radius.into(),
                },
                shadow: Default::default(),
            },
            if is_selected {
                node_color
            } else {
                Palette::BG_DEEP
            },
        );

        // Q indicator (horizontal lines showing bandwidth)
        if is_selected || is_dragging {
            let bandwidth = band.frequency / band.q;
            let low_freq = (band.frequency - bandwidth / 2.0).max(20.0);
            let high_freq = (band.frequency + bandwidth / 2.0).min(20000.0);

            let x_low = self.freq_to_x(low_freq, bounds);
            let x_high = self.freq_to_x(high_freq, bounds);

            // Draw Q range line
            renderer.fill_quad(
                renderer::Quad {
                    bounds: Rectangle {
                        x: x_low,
                        y: y - 1.0,
                        width: x_high - x_low,
                        height: 2.0,
                    },
                    border: Default::default(),
                    shadow: Default::default(),
                },
                iced::Color::from_rgba(node_color.r, node_color.g, node_color.b, 0.5),
            );
        }

        // Band index label
        let label_y = y - node_radius - 12.0;
        if label_y > bounds.y {
            // Small indicator rectangle for band number
            renderer.fill_quad(
                renderer::Quad {
                    bounds: Rectangle {
                        x: x - 6.0,
                        y: label_y,
                        width: 12.0,
                        height: 10.0,
                    },
                    border: iced::Border {
                        color: node_color,
                        width: 1.0,
                        radius: 2.0.into(),
                    },
                    shadow: Default::default(),
                },
                Palette::BG_DEEPEST,
            );
        }
    }
}

impl<'a, Message, Theme, Renderer> From<EqEditor<'a, Message>> for Element<'a, Message, Theme, Renderer>
where
    Renderer: renderer::Renderer + 'a,
    Message: Clone + 'a,
    Theme: 'a,
{
    fn from(editor: EqEditor<'a, Message>) -> Self {
        Element::new(editor)
    }
}
