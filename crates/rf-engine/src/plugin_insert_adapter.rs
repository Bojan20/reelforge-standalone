//! `PluginInsertProcessor` — wraps a `rf_plugin::PluginInstance` so the
//! engine's insert chain can host external VST3 / AU / CLAP / LV2
//! plugins through the same `InsertProcessor` trait it uses for
//! internal `rf-dsp` wrappers.
//!
//! # Why an adapter
//!
//! Front 4's `LoadExternal` step pointed at a scanner-found plugin, but
//! the executor logged-and-skipped it because the engine's insert chain
//! only accepts `Box<dyn InsertProcessor>`, while `rf-plugin` returns
//! `Box<dyn PluginInstance>`. This adapter bridges the two:
//!
//! - **Audio path:** `process_stereo(&mut [f64], &mut [f64])` →
//!   pre-allocated f32 `AudioBuffer` → `instance.process(...)` →
//!   copy back. All buffers are pre-allocated in `new()`; no per-block
//!   allocation on the audio thread.
//! - **Parameters:** internal DSP wrappers expose raw values
//!   (Cutoff in Hz, Threshold in dB); `PluginInstance` exposes
//!   normalised 0..1 values keyed by parameter `id`. The adapter
//!   normalises on `set_param` and denormalises on `get_param` using
//!   each parameter's `min`/`max` range. So the rest of the engine
//!   (and the `chain_apply_ffi` `SetParameter` step) can stay
//!   unit-agnostic.
//! - **Latency:** read once at construction (after initialize); the
//!   engine PDC manager can be told.
//!
//! # Audio-thread invariants
//!
//! - `process_stereo` does **not** allocate.
//! - `set_param` does not block — it forwards to `instance.set_parameter`.
//!   Whether that is itself wait-free depends on the plugin format
//!   (real VST3/CLAP plugins are designed to be RT-safe).
//! - Errors during `process` are logged at `warn` level and the block
//!   passes-through silent; the alternative — bubbling a panic —
//!   would crash the entire DAW for one bad plugin.

use std::ffi::c_void;

use rf_core::MidiBuffer;
use rf_plugin::{
    AudioBuffer, ParameterInfo, PluginInstance, ProcessContext as PluginCtx,
};

use rf_dsp::delay_compensation::LatencySamples;

use crate::control_room::Sample;
use crate::insert_chain::InsertProcessor;

/// Adapter wrapping an external plugin instance.
pub struct PluginInsertProcessor {
    /// Underlying plugin instance (initialised + activated).
    instance: Box<dyn PluginInstance>,
    /// Cached parameter info, indexed by plugin parameter index (not id).
    /// Used to map index→id and to denormalise/normalise values.
    parameters: Vec<ParameterInfo>,
    /// Pre-allocated input buffer (stereo, sized to max block).
    input_buf: AudioBuffer,
    /// Pre-allocated output buffer.
    output_buf: AudioBuffer,
    /// Pre-allocated empty MIDI in (effects don't consume MIDI).
    midi_in: MidiBuffer,
    /// Pre-allocated MIDI out scratch (effects don't emit MIDI).
    midi_out: MidiBuffer,
    /// Process context for `instance.process`. Updated on
    /// `set_sample_rate`.
    ctx: PluginCtx,
    /// Display name (cached so `name()` returns &str without allocating).
    cached_name: String,
    /// Cached latency in samples (read once after activate).
    latency_samples: usize,
    /// Maximum block size we promised the plugin in `initialize`.
    max_block_size: usize,
}

// SAFETY: PluginInstance is `?Sized + Send + Sync` from the trait
// definition (or its impls upstream). The adapter holds it in a Box
// and never aliases the inner state. Sound across threads.
unsafe impl Send for PluginInsertProcessor {}
unsafe impl Sync for PluginInsertProcessor {}

