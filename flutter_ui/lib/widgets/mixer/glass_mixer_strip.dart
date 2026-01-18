/// Glass Mixer Strip - Liquid Glass Theme
///
/// Professional mixer channel strip with Liquid Glass styling:
/// - Frosted glass fader with glow effects
/// - Translucent meter overlays
/// - Glass buttons with specular highlights
/// - Smooth gradients and blur effects

import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/theme_mode_provider.dart';
import '../../theme/liquid_glass_theme.dart';
import 'pro_mixer_strip.dart';

// ═══════════════════════════════════════════════════════════════════════════
// THEME-AWARE MIXER STRIP
// ═══════════════════════════════════════════════════════════════════════════

/// Theme-aware mixer strip that switches between Classic and Glass styles
class ThemeAwareMixerStrip extends StatelessWidget {
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
  final void Function(int index, bool muted)? onSendMuteToggle;
  final void Function(int index, bool preFader)? onSendPreFaderToggle;
  final void Function(int index, String? destination)? onSendDestinationChange;
  final VoidCallback? onOutputClick;
  final VoidCallback? onResetPeaks;
  final void Function(int slotIndex, SlotDestinationType type, String? targetId)?
      onSlotDestinationChange;
  final List<AvailableBus>? availableBuses;
  final List<String>? availablePlugins;

