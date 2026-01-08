/// Mixer Panel Widget
///
/// Professional mixing console with:
/// - Bus channel strips
/// - Faders with dB scale
/// - Peak/RMS meters
/// - Mute/Solo/Arm
/// - Pan control
/// - Send levels

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../mixer/pro_mixer_strip.dart';
import '../../theme/reelforge_theme.dart';

// ============ Types ============

class BusChannel {
  final String id;
  final String name;
  final Color? color;
  final double volume; // 0-1 linear
  final double pan; // -1 to 1
  final bool muted;
  final bool solo;
  final bool armed;
  final List<SendLevel>? sends;

  const BusChannel({
    required this.id,
    required this.name,
    this.color,
    this.volume = 0.85,
    this.pan = 0,
    this.muted = false,
    this.solo = false,
    this.armed = false,
    this.sends,
  });

  BusChannel copyWith({
    String? id,
    String? name,
    Color? color,
    double? volume,
    double? pan,
    bool? muted,
    bool? solo,
    bool? armed,
    List<SendLevel>? sends,
  }) {
    return BusChannel(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
      volume: volume ?? this.volume,
      pan: pan ?? this.pan,
      muted: muted ?? this.muted,
      solo: solo ?? this.solo,
      armed: armed ?? this.armed,
      sends: sends ?? this.sends,
    );
  }
}

class SendLevel {
  final String busId;
  final double level;

  const SendLevel({
    required this.busId,
    this.level = 0,
  });
}

class MeterReading {
  final ChannelLevel left;
  final ChannelLevel right;
  final bool isClipping;

  const MeterReading({
    required this.left,
    required this.right,
    this.isClipping = false,
  });
}

class ChannelLevel {
  final double peak;
  final double rms;

  const ChannelLevel({this.peak = -60, this.rms = -60});
}

// ============ Pro Mixer Panel (New Design) ============

/// New professional mixer panel using ProMixerStrip
class ProMixerPanel extends StatelessWidget {
  final List<BusChannel> buses;
  final BusChannel? masterBus;
  final Map<String, MeterReading>? meterReadings;
  final String? selectedBusId;
  final ValueChanged<(String, double)>? onVolumeChange;
  final ValueChanged<(String, double)>? onPanChange;
  final ValueChanged<String>? onMuteToggle;
  final ValueChanged<String>? onSoloToggle;
  final ValueChanged<String>? onArmToggle;
  final ValueChanged<String>? onSelect;
  final bool compact;

  const ProMixerPanel({
    super.key,
    required this.buses,
    this.masterBus,
    this.meterReadings,
    this.selectedBusId,
    this.onVolumeChange,
    this.onPanChange,
    this.onMuteToggle,
    this.onSoloToggle,
    this.onArmToggle,
    this.onSelect,
    this.compact = false,
  });

  ProMixerStripData _toProStripData(BusChannel bus, {bool isMaster = false}) {
    final reading = meterReadings?[bus.id];
    return ProMixerStripData(
      id: bus.id,
      name: bus.name,
      trackColor: bus.color ?? TrackColors.forIndex(buses.indexOf(bus)),
      type: isMaster ? 'master' : 'audio',
      volume: bus.volume,
      pan: bus.pan,
      muted: bus.muted,
      soloed: bus.solo,
      armed: bus.armed,
      selected: bus.id == selectedBusId,
      meters: reading != null
          ? MeterData(
              peakL: _dbToLinear(reading.left.peak),
              peakR: _dbToLinear(reading.right.peak),
              rmsL: _dbToLinear(reading.left.rms),
              rmsR: _dbToLinear(reading.right.rms),
              clipL: reading.isClipping,
              clipR: reading.isClipping,
            )
          : const MeterData(),
    );
  }