impl PluginInsertProcessor {
    /// Wrap a freshly-loaded `PluginInstance` for use in the insert chain.
    ///
    /// The instance must already be initialised (which is what
    /// `rf_plugin::load_plugin` does). This call activates it and
    /// caches metadata for the audio path.
    pub fn new(
        mut instance: Box<dyn PluginInstance>,
        sample_rate: f64,
        max_block_size: usize,
    ) -> Result<Self, String> {
        let ctx = PluginCtx {
            sample_rate,
            max_block_size,
            ..Default::default()
        };
        // Re-initialise so plugin matches our actual sample rate / block.
        // Plugins that reject re-init at this stage will return an Err
        // and we surface it.
        instance
            .initialize(&ctx)
            .map_err(|e| format!("plugin initialize failed: {:?}", e))?;
        instance
            .activate()
            .map_err(|e| format!("plugin activate failed: {:?}", e))?;

        // Cache parameters
        let count = instance.parameter_count();
        let mut parameters = Vec::with_capacity(count);
        for i in 0..count {
            if let Some(info) = instance.parameter_info(i) {
                parameters.push(info);
            } else {
                // Fill with placeholder so indexing stays consistent.
                parameters.push(ParameterInfo {
                    id: i as u32,
                    name: format!("param_{}", i),
                    unit: String::new(),
                    min: 0.0,
                    max: 1.0,
                    default: 0.0,
                    normalized: 0.0,
                    steps: 0,
                    automatable: false,
                    read_only: false,
                });
            }
        }

        let cached_name = instance.info().name.clone();
        let latency_samples = instance.latency();

        Ok(Self {
            instance,
            parameters,
            input_buf: AudioBuffer::new(2, max_block_size),
            output_buf: AudioBuffer::new(2, max_block_size),
            midi_in: MidiBuffer::new(),
            midi_out: MidiBuffer::new(),
            ctx,
            cached_name,
            latency_samples,
            max_block_size,
        })
    }

    /// Number of parameters.
    pub fn parameter_count(&self) -> usize {
        self.parameters.len()
    }

    /// Borrow cached parameter metadata (units, ranges).
    pub fn parameter_info(&self, index: usize) -> Option<&ParameterInfo> {
        self.parameters.get(index)
    }

    /// Underlying plugin info — useful for diagnostics.
    pub fn plugin_name(&self) -> &str {
        &self.cached_name
    }
}

impl Drop for PluginInsertProcessor {
    fn drop(&mut self) {
        // Deactivate before drop so the plugin can release its
        // processing resources cleanly.
        let _ = self.instance.deactivate();
    }
}

impl InsertProcessor for PluginInsertProcessor {
    fn name(&self) -> &str {
        &self.cached_name
    }

    fn process_stereo(&mut self, left: &mut [Sample], right: &mut [Sample]) {
        let len = left.len().min(right.len()).min(self.max_block_size);
        if len == 0 {
            return;
        }

        // f64 → f32 into pre-allocated input buffer.
        if let Some(in_l) = self.input_buf.channel_mut(0) {
            for i in 0..len {
                in_l[i] = left[i] as f32;
            }
        }
        if let Some(in_r) = self.input_buf.channel_mut(1) {
            for i in 0..len {
                in_r[i] = right[i] as f32;
            }
        }
        self.input_buf.samples = len;
        self.output_buf.samples = len;

        // Tell the plugin the actual block we're handing it.
        let mut block_ctx = self.ctx.clone();
        block_ctx.max_block_size = len;

        match self.instance.process(
            &self.input_buf,
            &mut self.output_buf,
            &self.midi_in,
            &mut self.midi_out,
            &block_ctx,
        ) {
            Ok(()) => {
                // f32 → f64 back into the caller's buffers.
                if let Some(out_l) = self.output_buf.channel(0) {
                    for i in 0..len.min(out_l.len()) {
                        left[i] = out_l[i] as f64;
                    }
                }
                if let Some(out_r) = self.output_buf.channel(1) {
                    for i in 0..len.min(out_r.len()) {
                        right[i] = out_r[i] as f64;
                    }
                }
            }
            Err(e) => {
                // Pass-through on error so a misbehaving plugin doesn't
                // silence the track. Log at warn (UI, not audio thread —
                // log crate handles its own throttling).
                log::warn!(
                    "[plugin-insert] '{}' process failed: {:?} (passing through)",
                    self.cached_name,
                    e
                );
            }
        }
    }

    fn latency(&self) -> LatencySamples {
        self.latency_samples
    }

