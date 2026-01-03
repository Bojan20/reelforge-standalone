//! Insert/Send Effects Rack Widget
//!
//! Visual rack for managing insert effects and sends per channel

use iced::advanced::layout::{self, Layout};
use iced::advanced::renderer;
use iced::advanced::widget::{self, Widget};
use iced::advanced::{Clipboard, Shell};
use iced::mouse;
use iced::{Element, Event, Length, Rectangle, Size};

use crate::theme::Palette;

/// Insert slot state
#[derive(Debug, Clone)]
pub struct InsertSlot {
    pub name: String,
    pub enabled: bool,
    pub bypassed: bool,
    pub has_plugin: bool,
}

impl Default for InsertSlot {
    fn default() -> Self {
        Self {
            name: String::new(),
            enabled: false,
            bypassed: false,
            has_plugin: false,
        }
    }
}

impl InsertSlot {
    pub fn empty() -> Self {
        Self::default()
    }

    pub fn with_plugin(name: impl Into<String>) -> Self {
        Self {
            name: name.into(),
            enabled: true,
            bypassed: false,
            has_plugin: true,
        }
    }
}

/// Send slot state
#[derive(Debug, Clone)]
pub struct SendSlot {
    pub name: String,
    pub level: f32,      // 0.0 - 1.0
    pub enabled: bool,
    pub pre_fader: bool,
}

impl Default for SendSlot {
    fn default() -> Self {
        Self {
            name: String::new(),
            level: 0.0,
            enabled: false,
            pre_fader: false,
        }
    }
}

impl SendSlot {
    pub fn new(name: impl Into<String>) -> Self {
        Self {
            name: name.into(),
            level: 0.75,
            enabled: true,
            pre_fader: false,
        }
    }
}

/// Messages from the insert rack
#[derive(Debug, Clone)]
pub enum InsertRackMessage {
    /// Insert slot clicked (slot index)
    InsertClicked(usize),
    /// Insert bypass toggled (slot index, bypassed)
    InsertBypassToggled(usize, bool),
    /// Insert removed (slot index)
    InsertRemoved(usize),
    /// Insert moved (from, to)
    InsertMoved(usize, usize),
    /// Send level changed (slot index, level)
    SendLevelChanged(usize, f32),
    /// Send enabled toggled (slot index, enabled)
    SendToggled(usize, bool),
    /// Send pre/post toggled (slot index, pre_fader)
    SendPrePostToggled(usize, bool),
}

/// Insert/Send rack widget
pub struct InsertRack<'a, Message> {
    inserts: &'a [InsertSlot],
    sends: &'a [SendSlot],
    width: f32,
    height: f32,
    on_message: Box<dyn Fn(InsertRackMessage) -> Message + 'a>,
}

impl<'a, Message> InsertRack<'a, Message> {
    pub fn new<F>(inserts: &'a [InsertSlot], sends: &'a [SendSlot], on_message: F) -> Self
    where
        F: Fn(InsertRackMessage) -> Message + 'a,
    {
        Self {
            inserts,
            sends,
            width: 180.0,
            height: 400.0,
            on_message: Box::new(on_message),
        }
    }

    pub fn width(mut self, width: f32) -> Self {
        self.width = width;
        self
    }

    const SLOT_HEIGHT: f32 = 28.0;
    const SECTION_HEADER_HEIGHT: f32 = 20.0;
    const PADDING: f32 = 4.0;

    fn get_insert_slot_bounds(&self, index: usize, bounds: &Rectangle) -> Rectangle {
        let y_offset = Self::SECTION_HEADER_HEIGHT + index as f32 * Self::SLOT_HEIGHT;
        Rectangle {
            x: bounds.x + Self::PADDING,
            y: bounds.y + y_offset,
            width: bounds.width - Self::PADDING * 2.0,
            height: Self::SLOT_HEIGHT - 2.0,
        }
    }

