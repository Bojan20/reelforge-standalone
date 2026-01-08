/// Channel Strip Widget
///
/// Cubase-style channel strip for the right zone:
/// - ProFader with GPU-accelerated metering
/// - Pan control
/// - Inserts (8 slots)
/// - Sends (8 slots)
/// - EQ curve preview
/// - Output routing
/// - LUFS metering (master only)

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/reelforge_theme.dart';

// ============ Types ============

/// Insert slot data
class InsertSlotData {
  final String id;
  final String? pluginName;
  final bool bypassed;

  const InsertSlotData({
    required this.id,
    this.pluginName,
    this.bypassed = false,
  });
}

/// Send slot data
class SendSlotData {
  final String id;
  final String? destination;
  final double level; // -inf to +6 dB
  final bool preFader;
  final bool bypassed;

  const SendSlotData({
    required this.id,
    this.destination,
    this.level = double.negativeInfinity,
    this.preFader = false,
    this.bypassed = false,
  });
}

/// EQ band data
class EQBandData {
  final double frequency;
  final double gain;
  final double q;
  final String type; // 'lowshelf', 'highshelf', 'peak', 'lowpass', 'highpass'
  final bool enabled;

  const EQBandData({
    required this.frequency,
    this.gain = 0,
    this.q = 1,
    this.type = 'peak',
    this.enabled = true,
  });
}

/// LUFS metering data
class LUFSData {
  final double momentary;
  final double shortTerm;
  final double integrated;
  final double truePeak;
  final double? range;

  const LUFSData({
    required this.momentary,
    required this.shortTerm,
    required this.integrated,
    required this.truePeak,
    this.range,
  });
}

/// Full channel strip data
class ChannelStripFullData {
  final String id;
  final String name;
  final String type; // 'audio', 'instrument', 'bus', 'fx', 'master'
  final Color? color;
  final double volume; // -inf to +12 dB
  final double pan; // -100 to +100
  final bool mute;
  final bool solo;
  final double meterL;
  final double meterR;
  final double peakL;
  final double peakR;
  final List<InsertSlotData> inserts;
  final List<SendSlotData> sends;
  final bool eqEnabled;
  final List<EQBandData> eqBands;
  final String input;
  final String output;
  final LUFSData? lufs;

  const ChannelStripFullData({
    required this.id,
    required this.name,
    required this.type,
    this.color,
    this.volume = 0,
    this.pan = 0,
    this.mute = false,
    this.solo = false,
    this.meterL = 0,
    this.meterR = 0,
    this.peakL = 0,
    this.peakR = 0,
    this.inserts = const [],
    this.sends = const [],
    this.eqEnabled = false,
    this.eqBands = const [],
    this.input = 'No Input',
    this.output = 'Stereo Out',
    this.lufs,
  });
}

// ============ Channel Strip Widget ============

class ChannelStrip extends StatelessWidget {
  final ChannelStripFullData? channel;
  final bool collapsed;
  final VoidCallback? onToggleCollapse;
  final void Function(String channelId, double volume)? onVolumeChange;
  final void Function(String channelId, double pan)? onPanChange;
  final void Function(String channelId)? onMuteToggle;
  final void Function(String channelId)? onSoloToggle;
  final void Function(String channelId, int slotIndex)? onInsertClick;
  final void Function(String channelId, int slotIndex)? onInsertRemove;
  final void Function(String channelId, int slotIndex)? onInsertBypassToggle;
  final void Function(String channelId, int sendIndex, double level)? onSendLevelChange;
  final void Function(String channelId)? onEQToggle;
  final void Function(String channelId)? onOutputClick;

  const ChannelStrip({
    super.key,
    this.channel,
    this.collapsed = false,
    this.onToggleCollapse,
    this.onVolumeChange,
    this.onPanChange,
    this.onMuteToggle,
    this.onSoloToggle,
    this.onInsertClick,
    this.onInsertRemove,
    this.onInsertBypassToggle,
    this.onSendLevelChange,
    this.onEQToggle,
    this.onOutputClick,
  });

  static const Map<String, String> _typeIcons = {
    'audio': '🎵',
    'instrument': '🎹',
    'bus': '🔈',
    'fx': '🎛️',
    'master': '🔊',
  };

