//! Preset Browser Widget
//!
//! Browse and select presets with categories and search

use iced::advanced::layout::{self, Layout};
use iced::advanced::renderer;
use iced::advanced::widget::{self, Widget};
use iced::advanced::{Clipboard, Shell};
use iced::mouse;
use iced::{Element, Event, Length, Rectangle, Size};

use crate::theme::Palette;

/// Preset entry for display
#[derive(Debug, Clone)]
pub struct PresetEntry {
    pub id: String,
    pub name: String,
    pub category: String,
    pub author: String,
    pub is_factory: bool,
    pub is_favorite: bool,
}

impl PresetEntry {
    pub fn new(id: impl Into<String>, name: impl Into<String>) -> Self {
        Self {
            id: id.into(),
            name: name.into(),
            category: String::new(),
            author: String::new(),
            is_factory: false,
            is_favorite: false,
        }
    }

    pub fn category(mut self, category: impl Into<String>) -> Self {
        self.category = category.into();
        self
    }

    pub fn author(mut self, author: impl Into<String>) -> Self {
        self.author = author.into();
        self
    }

    pub fn factory(mut self) -> Self {
        self.is_factory = true;
        self
    }

    pub fn favorite(mut self) -> Self {
        self.is_favorite = true;
        self
    }
}

/// Preset browser messages
#[derive(Debug, Clone)]
pub enum PresetBrowserMessage {
    /// Preset selected (id)
    PresetSelected(String),
    /// Category selected
    CategorySelected(String),
    /// Toggle favorite (id)
    ToggleFavorite(String),
    /// Save current as preset
    SavePreset,
    /// Delete preset (id)
    DeletePreset(String),
    /// Previous preset
    PreviousPreset,
    /// Next preset
    NextPreset,
}

/// Preset browser widget
pub struct PresetBrowser<'a, Message> {
    presets: &'a [PresetEntry],
    categories: &'a [String],
    selected_category: Option<&'a str>,
    selected_preset: Option<&'a str>,
    current_preset_name: &'a str,
    width: f32,
    height: f32,
    compact: bool,  // Compact mode shows only current preset with prev/next buttons
    on_message: Box<dyn Fn(PresetBrowserMessage) -> Message + 'a>,
}

impl<'a, Message> PresetBrowser<'a, Message> {
    pub fn new<F>(
        presets: &'a [PresetEntry],
        current_preset_name: &'a str,
        on_message: F,
    ) -> Self
    where
        F: Fn(PresetBrowserMessage) -> Message + 'a,
    {
        Self {
            presets,
            categories: &[],
            selected_category: None,
            selected_preset: None,
            current_preset_name,
            width: 300.0,
            height: 400.0,
            compact: false,
            on_message: Box::new(on_message),
        }
    }

    pub fn categories(mut self, categories: &'a [String], selected: Option<&'a str>) -> Self {
        self.categories = categories;
        self.selected_category = selected;
        self
    }

    pub fn selected_preset(mut self, id: Option<&'a str>) -> Self {
        self.selected_preset = id;
        self
    }

    pub fn size(mut self, width: f32, height: f32) -> Self {
        self.width = width;
        self.height = height;
        self
    }

    pub fn compact(mut self, compact: bool) -> Self {
        self.compact = compact;
        self
    }

    const ITEM_HEIGHT: f32 = 32.0;
    const HEADER_HEIGHT: f32 = 40.0;
    const NAV_BUTTON_WIDTH: f32 = 32.0;

    fn get_preset_bounds(&self, index: usize, bounds: &Rectangle) -> Rectangle {
        let y_offset = Self::HEADER_HEIGHT + index as f32 * Self::ITEM_HEIGHT;
        Rectangle {
            x: bounds.x + 4.0,
            y: bounds.y + y_offset,
            width: bounds.width - 8.0,
            height: Self::ITEM_HEIGHT - 2.0,
        }
    }
}

/// Preset browser state
#[derive(Default)]
pub struct PresetBrowserState {
    hovered_preset: Option<usize>,
    hovered_button: Option<&'static str>,
    scroll_offset: f32,
}

