//! ReelForge Standalone - Professional Audio Editor
//!
//! Main entry point for the ReelForge application.

use std::time::{Duration, Instant};

use iced::widget::{column, container, horizontal_space, row, scrollable, text, vertical_space, Column, Row};
use iced::{Element, Length, Subscription, Task, Theme};

use rf_core::{BufferSize, SampleRate};
use rf_engine::{ChannelId, RealtimeEngine};
use rf_gui::widgets::{
    EqBandConfig, EqEditor, EqMessage, Fader, FilterType, InsertRack, InsertRackMessage,
    InsertSlot, Knob, KnobStyle, PresetBrowser, PresetBrowserMessage, PresetEntry, SendSlot,
    SpectrumAnalyzer, StereoMeter, TransportBar, TransportMessage, TransportState,
    WaveformDisplay, WaveformMessage, WaveformPoint,
};

fn main() -> iced::Result {
    env_logger::init();
    log::info!("Starting ReelForge...");

    iced::application("ReelForge Standalone", ReelForge::update, ReelForge::view)
        .subscription(ReelForge::subscription)
        .theme(|_| Theme::Dark)
        .window_size((1400.0, 900.0))
        .antialiasing(true)
        .run_with(|| (ReelForge::new(), Task::none()))
}

/// View mode for the application
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
enum ViewMode {
    #[default]
    Mixer,
    Eq,
    Editor,
}

/// Main application state
struct ReelForge {
    // Audio engine
    engine: Option<RealtimeEngine>,

    // View state
    view_mode: ViewMode,

    // Mixer state
    bus_meters: [(f32, f32); 6],
    bus_gr: [f32; 6],
    master_meter: (f32, f32),
    master_gr: f32,
    lufs_short: f32,
    lufs_integrated: f32,
    true_peak: f32,
    bus_levels: [f32; 6],
    master_level: f32,

    // EQ state
    eq_bands: Vec<EqBandConfig>,
    eq_response: Vec<(f32, f32)>,
    selected_eq_band: Option<usize>,

    // Spectrum analyzer
    spectrum_data: Vec<f32>,
    spectrum_peaks: Vec<f32>,

    // Waveform
    waveform_data: Vec<WaveformPoint>,
    playhead_position: f32,
    waveform_selection: Option<(f32, f32)>,
    waveform_zoom: f32,

    // Transport
    transport_state: TransportState,
    position_samples: u64,

    // Inserts/Sends (per selected channel)
    selected_channel: usize,
    channel_inserts: Vec<InsertSlot>,
    channel_sends: Vec<SendSlot>,

    // Presets
    presets: Vec<PresetEntry>,
    current_preset: String,

    // Timing
    last_meter_update: Instant,
}

#[derive(Debug, Clone)]
enum Message {
    // View
    SetViewMode(ViewMode),

    // Mixer
    BusLevelChanged(usize, f32),
    MasterLevelChanged(f32),
    SelectChannel(usize),

    // EQ
    EqMessage(EqMessage),

    // Waveform
    WaveformMessage(WaveformMessage),

    // Transport
    TransportMessage(TransportMessage),

    // Insert/Send
    InsertRackMessage(InsertRackMessage),

    // Presets
    PresetMessage(PresetBrowserMessage),

    // Updates
    Tick,
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

        // Initialize EQ with some default bands
        let eq_bands = vec![
            EqBandConfig {
                enabled: true,
                filter_type: FilterType::HighCut,
                frequency: 80.0,
                gain_db: 0.0,
                q: 0.7,
            },
            EqBandConfig {
                enabled: true,
                filter_type: FilterType::LowShelf,
                frequency: 120.0,
                gain_db: 2.0,
                q: 0.7,
            },
            EqBandConfig {
                enabled: true,
                filter_type: FilterType::Bell,
                frequency: 400.0,
                gain_db: -3.0,
                q: 1.5,
            },
            EqBandConfig {
                enabled: true,
                filter_type: FilterType::Bell,
                frequency: 2500.0,
                gain_db: 4.0,
                q: 1.2,
            },
            EqBandConfig {
                enabled: true,
                filter_type: FilterType::HighShelf,
                frequency: 8000.0,
                gain_db: 1.5,
                q: 0.7,
            },
        ];