  @override
  Widget build(BuildContext context) {
    if (collapsed) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgMid,
        border: const Border(
          left: BorderSide(color: ReelForgeTheme.borderSubtle),
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: const BoxDecoration(
              color: ReelForgeTheme.bgSurface,
              border: Border(
                bottom: BorderSide(color: ReelForgeTheme.borderSubtle),
              ),
            ),
            child: Row(
              children: [
                Text('Channel', style: ReelForgeTheme.h3),
                const Spacer(),
                if (onToggleCollapse != null)
                  IconButton(
                    icon: const Icon(Icons.chevron_right, size: 16),
                    onPressed: onToggleCollapse,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 24,
                      minHeight: 24,
                    ),
                  ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: channel == null
                ? _buildEmptyState()
                : _buildChannelContent(channel!),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🎚️', style: TextStyle(fontSize: 32)),
          const SizedBox(height: 8),
          Text(
            'Select a track to view channel strip',
            style: ReelForgeTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildChannelContent(ChannelStripFullData ch) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Channel header
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: ReelForgeTheme.bgSurface,
              borderRadius: BorderRadius.circular(4),
              border: Border(
                left: BorderSide(
                  color: ch.color ?? ReelForgeTheme.accentBlue,
                  width: 3,
                ),
              ),
            ),
            child: Row(
              children: [
                Text(_typeIcons[ch.type] ?? '🎵', style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ch.name,
                    style: ReelForgeTheme.body.copyWith(
                      color: ReelForgeTheme.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Mute/Solo buttons
          Row(
            children: [
              Expanded(
                child: _ChannelButton(
                  label: 'M',
                  isActive: ch.mute,
                  activeColor: ReelForgeTheme.accentOrange,
                  onTap: () => onMuteToggle?.call(ch.id),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ChannelButton(
                  label: 'S',
                  isActive: ch.solo,
                  activeColor: ReelForgeTheme.accentYellow,
                  onTap: () => onSoloToggle?.call(ch.id),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Pan section
          _Section(
            title: 'Pan',
            child: _PanKnob(
              value: ch.pan,
              onChanged: (v) => onPanChange?.call(ch.id, v),
            ),
          ),
          const SizedBox(height: 12),

          // Fader section
          _VerticalFader(
            value: ch.volume,
            min: -60,
            max: 12,
            meterL: ch.meterL,
            meterR: ch.meterR,
            peakL: ch.peakL,
            peakR: ch.peakR,
            onChanged: (v) => onVolumeChange?.call(ch.id, v),
          ),
          const SizedBox(height: 12),

          // LUFS meter (master only)
          if (ch.type == 'master' && ch.lufs != null) ...[
            _LUFSMeterDisplay(lufs: ch.lufs!),
            const SizedBox(height: 12),
          ],

          // Inserts
          _InsertRack(
            inserts: ch.inserts,
            onInsertClick: (i) => onInsertClick?.call(ch.id, i),
            onInsertBypassToggle: (i) => onInsertBypassToggle?.call(ch.id, i),
          ),
          const SizedBox(height: 12),

          // Sends
          _SendRack(
            sends: ch.sends,
            onSendLevelChange: (i, level) => onSendLevelChange?.call(ch.id, i, level),
          ),
          const SizedBox(height: 12),

          // EQ preview
          _EQPreview(
            bands: ch.eqBands,
            enabled: ch.eqEnabled,
            onToggle: () => onEQToggle?.call(ch.id),
          ),
          const SizedBox(height: 12),

          // Output routing
          _Section(
            title: 'Output',
            child: GestureDetector(
              onTap: () => onOutputClick?.call(ch.id),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: ReelForgeTheme.bgDeep,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    const Text('🔈'),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        ch.output,
                        style: ReelForgeTheme.body,
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down, size: 16),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============ Helper Widgets ============

class _Section extends StatelessWidget {
  final String title;
  final Widget child;

  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: ReelForgeTheme.label),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}

class _ChannelButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final Color activeColor;
  final VoidCallback? onTap;

  const _ChannelButton({
    required this.label,
    required this.isActive,
    required this.activeColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 28,
        decoration: BoxDecoration(
          color: isActive ? activeColor : ReelForgeTheme.bgDeep,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isActive ? activeColor : ReelForgeTheme.borderSubtle,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isActive ? ReelForgeTheme.bgDeep : ReelForgeTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _PanKnob extends StatelessWidget {
  final double value; // -100 to +100
  final ValueChanged<double>? onChanged;

  const _PanKnob({required this.value, this.onChanged});

  String get _displayValue {
    if (value == 0) return 'C';
    return value < 0 ? 'L${value.abs().round()}' : 'R${value.round()}';
  }

  @override
  Widget build(BuildContext context) {
    final rotation = (value / 100) * 135; // -135 to +135 degrees

    return Column(
      children: [
        GestureDetector(
          onDoubleTap: () => onChanged?.call(0),
          onHorizontalDragUpdate: (details) {
            final newValue = (value + details.delta.dx).clamp(-100.0, 100.0);
            onChanged?.call(newValue);
          },
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ReelForgeTheme.bgDeep,
              border: Border.all(color: ReelForgeTheme.borderMedium),
            ),
            child: Center(
              child: Transform.rotate(
                angle: rotation * math.pi / 180,
                child: Container(
                  width: 2,
                  height: 16,
                  decoration: BoxDecoration(
                    color: ReelForgeTheme.accentBlue,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(_displayValue, style: ReelForgeTheme.monoSmall),
      ],
    );
  }
}

class _VerticalFader extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final double meterL;
  final double meterR;
  final double peakL;
  final double peakR;
  final ValueChanged<double>? onChanged;

  const _VerticalFader({
    required this.value,
    required this.min,
    required this.max,
    required this.meterL,
    required this.meterR,
    required this.peakL,
    required this.peakR,
    this.onChanged,
  });

  // ignore: unused_element
  String get _displayValue {
    if (value <= -60) return '-∞';
    return value >= 0 ? '+${value.toStringAsFixed(1)}' : value.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      child: Row(
        children: [
          // Left meter
          _Meter(level: meterL, peak: peakL),
          const SizedBox(width: 4),
          // Right meter
          _Meter(level: meterR, peak: peakR),
          const SizedBox(width: 8),
          // Fader
          Expanded(
            child: GestureDetector(
              onVerticalDragUpdate: (details) {
                final percent = 1 - (details.localPosition.dy / 200).clamp(0.0, 1.0);
                final newValue = min + (max - min) * percent;
                onChanged?.call(newValue);
              },
              onDoubleTap: () => onChanged?.call(0),
              child: CustomPaint(
                painter: _FaderPainter(
                  value: value,
                  min: min,
                  max: max,
                ),
                size: const Size(double.infinity, 200),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Scale
          SizedBox(
            width: 24,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('+12', style: ReelForgeTheme.label),
                Text('+6', style: ReelForgeTheme.label),
                Text('0', style: ReelForgeTheme.label),
                Text('-6', style: ReelForgeTheme.label),
                Text('-12', style: ReelForgeTheme.label),
                Text('-24', style: ReelForgeTheme.label),
                Text('-∞', style: ReelForgeTheme.label),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Meter extends StatelessWidget {
  final double level;
  final double peak;

  const _Meter({required this.level, required this.peak});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 8,
      child: CustomPaint(
        painter: _MeterPainter(level: level, peak: peak),
        size: const Size(8, 200),
      ),
    );
  }
}

class _MeterPainter extends CustomPainter {
  final double level;
  final double peak;

  _MeterPainter({required this.level, required this.peak});

  @override
  void paint(Canvas canvas, Size size) {
    // Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = ReelForgeTheme.bgDeepest,
    );

    // Level fill with gradient
    final fillHeight = size.height * level.clamp(0, 1);
    final rect = Rect.fromLTWH(0, size.height - fillHeight, size.width, fillHeight);

    final gradient = LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: ReelForgeTheme.meterGradient,
      stops: const [0.0, 0.5, 0.7, 0.85, 1.0],
    );

    canvas.drawRect(
      rect,
      Paint()..shader = gradient.createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    // Peak indicator
    final peakY = size.height * (1 - peak.clamp(0, 1));
    canvas.drawLine(
      Offset(0, peakY),
      Offset(size.width, peakY),
      Paint()
        ..color = peak >= 1.0 ? ReelForgeTheme.accentRed : ReelForgeTheme.textPrimary
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_MeterPainter oldDelegate) =>
      level != oldDelegate.level || peak != oldDelegate.peak;
}

class _FaderPainter extends CustomPainter {
  final double value;
  final double min;
  final double max;

  _FaderPainter({required this.value, required this.min, required this.max});

  @override
  void paint(Canvas canvas, Size size) {
    // Track
    final trackRect = Rect.fromLTWH(
      size.width / 2 - 2,
      0,
      4,
      size.height,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(trackRect, const Radius.circular(2)),
      Paint()..color = ReelForgeTheme.bgDeep,
    );

    // Thumb position
    final percent = (value - min) / (max - min);
    final thumbY = size.height * (1 - percent.clamp(0.0, 1.0));

    // Thumb
    final thumbRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(size.width / 2, thumbY),
        width: size.width - 8,
        height: 12,
      ),
      const Radius.circular(2),
    );

    canvas.drawRRect(
      thumbRect,
      Paint()..color = ReelForgeTheme.textSecondary,
    );

    // Thumb line
    canvas.drawLine(
      Offset(6, thumbY),
      Offset(size.width - 6, thumbY),
      Paint()
        ..color = ReelForgeTheme.textPrimary
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_FaderPainter oldDelegate) => value != oldDelegate.value;
}

class _InsertRack extends StatelessWidget {
  final List<InsertSlotData> inserts;
  final void Function(int index)? onInsertClick;
  final void Function(int index)? onInsertBypassToggle;

  const _InsertRack({
    required this.inserts,
    this.onInsertClick,
    this.onInsertBypassToggle,
  });

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Inserts',
      child: Column(
        children: List.generate(
          inserts.length.clamp(0, 8),
          (i) => _InsertSlot(
            index: i,
            insert: i < inserts.length ? inserts[i] : null,
            onTap: () => onInsertClick?.call(i),
            onBypassToggle: () => onInsertBypassToggle?.call(i),
          ),
        ),
      ),
    );
  }
}

class _InsertSlot extends StatelessWidget {
  final int index;
  final InsertSlotData? insert;
  final VoidCallback? onTap;
  final VoidCallback? onBypassToggle;

  const _InsertSlot({
    required this.index,
    this.insert,
    this.onTap,
    this.onBypassToggle,
  });

  @override
  Widget build(BuildContext context) {
    final hasPlugin = insert?.pluginName != null;
    final bypassed = insert?.bypassed ?? false;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 24,
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: hasPlugin
              ? (bypassed
                  ? ReelForgeTheme.bgDeep.withValues(alpha: 0.5)
                  : ReelForgeTheme.bgSurface)
              : ReelForgeTheme.bgDeep,
          borderRadius: BorderRadius.circular(2),
          border: hasPlugin
              ? Border.all(color: ReelForgeTheme.accentBlue.withValues(alpha: 0.3))
              : null,
        ),
        child: Row(
          children: [
            Text(
              '${index + 1}',
              style: ReelForgeTheme.label.copyWith(
                color: ReelForgeTheme.textTertiary,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                insert?.pluginName ?? '—',
                style: ReelForgeTheme.bodySmall.copyWith(
                  color: hasPlugin
                      ? (bypassed ? ReelForgeTheme.textTertiary : ReelForgeTheme.textSecondary)
                      : ReelForgeTheme.textTertiary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (bypassed && hasPlugin)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: ReelForgeTheme.accentOrange.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Text(
                  'OFF',
                  style: TextStyle(
                    fontSize: 8,
                    color: ReelForgeTheme.accentOrange,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SendRack extends StatelessWidget {
  final List<SendSlotData> sends;
  final void Function(int index, double level)? onSendLevelChange;

  const _SendRack({
    required this.sends,
    this.onSendLevelChange,
  });

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Sends',
      child: Column(
        children: List.generate(
          sends.length.clamp(0, 8),
          (i) => _SendSlot(
            index: i,
            send: i < sends.length ? sends[i] : null,
            onLevelChange: (level) => onSendLevelChange?.call(i, level),
          ),
        ),
      ),
    );
  }
}

class _SendSlot extends StatelessWidget {
  final int index;
  final SendSlotData? send;
  final ValueChanged<double>? onLevelChange;

  const _SendSlot({
    required this.index,
    this.send,
    this.onLevelChange,
  });

  @override
  Widget build(BuildContext context) {
    final hasDestination = send?.destination != null;

    return Container(
      height: 24,
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: hasDestination ? ReelForgeTheme.bgSurface : ReelForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(2),
      ),
      child: Row(
        children: [
          Text(
            '${index + 1}',
            style: ReelForgeTheme.label.copyWith(
              color: ReelForgeTheme.textTertiary,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              send?.destination ?? '—',
              style: ReelForgeTheme.bodySmall.copyWith(
                color: hasDestination
                    ? ReelForgeTheme.textSecondary
                    : ReelForgeTheme.textTertiary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (hasDestination) ...[
            SizedBox(
              width: 60,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                ),
                child: Slider(
                  value: send!.level.clamp(-60, 6),
                  min: -60,
                  max: 6,
                  onChanged: onLevelChange,
                ),
              ),
            ),
            if (send!.preFader)
              Text(
                'PRE',
                style: TextStyle(
                  fontSize: 8,
                  color: ReelForgeTheme.accentCyan,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _EQPreview extends StatelessWidget {
  final List<EQBandData> bands;
  final bool enabled;
  final VoidCallback? onToggle;

  const _EQPreview({
    required this.bands,
    required this.enabled,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('EQ', style: ReelForgeTheme.label),
            const Spacer(),
            GestureDetector(
              onTap: onToggle,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: enabled
                      ? ReelForgeTheme.accentBlue.withValues(alpha: 0.2)
                      : ReelForgeTheme.bgDeep,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Text(
                  enabled ? 'ON' : 'OFF',
                  style: TextStyle(
                    fontSize: 9,
                    color: enabled ? ReelForgeTheme.accentBlue : ReelForgeTheme.textTertiary,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          height: 60,
          decoration: BoxDecoration(
            color: ReelForgeTheme.bgDeep,
            borderRadius: BorderRadius.circular(4),
          ),
          child: CustomPaint(
            painter: _EQCurvePainter(bands: bands, enabled: enabled),
            size: const Size(double.infinity, 60),
          ),
        ),
      ],
    );
  }
}

class _EQCurvePainter extends CustomPainter {
  final List<EQBandData> bands;
  final bool enabled;

  _EQCurvePainter({required this.bands, required this.enabled});

  @override
  void paint(Canvas canvas, Size size) {
    // Grid
    final gridPaint = Paint()
      ..color = ReelForgeTheme.borderSubtle
      ..strokeWidth = 0.5;

    // Center line
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      gridPaint,
    );

    // Vertical grid
    for (int i = 1; i < 4; i++) {
      final x = size.width * i / 4;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        gridPaint..color = ReelForgeTheme.borderSubtle.withValues(alpha: 0.3),
      );
    }

    // EQ curve
    if (!enabled || bands.isEmpty) {
      final flatPaint = Paint()
        ..color = ReelForgeTheme.textTertiary
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        flatPaint,
      );
      return;
    }

    final path = Path();
    path.moveTo(0, size.height / 2);

    for (double x = 0; x <= size.width; x += 2) {
      final freq = 20 * math.pow(1000, x / size.width);
      double y = size.height / 2;

      for (final band in bands) {
        if (!band.enabled) continue;
        final dist = (math.log(freq) / math.ln10 - math.log(band.frequency) / math.ln10).abs();
        final influence = math.exp(-dist * band.q * 0.5);
        y -= band.gain * influence * 2;
      }

      y = y.clamp(5.0, size.height - 5);
      path.lineTo(x, y);
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = ReelForgeTheme.accentBlue
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_EQCurvePainter oldDelegate) =>
      enabled != oldDelegate.enabled || bands != oldDelegate.bands;
}

class _LUFSMeterDisplay extends StatelessWidget {
  final LUFSData lufs;
  final double target;

  // ignore: unused_element_parameter
  const _LUFSMeterDisplay({required this.lufs, this.target = -14});

  String _formatLufs(double value) {
    if (value <= -40) return '-∞';
    return value.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final isTooLoud = lufs.integrated > target + 1;
    final isTooQuiet = lufs.integrated < target - 3;
    final isClipping = lufs.truePeak > -0.3;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Loudness', style: ReelForgeTheme.label),
            const Spacer(),
            Text(
              '$target LUFS',
              style: ReelForgeTheme.label.copyWith(
                color: ReelForgeTheme.accentCyan,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // LUFS values
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _LUFSValue(label: 'M', value: _formatLufs(lufs.momentary)),
            _LUFSValue(label: 'S', value: _formatLufs(lufs.shortTerm)),
            _LUFSValue(
              label: 'I',
              value: _formatLufs(lufs.integrated),
              color: isTooLoud
                  ? ReelForgeTheme.accentRed
                  : (isTooQuiet ? ReelForgeTheme.accentYellow : null),
            ),
            _LUFSValue(
              label: 'TP',
              value: lufs.truePeak > -40 ? lufs.truePeak.toStringAsFixed(1) : '-∞',
              color: isClipping ? ReelForgeTheme.accentRed : null,
            ),
          ],
        ),
      ],
    );
  }
}

class _LUFSValue extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _LUFSValue({
    required this.label,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: ReelForgeTheme.label),
        const SizedBox(height: 2),
        Text(
          value,
          style: ReelForgeTheme.mono.copyWith(
            color: color ?? ReelForgeTheme.textPrimary,
          ),
        ),
      ],
    );
  }
}

// ============ Factory Functions ============

List<InsertSlotData> createEmptyInserts({int count = 8}) {
  return List.generate(
    count,
    (i) => InsertSlotData(id: 'insert-$i'),
  );
}

List<SendSlotData> createEmptySends({int count = 8}) {
  return List.generate(
    count,
    (i) => SendSlotData(id: 'send-$i'),
  );
}

ChannelStripFullData createDefaultChannelStrip({
  required String id,
  required String name,
  String type = 'audio',
}) {
  return ChannelStripFullData(
    id: id,
    name: name,
    type: type,
    inserts: createEmptyInserts(),
    sends: createEmptySends(),
  );
}
