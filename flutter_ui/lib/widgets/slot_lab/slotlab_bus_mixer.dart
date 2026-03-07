// SlotLab Bus Mixer — DAW-style vertical fader mixer for SlotLab Lower Zone
//
// Professional mixer channel strips matching the DAW mixer design:
// - Color header bar with bus name
// - Insert slots section
// - Pan control with slider indicator
// - Vertical fader with gradient cap + grip lines + dB markers
// - Stereo meter bars (L/R) with real FFI metering via SharedMeterReader
// - dB readout
// - Mute/Solo buttons (pro DAW style)
// - Output routing selector
// Connected to MixerDSPProvider → FFI → Rust engine.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../../providers/mixer_dsp_provider.dart';
import '../../services/shared_meter_reader.dart';
import '../../theme/fluxforge_theme.dart';
import '../../utils/audio_math.dart';

/// Bus colors for visual identification
const Map<String, Color> _busColors = {
  'master': Color(0xFFE0E0E0),
  'music': Color(0xFF4A9EFF),
  'sfx': Color(0xFFFF9040),
  'voice': Color(0xFF40FF90),
  'ambience': Color(0xFF40C8FF),
  'ui': Color(0xFFCCCCCC),
  'reels': Color(0xFFFFD700),
  'wins': Color(0xFFFF4060),
};

/// Map bus ID to SharedMeterSnapshot channel index
/// Must match kSlotLabBuses in realtime_bus_meters.dart:
/// 0=SFX, 1=Music, 2=Voice, 3=Ambient, 4=Aux, 5=Master
/// Each channel has L/R pair: channelIndex*2 = L, channelIndex*2+1 = R
int _busIdToMeterIndex(String busId) {
  return switch (busId) {
    'sfx' => 0,
    'music' => 1,
    'voice' => 2,
    'ambience' => 3,
    'aux' => 4,
    'master' => 5,
    _ => 0,
  };
}

/// DAW-style vertical fader mixer for SlotLab Lower Zone.
/// Reads real-time meter data from SharedMeterReader (FFI shared memory).
class SlotLabBusMixer extends StatefulWidget {
  const SlotLabBusMixer({super.key});

  @override
  State<SlotLabBusMixer> createState() => _SlotLabBusMixerState();
}