  double _dbToLinear(double db) {
    if (db <= -60) return 0;
    return math.pow(10, db / 20).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: ReelForgeTheme.bgDeep,
      child: Row(
        children: [
          // Bus channels
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: buses.map((bus) {
                  return ProMixerStrip(
                    data: _toProStripData(bus),
                    compact: compact,
                    onVolumeChange: (v) => onVolumeChange?.call((bus.id, v)),
                    onPanChange: (p) => onPanChange?.call((bus.id, p)),
                    onMuteToggle: () => onMuteToggle?.call(bus.id),
                    onSoloToggle: () => onSoloToggle?.call(bus.id),
                    onArmToggle: () => onArmToggle?.call(bus.id),
                    onSelect: () => onSelect?.call(bus.id),
                  );
                }).toList(),
              ),
            ),
          ),

          // Master bus separator
          if (masterBus != null)
            Container(
              width: 2,
              color: ReelForgeTheme.accentOrange.withValues(alpha: 0.3),
            ),

          // Master bus
          if (masterBus != null)
            ProMixerStrip(
              data: _toProStripData(masterBus!, isMaster: true),
              compact: compact,
              onVolumeChange: (v) => onVolumeChange?.call((masterBus!.id, v)),
              onMuteToggle: () => onMuteToggle?.call(masterBus!.id),
              onSoloToggle: () => onSoloToggle?.call(masterBus!.id),
              onSelect: () => onSelect?.call(masterBus!.id),
            ),
        ],
      ),
    );
  }
}

// ============ Legacy Mixer Panel ============

class MixerPanel extends StatelessWidget {
  final List<BusChannel> buses;
  final BusChannel? masterBus;
  final Map<String, MeterReading>? meterReadings;
  final ValueChanged<(String, double)>? onVolumeChange;
  final ValueChanged<(String, double)>? onPanChange;
  final ValueChanged<String>? onMuteToggle;
  final ValueChanged<String>? onSoloToggle;
  final ValueChanged<String>? onArmToggle;
  final bool compact;

  const MixerPanel({
    super.key,
    required this.buses,
    this.masterBus,
    this.meterReadings,
    this.onVolumeChange,
    this.onPanChange,
    this.onMuteToggle,
    this.onSoloToggle,
    this.onArmToggle,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: ReelForgeTheme.bgDeep,
      child: Row(
        children: [
          // Bus channels
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: buses.map((bus) {
                  return _ChannelStrip(
                    channel: bus,
                    reading: meterReadings?[bus.id],
                    compact: compact,
                    onVolumeChange: (v) => onVolumeChange?.call((bus.id, v)),
                    onPanChange: (p) => onPanChange?.call((bus.id, p)),
                    onMuteToggle: () => onMuteToggle?.call(bus.id),
                    onSoloToggle: () => onSoloToggle?.call(bus.id),
                    onArmToggle: () => onArmToggle?.call(bus.id),
                  );
                }).toList(),
              ),
            ),
          ),

          // Master bus
          if (masterBus != null) ...[
            Container(
              width: 1,
              color: ReelForgeTheme.borderSubtle,
            ),
            _ChannelStrip(
              channel: masterBus!,
              reading: meterReadings?[masterBus!.id],
              isMaster: true,
              compact: compact,
              onVolumeChange: (v) => onVolumeChange?.call((masterBus!.id, v)),
              onMuteToggle: () => onMuteToggle?.call(masterBus!.id),
              onSoloToggle: () => onSoloToggle?.call(masterBus!.id),
            ),
          ],
        ],
      ),
    );
  }
}

// ============ Channel Strip ============

class _ChannelStrip extends StatefulWidget {
  final BusChannel channel;
  final MeterReading? reading;
  final bool isMaster;
  final bool compact;
  final ValueChanged<double>? onVolumeChange;
  final ValueChanged<double>? onPanChange;
  final VoidCallback? onMuteToggle;
  final VoidCallback? onSoloToggle;
  final VoidCallback? onArmToggle;

  const _ChannelStrip({
    required this.channel,
    this.reading,
    this.isMaster = false,
    this.compact = false,
    this.onVolumeChange,
    this.onPanChange,
    this.onMuteToggle,
    this.onSoloToggle,
    this.onArmToggle,
  });

  @override
  State<_ChannelStrip> createState() => _ChannelStripState();
}

class _ChannelStripState extends State<_ChannelStrip> {
  bool _isDragging = false;

  String get _volumeDbStr {
    if (widget.channel.volume <= 0) return '-∞';
    final db = 20 * math.log(widget.channel.volume) / math.ln10;
    return _formatDb(db);
  }

