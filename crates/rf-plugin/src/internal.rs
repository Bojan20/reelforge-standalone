//! Internal Plugin Wrappers
//!
//! Wraps rf-dsp processors as plugins with the standard PluginInstance interface.
//! This allows internal DSP to be used in the same insert chain as external plugins.

use std::path::Path;

use crate::scanner::{PluginCategory, PluginType};
use crate::{
    AudioBuffer, ParameterInfo, PluginError, PluginInfo, PluginInstance, PluginResult,
    ProcessContext,
};

/// Internal plugin wrapper
pub struct InternalPlugin {
    /// Plugin info
    info: PluginInfo,
    /// Is active
    active: bool,
    /// Sample rate
    sample_rate: f64,
    /// Parameters
    parameters: Vec<InternalParameter>,
    /// Processing function
    processor_type: InternalProcessorType,
}

/// Parameter state for internal plugin
struct InternalParameter {
    info: ParameterInfo,
    value: f64,
}

/// Type of internal processor
#[derive(Debug, Clone, Copy)]
enum InternalProcessorType {
    /// Parametric EQ (uses rf-dsp EQ)
    ParametricEq,
    /// Compressor
    Compressor,
    /// Limiter
    Limiter,
    /// Gate
    Gate,
    /// Delay
    Delay,
    /// Reverb
    Reverb,
    /// Gain utility
    Gain,
    /// Spectrum analyzer
    Spectrum,
    /// Pass-through (null processor)
    PassThrough,
}

impl InternalPlugin {
    /// Load internal plugin by ID
    pub fn load(path: &Path) -> PluginResult<Self> {
        // Path is actually the plugin ID for internal plugins
        let id = path.to_str().unwrap_or("unknown");

        let (name, processor_type, category, parameters) = match id {
            "rf.eq.parametric" => (
                "Parametric EQ",
                InternalProcessorType::ParametricEq,
                PluginCategory::Effect,
                Self::eq_parameters(),
            ),
            "rf.dynamics.compressor" => (
                "Compressor",
                InternalProcessorType::Compressor,
                PluginCategory::Effect,
                Self::compressor_parameters(),
            ),
            "rf.dynamics.limiter" => (
                "Limiter",
                InternalProcessorType::Limiter,
                PluginCategory::Effect,
                Self::limiter_parameters(),
            ),
            "rf.dynamics.gate" => (
                "Gate",
                InternalProcessorType::Gate,
                PluginCategory::Effect,
                Self::gate_parameters(),
            ),
            "rf.delay.stereo" => (
                "Stereo Delay",
                InternalProcessorType::Delay,
                PluginCategory::Effect,
                Self::delay_parameters(),
            ),
            "rf.reverb.algorithmic" => (
                "Algorithmic Reverb",
                InternalProcessorType::Reverb,
                PluginCategory::Effect,
                Self::reverb_parameters(),
            ),
            "rf.utility.gain" => (
                "Gain",
                InternalProcessorType::Gain,
                PluginCategory::Utility,
                Self::gain_parameters(),
            ),
            "rf.analysis.spectrum" => (
                "Spectrum Analyzer",
                InternalProcessorType::Spectrum,
                PluginCategory::Analyzer,
                vec![],
            ),
            _ => (
                "Unknown",
                InternalProcessorType::PassThrough,
                PluginCategory::Unknown,
                vec![],
            ),
        };

        let info = PluginInfo {
            id: id.to_string(),
            name: name.to_string(),
            vendor: String::from("FluxForge Studio"),
            version: String::from("1.0.0"),
            plugin_type: PluginType::Internal,
            category,
            path: path.to_path_buf(),
            audio_inputs: 2,
            audio_outputs: 2,
            has_midi_input: false,
            has_midi_output: false,
            has_editor: true,
            latency: 0,
            is_shell: false,
            sub_plugins: Vec::new(),
        };

        Ok(Self {
            info,
            active: false,
            sample_rate: 48000.0,
            parameters,
            processor_type,
        })
    }