impl<'a, Message, Theme, Renderer> Widget<Message, Theme, Renderer> for PresetBrowser<'a, Message>
where
    Renderer: renderer::Renderer,
    Message: Clone,
{
    fn size(&self) -> Size<Length> {
        if self.compact {
            Size::new(Length::Fixed(self.width), Length::Fixed(Self::HEADER_HEIGHT))
        } else {
            Size::new(Length::Fixed(self.width), Length::Fixed(self.height))
        }
    }

    fn layout(
        &self,
        _tree: &mut widget::Tree,
        _renderer: &Renderer,
        _limits: &layout::Limits,
    ) -> layout::Node {
        if self.compact {
            layout::Node::new(Size::new(self.width, Self::HEADER_HEIGHT))
        } else {
            layout::Node::new(Size::new(self.width, self.height))
        }
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
        let state = tree.state.downcast_ref::<PresetBrowserState>();
        let bounds = layout.bounds();

        if self.compact {
            self.draw_compact(renderer, &bounds, state);
        } else {
            self.draw_full(renderer, &bounds, state);
        }
    }

    fn tag(&self) -> widget::tree::Tag {
        widget::tree::Tag::of::<PresetBrowserState>()
    }

    fn state(&self) -> widget::tree::State {
        widget::tree::State::new(PresetBrowserState::default())
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
        let state = tree.state.downcast_mut::<PresetBrowserState>();
        let bounds = layout.bounds();

        match event {
            Event::Mouse(mouse::Event::ButtonPressed(mouse::Button::Left)) => {
                if let Some(pos) = cursor.position() {
                    if bounds.contains(pos) {
                        if self.compact {
                            // Check prev/next buttons
                            let prev_bounds = Rectangle {
                                x: bounds.x,
                                y: bounds.y,
                                width: Self::NAV_BUTTON_WIDTH,
                                height: bounds.height,
                            };
                            let next_bounds = Rectangle {
                                x: bounds.x + bounds.width - Self::NAV_BUTTON_WIDTH,
                                y: bounds.y,
                                width: Self::NAV_BUTTON_WIDTH,
                                height: bounds.height,
                            };

                            if prev_bounds.contains(pos) {
                                shell.publish((self.on_message)(PresetBrowserMessage::PreviousPreset));
                                return iced::event::Status::Captured;
                            }
                            if next_bounds.contains(pos) {
                                shell.publish((self.on_message)(PresetBrowserMessage::NextPreset));
                                return iced::event::Status::Captured;
                            }
                        } else {
                            // Check preset items
                            for (i, preset) in self.presets.iter().enumerate() {
                                let item_bounds = self.get_preset_bounds(i, &bounds);
                                if item_bounds.contains(pos) {
                                    shell.publish((self.on_message)(PresetBrowserMessage::PresetSelected(
                                        preset.id.clone(),
                                    )));
                                    return iced::event::Status::Captured;
                                }
                            }
                        }
                    }
                }
            }

            Event::Mouse(mouse::Event::ButtonPressed(mouse::Button::Right)) => {
                if let Some(pos) = cursor.position() {
                    if !self.compact {
                        for (i, preset) in self.presets.iter().enumerate() {
                            let item_bounds = self.get_preset_bounds(i, &bounds);
                            if item_bounds.contains(pos) {
                                // Toggle favorite on right-click
                                shell.publish((self.on_message)(PresetBrowserMessage::ToggleFavorite(
                                    preset.id.clone(),
                                )));
                                return iced::event::Status::Captured;
                            }
                        }
                    }
                }
            }

            Event::Mouse(mouse::Event::CursorMoved { position }) => {
                state.hovered_preset = None;
                state.hovered_button = None;

                if bounds.contains(position) {
                    if self.compact {
                        let prev_bounds = Rectangle {
                            x: bounds.x,
                            y: bounds.y,
                            width: Self::NAV_BUTTON_WIDTH,
                            height: bounds.height,
                        };
                        let next_bounds = Rectangle {
                            x: bounds.x + bounds.width - Self::NAV_BUTTON_WIDTH,
                            y: bounds.y,
                            width: Self::NAV_BUTTON_WIDTH,
                            height: bounds.height,
                        };

                        if prev_bounds.contains(position) {
                            state.hovered_button = Some("prev");
                        } else if next_bounds.contains(position) {
                            state.hovered_button = Some("next");
                        }
                    } else {
                        for i in 0..self.presets.len() {
                            let item_bounds = self.get_preset_bounds(i, &bounds);
                            if item_bounds.contains(position) {
                                state.hovered_preset = Some(i);
                                break;
                            }
                        }
                    }
                }
            }

            Event::Mouse(mouse::Event::WheelScrolled { delta }) => {
                if cursor.is_over(bounds) && !self.compact {
                    let scroll_amount = match delta {
                        mouse::ScrollDelta::Lines { y, .. } => y * Self::ITEM_HEIGHT,
                        mouse::ScrollDelta::Pixels { y, .. } => y,
                    };
                    state.scroll_offset = (state.scroll_offset - scroll_amount).max(0.0);
                    return iced::event::Status::Captured;
                }
            }

            Event::Mouse(mouse::Event::CursorLeft) => {
                state.hovered_preset = None;
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
        let state = tree.state.downcast_ref::<PresetBrowserState>();

        if state.hovered_preset.is_some() || state.hovered_button.is_some() {
            mouse::Interaction::Pointer
        } else {
            mouse::Interaction::default()
        }
    }
}

impl<'a, Message> PresetBrowser<'a, Message> {
    fn draw_compact<Renderer: renderer::Renderer>(
        &self,
        renderer: &mut Renderer,
        bounds: &Rectangle,
        state: &PresetBrowserState,
    ) {
        // Background
        renderer.fill_quad(
            renderer::Quad {
                bounds: *bounds,
                border: iced::Border {
                    color: Palette::BG_SURFACE,
                    width: 1.0,
                    radius: 4.0.into(),
                },
                shadow: Default::default(),
            },
            Palette::BG_DEEP,
        );

        // Previous button
        let prev_bounds = Rectangle {
            x: bounds.x,
            y: bounds.y,
            width: Self::NAV_BUTTON_WIDTH,
            height: bounds.height,
        };
        let prev_color = if state.hovered_button == Some("prev") {
            Palette::BG_SURFACE
        } else {
            Palette::BG_MID
        };

        renderer.fill_quad(
            renderer::Quad {
                bounds: prev_bounds,
                border: iced::Border {
                    color: Palette::BG_SURFACE,
                    width: 0.0,
                    radius: 4.0.into(),
                },
                shadow: Default::default(),
            },
            prev_color,
        );

        // Draw < arrow
        let arrow_x = prev_bounds.x + prev_bounds.width / 2.0;
        let arrow_y = prev_bounds.y + prev_bounds.height / 2.0;
        self.draw_arrow(renderer, arrow_x, arrow_y, true);

        // Next button
        let next_bounds = Rectangle {
            x: bounds.x + bounds.width - Self::NAV_BUTTON_WIDTH,
            y: bounds.y,
            width: Self::NAV_BUTTON_WIDTH,
            height: bounds.height,
        };
        let next_color = if state.hovered_button == Some("next") {
            Palette::BG_SURFACE
        } else {
            Palette::BG_MID
        };

        renderer.fill_quad(
            renderer::Quad {
                bounds: next_bounds,
                border: iced::Border {
                    color: Palette::BG_SURFACE,
                    width: 0.0,
                    radius: 4.0.into(),
                },
                shadow: Default::default(),
            },
            next_color,
        );

        // Draw > arrow
        let arrow_x = next_bounds.x + next_bounds.width / 2.0;
        let arrow_y = next_bounds.y + next_bounds.height / 2.0;
        self.draw_arrow(renderer, arrow_x, arrow_y, false);

        // Current preset name area (center)
        let name_bounds = Rectangle {
            x: bounds.x + Self::NAV_BUTTON_WIDTH,
            y: bounds.y,
            width: bounds.width - Self::NAV_BUTTON_WIDTH * 2.0,
            height: bounds.height,
        };

        renderer.fill_quad(
            renderer::Quad {
                bounds: name_bounds,
                border: Default::default(),
                shadow: Default::default(),
            },
            Palette::BG_DEEPEST,
        );
    }

    fn draw_full<Renderer: renderer::Renderer>(
        &self,
        renderer: &mut Renderer,
        bounds: &Rectangle,
        state: &PresetBrowserState,
    ) {
        // Background
        renderer.fill_quad(
            renderer::Quad {
                bounds: *bounds,
                border: iced::Border {
                    color: Palette::BG_SURFACE,
                    width: 1.0,
                    radius: 4.0.into(),
                },
                shadow: Default::default(),
            },
            Palette::BG_DEEP,
        );

        // Header
        renderer.fill_quad(
            renderer::Quad {
                bounds: Rectangle {
                    x: bounds.x,
                    y: bounds.y,
                    width: bounds.width,
                    height: Self::HEADER_HEIGHT,
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

        // Draw preset list
        for (i, preset) in self.presets.iter().enumerate() {
            let item_bounds = self.get_preset_bounds(i, bounds);

            // Skip if outside visible area
            if item_bounds.y + item_bounds.height < bounds.y + Self::HEADER_HEIGHT {
                continue;
            }
            if item_bounds.y > bounds.y + bounds.height {
                break;
            }

            let is_selected = self.selected_preset == Some(&preset.id);
            let is_hovered = state.hovered_preset == Some(i);

            let bg_color = if is_selected {
                Palette::ACCENT_BLUE
            } else if is_hovered {
                Palette::BG_SURFACE
            } else {
                Palette::BG_DEEPEST
            };

            // Item background
            renderer.fill_quad(
                renderer::Quad {
                    bounds: item_bounds,
                    border: iced::Border {
                        color: if is_selected {
                            Palette::ACCENT_BLUE
                        } else {
                            Palette::BG_SURFACE
                        },
                        width: 1.0,
                        radius: 2.0.into(),
                    },
                    shadow: Default::default(),
                },
                bg_color,
            );

            // Favorite indicator
            if preset.is_favorite {
                renderer.fill_quad(
                    renderer::Quad {
                        bounds: Rectangle {
                            x: item_bounds.x + 4.0,
                            y: item_bounds.y + item_bounds.height / 2.0 - 4.0,
                            width: 8.0,
                            height: 8.0,
                        },
                        border: iced::Border {
                            color: Palette::ACCENT_ORANGE,
                            width: 0.0,
                            radius: 4.0.into(),
                        },
                        shadow: Default::default(),
                    },
                    Palette::ACCENT_ORANGE,
                );
            }

            // Factory indicator
            if preset.is_factory {
                renderer.fill_quad(
                    renderer::Quad {
                        bounds: Rectangle {
                            x: item_bounds.x + item_bounds.width - 12.0,
                            y: item_bounds.y + item_bounds.height / 2.0 - 4.0,
                            width: 8.0,
                            height: 8.0,
                        },
                        border: iced::Border {
                            color: Palette::TEXT_DISABLED,
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

    fn draw_arrow<Renderer: renderer::Renderer>(&self, renderer: &mut Renderer, x: f32, y: f32, left: bool) {
        let dir = if left { -1.0 } else { 1.0 };

        // Simple arrow using rectangles
        for i in 0i32..3 {
            let offset = (i as f32 - 1.0) * 3.0;
            let len = 3 - (i - 1).abs();

            renderer.fill_quad(
                renderer::Quad {
                    bounds: Rectangle {
                        x: x + dir * (offset - 1.0),
                        y: y - len as f32,
                        width: 2.0,
                        height: (len * 2) as f32,
                    },
                    border: Default::default(),
                    shadow: Default::default(),
                },
                Palette::TEXT_PRIMARY,
            );
        }
    }
}

impl<'a, Message, Theme, Renderer> From<PresetBrowser<'a, Message>> for Element<'a, Message, Theme, Renderer>
where
    Renderer: renderer::Renderer + 'a,
    Message: Clone + 'a,
    Theme: 'a,
{
    fn from(browser: PresetBrowser<'a, Message>) -> Self {
        Element::new(browser)
    }
}
