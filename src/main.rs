//! ReelForge Standalone - Professional Audio Editor
//!
//! Main entry point for the ReelForge application.

use std::sync::Arc;
use std::time::{Duration, Instant};

use iced::widget::{column, container, row, text, Row};
use iced::{Element, Length, Subscription, Task, Theme};

use rf_core::{BufferSize, SampleRate};
use rf_engine::{ChannelId, MeterBridge, MixerHandle, RealtimeEngine};
use rf_gui::widgets::{Fader, StereoMeter};

fn main() -> iced::Result {
    env_logger::init();
    log::info!("Starting ReelForge...");

    iced::application("ReelForge Standalone", ReelForge::update, ReelForge::view)
        .subscription(ReelForge::subscription)
        .theme(|_| Theme::Dark)
        .window_size((1200.0, 800.0))
        .antialiasing(true)
        .run_with(|| (ReelForge::new(), Task::none()))
}

/// Main application state
struct ReelForge {
    // Audio engine
    engine: Option<RealtimeEngine>,

    // Cached meter values (updated from meter bridge)
    bus_meters: [(f32, f32); 6],     // (left, right) peak for each bus
    bus_gr: [f32; 6],                // Gain reduction per bus
    master_meter: (f32, f32),        // Master peaks
    master_gr: f32,                  // Master limiter GR
    lufs_short: f32,                 // Short-term LUFS
    lufs_integrated: f32,            // Integrated LUFS
    true_peak: f32,                  // True peak dB

    // Fader positions (linear 0-1)
    bus_levels: [f32; 6],
    master_level: f32,

    // Last meter update time
    last_meter_update: Instant,
}

#[derive(Debug, Clone)]
enum Message {
    /// Fader moved
    BusLevelChanged(usize, f32),
    MasterLevelChanged(f32),

    /// Tick for meter updates
    Tick,

    /// Audio engine error
    AudioError(String),
}

impl ReelForge {
    fn new() -> Self {
        // Try to start audio engine
        let engine = match RealtimeEngine::new(SampleRate::Hz48000, BufferSize::Samples256) {
            Ok(engine) => {
                log::info!(
                    "Audio engine started: {}Hz, {} samples",
                    engine.sample_rate(),
                    engine.block_size()
                );
                Some(engine)
            }
            Err(e) => {
                log::error!("Failed to start audio engine: {}", e);
                None
            }
        };

        Self {
            engine,
            bus_meters: [(0.0, 0.0); 6],
            bus_gr: [0.0; 6],
            master_meter: (0.0, 0.0),
            master_gr: 0.0,
            lufs_short: -70.0,
            lufs_integrated: -70.0,
            true_peak: -70.0,
            bus_levels: [0.75; 6], // Default to ~-6dB
            master_level: 0.75,
            last_meter_update: Instant::now(),
        }
    }

    fn subscription(&self) -> Subscription<Message> {
        // Update meters at 60fps
        iced::time::every(Duration::from_millis(16)).map(|_| Message::Tick)
    }

    fn update(&mut self, message: Message) -> Task<Message> {
        match message {
            Message::BusLevelChanged(index, value) => {
                if index < 6 {
                    self.bus_levels[index] = value;

                    // Send to audio engine
                    if let Some(ref mut engine) = self.engine {
                        let channel_id = match index {
                            0 => ChannelId::Ui,
                            1 => ChannelId::Reels,
                            2 => ChannelId::Fx,
                            3 => ChannelId::Vo,
                            4 => ChannelId::Music,
                            5 => ChannelId::Ambient,
                            _ => return Task::none(),
                        };
                        let db = level_to_db(value);
                        engine.mixer_handle_mut().set_channel_volume(channel_id, db as f64);
                    }
                }
            }

            Message::MasterLevelChanged(value) => {
                self.master_level = value;

                if let Some(ref mut engine) = self.engine {
                    let db = level_to_db(value);
                    engine.mixer_handle_mut().set_master_volume(db as f64);
                }
            }

            Message::Tick => {
                // Read meters from audio engine
                if let Some(ref engine) = self.engine {
                    let handle = engine.mixer_handle();

                    // Read bus meters
                    for (i, channel_id) in [
                        ChannelId::Ui,
                        ChannelId::Reels,
                        ChannelId::Fx,
                        ChannelId::Vo,
                        ChannelId::Music,
                        ChannelId::Ambient,
                    ]
                    .iter()
                    .enumerate()
                    {
                        let (l, r) = handle.channel_peak(*channel_id);
                        // Convert dB to linear for display (meters expect 0-1)
                        self.bus_meters[i] = (db_to_meter(l as f32), db_to_meter(r as f32));
                        self.bus_gr[i] = handle.channel_gain_reduction(*channel_id) as f32;
                    }

                    // Read master meters
                    let (ml, mr) = handle.master_peak();
                    self.master_meter = (db_to_meter(ml as f32), db_to_meter(mr as f32));
                    self.master_gr = handle.master_gain_reduction() as f32;

                    // Read loudness
                    let (lufs_s, lufs_i) = handle.lufs();
                    self.lufs_short = lufs_s as f32;
                    self.lufs_integrated = lufs_i as f32;
                    self.true_peak = handle.true_peak() as f32;

                    self.last_meter_update = Instant::now();
                }
            }

            Message::AudioError(err) => {
                log::error!("Audio error: {}", err);
            }
        }

        Task::none()
    }

