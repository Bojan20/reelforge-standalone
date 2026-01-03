//! Mixer View Widget
//!
//! Full mixer view with:
//! - Multiple channel strips
//! - Master bus
//! - Horizontal scrolling
//! - Routing matrix view
//! - Bus grouping

use iced::advanced::layout::{self, Layout};
use iced::advanced::renderer;
use iced::advanced::widget::{self, Widget};
use iced::advanced::{Clipboard, Shell};
use iced::mouse;
use iced::{Element, Event, Length, Rectangle, Size};

use crate::theme::Palette;
use super::channel_strip::{ChannelStripData, ChannelType};

// ═══════════════════════════════════════════════════════════════════════════════
// MIXER TYPES
// ═══════════════════════════════════════════════════════════════════════════════

/// Mixer view mode
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum MixerViewMode {
    #[default]
    Channels,
    Routing,
    Sends,
}

/// Mixer messages
#[derive(Debug, Clone)]
pub enum MixerMessage {
    /// Channel selected
    SelectChannel(usize),
    /// Channel volume changed
    ChannelVolumeChanged(usize, f32),
    /// Channel pan changed
    ChannelPanChanged(usize, f32),
    /// Channel mute toggled
    ChannelMuteToggled(usize),
    /// Channel solo toggled
    ChannelSoloToggled(usize),
    /// Channel arm toggled
    ChannelArmToggled(usize),
    /// Master volume changed
    MasterVolumeChanged(f32),
    /// Scroll position changed
    ScrollChanged(f32),
    /// View mode changed
    ViewModeChanged(MixerViewMode),
    /// Channel insert clicked
    InsertClicked(usize, usize),
    /// Routing matrix cell clicked
    RoutingCellClicked(usize, usize),
}

// ═══════════════════════════════════════════════════════════════════════════════
// MIXER WIDGET
// ═══════════════════════════════════════════════════════════════════════════════

/// Mixer view widget
pub struct MixerView<'a, Message> {
    /// Channel strip data
    channels: &'a [ChannelStripData],
    /// Master channel data
    master: &'a ChannelStripData,
    /// Bus channels
    buses: &'a [ChannelStripData],
    /// Selected channel index
    selected_channel: Option<usize>,
    /// Horizontal scroll position
    scroll_x: f32,
    /// View mode
    view_mode: MixerViewMode,
    /// Show bus channels
    show_buses: bool,
    /// Show inserts section
    show_inserts: bool,
    /// Show sends section
    show_sends: bool,
    /// Widget dimensions
    width: f32,
    height: f32,
    /// Message callback
    on_message: Option<Box<dyn Fn(MixerMessage) -> Message + 'a>>,
}

impl<'a, Message> MixerView<'a, Message> {
    /// Channel strip width
    const CHANNEL_WIDTH: f32 = 80.0;
    /// Master channel width
    const MASTER_WIDTH: f32 = 100.0;
    /// Bus separator width
    const SEPARATOR_WIDTH: f32 = 8.0;
    /// Toolbar height
    const TOOLBAR_HEIGHT: f32 = 32.0;

    pub fn new(
        channels: &'a [ChannelStripData],
        buses: &'a [ChannelStripData],
        master: &'a ChannelStripData,
    ) -> Self {
        Self {
            channels,
            master,
            buses,
            selected_channel: None,
            scroll_x: 0.0,
            view_mode: MixerViewMode::Channels,
            show_buses: true,
            show_inserts: true,
            show_sends: true,
            width: 1200.0,
            height: 500.0,
            on_message: None,
        }
    }

    pub fn selected_channel(mut self, index: Option<usize>) -> Self {
        self.selected_channel = index;
        self
    }

    pub fn scroll(mut self, x: f32) -> Self {
        self.scroll_x = x;
        self
    }

    pub fn view_mode(mut self, mode: MixerViewMode) -> Self {
        self.view_mode = mode;
        self
    }

