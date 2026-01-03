//! ReelForge Dynamics Plugin
//!
//! Multi-mode dynamics processor:
//! - Compressor (VCA, Opto, FET modes)
//! - Limiter
//! - Gate/Expander

use nih_plug::prelude::*;
use std::sync::Arc;

use rf_dsp::dynamics::{StereoCompressor, CompressorType};
use rf_dsp::{Processor, ProcessorConfig, StereoProcessor};

use crate::params::{gain_param, time_ms_param, ratio_param, percent_param};

/// ReelForge Dynamics Plugin
pub struct ReelForgeDynamics {
    params: Arc<DynamicsParams>,
    compressor: StereoCompressor,
}

/// Dynamics Parameters
#[derive(Params)]
struct DynamicsParams {
    /// Compressor type
    #[id = "type"]
    comp_type: EnumParam<CompTypeParam>,

    /// Threshold
    #[id = "threshold"]
    threshold: FloatParam,

    /// Ratio
    #[id = "ratio"]
    ratio: FloatParam,

    /// Attack time
    #[id = "attack"]
    attack: FloatParam,

    /// Release time
    #[id = "release"]
    release: FloatParam,

    /// Knee
    #[id = "knee"]
    knee: FloatParam,

    /// Makeup gain
    #[id = "makeup"]
    makeup: FloatParam,

    /// Mix (dry/wet)
    #[id = "mix"]
    mix: FloatParam,

    /// Stereo link amount (0 = dual mono, 1 = fully linked)
    #[id = "link"]
    stereo_link: FloatParam,

    /// Input gain
    #[id = "input"]
    input_gain: FloatParam,

    /// Output gain
    #[id = "output"]
    output_gain: FloatParam,

    /// Auto makeup gain
    #[id = "auto_makeup"]
    auto_makeup: BoolParam,
}

/// Compressor type parameter
#[derive(Debug, Clone, Copy, PartialEq, Eq, Enum)]
enum CompTypeParam {
    #[name = "VCA"]
    Vca,
    #[name = "Opto"]
    Opto,
    #[name = "FET"]
    Fet,
}

impl Default for CompTypeParam {
    fn default() -> Self {
        Self::Vca
    }
}

impl From<CompTypeParam> for CompressorType {
    fn from(p: CompTypeParam) -> Self {
        match p {
            CompTypeParam::Vca => CompressorType::Vca,
            CompTypeParam::Opto => CompressorType::Opto,
            CompTypeParam::Fet => CompressorType::Fet,
        }
    }
}

impl Default for DynamicsParams {
    fn default() -> Self {
        Self {
            comp_type: EnumParam::new("Type", CompTypeParam::Vca),
            threshold: gain_param("Threshold", -18.0, -60.0, 0.0),
            ratio: ratio_param("Ratio", 4.0),
            attack: time_ms_param("Attack", 10.0, 0.1, 200.0),
            release: time_ms_param("Release", 100.0, 10.0, 2000.0),
            knee: FloatParam::new(
                "Knee",
                6.0,
                FloatRange::Linear { min: 0.0, max: 24.0 },
            )
            .with_unit(" dB")
            .with_value_to_string(formatters::v2s_f32_rounded(1)),
            makeup: gain_param("Makeup", 0.0, 0.0, 24.0),
            mix: percent_param("Mix", 100.0),
            stereo_link: percent_param("Link", 100.0),
            input_gain: gain_param("Input", 0.0, -24.0, 24.0),
            output_gain: gain_param("Output", 0.0, -24.0, 24.0),
            auto_makeup: BoolParam::new("Auto Makeup", false),
        }
    }
}

impl Default for ReelForgeDynamics {
    fn default() -> Self {
        Self {
            params: Arc::new(DynamicsParams::default()),
            compressor: StereoCompressor::new(48000.0),
        }
    }
}

impl Plugin for ReelForgeDynamics {
    const NAME: &'static str = "ReelForge Dynamics";
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
        self.compressor.set_sample_rate(buffer_config.sample_rate as f64);
        true
    }

    fn reset(&mut self) {
        self.compressor.reset();
    }

    fn process(
        &mut self,
        buffer: &mut Buffer,
        _aux: &mut AuxiliaryBuffers,
        _context: &mut impl ProcessContext<Self>,
    ) -> ProcessStatus {
        // Update compressor parameters using set_both for stereo
        let comp_type: CompressorType = self.params.comp_type.value().into();
        let threshold = self.params.threshold.value() as f64;
        let ratio = self.params.ratio.value() as f64;
        let attack = self.params.attack.value() as f64;
        let release = self.params.release.value() as f64;
        let knee = self.params.knee.value() as f64;
        let makeup = self.params.makeup.value() as f64;

        self.compressor.set_both(|c| {
            c.set_type(comp_type);
            c.set_threshold(threshold);
            c.set_ratio(ratio);
            c.set_attack(attack);
            c.set_release(release);
            c.set_knee(knee);
            c.set_makeup(makeup);
        });

        self.compressor.set_link(self.params.stereo_link.value() as f64 / 100.0);

        let input_gain = 10.0_f32.powf(self.params.input_gain.value() / 20.0);
        let output_gain = 10.0_f32.powf(self.params.output_gain.value() / 20.0);
        let mix = self.params.mix.value() / 100.0;

        // Process audio
        for channel_samples in buffer.iter_samples() {
            let mut samples: Vec<_> = channel_samples.into_iter().collect();

            if samples.len() >= 2 {
                let dry_l = *samples[0];
                let dry_r = *samples[1];

                let left = (dry_l * input_gain) as f64;
                let right = (dry_r * input_gain) as f64;

                let (wet_l, wet_r) = self.compressor.process_sample(left, right);

                // Mix dry/wet
                *samples[0] = (dry_l * (1.0 - mix) + wet_l as f32 * mix) * output_gain;
                *samples[1] = (dry_r * (1.0 - mix) + wet_r as f32 * mix) * output_gain;
            }
        }

        ProcessStatus::Normal
    }
}

impl ClapPlugin for ReelForgeDynamics {
    const CLAP_ID: &'static str = "audio.reelforge.dynamics";
    const CLAP_DESCRIPTION: Option<&'static str> = Some("Multi-mode dynamics processor");
    const CLAP_MANUAL_URL: Option<&'static str> = None;
    const CLAP_SUPPORT_URL: Option<&'static str> = None;
    const CLAP_FEATURES: &'static [ClapFeature] = &[
        ClapFeature::AudioEffect,
        ClapFeature::Stereo,
        ClapFeature::Compressor,
    ];
}

impl Vst3Plugin for ReelForgeDynamics {
    const VST3_CLASS_ID: [u8; 16] = *b"ReelForgeDyn_v01";
    const VST3_SUBCATEGORIES: &'static [Vst3SubCategory] = &[
        Vst3SubCategory::Fx,
        Vst3SubCategory::Dynamics,
        Vst3SubCategory::Stereo,
    ];
}
