//! Volume fader widget

use iced::advanced::layout::{self, Layout};
use iced::advanced::renderer;
use iced::advanced::widget::{self, Widget};
use iced::advanced::{Clipboard, Shell};
use iced::mouse;
use iced::{Color, Element, Event, Length, Point, Rectangle, Size};

use crate::theme::Palette;

/// Fader widget
pub struct Fader<'a, Message> {
    value: f32,          // 0.0 to 1.0
    width: f32,
    height: f32,
    on_change: Box<dyn Fn(f32) -> Message + 'a>,
}

impl<'a, Message> Fader<'a, Message> {
    pub fn new<F>(value: f32, on_change: F) -> Self
    where
        F: Fn(f32) -> Message + 'a,
    {
        Self {
            value: value.clamp(0.0, 1.0),
            width: 40.0,
            height: 200.0,
            on_change: Box::new(on_change),
        }
    }

    pub fn size(mut self, width: f32, height: f32) -> Self {
        self.width = width;
        self.height = height;
        self
    }
}

/// Fader state
#[derive(Default)]
pub struct FaderState {
    is_dragging: bool,
}

impl<'a, Message, Theme, Renderer> Widget<Message, Theme, Renderer> for Fader<'a, Message>
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

        // Track
        let track_width = 4.0;
        let track_x = bounds.x + (bounds.width - track_width) / 2.0;
        let track_bounds = Rectangle {
            x: track_x,
            y: bounds.y + 10.0,
            width: track_width,
            height: bounds.height - 20.0,
        };

        renderer.fill_quad(
            renderer::Quad {
                bounds: track_bounds,
                border: iced::Border {
                    color: Palette::BG_SURFACE,
                    width: 0.0,
                    radius: 2.0.into(),
                },
                shadow: Default::default(),
            },
            Palette::BG_DEEP,
        );

        // Filled portion
        let filled_height = track_bounds.height * self.value;
        let filled_bounds = Rectangle {
            x: track_bounds.x,
            y: track_bounds.y + track_bounds.height - filled_height,
            width: track_bounds.width,
            height: filled_height,
        };

        renderer.fill_quad(
            renderer::Quad {
                bounds: filled_bounds,
                border: Default::default(),
                shadow: Default::default(),
            },
            Palette::ACCENT_BLUE,
        );

        // Handle
        let handle_height = 24.0;
        let handle_y = track_bounds.y + track_bounds.height * (1.0 - self.value) - handle_height / 2.0;
        let handle_bounds = Rectangle {
            x: bounds.x + 4.0,
            y: handle_y,
            width: bounds.width - 8.0,
            height: handle_height,
        };

        renderer.fill_quad(
            renderer::Quad {
                bounds: handle_bounds,
                border: iced::Border {
                    color: Palette::BG_SURFACE,
                    width: 1.0,
                    radius: 4.0.into(),
                },
                shadow: Default::default(),
            },
            Palette::BG_MID,
        );

        // Handle center line
        let line_bounds = Rectangle {
            x: handle_bounds.x + 8.0,
            y: handle_bounds.y + handle_bounds.height / 2.0 - 1.0,
            width: handle_bounds.width - 16.0,
            height: 2.0,
        };

        renderer.fill_quad(
            renderer::Quad {
                bounds: line_bounds,
                border: Default::default(),
                shadow: Default::default(),
            },
            Palette::TEXT_SECONDARY,
        );
    }

    fn tag(&self) -> widget::tree::Tag {
        widget::tree::Tag::of::<FaderState>()
    }

    fn state(&self) -> widget::tree::State {
        widget::tree::State::new(FaderState::default())
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
        let state = tree.state.downcast_mut::<FaderState>();
        let bounds = layout.bounds();

        match event {
            Event::Mouse(mouse::Event::ButtonPressed(mouse::Button::Left)) => {
                if cursor.is_over(bounds) {
                    state.is_dragging = true;

                    // Set value based on click position
                    if let Some(position) = cursor.position() {
                        let track_y = bounds.y + 10.0;
                        let track_height = bounds.height - 20.0;
                        let relative_y = (position.y - track_y).clamp(0.0, track_height);
                        let new_value = 1.0 - (relative_y / track_height);

                        shell.publish((self.on_change)(new_value));
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
                    let track_y = bounds.y + 10.0;
                    let track_height = bounds.height - 20.0;
                    let relative_y = (position.y - track_y).clamp(0.0, track_height);
                    let new_value = 1.0 - (relative_y / track_height);

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
        let state = tree.state.downcast_ref::<FaderState>();

        if state.is_dragging {
            mouse::Interaction::Grabbing
        } else if cursor.is_over(layout.bounds()) {
            mouse::Interaction::Grab
        } else {
            mouse::Interaction::default()
        }
    }
}

impl<'a, Message, Theme, Renderer> From<Fader<'a, Message>> for Element<'a, Message, Theme, Renderer>
where
    Renderer: renderer::Renderer + 'a,
    Message: Clone + 'a,
    Theme: 'a,
{
    fn from(fader: Fader<'a, Message>) -> Self {
        Element::new(fader)
    }
}