    fn get_send_slot_bounds(&self, index: usize, bounds: &Rectangle) -> Rectangle {
        let inserts_height = Self::SECTION_HEADER_HEIGHT + self.inserts.len() as f32 * Self::SLOT_HEIGHT;
        let y_offset = inserts_height + Self::SECTION_HEADER_HEIGHT + 8.0 + index as f32 * Self::SLOT_HEIGHT;
        Rectangle {
            x: bounds.x + Self::PADDING,
            y: bounds.y + y_offset,
            width: bounds.width - Self::PADDING * 2.0,
            height: Self::SLOT_HEIGHT - 2.0,
        }
    }
}

/// Insert rack state
#[derive(Default)]
pub struct InsertRackState {
    hovered_insert: Option<usize>,
    hovered_send: Option<usize>,
    dragging_send: Option<usize>,
    drag_start_y: f32,
    drag_start_level: f32,
}

impl<'a, Message, Theme, Renderer> Widget<Message, Theme, Renderer> for InsertRack<'a, Message>
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
        let state = tree.state.downcast_ref::<InsertRackState>();
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

        // INSERTS section header
        renderer.fill_quad(
            renderer::Quad {
                bounds: Rectangle {
                    x: bounds.x,
                    y: bounds.y,
                    width: bounds.width,
                    height: Self::SECTION_HEADER_HEIGHT,
                },
                border: iced::Border {
                    color: Palette::BG_SURFACE,
                    width: 0.0,
                    radius: 4.0.into(),
                },
                shadow: Default::default(),
            },
            Palette::BG_MID,
        );

        // Draw insert slots
        for (i, insert) in self.inserts.iter().enumerate() {
            let slot_bounds = self.get_insert_slot_bounds(i, &bounds);
            let is_hovered = state.hovered_insert == Some(i);

            self.draw_insert_slot(renderer, &slot_bounds, insert, i, is_hovered);
        }

        // SENDS section header
        let sends_header_y = bounds.y + Self::SECTION_HEADER_HEIGHT + self.inserts.len() as f32 * Self::SLOT_HEIGHT + 8.0;
        renderer.fill_quad(
            renderer::Quad {
                bounds: Rectangle {
                    x: bounds.x,
                    y: sends_header_y,
                    width: bounds.width,
                    height: Self::SECTION_HEADER_HEIGHT,
                },
                border: Default::default(),
                shadow: Default::default(),
            },
            Palette::BG_MID,
        );

        // Draw send slots
        for (i, send) in self.sends.iter().enumerate() {
            let slot_bounds = self.get_send_slot_bounds(i, &bounds);
            let is_hovered = state.hovered_send == Some(i);

            self.draw_send_slot(renderer, &slot_bounds, send, i, is_hovered);
        }
    }

    fn tag(&self) -> widget::tree::Tag {
        widget::tree::Tag::of::<InsertRackState>()
    }

    fn state(&self) -> widget::tree::State {
        widget::tree::State::new(InsertRackState::default())
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
        let state = tree.state.downcast_mut::<InsertRackState>();
        let bounds = layout.bounds();

        match event {
            Event::Mouse(mouse::Event::ButtonPressed(mouse::Button::Left)) => {
                if let Some(pos) = cursor.position() {
                    // Check insert slots
                    for i in 0..self.inserts.len() {
                        let slot_bounds = self.get_insert_slot_bounds(i, &bounds);
                        if slot_bounds.contains(pos) {
                            shell.publish((self.on_message)(InsertRackMessage::InsertClicked(i)));
                            return iced::event::Status::Captured;
                        }
                    }

                    // Check send slots
                    for i in 0..self.sends.len() {
                        let slot_bounds = self.get_send_slot_bounds(i, &bounds);
                        if slot_bounds.contains(pos) {
                            // Start dragging for level adjustment
                            state.dragging_send = Some(i);
                            state.drag_start_y = pos.y;
                            state.drag_start_level = self.sends[i].level;
                            return iced::event::Status::Captured;
                        }
                    }
                }
            }

            Event::Mouse(mouse::Event::ButtonPressed(mouse::Button::Right)) => {
                if let Some(pos) = cursor.position() {
                    // Right-click on insert to bypass
                    for i in 0..self.inserts.len() {
                        let slot_bounds = self.get_insert_slot_bounds(i, &bounds);
                        if slot_bounds.contains(pos) && self.inserts[i].has_plugin {
                            let new_bypass = !self.inserts[i].bypassed;
                            shell.publish((self.on_message)(InsertRackMessage::InsertBypassToggled(i, new_bypass)));
                            return iced::event::Status::Captured;
                        }
                    }

                    // Right-click on send to toggle enabled
                    for i in 0..self.sends.len() {
                        let slot_bounds = self.get_send_slot_bounds(i, &bounds);
                        if slot_bounds.contains(pos) {
                            let new_enabled = !self.sends[i].enabled;
                            shell.publish((self.on_message)(InsertRackMessage::SendToggled(i, new_enabled)));
                            return iced::event::Status::Captured;
                        }
                    }
                }
            }

            Event::Mouse(mouse::Event::ButtonReleased(mouse::Button::Left)) => {
                if state.dragging_send.is_some() {
                    state.dragging_send = None;
                    return iced::event::Status::Captured;
                }
            }

            Event::Mouse(mouse::Event::CursorMoved { position }) => {
                // Update hover state
                state.hovered_insert = None;
                state.hovered_send = None;

                for i in 0..self.inserts.len() {
                    let slot_bounds = self.get_insert_slot_bounds(i, &bounds);
                    if slot_bounds.contains(position) {
                        state.hovered_insert = Some(i);
                        break;
                    }
                }

                for i in 0..self.sends.len() {
                    let slot_bounds = self.get_send_slot_bounds(i, &bounds);
                    if slot_bounds.contains(position) {
                        state.hovered_send = Some(i);
                        break;
                    }
                }

                // Handle send level drag
                if let Some(send_idx) = state.dragging_send {
                    let delta_y = state.drag_start_y - position.y;
                    let delta_level = delta_y * 0.005;
                    let new_level = (state.drag_start_level + delta_level).clamp(0.0, 1.0);

                    shell.publish((self.on_message)(InsertRackMessage::SendLevelChanged(send_idx, new_level)));
                    return iced::event::Status::Captured;
                }
            }

            Event::Mouse(mouse::Event::CursorLeft) => {
                state.hovered_insert = None;
                state.hovered_send = None;
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
        let state = tree.state.downcast_ref::<InsertRackState>();

        if state.dragging_send.is_some() {
            mouse::Interaction::ResizingVertically
        } else if state.hovered_insert.is_some() || state.hovered_send.is_some() {
            mouse::Interaction::Pointer
        } else {
            mouse::Interaction::default()
        }
    }
}

impl<'a, Message> InsertRack<'a, Message> {
    fn draw_insert_slot<Renderer: renderer::Renderer>(
        &self,
        renderer: &mut Renderer,
        bounds: &Rectangle,
        insert: &InsertSlot,
        _index: usize,
        is_hovered: bool,
    ) {
        let bg_color = if is_hovered {
            Palette::BG_SURFACE
        } else {
            Palette::BG_DEEPEST
        };

        let border_color = if insert.bypassed {
            Palette::ACCENT_RED
        } else if insert.has_plugin {
            Palette::ACCENT_CYAN
        } else {
            Palette::BG_SURFACE
        };

        // Slot background
        renderer.fill_quad(
            renderer::Quad {
                bounds: *bounds,
                border: iced::Border {
                    color: border_color,
                    width: 1.0,
                    radius: 2.0.into(),
                },
                shadow: Default::default(),
            },
            bg_color,
        );

        // Enable indicator
        if insert.has_plugin && insert.enabled && !insert.bypassed {
            renderer.fill_quad(
                renderer::Quad {
                    bounds: Rectangle {
                        x: bounds.x + 4.0,
                        y: bounds.y + bounds.height / 2.0 - 3.0,
                        width: 6.0,
                        height: 6.0,
                    },
                    border: iced::Border {
                        color: Palette::ACCENT_GREEN,
                        width: 0.0,
                        radius: 3.0.into(),
                    },
                    shadow: Default::default(),
                },
                Palette::ACCENT_GREEN,
            );
        }

        // Bypass indicator (red X)
        if insert.bypassed {
            renderer.fill_quad(
                renderer::Quad {
                    bounds: Rectangle {
                        x: bounds.x + 4.0,
                        y: bounds.y + bounds.height / 2.0 - 3.0,
                        width: 6.0,
                        height: 6.0,
                    },
                    border: iced::Border {
                        color: Palette::ACCENT_RED,
                        width: 0.0,
                        radius: 3.0.into(),
                    },
                    shadow: Default::default(),
                },
                Palette::ACCENT_RED,
            );
        }

        // Empty slot indicator
        if !insert.has_plugin {
            // Draw "+" symbol placeholder
            let center_x = bounds.x + bounds.width / 2.0;
            let center_y = bounds.y + bounds.height / 2.0;

            // Horizontal line
            renderer.fill_quad(
                renderer::Quad {
                    bounds: Rectangle {
                        x: center_x - 6.0,
                        y: center_y - 0.5,
                        width: 12.0,
                        height: 1.0,
                    },
                    border: Default::default(),
                    shadow: Default::default(),
                },
                Palette::TEXT_DISABLED,
            );

            // Vertical line
            renderer.fill_quad(
                renderer::Quad {
                    bounds: Rectangle {
                        x: center_x - 0.5,
                        y: center_y - 6.0,
                        width: 1.0,
                        height: 12.0,
                    },
                    border: Default::default(),
                    shadow: Default::default(),
                },
                Palette::TEXT_DISABLED,
            );
        }
    }

    fn draw_send_slot<Renderer: renderer::Renderer>(
        &self,
        renderer: &mut Renderer,
        bounds: &Rectangle,
        send: &SendSlot,
        _index: usize,
        is_hovered: bool,
    ) {
        let bg_color = if is_hovered {
            Palette::BG_SURFACE
        } else {
            Palette::BG_DEEPEST
        };

        let border_color = if send.enabled {
            Palette::ACCENT_ORANGE
        } else {
            Palette::BG_SURFACE
        };

        // Slot background
        renderer.fill_quad(
            renderer::Quad {
                bounds: *bounds,
                border: iced::Border {
                    color: border_color,
                    width: 1.0,
                    radius: 2.0.into(),
                },
                shadow: Default::default(),
            },
            bg_color,
        );

        // Level indicator (horizontal bar)
        if send.enabled {
            let level_width = (bounds.width - 8.0) * send.level;
            renderer.fill_quad(
                renderer::Quad {
                    bounds: Rectangle {
                        x: bounds.x + 4.0,
                        y: bounds.y + bounds.height - 6.0,
                        width: level_width,
                        height: 3.0,
                    },
                    border: Default::default(),
                    shadow: Default::default(),
                },
                Palette::ACCENT_ORANGE,
            );
        }

        // Pre-fader indicator
        if send.pre_fader {
            renderer.fill_quad(
                renderer::Quad {
                    bounds: Rectangle {
                        x: bounds.x + bounds.width - 12.0,
                        y: bounds.y + 4.0,
                        width: 8.0,
                        height: 8.0,
                    },
                    border: iced::Border {
                        color: Palette::ACCENT_CYAN,
                        width: 1.0,
                        radius: 2.0.into(),
                    },
                    shadow: Default::default(),
                },
                Palette::BG_DEEP,
            );
        }
    }
}

impl<'a, Message, Theme, Renderer> From<InsertRack<'a, Message>> for Element<'a, Message, Theme, Renderer>
where
    Renderer: renderer::Renderer + 'a,
    Message: Clone + 'a,
    Theme: 'a,
{
    fn from(rack: InsertRack<'a, Message>) -> Self {
        Element::new(rack)
    }
}