  const ThemeAwareMixerStrip({
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
    this.onSendMuteToggle,
    this.onSendPreFaderToggle,
    this.onSendDestinationChange,
    this.onOutputClick,
    this.onResetPeaks,
    this.onSlotDestinationChange,
    this.availableBuses,
    this.availablePlugins,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;

    if (isGlassMode) {
      return GlassMixerStrip(
        data: data,
        compact: compact,
        onVolumeChange: onVolumeChange,
        onPanChange: onPanChange,
        onMuteToggle: onMuteToggle,
        onSoloToggle: onSoloToggle,
        onArmToggle: onArmToggle,
        onSelect: onSelect,
        onInsertClick: onInsertClick,
        onSendLevelChange: onSendLevelChange,
        onSendMuteToggle: onSendMuteToggle,
        onSendPreFaderToggle: onSendPreFaderToggle,
        onSendDestinationChange: onSendDestinationChange,
        onOutputClick: onOutputClick,
        onResetPeaks: onResetPeaks,
        onSlotDestinationChange: onSlotDestinationChange,
        availableBuses: availableBuses,
        availablePlugins: availablePlugins,
      );
    }

    return ProMixerStrip(
      data: data,
      compact: compact,
      onVolumeChange: onVolumeChange,
      onPanChange: onPanChange,
      onMuteToggle: onMuteToggle,
      onSoloToggle: onSoloToggle,
      onArmToggle: onArmToggle,
      onSelect: onSelect,
      onInsertClick: onInsertClick,
      onSendLevelChange: onSendLevelChange,
      onSendMuteToggle: onSendMuteToggle,
      onSendPreFaderToggle: onSendPreFaderToggle,
      onSendDestinationChange: onSendDestinationChange,
      onOutputClick: onOutputClick,
      onResetPeaks: onResetPeaks,
      onSlotDestinationChange: onSlotDestinationChange,
      availableBuses: availableBuses,
      availablePlugins: availablePlugins,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// GLASS MIXER STRIP
// ═══════════════════════════════════════════════════════════════════════════

class GlassMixerStrip extends StatefulWidget {
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
  final void Function(int index, bool muted)? onSendMuteToggle;
  final void Function(int index, bool preFader)? onSendPreFaderToggle;
  final void Function(int index, String? destination)? onSendDestinationChange;
  final VoidCallback? onOutputClick;
  final VoidCallback? onResetPeaks;
  final void Function(int slotIndex, SlotDestinationType type, String? targetId)?
      onSlotDestinationChange;
  final List<AvailableBus>? availableBuses;
  final List<String>? availablePlugins;

  const GlassMixerStrip({
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
    this.onSendMuteToggle,
    this.onSendPreFaderToggle,
    this.onSendDestinationChange,
    this.onOutputClick,
    this.onResetPeaks,
    this.onSlotDestinationChange,
    this.availableBuses,
    this.availablePlugins,
  });

  @override
  State<GlassMixerStrip> createState() => _GlassMixerStripState();
}

class _GlassMixerStripState extends State<GlassMixerStrip> {
  bool _isDraggingFader = false;
  bool _isDraggingPan = false;
  double _dragStartPan = 0;
  double _dragStartX = 0;

  static const double _width = 90;
  static const double _compactWidth = 75;

  double get width => widget.compact ? _compactWidth : _width;

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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: LiquidGlassTheme.blurLight,
            sigmaY: LiquidGlassTheme.blurLight,
          ),
          child: Container(
            width: width,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: d.selected ? 0.12 : 0.06),
                  Colors.black.withValues(alpha: 0.15),
                ],
              ),
              border: Border(
                right: BorderSide(
                  color: Colors.white.withValues(alpha: 0.1),
                  width: 1,
                ),
                left: d.selected
                    ? BorderSide(color: d.trackColor, width: 2)
                    : BorderSide.none,
              ),
            ),
            child: Column(
              children: [
                _buildGlassHeader(d),
                if (!widget.compact) _buildGlassInputSelector(d),
                _buildGlassInsertSection(d),
                if (!widget.compact) _buildGlassSendSection(d),
                Expanded(child: _buildGlassMeterFader(d)),
                if (!d.isMaster) _buildGlassPanControl(d),
                _buildGlassVolumeDisplay(d),
                _buildGlassButtons(d),
                _buildGlassOutputSelector(d),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGlassHeader(ProMixerStripData d) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        gradient: d.isMaster
            ? LinearGradient(
                colors: [
                  LiquidGlassTheme.accentOrange.withValues(alpha: 0.25),
                  LiquidGlassTheme.accentOrange.withValues(alpha: 0.1),
                ],
              )
            : LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.08),
                  Colors.white.withValues(alpha: 0.03),
                ],
              ),
        border: Border(
          top: BorderSide(color: d.trackColor, width: 3),
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          _GlassTypeIcon(type: d.type),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              d.name,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: LiquidGlassTheme.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassInputSelector(ProMixerStripData d) {
    return Container(
      height: 22,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Icon(Icons.input, size: 11, color: LiquidGlassTheme.textTertiary),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              d.type == 'audio' ? 'Stereo In' : 'No Input',
              style: TextStyle(
                fontSize: 9,
                color: LiquidGlassTheme.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassInsertSection(ProMixerStripData d) {
    final usedSlots = d.inserts.where((s) => !s.isEmpty).toList();
    final slotCount = usedSlots.length + 1;
    final slots = List.generate(slotCount, (i) {
      return i < usedSlots.length
          ? usedSlots[i]
          : ProInsertSlot(id: 'slot-$i', isPreFader: true);
    });

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
      child: Column(
        children: slots.asMap().entries.map((e) {
          final i = e.key;
          final slot = e.value;
          final isPreFader = slot.isPreFader;

          return GestureDetector(
            onTap: () => widget.onInsertClick?.call(i),
            child: Container(
              height: 18,
              margin: const EdgeInsets.only(bottom: 1),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                gradient: slot.isEmpty
                    ? null
                    : LinearGradient(
                        colors: [
                          (isPreFader
                                  ? LiquidGlassTheme.accentBlue
                                  : LiquidGlassTheme.accentOrange)
                              .withValues(alpha: slot.bypassed ? 0.1 : 0.2),
                          Colors.transparent,
                        ],
                      ),
                color: slot.isEmpty ? Colors.black.withValues(alpha: 0.2) : null,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: slot.isEmpty
                      ? Colors.transparent
                      : (isPreFader
                              ? LiquidGlassTheme.accentBlue
                              : LiquidGlassTheme.accentOrange)
                          .withValues(alpha: 0.4),
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
                          ? Colors.white.withValues(alpha: 0.2)
                          : (slot.bypassed
                              ? LiquidGlassTheme.textDisabled
                              : (isPreFader
                                  ? LiquidGlassTheme.accentBlue
                                  : LiquidGlassTheme.accentOrange)),
                      boxShadow: slot.isEmpty || slot.bypassed
                          ? null
                          : [
                              BoxShadow(
                                color: (isPreFader
                                        ? LiquidGlassTheme.accentBlue
                                        : LiquidGlassTheme.accentOrange)
                                    .withValues(alpha: 0.5),
                                blurRadius: 4,
                              ),
                            ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      slot.isEmpty ? '' : slot.name ?? '',
                      style: TextStyle(
                        fontSize: 9,
                        color: slot.bypassed
                            ? LiquidGlassTheme.textDisabled
                            : LiquidGlassTheme.textSecondary,
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

  Widget _buildGlassSendSection(ProMixerStripData d) {
    final slots = List.generate(4, (i) {
      return i < d.sends.length ? d.sends[i] : ProSendSlot(id: 'send-$i');
    });

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
      child: Column(
        children: slots.asMap().entries.map((e) {
          final i = e.key;
          final slot = e.value;

          return GestureDetector(
            onVerticalDragUpdate: (details) {
              if (widget.onSendLevelChange == null || slot.isEmpty) return;
              final newLevel =
                  (slot.level - details.delta.dy * 0.01).clamp(0.0, 1.0);
              widget.onSendLevelChange!(i, newLevel);
            },
            child: Container(
              height: 22,
              margin: const EdgeInsets.only(bottom: 1),
              padding: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: slot.isEmpty
                    ? Colors.black.withValues(alpha: 0.2)
                    : Colors.black.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Row(
                children: [
                  // Mute button
                  GestureDetector(
                    onTap: slot.isEmpty
                        ? null
                        : () => widget.onSendMuteToggle?.call(i, !slot.muted),
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        gradient: slot.muted
                            ? LinearGradient(
                                colors: [
                                  LiquidGlassTheme.accentOrange,
                                  LiquidGlassTheme.accentOrange
                                      .withValues(alpha: 0.7),
                                ],
                              )
                            : null,
                        color: slot.muted
                            ? null
                            : Colors.black.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                        border: Border.all(
                          color: slot.muted
                              ? LiquidGlassTheme.accentOrange
                              : Colors.white.withValues(alpha: 0.2),
                          width: 1,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'M',
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                            color: slot.muted
                                ? Colors.white
                                : LiquidGlassTheme.textTertiary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  // Send level indicator
                  Container(
                    width: 12,
                    height: 10,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: FractionallySizedBox(
                      widthFactor: slot.level,
                      alignment: Alignment.centerLeft,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              (slot.muted
                                      ? LiquidGlassTheme.textTertiary
                                      : LiquidGlassTheme.accentCyan)
                                  .withValues(alpha: 0.6),
                              slot.muted
                                  ? LiquidGlassTheme.textTertiary
                                  : LiquidGlassTheme.accentCyan,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  // Destination
                  Expanded(
                    child: Text(
                      slot.isEmpty ? '' : (slot.destination ?? ''),
                      style: TextStyle(
                        fontSize: 8,
                        color: slot.muted
                            ? LiquidGlassTheme.textTertiary
                            : LiquidGlassTheme.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Pre/Post toggle
                  GestureDetector(
                    onTap: slot.isEmpty
                        ? null
                        : () =>
                            widget.onSendPreFaderToggle?.call(i, !slot.preFader),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 3, vertical: 2),
                      decoration: BoxDecoration(
                        gradient: slot.preFader
                            ? LinearGradient(
                                colors: [
                                  LiquidGlassTheme.accentCyan
                                      .withValues(alpha: 0.3),
                                  LiquidGlassTheme.accentCyan
                                      .withValues(alpha: 0.1),
                                ],
                              )
                            : null,
                        color: slot.preFader
                            ? null
                            : Colors.black.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(2),
                        border: Border.all(
                          color: slot.preFader
                              ? LiquidGlassTheme.accentCyan
                                  .withValues(alpha: 0.5)
                              : Colors.white.withValues(alpha: 0.1),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        slot.preFader ? 'PRE' : 'PST',
                        style: TextStyle(
                          fontSize: 6,
                          fontWeight: FontWeight.w600,
                          color: slot.preFader
                              ? LiquidGlassTheme.accentCyan
                              : LiquidGlassTheme.textTertiary,
                        ),
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

  Widget _buildGlassMeterFader(ProMixerStripData d) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final height = constraints.maxHeight;
          final faderPos = _volumeToFaderPos(d.volume);

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: (_) =>
                setState(() => _isDraggingFader = true),
            onVerticalDragEnd: (_) =>
                setState(() => _isDraggingFader = false),
            onVerticalDragUpdate: (details) =>
                _handleFaderDrag(details, height),
            onDoubleTap: () => widget.onVolumeChange?.call(1.0),
            onLongPress: widget.onResetPeaks,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                child: Stack(
                  children: [
                    // Glass background
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.white.withValues(alpha: 0.05),
                              Colors.black.withValues(alpha: 0.2),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                      ),
                    ),

                    // Meters (behind fader)
                    Positioned(
                      left: 4,
                      top: 4,
                      bottom: 4,
                      width: 20,
                      child: _GlassIntegratedMeter(
                        meters: d.meters,
                        height: height - 8,
                      ),
                    ),

                    // dB scale
                    Positioned(
                      right: 4,
                      top: 4,
                      bottom: 4,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          '+6',
                          '+3',
                          '0',
                          '-3',
                          '-6',
                          '-12',
                          '-24',
                          '-48',
                          '-∞'
                        ]
                            .map((db) => Text(
                                  db,
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: db == '0'
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: db == '0'
                                        ? LiquidGlassTheme.accentBlue
                                        : LiquidGlassTheme.textDisabled,
                                    fontFamily: 'JetBrains Mono',
                                  ),
                                ))
                            .toList(),
                      ),
                    ),

                    // Fader track
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
                                Colors.black.withValues(alpha: 0.4),
                                Colors.black.withValues(alpha: 0.2),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.1),
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
                          color: LiquidGlassTheme.accentBlue,
                          boxShadow: [
                            BoxShadow(
                              color:
                                  LiquidGlassTheme.accentBlue.withValues(alpha: 0.6),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Glass fader thumb
                    Positioned(
                      left: 24,
                      right: 20,
                      bottom: faderPos * (height - 32),
                      child: _GlassFaderThumb(
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
                            color: LiquidGlassTheme.accentRed,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(6),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: LiquidGlassTheme.accentRed
                                    .withValues(alpha: 0.8),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: Center(
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
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildGlassPanControl(ProMixerStripData d) {
    final rotation = d.pan * 135;

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onHorizontalDragStart: (details) {
                setState(() {
                  _isDraggingPan = true;
                  _dragStartPan = d.pan;
                  _dragStartX = details.localPosition.dx;
                });
              },
              onHorizontalDragEnd: (_) =>
                  setState(() => _isDraggingPan = false),
              onHorizontalDragUpdate: (details) {
                if (widget.onPanChange == null) return;
                final isFineTune = HardwareKeyboard.instance.isShiftPressed;
                final sensitivity = isFineTune ? 0.002 : 0.01;
                final delta =
                    (details.localPosition.dx - _dragStartX) * sensitivity;
                final newPan = (_dragStartPan + delta).clamp(-1.0, 1.0);
                widget.onPanChange!(newPan);
              },
              onDoubleTap: () => widget.onPanChange?.call(0),
              child: Center(
                child: ClipOval(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          center: const Alignment(-0.3, -0.3),
                          colors: [
                            Colors.white.withValues(alpha: 0.15),
                            Colors.black.withValues(alpha: 0.15),
                          ],
                        ),
                        border: Border.all(
                          color: _isDraggingPan
                              ? d.trackColor
                              : Colors.white.withValues(alpha: 0.2),
                          width: 1.5,
                        ),
                        boxShadow: _isDraggingPan
                            ? [
                                BoxShadow(
                                  color: d.trackColor.withValues(alpha: 0.4),
                                  blurRadius: 8,
                                ),
                              ]
                            : null,
                      ),
                      child: Stack(
                        children: [
                          CustomPaint(
                            size: const Size(34, 34),
                            painter: _GlassPanArcPainter(
                              pan: d.pan,
                              color: d.trackColor,
                            ),
                          ),
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
                                      color: d.trackColor.withValues(alpha: 0.6),
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
            ),
          ),
          SizedBox(
            width: 28,
            child: Text(
              _formatPan(d.pan),
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                fontFamily: 'JetBrains Mono',
                color: LiquidGlassTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassVolumeDisplay(ProMixerStripData d) {
    final dbStr = _formatDb(d.volume);
    final isOver = d.volume > 1.0;

    return Container(
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isOver
              ? LiquidGlassTheme.accentRed
              : (_isDraggingFader
                  ? LiquidGlassTheme.accentBlue
                  : Colors.white.withValues(alpha: 0.1)),
          width: _isDraggingFader ? 1.5 : 0.5,
        ),
        boxShadow: _isDraggingFader
            ? [
                BoxShadow(
                  color: LiquidGlassTheme.accentBlue.withValues(alpha: 0.3),
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
            fontFamily: 'JetBrains Mono',
            color: isOver
                ? LiquidGlassTheme.accentRed
                : (_isDraggingFader
                    ? LiquidGlassTheme.accentBlue
                    : LiquidGlassTheme.textPrimary),
          ),
        ),
      ),
    );
  }

  Widget _buildGlassButtons(ProMixerStripData d) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: _GlassChannelButton(
              label: 'M',
              isActive: d.muted,
              activeColor: LiquidGlassTheme.accentRed,
              onTap: widget.onMuteToggle,
            ),
          ),
          const SizedBox(width: 3),
          Expanded(
            child: _GlassChannelButton(
              label: 'S',
              isActive: d.soloed,
              activeColor: LiquidGlassTheme.accentYellow,
              onTap: widget.onSoloToggle,
            ),
          ),
          if (!d.isMaster && d.type == 'audio') ...[
            const SizedBox(width: 3),
            Expanded(
              child: _GlassChannelButton(
                label: 'R',
                isActive: d.armed,
                activeColor: LiquidGlassTheme.accentRed,
                onTap: widget.onArmToggle,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGlassOutputSelector(ProMixerStripData d) {
    return GestureDetector(
      onTap: widget.onOutputClick,
      child: Container(
        height: 22,
        margin: const EdgeInsets.all(4),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            Icon(Icons.output, size: 11, color: LiquidGlassTheme.textTertiary),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                d.output ?? (d.isMaster ? 'Out 1-2' : 'Master'),
                style: TextStyle(
                  fontSize: 9,
                  color: LiquidGlassTheme.textSecondary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.keyboard_arrow_down,
                size: 12, color: LiquidGlassTheme.textTertiary),
          ],
        ),
      ),
    );
  }

  void _handleFaderDrag(DragUpdateDetails details, double height) {
    if (widget.onVolumeChange == null) return;

    final isFineTune = HardwareKeyboard.instance.isShiftPressed;
    final dbPerPixel = isFineTune ? 0.05 : 0.3;
    final dbDelta = -details.delta.dy * dbPerPixel;
    final currentDb = _linearToDb(widget.data.volume);
    final newDb = (currentDb + dbDelta).clamp(-60.0, 6.0);
    final newVolume = _dbToLinear(newDb);

    widget.onVolumeChange!(newVolume);
  }

  double _linearToDb(double linear) {
    if (linear <= 0.001) return -60.0;
    final db = 20 * math.log(linear) / math.ln10;
    return db.clamp(-60.0, 6.0);
  }

  double _dbToLinear(double db) {
    if (db <= -60.0) return 0.0;
    return math.pow(10, db / 20).toDouble();
  }

  double _volumeToFaderPos(double volume) {
    if (volume <= 0.001) return 0;
    final db = 20 * math.log(volume) / math.ln10;
    return _dbToFaderPos(db);
  }

  double _dbToFaderPos(double db) {
    if (db <= -60) return 0;
    if (db >= 6) return 1;
    if (db < 0) {
      return 0.7 * (db + 60) / 60;
    } else {
      return 0.7 + 0.3 * db / 6;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// GLASS HELPER WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

class _GlassTypeIcon extends StatelessWidget {
  final String type;

  const _GlassTypeIcon({required this.type});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;

    switch (type) {
      case 'audio':
        icon = Icons.music_note;
        color = LiquidGlassTheme.accentCyan;
        break;
      case 'instrument':
        icon = Icons.piano;
        color = LiquidGlassTheme.accentPurple;
        break;
      case 'bus':
        icon = Icons.alt_route;
        color = LiquidGlassTheme.accentGreen;
        break;
      case 'fx':
        icon = Icons.auto_fix_high;
        color = LiquidGlassTheme.accentOrange;
        break;
      case 'master':
        icon = Icons.surround_sound;
        color = LiquidGlassTheme.accentOrange;
        break;
      default:
        icon = Icons.audiotrack;
        color = LiquidGlassTheme.textSecondary;
    }

    return Icon(icon, size: 13, color: color);
  }
}

class _GlassChannelButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final Color activeColor;
  final VoidCallback? onTap;

  const _GlassChannelButton({
    required this.label,
    required this.isActive,
    required this.activeColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: LiquidGlassTheme.animFast,
        decoration: BoxDecoration(
          gradient: isActive
              ? LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    activeColor,
                    activeColor.withValues(alpha: 0.7),
                  ],
                )
              : LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.08),
                    Colors.black.withValues(alpha: 0.15),
                  ],
                ),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isActive ? activeColor : Colors.white.withValues(alpha: 0.1),
            width: 1,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: activeColor.withValues(alpha: 0.5),
                    blurRadius: 8,
                    spreadRadius: -2,
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isActive ? Colors.white : LiquidGlassTheme.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassFaderThumb extends StatelessWidget {
  final bool isDragging;
  final Color trackColor;

  const _GlassFaderThumb({
    this.isDragging = false,
    required this.trackColor,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: Container(
          height: 32,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: isDragging ? 0.35 : 0.25),
                Colors.white.withValues(alpha: isDragging ? 0.2 : 0.1),
                Colors.black.withValues(alpha: 0.1),
              ],
            ),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isDragging
                  ? trackColor
                  : Colors.white.withValues(alpha: 0.3),
              width: isDragging ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
              if (isDragging)
                BoxShadow(
                  color: trackColor.withValues(alpha: 0.5),
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
                    color: Colors.white.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassIntegratedMeter extends StatelessWidget {
  final MeterData meters;
  final double height;

  const _GlassIntegratedMeter({
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
    return Row(
      children: [
        _GlassMeterBar(
          peakLevel: _linearToNormalized(meters.peakL),
          rmsLevel: _linearToNormalized(meters.rmsL),
          peakHold: _linearToNormalized(meters.peakHoldL),
          isClipping: meters.clipL,
        ),
        const SizedBox(width: 2),
        _GlassMeterBar(
          peakLevel: _linearToNormalized(meters.peakR),
          rmsLevel: _linearToNormalized(meters.rmsR),
          peakHold: _linearToNormalized(meters.peakHoldR),
          isClipping: meters.clipR,
        ),
      ],
    );
  }
}

class _GlassMeterBar extends StatelessWidget {
  final double peakLevel;
  final double rmsLevel;
  final double peakHold;
  final bool isClipping;

  const _GlassMeterBar({
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
              color: Colors.black.withValues(alpha: 0.4),
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
                        colors: [
                          LiquidGlassTheme.accentCyan,
                          LiquidGlassTheme.accentGreen,
                          LiquidGlassTheme.accentYellow,
                          LiquidGlassTheme.accentOrange,
                          LiquidGlassTheme.accentRed,
                        ],
                        stops: const [0.0, 0.5, 0.7, 0.85, 1.0],
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Peak indicator
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
                          color: _getPeakColor(peakLevel).withValues(alpha: 0.6),
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
                            ? LiquidGlassTheme.accentRed
                            : Colors.white,
                        boxShadow: isClipping
                            ? [
                                BoxShadow(
                                  color: LiquidGlassTheme.accentRed
                                      .withValues(alpha: 0.8),
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
    if (level > 0.92) return LiquidGlassTheme.accentRed;
    if (level > 0.85) return LiquidGlassTheme.accentOrange;
    if (level > 0.7) return LiquidGlassTheme.accentYellow;
    return LiquidGlassTheme.accentGreen;
  }
}

class _GlassPanArcPainter extends CustomPainter {
  final double pan;
  final Color color;

  _GlassPanArcPainter({required this.pan, required this.color});

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
        ..color = Colors.white.withValues(alpha: 0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );

    // Active arc
    if (pan.abs() > 0.01) {
      final sweepAngle = pan * 135 * math.pi / 180;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -90 * math.pi / 180,
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
      Paint()..color = Colors.white.withValues(alpha: 0.6),
    );
  }

  @override
  bool shouldRepaint(_GlassPanArcPainter oldDelegate) =>
      pan != oldDelegate.pan || color != oldDelegate.color;
}