    /// EQ parameters
    fn eq_parameters() -> Vec<InternalParameter> {
        vec![
            InternalParameter {
                info: ParameterInfo {
                    id: 0,
                    name: "Low Freq".into(),
                    unit: "Hz".into(),
                    min: 20.0,
                    max: 500.0,
                    default: 80.0,
                    normalized: 0.15,
                    steps: 0,
                    automatable: true,
                    read_only: false,
                },
                value: 0.15,
            },
            InternalParameter {
                info: ParameterInfo {
                    id: 1,
                    name: "Low Gain".into(),
                    unit: "dB".into(),
                    min: -18.0,
                    max: 18.0,
                    default: 0.0,
                    normalized: 0.5,
                    steps: 0,
                    automatable: true,
                    read_only: false,
                },
                value: 0.5,
            },
            InternalParameter {
                info: ParameterInfo {
                    id: 2,
                    name: "Mid Freq".into(),
                    unit: "Hz".into(),
                    min: 200.0,
                    max: 5000.0,
                    default: 1000.0,
                    normalized: 0.33,
                    steps: 0,
                    automatable: true,
                    read_only: false,
                },
                value: 0.33,
            },
            InternalParameter {
                info: ParameterInfo {
                    id: 3,
                    name: "Mid Gain".into(),
                    unit: "dB".into(),
                    min: -18.0,
                    max: 18.0,
                    default: 0.0,
                    normalized: 0.5,
                    steps: 0,
                    automatable: true,
                    read_only: false,
                },
                value: 0.5,
            },
            InternalParameter {
                info: ParameterInfo {
                    id: 4,
                    name: "High Freq".into(),
                    unit: "Hz".into(),
                    min: 2000.0,
                    max: 20000.0,
                    default: 8000.0,
                    normalized: 0.5,
                    steps: 0,
                    automatable: true,
                    read_only: false,
                },
                value: 0.5,
            },
            InternalParameter {
                info: ParameterInfo {
                    id: 5,
                    name: "High Gain".into(),
                    unit: "dB".into(),
                    min: -18.0,
                    max: 18.0,
                    default: 0.0,
                    normalized: 0.5,
                    steps: 0,
                    automatable: true,
                    read_only: false,
                },
                value: 0.5,
            },
        ]
    }

    /// Compressor parameters
    fn compressor_parameters() -> Vec<InternalParameter> {
        vec![
            InternalParameter {
                info: ParameterInfo {
                    id: 0,
                    name: "Threshold".into(),
                    unit: "dB".into(),
                    min: -60.0,
                    max: 0.0,
                    default: -20.0,
                    normalized: 0.67,
                    steps: 0,
                    automatable: true,
                    read_only: false,
                },
                value: 0.67,
            },
            InternalParameter {
                info: ParameterInfo {
                    id: 1,
                    name: "Ratio".into(),
                    unit: ":1".into(),
                    min: 1.0,
                    max: 20.0,
                    default: 4.0,
                    normalized: 0.16,
                    steps: 0,
                    automatable: true,
                    read_only: false,
                },
                value: 0.16,
            },
            InternalParameter {
                info: ParameterInfo {
                    id: 2,
                    name: "Attack".into(),
                    unit: "ms".into(),
                    min: 0.1,
                    max: 100.0,
                    default: 10.0,
                    normalized: 0.1,
                    steps: 0,
                    automatable: true,
                    read_only: false,
                },
                value: 0.1,
            },
            InternalParameter {
                info: ParameterInfo {
                    id: 3,
                    name: "Release".into(),
                    unit: "ms".into(),
                    min: 10.0,
                    max: 1000.0,
                    default: 100.0,
                    normalized: 0.1,
                    steps: 0,
                    automatable: true,
                    read_only: false,
                },
                value: 0.1,
            },
            InternalParameter {
                info: ParameterInfo {
                    id: 4,
                    name: "Makeup".into(),
                    unit: "dB".into(),
                    min: 0.0,
                    max: 24.0,
                    default: 0.0,
                    normalized: 0.0,
                    steps: 0,
                    automatable: true,
                    read_only: false,
                },
                value: 0.0,
            },
        ]
    }