        // Generate demo EQ response curve
        let eq_response = Self::calculate_eq_response(&eq_bands);

        // Demo spectrum data
        let spectrum_data: Vec<f32> = (0..512)
            .map(|i| {
                let freq = (i as f32 / 512.0) * 20000.0;
                let base = (-freq / 5000.0).exp() * 0.8;
                let variation = ((i as f32 * 0.1).sin() * 0.2).abs();
                (base + variation).min(1.0)
            })
            .collect();

        let spectrum_peaks = spectrum_data.iter().map(|v| v * 1.1).collect();

        // Demo waveform data
        let waveform_data: Vec<WaveformPoint> = (0..800)
            .map(|i| {
                let t = i as f32 / 800.0;
                let envelope = (t * 3.14159 * 2.0).sin().abs() * 0.7 + 0.1;
                let noise = ((i as f32 * 0.3).sin() * 0.3).abs();
                WaveformPoint {
                    min: -(envelope + noise * 0.5),
                    max: envelope + noise * 0.5,
                    rms: envelope * 0.7,
                }
            })
            .collect();

        // Demo inserts
        let channel_inserts = vec![
            InsertSlot::with_plugin("Pro-Q 4"),
            InsertSlot::with_plugin("LA-2A"),
            InsertSlot::empty(),
            InsertSlot::empty(),
            InsertSlot::empty(),
            InsertSlot::empty(),
            InsertSlot::empty(),
            InsertSlot::empty(),
        ];

        // Demo sends
        let channel_sends = vec![
            SendSlot::new("Reverb"),
            SendSlot::new("Delay"),
            SendSlot {
                name: "Chorus".into(),
                level: 0.3,
                enabled: false,
                pre_fader: false,
            },
            SendSlot::default(),
        ];

        // Demo presets
        let presets = vec![
            PresetEntry::new("1", "Warm Vocal").category("Vocal").factory(),
            PresetEntry::new("2", "Bright Mix").category("Master").factory(),
            PresetEntry::new("3", "Bass Boost").category("Bass").factory().favorite(),
            PresetEntry::new("4", "Clean Dialog").category("Dialog"),
            PresetEntry::new("5", "Aggressive Drum").category("Drums"),
        ];

