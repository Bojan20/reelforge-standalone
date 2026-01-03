//! ReelForge Channel Plugin
//!
//! Complete channel strip with:
//! - Input gain/trim
//! - High-pass filter
//! - 4-band EQ
//! - Compressor
//! - Output gain/pan

use nih_plug::prelude::*;
use std::sync::Arc;

use rf_dsp::channel::ChannelStrip;
use rf_dsp::{Processor, ProcessorConfig, StereoProcessor};

use crate::params::{freq_param, gain_param, q_param, time_ms_param, ratio_param, pan_param};

/// ReelForge Channel Plugin
pub struct ReelForgeChannel {
    params: Arc<ChannelParams>,
    strip: ChannelStrip,
}

/// Channel Parameters
#[derive(Params)]
struct ChannelParams {
    // Input section
    #[id = "input_gain"]
    input_gain: FloatParam,

    // High-pass filter
    #[id = "hpf_enabled"]
    hpf_enabled: BoolParam,

    #[id = "hpf_freq"]
    hpf_frequency: FloatParam,

    // EQ section (4 bands)
    #[nested(group = "EQ Low")]
    eq_low: EQBandParams,

    #[nested(group = "EQ Low-Mid")]
    eq_low_mid: EQBandParams,

    #[nested(group = "EQ High-Mid")]
    eq_high_mid: EQBandParams,

    #[nested(group = "EQ High")]
    eq_high: EQBandParams,

    // Compressor section
    #[id = "comp_enabled"]
    comp_enabled: BoolParam,

    #[id = "comp_threshold"]
    comp_threshold: FloatParam,

    #[id = "comp_ratio"]
    comp_ratio: FloatParam,

    #[id = "comp_attack"]
    comp_attack: FloatParam,

    #[id = "comp_release"]
    comp_release: FloatParam,

    #[id = "comp_makeup"]
    comp_makeup: FloatParam,

    // Output section
    #[id = "output_gain"]
    output_gain: FloatParam,

    #[id = "pan"]
    pan: FloatParam,

    #[id = "width"]
    width: FloatParam,

    #[id = "mute"]
    mute: BoolParam,
}

/// EQ Band Parameters
#[derive(Params)]
struct EQBandParams {
    #[id = "enabled"]
    enabled: BoolParam,

    #[id = "freq"]
    frequency: FloatParam,

    #[id = "gain"]
    gain: FloatParam,

    #[id = "q"]
    q: FloatParam,
}

impl EQBandParams {
    fn new(default_freq: f32, is_shelf: bool) -> Self {
        Self {
            enabled: BoolParam::new("Enabled", true),
            frequency: freq_param("Frequency", default_freq),
            gain: gain_param("Gain", 0.0, -18.0, 18.0),
            q: if is_shelf {
                FloatParam::new("Q", 0.7, FloatRange::Linear { min: 0.3, max: 2.0 })
                    .with_value_to_string(formatters::v2s_f32_rounded(2))
            } else {
                q_param("Q", 1.0)
            },
        }
    }
}

impl Default for ChannelParams {
    fn default() -> Self {
        Self {
            // Input
            input_gain: gain_param("Input Gain", 0.0, -24.0, 24.0),

            // HPF
            hpf_enabled: BoolParam::new("HPF Enabled", false),
            hpf_frequency: freq_param("HPF Frequency", 80.0),

            // EQ bands
            eq_low: EQBandParams::new(100.0, true),      // Low shelf
            eq_low_mid: EQBandParams::new(400.0, false), // Bell
            eq_high_mid: EQBandParams::new(2500.0, false), // Bell
            eq_high: EQBandParams::new(8000.0, true),    // High shelf

            // Compressor
            comp_enabled: BoolParam::new("Comp Enabled", false),
            comp_threshold: gain_param("Comp Threshold", -18.0, -60.0, 0.0),
            comp_ratio: ratio_param("Comp Ratio", 4.0),
            comp_attack: time_ms_param("Comp Attack", 10.0, 0.1, 200.0),
            comp_release: time_ms_param("Comp Release", 100.0, 10.0, 2000.0),
            comp_makeup: gain_param("Comp Makeup", 0.0, 0.0, 24.0),

            // Output
            output_gain: gain_param("Output Gain", 0.0, -60.0, 12.0),
            pan: pan_param("Pan"),
            width: FloatParam::new("Width", 100.0, FloatRange::Linear { min: 0.0, max: 200.0 })
                .with_unit(" %")
                .with_value_to_string(formatters::v2s_f32_rounded(0)),
            mute: BoolParam::new("Mute", false),
        }
    }
}

impl Default for ReelForgeChannel {
    fn default() -> Self {
        Self {
            params: Arc::new(ChannelParams::default()),
            strip: ChannelStrip::new(48000.0),
        }
    }
}

impl Plugin for ReelForgeChannel {
    const NAME: &'static str = "ReelForge Channel";
    const VENDOR: &'static str = "ReelForge";
    const URL: &'static str = "https://reelforge.audio";
    const EMAIL: &'static str = "support@reelforge.audio";
    const VERSION: &'static str = env!("CARGO_PKG_VERSION");