    /// Limiter parameters
    fn limiter_parameters() -> Vec<InternalParameter> {
        vec![
            InternalParameter {
                info: ParameterInfo {
                    id: 0,
                    name: "Ceiling".into(),
                    unit: "dB".into(),
                    min: -12.0,
                    max: 0.0,
                    default: -0.3,
                    normalized: 0.975,
                    steps: 0,
                    automatable: true,
                    read_only: false,
                },
                value: 0.975,
            },
            InternalParameter {
                info: ParameterInfo {
                    id: 1,
                    name: "Release".into(),
                    unit: "ms".into(),
                    min: 10.0,
                    max: 500.0,
                    default: 100.0,
                    normalized: 0.18,
                    steps: 0,
                    automatable: true,
                    read_only: false,
                },
                value: 0.18,
            },
        ]
    }

    /// Gate parameters
    fn gate_parameters() -> Vec<InternalParameter> {
        vec![
            InternalParameter {
                info: ParameterInfo {
                    id: 0,
                    name: "Threshold".into(),
                    unit: "dB".into(),
                    min: -80.0,
                    max: 0.0,
                    default: -40.0,
                    normalized: 0.5,
                    steps: 0,
                    automatable: true,
                    read_only: false,
                },
                value: 0.5,
            },
            InternalParameter {
                info: ParameterInfo {
                    id: 1,
                    name: "Range".into(),
                    unit: "dB".into(),
                    min: -80.0,
                    max: 0.0,
                    default: -40.0,
                    normalized: 0.5,
                    steps: 0,
                    automatable: true,
                    read_only: false,
                },
                value: 0.5,
            },
            InternalParameter {
                info: ParameterInfo {
                    id: 2,
                    name: "Attack".into(),
                    unit: "ms".into(),
                    min: 0.01,
                    max: 50.0,
                    default: 1.0,
                    normalized: 0.02,
                    steps: 0,
                    automatable: true,
                    read_only: false,
                },
                value: 0.02,
            },
            InternalParameter {
                info: ParameterInfo {
                    id: 3,
                    name: "Release".into(),
                    unit: "ms".into(),
                    min: 10.0,
                    max: 500.0,
                    default: 100.0,
                    normalized: 0.18,
                    steps: 0,
                    automatable: true,
                    read_only: false,
                },
                value: 0.18,
            },
        ]
    }

    /// Delay parameters
    fn delay_parameters() -> Vec<InternalParameter> {
        vec![
            InternalParameter {
                info: ParameterInfo {
                    id: 0,
                    name: "Time L".into(),
                    unit: "ms".into(),
                    min: 1.0,
                    max: 2000.0,
                    default: 250.0,
                    normalized: 0.125,
                    steps: 0,
                    automatable: true,
                    read_only: false,
                },
                value: 0.125,
            },
            InternalParameter {
                info: ParameterInfo {
                    id: 1,
                    name: "Time R".into(),
                    unit: "ms".into(),
                    min: 1.0,
                    max: 2000.0,
                    default: 375.0,
                    normalized: 0.187,
                    steps: 0,
                    automatable: true,
                    read_only: false,
                },
                value: 0.187,
            },
            InternalParameter {
                info: ParameterInfo {
                    id: 2,
                    name: "Feedback".into(),
                    unit: "%".into(),
                    min: 0.0,
                    max: 100.0,
                    default: 30.0,
                    normalized: 0.3,
                    steps: 0,
                    automatable: true,
                    read_only: false,
                },
                value: 0.3,
            },
            InternalParameter {
                info: ParameterInfo {
                    id: 3,
                    name: "Mix".into(),
                    unit: "%".into(),
                    min: 0.0,
                    max: 100.0,
                    default: 25.0,
                    normalized: 0.25,
                    steps: 0,
                    automatable: true,
                    read_only: false,
                },
                value: 0.25,
            },
        ]
    }

