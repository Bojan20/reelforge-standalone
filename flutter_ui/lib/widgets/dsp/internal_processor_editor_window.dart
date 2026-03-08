// Internal Processor Editor Window
//
// Floating window for editing internal DSP processor parameters.
// Uses premium FabFilter panels (EQ, Comp, Limiter, Gate, Expander,
// Reverb, Delay, Saturation, DeEsser) when available.
// Falls back to generic parameter sliders for vintage EQs.
//
// Supports S/M/L sizing like FabFilter Pro series.

import 'package:flutter/material.dart';
import '../../providers/dsp_chain_provider.dart';
import '../../theme/fluxforge_theme.dart';
import '../../src/rust/native_ffi.dart';
import '../fabfilter/fabfilter_theme.dart';
import '../fabfilter/fabfilter_eq_panel.dart';
import '../fabfilter/fabfilter_compressor_panel.dart';
import '../fabfilter/fabfilter_limiter_panel.dart';
import '../fabfilter/fabfilter_gate_panel.dart';
import '../fabfilter/fabfilter_reverb_panel.dart';
import '../fabfilter/fabfilter_delay_panel.dart';
import '../fabfilter/fabfilter_saturation_panel.dart';
import '../fabfilter/fabfilter_deesser_panel.dart';
import '../fabfilter/fabfilter_expander_panel.dart';
import '../fabfilter/fabfilter_haas_panel.dart';
import '../fabfilter/fabfilter_imager_panel.dart';
import '../fabfilter/fabfilter_multiband_imager_panel.dart';
import '../eq/pultec_eq.dart';
import '../eq/api550_eq.dart';
import '../eq/neve1073_eq.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// OPEN EDITOR REGISTRY — tracks all open floating editor windows
// ═══════════════════════════════════════════════════════════════════════════════

/// Global registry of open processor editor windows.
/// Prevents duplicate windows for the same track+slot.
class ProcessorEditorRegistry {
  ProcessorEditorRegistry._();
  static final instance = ProcessorEditorRegistry._();

  /// Key = "trackId:slotIndex", Value = OverlayEntry
  final Map<String, OverlayEntry> _openEditors = {};

  /// Check if an editor is already open for this track+slot
  bool isOpen(int trackId, int slotIndex) =>
      _openEditors.containsKey('$trackId:$slotIndex');

  /// Register an open editor
  void register(int trackId, int slotIndex, OverlayEntry entry) =>
      _openEditors['$trackId:$slotIndex'] = entry;

  /// Unregister (on close)
  void unregister(int trackId, int slotIndex) =>
      _openEditors.remove('$trackId:$slotIndex');

  /// Close a specific editor
  void close(int trackId, int slotIndex) {
    final entry = _openEditors.remove('$trackId:$slotIndex');
    entry?.remove();
  }

  /// Close all open editors
  void closeAll() {
    for (final entry in _openEditors.values) {
      entry.remove();
    }
    _openEditors.clear();
  }

  /// Number of open editors
  int get count => _openEditors.length;
}

// ═══════════════════════════════════════════════════════════════════════════════
// PREMIUM PANEL SUPPORT CHECK
// ═══════════════════════════════════════════════════════════════════════════════

/// Node types that have premium panels (FabFilter or vintage hardware)
bool _hasPremiumPanel(DspNodeType type) {
  switch (type) {
    case DspNodeType.eq:
    case DspNodeType.compressor:
    case DspNodeType.limiter:
    case DspNodeType.gate:
    case DspNodeType.reverb:
    case DspNodeType.delay:
    case DspNodeType.saturation:
    case DspNodeType.deEsser:
    case DspNodeType.multibandSaturation:
    case DspNodeType.pultec:
    case DspNodeType.api550:
    case DspNodeType.neve1073:
      return true;
    case DspNodeType.expander:
    case DspNodeType.haasDelay:
    case DspNodeType.stereoImager:
    case DspNodeType.multibandStereoImager:
      return true;
  }
}

