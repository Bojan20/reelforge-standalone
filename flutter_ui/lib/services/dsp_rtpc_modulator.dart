/// DSP RTPC Modulator Service (P11.1.2)
///
/// Provides utility functions for RTPC → DSP parameter modulation:
/// - Parameter range validation
/// - Curve-based modulation with multiple shapes
/// - FFI sync helpers
/// - Scale conversion utilities (Hz to normalized, dB to linear, etc.)
///
/// This service complements RtpcSystemProvider by providing additional
/// modulation utilities and scale conversions specific to DSP parameters.
library;

import 'dart:math' as math;
import '../models/middleware_models.dart';
import '../providers/dsp_chain_provider.dart';
import '../providers/subsystems/rtpc_system_provider.dart';
import '../src/rust/native_ffi.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// DSP PARAMETER RANGES
// ═══════════════════════════════════════════════════════════════════════════════

/// Parameter range with unit information
class DspParameterRange {
  final double min;
  final double max;
  final double defaultValue;
  final String unit;
  final DspParameterScale scale;

  const DspParameterRange({
    required this.min,
    required this.max,
    required this.defaultValue,
    required this.unit,
    this.scale = DspParameterScale.linear,
  });

  /// Clamp value to range
  double clamp(double value) => value.clamp(min, max);

  /// Normalize value to 0-1 range
  double normalize(double value) {
    if (max == min) return 0.5;
    return ((value - min) / (max - min)).clamp(0.0, 1.0);
  }

  /// Denormalize from 0-1 to actual range
  double denormalize(double normalized) {
    return min + (normalized.clamp(0.0, 1.0) * (max - min));
  }

  /// Apply scale transformation for display
  double toDisplay(double value) {
    switch (scale) {
      case DspParameterScale.linear:
        return value;
      case DspParameterScale.logarithmic:
        if (value <= 0) return min;
        return math.log(value) / math.ln10;
      case DspParameterScale.exponential:
        return math.pow(10, value).toDouble();
      case DspParameterScale.decibel:
        if (value <= 0) return -120.0;
        return 20.0 * math.log(value) / math.ln10;
    }
  }

  /// Apply inverse scale transformation from display
  double fromDisplay(double displayValue) {
    switch (scale) {
      case DspParameterScale.linear:
        return displayValue;
      case DspParameterScale.logarithmic:
        return math.pow(10, displayValue).toDouble();
      case DspParameterScale.exponential:
        return math.log(displayValue) / math.ln10;
      case DspParameterScale.decibel:
        return math.pow(10, displayValue / 20.0).toDouble();
    }
  }
}

/// Scale type for parameter display
enum DspParameterScale {
  linear,
  logarithmic,  // For frequency parameters (Hz)
  exponential,  // For time parameters (ms)
  decibel,      // For gain/level parameters (dB)
}

// ═══════════════════════════════════════════════════════════════════════════════
// DSP RTPC MODULATOR SERVICE
// ═══════════════════════════════════════════════════════════════════════════════

/// Service for RTPC → DSP parameter modulation utilities
class DspRtpcModulator {
  DspRtpcModulator._();

  /// Singleton instance
  static final DspRtpcModulator instance = DspRtpcModulator._();

