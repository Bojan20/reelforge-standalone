// Pro Channel Strip Widget
//
// Cubase/Pro Tools-style channel strip with:
// - Input selector/trim
// - Insert slots (8 pre-fader + 8 post-fader)
// - 4 send slots with pre/post selection
// - EQ section (enable/edit button)
// - Dynamics section
// - Full fader with motorized feel
// - Pan control
// - Solo/Mute/Record buttons
// - Output routing
// - Metering

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/fluxforge_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// CHANNEL TYPES
// ═══════════════════════════════════════════════════════════════════════════════

/// Channel type
enum ChannelType {
  audio,
  instrument,
  bus,
  aux,
  vca,
  master,
}

/// Insert slot data
class InsertSlot {
  final String? pluginId;
  final String? pluginName;
  final bool bypass;
  final bool prePost; // true = pre-fader, false = post-fader

  const InsertSlot({
    this.pluginId,
    this.pluginName,
    this.bypass = false,
    this.prePost = true,
  });

  bool get isEmpty => pluginId == null;

  InsertSlot copyWith({
    String? pluginId,
    String? pluginName,
    bool? bypass,
    bool? prePost,
  }) {
    return InsertSlot(
      pluginId: pluginId ?? this.pluginId,
      pluginName: pluginName ?? this.pluginName,
      bypass: bypass ?? this.bypass,
      prePost: prePost ?? this.prePost,
    );
  }
}

/// Send slot data
class SendSlot {
  final String? destinationId;
  final String? destinationName;
  final double level; // 0.0 to 1.0
  final double pan; // -1.0 to 1.0
  final bool preFader;
  final bool enabled;

  const SendSlot({
    this.destinationId,
    this.destinationName,
    this.level = 0.75,
    this.pan = 0.0,
    this.preFader = false,
    this.enabled = true,
  });

  bool get isEmpty => destinationId == null;

  double get levelDb {
    if (level <= 0) return double.negativeInfinity;
    return 20 * math.log(level) / math.ln10;
  }

