/// Floating Mixer Window — Detachable full-featured mixer (Pro Tools style)
///
/// Opens as an OverlayEntry floating window that can be dragged and resized.
/// Contains the full MixerScreen with all callbacks.
/// Toggle via Cmd+Shift+= or the Detach button in MixerTopBar.

import 'package:flutter/material.dart';
import '../../controllers/mixer/mixer_view_controller.dart';
import '../../models/mixer_view_models.dart';
import '../../widgets/mixer/ultimate_mixer.dart' as ultimate;
import 'mixer_status_bar.dart';
import 'mixer_top_bar.dart';

// ═══════════════════════════════════════════════════════════════════════════
// FLOATING MIXER REGISTRY
// ═══════════════════════════════════════════════════════════════════════════

/// Singleton registry — only one floating mixer allowed at a time.
class FloatingMixerRegistry {
  FloatingMixerRegistry._();
  static final instance = FloatingMixerRegistry._();

  OverlayEntry? _entry;
  VoidCallback? _onClosed;

  bool get isOpen => _entry != null;

  void register(OverlayEntry entry, {VoidCallback? onClosed}) {
    _entry = entry;
    _onClosed = onClosed;
  }

  void close() {
    _entry?.remove();
    _entry = null;
    _onClosed?.call();
    _onClosed = null;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// FLOATING MIXER WINDOW
// ═══════════════════════════════════════════════════════════════════════════

class FloatingMixerWindow {
  /// Show a floating mixer window via OverlayEntry.
  /// If already open, closes it (toggle behavior).
  static void show({
    required BuildContext context,
    required MixerViewController viewController,
    required MixerCallbacks callbacks,
    VoidCallback? onClosed,
  }) {
    final registry = FloatingMixerRegistry.instance;

    // Toggle — close if already open
    if (registry.isOpen) {
      registry.close();
      return;
    }

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _FloatingMixerWidget(
        parentContext: context,
        viewController: viewController,
        callbacks: callbacks,
        onClose: () {
          registry.close();
        },
        onDock: () {
          registry.close();
          // The onClosed callback switches back to inline mixer mode
        },
      ),
    );

    registry.register(entry, onClosed: onClosed);
    Overlay.of(context).insert(entry);
  }
}

/// Bundles all mixer callbacks to avoid 25+ parameters.
class MixerCallbacks {
  final ValueChanged<String>? onChannelSelect;
  final void Function(String, double)? onVolumeChange;
  final void Function(String, double)? onPanChange;
  final void Function(String, double)? onPanChangeEnd;
  final void Function(String, double)? onPanRightChange;
  final ValueChanged<String>? onMuteToggle;
  final ValueChanged<String>? onSoloToggle;
  final ValueChanged<String>? onArmToggle;
  final void Function(String, int, double)? onSendLevelChange;
  final void Function(String, int, bool)? onSendMuteToggle;
  final void Function(String, int, bool)? onSendPreFaderToggle;
  final void Function(String, int, String?)? onSendDestChange;
  final void Function(String, int)? onInsertClick;
  final void Function(String, String)? onOutputChange;
  final ValueChanged<String>? onPhaseToggle;
  final void Function(String, double)? onGainChange;
  final VoidCallback? onAddBus;
  final void Function(int, int)? onChannelReorder;
  final ValueChanged<String>? onSoloSafeToggle;
  final void Function(String, String)? onCommentsChanged;
  final ValueChanged<String>? onFolderToggle;
  final ValueChanged<String>? onEqCurveClick;
  final void Function(String, double)? onWidthChange;

  /// Build channel/bus data from providers — passed as function
  /// so the floating window can rebuild with fresh data each frame.
  final List<ultimate.UltimateMixerChannel> Function() buildChannels;
  final List<ultimate.UltimateMixerChannel> Function() buildBuses;
  final List<ultimate.UltimateMixerChannel> Function() buildAuxes;
  final List<ultimate.UltimateMixerChannel> Function() buildVcas;
  final ultimate.UltimateMixerChannel Function() buildMaster;