  @override
  Widget build(BuildContext context) {
    final channelColor = widget.channel.color ?? ReelForgeTheme.accentPurple;

    return Container(
      width: widget.compact ? 50 : 70,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgMid,
        border: Border(
          right: BorderSide(color: ReelForgeTheme.borderSubtle.withValues(alpha: 0.5)),
        ),
      ),
      child: Column(
        children: [
          // Header
          _buildHeader(channelColor),
          const SizedBox(height: 8),

          // Meter + Fader
          Expanded(child: _buildFaderSection()),
          const SizedBox(height: 4),

          // Volume display
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: ReelForgeTheme.bgVoid,
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              '$_volumeDbStr dB',
              style: TextStyle(
                fontSize: 9,
                fontFamily: 'monospace',
                color: ReelForgeTheme.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Pan knob (not for master)
          if (!widget.isMaster) _buildPanControl(),
          const SizedBox(height: 8),

          // Control buttons
          _buildControlButtons(),
        ],
      ),
    );
  }

  Widget _buildHeader(Color channelColor) {
    return Column(
      children: [
        Text(
          widget.channel.name,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: ReelForgeTheme.textPrimary,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Container(
          height: 3,
          decoration: BoxDecoration(
            color: channelColor,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ],
    );
  }

  Widget _buildFaderSection() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onVerticalDragStart: (_) => setState(() => _isDragging = true),
          onVerticalDragEnd: (_) => setState(() => _isDragging = false),
          onVerticalDragUpdate: _handleFaderDrag,
          onDoubleTap: () => widget.onVolumeChange?.call(1), // 0dB
          child: Row(
            children: [
              // Meter
              Expanded(
                flex: 1,
                child: _buildMeter(constraints.maxHeight),
              ),
              const SizedBox(width: 2),

              // Fader track
              Expanded(
                flex: 2,
                child: _buildFader(constraints.maxHeight),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMeter(double height) {
    return CustomPaint(
      size: Size(double.infinity, height),
      painter: _MeterPainter(reading: widget.reading),
    );
  }

  Widget _buildFader(double height) {
    final volume = math.sqrt(widget.channel.volume);

    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        // Track
        Container(
          width: 12,
          height: height,
          decoration: BoxDecoration(
            color: ReelForgeTheme.bgVoid,
            borderRadius: BorderRadius.circular(2),
          ),
        ),

        // dB scale
        ...[-48, -24, -12, -6, 0, 6].map((db) {
          final percent = _dbToPercent(db.toDouble());
          return Positioned(
            bottom: height * percent / 100,
            left: 0,
            child: Container(
              width: 4,
              height: 1,
              color: db == 0
                  ? ReelForgeTheme.accentBlue
                  : ReelForgeTheme.borderMedium,
            ),
          );
        }),

        // Fill
        Positioned(
          bottom: 0,
          child: Container(
            width: 12,
            height: height * volume,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  ReelForgeTheme.accentGreen,
                  ReelForgeTheme.accentGreen,
                  ReelForgeTheme.accentYellow,
                  ReelForgeTheme.accentRed,
                ],
                stops: const [0, 0.7, 0.9, 1],
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),

        // Knob
        Positioned(
          bottom: height * volume - 12,
          child: Container(
            width: 20,
            height: 24,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  ReelForgeTheme.bgHover,
                  ReelForgeTheme.bgElevated,
                  ReelForgeTheme.bgSurface,
                ],
              ),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: _isDragging
                    ? ReelForgeTheme.accentBlue
                    : ReelForgeTheme.borderMedium,
              ),
            ),
            child: Center(
              child: Container(
                width: 12,
                height: 2,
                color: ReelForgeTheme.textSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _handleFaderDrag(DragUpdateDetails details) {
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null) return;

    final height = box.size.height - 150; // Approximate fader height
    final localY = details.localPosition.dy;
    final percent = 1 - (localY / height).clamp(0.0, 1.0);
    final volume = percent * percent; // Curved response
    widget.onVolumeChange?.call(volume);
  }

  Widget _buildPanControl() {
    final pan = widget.channel.pan;
    final panLabel = pan > 0.05
        ? 'R${(pan * 100).round()}'
        : pan < -0.05
            ? 'L${(-pan * 100).round()}'
            : 'C';

    return Column(
      children: [
        SizedBox(
          height: 20,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              activeTrackColor: ReelForgeTheme.accentBlue,
              inactiveTrackColor: ReelForgeTheme.bgElevated,
              thumbColor: ReelForgeTheme.textPrimary,
            ),
            child: Slider(
              value: pan,
              min: -1,
              max: 1,
              onChanged: widget.onPanChange,
            ),
          ),
        ),
        Text(
          panLabel,
          style: TextStyle(fontSize: 8, color: ReelForgeTheme.textSecondary),
        ),
      ],
    );
  }

  Widget _buildControlButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _ChannelButton(
          label: 'M',
          active: widget.channel.muted,
          activeColor: ReelForgeTheme.accentRed,
          onTap: widget.onMuteToggle,
        ),
        const SizedBox(width: 2),
        _ChannelButton(
          label: 'S',
          active: widget.channel.solo,
          activeColor: ReelForgeTheme.accentYellow,
          onTap: widget.onSoloToggle,
        ),
        if (!widget.isMaster && widget.onArmToggle != null) ...[
          const SizedBox(width: 2),
          _ChannelButton(
            label: 'R',
            active: widget.channel.armed,
            activeColor: ReelForgeTheme.accentRed,
            onTap: widget.onArmToggle,
          ),
        ],
      ],
    );
  }

  String _formatDb(double db) {
    if (db <= -60) return '-∞';
    return db >= 0 ? '+${db.toStringAsFixed(1)}' : db.toStringAsFixed(1);
  }

  double _dbToPercent(double db, [double minDb = -60, double maxDb = 6]) {
    if (db <= minDb) return 0;
    if (db >= maxDb) return 100;
    return ((db - minDb) / (maxDb - minDb)) * 100;
  }
}

// ============ Channel Button ============

class _ChannelButton extends StatelessWidget {
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback? onTap;