/// S/M/L size presets per processor type
Map<FabFilterSize, Size> _sizesForType(DspNodeType type) {
  switch (type) {
    case DspNodeType.eq:
      return FabFilterSizePresets.eq;
    case DspNodeType.compressor:
      return FabFilterSizePresets.compressor;
    case DspNodeType.limiter:
      return FabFilterSizePresets.limiter;
    case DspNodeType.gate:
      return FabFilterSizePresets.gate;
    case DspNodeType.reverb:
      return FabFilterSizePresets.reverb;
    case DspNodeType.delay:
      return FabFilterSizePresets.delay;
    case DspNodeType.saturation:
    case DspNodeType.multibandSaturation:
      return FabFilterSizePresets.saturation;
    case DspNodeType.deEsser:
      return FabFilterSizePresets.deEsser;
    case DspNodeType.expander:
      return FabFilterSizePresets.expander;
    case DspNodeType.pultec:
      return FabFilterSizePresets.pultec;
    case DspNodeType.api550:
      return FabFilterSizePresets.api550;
    case DspNodeType.neve1073:
      return FabFilterSizePresets.neve1073;
    case DspNodeType.haasDelay:
      return FabFilterSizePresets.haasDelay;
    case DspNodeType.stereoImager:
      return FabFilterSizePresets.imager;
    case DspNodeType.multibandStereoImager:
      return FabFilterSizePresets.saturation; // Wide panel for multiband
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MAIN WIDGET
// ═══════════════════════════════════════════════════════════════════════════════

/// Floating editor window for internal DSP processors.
///
/// Opens as an [OverlayEntry] that can be dragged, resized, and closed
/// independently of the Lower Zone. Uses premium FabFilter panels when
/// available, falls back to generic parameter sliders otherwise.
///
/// Supports S/M/L sizing like FabFilter Pro series.
class InternalProcessorEditorWindow extends StatefulWidget {
  final int trackId;
  final int slotIndex;
  final DspNode node;
  final VoidCallback? onClose;
  final Offset initialPosition;

  const InternalProcessorEditorWindow({
    super.key,
    required this.trackId,
    required this.slotIndex,
    required this.node,
    this.onClose,
    this.initialPosition = const Offset(100, 100),
  });

  /// Show the editor as a floating overlay.
  static OverlayEntry? show({
    required BuildContext context,
    required int trackId,
    required int slotIndex,
    required DspNode node,
    Offset? position,
  }) {
    final registry = ProcessorEditorRegistry.instance;

    // Already open — close and reopen to bring to front
    if (registry.isOpen(trackId, slotIndex)) {
      registry.close(trackId, slotIndex);
    }

    final overlay = Overlay.of(context);
    OverlayEntry? entry;

    // Stagger position based on open editor count
    final basePos = position ?? Offset(120.0 + registry.count * 30.0,
                                        80.0 + registry.count * 30.0);

    entry = OverlayEntry(
      builder: (context) => InternalProcessorEditorWindow(
        trackId: trackId,
        slotIndex: slotIndex,
        node: node,
        initialPosition: basePos,
        onClose: () {
          entry?.remove();
          registry.unregister(trackId, slotIndex);
        },
      ),
    );

    registry.register(trackId, slotIndex, entry);
    overlay.insert(entry);
    return entry;
  }

  @override
  State<InternalProcessorEditorWindow> createState() =>
      _InternalProcessorEditorWindowState();
}

class _InternalProcessorEditorWindowState
    extends State<InternalProcessorEditorWindow> {
  late Offset _position;
  bool _isDragging = false;
  late Map<String, dynamic> _params;
  bool _isCollapsed = false;
  FabFilterSize _currentSize = FabFilterSize.medium;
  late bool _isBypassed;

  @override
  void initState() {
    super.initState();
    _position = widget.initialPosition;
    _params = Map<String, dynamic>.from(widget.node.params);
    _isBypassed = widget.node.bypass;
  }

  Size get _windowSize {
    final sizes = _sizesForType(widget.node.type);
    return sizes[_currentSize] ?? sizes[FabFilterSize.medium]!;
  }

  void _updateParam(String key, dynamic value, int paramIndex) {
    setState(() {
      _params[key] = value;
    });
    if (value is num) {
      NativeFFI.instance.insertSetParam(
        widget.trackId,
        widget.slotIndex,
        paramIndex,
        value.toDouble(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = _windowSize;
    final hasPremium = _hasPremiumPanel(widget.node.type);
    final isVintage = widget.node.type == DspNodeType.pultec ||
        widget.node.type == DspNodeType.api550 ||
        widget.node.type == DspNodeType.neve1073;

    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: Material(
        elevation: 24,
        borderRadius: BorderRadius.circular(8),
        color: isVintage
            ? const Color(0xFF1A1A1E)
            : hasPremium
                ? const Color(0xFF0D0D11)
                : FluxForgeTheme.bgDeep,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          width: size.width,
          height: _isCollapsed ? 36 : size.height,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            border: Border.all(
              color: hasPremium
                  ? _getTypeColor(widget.node.type).withValues(alpha: 0.3)
                  : FluxForgeTheme.bgSurface,
              width: hasPremium ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              _buildTitleBar(),
              if (!_isCollapsed) Expanded(child: _buildContent()),
            ],
          ),
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════════
  // TITLE BAR (draggable) — with S/M/L size buttons
  // ═════════════════════════════════════════════════════════════════════════════

  Widget _buildTitleBar() {
    final typeColor = _getTypeColor(widget.node.type);
    final hasPremium = _hasPremiumPanel(widget.node.type);

    return GestureDetector(
      onPanStart: (_) => setState(() => _isDragging = true),
      onPanUpdate: (details) {
        if (_isDragging) {
          setState(() {
            _position = Offset(
              _position.dx + details.delta.dx,
              _position.dy + details.delta.dy,
            );
          });
        }
      },
      onPanEnd: (_) => setState(() => _isDragging = false),
      child: Container(
        height: 36,
        padding: const EdgeInsets.only(left: 10, right: 4),
        decoration: BoxDecoration(
          gradient: hasPremium
              ? LinearGradient(
                  colors: [
                    typeColor.withValues(alpha: 0.15),
                    const Color(0xFF161620),
                  ],
                )
              : null,
          color: hasPremium ? null : FluxForgeTheme.bgMid,
        ),
        child: Row(
          children: [
            // Type badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: typeColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: typeColor.withValues(alpha: 0.4)),
              ),
              child: Text(
                widget.node.type.shortName,
                style: TextStyle(
                  color: typeColor,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Name
            Expanded(
              child: Text(
                widget.node.name,
                style: const TextStyle(
                  color: FluxForgeTheme.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // S / M / L size buttons
            _buildSizeButton('S', FabFilterSize.small),
            _buildSizeButton('M', FabFilterSize.medium),
            _buildSizeButton('L', FabFilterSize.large),

            const SizedBox(width: 4),

            // Separator
            Container(
              width: 1,
              height: 18,
              color: Colors.white.withValues(alpha: 0.08),
            ),

            // Collapse toggle
            _buildTitleButton(
              icon: _isCollapsed ? Icons.unfold_more : Icons.unfold_less,
              tooltip: _isCollapsed ? 'Expand' : 'Collapse',
              onPressed: () => setState(() => _isCollapsed = !_isCollapsed),
            ),

            // Bypass toggle — local state + direct FFI + DspChainProvider sync
            _buildTitleButton(
              icon: Icons.power_settings_new,
              tooltip: _isBypassed ? 'Enable' : 'Bypass',
              color: _isBypassed
                  ? FluxForgeTheme.textDisabled
                  : FluxForgeTheme.accentGreen,
              onPressed: () {
                setState(() => _isBypassed = !_isBypassed);
                // Direct FFI call — always works regardless of DspChainProvider state
                NativeFFI.instance.insertSetBypass(widget.trackId, widget.slotIndex, _isBypassed);
                // Sync DspChainProvider UI state
                final chain = DspChainProvider.instance.getChain(widget.trackId);
                final nodeIndex = chain.nodes.indexWhere((n) => n.id == widget.node.id);
                if (nodeIndex >= 0) {
                  DspChainProvider.instance.toggleNodeBypass(widget.trackId, widget.node.id);
                } else {
                  // Node not in DspChainProvider — add it so future reads see bypass
                  DspChainProvider.instance.addNodeUiOnly(widget.trackId, widget.node.type, atSlot: widget.slotIndex);
                  DspChainProvider.instance.setNodeBypassUiOnly(widget.trackId, widget.node.type, _isBypassed);
                }
              },
            ),

            // Close button
            _buildTitleButton(
              icon: Icons.close,
              tooltip: 'Close',
              color: FluxForgeTheme.textSecondary,
              onPressed: widget.onClose,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSizeButton(String label, FabFilterSize size) {
    final isActive = _currentSize == size;
    final typeColor = _getTypeColor(widget.node.type);

    return GestureDetector(
      onTap: () => setState(() => _currentSize = size),
      child: Container(
        width: 22,
        height: 22,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          color: isActive
              ? typeColor.withValues(alpha: 0.25)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
          border: isActive
              ? Border.all(color: typeColor.withValues(alpha: 0.5), width: 1)
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? typeColor : Colors.white.withValues(alpha: 0.35),
            fontSize: 9,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildTitleButton({
    required IconData icon,
    required String tooltip,
    Color? color,
    VoidCallback? onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 16,
            color: color ?? FluxForgeTheme.textTertiary,
          ),
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════════
  // CONTENT — FabFilter panel or generic sliders
  // ═════════════════════════════════════════════════════════════════════════════

  Widget _buildContent() {
    if (_hasPremiumPanel(widget.node.type)) {
      return _buildFabFilterPanel();
    }
    // Generic slider fallback
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: FluxForgeTheme.bgDeep,
      ),
      child: _buildGenericParamsForType(),
    );
  }

  /// Build the premium FabFilter panel for this processor type
  Widget _buildFabFilterPanel() {
    final si = widget.slotIndex;
    switch (widget.node.type) {
      case DspNodeType.eq:
        return FabFilterEqPanel(trackId: widget.trackId, slotIndex: si);
      case DspNodeType.compressor:
        return FabFilterCompressorPanel(trackId: widget.trackId, slotIndex: si);
      case DspNodeType.limiter:
        return FabFilterLimiterPanel(trackId: widget.trackId, slotIndex: si);
      case DspNodeType.gate:
        return FabFilterGatePanel(trackId: widget.trackId, slotIndex: si);
      case DspNodeType.reverb:
        return FabFilterReverbPanel(trackId: widget.trackId, slotIndex: si);
      case DspNodeType.delay:
        return FabFilterDelayPanel(trackId: widget.trackId, slotIndex: si);
      case DspNodeType.saturation:
      case DspNodeType.multibandSaturation:
        return FabFilterSaturationPanel(trackId: widget.trackId, slotIndex: si);
      case DspNodeType.deEsser:
        return FabFilterDeEsserPanel(trackId: widget.trackId, slotIndex: si);
      case DspNodeType.expander:
        return FabFilterExpanderPanel(trackId: widget.trackId, slotIndex: si);
      case DspNodeType.haasDelay:
        return FabFilterHaasPanel(trackId: widget.trackId, slotIndex: si);
      case DspNodeType.stereoImager:
        return FabFilterImagerPanel(trackId: widget.trackId, slotIndex: si);
      case DspNodeType.multibandStereoImager:
        return FabFilterMultibandImagerPanel(trackId: widget.trackId, slotIndex: si);
      case DspNodeType.pultec:
        return PultecEq(
          onParamsChanged: (params) {
            final ffi = NativeFFI.instance;
            final t = widget.trackId;
            final s = widget.slotIndex;
            // Bypass
            ffi.insertSetBypass(t, s, params.bypass);
            // Gain params (0-3)
            ffi.insertSetParam(t, s, 0, params.lowBoost);
            ffi.insertSetParam(t, s, 1, params.lowAtten);
            ffi.insertSetParam(t, s, 2, params.highBoost);
            ffi.insertSetParam(t, s, 3, params.highAtten);
            // Freq indices (4-6): Hz → index
            const pultecLowFreqs = [20, 30, 60, 100];
            const pultecHiBoostFreqs = [3000, 4000, 5000, 8000, 10000, 12000, 16000];
            const pultecHiAttenFreqs = [5000, 10000, 20000];
            final lowIdx = pultecLowFreqs.indexOf(params.lowFreq);
            final hiBoostIdx = pultecHiBoostFreqs.indexOf(params.highBoostFreq);
            final hiAttenIdx = pultecHiAttenFreqs.indexOf(params.highAttenFreq);
            ffi.insertSetParam(t, s, 4, (lowIdx >= 0 ? lowIdx : 2).toDouble());
            ffi.insertSetParam(t, s, 5, (hiBoostIdx >= 0 ? hiBoostIdx : 3).toDouble());
            ffi.insertSetParam(t, s, 6, (hiAttenIdx >= 0 ? hiAttenIdx : 1).toDouble());
            // Bandwidth (7): 0-10 → 0.0-1.0
            ffi.insertSetParam(t, s, 7, (params.bandwidth / 10.0).clamp(0.0, 1.0));
            // Drive (8): not exposed in PultecParams → 0
            // Output Level (9): dB
            ffi.insertSetParam(t, s, 9, params.outputLevel);
          },
        );
      case DspNodeType.api550:
        return Api550Eq(
          onParamsChanged: (params) {
            final ffi = NativeFFI.instance;
            final t = widget.trackId;
            final s = widget.slotIndex;
            // Bypass
            ffi.insertSetBypass(t, s, params.bypass);
            // Api550Wrapper param layout (7 params, UAD-faithful):
            // 0: Low Gain (-12 to +12 dB)
            ffi.insertSetParam(t, s, 0, params.lowGain);
            // 1: Mid Gain (-12 to +12 dB)
            ffi.insertSetParam(t, s, 1, params.midGain);
            // 2: High Gain (-12 to +12 dB)
            ffi.insertSetParam(t, s, 2, params.highGain);
            // 3: Low Freq index (0-6: 30,40,50,100,200,300,400 Hz)
            ffi.insertSetParam(t, s, 3, _api550LowFreqToIndex(params.lowFreq));
            // 4: Mid Freq index (0-6: 200,400,600,800,1.5k,3k,5k Hz)
            ffi.insertSetParam(t, s, 4, _api550MidFreqToIndex(params.midFreq));
            // 5: High Freq index (0-6: 2.5k,5k,7k,10k,12.5k,15k,20k Hz)
            ffi.insertSetParam(t, s, 5, _api550HighFreqToIndex(params.highFreq));
            // 6: Output Level (dB)
            ffi.insertSetParam(t, s, 6, params.outputLevel);
          },
        );
      case DspNodeType.neve1073:
        return Neve1073Eq(
          onParamsChanged: (params) {
            final ffi = NativeFFI.instance;
            final t = widget.trackId;
            final s = widget.slotIndex;
            // Bypass (eqEnabled is inverse of bypass)
            ffi.insertSetBypass(t, s, !params.eqEnabled);
            // NEW Neve1073Wrapper param layout (8 params, UAD-faithful):
            // 0: HP Enabled (0/1)
            ffi.insertSetParam(t, s, 0, params.hpfEnabled ? 1.0 : 0.0);
            // 1: LF Gain (-16 to +16 dB)
            ffi.insertSetParam(t, s, 1, params.lfGain);
            // 2: MF Gain (-18 to +18 dB)
            ffi.insertSetParam(t, s, 2, params.mfGain);
            // 3: HF Gain (-16 to +16 dB, fixed 12kHz)
            ffi.insertSetParam(t, s, 3, params.hfGain);
            // 4: HP Freq index (0-3: 50, 80, 160, 300 Hz)
            const neveHpFreqs = [50, 80, 160, 300];
            final hpIdx = neveHpFreqs.indexOf(params.hpfFreq);
            ffi.insertSetParam(t, s, 4, (hpIdx >= 0 ? hpIdx : 3).toDouble());
            // 5: LF Freq index (0-3: 35, 60, 110, 220 Hz)
            const neveLfFreqs = [35, 60, 110, 220];
            final lfIdx = neveLfFreqs.indexOf(params.lfFreq);
            ffi.insertSetParam(t, s, 5, (lfIdx >= 0 ? lfIdx : 2).toDouble());
            // 6: MF Freq index (0-5: 360, 700, 1600, 3200, 4800, 7200 Hz)
            const neveMfFreqs = [360, 700, 1600, 3200, 4800, 7200];
            final mfIdx = neveMfFreqs.indexOf(params.mfFreq);
            ffi.insertSetParam(t, s, 6, (mfIdx >= 0 ? mfIdx : 2).toDouble());
            // 7: Output Level (dB)
            ffi.insertSetParam(t, s, 7, params.outputLevel);
          },
        );
    }
  }

  // ═════════════════════════════════════════════════════════════════════════════
  // GENERIC PARAM SLIDERS — fallback for types without FabFilter panels
  // ═════════════════════════════════════════════════════════════════════════════

  Widget _buildGenericParamsForType() {
    return const Text(
      'No editor available',
      style: TextStyle(color: FluxForgeTheme.textDisabled),
    );
  }

  Color _getTypeColor(DspNodeType type) {
    switch (type) {
      case DspNodeType.eq:
        return FluxForgeTheme.accentCyan;
      case DspNodeType.compressor:
        return FluxForgeTheme.accentOrange;
      case DspNodeType.limiter:
        return FluxForgeTheme.accentRed;
      case DspNodeType.gate:
        return FluxForgeTheme.accentYellow;
      case DspNodeType.expander:
        return FluxForgeTheme.accentGreen;
      case DspNodeType.reverb:
        return FluxForgeTheme.accentBlue;
      case DspNodeType.delay:
        return FluxForgeTheme.accentPurple;
      case DspNodeType.saturation:
        return FluxForgeTheme.accentPink;
      case DspNodeType.deEsser:
        return FluxForgeTheme.accentCyan;
      case DspNodeType.pultec:
        return const Color(0xFFD4A574);
      case DspNodeType.api550:
        return const Color(0xFF4A9EFF);
      case DspNodeType.neve1073:
        return const Color(0xFF8B4513);
      case DspNodeType.multibandSaturation:
        return FluxForgeTheme.accentOrange;
      case DspNodeType.haasDelay:
        return FluxForgeTheme.accentGreen;
      case DspNodeType.stereoImager:
        return FluxForgeTheme.accentCyan;
      case DspNodeType.multibandStereoImager:
        return FluxForgeTheme.accentCyan;
    }
  }

  // ═════════════════════════════════════════════════════════════════════════════
  // VINTAGE EQ — Hz → Rust enum index converters (UAD-faithful 7 positions)
  // ═════════════════════════════════════════════════════════════════════════════

  /// API 550A low freq: Dart [30,40,50,100,200,300,400] → Rust Api550LowFreq enum
  /// Hz30(0), Hz40(1), Hz50(2), Hz100(3), Hz200(4), Hz300(5), Hz400(6)
  static double _api550LowFreqToIndex(int hz) {
    switch (hz) {
      case 30:  return 0.0;
      case 40:  return 1.0;
      case 50:  return 2.0;
      case 100: return 3.0;
      case 200: return 4.0;
      case 300: return 5.0;
      case 400: return 6.0;
      default:  return 3.0; // fallback to 100Hz
    }
  }

  /// API 550A mid freq: Dart [200,400,600,800,1500,3000,5000] → Rust Api550MidFreq enum
  /// Hz200(0), Hz400(1), Hz600(2), Hz800(3), K1_5(4), K3(5), K5(6)
  static double _api550MidFreqToIndex(int hz) {
    switch (hz) {
      case 200:  return 0.0;
      case 400:  return 1.0;
      case 600:  return 2.0;
      case 800:  return 3.0;
      case 1500: return 4.0;
      case 3000: return 5.0;
      case 5000: return 6.0;
      default:   return 3.0; // fallback to 800Hz
    }
  }

  /// API 550A high freq: Dart [2500,5000,7000,10000,12500,15000,20000] → Rust Api550HighFreq enum
  /// K2_5(0), K5(1), K7(2), K10(3), K12_5(4), K15(5), K20(6)
  static double _api550HighFreqToIndex(int hz) {
    switch (hz) {
      case 2500:  return 0.0;
      case 5000:  return 1.0;
      case 7000:  return 2.0;
      case 10000: return 3.0;
      case 12500: return 4.0;
      case 15000: return 5.0;
      case 20000: return 6.0;
      default:    return 1.0; // fallback to 5kHz
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PARAM SLIDER WIDGET (generic fallback)
// ═══════════════════════════════════════════════════════════════════════════════

class _ParamSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final double? defaultValue;
  final String unit;
  final ValueChanged<double> onChanged;

  const _ParamSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.unit,
    required this.onChanged,
    this.defaultValue,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: () => onChanged(defaultValue ?? (min + max) / 2),
      child: Row(
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: const TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 12,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: FluxForgeTheme.accentCyan,
              inactiveTrackColor: FluxForgeTheme.bgMid,
              thumbColor: FluxForgeTheme.accentCyan,
              overlayColor: FluxForgeTheme.accentCyan.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 65,
          child: Text(
            _formatValue(),
            style: const TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 11,
              fontFamily: 'JetBrains Mono',
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    ),
    );
  }

  String _formatValue() {
    if (unit == 'dB') {
      return '${value >= 0 ? '+' : ''}${value.toStringAsFixed(1)} $unit';
    } else if (unit == ':1') {
      return '${value.toStringAsFixed(1)}$unit';
    } else if (unit == 'Hz') {
      if (value >= 1000) {
        return '${(value / 1000).toStringAsFixed(1)} kHz';
      }
      return '${value.toStringAsFixed(0)} $unit';
    } else if (unit == 'ms' || unit == 's') {
      return '${value.toStringAsFixed(1)} $unit';
    } else if (unit.isEmpty) {
      return value.toStringAsFixed(2);
    }
    return '${value.toStringAsFixed(1)} $unit';
  }
}