    /// Reverb parameters
    fn reverb_parameters() -> Vec<InternalParameter> {
        vec![
            InternalParameter {
                info: ParameterInfo {
                    id: 0,
                    name: "Size".into(),
                    unit: "%".into(),
                    min: 0.0,
                    max: 100.0,
                    default: 50.0,
                    normalized: 0.5,
                    steps: 0,
                    automatable: true,
                    read_only: false,
                },
                value: 0.5,
            },
            InternalParameter {
                info: ParameterInfo {
                    id: 1,
                    name: "Decay".into(),
                    unit: "s".into(),
                    min: 0.1,
                    max: 10.0,
                    default: 2.0,
                    normalized: 0.19,
                    steps: 0,
                    automatable: true,
                    read_only: false,
                },
                value: 0.19,
            },
            InternalParameter {
                info: ParameterInfo {
                    id: 2,
                    name: "Damping".into(),
                    unit: "%".into(),
                    min: 0.0,
                    max: 100.0,
                    default: 50.0,
                    normalized: 0.5,
                    steps: 0,
                    automatable: true,
                    read_only: false,
                },
                value: 0.5,
            },
            InternalParameter {
                info: ParameterInfo {
                    id: 3,
                    name: "Pre-delay".into(),
                    unit: "ms".into(),
                    min: 0.0,
                    max: 200.0,
                    default: 20.0,
                    normalized: 0.1,
                    steps: 0,
                    automatable: true,
                    read_only: false,
                },
                value: 0.1,
            },
            InternalParameter {
                info: ParameterInfo {
                    id: 4,
                    name: "Mix".into(),
                    unit: "%".into(),
                    min: 0.0,
                    max: 100.0,
                    default: 30.0,
                    normalized: 0.3,
                    steps: 0,
                    automatable: true,
                    read_only: false,
                },
                value: 0.3,
            },
        ]
    }

    /// Gain parameters
    fn gain_parameters() -> Vec<InternalParameter> {
        vec![
            InternalParameter {
                info: ParameterInfo {
                    id: 0,
                    name: "Gain".into(),
                    unit: "dB".into(),
                    min: -24.0,
                    max: 24.0,
                    default: 0.0,
                    normalized: 0.5,
                    steps: 0,
                    automatable: true,
                    read_only: false,
                },
                value: 0.5,
            },
            InternalParameter {
                info: ParameterInfo {
                    id: 1,
                    name: "Pan".into(),
                    unit: "".into(),
                    min: -1.0,
                    max: 1.0,
                    default: 0.0,
                    normalized: 0.5,
                    steps: 0,
                    automatable: true,
                    read_only: false,
                },
                value: 0.5,
            },
            InternalParameter {
                info: ParameterInfo {
                    id: 2,
                    name: "Phase L".into(),
                    unit: "".into(),
                    min: 0.0,
                    max: 1.0,
                    default: 0.0,
                    normalized: 0.0,
                    steps: 2,
                    automatable: true,
                    read_only: false,
                },
                value: 0.0,
            },
            InternalParameter {
                info: ParameterInfo {
                    id: 3,
                    name: "Phase R".into(),
                    unit: "".into(),
                    min: 0.0,
                    max: 1.0,
                    default: 0.0,
                    normalized: 0.0,
                    steps: 2,
                    automatable: true,
                    read_only: false,
                },
                value: 0.0,
            },
        ]
    }
}

impl PluginInstance for InternalPlugin {
    fn info(&self) -> &PluginInfo {
        &self.info
    }

    fn initialize(&mut self, context: &ProcessContext) -> PluginResult<()> {
        self.sample_rate = context.sample_rate;
        log::debug!(
            "Initializing internal plugin {} at {}Hz",
            self.info.name,
            context.sample_rate
        );
        Ok(())
    }

    fn activate(&mut self) -> PluginResult<()> {
        self.active = true;
        log::debug!("Activated internal plugin: {}", self.info.name);
        Ok(())
    }

    fn deactivate(&mut self) -> PluginResult<()> {
        self.active = false;
        log::debug!("Deactivated internal plugin: {}", self.info.name);
        Ok(())
    }