  /// Parameter ranges by target type
  static final Map<RtpcTargetParameter, DspParameterRange> _ranges = {
    // Filter parameters
    RtpcTargetParameter.filterCutoff: const DspParameterRange(
      min: 20.0, max: 20000.0, defaultValue: 1000.0, unit: 'Hz',
      scale: DspParameterScale.logarithmic,
    ),
    RtpcTargetParameter.filterResonance: const DspParameterRange(
      min: 0.1, max: 20.0, defaultValue: 1.0, unit: 'Q',
    ),
    RtpcTargetParameter.lowPassFilter: const DspParameterRange(
      min: 20.0, max: 20000.0, defaultValue: 20000.0, unit: 'Hz',
      scale: DspParameterScale.logarithmic,
    ),
    RtpcTargetParameter.highPassFilter: const DspParameterRange(
      min: 20.0, max: 20000.0, defaultValue: 20.0, unit: 'Hz',
      scale: DspParameterScale.logarithmic,
    ),

    // Reverb parameters
    RtpcTargetParameter.reverbDecay: const DspParameterRange(
      min: 0.1, max: 20.0, defaultValue: 2.0, unit: 's',
    ),
    RtpcTargetParameter.reverbPreDelay: const DspParameterRange(
      min: 0.0, max: 200.0, defaultValue: 20.0, unit: 'ms',
    ),
    RtpcTargetParameter.reverbMix: const DspParameterRange(
      min: 0.0, max: 1.0, defaultValue: 0.3, unit: '%',
    ),
    RtpcTargetParameter.reverbDamping: const DspParameterRange(
      min: 0.0, max: 1.0, defaultValue: 0.5, unit: '',
    ),
    RtpcTargetParameter.reverbSize: const DspParameterRange(
      min: 0.0, max: 1.0, defaultValue: 0.7, unit: '',
    ),

    // Compressor parameters
    RtpcTargetParameter.compressorThreshold: const DspParameterRange(
      min: -60.0, max: 0.0, defaultValue: -20.0, unit: 'dB',
      scale: DspParameterScale.decibel,
    ),
    RtpcTargetParameter.compressorRatio: const DspParameterRange(
      min: 1.0, max: 20.0, defaultValue: 4.0, unit: ':1',
    ),
    RtpcTargetParameter.compressorAttack: const DspParameterRange(
      min: 0.1, max: 500.0, defaultValue: 10.0, unit: 'ms',
    ),
    RtpcTargetParameter.compressorRelease: const DspParameterRange(
      min: 10.0, max: 2000.0, defaultValue: 100.0, unit: 'ms',
    ),
    RtpcTargetParameter.compressorMakeup: const DspParameterRange(
      min: 0.0, max: 24.0, defaultValue: 0.0, unit: 'dB',
    ),
    RtpcTargetParameter.compressorKnee: const DspParameterRange(
      min: 0.0, max: 24.0, defaultValue: 6.0, unit: 'dB',
    ),

    // Delay parameters
    RtpcTargetParameter.delayTime: const DspParameterRange(
      min: 0.0, max: 2000.0, defaultValue: 250.0, unit: 'ms',
    ),
    RtpcTargetParameter.delayFeedback: const DspParameterRange(
      min: 0.0, max: 0.95, defaultValue: 0.3, unit: '%',
    ),
    RtpcTargetParameter.delayMix: const DspParameterRange(
      min: 0.0, max: 1.0, defaultValue: 0.5, unit: '%',
    ),
    RtpcTargetParameter.delayHighCut: const DspParameterRange(
      min: 1000.0, max: 20000.0, defaultValue: 8000.0, unit: 'Hz',
      scale: DspParameterScale.logarithmic,
    ),
    RtpcTargetParameter.delayLowCut: const DspParameterRange(
      min: 20.0, max: 2000.0, defaultValue: 80.0, unit: 'Hz',
      scale: DspParameterScale.logarithmic,
    ),

    // Gate parameters
    RtpcTargetParameter.gateThreshold: const DspParameterRange(
      min: -80.0, max: 0.0, defaultValue: -40.0, unit: 'dB',
    ),
    RtpcTargetParameter.gateAttack: const DspParameterRange(
      min: 0.1, max: 50.0, defaultValue: 0.5, unit: 'ms',
    ),
    RtpcTargetParameter.gateRelease: const DspParameterRange(
      min: 10.0, max: 2000.0, defaultValue: 50.0, unit: 'ms',
    ),
    RtpcTargetParameter.gateRange: const DspParameterRange(
      min: -80.0, max: 0.0, defaultValue: -80.0, unit: 'dB',
    ),

    // Limiter parameters
    RtpcTargetParameter.limiterCeiling: const DspParameterRange(
      min: -12.0, max: 0.0, defaultValue: -0.3, unit: 'dB',
    ),
    RtpcTargetParameter.limiterRelease: const DspParameterRange(
      min: 10.0, max: 1000.0, defaultValue: 50.0, unit: 'ms',
    ),

    // Saturation parameters
    RtpcTargetParameter.saturationDrive: const DspParameterRange(
      min: 0.0, max: 1.0, defaultValue: 0.3, unit: '',
    ),
    RtpcTargetParameter.saturationMix: const DspParameterRange(
      min: 0.0, max: 1.0, defaultValue: 0.5, unit: '%',
    ),

    // De-Esser parameters
    RtpcTargetParameter.deEsserFrequency: const DspParameterRange(
      min: 2000.0, max: 12000.0, defaultValue: 6000.0, unit: 'Hz',
      scale: DspParameterScale.logarithmic,
    ),
    RtpcTargetParameter.deEsserThreshold: const DspParameterRange(
      min: -40.0, max: 0.0, defaultValue: -20.0, unit: 'dB',
    ),
    RtpcTargetParameter.deEsserRange: const DspParameterRange(
      min: -20.0, max: 0.0, defaultValue: -10.0, unit: 'dB',
    ),
  };

