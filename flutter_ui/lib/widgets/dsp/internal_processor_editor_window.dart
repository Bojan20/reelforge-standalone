// Internal Processor Editor Window
//
// Floating window for editing internal DSP processor parameters.
// Uses premium FabFilter panels (EQ, Comp, Limiter, Gate, Expander,
// Reverb, Delay, Saturation, DeEsser) when available.
// Falls back to generic parameter sliders for vintage EQs.

import 'package:flutter/material.dart';
import '../../providers/dsp_chain_provider.dart';
import '../../theme/fluxforge_theme.dart';
import '../../src/rust/native_ffi.dart';
import '../fabfilter/fabfilter_eq_panel.dart';
import '../fabfilter/fabfilter_compressor_panel.dart';
import '../fabfilter/fabfilter_limiter_panel.dart';
import '../fabfilter/fabfilter_gate_panel.dart';
import '../fabfilter/fabfilter_reverb_panel.dart';
import '../fabfilter/fabfilter_delay_panel.dart';
import '../fabfilter/fabfilter_saturation_panel.dart';
import '../fabfilter/fabfilter_deesser_panel.dart';
import '../fabfilter/fabfilter_expander_panel.dart';
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
      return true;
  }
}

/// Window dimensions based on panel type
Size _windowSizeForType(DspNodeType type) {
  switch (type) {
    // FabFilter premium panels
    case DspNodeType.eq:
      return const Size(700, 520);
    case DspNodeType.compressor:
      return const Size(660, 500);
    case DspNodeType.limiter:
      return const Size(620, 480);
    case DspNodeType.gate:
      return const Size(620, 480);
    case DspNodeType.reverb:
      return const Size(660, 500);
    case DspNodeType.delay:
      return const Size(620, 480);
    case DspNodeType.saturation:
    case DspNodeType.multibandSaturation:
      return const Size(600, 460);
    case DspNodeType.deEsser:
      return const Size(560, 440);
    // Vintage hardware panels
    case DspNodeType.pultec:
      return const Size(680, 520);
    case DspNodeType.api550:
      return const Size(540, 500);
    case DspNodeType.neve1073:
      return const Size(640, 520);
    case DspNodeType.expander:
      return const Size(620, 480);
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
  ///
  /// If an editor for this track+slot is already open, it is brought
  /// to the front instead of opening a duplicate.
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

  @override
  void initState() {
    super.initState();
    _position = widget.initialPosition;
    _params = Map<String, dynamic>.from(widget.node.params);
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
    final size = _windowSizeForType(widget.node.type);
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
        child: Container(
          width: size.width,
          constraints: BoxConstraints(
            maxHeight: _isCollapsed ? 36 : size.height,
          ),
          decoration: BoxDecoration(
            border: Border.all(
              color: hasPremium
                  ? _getTypeColor(widget.node.type).withValues(alpha: 0.3)
                  : FluxForgeTheme.bgSurface,
              width: hasPremium ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildTitleBar(),
                if (!_isCollapsed) _buildContent(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════════
  // TITLE BAR (draggable)
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
        padding: const EdgeInsets.symmetric(horizontal: 10),
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

            // Track badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                'T${widget.trackId}:${widget.slotIndex}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 9,
                  fontFamily: 'JetBrains Mono',
                ),
              ),
            ),
            const SizedBox(width: 6),

            // Collapse toggle
            _buildTitleButton(
              icon: _isCollapsed ? Icons.unfold_more : Icons.unfold_less,
              tooltip: _isCollapsed ? 'Expand' : 'Collapse',
              onPressed: () => setState(() => _isCollapsed = !_isCollapsed),
            ),

            // Bypass toggle
            _buildTitleButton(
              icon: Icons.power_settings_new,
              tooltip: widget.node.bypass ? 'Enable' : 'Bypass',
              color: widget.node.bypass
                  ? FluxForgeTheme.textDisabled
                  : FluxForgeTheme.accentGreen,
              onPressed: () {
                DspChainProvider.instance.toggleNodeBypass(
                  widget.trackId,
                  widget.node.id,
                );
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

  Widget _buildTitleButton({
    required IconData icon,
    required String tooltip,
    Color? color,
    VoidCallback? onPressed,
  }) {
    return IconButton(
      icon: Icon(icon, size: 16, color: color ?? FluxForgeTheme.textTertiary),
      tooltip: tooltip,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════════
  // CONTENT — FabFilter panel or generic sliders
  // ═════════════════════════════════════════════════════════════════════════════

  Widget _buildContent() {
    if (_hasPremiumPanel(widget.node.type)) {
      return Flexible(
        child: _buildFabFilterPanel(),
      );
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
    switch (widget.node.type) {
      case DspNodeType.eq:
        return FabFilterEqPanel(trackId: widget.trackId);
      case DspNodeType.compressor:
        return FabFilterCompressorPanel(trackId: widget.trackId);
      case DspNodeType.limiter:
        return FabFilterLimiterPanel(trackId: widget.trackId);
      case DspNodeType.gate:
        return FabFilterGatePanel(trackId: widget.trackId);
      case DspNodeType.reverb:
        return FabFilterReverbPanel(trackId: widget.trackId);
      case DspNodeType.delay:
        return FabFilterDelayPanel(trackId: widget.trackId);
      case DspNodeType.saturation:
      case DspNodeType.multibandSaturation:
        return FabFilterSaturationPanel(trackId: widget.trackId);
      case DspNodeType.deEsser:
        return FabFilterDeEsserPanel(trackId: widget.trackId);
      case DspNodeType.expander:
        return FabFilterExpanderPanel(trackId: widget.trackId);
      case DspNodeType.pultec:
        return PultecEq(
          onParamsChanged: (params) {
            // Sync key params to FFI insert chain
            NativeFFI.instance.insertSetParam(widget.trackId, widget.slotIndex, 0, params.lowBoost);
            NativeFFI.instance.insertSetParam(widget.trackId, widget.slotIndex, 1, params.lowAtten);
            NativeFFI.instance.insertSetParam(widget.trackId, widget.slotIndex, 2, params.highBoost);
            NativeFFI.instance.insertSetParam(widget.trackId, widget.slotIndex, 3, params.highAtten);
          },
        );
      case DspNodeType.api550:
        return Api550Eq(
          onParamsChanged: (params) {
            NativeFFI.instance.insertSetParam(widget.trackId, widget.slotIndex, 0, params.lowGain);
            NativeFFI.instance.insertSetParam(widget.trackId, widget.slotIndex, 1, params.midGain);
            NativeFFI.instance.insertSetParam(widget.trackId, widget.slotIndex, 2, params.highGain);
          },
        );
      case DspNodeType.neve1073:
        return Neve1073Eq(
          onParamsChanged: (params) {
            NativeFFI.instance.insertSetParam(widget.trackId, widget.slotIndex, 0, params.hpfEnabled ? 1.0 : 0.0);
            NativeFFI.instance.insertSetParam(widget.trackId, widget.slotIndex, 1, params.lfGain);
            NativeFFI.instance.insertSetParam(widget.trackId, widget.slotIndex, 2, params.hfGain);
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
  final String unit;
  final ValueChanged<double> onChanged;

  const _ParamSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.unit,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
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