  SendSlot copyWith({
    String? destinationId,
    String? destinationName,
    double? level,
    double? pan,
    bool? preFader,
    bool? enabled,
  }) {
    return SendSlot(
      destinationId: destinationId ?? this.destinationId,
      destinationName: destinationName ?? this.destinationName,
      level: level ?? this.level,
      pan: pan ?? this.pan,
      preFader: preFader ?? this.preFader,
      enabled: enabled ?? this.enabled,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CHANNEL STRIP DATA
// ═══════════════════════════════════════════════════════════════════════════════

/// Complete channel strip state
class ChannelStripData {
  final String id;
  final String name;
  final ChannelType type;
  final Color color;

  // Input
  final String? inputSource;
  final double inputTrim; // -20 to +20 dB

  // Inserts (8 pre + 8 post)
  final List<InsertSlot> insertsPreFader;
  final List<InsertSlot> insertsPostFader;

  // Sends (4 slots)
  final List<SendSlot> sends;

  // EQ
  final bool eqEnabled;
  final bool eqExpanded;

  // Dynamics
  final bool dynamicsEnabled;

  // Fader
  final double faderLevel; // 0.0 to 1.0 (represents -inf to +12dB)
  final double pan; // -1.0 to 1.0

  // Buttons
  final bool muted;
  final bool soloed;
  final bool armed;
  final bool inputMonitor;

  // Output
  final String? outputDestination;

  // Metering
  final double peakLeft;
  final double peakRight;
  final bool clipped;

  const ChannelStripData({
    required this.id,
    required this.name,
    this.type = ChannelType.audio,
    this.color = const Color(0xFF4A9EFF),
    this.inputSource,
    this.inputTrim = 0,
    this.insertsPreFader = const [],
    this.insertsPostFader = const [],
    this.sends = const [],
    this.eqEnabled = false,
    this.eqExpanded = false,
    this.dynamicsEnabled = false,
    this.faderLevel = 0.75, // 0dB
    this.pan = 0,
    this.muted = false,
    this.soloed = false,
    this.armed = false,
    this.inputMonitor = false,
    this.outputDestination,
    this.peakLeft = 0,
    this.peakRight = 0,
    this.clipped = false,
  });

  double get faderDb {
    if (faderLevel <= 0) return double.negativeInfinity;
    // Map 0-1 to -inf to +12dB
    // 0.75 = 0dB
    if (faderLevel < 0.01) return -60;
    return (faderLevel / 0.75 - 1) * 60;
  }

  ChannelStripData copyWith({
    String? id,
    String? name,
    ChannelType? type,
    Color? color,
    String? inputSource,
    double? inputTrim,
    List<InsertSlot>? insertsPreFader,
    List<InsertSlot>? insertsPostFader,
    List<SendSlot>? sends,
    bool? eqEnabled,
    bool? eqExpanded,
    bool? dynamicsEnabled,
    double? faderLevel,
    double? pan,
    bool? muted,
    bool? soloed,
    bool? armed,
    bool? inputMonitor,
    String? outputDestination,
    double? peakLeft,
    double? peakRight,
    bool? clipped,
  }) {
    return ChannelStripData(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      color: color ?? this.color,
      inputSource: inputSource ?? this.inputSource,
      inputTrim: inputTrim ?? this.inputTrim,
      insertsPreFader: insertsPreFader ?? this.insertsPreFader,
      insertsPostFader: insertsPostFader ?? this.insertsPostFader,
      sends: sends ?? this.sends,
      eqEnabled: eqEnabled ?? this.eqEnabled,
      eqExpanded: eqExpanded ?? this.eqExpanded,
      dynamicsEnabled: dynamicsEnabled ?? this.dynamicsEnabled,
      faderLevel: faderLevel ?? this.faderLevel,
      pan: pan ?? this.pan,
      muted: muted ?? this.muted,
      soloed: soloed ?? this.soloed,
      armed: armed ?? this.armed,
      inputMonitor: inputMonitor ?? this.inputMonitor,
      outputDestination: outputDestination ?? this.outputDestination,
      peakLeft: peakLeft ?? this.peakLeft,
      peakRight: peakRight ?? this.peakRight,
      clipped: clipped ?? this.clipped,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CHANNEL STRIP WIDGET
// ═══════════════════════════════════════════════════════════════════════════════

/// Professional channel strip widget
class ChannelStrip extends StatefulWidget {
  final ChannelStripData data;
  final bool expanded;
  final bool selected;
  final ValueChanged<ChannelStripData>? onDataChanged;
  final VoidCallback? onSelect;
  final VoidCallback? onEqEdit;
  final VoidCallback? onInsertEdit;
  final ValueChanged<int>? onSendEdit;

  const ChannelStrip({
    super.key,
    required this.data,
    this.expanded = false,
    this.selected = false,
    this.onDataChanged,
    this.onSelect,
    this.onEqEdit,
    this.onInsertEdit,
    this.onSendEdit,
  });

  @override
  State<ChannelStrip> createState() => _ChannelStripState();
}

class _ChannelStripState extends State<ChannelStrip> {
  bool _faderDragging = false;
  bool _panDragging = false;

  void _updateData(ChannelStripData newData) {
    widget.onDataChanged?.call(newData);
  }

  @override
  Widget build(BuildContext context) {
    final width = widget.expanded ? 120.0 : 60.0;

    return GestureDetector(
      onTap: widget.onSelect,
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: widget.selected
              ? widget.data.color.withValues(alpha: 0.1)
              : FluxForgeTheme.bgSurface,
          border: Border(
            right: BorderSide(color: FluxForgeTheme.borderSubtle),
            left: widget.selected
                ? BorderSide(color: widget.data.color, width: 2)
                : BorderSide.none,
          ),
        ),
        child: Column(
          children: [
            // Channel name
            _buildHeader(),

            // Input section (expanded only)
            if (widget.expanded) _buildInputSection(),

            // Insert slots
            if (widget.expanded) _buildInsertSection(),

            // EQ button
            _buildEqButton(),

            // Dynamics button (expanded only)
            if (widget.expanded) _buildDynamicsButton(),

            // Send slots
            if (widget.expanded) _buildSendSection(),

            // Pan control
            _buildPanControl(),

            // Fader with meter
            Expanded(child: _buildFaderSection()),

            // Solo/Mute/Record buttons
            _buildButtons(),

            // Output selector
            _buildOutputSelector(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 24,
      decoration: BoxDecoration(
        color: widget.data.color,
      ),
      alignment: Alignment.center,
      child: Text(
        widget.data.name,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: FluxForgeTheme.textPrimary,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildInputSection() {
    return Container(
      height: 32,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.data.inputSource ?? 'No Input',
              style: TextStyle(
                fontSize: 9,
                color: FluxForgeTheme.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Trim knob
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgDeep,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '${widget.data.inputTrim.toStringAsFixed(0)}',
                style: TextStyle(
                  fontSize: 8,
                  color: FluxForgeTheme.textTertiary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsertSection() {
    // Dynamic slots: show used + 1 empty, min 1, max 8
    final preSlots = widget.data.insertsPreFader;
    int lastUsed = -1;
    for (int i = 0; i < preSlots.length; i++) {
      if (!preSlots[i].isEmpty) lastUsed = i;
    }
    final visibleSlots = (lastUsed + 2).clamp(1, 8);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      child: Column(
        children: [
          Text(
            'INSERTS',
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.bold,
              color: FluxForgeTheme.textTertiary,
            ),
          ),
          const SizedBox(height: 2),
          for (int i = 0; i < visibleSlots; i++)
            _buildInsertSlot(
              i < preSlots.length ? preSlots[i] : const InsertSlot(),
              i,
              true,
            ),
        ],
      ),
    );
  }

  Widget _buildInsertSlot(InsertSlot slot, int index, bool preFader) {
    return GestureDetector(
      onTap: () => widget.onInsertEdit?.call(),
      child: Container(
        height: 18,
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: slot.isEmpty
              ? FluxForgeTheme.bgDeep
              : slot.bypass
                  ? FluxForgeTheme.bgDeep
                  : FluxForgeTheme.accentCyan.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: slot.bypass
                ? FluxForgeTheme.borderSubtle
                : slot.isEmpty
                    ? FluxForgeTheme.borderSubtle
                    : FluxForgeTheme.accentCyan.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          children: [
            Text(
              '${index + 1}',
              style: TextStyle(
                fontSize: 8,
                color: FluxForgeTheme.textTertiary,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                slot.pluginName ?? '—',
                style: TextStyle(
                  fontSize: 9,
                  color: slot.isEmpty
                      ? FluxForgeTheme.textTertiary
                      : slot.bypass
                          ? FluxForgeTheme.textTertiary
                          : FluxForgeTheme.textSecondary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEqButton() {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: GestureDetector(
        onTap: widget.onEqEdit,
        child: Container(
          height: widget.expanded ? 28 : 20,
          decoration: BoxDecoration(
            color: widget.data.eqEnabled
                ? FluxForgeTheme.accentOrange.withValues(alpha: 0.3)
                : FluxForgeTheme.bgDeep,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: widget.data.eqEnabled
                  ? FluxForgeTheme.accentOrange.withValues(alpha: 0.5)
                  : FluxForgeTheme.borderSubtle,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            'EQ',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: widget.data.eqEnabled
                  ? FluxForgeTheme.accentOrange
                  : FluxForgeTheme.textTertiary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDynamicsButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Container(
        height: 24,
        decoration: BoxDecoration(
          color: widget.data.dynamicsEnabled
              ? FluxForgeTheme.accentPurple.withValues(alpha: 0.3)
              : FluxForgeTheme.bgDeep,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: widget.data.dynamicsEnabled
                ? FluxForgeTheme.accentPurple.withValues(alpha: 0.5)
                : FluxForgeTheme.borderSubtle,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          'DYN',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: widget.data.dynamicsEnabled
                ? FluxForgeTheme.accentPurple
                : FluxForgeTheme.textTertiary,
          ),
        ),
      ),
    );
  }

  Widget _buildSendSection() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      child: Column(
        children: [
          Text(
            'SENDS',
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.bold,
              color: FluxForgeTheme.textTertiary,
            ),
          ),
          const SizedBox(height: 2),
          for (int i = 0; i < 4; i++)
            _buildSendSlot(
              i < widget.data.sends.length
                  ? widget.data.sends[i]
                  : const SendSlot(),
              i,
            ),
        ],
      ),
    );
  }

  Widget _buildSendSlot(SendSlot slot, int index) {
    return GestureDetector(
      onTap: () => widget.onSendEdit?.call(index),
      child: Container(
        height: 20,
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        child: Row(
          children: [
            // Send level
            Container(
              width: 24,
              height: 16,
              decoration: BoxDecoration(
                color: FluxForgeTheme.bgDeep,
                borderRadius: BorderRadius.circular(2),
              ),
              child: Center(
                child: Text(
                  slot.isEmpty
                      ? '—'
                      : slot.levelDb.isFinite
                          ? '${slot.levelDb.toStringAsFixed(0)}'
                          : '-∞',
                  style: TextStyle(
                    fontSize: 8,
                    color: slot.enabled
                        ? FluxForgeTheme.textSecondary
                        : FluxForgeTheme.textTertiary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            // Destination
            Expanded(
              child: Container(
                height: 16,
                padding: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: slot.isEmpty
                      ? FluxForgeTheme.bgDeep
                      : slot.enabled
                          ? FluxForgeTheme.accentGreen.withValues(alpha: 0.2)
                          : FluxForgeTheme.bgDeep,
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(
                    color: slot.enabled && !slot.isEmpty
                        ? FluxForgeTheme.accentGreen.withValues(alpha: 0.3)
                        : FluxForgeTheme.borderSubtle,
                  ),
                ),
                alignment: Alignment.centerLeft,
                child: Text(
                  slot.destinationName ?? '—',
                  style: TextStyle(
                    fontSize: 8,
                    color: slot.isEmpty
                        ? FluxForgeTheme.textTertiary
                        : slot.enabled
                            ? FluxForgeTheme.textSecondary
                            : FluxForgeTheme.textTertiary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            // Pre/Post indicator
            if (!slot.isEmpty)
              Container(
                width: 12,
                alignment: Alignment.center,
                child: Text(
                  slot.preFader ? 'P' : '',
                  style: TextStyle(
                    fontSize: 7,
                    fontWeight: FontWeight.bold,
                    color: FluxForgeTheme.accentBlue,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPanControl() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: GestureDetector(
        onHorizontalDragStart: (_) => setState(() => _panDragging = true),
        onHorizontalDragEnd: (_) => setState(() => _panDragging = false),
        onHorizontalDragUpdate: (details) {
          final delta = details.delta.dx / 50;
          final newPan = (widget.data.pan + delta).clamp(-1.0, 1.0);
          _updateData(widget.data.copyWith(pan: newPan));
        },
        onDoubleTap: () {
          _updateData(widget.data.copyWith(pan: 0));
        },
        child: Container(
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgDeep,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: _panDragging
                  ? FluxForgeTheme.accentBlue
                  : FluxForgeTheme.borderSubtle,
            ),
          ),
          child: Stack(
            children: [
              // Center line
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Container(
                    width: 1,
                    color: FluxForgeTheme.borderSubtle,
                  ),
                ),
              ),
              // Pan indicator
              Positioned(
                left: 4 + (widget.data.pan + 1) / 2 * (widget.expanded ? 104 : 44),
                top: 4,
                bottom: 4,
                child: Container(
                  width: 8,
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.accentBlue,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Label
              Positioned.fill(
                child: Center(
                  child: Text(
                    _panLabel,
                    style: TextStyle(
                      fontSize: 9,
                      color: FluxForgeTheme.textTertiary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _panLabel {
    if (widget.data.pan.abs() < 0.02) return 'C';
    final pct = (widget.data.pan.abs() * 100).round();
    return widget.data.pan < 0 ? 'L$pct' : 'R$pct';
  }

  Widget _buildFaderSection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        children: [
          // Meter
          SizedBox(
            width: widget.expanded ? 20 : 12,
            child: _buildMeter(),
          ),
          const SizedBox(width: 4),
          // Fader
          Expanded(
            child: _buildFader(),
          ),
        ],
      ),
    );
  }

  Widget _buildMeter() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final peakHeight = height * widget.data.peakLeft.clamp(0.0, 1.0);
        final peakHeightR = height * widget.data.peakRight.clamp(0.0, 1.0);

        return Row(
          children: [
            // Left channel
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: FluxForgeTheme.bgDeepest,
                  borderRadius: BorderRadius.circular(1),
                ),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    height: peakHeight,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: FluxForgeTheme.meterGradient,
                        stops: FluxForgeTheme.meterStops,
                      ),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 1),
            // Right channel
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: FluxForgeTheme.bgDeepest,
                  borderRadius: BorderRadius.circular(1),
                ),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    height: peakHeightR,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: FluxForgeTheme.meterGradient,
                        stops: FluxForgeTheme.meterStops,
                      ),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFader() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final faderHeight = 24.0;
        final trackHeight = height - faderHeight;
        final faderPosition = trackHeight * (1 - widget.data.faderLevel);

        return GestureDetector(
          onVerticalDragStart: (_) => setState(() => _faderDragging = true),
          onVerticalDragEnd: (_) => setState(() => _faderDragging = false),
          onVerticalDragUpdate: (details) {
            final delta = -details.delta.dy / trackHeight;
            final newLevel = (widget.data.faderLevel + delta).clamp(0.0, 1.0);
            _updateData(widget.data.copyWith(faderLevel: newLevel));
          },
          onDoubleTap: () {
            _updateData(widget.data.copyWith(faderLevel: 0.75)); // 0dB
          },
          child: Container(
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgDeep,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Stack(
              children: [
                // Track
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Container(
                      width: 4,
                      decoration: BoxDecoration(
                        color: FluxForgeTheme.bgDeepest,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
                // 0dB line
                Positioned(
                  left: 4,
                  right: 4,
                  top: trackHeight * 0.25, // 0dB at 75% fader position
                  child: Container(
                    height: 1,
                    color: FluxForgeTheme.accentGreen.withValues(alpha: 0.5),
                  ),
                ),
                // dB markers
                for (final db in [-48, -24, -12, -6, 0, 6])
                  Positioned(
                    right: 2,
                    top: _dbToPosition(db.toDouble(), trackHeight) - 4,
                    child: Text(
                      '$db',
                      style: TextStyle(
                        fontSize: 7,
                        color: FluxForgeTheme.textTertiary,
                      ),
                    ),
                  ),
                // Fader cap
                Positioned(
                  left: 2,
                  right: 2,
                  top: faderPosition,
                  height: faderHeight,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          FluxForgeTheme.textSecondary,
                          FluxForgeTheme.textTertiary,
                          FluxForgeTheme.textSecondary,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: _faderDragging
                            ? FluxForgeTheme.accentBlue
                            : FluxForgeTheme.borderMedium,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: FluxForgeTheme.bgVoid.withValues(alpha: 0.3),
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Container(
                        width: double.infinity,
                        height: 2,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        color: FluxForgeTheme.bgElevated,
                      ),
                    ),
                  ),
                ),
                // dB value
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 4,
                  child: Center(
                    child: Text(
                      _faderDbLabel,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: FluxForgeTheme.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  double _dbToPosition(double db, double trackHeight) {
    // Map dB to position (0dB at 75% fader)
    // -inf at bottom, +12dB at top
    final normalized = (db + 60) / 72; // -60 to +12 range
    return trackHeight * (1 - normalized);
  }

  String get _faderDbLabel {
    final db = widget.data.faderDb;
    if (!db.isFinite || db < -59) return '-∞';
    return '${db.toStringAsFixed(1)} dB';
  }

  Widget _buildButtons() {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Mute
          _buildChannelButton(
            'M',
            widget.data.muted,
            FluxForgeTheme.accentRed,
            () => _updateData(widget.data.copyWith(muted: !widget.data.muted)),
          ),
          // Solo
          _buildChannelButton(
            'S',
            widget.data.soloed,
            FluxForgeTheme.accentYellow,
            () => _updateData(widget.data.copyWith(soloed: !widget.data.soloed)),
          ),
          // Record
          if (widget.data.type == ChannelType.audio ||
              widget.data.type == ChannelType.instrument)
            _buildChannelButton(
              'R',
              widget.data.armed,
              FluxForgeTheme.accentRed,
              () => _updateData(widget.data.copyWith(armed: !widget.data.armed)),
            ),
        ],
      ),
    );
  }

  Widget _buildChannelButton(
    String label,
    bool active,
    Color activeColor,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: widget.expanded ? 28 : 16,
        height: 20,
        decoration: BoxDecoration(
          color: active ? activeColor : FluxForgeTheme.bgDeep,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: active ? activeColor : FluxForgeTheme.borderSubtle,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: active ? FluxForgeTheme.bgDeepest : FluxForgeTheme.textTertiary,
          ),
        ),
      ),
    );
  }

  Widget _buildOutputSelector() {
    return Container(
      height: 20,
      margin: const EdgeInsets.all(4),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      alignment: Alignment.center,
      child: Text(
        widget.data.outputDestination ?? 'Master',
        style: TextStyle(
          fontSize: 9,
          color: FluxForgeTheme.textSecondary,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