  // ═══════════════════════════════════════════════════════════════════════════
  // PUBLIC API
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get parameter range for a target parameter
  DspParameterRange? getParameterRange(RtpcTargetParameter param) {
    return _ranges[param];
  }

  /// Get parameter range tuple (min, max)
  (double, double) getParameterRangeTuple(RtpcTargetParameter param) {
    final range = _ranges[param];
    if (range != null) {
      return (range.min, range.max);
    }
    return param.defaultRange;
  }

  /// Apply RTPC modulation to a base value
  ///
  /// [baseValue] - The unmodulated parameter value
  /// [rtpcValue] - Normalized RTPC value (0-1)
  /// [curve] - The RTPC curve for mapping
  /// [param] - Target parameter for range clamping
  double modulateDspParameter({
    required RtpcTargetParameter param,
    required double baseValue,
    required double rtpcValue,
    required RtpcCurve curve,
  }) {
    // Evaluate curve to get output value
    final outputValue = curve.evaluate(rtpcValue.clamp(0.0, 1.0));

    // Clamp to parameter range
    final range = _ranges[param];
    if (range != null) {
      return range.clamp(outputValue);
    }

    return outputValue;
  }

  /// Modulate with blend between base and modulated value
  ///
  /// [amount] - Modulation depth (0 = baseValue, 1 = fully modulated)
  double modulateWithBlend({
    required RtpcTargetParameter param,
    required double baseValue,
    required double rtpcValue,
    required RtpcCurve curve,
    required double amount,
  }) {
    final modulated = modulateDspParameter(
      param: param,
      baseValue: baseValue,
      rtpcValue: rtpcValue,
      curve: curve,
    );

    return baseValue + (modulated - baseValue) * amount.clamp(0.0, 1.0);
  }

  /// Sync DSP parameter to engine via FFI
  ///
  /// Returns true if successful
  bool syncToEngine({
    required int trackId,
    required int slotIndex,
    required RtpcTargetParameter param,
    required double value,
    DspNodeType? processorType,
  }) {
    // Determine param index
    int? paramIndex;
    if (processorType != null) {
      paramIndex = DspParamMapping.getParamIndex(processorType, param);
    }

    if (paramIndex == null) {
      return false;
    }

    // Clamp value to range
    final range = _ranges[param];
    final clampedValue = range?.clamp(value) ?? value;

    // Call FFI
    final result = NativeFFI.instance.insertSetParam(
      trackId,
      slotIndex,
      paramIndex,
      clampedValue,
    );

    if (result != 0) {
      return false;
    }

    return true;
  }