    fn reset(&mut self) {
        // Plugins don't expose a generic reset; deactivate+activate is
        // the cleanest equivalent.
        let _ = self.instance.deactivate();
        let _ = self.instance.activate();
    }

    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.ctx.sample_rate = sample_rate;
        // Re-init so the plugin recomputes any rate-dependent state.
        // Failure here is logged but not propagated — caller can inspect
        // via probe APIs if needed.
        if let Err(e) = self.instance.initialize(&self.ctx) {
            log::warn!(
                "[plugin-insert] '{}' set_sample_rate re-init failed: {:?}",
                self.cached_name,
                e
            );
        }
        // Re-activate after init.
        let _ = self.instance.activate();
        // Refresh latency — some plugins change latency at new SR.
        self.latency_samples = self.instance.latency();
    }

    fn num_params(&self) -> usize {
        self.parameters.len()
    }

    fn get_param(&self, index: usize) -> f64 {
        let info = match self.parameters.get(index) {
            Some(i) => i,
            None => return 0.0,
        };
        let normalized = self.instance.get_parameter(info.id).unwrap_or(info.normalized);
        denormalize(normalized, info)
    }

    fn set_param(&mut self, index: usize, value: f64) {
        let info = match self.parameters.get(index) {
            Some(i) => i.clone(),
            None => return,
        };
        let normalized = normalize(value, &info);
        // Fire-and-forget: errors are non-fatal, plugin keeps prior value.
        let _ = self.instance.set_parameter(info.id, normalized);
    }

    fn param_name(&self, index: usize) -> &str {
        self.parameters
            .get(index)
            .map(|p| p.name.as_str())
            .unwrap_or("")
    }
}

/// Map a *raw* value (e.g. 80 Hz, -22 dB) into the plugin's normalised
/// 0..1 domain using the parameter's `min`/`max`. If `min == max`
/// (degenerate range), returns 0.0 to avoid NaN.
fn normalize(value: f64, info: &ParameterInfo) -> f64 {
    if info.max <= info.min {
        return 0.0;
    }
    let range = info.max - info.min;
    ((value - info.min) / range).clamp(0.0, 1.0)
}

/// Map a normalised 0..1 value back into the parameter's raw domain.
fn denormalize(normalized: f64, info: &ParameterInfo) -> f64 {
    info.min + normalized.clamp(0.0, 1.0) * (info.max - info.min)
}

/// Try to instantiate a scanned plugin by id and wrap it as an insert
/// processor in one call. The convenience wrapper most callers want.
///
/// Returns `Err(String)` describing the failure (plugin not found,
/// load failed, init failed, activate failed).
pub fn load_external_plugin_as_insert(
    plugin_id: &str,
    sample_rate: f64,
    max_block_size: usize,
) -> Result<Box<dyn InsertProcessor>, String> {
    let instance = rf_plugin::load_plugin(plugin_id)
        .map_err(|e| format!("load_plugin('{}') failed: {:?}", plugin_id, e))?;
    let adapter = PluginInsertProcessor::new(instance, sample_rate, max_block_size)?;
    Ok(Box::new(adapter))
}

// Silence the unused-import lint when the `c_void` import is not
// reachable through process(). Keeps the intent visible at the top of
// the file and lets clippy know we considered it.
#[allow(dead_code)]
const _C_VOID_USED: Option<*mut c_void> = None;

