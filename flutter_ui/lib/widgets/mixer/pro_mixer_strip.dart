/// Pro Mixer Strip - Cubase/Pro Tools Level Quality
///
/// Best-in-class mixer channel strip with:
/// - Smooth fader with fine-tuning (Shift key)
/// - Integrated meter + fader (meter behind fader like Pro Tools)
/// - 8 insert slots (4 pre + 4 post) with drag-drop
/// - 4 send slots with level knobs
/// - Pan control with visual indicator
/// - Mute/Solo/Record arm buttons
/// - LUFS metering (master only)
/// - Track color bar indicator
/// - Compact and extended modes

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/reelforge_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// DATA MODELS
// ═══════════════════════════════════════════════════════════════════════════

/// Insert slot data
class ProInsertSlot {
  final String id;
  final String? name;
  final bool bypassed;
  final bool isPreFader;

  const ProInsertSlot({
    required this.id,
    this.name,
    this.bypassed = false,
    this.isPreFader = true,
  });

  bool get isEmpty => name == null || name!.isEmpty;
}

/// Send slot data
class ProSendSlot {
  final String id;
  final String? destination;
  final double level; // 0.0 to 1.0
  final bool preFader;
  final bool muted;

  const ProSendSlot({
    required this.id,
    this.destination,
    this.level = 0.0,
    this.preFader = false,
    this.muted = false,
  });

  bool get isEmpty => destination == null;
}

/// Metering data
class MeterData {
  final double peakL;
  final double peakR;
  final double rmsL;
  final double rmsR;
  final double peakHoldL;
  final double peakHoldR;
  final bool clipL;
  final bool clipR;

  const MeterData({
    this.peakL = 0,
    this.peakR = 0,
    this.rmsL = 0,
    this.rmsR = 0,
    this.peakHoldL = 0,
    this.peakHoldR = 0,
    this.clipL = false,
    this.clipR = false,
  });

  factory MeterData.fromLinear({
    required double peakL,
    required double peakR,
    double? rmsL,
    double? rmsR,
    double? peakHoldL,
    double? peakHoldR,
  }) {
    return MeterData(
      peakL: peakL,
      peakR: peakR,
      rmsL: rmsL ?? peakL * 0.7,
      rmsR: rmsR ?? peakR * 0.7,
      peakHoldL: peakHoldL ?? peakL,
      peakHoldR: peakHoldR ?? peakR,
      clipL: peakL >= 1.0,
      clipR: peakR >= 1.0,
    );
  }
}

/// Full strip data
class ProMixerStripData {
  final String id;
  final String name;
  final Color trackColor;
  final String type; // 'audio', 'instrument', 'bus', 'fx', 'master'
  final double volume; // 0.0 (off) to 1.5 (+6dB)
  final double pan; // -1.0 to +1.0
  final bool muted;
  final bool soloed;
  final bool armed;
  final bool selected;
  final MeterData meters;
  final List<ProInsertSlot> inserts;
  final List<ProSendSlot> sends;
  final String? output;

  const ProMixerStripData({
    required this.id,
    required this.name,
    this.trackColor = const Color(0xFF5AA8FF),
    this.type = 'audio',
    this.volume = 1.0,
    this.pan = 0,
    this.muted = false,
    this.soloed = false,
    this.armed = false,
    this.selected = false,
    this.meters = const MeterData(),
    this.inserts = const [],
    this.sends = const [],
    this.output,
  });

  bool get isMaster => type == 'master';
}

// ═══════════════════════════════════════════════════════════════════════════
// PRO MIXER STRIP WIDGET
// ═══════════════════════════════════════════════════════════════════════════

/// Slot destination types for Insert/Aux/Bus selection
enum SlotDestinationType { insert, aux, bus }

/// Available buses for routing
class AvailableBus {
  final String id;
  final String name;
  final Color color;
  final bool isFx;

  const AvailableBus({
    required this.id,
    required this.name,
    this.color = const Color(0xFF5AA8FF),
    this.isFx = false,
  });
}

class ProMixerStrip extends StatefulWidget {
  final ProMixerStripData data;
  final bool compact;
  final ValueChanged<double>? onVolumeChange;
  final ValueChanged<double>? onPanChange;
  final VoidCallback? onMuteToggle;
  final VoidCallback? onSoloToggle;
  final VoidCallback? onArmToggle;
  final VoidCallback? onSelect;
  final void Function(int index)? onInsertClick;
  final void Function(int index, double level)? onSendLevelChange;
  final VoidCallback? onOutputClick;
  final VoidCallback? onResetPeaks;
  // New: Insert/Aux/Bus selection
  final void Function(int slotIndex, SlotDestinationType type, String? targetId)? onSlotDestinationChange;
  final List<AvailableBus>? availableBuses;
  final List<String>? availablePlugins;