    const AUDIO_IO_LAYOUTS: &'static [AudioIOLayout] = &[
        AudioIOLayout {
            main_input_channels: NonZeroU32::new(2),
            main_output_channels: NonZeroU32::new(2),
            ..AudioIOLayout::const_default()
        },
    ];

    const MIDI_INPUT: MidiConfig = MidiConfig::None;
    const MIDI_OUTPUT: MidiConfig = MidiConfig::None;

    const SAMPLE_ACCURATE_AUTOMATION: bool = true;

    type SysExMessage = ();
    type BackgroundTask = ();

    fn params(&self) -> Arc<dyn Params> {
        self.params.clone()
    }

    fn initialize(
        &mut self,
        _audio_io_layout: &AudioIOLayout,
        buffer_config: &BufferConfig,
        _context: &mut impl InitContext<Self>,
    ) -> bool {
        self.strip.set_sample_rate(buffer_config.sample_rate as f64);
        true
    }

    fn reset(&mut self) {
        self.strip.reset();
    }

    fn process(
        &mut self,
        buffer: &mut Buffer,
        _aux: &mut AuxiliaryBuffers,
        _context: &mut impl ProcessContext<Self>,
    ) -> ProcessStatus {
        // Update strip parameters
        self.update_strip_from_params();

        // Check mute
        if self.params.mute.value() {
            for sample in buffer.iter_samples() {
                for s in sample {
                    *s = 0.0;
                }
            }
            return ProcessStatus::Normal;
        }

        // Process audio
        for channel_samples in buffer.iter_samples() {
            let mut samples: Vec<_> = channel_samples.into_iter().collect();

            if samples.len() >= 2 {
                let left = *samples[0] as f64;
                let right = *samples[1] as f64;

                let (out_l, out_r) = self.strip.process_sample(left, right);

                *samples[0] = out_l as f32;
                *samples[1] = out_r as f32;
            }
        }

        ProcessStatus::Normal
    }
}

impl ReelForgeChannel {
    fn update_strip_from_params(&mut self) {
        // Input (phase_invert not supported - skipped)
        self.strip.set_input_gain_db(self.params.input_gain.value() as f64);

        // HPF
        self.strip.set_hpf_enabled(self.params.hpf_enabled.value());
        self.strip.set_hpf_freq(self.params.hpf_frequency.value() as f64);

        // EQ
        self.strip.set_eq_enabled(true);
        if self.params.eq_low.enabled.value() {
            self.strip.set_eq_low(
                self.params.eq_low.frequency.value() as f64,
                self.params.eq_low.gain.value() as f64,
            );
        }
        if self.params.eq_low_mid.enabled.value() {
            self.strip.set_eq_low_mid(
                self.params.eq_low_mid.frequency.value() as f64,
                self.params.eq_low_mid.gain.value() as f64,
                self.params.eq_low_mid.q.value() as f64,
            );
        }
        if self.params.eq_high_mid.enabled.value() {
            self.strip.set_eq_high_mid(
                self.params.eq_high_mid.frequency.value() as f64,
                self.params.eq_high_mid.gain.value() as f64,
                self.params.eq_high_mid.q.value() as f64,
            );
        }
        if self.params.eq_high.enabled.value() {
            self.strip.set_eq_high(
                self.params.eq_high.frequency.value() as f64,
                self.params.eq_high.gain.value() as f64,
            );
        }

        // Compressor
        self.strip.set_comp_enabled(self.params.comp_enabled.value());
        self.strip.set_comp_threshold(self.params.comp_threshold.value() as f64);
        self.strip.set_comp_ratio(self.params.comp_ratio.value() as f64);
        self.strip.set_comp_attack(self.params.comp_attack.value() as f64);
        self.strip.set_comp_release(self.params.comp_release.value() as f64);
        self.strip.set_comp_makeup(self.params.comp_makeup.value() as f64);

        // Output
        self.strip.set_output_gain_db(self.params.output_gain.value() as f64);
        self.strip.set_pan(self.params.pan.value() as f64 / 100.0);
        self.strip.set_width(self.params.width.value() as f64 / 100.0);
    }
}

impl ClapPlugin for ReelForgeChannel {
    const CLAP_ID: &'static str = "audio.reelforge.channel";
    const CLAP_DESCRIPTION: Option<&'static str> = Some("Complete channel strip processor");
    const CLAP_MANUAL_URL: Option<&'static str> = None;
    const CLAP_SUPPORT_URL: Option<&'static str> = None;
    const CLAP_FEATURES: &'static [ClapFeature] = &[
        ClapFeature::AudioEffect,
        ClapFeature::Stereo,
        ClapFeature::Mixing,
    ];
}

impl Vst3Plugin for ReelForgeChannel {
    const VST3_CLASS_ID: [u8; 16] = *b"ReelForgeChn_v01";
    const VST3_SUBCATEGORIES: &'static [Vst3SubCategory] = &[
        Vst3SubCategory::Fx,
        Vst3SubCategory::Tools,
        Vst3SubCategory::Stereo,
    ];
}