    pub fn show_buses(mut self, show: bool) -> Self {
        self.show_buses = show;
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

    pub fn size(mut self, width: f32, height: f32) -> Self {
        self.width = width;
        self.height = height;
        self
    }

    pub fn on_message<F>(mut self, callback: F) -> Self
    where
        F: Fn(MixerMessage) -> Message + 'a,
    {
        self.on_message = Some(Box::new(callback));
        self
    }

    fn total_channels_width(&self) -> f32 {
        let channels_width = self.channels.len() as f32 * Self::CHANNEL_WIDTH;
        let buses_width = if self.show_buses {
            Self::SEPARATOR_WIDTH + self.buses.len() as f32 * Self::CHANNEL_WIDTH
        } else {
            0.0
        };
        channels_width + buses_width + Self::SEPARATOR_WIDTH + Self::MASTER_WIDTH
    }

    fn max_scroll(&self) -> f32 {
        (self.total_channels_width() - self.width).max(0.0)
    }

    fn channel_at_x(&self, x: f32, bounds: &Rectangle) -> Option<(usize, bool, bool)> {
        let content_x = bounds.x - self.scroll_x;
        let relative_x = x - content_x;

        // Check audio channels
        let channels_end = self.channels.len() as f32 * Self::CHANNEL_WIDTH;
        if relative_x >= 0.0 && relative_x < channels_end {
            let idx = (relative_x / Self::CHANNEL_WIDTH) as usize;
            return Some((idx, false, false)); // (index, is_bus, is_master)
        }

        // Check buses
        if self.show_buses {
            let buses_start = channels_end + Self::SEPARATOR_WIDTH;
            let buses_end = buses_start + self.buses.len() as f32 * Self::CHANNEL_WIDTH;
            if relative_x >= buses_start && relative_x < buses_end {
                let idx = ((relative_x - buses_start) / Self::CHANNEL_WIDTH) as usize;
                return Some((idx, true, false));
            }
        }

        // Check master
        let master_start = self.total_channels_width() - Self::MASTER_WIDTH;
        if relative_x >= master_start && relative_x < self.total_channels_width() {
            return Some((0, false, true));
        }

        None
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MIXER STATE
// ═══════════════════════════════════════════════════════════════════════════════

#[derive(Default)]
pub struct MixerViewState {
    dragging_scroll: bool,
    drag_start_x: f32,
    drag_start_scroll: f32,
    hovered_channel: Option<usize>,
}

// ═══════════════════════════════════════════════════════════════════════════════
// WIDGET IMPLEMENTATION
// ═══════════════════════════════════════════════════════════════════════════════

impl<'a, Message, Theme, Renderer> Widget<Message, Theme, Renderer> for MixerView<'a, Message>
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

        // Background
        renderer.fill_quad(
            renderer::Quad {
                bounds,
                border: iced::Border {
                    color: Palette::BG_SURFACE,
                    width: 1.0,
                    radius: 0.0.into(),
                },
                shadow: Default::default(),
            },
            Palette::BG_DEEPEST,
        );

        // Toolbar
        self.draw_toolbar(renderer, &bounds);

        // Content area
        let content_bounds = Rectangle {
            x: bounds.x,
            y: bounds.y + Self::TOOLBAR_HEIGHT,
            width: bounds.width,
            height: bounds.height - Self::TOOLBAR_HEIGHT,
        };

        match self.view_mode {
            MixerViewMode::Channels => self.draw_channels_view(renderer, &content_bounds),
            MixerViewMode::Routing => self.draw_routing_view(renderer, &content_bounds),
            MixerViewMode::Sends => self.draw_sends_view(renderer, &content_bounds),
        }

        // Scrollbar
        if self.total_channels_width() > self.width {
            self.draw_scrollbar(renderer, &bounds);
        }
    }

    fn tag(&self) -> widget::tree::Tag {
        widget::tree::Tag::of::<MixerViewState>()
    }

    fn state(&self) -> widget::tree::State {
        widget::tree::State::new(MixerViewState::default())
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
        let state = tree.state.downcast_mut::<MixerViewState>();
        let bounds = layout.bounds();

        match event {
            Event::Mouse(mouse::Event::ButtonPressed(mouse::Button::Left)) => {
                if let Some(pos) = cursor.position() {
                    if bounds.contains(pos) {
                        // Check scrollbar
                        let scrollbar_bounds = self.scrollbar_bounds(&bounds);
                        if scrollbar_bounds.contains(pos) {
                            state.dragging_scroll = true;
                            state.drag_start_x = pos.x;
                            state.drag_start_scroll = self.scroll_x;
                            return iced::event::Status::Captured;
                        }

                        // Check content
                        let content_y = bounds.y + Self::TOOLBAR_HEIGHT;
                        if pos.y > content_y {
                            if let Some((idx, is_bus, is_master)) = self.channel_at_x(pos.x, &bounds) {
                                if !is_bus && !is_master {
                                    if let Some(ref on_message) = self.on_message {
                                        shell.publish(on_message(MixerMessage::SelectChannel(idx)));
                                    }
                                }
                                return iced::event::Status::Captured;
                            }
                        }
                    }
                }
            }

            Event::Mouse(mouse::Event::ButtonReleased(mouse::Button::Left)) => {
                if state.dragging_scroll {
                    state.dragging_scroll = false;
                    return iced::event::Status::Captured;
                }
            }

            Event::Mouse(mouse::Event::CursorMoved { position }) => {
                if state.dragging_scroll {
                    let scrollbar = self.scrollbar_bounds(&bounds);
                    let delta_x = position.x - state.drag_start_x;
                    let scroll_ratio = self.max_scroll() / (scrollbar.width - self.scrollbar_thumb_width(&bounds));
                    let new_scroll = (state.drag_start_scroll + delta_x * scroll_ratio).clamp(0.0, self.max_scroll());

                    if let Some(ref on_message) = self.on_message {
                        shell.publish(on_message(MixerMessage::ScrollChanged(new_scroll)));
                    }
                    return iced::event::Status::Captured;
                }
            }

            Event::Mouse(mouse::Event::WheelScrolled { delta }) => {
                if cursor.is_over(bounds) {
                    let scroll_amount = match delta {
                        mouse::ScrollDelta::Lines { x, .. } => x * 30.0,
                        mouse::ScrollDelta::Pixels { x, .. } => x,
                    };

                    let new_scroll = (self.scroll_x - scroll_amount).clamp(0.0, self.max_scroll());

                    if let Some(ref on_message) = self.on_message {
                        shell.publish(on_message(MixerMessage::ScrollChanged(new_scroll)));
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
        let state = tree.state.downcast_ref::<MixerViewState>();
        let bounds = layout.bounds();

        if state.dragging_scroll {
            return mouse::Interaction::Grabbing;
        }

        if let Some(pos) = cursor.position() {
            let scrollbar = self.scrollbar_bounds(&bounds);
            if scrollbar.contains(pos) {
                return mouse::Interaction::Grab;
            }
        }

        mouse::Interaction::default()
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DRAWING HELPERS
// ═══════════════════════════════════════════════════════════════════════════════

impl<'a, Message> MixerView<'a, Message>
where
    Message: Clone,
{
    fn scrollbar_bounds(&self, bounds: &Rectangle) -> Rectangle {
        Rectangle {
            x: bounds.x,
            y: bounds.y + bounds.height - 12.0,
            width: bounds.width,
            height: 12.0,
        }
    }

    fn scrollbar_thumb_width(&self, bounds: &Rectangle) -> f32 {
        let visible_ratio = self.width / self.total_channels_width();
        (bounds.width * visible_ratio).max(40.0)
    }

    fn draw_toolbar<Renderer: renderer::Renderer>(&self, renderer: &mut Renderer, bounds: &Rectangle) {
        let toolbar = Rectangle {
            x: bounds.x,
            y: bounds.y,
            width: bounds.width,
            height: Self::TOOLBAR_HEIGHT,
        };

        renderer.fill_quad(
            renderer::Quad {
                bounds: toolbar,
                border: Default::default(),
                shadow: Default::default(),
            },
            Palette::BG_MID,
        );

        // View mode buttons
        let modes = [
            ("Channels", MixerViewMode::Channels),
            ("Routing", MixerViewMode::Routing),
            ("Sends", MixerViewMode::Sends),
        ];

        let button_width = 80.0;
        let button_height = 24.0;
        let start_x = toolbar.x + 8.0;
        let button_y = toolbar.y + (toolbar.height - button_height) / 2.0;

        for (i, (_label, mode)) in modes.iter().enumerate() {
            let btn_bounds = Rectangle {
                x: start_x + i as f32 * (button_width + 4.0),
                y: button_y,
                width: button_width,
                height: button_height,
            };

            let bg = if *mode == self.view_mode {
                Palette::ACCENT_BLUE
            } else {
                Palette::BG_SURFACE
            };

            renderer.fill_quad(
                renderer::Quad {
                    bounds: btn_bounds,
                    border: iced::Border {
                        color: Palette::BG_SURFACE,
                        width: 1.0,
                        radius: 4.0.into(),
                    },
                    shadow: Default::default(),
                },
                bg,
            );
        }

        // Toolbar bottom border
        renderer.fill_quad(
            renderer::Quad {
                bounds: Rectangle {
                    x: toolbar.x,
                    y: toolbar.y + toolbar.height - 1.0,
                    width: toolbar.width,
                    height: 1.0,
                },
                border: Default::default(),
                shadow: Default::default(),
            },
            Palette::BG_SURFACE,
        );
    }

    fn draw_channels_view<Renderer: renderer::Renderer>(&self, renderer: &mut Renderer, bounds: &Rectangle) {
        let mut x = bounds.x - self.scroll_x;

        // Draw channel strips
        for (i, channel) in self.channels.iter().enumerate() {
            if x + Self::CHANNEL_WIDTH > bounds.x && x < bounds.x + bounds.width {
                self.draw_channel_strip(renderer, channel, x, bounds.y, bounds.height, self.selected_channel == Some(i));
            }
            x += Self::CHANNEL_WIDTH;
        }

        // Separator
        if self.show_buses {
            renderer.fill_quad(
                renderer::Quad {
                    bounds: Rectangle {
                        x,
                        y: bounds.y,
                        width: Self::SEPARATOR_WIDTH,
                        height: bounds.height,
                    },
                    border: Default::default(),
                    shadow: Default::default(),
                },
                Palette::BG_MID,
            );
            x += Self::SEPARATOR_WIDTH;

            // Draw bus strips
            for bus in self.buses.iter() {
                if x + Self::CHANNEL_WIDTH > bounds.x && x < bounds.x + bounds.width {
                    self.draw_channel_strip(renderer, bus, x, bounds.y, bounds.height, false);
                }
                x += Self::CHANNEL_WIDTH;
            }
        }

        // Master separator
        let master_x = bounds.x + bounds.width - Self::MASTER_WIDTH;
        renderer.fill_quad(
            renderer::Quad {
                bounds: Rectangle {
                    x: master_x - Self::SEPARATOR_WIDTH,
                    y: bounds.y,
                    width: Self::SEPARATOR_WIDTH,
                    height: bounds.height,
                },
                border: Default::default(),
                shadow: Default::default(),
            },
            Palette::BG_MID,
        );

        // Master channel (always visible on right)
        self.draw_channel_strip(renderer, self.master, master_x, bounds.y, bounds.height, false);
    }

    fn draw_channel_strip<Renderer: renderer::Renderer>(
        &self,
        renderer: &mut Renderer,
        channel: &ChannelStripData,
        x: f32,
        y: f32,
        height: f32,
        selected: bool,
    ) {
        let strip_bounds = Rectangle {
            x,
            y,
            width: if channel.channel_type == ChannelType::Master {
                Self::MASTER_WIDTH
            } else {
                Self::CHANNEL_WIDTH
            },
            height,
        };

        // Background
        let bg = if selected {
            iced::Color::from_rgba(0.15, 0.15, 0.2, 1.0)
        } else {
            Palette::BG_DEEP
        };

        renderer.fill_quad(
            renderer::Quad {
                bounds: strip_bounds,
                border: iced::Border {
                    color: if selected {
                        Palette::ACCENT_BLUE
                    } else {
                        Palette::BG_SURFACE
                    },
                    width: 1.0,
                    radius: 0.0.into(),
                },
                shadow: Default::default(),
            },
            bg,
        );

        // Color bar at top
        let color = channel.color.map(|c| {
            iced::Color::from_rgb(
                ((c >> 16) & 0xFF) as f32 / 255.0,
                ((c >> 8) & 0xFF) as f32 / 255.0,
                (c & 0xFF) as f32 / 255.0,
            )
        }).unwrap_or(match channel.channel_type {
            ChannelType::Master => Palette::ACCENT_ORANGE,
            ChannelType::Bus => Palette::ACCENT_GREEN,
            _ => Palette::ACCENT_CYAN,
        });

        renderer.fill_quad(
            renderer::Quad {
                bounds: Rectangle {
                    x: strip_bounds.x,
                    y: strip_bounds.y,
                    width: strip_bounds.width,
                    height: 4.0,
                },
                border: Default::default(),
                shadow: Default::default(),
            },
            color,
        );

        // Mute/Solo/Arm buttons
        let button_size = 18.0;
        let button_y = strip_bounds.y + 28.0;
        let buttons_start_x = strip_bounds.x + (strip_bounds.width - 3.0 * button_size - 8.0) / 2.0;

        for (i, (active, active_color)) in [
            (channel.mute, Palette::ACCENT_ORANGE),
            (channel.solo, Palette::ACCENT_YELLOW),
            (channel.armed, Palette::ACCENT_RED),
        ].iter().enumerate() {
            let btn_bounds = Rectangle {
                x: buttons_start_x + i as f32 * (button_size + 4.0),
                y: button_y,
                width: button_size,
                height: button_size,
            };

            let btn_bg = if *active { *active_color } else { Palette::BG_MID };

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
                btn_bg,
            );
        }

        // Fader and meter area
        let fader_height = 150.0;
        let fader_y = strip_bounds.y + strip_bounds.height - fader_height - 30.0;

        // Fader track
        let fader_width = 28.0;
        let fader_x = strip_bounds.x + (strip_bounds.width - fader_width) / 2.0;

        renderer.fill_quad(
            renderer::Quad {
                bounds: Rectangle {
                    x: fader_x,
                    y: fader_y,
                    width: fader_width,
                    height: fader_height,
                },
                border: iced::Border {
                    color: Palette::BG_SURFACE,
                    width: 1.0,
                    radius: 2.0.into(),
                },
                shadow: Default::default(),
            },
            Palette::BG_DEEPEST,
        );

        // Fader level
        let level_height = fader_height * channel.volume;
        renderer.fill_quad(
            renderer::Quad {
                bounds: Rectangle {
                    x: fader_x + 1.0,
                    y: fader_y + fader_height - level_height - 1.0,
                    width: fader_width - 2.0,
                    height: level_height,
                },
                border: Default::default(),
                shadow: Default::default(),
            },
            Palette::ACCENT_BLUE,
        );

        // Fader handle
        let handle_height = 16.0;
        let handle_y = fader_y + fader_height * (1.0 - channel.volume) - handle_height / 2.0;
        renderer.fill_quad(
            renderer::Quad {
                bounds: Rectangle {
                    x: fader_x - 2.0,
                    y: handle_y.clamp(fader_y, fader_y + fader_height - handle_height),
                    width: fader_width + 4.0,
                    height: handle_height,
                },
                border: iced::Border {
                    color: Palette::BG_SURFACE,
                    width: 1.0,
                    radius: 3.0.into(),
                },
                shadow: Default::default(),
            },
            Palette::BG_MID,
        );
    }

    fn draw_routing_view<Renderer: renderer::Renderer>(&self, renderer: &mut Renderer, bounds: &Rectangle) {
        // Routing matrix placeholder
        let grid_size = 24.0;
        let header_height = 60.0;
        let label_width = 100.0;

        // Draw row labels (sources)
        let mut y = bounds.y + header_height;
        for channel in self.channels.iter() {
            if y + grid_size > bounds.y + bounds.height {
                break;
            }

            renderer.fill_quad(
                renderer::Quad {
                    bounds: Rectangle {
                        x: bounds.x,
                        y,
                        width: label_width,
                        height: grid_size,
                    },
                    border: iced::Border {
                        color: Palette::BG_SURFACE,
                        width: 1.0,
                        radius: 0.0.into(),
                    },
                    shadow: Default::default(),
                },
                Palette::BG_DEEP,
            );

            y += grid_size;
        }

        // Draw column headers (destinations) and grid
        let mut x = bounds.x + label_width;
        for (_i, bus) in self.buses.iter().enumerate() {
            if x + grid_size > bounds.x + bounds.width {
                break;
            }

            // Header
            renderer.fill_quad(
                renderer::Quad {
                    bounds: Rectangle {
                        x,
                        y: bounds.y,
                        width: grid_size,
                        height: header_height,
                    },
                    border: iced::Border {
                        color: Palette::BG_SURFACE,
                        width: 1.0,
                        radius: 0.0.into(),
                    },
                    shadow: Default::default(),
                },
                Palette::BG_DEEP,
            );

            // Grid cells
            let mut cell_y = bounds.y + header_height;
            for _channel in self.channels.iter() {
                if cell_y + grid_size > bounds.y + bounds.height {
                    break;
                }

                renderer.fill_quad(
                    renderer::Quad {
                        bounds: Rectangle {
                            x,
                            y: cell_y,
                            width: grid_size,
                            height: grid_size,
                        },
                        border: iced::Border {
                            color: Palette::BG_SURFACE,
                            width: 1.0,
                            radius: 0.0.into(),
                        },
                        shadow: Default::default(),
                    },
                    Palette::BG_DEEPEST,
                );

                cell_y += grid_size;
            }

            x += grid_size;
        }
    }

    fn draw_sends_view<Renderer: renderer::Renderer>(&self, renderer: &mut Renderer, bounds: &Rectangle) {
        // Sends view - shows send levels for each channel
        let row_height = 30.0;
        let label_width = 120.0;
        let send_width = 60.0;

        let mut y = bounds.y + 8.0;

        // Header row with bus names
        renderer.fill_quad(
            renderer::Quad {
                bounds: Rectangle {
                    x: bounds.x,
                    y,
                    width: bounds.width,
                    height: row_height,
                },
                border: Default::default(),
                shadow: Default::default(),
            },
            Palette::BG_MID,
        );
        y += row_height;

        // Channel rows with send knobs
        for channel in self.channels.iter() {
            if y + row_height > bounds.y + bounds.height {
                break;
            }

            // Channel name
            renderer.fill_quad(
                renderer::Quad {
                    bounds: Rectangle {
                        x: bounds.x,
                        y,
                        width: label_width,
                        height: row_height,
                    },
                    border: iced::Border {
                        color: Palette::BG_SURFACE,
                        width: 1.0,
                        radius: 0.0.into(),
                    },
                    shadow: Default::default(),
                },
                Palette::BG_DEEP,
            );

            // Send slots
            let mut send_x = bounds.x + label_width;
            for send in channel.sends.iter() {
                if send_x + send_width > bounds.x + bounds.width {
                    break;
                }

                // Send cell
                renderer.fill_quad(
                    renderer::Quad {
                        bounds: Rectangle {
                            x: send_x,
                            y,
                            width: send_width,
                            height: row_height,
                        },
                        border: iced::Border {
                            color: Palette::BG_SURFACE,
                            width: 1.0,
                            radius: 0.0.into(),
                        },
                        shadow: Default::default(),
                    },
                    Palette::BG_DEEPEST,
                );

                // Send level indicator
                let level_width = (send_width - 8.0) * send.level;
                renderer.fill_quad(
                    renderer::Quad {
                        bounds: Rectangle {
                            x: send_x + 4.0,
                            y: y + row_height / 2.0 - 3.0,
                            width: level_width,
                            height: 6.0,
                        },
                        border: Default::default(),
                        shadow: Default::default(),
                    },
                    if send.pre_fader {
                        Palette::ACCENT_CYAN
                    } else {
                        Palette::ACCENT_BLUE
                    },
                );

                send_x += send_width;
            }

            y += row_height;
        }
    }

    fn draw_scrollbar<Renderer: renderer::Renderer>(&self, renderer: &mut Renderer, bounds: &Rectangle) {
        let scrollbar = self.scrollbar_bounds(bounds);

        // Scrollbar background
        renderer.fill_quad(
            renderer::Quad {
                bounds: scrollbar,
                border: Default::default(),
                shadow: Default::default(),
            },
            Palette::BG_DEEP,
        );

        // Scrollbar thumb
        let thumb_width = self.scrollbar_thumb_width(bounds);
        let scroll_ratio = self.scroll_x / self.max_scroll();
        let thumb_x = scrollbar.x + (scrollbar.width - thumb_width) * scroll_ratio;

        renderer.fill_quad(
            renderer::Quad {
                bounds: Rectangle {
                    x: thumb_x,
                    y: scrollbar.y + 2.0,
                    width: thumb_width,
                    height: scrollbar.height - 4.0,
                },
                border: iced::Border {
                    color: Palette::BG_SURFACE,
                    width: 0.0,
                    radius: 4.0.into(),
                },
                shadow: Default::default(),
            },
            Palette::BG_SURFACE,
        );
    }
}

impl<'a, Message, Theme, Renderer> From<MixerView<'a, Message>> for Element<'a, Message, Theme, Renderer>
where
    Renderer: renderer::Renderer + 'a,
    Message: Clone + 'a,
    Theme: 'a,
{
    fn from(mixer: MixerView<'a, Message>) -> Self {
        Element::new(mixer)
    }
}