        Self {
            engine,
            view_mode: ViewMode::Mixer,
            bus_meters: [(0.0, 0.0); 6],
            bus_gr: [0.0; 6],
            master_meter: (0.0, 0.0),
            master_gr: 0.0,
            lufs_short: -23.0,
            lufs_integrated: -24.0,
            true_peak: -1.0,
            bus_levels: [0.75; 6],
            master_level: 0.75,
            eq_bands,
            eq_response,
            selected_eq_band: Some(2),
            spectrum_data,
            spectrum_peaks,
            waveform_data,
            playhead_position: 0.35,
            waveform_selection: None,
            waveform_zoom: 1.0,
            transport_state: TransportState::Stopped,
            position_samples: 0,
            selected_channel: 0,
            channel_inserts,
            channel_sends,
            presets,
            current_preset: "Warm Vocal".into(),
            last_meter_update: Instant::now(),
        }
    }

    fn calculate_eq_response(bands: &[EqBandConfig]) -> Vec<(f32, f32)> {
        // Simple approximation for demo - real implementation would use rf-dsp
        let num_points = 200;
        let log_min = 20.0_f32.ln();
        let log_max = 20000.0_f32.ln();

        (0..num_points)
            .map(|i| {
                let t = i as f32 / (num_points - 1) as f32;
                let freq = (log_min + t * (log_max - log_min)).exp();

                let mut total_db = 0.0;
                for band in bands {
                    if band.enabled {
                        // Simplified frequency response approximation
                        let ratio = (freq / band.frequency).ln();
                        let bandwidth = 1.0 / band.q;
                        let response = (-ratio * ratio / (bandwidth * bandwidth)).exp();

                        match band.filter_type {
                            FilterType::Bell => {
                                total_db += band.gain_db * response;
                            }
                            FilterType::LowShelf => {
                                if freq < band.frequency {
                                    total_db += band.gain_db * (1.0 - response * 0.5);
                                }
                            }
                            FilterType::HighShelf => {
                                if freq > band.frequency {
                                    total_db += band.gain_db * (1.0 - response * 0.5);
                                }
                            }
                            FilterType::HighCut => {
                                if freq < band.frequency {
                                    total_db -= 24.0 * (1.0 - (freq / band.frequency).powf(2.0));
                                }
                            }
                            FilterType::LowCut => {
                                if freq > band.frequency {
                                    total_db -= 24.0 * (1.0 - (band.frequency / freq).powf(2.0));
                                }
                            }
                            _ => {}
                        }
                    }
                }

                (freq, total_db.clamp(-24.0, 24.0))
            })
            .collect()
    }

    fn subscription(&self) -> Subscription<Message> {
        iced::time::every(Duration::from_millis(16)).map(|_| Message::Tick)
    }

    fn update(&mut self, message: Message) -> Task<Message> {
        match message {
            Message::SetViewMode(mode) => {
                self.view_mode = mode;
            }

            Message::BusLevelChanged(index, value) => {
                if index < 6 {
                    self.bus_levels[index] = value;
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

            Message::SelectChannel(index) => {
                self.selected_channel = index;
            }

            Message::EqMessage(eq_msg) => match eq_msg {
                EqMessage::FrequencyChanged(idx, freq) => {
                    if let Some(band) = self.eq_bands.get_mut(idx) {
                        band.frequency = freq;
                        self.eq_response = Self::calculate_eq_response(&self.eq_bands);
                    }
                }
                EqMessage::GainChanged(idx, gain) => {
                    if let Some(band) = self.eq_bands.get_mut(idx) {
                        band.gain_db = gain;
                        self.eq_response = Self::calculate_eq_response(&self.eq_bands);
                    }
                }
                EqMessage::QChanged(idx, q) => {
                    if let Some(band) = self.eq_bands.get_mut(idx) {
                        band.q = q;
                        self.eq_response = Self::calculate_eq_response(&self.eq_bands);
                    }
                }
                EqMessage::BandSelected(idx) => {
                    self.selected_eq_band = idx;
                }
                EqMessage::BandAdded(freq, gain) => {
                    self.eq_bands.push(EqBandConfig {
                        enabled: true,
                        filter_type: FilterType::Bell,
                        frequency: freq,
                        gain_db: gain,
                        q: 1.0,
                    });
                    self.selected_eq_band = Some(self.eq_bands.len() - 1);
                    self.eq_response = Self::calculate_eq_response(&self.eq_bands);
                }
                _ => {}
            },

            Message::WaveformMessage(wf_msg) => match wf_msg {
                WaveformMessage::SeekTo(pos) => {
                    self.playhead_position = pos;
                }
                WaveformMessage::SelectionChanged(start, end) => {
                    self.waveform_selection = Some((start, end));
                }
                WaveformMessage::ZoomChanged(zoom) => {
                    self.waveform_zoom = zoom;
                }
            },

            Message::TransportMessage(tr_msg) => match tr_msg {
                TransportMessage::Play => {
                    self.transport_state = TransportState::Playing;
                }
                TransportMessage::Pause => {
                    self.transport_state = TransportState::Paused;
                }
                TransportMessage::Stop => {
                    self.transport_state = TransportState::Stopped;
                    self.playhead_position = 0.0;
                    self.position_samples = 0;
                }
                TransportMessage::Record => {
                    self.transport_state = TransportState::Recording;
                }
                _ => {}
            },

            Message::InsertRackMessage(ir_msg) => match ir_msg {
                InsertRackMessage::InsertClicked(idx) => {
                    log::info!("Insert slot {} clicked", idx);
                }
                InsertRackMessage::InsertBypassToggled(idx, bypassed) => {
                    if let Some(insert) = self.channel_inserts.get_mut(idx) {
                        insert.bypassed = bypassed;
                    }
                }
                InsertRackMessage::SendLevelChanged(idx, level) => {
                    if let Some(send) = self.channel_sends.get_mut(idx) {
                        send.level = level;
                    }
                }
                InsertRackMessage::SendToggled(idx, enabled) => {
                    if let Some(send) = self.channel_sends.get_mut(idx) {
                        send.enabled = enabled;
                    }
                }
                _ => {}
            },

            Message::PresetMessage(pr_msg) => match pr_msg {
                PresetBrowserMessage::PresetSelected(id) => {
                    if let Some(preset) = self.presets.iter().find(|p| p.id == id) {
                        self.current_preset = preset.name.clone();
                        log::info!("Loaded preset: {}", preset.name);
                    }
                }
                PresetBrowserMessage::PreviousPreset => {
                    log::info!("Previous preset");
                }
                PresetBrowserMessage::NextPreset => {
                    log::info!("Next preset");
                }
                PresetBrowserMessage::ToggleFavorite(id) => {
                    if let Some(preset) = self.presets.iter_mut().find(|p| p.id == id) {
                        preset.is_favorite = !preset.is_favorite;
                    }
                }
                _ => {}
            },

            Message::Tick => {
                // Update playhead during playback
                if self.transport_state == TransportState::Playing {
                    self.position_samples += 800; // ~16ms at 48kHz
                    self.playhead_position = (self.playhead_position + 0.001).min(1.0);
                    if self.playhead_position >= 1.0 {
                        self.playhead_position = 0.0;
                    }
                }

                // Read meters from audio engine
                if let Some(ref engine) = self.engine {
                    let handle = engine.mixer_handle();

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
                        self.bus_meters[i] = (db_to_meter(l as f32), db_to_meter(r as f32));
                        self.bus_gr[i] = handle.channel_gain_reduction(*channel_id) as f32;
                    }

                    let (ml, mr) = handle.master_peak();
                    self.master_meter = (db_to_meter(ml as f32), db_to_meter(mr as f32));
                    self.master_gr = handle.master_gain_reduction() as f32;

                    let (lufs_s, lufs_i) = handle.lufs();
                    self.lufs_short = lufs_s as f32;
                    self.lufs_integrated = lufs_i as f32;
                    self.true_peak = handle.true_peak() as f32;

                    self.last_meter_update = Instant::now();
                }
            }
        }

        Task::none()
    }

    fn view(&self) -> Element<'_, Message> {
        let header = self.view_header();
        let transport = TransportBar::new(self.transport_state, self.position_samples, Message::TransportMessage)
            .tempo(120.0)
            .sample_rate(48000);

        let content = match self.view_mode {
            ViewMode::Mixer => self.view_mixer(),
            ViewMode::Eq => self.view_eq(),
            ViewMode::Editor => self.view_editor(),
        };

        let main_layout = column![
            header,
            container(transport).padding(8).width(Length::Fill),
            content,
        ]
        .spacing(0);

        container(main_layout)
            .width(Length::Fill)
            .height(Length::Fill)
            .into()
    }

    fn view_header(&self) -> Element<'_, Message> {
        let status = if self.engine.is_some() {
            text("● Audio").size(11)
        } else {
            text("○ No Audio").size(11)
        };

        let view_buttons = row![
            self.view_button("MIXER", ViewMode::Mixer),
            self.view_button("EQ", ViewMode::Eq),
            self.view_button("EDITOR", ViewMode::Editor),
        ]
        .spacing(4);

        let preset = PresetBrowser::new(&self.presets, &self.current_preset, Message::PresetMessage)
            .compact(true)
            .size(200.0, 32.0);

        container(
            row![
                text("ReelForge").size(20),
                horizontal_space(),
                view_buttons,
                horizontal_space(),
                preset,
                container(status).padding(iced::Padding::from([0, 16])),
            ]
            .spacing(16)
            .align_y(iced::Alignment::Center),
        )
        .padding(12)
        .width(Length::Fill)
        .style(|_| container::Style {
            background: Some(iced::Background::Color(iced::Color::from_rgb(0.07, 0.07, 0.09))),
            ..Default::default()
        })
        .into()
    }

    fn view_button<'a>(&'a self, label: &'a str, mode: ViewMode) -> Element<'a, Message> {
        let is_active = self.view_mode == mode;
        let btn = container(text(label).size(12))
            .padding(iced::Padding::from([6, 12]))
            .style(move |_| {
                if is_active {
                    container::Style {
                        background: Some(iced::Background::Color(iced::Color::from_rgb(0.29, 0.62, 1.0))),
                        border: iced::Border {
                            radius: 4.0.into(),
                            ..Default::default()
                        },
                        ..Default::default()
                    }
                } else {
                    container::Style {
                        background: Some(iced::Background::Color(iced::Color::from_rgb(0.15, 0.15, 0.18))),
                        border: iced::Border {
                            radius: 4.0.into(),
                            ..Default::default()
                        },
                        ..Default::default()
                    }
                }
            });

        iced::widget::mouse_area(btn)
            .on_press(Message::SetViewMode(mode))
            .into()
    }

    fn view_mixer(&self) -> Element<'_, Message> {
        let bus_names = ["UI", "REELS", "FX", "VO", "MUSIC", "AMBIENT"];

        let bus_strips: Vec<Element<Message>> = (0..6)
            .map(|i| {
                let name = bus_names[i];
                let level = self.bus_levels[i];
                let (meter_l, meter_r) = self.bus_meters[i];
                let is_selected = self.selected_channel == i;

                self.channel_strip(name, i, level, meter_l, meter_r, is_selected)
            })
            .collect();

        let master_strip = self.master_strip();

        let loudness = column![
            text("LOUDNESS").size(10),
            vertical_space().height(4),
            text(format!("{:.1} LUFS", self.lufs_short)).size(14),
            text(format!("∫ {:.1}", self.lufs_integrated)).size(11),
            vertical_space().height(8),
            text("TRUE PEAK").size(10),
            text(format!("{:.1} dB", self.true_peak)).size(14),
        ]
        .align_x(iced::Alignment::Center)
        .spacing(2);

        let insert_rack = InsertRack::new(
            &self.channel_inserts,
            &self.channel_sends,
            Message::InsertRackMessage,
        )
        .width(160.0);

        let spectrum = SpectrumAnalyzer::new(&self.spectrum_data)
            .peaks(&self.spectrum_peaks)
            .size(300.0, 150.0)
            .db_range(-90.0, 0.0);

        let right_panel = column![
            container(spectrum).padding(8),
            vertical_space().height(8),
            container(insert_rack).padding(8),
        ]
        .align_x(iced::Alignment::Center);

        let mixer = row![
            Row::with_children(bus_strips).spacing(6),
            container(text("│").size(20)).padding(8),
            master_strip,
            container(loudness).padding(16),
            horizontal_space(),
            right_panel,
        ]
        .spacing(8)
        .padding(16);

        scrollable(mixer).into()
    }

    fn view_eq(&self) -> Element<'_, Message> {
        let eq_editor = EqEditor::new(&self.eq_bands, &self.eq_response, Message::EqMessage)
            .selected_band(self.selected_eq_band)
            .size(900.0, 350.0)
            .db_range(-24.0, 24.0);

        let spectrum = SpectrumAnalyzer::new(&self.spectrum_data)
            .peaks(&self.spectrum_peaks)
            .size(900.0, 120.0)
            .db_range(-90.0, 0.0);

        let band_controls = if let Some(idx) = self.selected_eq_band {
            if let Some(band) = self.eq_bands.get(idx) {
                self.eq_band_controls(idx, band)
            } else {
                column![text("No band selected")].into()
            }
        } else {
            column![text("Click to add a band")].into()
        };

        let main_content = column![
            container(eq_editor).padding(16),
            container(spectrum).padding(iced::Padding::from([0, 16])),
            container(band_controls).padding(16),
        ]
        .spacing(8);

        scrollable(main_content).into()
    }

    fn eq_band_controls(&self, idx: usize, band: &EqBandConfig) -> Element<'_, Message> {
        let freq_knob = column![
            text("FREQ").size(10),
            Knob::new(band.frequency / 20000.0, move |v| {
                Message::EqMessage(EqMessage::FrequencyChanged(idx, v * 20000.0))
            })
            .size(56.0),
            text(format!("{:.0} Hz", band.frequency)).size(11),
        ]
        .align_x(iced::Alignment::Center)
        .spacing(4);

        let gain_knob = column![
            text("GAIN").size(10),
            Knob::new((band.gain_db + 24.0) / 48.0, move |v| {
                Message::EqMessage(EqMessage::GainChanged(idx, v * 48.0 - 24.0))
            })
            .style(KnobStyle::Bipolar)
            .size(56.0),
            text(format!("{:+.1} dB", band.gain_db)).size(11),
        ]
        .align_x(iced::Alignment::Center)
        .spacing(4);

        let q_knob = column![
            text("Q").size(10),
            Knob::new(band.q / 10.0, move |v| {
                Message::EqMessage(EqMessage::QChanged(idx, v * 10.0 + 0.1))
            })
            .size(56.0),
            text(format!("{:.2}", band.q)).size(11),
        ]
        .align_x(iced::Alignment::Center)
        .spacing(4);

        row![
            text(format!("Band {}", idx + 1)).size(14),
            horizontal_space().width(32),
            freq_knob,
            gain_knob,
            q_knob,
            horizontal_space(),
            text(format!("{}", band.filter_type.name())).size(12),
        ]
        .spacing(24)
        .align_y(iced::Alignment::Center)
        .into()
    }

    fn view_editor(&self) -> Element<'_, Message> {
        let waveform = WaveformDisplay::new(&self.waveform_data)
            .playhead(self.playhead_position)
            .zoom(self.waveform_zoom)
            .size(1000.0, 200.0)
            .on_message(Message::WaveformMessage);

        let waveform_with_selection = if let Some((start, end)) = self.waveform_selection {
            column![
                container(waveform).padding(16),
                text(format!("Selection: {:.2} - {:.2}", start, end)).size(11),
            ]
        } else {
            column![container(waveform).padding(16),]
        };

        let spectrum = SpectrumAnalyzer::new(&self.spectrum_data)
            .peaks(&self.spectrum_peaks)
            .size(1000.0, 150.0)
            .db_range(-90.0, 0.0);

        let content = column![
            waveform_with_selection,
            vertical_space().height(8),
            container(spectrum).padding(iced::Padding::from([0, 16])),
        ]
        .spacing(8);

        scrollable(content).into()
    }

    fn channel_strip(
        &self,
        name: &'static str,
        index: usize,
        level: f32,
        meter_l: f32,
        meter_r: f32,
        is_selected: bool,
    ) -> Element<'_, Message> {
        let strip = column![
            text(name).size(11),
            StereoMeter::new(meter_l, meter_r).size(20.0, 120.0),
            Fader::new(level, move |v| Message::BusLevelChanged(index, v)).size(36.0, 120.0),
            text(format!("{:.1}", level_to_db(level))).size(10),
        ]
        .spacing(6)
        .align_x(iced::Alignment::Center);

        let wrapper = container(strip).padding(6).style(move |_| {
            if is_selected {
                container::Style {
                    background: Some(iced::Background::Color(iced::Color::from_rgba(0.29, 0.62, 1.0, 0.15))),
                    border: iced::Border {
                        color: iced::Color::from_rgb(0.29, 0.62, 1.0),
                        width: 1.0,
                        radius: 4.0.into(),
                    },
                    ..Default::default()
                }
            } else {
                container::Style {
                    background: Some(iced::Background::Color(iced::Color::from_rgb(0.1, 0.1, 0.12))),
                    border: iced::Border {
                        radius: 4.0.into(),
                        ..Default::default()
                    },
                    ..Default::default()
                }
            }
        });

        iced::widget::mouse_area(wrapper)
            .on_press(Message::SelectChannel(index))
            .into()
    }

    fn master_strip(&self) -> Element<'_, Message> {
        let (meter_l, meter_r) = self.master_meter;

        column![
            text("MASTER").size(11),
            StereoMeter::new(meter_l, meter_r)
                .peaks(meter_l, meter_r)
                .size(28.0, 120.0),
            Fader::new(self.master_level, Message::MasterLevelChanged).size(44.0, 120.0),
            text(format!("{:.1}", level_to_db(self.master_level))).size(10),
            if self.master_gr.abs() > 0.1 {
                text(format!("GR {:.1}", self.master_gr)).size(9)
            } else {
                text("").size(9)
            },
        ]
        .spacing(6)
        .align_x(iced::Alignment::Center)
        .into()
    }
}

fn level_to_db(level: f32) -> f32 {
    if level <= 0.0 {
        -60.0
    } else {
        20.0 * level.log10()
    }
}

fn db_to_meter(db: f32) -> f32 {
    let normalized = (db + 60.0) / 60.0;
    normalized.clamp(0.0, 1.0)
}