// ─── Tests ────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use rf_plugin::{
        AudioBuffer as PluginAudioBuffer, ParameterInfo as PInfo, PluginError, PluginInstance,
        PluginResult,
    };

    /// Trivial test plugin that doubles its input on the left and halves
    /// it on the right. One parameter: "Gain" (0..2 range).
    struct TestPlug {
        info: rf_plugin::scanner::PluginInfo,
        gain_normalized: f64,
        latency: usize,
        active: bool,
        sample_rate: f64,
        params: Vec<PInfo>,
    }

    impl TestPlug {
        fn new() -> Self {
            let params = vec![PInfo {
                id: 7, // deliberately != index to test id↔index mapping
                name: "Gain".into(),
                unit: "x".into(),
                min: 0.0,
                max: 2.0,
                default: 1.0,
                normalized: 0.5,
                steps: 0,
                automatable: true,
                read_only: false,
            }];
            Self {
                info: rf_plugin::scanner::PluginInfo {
                    id: "test.plug".into(),
                    name: "TestPlug".into(),
                    vendor: "test".into(),
                    version: "1.0.0".into(),
                    plugin_type: rf_plugin::scanner::PluginType::Internal,
                    category: rf_plugin::scanner::PluginCategory::Effect,
                    path: "<test>".into(),
                    audio_inputs: 2,
                    audio_outputs: 2,
                    has_midi_input: false,
                    has_midi_output: false,
                    has_editor: false,
                    latency: 0,
                    is_shell: false,
                    sub_plugins: vec![],
                },
                gain_normalized: 0.5,
                latency: 16,
                active: false,
                sample_rate: 48000.0,
                params,
            }
        }
    }

    impl PluginInstance for TestPlug {
        fn info(&self) -> &rf_plugin::scanner::PluginInfo {
            &self.info
        }

        fn initialize(&mut self, ctx: &PluginCtx) -> PluginResult<()> {
            self.sample_rate = ctx.sample_rate;
            Ok(())
        }

        fn activate(&mut self) -> PluginResult<()> {
            self.active = true;
            Ok(())
        }

        fn deactivate(&mut self) -> PluginResult<()> {
            self.active = false;
            Ok(())
        }

        fn process(
            &mut self,
            input: &PluginAudioBuffer,
            output: &mut PluginAudioBuffer,
            _midi_in: &MidiBuffer,
            _midi_out: &mut MidiBuffer,
            _ctx: &PluginCtx,
        ) -> PluginResult<()> {
            if !self.active {
                return Err(PluginError::ProcessingError("not active".into()));
            }
            let gain = (self.params[0].min
                + self.gain_normalized * (self.params[0].max - self.params[0].min)) as f32;
            for ch in 0..2 {
                if let (Some(src), Some(dst)) = (input.channel(ch), output.channel_mut(ch)) {
                    let len = src.len().min(dst.len());
                    let scale = if ch == 0 { gain * 2.0 } else { gain * 0.5 };
                    for i in 0..len {
                        dst[i] = src[i] * scale;
                    }
                }
            }
            Ok(())
        }

        fn parameter_count(&self) -> usize {
            self.params.len()
        }

        fn parameter_info(&self, index: usize) -> Option<PInfo> {
            self.params.get(index).cloned()
        }

        fn get_parameter(&self, id: u32) -> Option<f64> {
            self.params
                .iter()
                .find(|p| p.id == id)
                .map(|_| self.gain_normalized)
        }

        fn set_parameter(&mut self, id: u32, value: f64) -> PluginResult<()> {
            if self.params.iter().any(|p| p.id == id) {
                self.gain_normalized = value.clamp(0.0, 1.0);
                Ok(())
            } else {
                Err(PluginError::ParameterError(format!("no param {}", id)))
            }
        }

        fn get_state(&self) -> PluginResult<Vec<u8>> {
            Ok(vec![])
        }
        fn set_state(&mut self, _: &[u8]) -> PluginResult<()> {
            Ok(())
        }
        fn latency(&self) -> usize {
            self.latency
        }
        fn has_editor(&self) -> bool {
            false
        }
        fn open_editor(&mut self, _: *mut c_void) -> PluginResult<()> {
            Err(PluginError::ProcessingError("no editor".into()))
        }
        fn close_editor(&mut self) -> PluginResult<()> {
            Ok(())
        }
    }

    fn make_adapter() -> PluginInsertProcessor {
        PluginInsertProcessor::new(Box::new(TestPlug::new()), 48000.0, 64).unwrap()
    }

    #[test]
    fn name_is_cached() {
        let a = make_adapter();
        assert_eq!(a.name(), "TestPlug");
    }

    #[test]
    fn latency_propagates() {
        let a = make_adapter();
        assert_eq!(a.latency(), 16);
    }

    #[test]
    fn process_doubles_left_halves_right() {
        let mut a = make_adapter();
        // gain default 1.0 (normalized 0.5 → mapped to 0.0 + 0.5*2.0 = 1.0)
        let mut left = vec![0.5_f64; 32];
        let mut right = vec![0.5_f64; 32];
        a.process_stereo(&mut left, &mut right);
        // left scaled by gain*2 = 2.0 → 1.0
        assert!(
            (left[0] - 1.0).abs() < 1e-5,
            "left[0] = {}, expected 1.0",
            left[0]
        );
        // right scaled by gain*0.5 = 0.5 → 0.25
        assert!(
            (right[0] - 0.25).abs() < 1e-5,
            "right[0] = {}, expected 0.25",
            right[0]
        );
    }

    #[test]
    fn set_param_normalises_raw_value() {
        let mut a = make_adapter();
        // Range is 0..2 — set raw 1.0 should give normalised 0.5
        a.set_param(0, 1.0);
        // get_param should denormalise back to ~1.0
        let got = a.get_param(0);
        assert!((got - 1.0).abs() < 1e-5, "got {}, expected ~1.0", got);
    }

    #[test]
    fn set_param_clamps_out_of_range() {
        let mut a = make_adapter();
        a.set_param(0, 5.0); // way above 2.0 max
        let got = a.get_param(0);
        // Clamped to max
        assert!((got - 2.0).abs() < 1e-5);
    }

    #[test]
    fn set_param_below_min_clamps_to_zero() {
        let mut a = make_adapter();
        a.set_param(0, -1.0);
        let got = a.get_param(0);
        assert!(got >= 0.0 && got < 1e-5);
    }

    #[test]
    fn param_name_returned() {
        let a = make_adapter();
        assert_eq!(a.param_name(0), "Gain");
    }

    #[test]
    fn out_of_range_param_index_is_safe() {
        let mut a = make_adapter();
        // No panic, just no-op
        a.set_param(99, 1.0);
        assert_eq!(a.get_param(99), 0.0);
        assert_eq!(a.param_name(99), "");
    }

    #[test]
    fn process_zero_length_is_safe() {
        let mut a = make_adapter();
        let mut left: Vec<f64> = vec![];
        let mut right: Vec<f64> = vec![];
        a.process_stereo(&mut left, &mut right);
        // No crash, no allocation.
    }

    #[test]
    fn process_block_larger_than_max_truncates() {
        let mut a = make_adapter();
        // Adapter was built with max_block_size=64
        let mut left = vec![0.5_f64; 128];
        let mut right = vec![0.5_f64; 128];
        a.process_stereo(&mut left, &mut right);
        // First 64 samples processed (left doubled to 1.0)
        assert!((left[0] - 1.0).abs() < 1e-5);
        assert!((left[63] - 1.0).abs() < 1e-5);
        // Beyond the max, samples are untouched (still 0.5)
        assert!((left[64] - 0.5).abs() < 1e-5);
    }

    #[test]
    fn reset_does_not_panic() {
        let mut a = make_adapter();
        a.reset();
        // After reset, plugin should still be active and processable
        let mut left = vec![0.5_f64; 8];
        let mut right = vec![0.5_f64; 8];
        a.process_stereo(&mut left, &mut right);
    }

    #[test]
    fn set_sample_rate_updates_context() {
        let mut a = make_adapter();
        a.set_sample_rate(96000.0);
        assert_eq!(a.ctx.sample_rate, 96000.0);
    }

    #[test]
    fn parameter_count_matches() {
        let a = make_adapter();
        assert_eq!(a.num_params(), 1);
        assert_eq!(a.parameter_count(), 1);
    }

    #[test]
    fn parameter_info_exposed() {
        let a = make_adapter();
        let info = a.parameter_info(0).unwrap();
        assert_eq!(info.name, "Gain");
        assert_eq!(info.id, 7);
    }

    #[test]
    fn normalize_handles_degenerate_range() {
        let info = PInfo {
            id: 0,
            name: "x".into(),
            unit: "".into(),
            min: 1.0,
            max: 1.0, // zero range
            default: 1.0,
            normalized: 0.0,
            steps: 0,
            automatable: false,
            read_only: false,
        };
        assert_eq!(normalize(0.5, &info), 0.0); // doesn't NaN
    }

    #[test]
    fn denormalize_inverse_of_normalize() {
        let info = PInfo {
            id: 0,
            name: "x".into(),
            unit: "".into(),
            min: -20.0,
            max: 20.0,
            default: 0.0,
            normalized: 0.5,
            steps: 0,
            automatable: false,
            read_only: false,
        };
        for raw in [-20.0_f64, -10.0, 0.0, 10.0, 20.0] {
            let n = normalize(raw, &info);
            let d = denormalize(n, &info);
            assert!((d - raw).abs() < 1e-9, "raw {} → norm {} → de {}", raw, n, d);
        }
    }
}