  /// Batch sync multiple parameters at once
  void syncMultipleToEngine({
    required int trackId,
    required int slotIndex,
    required DspNodeType processorType,
    required Map<RtpcTargetParameter, double> values,
  }) {
    for (final entry in values.entries) {
      syncToEngine(
        trackId: trackId,
        slotIndex: slotIndex,
        param: entry.key,
        value: entry.value,
        processorType: processorType,
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SCALE CONVERSIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Convert frequency (Hz) to logarithmic position (0-1)
  ///
  /// Useful for frequency sliders with perceptually even spacing
  double frequencyToLogPosition(double hz, {double minHz = 20.0, double maxHz = 20000.0}) {
    if (hz <= minHz) return 0.0;
    if (hz >= maxHz) return 1.0;
    return (math.log(hz / minHz) / math.log(maxHz / minHz)).clamp(0.0, 1.0);
  }

  /// Convert logarithmic position (0-1) to frequency (Hz)
  double logPositionToFrequency(double position, {double minHz = 20.0, double maxHz = 20000.0}) {
    final clamped = position.clamp(0.0, 1.0);
    return minHz * math.pow(maxHz / minHz, clamped);
  }

  /// Convert linear gain (0-2) to dB
  double linearToDecibel(double linear, {double minDb = -60.0}) {
    if (linear <= 0.0) return minDb;
    final db = 20.0 * math.log(linear) / math.ln10;
    return db < minDb ? minDb : db;
  }

  /// Convert dB to linear gain
  double decibelToLinear(double db) {
    if (db <= -120.0) return 0.0;
    return math.pow(10.0, db / 20.0).toDouble();
  }

  /// Format parameter value for display with unit
  String formatParameterValue(RtpcTargetParameter param, double value) {
    final range = _ranges[param];
    if (range == null) return value.toStringAsFixed(2);

    switch (range.unit) {
      case 'Hz':
        if (value >= 1000) {
          return '${(value / 1000).toStringAsFixed(1)} kHz';
        }
        return '${value.toStringAsFixed(0)} Hz';
      case 'ms':
        if (value >= 1000) {
          return '${(value / 1000).toStringAsFixed(2)} s';
        }
        return '${value.toStringAsFixed(1)} ms';
      case 's':
        return '${value.toStringAsFixed(2)} s';
      case 'dB':
        return '${value.toStringAsFixed(1)} dB';
      case 'Q':
        return 'Q ${value.toStringAsFixed(2)}';
      case ':1':
        return '${value.toStringAsFixed(1)}:1';
      case '%':
        return '${(value * 100).toStringAsFixed(0)}%';
      default:
        return value.toStringAsFixed(2);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PRESET CURVES
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get preset curve for common modulation scenarios
  RtpcCurve getPresetCurve(String presetName, RtpcTargetParameter param) {
    final range = getParameterRangeTuple(param);
    final minOut = range.$1;
    final maxOut = range.$2;

    switch (presetName) {
      case 'linear':
        return RtpcCurve.linear(0.0, 1.0, minOut, maxOut);

      case 'linear_inverted':
        return RtpcCurve.linear(0.0, 1.0, maxOut, minOut);

      case 'exponential':
        return RtpcCurve(points: [
          RtpcCurvePoint(x: 0.0, y: minOut, shape: RtpcCurveShape.exp3),
          RtpcCurvePoint(x: 1.0, y: maxOut),
        ]);

      case 'logarithmic':
        return RtpcCurve(points: [
          RtpcCurvePoint(x: 0.0, y: minOut, shape: RtpcCurveShape.log3),
          RtpcCurvePoint(x: 1.0, y: maxOut),
        ]);

      case 's_curve':
        return RtpcCurve(points: [
          RtpcCurvePoint(x: 0.0, y: minOut, shape: RtpcCurveShape.sCurve),
          RtpcCurvePoint(x: 1.0, y: maxOut),
        ]);

      case 'threshold_50':
        final midOut = (minOut + maxOut) / 2.0;
        return RtpcCurve(points: [
          RtpcCurvePoint(x: 0.0, y: minOut, shape: RtpcCurveShape.constant),
          RtpcCurvePoint(x: 0.5, y: midOut),
          RtpcCurvePoint(x: 1.0, y: maxOut),
        ]);

      case 'threshold_75':
        return RtpcCurve(points: [
          RtpcCurvePoint(x: 0.0, y: minOut, shape: RtpcCurveShape.constant),
          RtpcCurvePoint(x: 0.75, y: minOut),
          RtpcCurvePoint(x: 1.0, y: maxOut),
        ]);

      default:
        return RtpcCurve.linear(0.0, 1.0, minOut, maxOut);
    }
  }

  /// Get all available preset curve names
  List<String> get presetCurveNames => [
    'linear',
    'linear_inverted',
    'exponential',
    'logarithmic',
    's_curve',
    'threshold_50',
    'threshold_75',
  ];

  // ═══════════════════════════════════════════════════════════════════════════
  // CATEGORIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get DSP parameters grouped by processor type
  static Map<DspNodeType, List<RtpcTargetParameter>> get parametersByProcessor => {
    DspNodeType.eq: DspParamMapping.getValidTargets(DspNodeType.eq),
    DspNodeType.compressor: DspParamMapping.getValidTargets(DspNodeType.compressor),
    DspNodeType.limiter: DspParamMapping.getValidTargets(DspNodeType.limiter),
    DspNodeType.gate: DspParamMapping.getValidTargets(DspNodeType.gate),
    DspNodeType.reverb: DspParamMapping.getValidTargets(DspNodeType.reverb),
    DspNodeType.delay: DspParamMapping.getValidTargets(DspNodeType.delay),
    DspNodeType.saturation: DspParamMapping.getValidTargets(DspNodeType.saturation),
    DspNodeType.deEsser: DspParamMapping.getValidTargets(DspNodeType.deEsser),
    DspNodeType.expander: DspParamMapping.getValidTargets(DspNodeType.expander),
  };

  /// Get processor type for a parameter
  static DspNodeType? getProcessorForParameter(RtpcTargetParameter param) {
    for (final entry in parametersByProcessor.entries) {
      if (entry.value.contains(param)) {
        return entry.key;
      }
    }
    return null;
  }

  /// Check if parameter is a filter parameter
  static bool isFilterParameter(RtpcTargetParameter param) {
    return param == RtpcTargetParameter.filterCutoff ||
           param == RtpcTargetParameter.filterResonance ||
           param == RtpcTargetParameter.lowPassFilter ||
           param == RtpcTargetParameter.highPassFilter;
  }

  /// Check if parameter is a dynamics parameter
  static bool isDynamicsParameter(RtpcTargetParameter param) {
    return param == RtpcTargetParameter.compressorThreshold ||
           param == RtpcTargetParameter.compressorRatio ||
           param == RtpcTargetParameter.compressorAttack ||
           param == RtpcTargetParameter.compressorRelease ||
           param == RtpcTargetParameter.compressorMakeup ||
           param == RtpcTargetParameter.compressorKnee ||
           param == RtpcTargetParameter.limiterCeiling ||
           param == RtpcTargetParameter.limiterRelease ||
           param == RtpcTargetParameter.gateThreshold ||
           param == RtpcTargetParameter.gateAttack ||
           param == RtpcTargetParameter.gateRelease ||
           param == RtpcTargetParameter.gateRange;
  }

  /// Check if parameter is a time-based effect parameter
  static bool isTimeBasedParameter(RtpcTargetParameter param) {
    return param == RtpcTargetParameter.reverbDecay ||
           param == RtpcTargetParameter.reverbPreDelay ||
           param == RtpcTargetParameter.reverbMix ||
           param == RtpcTargetParameter.reverbDamping ||
           param == RtpcTargetParameter.reverbSize ||
           param == RtpcTargetParameter.delayTime ||
           param == RtpcTargetParameter.delayFeedback ||
           param == RtpcTargetParameter.delayMix ||
           param == RtpcTargetParameter.delayHighCut ||
           param == RtpcTargetParameter.delayLowCut;
  }
}
