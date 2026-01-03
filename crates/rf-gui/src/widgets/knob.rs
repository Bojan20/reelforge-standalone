//! Rotary knob widget

use iced::advanced::layout::{self, Layout};
use iced::advanced::renderer;
use iced::advanced::widget::{self, Widget};
use iced::advanced::{Clipboard, Shell};
use iced::mouse;
use iced::{Color, Element, Event, Length, Point, Rectangle, Size, Vector};
use std::f32::consts::PI;

use crate::theme::Palette;

/// Knob widget message
#[derive(Debug, Clone, Copy)]
pub enum KnobMessage {
    Changed(f32),
}

/// Rotary knob widget
pub struct Knob<'a, Message> {
    value: f32,
    min: f32,
    max: f32,
    size: f32,
    on_change: Box<dyn Fn(f32) -> Message + 'a>,
    label: Option<&'a str>,
}

impl<'a, Message> Knob<'a, Message> {
    pub fn new<F>(value: f32, on_change: F) -> Self
    where
        F: Fn(f32) -> Message + 'a,
    {
        Self {
            value: value.clamp(0.0, 1.0),
            min: 0.0,
            max: 1.0,
            size: 48.0,
            on_change: Box::new(on_change),
            label: None,
        }
    }

    pub fn range(mut self, min: f32, max: f32) -> Self {
        self.min = min;
        self.max = max;
        self
    }

    pub fn size(mut self, size: f32) -> Self {
        self.size = size;
        self
    }

    pub fn label(mut self, label: &'a str) -> Self {
        self.label = Some(label);
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
}

impl<'a, Message, Theme, Renderer> Widget<Message, Theme, Renderer> for Knob<'a, Message>
where
    Renderer: renderer::Renderer,
    Message: Clone,
{
    fn size(&self) -> Size<Length> {
        Size::new(Length::Fixed(self.size), Length::Fixed(self.size + 20.0))
    }

    fn layout(
        &self,
        _tree: &mut widget::Tree,
        _renderer: &Renderer,
        _limits: &layout::Limits,
    ) -> layout::Node {
        layout::Node::new(Size::new(self.size, self.size + 20.0))
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
        let knob_bounds = Rectangle {
            x: bounds.x,
            y: bounds.y,
            width: self.size,
            height: self.size,
        };

        // Draw knob background
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
        let center = Point::new(
            knob_bounds.x + knob_bounds.width / 2.0,
            knob_bounds.y + knob_bounds.height / 2.0,
        );
        let radius = self.size / 2.0 - 4.0;

        // Start angle: -135 degrees, end angle: 135 degrees (270 degree range)
        let start_angle = -135.0_f32.to_radians();
        let end_angle = 135.0_f32.to_radians();
        let angle_range = end_angle - start_angle;

        let value_angle = start_angle + self.normalized() * angle_range;

        // Draw indicator line
        let indicator_start = Point::new(
            center.x + value_angle.cos() * (radius - 8.0),
            center.y + value_angle.sin() * (radius - 8.0),
        );
        let indicator_end = Point::new(
            center.x + value_angle.cos() * radius,
            center.y + value_angle.sin() * radius,
        );

        // Simple indicator (would need proper line rendering in production)
        let indicator_bounds = Rectangle {
            x: indicator_end.x - 2.0,
            y: indicator_end.y - 2.0,
            width: 4.0,
            height: 4.0,
        };

        renderer.fill_quad(
            renderer::Quad {
                bounds: indicator_bounds,
                border: iced::Border {
                    color: Palette::ACCENT_ORANGE,
                    width: 0.0,
                    radius: 2.0.into(),
                },
                shadow: Default::default(),
            },
            Palette::ACCENT_ORANGE,
        );

        // Draw center dot
        let center_size = 6.0;
        renderer.fill_quad(
            renderer::Quad {
                bounds: Rectangle {
                    x: center.x - center_size / 2.0,
                    y: center.y - center_size / 2.0,
                    width: center_size,
                    height: center_size,
                },
                border: iced::Border {
                    color: Palette::BG_SURFACE,
                    width: 0.0,
                    radius: (center_size / 2.0).into(),
                },
                shadow: Default::default(),
            },
            Palette::BG_SURFACE,
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
                if state.is_dragging {
                    let delta = state.last_y - position.y;
                    let sensitivity = 0.005;
                    let new_normalized = (self.normalized() + delta * sensitivity).clamp(0.0, 1.0);
                    let new_value = self.denormalize(new_normalized);

                    state.last_y = position.y;

                    shell.publish((self.on_change)(new_value));
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
