/// FabFilter-Style Widgets
///
/// Professional DSP panel widgets inspired by FabFilter's design language:
/// - Pro-Q style EQ panel with interactive spectrum
/// - Pro-C style Compressor panel with knee visualization
/// - Pro-L style Limiter panel with LUFS metering
///
/// Usage:
/// ```dart
/// import 'package:flutter_ui/widgets/fabfilter/fabfilter.dart';
///
/// FabFilterEqPanel(trackId: 0)
/// FabFilterCompressorPanel(trackId: 0)
/// FabFilterLimiterPanel(trackId: 0)
/// ```

export 'fabfilter_theme.dart';
export 'fabfilter_knob.dart';
export 'fabfilter_panel_base.dart';
export 'fabfilter_eq_panel.dart';
export 'fabfilter_compressor_panel.dart';
export 'fabfilter_limiter_panel.dart';
export 'fabfilter_reverb_panel.dart';
export 'fabfilter_gate_panel.dart';
export 'fabfilter_preset_browser.dart';