  const ProMixerStrip({
    super.key,
    required this.data,
    this.compact = false,
    this.onVolumeChange,
    this.onPanChange,
    this.onMuteToggle,
    this.onSoloToggle,
    this.onArmToggle,
    this.onSelect,
    this.onInsertClick,
    this.onSendLevelChange,
    this.onOutputClick,
    this.onResetPeaks,
    this.onSlotDestinationChange,
    this.availableBuses,
    this.availablePlugins,
  });

  @override
  State<ProMixerStrip> createState() => _ProMixerStripState();
}

class _ProMixerStripState extends State<ProMixerStrip> {
  // Drag state
  bool _isDraggingFader = false;
  bool _isDraggingPan = false;
  double _dragStartPan = 0;
  double _dragStartX = 0;

  // Constants
  static const double _width = 90;
  static const double _compactWidth = 75;

  double get width => widget.compact ? _compactWidth : _width;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  String _formatDb(double linear) {
    if (linear <= 0.001) return '-∞';
    final db = 20 * math.log(linear) / math.ln10;
    if (db <= -60) return '-∞';
    if (db >= 0) return '+${db.toStringAsFixed(1)}';
    return db.toStringAsFixed(1);
  }

  String _formatPan(double pan) {
    if (pan.abs() < 0.01) return 'C';
    final percent = (pan.abs() * 100).round();
    return pan < 0 ? 'L$percent' : 'R$percent';
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;

    return GestureDetector(
      onTap: widget.onSelect,
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: d.selected
              ? ReelForgeTheme.accentBlue.withValues(alpha: 0.08)
              : ReelForgeTheme.bgMid,
          border: Border(
            right: BorderSide(color: ReelForgeTheme.borderSubtle, width: 1),
            left: d.selected
                ? BorderSide(color: d.trackColor, width: 2)
                : BorderSide.none,
          ),
        ),
        child: Column(
          children: [
            // Track color bar + name
            _buildHeader(d),

            // Input selector (compact hides this)
            if (!widget.compact) _buildInputSelector(d),

            // Insert slots
            _buildInsertSection(d),

            // Send section (compact shows fewer)
            if (!widget.compact) _buildSendSection(d),

            // Meter + Fader (integrated) - MAIN SECTION
            Expanded(child: _buildMeterFader(d)),

            // Pan control
            if (!d.isMaster) _buildPanControl(d),

            // Volume display
            _buildVolumeDisplay(d),

            // Solo/Mute/Arm buttons
            _buildButtons(d),

            // Output routing
            _buildOutputSelector(d),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ProMixerStripData d) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        gradient: d.isMaster
            ? LinearGradient(
                colors: [
                  ReelForgeTheme.accentOrange.withValues(alpha: 0.2),
                  ReelForgeTheme.accentOrange.withValues(alpha: 0.1),
                ],
              )
            : null,
        color: d.isMaster ? null : ReelForgeTheme.bgSurface,
        border: Border(
          top: BorderSide(color: d.trackColor, width: 3),
          bottom: BorderSide(color: ReelForgeTheme.borderSubtle),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          // Type icon
          _TypeIcon(type: d.type),
          const SizedBox(width: 4),
          // Name
          Expanded(
            child: Text(
              d.name,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: ReelForgeTheme.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputSelector(ProMixerStripData d) {
    return Container(
      height: 22,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: ReelForgeTheme.borderSubtle, width: 0.5),
      ),
      child: Row(
        children: [
          Icon(Icons.input, size: 11, color: ReelForgeTheme.textTertiary),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              d.type == 'audio' ? 'Stereo In' : 'No Input',
              style: TextStyle(fontSize: 9, color: ReelForgeTheme.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsertSection(ProMixerStripData d) {
    // Dynamic slots: show used slots + 1 empty slot for adding new plugins
    // Always show at least 1 empty slot
    final usedSlots = d.inserts.where((s) => !s.isEmpty).toList();
    final slotCount = usedSlots.length + 1; // +1 for empty "add" slot
    final slots = List.generate(slotCount, (i) {
      return i < usedSlots.length
          ? usedSlots[i]
          : ProInsertSlot(id: 'slot-$i', isPreFader: true);
    });

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ReelForgeTheme.borderSubtle),
        ),
      ),
      child: Column(
        children: slots.asMap().entries.map((e) {
          final i = e.key;
          final slot = e.value;
          final isPreFader = slot.isPreFader;

          return GestureDetector(
            onTap: () => _showSlotSelector(context, i, slot, isPreFader),
            onSecondaryTap: () => _showSlotSelector(context, i, slot, isPreFader),
            child: Container(
              height: 18,
              margin: const EdgeInsets.only(bottom: 1),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: slot.isEmpty
                    ? ReelForgeTheme.bgDeepest
                    : (slot.bypassed
                        ? ReelForgeTheme.bgDeep
                        : ReelForgeTheme.bgSurface),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: slot.isEmpty
                      ? Colors.transparent
                      : (isPreFader
                          ? ReelForgeTheme.accentBlue.withValues(alpha: 0.5)
                          : ReelForgeTheme.accentOrange.withValues(alpha: 0.5)),
                  width: 0.5,
                ),
              ),
              child: Row(
                children: [
                  // Pre/Post indicator
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: slot.isEmpty
                          ? ReelForgeTheme.borderSubtle
                          : (slot.bypassed
                              ? ReelForgeTheme.textDisabled
                              : (isPreFader
                                  ? ReelForgeTheme.accentBlue
                                  : ReelForgeTheme.accentOrange)),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      slot.isEmpty ? '' : slot.name ?? '',
                      style: TextStyle(
                        fontSize: 9,
                        color: slot.bypassed
                            ? ReelForgeTheme.textDisabled
                            : ReelForgeTheme.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Show popup to select Insert/Aux/Bus destination
  void _showSlotSelector(BuildContext context, int slotIndex, ProInsertSlot slot, bool isPreFader) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final Offset offset = button.localToGlobal(Offset.zero);

    showMenu<dynamic>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx + 85, // Right of the strip
        offset.dy + (slotIndex * 19) + 60,
        offset.dx + 300,
        offset.dy + 200,
      ),
      color: ReelForgeTheme.bgSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: ReelForgeTheme.borderMedium),
      ),
      items: [
        // Header
        PopupMenuItem(
          enabled: false,
          height: 28,
          child: Text(
            isPreFader ? 'PRE-FADER SLOT ${slotIndex + 1}' : 'POST-FADER SLOT ${slotIndex - 3}',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: ReelForgeTheme.textTertiary,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const PopupMenuDivider(height: 1),

        // INSERT section
        PopupMenuItem(
          enabled: false,
          height: 24,
          child: Row(
            children: [
              Icon(Icons.add_box_outlined, size: 12, color: ReelForgeTheme.accentBlue),
              const SizedBox(width: 6),
              Text('INSERT', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: ReelForgeTheme.accentBlue)),
            ],
          ),
        ),
        ..._buildPluginMenuItems(slotIndex),

        const PopupMenuDivider(height: 1),

        // AUX section
        PopupMenuItem(
          enabled: false,
          height: 24,
          child: Row(
            children: [
              Icon(Icons.call_split, size: 12, color: ReelForgeTheme.accentCyan),
              const SizedBox(width: 6),
              Text('AUX SEND', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: ReelForgeTheme.accentCyan)),
            ],
          ),
        ),
        ..._buildAuxMenuItems(slotIndex),

        const PopupMenuDivider(height: 1),

        // BUS section
        PopupMenuItem(
          enabled: false,
          height: 24,
          child: Row(
            children: [
              Icon(Icons.alt_route, size: 12, color: ReelForgeTheme.accentGreen),
              const SizedBox(width: 6),
              Text('BUS', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: ReelForgeTheme.accentGreen)),
            ],
          ),
        ),
        ..._buildBusMenuItems(slotIndex),

        // Clear option
        if (!slot.isEmpty) ...[
          const PopupMenuDivider(height: 1),
          PopupMenuItem(
            onTap: () {
              widget.onSlotDestinationChange?.call(slotIndex, SlotDestinationType.insert, null);
            },
            height: 32,
            child: Row(
              children: [
                Icon(Icons.clear, size: 14, color: ReelForgeTheme.accentRed),
                const SizedBox(width: 8),
                Text('Clear Slot', style: TextStyle(fontSize: 11, color: ReelForgeTheme.accentRed)),
              ],
            ),
          ),
        ],
      ],
    );
  }

  List<PopupMenuItem> _buildPluginMenuItems(int slotIndex) {
    final plugins = widget.availablePlugins ?? [
      'RF-EQ 64',
      'RF-COMP',
      'RF-LIMIT',
      'RF-GATE',
      'RF-VERB',
      'RF-DELAY',
      'RF-SAT',
    ];

    return plugins.map((plugin) => PopupMenuItem(
      onTap: () {
        // Insert plugin and auto-open editor (handled by onSlotDestinationChange)
        widget.onSlotDestinationChange?.call(slotIndex, SlotDestinationType.insert, plugin);
      },
      height: 28,
      child: Row(
        children: [
          const SizedBox(width: 18),
          Text(plugin, style: TextStyle(fontSize: 11, color: ReelForgeTheme.textPrimary)),
        ],
      ),
    )).toList();
  }

  List<PopupMenuItem> _buildAuxMenuItems(int slotIndex) {
    final buses = widget.availableBuses?.where((b) => b.isFx).toList() ?? [
      const AvailableBus(id: 'fx1', name: 'FX 1 - Reverb', color: Color(0xFF5DADE2), isFx: true),
      const AvailableBus(id: 'fx2', name: 'FX 2 - Delay', color: Color(0xFF48C9B0), isFx: true),
      const AvailableBus(id: 'fx3', name: 'FX 3 - Chorus', color: Color(0xFFAF7AC5), isFx: true),
    ];

    return buses.map((bus) => PopupMenuItem(
      onTap: () {
        widget.onSlotDestinationChange?.call(slotIndex, SlotDestinationType.aux, bus.id);
      },
      height: 28,
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(left: 4, right: 8),
            decoration: BoxDecoration(
              color: bus.color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Text(bus.name, style: TextStyle(fontSize: 11, color: ReelForgeTheme.textPrimary)),
        ],
      ),
    )).toList();
  }

  List<PopupMenuItem> _buildBusMenuItems(int slotIndex) {
    final buses = widget.availableBuses?.where((b) => !b.isFx).toList() ?? [
      const AvailableBus(id: 'bus1', name: 'Bus 1 - Drums', color: Color(0xFFE74C3C)),
      const AvailableBus(id: 'bus2', name: 'Bus 2 - Bass', color: Color(0xFFF39C12)),
      const AvailableBus(id: 'bus3', name: 'Bus 3 - Vox', color: Color(0xFF27AE60)),
      const AvailableBus(id: 'bus4', name: 'Bus 4 - Keys', color: Color(0xFF9B59B6)),
    ];

    return buses.map((bus) => PopupMenuItem(
      onTap: () {
        widget.onSlotDestinationChange?.call(slotIndex, SlotDestinationType.bus, bus.id);
      },
      height: 28,
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(left: 4, right: 8),
            decoration: BoxDecoration(
              color: bus.color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Text(bus.name, style: TextStyle(fontSize: 11, color: ReelForgeTheme.textPrimary)),
        ],
      ),
    )).toList();
  }

  Widget _buildSendSection(ProMixerStripData d) {
    final slots = List.generate(4, (i) {
      return i < d.sends.length ? d.sends[i] : ProSendSlot(id: 'send-$i');
    });

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ReelForgeTheme.borderSubtle),
        ),
      ),
      child: Column(
        children: slots.asMap().entries.map((e) {
          final i = e.key;
          final slot = e.value;

          return GestureDetector(
            onVerticalDragUpdate: (details) {
              if (widget.onSendLevelChange == null || slot.isEmpty) return;
              final newLevel = (slot.level - details.delta.dy * 0.01).clamp(0.0, 1.0);
              widget.onSendLevelChange!(i, newLevel);
            },
            child: Container(
              height: 18,
              margin: const EdgeInsets.only(bottom: 1),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: slot.isEmpty
                    ? ReelForgeTheme.bgDeepest
                    : ReelForgeTheme.bgSurface,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Row(
                children: [
                  // Send level indicator
                  Container(
                    width: 14,
                    height: 10,
                    decoration: BoxDecoration(
                      color: ReelForgeTheme.bgDeepest,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: FractionallySizedBox(
                      widthFactor: slot.level,
                      alignment: Alignment.centerLeft,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              ReelForgeTheme.accentCyan.withValues(alpha: 0.6),
                              ReelForgeTheme.accentCyan,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      slot.isEmpty ? '' : slot.destination ?? '',
                      style: TextStyle(
                        fontSize: 9,
                        color: ReelForgeTheme.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (slot.preFader && !slot.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: ReelForgeTheme.accentCyan.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: Text(
                        'PRE',
                        style: TextStyle(
                          fontSize: 7,
                          fontWeight: FontWeight.w600,
                          color: ReelForgeTheme.accentCyan,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FADER + METER SECTION (Main Feature)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMeterFader(ProMixerStripData d) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final height = constraints.maxHeight;
          // Cubase-style: ALWAYS use widget.data.volume directly - no animation tricks
          final faderPos = _volumeToFaderPos(d.volume);

          return GestureDetector(
            behavior: HitTestBehavior.opaque, // Capture all touch events
            onVerticalDragStart: (details) {
              setState(() {
                _isDraggingFader = true;
              });
            },
            onVerticalDragEnd: (_) {
              setState(() => _isDraggingFader = false);
            },
            onVerticalDragUpdate: (details) => _handleFaderDrag(details, height),
            onDoubleTap: () {
              // Reset to 0dB (unity gain)
              widget.onVolumeChange?.call(1.0);
            },
            onLongPress: widget.onResetPeaks,
            child: Stack(
              children: [
                // Background track
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: ReelForgeTheme.bgDeepest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),

                // Meters (behind fader)
                Positioned(
                  left: 4,
                  top: 4,
                  bottom: 4,
                  width: 20,
                  child: _IntegratedMeter(
                    meters: d.meters,
                    height: height - 8,
                  ),
                ),

                // dB scale lines
                ..._buildDbScaleLines(height),

                // dB scale labels
                Positioned(
                  right: 4,
                  top: 4,
                  bottom: 4,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: ['+6', '+3', '0', '-3', '-6', '-12', '-24', '-48', '-∞']
                        .map((db) => Text(
                              db,
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: db == '0' ? FontWeight.w600 : FontWeight.w400,
                                color: db == '0'
                                    ? ReelForgeTheme.accentBlue
                                    : ReelForgeTheme.textDisabled,
                              ),
                            ))
                        .toList(),
                  ),
                ),

                // Fader track (center line)
                Positioned(
                  left: 28,
                  right: 24,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Container(
                      width: 6,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            ReelForgeTheme.bgDeep,
                            ReelForgeTheme.bgSurface,
                            ReelForgeTheme.bgDeep,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                          color: ReelForgeTheme.borderMedium,
                          width: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),

                // 0dB reference line
                Positioned(
                  left: 24,
                  right: 20,
                  top: height * (1 - _dbToFaderPos(0)),
                  child: Container(
                    height: 2,
                    decoration: BoxDecoration(
                      color: ReelForgeTheme.accentBlue,
                      boxShadow: [
                        BoxShadow(
                          color: ReelForgeTheme.accentBlue.withValues(alpha: 0.5),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                ),

                // Fader thumb
                Positioned(
                  left: 24,
                  right: 20,
                  bottom: faderPos * (height - 32),
                  child: _FaderThumb(
                    isDragging: _isDraggingFader,
                    trackColor: d.trackColor,
                  ),
                ),

                // Clip indicators
                if (d.meters.clipL || d.meters.clipR)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: ReelForgeTheme.clipRed,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        boxShadow: ReelForgeTheme.glowShadow(
                          ReelForgeTheme.clipRed,
                          intensity: 0.8,
                        ),
                      ),
                      child: const Center(
                        child: Text(
                          'CLIP',
                          style: TextStyle(
                            fontSize: 6,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildDbScaleLines(double height) {
    final dbValues = [6.0, 3.0, 0.0, -3.0, -6.0, -12.0, -24.0, -48.0];
    return dbValues.map((db) {
      final y = height * (1 - _dbToFaderPos(db));
      final isMajor = db == 0 || db == -12 || db == -24;
      return Positioned(
        left: 24,
        right: 24,
        top: y - 0.5,
        child: Container(
          height: 1,
          color: isMajor
              ? ReelForgeTheme.borderMedium
              : ReelForgeTheme.borderSubtle,
        ),
      );
    }).toList();
  }

  void _handleFaderDrag(DragUpdateDetails details, double height) {
    if (widget.onVolumeChange == null) return;

    // Cubase-style fader: work in dB domain for perceptually uniform response
    // Convert pixel delta to dB delta, then back to linear

    final isFineTune = HardwareKeyboard.instance.isShiftPressed;

    // dB per pixel: full fader travel = 66dB range (-60 to +6)
    // Normal: ~0.3 dB/pixel, Fine: ~0.05 dB/pixel
    final dbPerPixel = isFineTune ? 0.05 : 0.3;

    // Negative delta.dy = moving up = increase dB
    final dbDelta = -details.delta.dy * dbPerPixel;

    // Convert current volume to dB
    final currentDb = _linearToDb(widget.data.volume);

    // Apply delta in dB domain
    final newDb = (currentDb + dbDelta).clamp(-60.0, 6.0);

    // Convert back to linear
    final newVolume = _dbToLinear(newDb);

    widget.onVolumeChange!(newVolume);
  }

  /// Convert linear amplitude to dB
  double _linearToDb(double linear) {
    if (linear <= 0.001) return -60.0;
    final db = 20 * math.log(linear) / math.ln10;
    return db.clamp(-60.0, 6.0);
  }

  /// Convert dB to linear amplitude
  double _dbToLinear(double db) {
    if (db <= -60.0) return 0.0;
    return math.pow(10, db / 20).toDouble();
  }

  Widget _buildPanControl(ProMixerStripData d) {
    final rotation = d.pan * 135; // -135 to +135 degrees

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        children: [
          // Pan knob
          Expanded(
            child: GestureDetector(
              onHorizontalDragStart: (details) {
                setState(() {
                  _isDraggingPan = true;
                  _dragStartPan = d.pan;
                  _dragStartX = details.localPosition.dx;
                });
              },
              onHorizontalDragEnd: (_) => setState(() => _isDraggingPan = false),
              onHorizontalDragUpdate: (details) {
                if (widget.onPanChange == null) return;
                final isFineTune = HardwareKeyboard.instance.isShiftPressed;
                final sensitivity = isFineTune ? 0.002 : 0.01;
                final delta = (details.localPosition.dx - _dragStartX) * sensitivity;
                final newPan = (_dragStartPan + delta).clamp(-1.0, 1.0);
                widget.onPanChange!(newPan);
              },
              onDoubleTap: () => widget.onPanChange?.call(0),
              child: Center(
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      center: const Alignment(-0.3, -0.3),
                      colors: [
                        ReelForgeTheme.bgSurface,
                        ReelForgeTheme.bgDeepest,
                      ],
                    ),
                    border: Border.all(
                      color: _isDraggingPan
                          ? ReelForgeTheme.accentBlue
                          : ReelForgeTheme.borderMedium,
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                      if (_isDraggingPan)
                        BoxShadow(
                          color: ReelForgeTheme.accentBlue.withValues(alpha: 0.3),
                          blurRadius: 8,
                        ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      // Position indicator arc
                      CustomPaint(
                        size: const Size(34, 34),
                        painter: _PanArcPainter(
                          pan: d.pan,
                          color: d.trackColor,
                        ),
                      ),
                      // Center indicator
                      Center(
                        child: Transform.rotate(
                          angle: rotation * math.pi / 180,
                          child: Container(
                            width: 3,
                            height: 12,
                            decoration: BoxDecoration(
                              color: d.trackColor,
                              borderRadius: BorderRadius.circular(1.5),
                              boxShadow: [
                                BoxShadow(
                                  color: d.trackColor.withValues(alpha: 0.5),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Pan value
          SizedBox(
            width: 28,
            child: Text(
              _formatPan(d.pan),
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
                color: ReelForgeTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVolumeDisplay(ProMixerStripData d) {
    final dbStr = _formatDb(d.volume);
    final isOver = d.volume > 1.0;

    return Container(
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isOver
              ? ReelForgeTheme.accentRed
              : (_isDraggingFader
                  ? ReelForgeTheme.accentBlue
                  : ReelForgeTheme.borderSubtle),
          width: _isDraggingFader ? 1.5 : 0.5,
        ),
        boxShadow: _isDraggingFader
            ? [
                BoxShadow(
                  color: ReelForgeTheme.accentBlue.withValues(alpha: 0.2),
                  blurRadius: 6,
                ),
              ]
            : null,
      ),
      child: Center(
        child: Text(
          '$dbStr dB',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            fontFamily: 'monospace',
            color: isOver
                ? ReelForgeTheme.accentRed
                : (_isDraggingFader
                    ? ReelForgeTheme.accentBlue
                    : ReelForgeTheme.textPrimary),
          ),
        ),
      ),
    );
  }

  Widget _buildButtons(ProMixerStripData d) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: Row(
        children: [
          // Mute
          Expanded(
            child: _ChannelButton(
              label: 'M',
              isActive: d.muted,
              activeColor: ReelForgeTheme.accentRed,
              onTap: widget.onMuteToggle,
            ),
          ),
          const SizedBox(width: 3),
          // Solo
          Expanded(
            child: _ChannelButton(
              label: 'S',
              isActive: d.soloed,
              activeColor: ReelForgeTheme.accentYellow,
              onTap: widget.onSoloToggle,
            ),
          ),
          // Record arm (audio tracks only)
          if (!d.isMaster && d.type == 'audio') ...[
            const SizedBox(width: 3),
            Expanded(
              child: _ChannelButton(
                label: 'R',
                isActive: d.armed,
                activeColor: ReelForgeTheme.accentRed,
                onTap: widget.onArmToggle,
                pulsing: d.armed,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOutputSelector(ProMixerStripData d) {
    return GestureDetector(
      onTap: widget.onOutputClick,
      child: Container(
        height: 22,
        margin: const EdgeInsets.all(4),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: ReelForgeTheme.bgDeepest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: ReelForgeTheme.borderSubtle, width: 0.5),
        ),
        child: Row(
          children: [
            Icon(Icons.output, size: 11, color: ReelForgeTheme.textTertiary),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                d.output ?? (d.isMaster ? 'Out 1-2' : 'Master'),
                style: TextStyle(fontSize: 9, color: ReelForgeTheme.textSecondary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.keyboard_arrow_down, size: 12, color: ReelForgeTheme.textTertiary),
          ],
        ),
      ),
    );
  }

  double _volumeToFaderPos(double volume) {
    // Non-linear fader curve - 0dB at ~70% of fader travel
    if (volume <= 0.001) return 0;
    final db = 20 * math.log(volume) / math.ln10;
    return _dbToFaderPos(db);
  }

  double _dbToFaderPos(double db) {
    if (db <= -60) return 0;
    if (db >= 6) return 1;
    // Map -60dB..+6dB to 0..1 with 0dB at 0.7
    if (db < 0) {
      return 0.7 * (db + 60) / 60;
    } else {
      return 0.7 + 0.3 * db / 6;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// HELPER WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

class _TypeIcon extends StatelessWidget {
  final String type;

  const _TypeIcon({required this.type});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;

    switch (type) {
      case 'audio':
        icon = Icons.music_note;
        color = ReelForgeTheme.accentCyan;
        break;
      case 'instrument':
        icon = Icons.piano;
        color = ReelForgeTheme.accentPurple;
        break;
      case 'bus':
        icon = Icons.alt_route;
        color = ReelForgeTheme.accentGreen;
        break;
      case 'fx':
        icon = Icons.auto_fix_high;
        color = ReelForgeTheme.accentOrange;
        break;
      case 'master':
        icon = Icons.surround_sound;
        color = ReelForgeTheme.accentOrange;
        break;
      default:
        icon = Icons.audiotrack;
        color = ReelForgeTheme.textSecondary;
    }

    return Icon(icon, size: 13, color: color);
  }
}

class _ChannelButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final Color activeColor;
  final VoidCallback? onTap;
  final bool pulsing;

  const _ChannelButton({
    required this.label,
    required this.isActive,
    required this.activeColor,
    this.onTap,
    this.pulsing = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: ReelForgeTheme.fastDuration,
        curve: ReelForgeTheme.smoothCurve,
        decoration: BoxDecoration(
          gradient: isActive
              ? LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    activeColor,
                    activeColor.withValues(alpha: 0.8),
                  ],
                )
              : null,
          color: isActive ? null : ReelForgeTheme.bgDeepest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isActive ? activeColor : ReelForgeTheme.borderSubtle,
            width: 1,
          ),
          boxShadow: isActive
              ? ReelForgeTheme.glowShadow(activeColor, intensity: 0.4)
              : null,
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isActive
                  ? ReelForgeTheme.textInverse
                  : ReelForgeTheme.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}

class _FaderThumb extends StatelessWidget {
  final bool isDragging;
  final Color trackColor;

  const _FaderThumb({
    this.isDragging = false,
    required this.trackColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDragging
              ? [
                  const Color(0xFFE8E8F0),
                  const Color(0xFFD0D0D8),
                  const Color(0xFFB8B8C0),
                ]
              : [
                  const Color(0xFFD8D8E0),
                  const Color(0xFFC0C0C8),
                  const Color(0xFFA8A8B0),
                ],
        ),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isDragging ? trackColor : ReelForgeTheme.borderMedium,
          width: isDragging ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
          if (isDragging)
            BoxShadow(
              color: trackColor.withValues(alpha: 0.4),
              blurRadius: 12,
              spreadRadius: 2,
            ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Grip lines
          for (int i = 0; i < 3; i++)
            Container(
              width: 18,
              height: 2,
              margin: const EdgeInsets.symmetric(vertical: 1),
              decoration: BoxDecoration(
                color: ReelForgeTheme.bgDeep,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
        ],
      ),
    );
  }
}

class _IntegratedMeter extends StatelessWidget {
  final MeterData meters;
  final double height;

  const _IntegratedMeter({
    required this.meters,
    required this.height,
  });

  double _linearToNormalized(double linear) {
    if (linear <= 0.001) return 0;
    final db = 20 * math.log(linear) / math.ln10;
    if (db <= -60) return 0;
    if (db >= 6) return 1;
    return (db + 60) / 66;
  }

  @override
  Widget build(BuildContext context) {
    final pctPeakL = _linearToNormalized(meters.peakL);
    final pctPeakR = _linearToNormalized(meters.peakR);
    final pctRmsL = _linearToNormalized(meters.rmsL);
    final pctRmsR = _linearToNormalized(meters.rmsR);
    final pctHoldL = _linearToNormalized(meters.peakHoldL);
    final pctHoldR = _linearToNormalized(meters.peakHoldR);

    return Row(
      children: [
        // Left meter
        _MeterBar(
          peakLevel: pctPeakL,
          rmsLevel: pctRmsL,
          peakHold: pctHoldL,
          isClipping: meters.clipL,
        ),
        const SizedBox(width: 2),
        // Right meter
        _MeterBar(
          peakLevel: pctPeakR,
          rmsLevel: pctRmsR,
          peakHold: pctHoldR,
          isClipping: meters.clipR,
        ),
      ],
    );
  }
}

class _MeterBar extends StatelessWidget {
  final double peakLevel;
  final double rmsLevel;
  final double peakHold;
  final bool isClipping;

  const _MeterBar({
    required this.peakLevel,
    required this.rmsLevel,
    required this.peakHold,
    this.isClipping = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final h = constraints.maxHeight;

          return Container(
            decoration: BoxDecoration(
              color: ReelForgeTheme.bgDeepest,
              borderRadius: BorderRadius.circular(2),
            ),
            child: Stack(
              children: [
                // RMS fill with gradient
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: h * rmsLevel,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: const [
                          Color(0xFF22C55E), // Green
                          Color(0xFF22C55E),
                          Color(0xFF84CC16), // Lime
                          Color(0xFFEAB308), // Yellow
                          Color(0xFFF97316), // Orange
                          Color(0xFFEF4444), // Red
                        ],
                        stops: const [0.0, 0.5, 0.7, 0.85, 0.92, 1.0],
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Peak indicator (brighter line at top of peak)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: h * peakLevel - 2,
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: _getPeakColor(peakLevel),
                      borderRadius: BorderRadius.circular(1),
                      boxShadow: [
                        BoxShadow(
                          color: _getPeakColor(peakLevel).withValues(alpha: 0.5),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                ),
                // Peak hold line
                if (peakHold > 0.01)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: h * peakHold - 1,
                    child: Container(
                      height: 2,
                      decoration: BoxDecoration(
                        color: isClipping
                            ? ReelForgeTheme.clipRed
                            : ReelForgeTheme.peakHoldColor,
                        boxShadow: isClipping
                            ? [
                                BoxShadow(
                                  color: ReelForgeTheme.clipRed.withValues(alpha: 0.8),
                                  blurRadius: 4,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Color _getPeakColor(double level) {
    if (level > 0.92) return ReelForgeTheme.accentRed;
    if (level > 0.85) return ReelForgeTheme.accentOrange;
    if (level > 0.7) return ReelForgeTheme.accentYellow;
    return ReelForgeTheme.accentGreen;
  }
}

/// Custom painter for pan position arc
class _PanArcPainter extends CustomPainter {
  final double pan;
  final Color color;

  _PanArcPainter({required this.pan, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    // Background arc
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -225 * math.pi / 180,
      270 * math.pi / 180,
      false,
      Paint()
        ..color = ReelForgeTheme.borderSubtle
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );

    // Active arc (from center to current position)
    if (pan.abs() > 0.01) {
      final sweepAngle = pan * 135 * math.pi / 180;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -90 * math.pi / 180, // Start from top
        sweepAngle,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    }

    // Center marker
    canvas.drawCircle(
      Offset(center.dx, center.dy - radius),
      2,
      Paint()..color = ReelForgeTheme.textSecondary,
    );
  }

  @override
  bool shouldRepaint(_PanArcPainter oldDelegate) =>
      pan != oldDelegate.pan || color != oldDelegate.color;
}
