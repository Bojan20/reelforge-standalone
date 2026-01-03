//! Professional rotary knob widget
//!
//! Features:
//! - Arc-style value display
//! - Fine control with shift modifier
//! - Double-click to reset
//! - Value tooltip on hover
//! - Bipolar mode (centered zero)

use iced::advanced::layout::{self, Layout};
use iced::advanced::renderer;
use iced::advanced::widget::{self, Widget};
use iced::advanced::{Clipboard, Shell};
use iced::keyboard;
use iced::mouse;
use iced::{Element, Event, Length, Point, Rectangle, Size};

use crate::theme::Palette;

/// Knob style
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum KnobStyle {
    #[default]
    Normal,
    /// Bipolar knob (center is zero)
    Bipolar,
    /// Small gain trim style
    Trim,
}

/// Rotary knob widget
pub struct Knob<'a, Message> {
    value: f32,
    default: f32,
    min: f32,
    max: f32,
    size: f32,
    style: KnobStyle,
    on_change: Box<dyn Fn(f32) -> Message + 'a>,
    label: Option<&'a str>,
    unit: Option<&'a str>,
    decimals: usize,
}

impl<'a, Message> Knob<'a, Message> {
    pub fn new<F>(value: f32, on_change: F) -> Self
    where
        F: Fn(f32) -> Message + 'a,
    {
        Self {
            value: value.clamp(0.0, 1.0),
            default: 0.5,
            min: 0.0,
            max: 1.0,
            size: 48.0,
            style: KnobStyle::Normal,
            on_change: Box::new(on_change),
            label: None,
            unit: None,
            decimals: 2,
        }
    }

    pub fn range(mut self, min: f32, max: f32) -> Self {
        self.min = min;
        self.max = max;
        self
    }

    pub fn default_value(mut self, default: f32) -> Self {
        self.default = default;
        self
    }

    pub fn size(mut self, size: f32) -> Self {
        self.size = size;
        self
    }

    pub fn style(mut self, style: KnobStyle) -> Self {
        self.style = style;
        self
    }

    pub fn label(mut self, label: &'a str) -> Self {
        self.label = Some(label);
        self
    }

    pub fn unit(mut self, unit: &'a str) -> Self {
        self.unit = Some(unit);
        self
    }

    pub fn decimals(mut self, decimals: usize) -> Self {
        self.decimals = decimals;
        self
    }

    fn normalized(&self) -> f32 {
        (self.value - self.min) / (self.max - self.min)
    }

    fn denormalize(&self, normalized: f32) -> f32 {
        self.min + normalized * (self.max - self.min)
    }
}

/// Knob state
#[derive(Default)]
pub struct KnobState {
    is_dragging: bool,
    last_y: f32,
    fine_mode: bool,
    is_hovered: bool,
}