    fn process(
        &mut self,
        input: &AudioBuffer,
        output: &mut AudioBuffer,
        _context: &ProcessContext,
    ) -> PluginResult<()> {
        if !self.active {
            return Err(PluginError::ProcessingError("Plugin not active".into()));
        }

        match self.processor_type {
            InternalProcessorType::Gain => {
                // Get gain in dB and convert to linear
                let gain_db = self
                    .parameters.first()
                    .map(|p| {
                        let normalized = p.value;
                        p.info.min + normalized * (p.info.max - p.info.min)
                    })
                    .unwrap_or(0.0);
                let gain_linear = 10.0_f64.powf(gain_db / 20.0) as f32;

                for ch in 0..output.channels.min(input.channels) {
                    if let (Some(inp), Some(out)) = (input.channel(ch), output.channel_mut(ch)) {
                        for (o, &i) in out.iter_mut().zip(inp.iter()) {
                            *o = i * gain_linear;
                        }
                    }
                }
            }
            InternalProcessorType::PassThrough | _ => {
                // Pass-through
                for ch in 0..output.channels.min(input.channels) {
                    if let (Some(inp), Some(out)) = (input.channel(ch), output.channel_mut(ch)) {
                        out.copy_from_slice(inp);
                    }
                }
            }
        }

        Ok(())
    }

    fn parameter_count(&self) -> usize {
        self.parameters.len()
    }

    fn parameter_info(&self, index: usize) -> Option<ParameterInfo> {
        self.parameters.get(index).map(|p| p.info.clone())
    }

    fn get_parameter(&self, id: u32) -> Option<f64> {
        self.parameters
            .iter()
            .find(|p| p.info.id == id)
            .map(|p| p.value)
    }

    fn set_parameter(&mut self, id: u32, value: f64) -> PluginResult<()> {
        if let Some(param) = self.parameters.iter_mut().find(|p| p.info.id == id) {
            param.value = value.clamp(0.0, 1.0);
            param.info.normalized = param.value;
            Ok(())
        } else {
            Err(PluginError::ParameterError(format!(
                "Parameter {} not found",
                id
            )))
        }
    }

    fn get_state(&self) -> PluginResult<Vec<u8>> {
        // Serialize parameter values as JSON
        let values: Vec<f64> = self.parameters.iter().map(|p| p.value).collect();
        serde_json::to_vec(&values).map_err(|e| {
            PluginError::IoError(std::io::Error::new(std::io::ErrorKind::InvalidData, e))
        })
    }

    fn set_state(&mut self, state: &[u8]) -> PluginResult<()> {
        let values: Vec<f64> = serde_json::from_slice(state).map_err(|e| {
            PluginError::IoError(std::io::Error::new(std::io::ErrorKind::InvalidData, e))
        })?;

        for (param, &value) in self.parameters.iter_mut().zip(values.iter()) {
            param.value = value.clamp(0.0, 1.0);
            param.info.normalized = param.value;
        }

        Ok(())
    }

    fn latency(&self) -> usize {
        0
    }

    fn has_editor(&self) -> bool {
        true
    }

    #[cfg(any(target_os = "macos", target_os = "windows", target_os = "linux"))]
    fn open_editor(&mut self, _parent: *mut std::ffi::c_void) -> PluginResult<()> {
        // Internal plugins use Flutter UI, not native editors
        Ok(())
    }

    fn close_editor(&mut self) -> PluginResult<()> {
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    #[test]
    fn test_internal_plugin_loading() {
        let path = PathBuf::from("rf.utility.gain");
        let result = InternalPlugin::load(&path);
        assert!(result.is_ok());

        let plugin = result.unwrap();
        assert_eq!(plugin.info.name, "Gain");
        assert_eq!(plugin.parameter_count(), 4);
    }

    #[test]
    fn test_gain_processing() {
        let path = PathBuf::from("rf.utility.gain");
        let mut plugin = InternalPlugin::load(&path).unwrap();

        let context = ProcessContext::default();
        plugin.initialize(&context).unwrap();
        plugin.activate().unwrap();

        let input = AudioBuffer::from_data(vec![vec![0.5; 512], vec![0.5; 512]]);
        let mut output = AudioBuffer::new(2, 512);

        plugin.process(&input, &mut output, &context).unwrap();

        // With 0 dB gain, output should equal input
        assert_eq!(output.channel(0).unwrap()[0], 0.5);
    }
}