  const MixerCallbacks({
    this.onChannelSelect,
    this.onVolumeChange,
    this.onPanChange,
    this.onPanChangeEnd,
    this.onPanRightChange,
    this.onMuteToggle,
    this.onSoloToggle,
    this.onArmToggle,
    this.onSendLevelChange,
    this.onSendMuteToggle,
    this.onSendPreFaderToggle,
    this.onSendDestChange,
    this.onInsertClick,
    this.onOutputChange,
    this.onPhaseToggle,
    this.onGainChange,
    this.onAddBus,
    this.onChannelReorder,
    this.onSoloSafeToggle,
    this.onCommentsChanged,
    this.onFolderToggle,
    this.onEqCurveClick,
    this.onWidthChange,
    required this.buildChannels,
    required this.buildBuses,
    required this.buildAuxes,
    required this.buildVcas,
    required this.buildMaster,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// FLOATING MIXER WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class _FloatingMixerWidget extends StatefulWidget {
  final BuildContext parentContext;
  final MixerViewController viewController;
  final MixerCallbacks callbacks;
  final VoidCallback onClose;
  final VoidCallback onDock;

  const _FloatingMixerWidget({
    required this.parentContext,
    required this.viewController,
    required this.callbacks,
    required this.onClose,
    required this.onDock,
  });

  @override
  State<_FloatingMixerWidget> createState() => _FloatingMixerWidgetState();
}

class _FloatingMixerWidgetState extends State<_FloatingMixerWidget> {
  Offset _position = const Offset(60, 60);
  Size _size = const Size(1200, 500);

  static const double _minWidth = 600;
  static const double _minHeight = 300;
  static const double _titleBarHeight = 28;

  @override
  void initState() {
    super.initState();
    widget.viewController.addListener(_rebuild);
    // Center on screen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final screenSize = MediaQuery.of(widget.parentContext).size;
      setState(() {
        _size = Size(
          (screenSize.width * 0.85).clamp(_minWidth, screenSize.width - 40),
          (screenSize.height * 0.55).clamp(_minHeight, screenSize.height - 80),
        );
        _position = Offset(
          (screenSize.width - _size.width) / 2,
          (screenSize.height - _size.height) / 2,
        );
      });
    });
  }