class _SlotLabBusMixerState extends State<SlotLabBusMixer>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  SharedMeterSnapshot _snapshot = SharedMeterSnapshot.empty;
  bool _meterInitialized = false;

  // Peak hold state per channel (L/R index → held peak value)
  final Map<int, double> _peakHold = {};
  final Map<int, int> _peakHoldTime = {};

  static const int _peakHoldMs = 1500;
  static const double _peakDecayRate = 0.02;

  @override
  void initState() {
    super.initState();
    _initMetering();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  Future<void> _initMetering() async {
    final success = await SharedMeterReader.instance.initialize();
    if (mounted) {
      setState(() => _meterInitialized = success);
    }
  }

  void _onTick(Duration elapsed) {
    if (!_meterInitialized) return;

    if (SharedMeterReader.instance.hasChanged) {
      final newSnapshot = SharedMeterReader.instance.readMeters();
      _updatePeakHold(newSnapshot);
      setState(() => _snapshot = newSnapshot);
    } else {
      if (_decayPeakHold()) {
        setState(() {});
      }
    }
  }

  void _updatePeakHold(SharedMeterSnapshot snapshot) {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (int i = 0; i < snapshot.channelPeaks.length; i++) {
      final level = snapshot.channelPeaks[i];
      final currentPeak = _peakHold[i] ?? 0.0;
      if (level >= currentPeak) {
        _peakHold[i] = level;
        _peakHoldTime[i] = now;
      }
    }
  }

  bool _decayPeakHold() {
    final now = DateTime.now().millisecondsSinceEpoch;
    bool changed = false;
    for (final entry in _peakHold.entries.toList()) {
      final holdTime = _peakHoldTime[entry.key] ?? 0;
      if (now - holdTime > _peakHoldMs) {
        final newPeak = entry.value - _peakDecayRate;
        if (newPeak > 0) {
          _peakHold[entry.key] = newPeak;
          changed = true;
        } else {
          _peakHold.remove(entry.key);
          _peakHoldTime.remove(entry.key);
          changed = true;
        }
      }
    }
    return changed;
  }

  /// Get L/R peak levels for a bus
  (double, double) _getBusPeaks(String busId) {
    final channelIdx = _busIdToMeterIndex(busId);
    final leftIdx = channelIdx * 2;
    final rightIdx = leftIdx + 1;

    if (!_meterInitialized || leftIdx >= _snapshot.channelPeaks.length) {
      return (0.0, 0.0);
    }

    final leftPeak = _snapshot.channelPeaks[leftIdx];
    final rightPeak = rightIdx < _snapshot.channelPeaks.length
        ? _snapshot.channelPeaks[rightIdx]
        : leftPeak;
    return (leftPeak, rightPeak);
  }

  /// Get L/R peak hold levels for a bus
  (double, double) _getBusPeakHold(String busId) {
    final channelIdx = _busIdToMeterIndex(busId);
    final leftIdx = channelIdx * 2;
    final rightIdx = leftIdx + 1;
    return (_peakHold[leftIdx] ?? 0.0, _peakHold[rightIdx] ?? 0.0);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MixerDSPProvider>(
      builder: (context, provider, _) {
        final buses = provider.buses;
        final hasSolo = buses.any((b) => b.solo);

        final nonMaster = buses.where((b) => b.id != 'master').toList();
        final master = buses.where((b) => b.id == 'master').toList();

        return Container(
          color: FluxForgeTheme.bgDeepest,
          child: Center(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(width: 4),
                  // Non-master buses
                  for (final bus in nonMaster)
                    _BusStrip(
                      key: ValueKey('bus_${bus.id}'),
                      bus: bus,
                      color: _busColors[bus.id] ?? const Color(0xFF808080),
                      hasSoloActive: hasSolo,
                      provider: provider,
                      peakL: _getBusPeaks(bus.id).$1,
                      peakR: _getBusPeaks(bus.id).$2,
                      peakHoldL: _getBusPeakHold(bus.id).$1,
                      peakHoldR: _getBusPeakHold(bus.id).$2,
                    ),
                  // Divider before master
                  Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: FluxForgeTheme.textPrimary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                  // Master bus
                  for (final bus in master)
                    _BusStrip(
                      key: const ValueKey('bus_master'),
                      bus: bus,
                      color: _busColors['master']!,
                      hasSoloActive: false,
                      isMaster: true,
                      provider: provider,
                      peakL: _getBusPeaks(bus.id).$1,
                      peakR: _getBusPeaks(bus.id).$2,
                      peakHoldL: _getBusPeakHold(bus.id).$1,
                      peakHoldR: _getBusPeakHold(bus.id).$2,
                    ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Single bus channel strip — DAW mixer style
class _BusStrip extends StatefulWidget {
  final MixerBus bus;
  final Color color;
  final bool hasSoloActive;
  final bool isMaster;
  final MixerDSPProvider provider;
  final double peakL;
  final double peakR;
  final double peakHoldL;
  final double peakHoldR;

  const _BusStrip({
    super.key,
    required this.bus,
    required this.color,
    required this.hasSoloActive,
    this.isMaster = false,
    required this.provider,
    required this.peakL,
    required this.peakR,
    required this.peakHoldL,
    required this.peakHoldR,
  });

  @override
  State<_BusStrip> createState() => _BusStripState();
}

class _BusStripState extends State<_BusStrip> {
  bool _faderDragging = false;
  bool _panDragging = false;
  DateTime _lastFaderTapUp = DateTime(0);
  DateTime _lastPanTapUp = DateTime(0);
  bool _faderDragged = false;
  bool _panDragged = false;

  String _volumeToDb(double volume) => FaderCurve.linearToDbString(volume);

  String _panToString(double pan) {
    if (pan.abs() < 0.02) return 'C';
    final pct = (pan.abs() * 100).round();
    return pan < 0 ? 'L$pct' : 'R$pct';
  }

  @override
  Widget build(BuildContext context) {
    final bus = widget.bus;
    final isDimmed = widget.hasSoloActive && !bus.solo;
    final stripWidth = widget.isMaster ? 80.0 : 64.0;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 120),
      opacity: isDimmed ? 0.35 : 1.0,
      child: Container(
        width: stripWidth,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgSurface,
          border: Border(
            right: BorderSide(color: FluxForgeTheme.borderSubtle),
          ),
        ),
        child: Column(
          children: [
            _buildHeader(),
            _buildInsertSection(),
            _buildPanControl(),
            Expanded(child: _buildFaderSection()),
            _buildDbReadout(),
            _buildButtons(),
            _buildOutputSelector(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 24,
      decoration: BoxDecoration(color: widget.color),
      alignment: Alignment.center,
      child: Text(
        widget.bus.name.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: _headerTextColor(),
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Color _headerTextColor() {
    final luminance = widget.color.computeLuminance();
    return luminance > 0.5 ? FluxForgeTheme.bgVoid : FluxForgeTheme.textPrimary;
  }

  Widget _buildInsertSection() {
    final inserts = widget.bus.inserts;
    final visibleSlots = (inserts.length + 1).clamp(1, 4);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              'INSERTS',
              style: TextStyle(
                fontSize: 7,
                fontWeight: FontWeight.bold,
                color: FluxForgeTheme.textTertiary,
                letterSpacing: 0.5,
              ),
            ),
          ),
          for (int i = 0; i < visibleSlots; i++)
            _buildInsertSlot(
              i < inserts.length ? inserts[i] : null,
              i,
            ),
        ],
      ),
    );
  }

  Widget _buildInsertSlot(MixerInsert? insert, int index) {
    final isEmpty = insert == null;
    final isBypassed = insert?.bypassed ?? false;

    Color bgColor;
    Color borderColor;
    Color textColor;

    if (isEmpty) {
      bgColor = FluxForgeTheme.bgDeep;
      borderColor = FluxForgeTheme.borderSubtle;
      textColor = FluxForgeTheme.textTertiary;
    } else if (isBypassed) {
      bgColor = FluxForgeTheme.bgDeep;
      borderColor = FluxForgeTheme.borderSubtle;
      textColor = FluxForgeTheme.textTertiary;
    } else {
      bgColor = FluxForgeTheme.accentCyan.withOpacity(0.15);
      borderColor = FluxForgeTheme.accentCyan.withOpacity(0.3);
      textColor = FluxForgeTheme.textSecondary;
    }

    return GestureDetector(
      onTap: () {
        if (!isEmpty) {
          widget.provider.toggleBypass(widget.bus.id, insert.id);
        }
      },
      child: Container(
        height: 16,
        margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(color: borderColor, width: 0.5),
        ),
        child: Row(
          children: [
            Text(
              '${index + 1}',
              style: TextStyle(fontSize: 7, color: FluxForgeTheme.textTertiary),
            ),
            const SizedBox(width: 3),
            Expanded(
              child: Text(
                insert?.name ?? '—',
                style: TextStyle(fontSize: 8, color: textColor),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPanControl() {
    final pan = widget.bus.pan;
    final panWidth = widget.isMaster ? 72.0 : 56.0;

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: Listener(
        onPointerDown: (_) { _panDragged = false; },
        onPointerUp: (_) {
          if (_panDragged) return;
          final now = DateTime.now();
          if (now.difference(_lastPanTapUp).inMilliseconds < 300) {
            widget.provider.setBusPan(widget.bus.id, 0.0);
            _lastPanTapUp = DateTime(0);
          } else {
            _lastPanTapUp = now;
          }
        },
        child: GestureDetector(
        onHorizontalDragStart: (_) {
          _panDragged = true;
          setState(() => _panDragging = true);
        },
        onHorizontalDragEnd: (_) => setState(() => _panDragging = false),
        onHorizontalDragUpdate: (details) {
          final newPan = (pan + details.delta.dx / 50).clamp(-1.0, 1.0);
          widget.provider.setBusPan(widget.bus.id, newPan);
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
              Center(
                child: Container(width: 1, color: FluxForgeTheme.borderSubtle),
              ),
              Positioned(
                left: 4 + (pan + 1) / 2 * (panWidth - 16),
                top: 4,
                bottom: 4,
                child: Container(
                  width: 8,
                  decoration: BoxDecoration(
                    color: _panDragging
                        ? FluxForgeTheme.accentBlue
                        : pan.abs() < 0.02
                            ? FluxForgeTheme.textTertiary
                            : widget.color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Positioned.fill(
                child: Center(
                  child: Text(
                    _panToString(pan),
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                      color: FluxForgeTheme.textTertiary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildFaderSection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
      child: Row(
        children: [
          // Real-time stereo meter (L/R) from SharedMeterReader
          SizedBox(
            width: widget.isMaster ? 16 : 10,
            child: _buildStereoMeter(),
          ),
          const SizedBox(width: 3),
          Expanded(child: _buildFader()),
        ],
      ),
    );
  }

  Widget _buildStereoMeter() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;

        return Row(
          children: [
            // Left channel
            Expanded(
              child: _buildMeterBar(
                peak: widget.peakL,
                peakHold: widget.peakHoldL,
                height: height,
              ),
            ),
            const SizedBox(width: 1),
            // Right channel
            Expanded(
              child: _buildMeterBar(
                peak: widget.peakR,
                peakHold: widget.peakHoldR,
                height: height,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMeterBar({
    required double peak,
    required double peakHold,
    required double height,
  }) {
    // Convert linear peak to log scale for natural meter response
    final peakDb = peak > 0 ? 20 * math.log(peak) / math.ln10 : -60.0;
    final normalizedPeak = ((peakDb - (-60.0)) / (0.0 - (-60.0))).clamp(0.0, 1.0);
    final peakHeight = normalizedPeak * height;

    final holdDb = peakHold > 0 ? 20 * math.log(peakHold) / math.ln10 : -60.0;
    final normalizedHold = ((holdDb - (-60.0)) / (0.0 - (-60.0))).clamp(0.0, 1.0);

    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeepest,
        borderRadius: BorderRadius.circular(1),
      ),
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          // Peak level bar with gradient
          if (peakHeight > 0)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                height: peakHeight,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      peak > 0.9
                          ? FluxForgeTheme.accentRed
                          : peak > 0.7
                              ? FluxForgeTheme.accentOrange
                              : widget.color,
                      widget.color.withOpacity(0.6),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
          // Peak hold indicator
          if (peakHold > 0.01)
            Positioned(
              bottom: normalizedHold * height - 1,
              left: 0,
              right: 0,
              child: Container(
                height: 2,
                decoration: BoxDecoration(
                  color: peakHold > 0.9
                      ? FluxForgeTheme.accentRed
                      : widget.color,
                  boxShadow: [
                    BoxShadow(
                      color: (peakHold > 0.9
                              ? FluxForgeTheme.accentRed
                              : widget.color)
                          .withOpacity(0.5),
                      blurRadius: 3,
                    ),
                  ],
                ),
              ),
            ),
          // Clip indicator
          if (peak >= 1.0)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 3,
                decoration: BoxDecoration(
                  color: FluxForgeTheme.accentRed,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(1),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFader() {
    final volume = widget.bus.volume;
    final faderPos = FaderCurve.linearToPosition(volume);

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final faderCapHeight = 28.0;
        final trackHeight = height - faderCapHeight;
        final faderY = trackHeight * (1 - faderPos);

        return Listener(
          onPointerDown: (_) { _faderDragged = false; },
          onPointerUp: (_) {
            if (_faderDragged) return; // Was a drag, not a tap
            final now = DateTime.now();
            if (now.difference(_lastFaderTapUp).inMilliseconds < 300) {
              widget.provider.setBusVolume(widget.bus.id, 1.0);
              _lastFaderTapUp = DateTime(0);
            } else {
              _lastFaderTapUp = now;
            }
          },
          child: GestureDetector(
          onVerticalDragStart: (details) {
            _faderDragged = true;
            setState(() => _faderDragging = true);
            // Jump fader to click position
            final clickPos = 1.0 - (details.localPosition.dy / trackHeight).clamp(0.0, 1.0);
            final newVolume = FaderCurve.positionToLinear(clickPos);
            widget.provider.setBusVolume(widget.bus.id, newVolume);
          },
          onVerticalDragEnd: (_) => setState(() => _faderDragging = false),
          onVerticalDragUpdate: (details) {
            final currentPos = FaderCurve.linearToPosition(widget.bus.volume);
            final delta = -details.delta.dy / trackHeight;
            final newPos = (currentPos + delta).clamp(0.0, 1.0);
            final newVolume = FaderCurve.positionToLinear(newPos);
            widget.provider.setBusVolume(widget.bus.id, newVolume);
          },
          child: Container(
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgDeep,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Stack(
              children: [
                // Fader track
                Positioned(
                  left: 0, right: 0, top: 0, bottom: 0,
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
                // 0dB unity line
                Positioned(
                  left: 4, right: 4,
                  top: trackHeight * 0.15,
                  child: Container(
                    height: 1,
                    color: FluxForgeTheme.accentGreen.withOpacity(0.4),
                  ),
                ),
                // dB scale markers
                ..._buildDbMarkers(trackHeight),
                // Fader cap
                Positioned(
                  left: 2, right: 2,
                  top: faderY,
                  height: faderCapHeight,
                  child: _buildFaderCap(),
                ),
              ],
            ),
          ),
        ),
        );
      },
    );
  }

  List<Widget> _buildDbMarkers(double trackHeight) {
    const dbValues = [6, 0, -6, -12, -24, -48];
    final markers = <Widget>[];

    for (final db in dbValues) {
      final position = 1.0 - FaderCurve.dbToPosition(db.toDouble(), minDb: -60.0, maxDb: 12.0);
      final y = trackHeight * position;

      markers.add(
        Positioned(
          right: 1,
          top: y - 4,
          child: Text(
            '$db',
            style: TextStyle(
              fontSize: 7,
              color: db == 0
                  ? FluxForgeTheme.accentGreen.withOpacity(0.6)
                  : FluxForgeTheme.textTertiary.withOpacity(0.5),
            ),
          ),
        ),
      );

      markers.add(
        Positioned(
          left: 2, right: 2,
          top: y,
          child: Container(
            height: 0.5,
            color: FluxForgeTheme.textTertiary.withOpacity(0.15),
          ),
        ),
      );
    }

    return markers;
  }

  Widget _buildFaderCap() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: _faderDragging
              ? [
                  widget.color.withOpacity(0.9),
                  widget.color.withOpacity(0.7),
                  widget.color.withOpacity(0.6),
                  widget.color.withOpacity(0.7),
                  widget.color.withOpacity(0.8),
                ]
              : [
                  Colors.grey.shade200,
                  Colors.grey.shade400,
                  Colors.grey.shade500,
                  Colors.grey.shade400,
                  Colors.grey.shade300,
                ],
          stops: const [0.0, 0.2, 0.5, 0.8, 1.0],
        ),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: _faderDragging
              ? FluxForgeTheme.accentBlue
              : Colors.grey.shade600,
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: FluxForgeTheme.bgVoid.withOpacity(0.5),
            blurRadius: 3,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (int i = 0; i < 3; i++)
            Container(
              width: double.infinity,
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              color: (_faderDragging ? Colors.white : FluxForgeTheme.bgVoid)
                  .withOpacity(0.4),
            ),
        ],
      ),
    );
  }

  Widget _buildDbReadout() {
    final db = _volumeToDb(widget.bus.volume);
    final isHot = widget.bus.volume > 0.95;

    return Container(
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeepest,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(
          color: isHot
              ? FluxForgeTheme.accentRed.withOpacity(0.5)
              : FluxForgeTheme.borderSubtle,
          width: 0.5,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        '$db dB',
        style: TextStyle(
          fontSize: 9,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w600,
          color: isHot
              ? FluxForgeTheme.accentRed
              : FluxForgeTheme.textSecondary,
        ),
      ),
    );
  }

  Widget _buildButtons() {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: _buildChannelButton(
              'M',
              widget.bus.muted,
              FluxForgeTheme.accentRed,
              () => widget.provider.toggleMute(widget.bus.id),
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: _buildChannelButton(
              'S',
              widget.bus.solo,
              FluxForgeTheme.accentYellow,
              () => widget.provider.toggleSolo(widget.bus.id),
            ),
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
      margin: const EdgeInsets.all(3),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      alignment: Alignment.center,
      child: Text(
        widget.isMaster ? 'OUT 1-2' : 'Master',
        style: TextStyle(
          fontSize: 8,
          color: FluxForgeTheme.textSecondary,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