  const _ChannelButton({
    required this.label,
    this.active = false,
    required this.activeColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: active ? activeColor : ReelForgeTheme.bgSurface,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: active ? activeColor : ReelForgeTheme.borderSubtle,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: active ? ReelForgeTheme.bgVoid : ReelForgeTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

// ============ Meter Painter ============

class _MeterPainter extends CustomPainter {
  final MeterReading? reading;

  _MeterPainter({this.reading});

  @override
  void paint(Canvas canvas, Size size) {
    final meterWidth = (size.width - 2) / 2;

    // Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = ReelForgeTheme.bgVoid,
    );

    if (reading == null) return;

    // Left meter
    _drawMeterBar(canvas, 0, meterWidth, size.height, reading!.left.peak);

    // Right meter
    _drawMeterBar(
        canvas, meterWidth + 2, meterWidth, size.height, reading!.right.peak);

    // Clip indicator
    if (reading!.isClipping) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, 4),
        Paint()..color = ReelForgeTheme.clipRed,
      );
    }
  }

  void _drawMeterBar(
      Canvas canvas, double x, double width, double height, double peakDb) {
    final percent = _dbToPercent(peakDb);
    final meterHeight = height * percent / 100;

    final gradient = LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [
        ReelForgeTheme.accentGreen,
        ReelForgeTheme.accentGreen,
        ReelForgeTheme.accentYellow,
        ReelForgeTheme.accentRed,
      ],
      stops: const [0, 0.6, 0.85, 1],
    );

    canvas.drawRect(
      Rect.fromLTWH(x, height - meterHeight, width, meterHeight),
      Paint()..shader = gradient.createShader(Rect.fromLTWH(x, 0, width, height)),
    );
  }

  double _dbToPercent(double db, [double minDb = -60, double maxDb = 6]) {
    if (db <= minDb) return 0;
    if (db >= maxDb) return 100;
    return ((db - minDb) / (maxDb - minDb)) * 100;
  }

  @override
  bool shouldRepaint(_MeterPainter oldDelegate) => reading != oldDelegate.reading;
}
