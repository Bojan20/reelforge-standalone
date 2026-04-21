# Agent 8: DSPSpecialist — Memory

## Accumulated Knowledge
- rf-dsp is the largest DSP crate (65 files) covering all processing algorithms
- SIMD dispatch: runtime detection → best available instruction set
- Biquad TDF-II is verified correct with all edge cases
- Denormal handling: CPU-level FTZ/DAZ flags + software flush (belt and suspenders)
- FFT spectrum: Hann window + RMS scaling + exponential smoothing (all verified)
- Convolution reverb uses uniform partitioned overlap-save method
- Pitch engine is polyphonic (Melodyne DNA level capability)

## Patterns
- DSP processor trait: Processor { process(&mut self, input: &[Sample], output: &mut [Sample]) }
- StereoProcessor: processes L/R channels
- ProcessorConfig: sample_rate, buffer_size, channel_count
- SIMD: #[cfg(target_feature = "avx2")] with fallback chain
- All BPM-dependent values recalculated on tempo change

## Decisions
- TDF-II for biquads (better numerical stability than DF-I)
- Blackman-Harris windowed sinc for SRC (reference quality)
- ONNX for ML model inference (portable, fast)
- Hann window for FFT (good frequency resolution / leakage tradeoff)

## Gotchas
- BPM was hardcoded 120.0 in 4 structs — now all use dynamic tempo (BUG #7 fixed)
- FabFilter delay slider had hardcoded BPM default — now uses _bpm value (BUG #23 fixed)
- Convolution reverb partition size is 256 samples (constant, not configurable)
- GPU compute (wgpu) in rf-realtime — device.poll() result must be handled