  @override
  void dispose() {
    widget.viewController.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cb = widget.callbacks;
    final vc = widget.viewController;

    final showTracks = vc.isSectionVisible(MixerSection.tracks);
    final showBuses = vc.isSectionVisible(MixerSection.buses);
    final showAuxes = vc.isSectionVisible(MixerSection.auxes);
    final showVcas = vc.isSectionVisible(MixerSection.vcas);

    final channels = cb.buildChannels();
    final buses = cb.buildBuses();
    final auxes = cb.buildAuxes();
    final vcas = cb.buildVcas();
    final master = cb.buildMaster();

    // Filter
    final query = vc.filterQuery.toLowerCase();
    List<ultimate.UltimateMixerChannel> filter(List<ultimate.UltimateMixerChannel> list) {
      if (query.isEmpty) return list;
      return list.where((c) => c.name.toLowerCase().contains(query)).toList();
    }

    return Stack(
      children: [
        // Semi-transparent scrim (click to close)
        Positioned.fill(
          child: GestureDetector(
            onTap: () {}, // Don't close on scrim tap — mixer should persist
            child: Container(color: Colors.transparent),
          ),
        ),
        // The floating window
        Positioned(
          left: _position.dx,
          top: _position.dy,
          child: Material(
            color: Colors.transparent,
            child: _buildResizeDetectors(
              child: Container(
                width: _size.width,
                height: _size.height,
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0A0C),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFF4A9EFF).withOpacity(0.3),
                    width: 1,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0xCC000000),
                      blurRadius: 32,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    // Custom title bar (draggable)
                    _buildTitleBar(),
                    // Mixer top bar (controls)
                    MixerTopBar(
                      controller: vc,
                      onSwitchToEdit: widget.onDock,
                      onDetach: widget.onDock,
                      isDetached: true,
                    ),
                    // Mixer body
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: ultimate.UltimateMixer(
                              channels: showTracks ? filter(channels) : const [],
                              buses: showBuses ? filter(buses) : const [],
                              auxes: showAuxes ? filter(auxes) : const [],
                              vcas: showVcas ? filter(vcas) : const [],
                              master: master,
                              compact: vc.stripWidthMode == StripWidthMode.narrow,
                              showInserts: true,
                              showSends: true,
                              showInput: true,
                              showToolbar: false, // MixerTopBar already provides these controls
                              totalTracks: channels.length,
                              totalBuses: buses.length,
                              totalAuxes: auxes.length,
                              totalVcas: vcas.length,
                              visibleStripSections: vc.visibleStripSections,
                              meteringMode: vc.meteringMode,
                              onStripSectionToggle: vc.toggleStripSection,
                              onPresetApply: vc.applyPreset,
                              onMeteringModeChange: vc.setMeteringMode,
                              onStripWidthToggle: vc.toggleStripWidth,
                              onSectionToggle: (name) {
                                final section = MixerSection.values.firstWhere(
                                  (s) => s.name == name,
                                  orElse: () => MixerSection.tracks,
                                );
                                vc.toggleSection(section);
                              },
                              onChannelSelect: cb.onChannelSelect,
                              onVolumeChange: cb.onVolumeChange,
                              onPanChange: cb.onPanChange,
                              onPanChangeEnd: cb.onPanChangeEnd,
                              onPanRightChange: cb.onPanRightChange,
                              onMuteToggle: cb.onMuteToggle,
                              onSoloToggle: cb.onSoloToggle,
                              onArmToggle: cb.onArmToggle,
                              onSendLevelChange: cb.onSendLevelChange,
                              onSendMuteToggle: cb.onSendMuteToggle,
                              onSendPreFaderToggle: cb.onSendPreFaderToggle,
                              onSendDestChange: cb.onSendDestChange,
                              onInsertClick: cb.onInsertClick,
                              onOutputChange: cb.onOutputChange,
                              onPhaseToggle: cb.onPhaseToggle,
                              onGainChange: cb.onGainChange,
                              onAddBus: cb.onAddBus,
                              onChannelReorder: cb.onChannelReorder,
                              onSoloSafeToggle: cb.onSoloSafeToggle,
                              onCommentsChanged: cb.onCommentsChanged,
                              onFolderToggle: cb.onFolderToggle,
                              onEqCurveClick: cb.onEqCurveClick,
                              onWidthChange: cb.onWidthChange,
                            ),
                          ),
                          // Pinned master strip
                          _buildPinnedMaster(master, vc),
                        ],
                      ),
                    ),
                    // Status bar
                    const MixerStatusBar(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTitleBar() {
    return GestureDetector(
      onPanUpdate: (details) {
        setState(() {
          _position += details.delta;
        });
      },
      child: Container(
        height: _titleBarHeight,
        decoration: const BoxDecoration(
          color: Color(0xFF141418),
          borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            // Drag handle
            Icon(Icons.drag_indicator, size: 14, color: Colors.white.withOpacity(0.25)),
            const SizedBox(width: 6),
            Text(
              'MIX',
              style: TextStyle(
                color: const Color(0xFF4A9EFF).withOpacity(0.9),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Floating Mixer',
              style: TextStyle(
                color: Colors.white.withOpacity(0.4),
                fontSize: 10,
                fontWeight: FontWeight.w400,
              ),
            ),
            const Spacer(),
            // Dock button (return to inline)
            _buildTitleButton(
              icon: Icons.vertical_align_bottom,
              tooltip: 'Dock mixer (Cmd+Shift+=)',
              onTap: widget.onDock,
            ),
            const SizedBox(width: 4),
            // Close button
            _buildTitleButton(
              icon: Icons.close,
              tooltip: 'Close',
              onTap: widget.onClose,
              isClose: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTitleButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    bool isClose = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: isClose
                ? Colors.white.withOpacity(0.04)
                : Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Icon(
            icon,
            size: 12,
            color: isClose
                ? const Color(0xFFFF4060).withOpacity(0.7)
                : Colors.white.withOpacity(0.5),
          ),
        ),
      ),
    );
  }

  Widget _buildPinnedMaster(
    ultimate.UltimateMixerChannel master,
    MixerViewController vc,
  ) {
    final cb = widget.callbacks;
    return Container(
      width: 80,
      decoration: BoxDecoration(
        color: const Color(0xFF0E0E12),
        border: Border(
          left: BorderSide(
            color: const Color(0xFFFFD700).withOpacity(0.2),
            width: 1,
          ),
        ),
      ),
      child: ultimate.UltimateMixer(
        channels: const [],
        buses: const [],
        auxes: const [],
        vcas: const [],
        master: master,
        compact: false,
        showInserts: true,
        showSends: true,
        showInput: true,
        showToolbar: false, // MixerTopBar handles controls
        visibleStripSections: vc.visibleStripSections,
        meteringMode: vc.meteringMode,
        onVolumeChange: cb.onVolumeChange,
        onPanChange: cb.onPanChange,
        onPanChangeEnd: cb.onPanChangeEnd,
        onPanRightChange: cb.onPanRightChange,
        onMuteToggle: cb.onMuteToggle,
        onSoloToggle: cb.onSoloToggle,
        onSoloSafeToggle: cb.onSoloSafeToggle,
        onInsertClick: cb.onInsertClick,
        onCommentsChanged: cb.onCommentsChanged,
        onEqCurveClick: cb.onEqCurveClick,
        onWidthChange: cb.onWidthChange,
      ),
    );
  }

  /// Wrap child with edge/corner resize detectors.
  Widget _buildResizeDetectors({required Widget child}) {
    const edgeWidth = 6.0;
    return Stack(
      children: [
        child,
        // Right edge
        Positioned(
          right: 0, top: _titleBarHeight, bottom: 0, width: edgeWidth,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeRight,
            child: GestureDetector(
              onPanUpdate: (d) => _onResize(d.delta, _ResizeEdge.right),
            ),
          ),
        ),
        // Bottom edge
        Positioned(
          left: 0, right: 0, bottom: 0, height: edgeWidth,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeDown,
            child: GestureDetector(
              onPanUpdate: (d) => _onResize(d.delta, _ResizeEdge.bottom),
            ),
          ),
        ),
        // Left edge
        Positioned(
          left: 0, top: _titleBarHeight, bottom: 0, width: edgeWidth,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeLeft,
            child: GestureDetector(
              onPanUpdate: (d) => _onResize(d.delta, _ResizeEdge.left),
            ),
          ),
        ),
        // Bottom-right corner
        Positioned(
          right: 0, bottom: 0, width: 12, height: 12,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeDownRight,
            child: GestureDetector(
              onPanUpdate: (d) => _onResize(d.delta, _ResizeEdge.bottomRight),
            ),
          ),
        ),
        // Bottom-left corner
        Positioned(
          left: 0, bottom: 0, width: 12, height: 12,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeDownLeft,
            child: GestureDetector(
              onPanUpdate: (d) => _onResize(d.delta, _ResizeEdge.bottomLeft),
            ),
          ),
        ),
      ],
    );
  }

  void _onResize(Offset delta, _ResizeEdge edge) {
    setState(() {
      double newW = _size.width;
      double newH = _size.height;
      double newX = _position.dx;
      double newY = _position.dy;

      switch (edge) {
        case _ResizeEdge.right:
          newW += delta.dx;
        case _ResizeEdge.bottom:
          newH += delta.dy;
        case _ResizeEdge.left:
          newW -= delta.dx;
          newX += delta.dx;
        case _ResizeEdge.bottomRight:
          newW += delta.dx;
          newH += delta.dy;
        case _ResizeEdge.bottomLeft:
          newW -= delta.dx;
          newX += delta.dx;
          newH += delta.dy;
      }

      if (newW >= _minWidth) {
        _size = Size(newW, _size.height);
        _position = Offset(newX, _position.dy);
      }
      if (newH >= _minHeight) {
        _size = Size(_size.width, newH);
        _position = Offset(_position.dx, newY);
      }
    });
  }
}

enum _ResizeEdge { right, bottom, left, bottomRight, bottomLeft }