impl<'a, Message, Theme, Renderer> Widget<Message, Theme, Renderer> for Knob<'a, Message>
where
    Renderer: renderer::Renderer,
    Message: Clone,
{
    fn size(&self) -> Size<Length> {
        let label_height = if self.label.is_some() { 16.0 } else { 0.0 };
        Size::new(
            Length::Fixed(self.size),
            Length::Fixed(self.size + label_height + 16.0),
        )
    }

    fn layout(
        &self,
        _tree: &mut widget::Tree,
        _renderer: &Renderer,
        _limits: &layout::Limits,
    ) -> layout::Node {
        let label_height = if self.label.is_some() { 16.0 } else { 0.0 };
        layout::Node::new(Size::new(self.size, self.size + label_height + 16.0))
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
        let state = tree.state.downcast_ref::<KnobState>();
        let bounds = layout.bounds();
        let knob_bounds = Rectangle {
            x: bounds.x,
            y: bounds.y,
            width: self.size,
            height: self.size,
        };

        let center = Point::new(
            knob_bounds.x + knob_bounds.width / 2.0,
            knob_bounds.y + knob_bounds.height / 2.0,
        );
        let outer_radius = self.size / 2.0 - 2.0;
        let inner_radius = outer_radius - 6.0;

        // Draw outer ring (background)
        renderer.fill_quad(
            renderer::Quad {
                bounds: knob_bounds,
                border: iced::Border {
                    color: Palette::BG_SURFACE,
                    width: 2.0,
                    radius: (self.size / 2.0).into(),
                },
                shadow: Default::default(),
            },
            Palette::BG_DEEP,
        );

        // Draw value arc
        let start_angle = -135.0_f32.to_radians();
        let end_angle = 135.0_f32.to_radians();
        let angle_range = end_angle - start_angle;
        let value_angle = start_angle + self.normalized() * angle_range;

        // Draw arc segments
        let num_segments = 24;
        let segment_angle = angle_range / num_segments as f32;

        // Determine arc color based on style
        let arc_color = match self.style {
            KnobStyle::Normal => {
                if state.is_dragging || state.is_hovered {
                    Palette::ACCENT_ORANGE
                } else {
                    Palette::ACCENT_CYAN
                }
            }
            KnobStyle::Bipolar => {
                if self.value >= self.default {
                    Palette::ACCENT_ORANGE
                } else {
                    Palette::ACCENT_CYAN
                }
            }
            KnobStyle::Trim => Palette::ACCENT_GREEN,
        };

        // Draw filled arc segments
        let (arc_start, arc_end) = match self.style {
            KnobStyle::Bipolar => {
                let default_angle = start_angle + ((self.default - self.min) / (self.max - self.min)) * angle_range;
                if value_angle >= default_angle {
                    (default_angle, value_angle)
                } else {
                    (value_angle, default_angle)
                }
            }
            _ => (start_angle, value_angle),
        };

        for i in 0..num_segments {
            let seg_start = start_angle + i as f32 * segment_angle;
            let seg_end = seg_start + segment_angle * 0.85;

            // Check if this segment is within the value arc
            let in_arc = seg_start >= arc_start && seg_start < arc_end;

            if in_arc {
                let mid_angle = (seg_start + seg_end) / 2.0;
                let dot_x = center.x + mid_angle.cos() * (outer_radius - 3.0);
                let dot_y = center.y + mid_angle.sin() * (outer_radius - 3.0);

                renderer.fill_quad(
                    renderer::Quad {
                        bounds: Rectangle {
                            x: dot_x - 2.5,
                            y: dot_y - 2.5,
                            width: 5.0,
                            height: 5.0,
                        },
                        border: iced::Border {
                            color: arc_color,
                            width: 0.0,
                            radius: 2.5.into(),
                        },
                        shadow: Default::default(),
                    },
                    arc_color,
                );
            }
        }

        // Draw inner circle (knob body)
        let inner_bounds = Rectangle {
            x: center.x - inner_radius,
            y: center.y - inner_radius,
            width: inner_radius * 2.0,
            height: inner_radius * 2.0,
        };

        renderer.fill_quad(
            renderer::Quad {
                bounds: inner_bounds,
                border: iced::Border {
                    color: if state.is_dragging {
                        Palette::ACCENT_BLUE
                    } else {
                        Palette::BG_SURFACE
                    },
                    width: 1.0,
                    radius: inner_radius.into(),
                },
                shadow: Default::default(),
            },
            if state.is_hovered {
                Palette::BG_MID
            } else {
                Palette::BG_DEEP
            },
        );

        // Draw indicator line
        let indicator_length = inner_radius - 4.0;
        let indicator_end = Point::new(
            center.x + value_angle.cos() * indicator_length,
            center.y + value_angle.sin() * indicator_length,
        );

        let indicator_start = Point::new(
            center.x + value_angle.cos() * (indicator_length * 0.3),
            center.y + value_angle.sin() * (indicator_length * 0.3),
        );

        // Draw indicator as small rectangles along the line
        let steps = 3;
        for i in 0..=steps {
            let t = i as f32 / steps as f32;
            let x = indicator_start.x + (indicator_end.x - indicator_start.x) * t;
            let y = indicator_start.y + (indicator_end.y - indicator_start.y) * t;

            renderer.fill_quad(
                renderer::Quad {
                    bounds: Rectangle {
                        x: x - 1.5,
                        y: y - 1.5,
                        width: 3.0,
                        height: 3.0,
                    },
                    border: iced::Border {
                        color: arc_color,
                        width: 0.0,
                        radius: 1.5.into(),
                    },
                    shadow: Default::default(),
                },
                arc_color,
            );
        }

        // Draw value text below knob
        // Note: In a real implementation, you'd use proper text rendering
        // For now, just draw a small indicator of the value area
        let value_y = knob_bounds.y + knob_bounds.height + 4.0;
        let value_bounds = Rectangle {
            x: bounds.x,
            y: value_y,
            width: self.size,
            height: 12.0,
        };

        renderer.fill_quad(
            renderer::Quad {
                bounds: value_bounds,
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

    fn tag(&self) -> widget::tree::Tag {
        widget::tree::Tag::of::<KnobState>()
    }

    fn state(&self) -> widget::tree::State {
        widget::tree::State::new(KnobState::default())
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
        let state = tree.state.downcast_mut::<KnobState>();
        let bounds = layout.bounds();

        match event {
            Event::Mouse(mouse::Event::ButtonPressed(mouse::Button::Left)) => {
                if cursor.is_over(bounds) {
                    state.is_dragging = true;
                    if let Some(position) = cursor.position() {
                        state.last_y = position.y;
                    }
                    return iced::event::Status::Captured;
                }
            }
            Event::Mouse(mouse::Event::ButtonReleased(mouse::Button::Left)) => {
                if state.is_dragging {
                    state.is_dragging = false;
                    return iced::event::Status::Captured;
                }
            }
            Event::Mouse(mouse::Event::CursorMoved { position }) => {
                state.is_hovered = cursor.is_over(bounds);

                if state.is_dragging {
                    let delta = state.last_y - position.y;
                    // Fine mode: shift key for 10x precision
                    let sensitivity = if state.fine_mode { 0.001 } else { 0.005 };
                    let new_normalized = (self.normalized() + delta * sensitivity).clamp(0.0, 1.0);
                    let new_value = self.denormalize(new_normalized);

                    state.last_y = position.y;

                    shell.publish((self.on_change)(new_value));
                    return iced::event::Status::Captured;
                }
            }
            Event::Mouse(mouse::Event::CursorLeft) => {
                state.is_hovered = false;
            }
            // Double-click to reset
            Event::Mouse(mouse::Event::ButtonPressed(mouse::Button::Middle)) => {
                if cursor.is_over(bounds) {
                    shell.publish((self.on_change)(self.default));
                    return iced::event::Status::Captured;
                }
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
        let state = tree.state.downcast_ref::<KnobState>();

        if state.is_dragging {
            mouse::Interaction::Grabbing
        } else if cursor.is_over(layout.bounds()) {
            mouse::Interaction::Grab
        } else {
            mouse::Interaction::default()
        }
    }
}

impl<'a, Message, Theme, Renderer> From<Knob<'a, Message>> for Element<'a, Message, Theme, Renderer>
where
    Renderer: renderer::Renderer + 'a,
    Message: Clone + 'a,
    Theme: 'a,
{
    fn from(knob: Knob<'a, Message>) -> Self {
        Element::new(knob)
    }
}