    fn view(&self) -> Element<'_, Message> {
        let bus_names = ["UI", "REELS", "FX", "VO", "MUSIC", "AMBIENT"];

        // Create bus channel strips
        let bus_strips: Vec<Element<Message>> = (0..6)
            .map(|i| {
                let name = bus_names[i];
                let level = self.bus_levels[i];
                let (meter_l, meter_r) = self.bus_meters[i];

                self.channel_strip(name, i, level, meter_l, meter_r)
            })
            .collect();

        // Master strip
        let master_strip = self.master_strip();

        // Loudness display
        let loudness = column![
            text("LOUDNESS").size(10),
            text(format!("{:.1} LUFS", self.lufs_short)).size(11),
            text(format!("∫ {:.1}", self.lufs_integrated)).size(10),
            text(format!("TP {:.1}", self.true_peak)).size(10),
        ]
        .spacing(4)
        .align_x(iced::Alignment::Center);

        // Audio status
        let status = if self.engine.is_some() {
            text("● Audio Running").size(11)
        } else {
            text("○ No Audio").size(11)
        };

        // Main mixer layout
        let mixer = row![
            Row::with_children(bus_strips).spacing(8),
            container(text("│")).padding(8),
            master_strip,
            container(loudness).padding(16),
        ]
        .spacing(16)
        .padding(16);

        // Header
        let header = container(
            row![
                text("ReelForge").size(24),
                text(" │ ").size(24),
                text("Mixer").size(18),
                container(status).padding(iced::Padding::from([0, 32])),
            ]
            .spacing(8),
        )
        .padding(16)
        .width(Length::Fill);

        // Main layout
        let content = column![header, mixer,].spacing(8);

        container(content)
            .width(Length::Fill)
            .height(Length::Fill)
            .into()
    }

    fn channel_strip(
        &self,
        name: &'static str,
        index: usize,
        level: f32,
        meter_l: f32,
        meter_r: f32,
    ) -> Element<'_, Message> {
        column![
            // Bus name
            text(name).size(12),
            // Meter
            StereoMeter::new(meter_l, meter_r).size(24.0, 150.0),
            // Fader
            Fader::new(level, move |v| Message::BusLevelChanged(index, v)).size(40.0, 150.0),
            // dB value
            text(format!("{:.1} dB", level_to_db(level))).size(11),
        ]
        .spacing(8)
        .align_x(iced::Alignment::Center)
        .into()
    }

    fn master_strip(&self) -> Element<'_, Message> {
        let (meter_l, meter_r) = self.master_meter;

        column![
            text("MASTER").size(12),
            StereoMeter::new(meter_l, meter_r)
                .peaks(meter_l, meter_r)
                .size(32.0, 150.0),
            Fader::new(self.master_level, Message::MasterLevelChanged).size(48.0, 150.0),
            text(format!("{:.1} dB", level_to_db(self.master_level))).size(11),
            // Show gain reduction if active
            if self.master_gr.abs() > 0.1 {
                text(format!("GR {:.1}", self.master_gr)).size(10)
            } else {
                text("").size(10)
            },
        ]
        .spacing(8)
        .align_x(iced::Alignment::Center)
        .into()
    }
}

/// Convert linear level (0.0-1.0) to dB
fn level_to_db(level: f32) -> f32 {
    if level <= 0.0 {
        -60.0
    } else {
        20.0 * level.log10()
    }
}

/// Convert dB to meter display level (0.0-1.0)
fn db_to_meter(db: f32) -> f32 {
    // Map -60dB to 0.0, 0dB to 1.0
    let normalized = (db + 60.0) / 60.0;
    normalized.clamp(0.0, 1.0)
}
