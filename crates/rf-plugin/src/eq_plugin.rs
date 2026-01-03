//! ReelForge EQ Plugin
//!
//! 64-band parametric EQ with:
//! - Multiple filter types per band
//! - Dynamic EQ capability
//! - Linear phase option
//! - Analyzer integration

use nih_plug::prelude::*;
use std::sync::Arc;

use rf_dsp::eq::{ParametricEq, EqFilterType};
use rf_dsp::{Processor, ProcessorConfig, StereoProcessor};

use crate::params::{freq_param, gain_param, q_param};

/// Number of EQ bands exposed in plugin
const NUM_BANDS: usize = 8;

/// ReelForge EQ Plugin
pub struct ReelForgeEQ {
    params: Arc<EQParams>,
    eq: ParametricEq,
}

/// EQ Parameters
#[derive(Params)]
struct EQParams {
    /// Output gain
    #[id = "output"]
    output_gain: FloatParam,

    /// Band parameters (nested)
    #[nested(array, group = "Band")]
    bands: [BandParams; NUM_BANDS],
}

/// Single band parameters
#[derive(Params)]
struct BandParams {
    /// Band enabled
    #[id = "enabled"]
    enabled: BoolParam,

    /// Filter type
    #[id = "type"]
    filter_type: EnumParam<FilterTypeParam>,

    /// Frequency
    #[id = "freq"]
    frequency: FloatParam,

    /// Gain (for peaking/shelf)
    #[id = "gain"]
    gain: FloatParam,

    /// Q factor
    #[id = "q"]
    q: FloatParam,
}

/// Filter type enum for plugin parameter
#[derive(Debug, Clone, Copy, PartialEq, Eq, Enum)]
enum FilterTypeParam {
    #[name = "Bell"]
    Bell,
    #[name = "Low Shelf"]
    LowShelf,
    #[name = "High Shelf"]
    HighShelf,
    #[name = "Low Cut"]
    LowCut,
    #[name = "High Cut"]
    HighCut,
    #[name = "Notch"]
    Notch,
    #[name = "Band Pass"]
    BandPass,
}

impl Default for FilterTypeParam {
    fn default() -> Self {
        Self::Bell
    }
}

impl From<FilterTypeParam> for EqFilterType {
    fn from(p: FilterTypeParam) -> Self {
        match p {
            FilterTypeParam::Bell => EqFilterType::Bell,
            FilterTypeParam::LowShelf => EqFilterType::LowShelf,
            FilterTypeParam::HighShelf => EqFilterType::HighShelf,
            FilterTypeParam::LowCut => EqFilterType::LowCut,
            FilterTypeParam::HighCut => EqFilterType::HighCut,
            FilterTypeParam::Notch => EqFilterType::Notch,
            FilterTypeParam::BandPass => EqFilterType::Bandpass,
        }
    }
}

impl Default for EQParams {
    fn default() -> Self {
        // Default frequencies for 8 bands
        let default_freqs = [80.0, 160.0, 320.0, 640.0, 1280.0, 2560.0, 5120.0, 10240.0];

        Self {
            output_gain: gain_param("Output", 0.0, -24.0, 24.0),
            bands: std::array::from_fn(|i| BandParams {
                enabled: BoolParam::new("Enabled", i < 4), // First 4 bands enabled
                filter_type: EnumParam::new("Type", FilterTypeParam::Bell),
                frequency: freq_param("Frequency", default_freqs[i]),
                gain: gain_param("Gain", 0.0, -24.0, 24.0),
                q: q_param("Q", 1.0),
            }),
        }
    }
}

impl Default for ReelForgeEQ {
    fn default() -> Self {
        Self {
            params: Arc::new(EQParams::default()),
            eq: ParametricEq::new(48000.0),
        }
    }
}

impl Plugin for ReelForgeEQ {
    const NAME: &'static str = "ReelForge EQ";
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
        self.eq.set_sample_rate(buffer_config.sample_rate as f64);
        self.update_eq_from_params();
        true
    }

    fn reset(&mut self) {
        self.eq.reset();
    }

    fn process(
        &mut self,
        buffer: &mut Buffer,
        _aux: &mut AuxiliaryBuffers,
        _context: &mut impl ProcessContext<Self>,
    ) -> ProcessStatus {
        // Update EQ parameters
        self.update_eq_from_params();

        // Process audio
        let output_gain = 10.0_f32.powf(self.params.output_gain.value() / 20.0);

        for channel_samples in buffer.iter_samples() {
            let mut samples: Vec<_> = channel_samples.into_iter().collect();

            if samples.len() >= 2 {
                let left = *samples[0] as f64;
                let right = *samples[1] as f64;

                let (out_l, out_r) = self.eq.process_sample(left, right);

                *samples[0] = (out_l as f32) * output_gain;
                *samples[1] = (out_r as f32) * output_gain;
            }
        }

        ProcessStatus::Normal
    }
}

impl ReelForgeEQ {
    fn update_eq_from_params(&mut self) {
        for (i, band_params) in self.params.bands.iter().enumerate() {
            let enabled = band_params.enabled.value();
            self.eq.enable_band(i, enabled);

            if enabled {
                let filter_type: EqFilterType = band_params.filter_type.value().into();
                self.eq.set_band(
                    i,
                    band_params.frequency.value() as f64,
                    band_params.gain.value() as f64,
                    band_params.q.value() as f64,
                    filter_type,
                );
            }
        }
    }
}

impl ClapPlugin for ReelForgeEQ {
    const CLAP_ID: &'static str = "audio.reelforge.eq";
    const CLAP_DESCRIPTION: Option<&'static str> = Some("Professional 64-band parametric EQ");
    const CLAP_MANUAL_URL: Option<&'static str> = None;
    const CLAP_SUPPORT_URL: Option<&'static str> = None;
    const CLAP_FEATURES: &'static [ClapFeature] = &[
        ClapFeature::AudioEffect,
        ClapFeature::Stereo,
        ClapFeature::Equalizer,
    ];
}

impl Vst3Plugin for ReelForgeEQ {
    const VST3_CLASS_ID: [u8; 16] = *b"ReelForgeEQ_v001";
    const VST3_SUBCATEGORIES: &'static [Vst3SubCategory] = &[
        Vst3SubCategory::Fx,
        Vst3SubCategory::Eq,
        Vst3SubCategory::Stereo,
    ];
}
