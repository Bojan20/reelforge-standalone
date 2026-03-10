// Aux Sends Panel — DAW-style vertical fader mixer for SlotLab Lower Zone
//
// Pro Tools / Cubase-style send routing:
// - Each aux bus as a vertical channel strip
// - Return level fader with gradient cap + grip lines
// - Per-track send level faders in a scrollable row
// - Pre/Post fader toggle per send
// - Mute/Solo on aux returns
// - Effect type label
// - Real-time meters via SharedMeterReader

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../../providers/mixer_dsp_provider.dart';
import '../../services/shared_meter_reader.dart';
import '../../theme/fluxforge_theme.dart';
import '../../utils/audio_math.dart';

/// DAW-style Aux Sends Panel
class AuxSendsPanel extends StatefulWidget {
  final double height;

  const AuxSendsPanel({
    super.key,
    this.height = 250,
  });

  @override
  State<AuxSendsPanel> createState() => _AuxSendsPanelState();
}

class _AuxSendsPanelState extends State<AuxSendsPanel>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  bool _meterInitialized = false;
  SharedMeterSnapshot _snapshot = SharedMeterSnapshot.empty;

  int? _selectedAuxId;

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
    if (mounted) setState(() => _meterInitialized = success);
  }

  void _onTick(Duration elapsed) {
    if (!_meterInitialized) return;
    if (SharedMeterReader.instance.hasChanged) {
      setState(() => _snapshot = SharedMeterReader.instance.readMeters());
    }
  }

  /// Derive aux bus meter peak from master signal, scaled by return level.
  /// Returns 0 when not playing or muted — no fake signal.
  double _getAuxPeakL(AuxBus aux) {
    if (!_meterInitialized || !_snapshot.isPlaying || aux.isMuted) return 0.0;
    return (_snapshot.masterPeakL * aux.returnLevel).clamp(0.0, 1.0);
  }

  double _getAuxPeakR(AuxBus aux) {
    if (!_meterInitialized || !_snapshot.isPlaying || aux.isMuted) return 0.0;
    return (_snapshot.masterPeakR * aux.returnLevel).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MixerDSPProvider>();
    final auxBuses = provider.auxBuses;
    final hasSolo = auxBuses.any((b) => b.isSoloed);

    return Container(
      color: FluxForgeTheme.bgDeepest,
      child: Row(
        children: [
          // Left: Aux return channel strips (DAW mixer style)
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(width: 4),
                    for (final aux in auxBuses)
                      _AuxReturnStrip(
                        key: ValueKey('aux_${aux.id}'),
                        aux: aux,
                        hasSoloActive: hasSolo,
                        isSelected: _selectedAuxId == aux.id,
                        onTap: () => setState(() => _selectedAuxId = aux.id),
                        onVolumeChange: (v) => provider.setAuxReturnLevel(aux.id, v),
                        onMuteToggle: () => provider.toggleAuxMute(aux.id),
                        onSoloToggle: () => provider.toggleAuxSolo(aux.id),
                        peakL: _getAuxPeakL(aux),
                        peakR: _getAuxPeakR(aux),
                      ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ),
          ),
          // Divider
          Container(width: 1, color: FluxForgeTheme.borderSubtle),
          // Right: Send levels for selected aux
          SizedBox(
            width: 200,
            child: _selectedAuxId != null
                ? _buildSendLevelsPanel(provider)
                : _buildEmptySelection(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptySelection() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.call_split, size: 28, color: FluxForgeTheme.textTertiary.withOpacity(0.3)),
          const SizedBox(height: 8),
          Text(
            'Select aux bus',
            style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildSendLevelsPanel(MixerDSPProvider provider) {
    final aux = provider.auxBuses.firstWhere(
      (a) => a.id == _selectedAuxId,
      orElse: () => provider.auxBuses.first,
    );
    final trackSends = provider.trackSends;

    return Column(
      children: [
        // Header
        Container(
          height: 28,
          color: aux.color,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${aux.name} SENDS',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: aux.color.computeLuminance() > 0.5
                        ? FluxForgeTheme.bgVoid
                        : FluxForgeTheme.textPrimary,
                  ),
                ),
              ),
              Text(
                aux.effectType.toUpperCase(),
                style: TextStyle(
                  fontSize: 8,
                  color: (aux.color.computeLuminance() > 0.5
                          ? FluxForgeTheme.bgVoid
                          : FluxForgeTheme.textPrimary)
                      .withOpacity(0.6),
                ),
              ),
            ],
          ),
        ),
        // Per-track send faders
        Expanded(
          child: ListView.builder(
            itemCount: trackSends.length,
            itemBuilder: (context, index) {
              final track = trackSends[index];
              final level = track.sendLevels[aux.id] ?? 0.0;
              final isPre = track.prePost[aux.id] ?? false;

              return _SendRow(
                trackName: track.trackName,
                level: level,
                isPreFader: isPre,
                color: aux.color,
                onLevelChange: (v) {
                  provider.setTrackSendLevel(track.trackId, aux.id, v);
                },
                onPrePostToggle: () {
                  provider.toggleTrackSendPrePost(track.trackId, aux.id);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Single aux return channel strip — DAW mixer style
class _AuxReturnStrip extends StatefulWidget {
  final AuxBus aux;
  final bool hasSoloActive;
  final bool isSelected;
  final VoidCallback onTap;
  final ValueChanged<double> onVolumeChange;
  final VoidCallback onMuteToggle;
  final VoidCallback onSoloToggle;
  final double peakL;
  final double peakR;

  const _AuxReturnStrip({
    super.key,
    required this.aux,
    required this.hasSoloActive,
    required this.isSelected,
    required this.onTap,
    required this.onVolumeChange,
    required this.onMuteToggle,
    required this.onSoloToggle,
    this.peakL = 0.0,
    this.peakR = 0.0,
  });

  @override
  State<_AuxReturnStrip> createState() => _AuxReturnStripState();
}

class _AuxReturnStripState extends State<_AuxReturnStrip> {
  bool _faderDragging = false;
  DateTime _lastFaderTapUp = DateTime(0);
  bool _faderDragged = false;

  String _volumeToDb(double volume) => FaderCurve.linearToDbString(volume);

  @override
  Widget build(BuildContext context) {
    final aux = widget.aux;
    final isDimmed = widget.hasSoloActive && !aux.isSoloed;

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 120),
        opacity: isDimmed ? 0.35 : 1.0,
        child: Container(
          width: 64,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgSurface,
            border: Border(
              right: BorderSide(color: FluxForgeTheme.borderSubtle),
              left: widget.isSelected
                  ? BorderSide(color: aux.color, width: 2)
                  : BorderSide.none,
            ),
          ),
          child: Column(
            children: [
              // Header with aux name
              _buildHeader(),
              // Effect type label
              _buildEffectLabel(),
              // Fader + meter
              Expanded(child: _buildFaderSection()),
              // dB readout
              _buildDbReadout(),
              // M/S buttons
              _buildButtons(),
              // Output label
              _buildOutputLabel(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 24,
      decoration: BoxDecoration(color: widget.aux.color),
      alignment: Alignment.center,
      child: Text(
        widget.aux.name.toUpperCase(),
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: widget.aux.color.computeLuminance() > 0.5
              ? FluxForgeTheme.bgVoid
              : FluxForgeTheme.textPrimary,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildEffectLabel() {
    return Container(
      height: 20,
      decoration: BoxDecoration(
        color: widget.aux.color.withOpacity(0.1),
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        widget.aux.effectType.toUpperCase(),
        style: TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.w600,
          color: widget.aux.color.withOpacity(0.7),
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildFaderSection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
      child: Row(
        children: [
          // Stereo meter
          SizedBox(
            width: 10,
            child: _buildStereoMeter(),
          ),
          const SizedBox(width: 3),
          // Fader
          Expanded(child: _buildFader()),
        ],
      ),
    );
  }

  Widget _buildStereoMeter() {
    // Meters only show signal during playback — reads from SharedMeterReader
    // Aux buses don't have dedicated meter channels yet, so we derive from
    // master peak scaled by return level (approximation until per-bus meters exist)
    final peakL = widget.peakL;
    final peakR = widget.peakR;

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;

        return Row(
          children: [
            Expanded(child: _buildMeterBar(peakL, height)),
            const SizedBox(width: 1),
            Expanded(child: _buildMeterBar(peakR, height)),
          ],
        );
      },
    );
  }

  Widget _buildMeterBar(double peak, double height) {
    final peakDb = peak > 0 ? 20 * math.log(peak) / math.ln10 : -60.0;
    final normalized = ((peakDb + 60.0) / 60.0).clamp(0.0, 1.0);
    final barHeight = normalized * height;

    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeepest,
        borderRadius: BorderRadius.circular(1),
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          height: barHeight,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                widget.aux.color.withOpacity(0.6),
                peak > 0.7
                    ? FluxForgeTheme.accentOrange
                    : widget.aux.color,
              ],
            ),
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ),
    );
  }

  Widget _buildFader() {
    final volume = widget.aux.returnLevel;
    final faderPos = FaderCurve.linearToPosition(volume);

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final faderCapHeight = 28.0;
        final trackHeight = height - faderCapHeight;
        final faderY = trackHeight * (1 - faderPos);

        return Listener(
          onPointerDown: (_) {
            _faderDragged = false;
          },
          onPointerUp: (_) {
            if (_faderDragged) return;
            final now = DateTime.now();
            if (now.difference(_lastFaderTapUp).inMilliseconds < 300) {
              widget.onVolumeChange(1.0);
              _lastFaderTapUp = DateTime(0);
            } else {
              _lastFaderTapUp = now;
            }
          },
          child: GestureDetector(
          onVerticalDragStart: (details) {
            _faderDragged = true;
            setState(() => _faderDragging = true);
            widget.onTap(); // Auto-select this aux bus
            // Jump fader to click position
            final clickPos = 1.0 - (details.localPosition.dy / trackHeight).clamp(0.0, 1.0);
            final newVolume = FaderCurve.positionToLinear(clickPos);
            widget.onVolumeChange(newVolume);
          },
          onVerticalDragEnd: (_) => setState(() => _faderDragging = false),
          onVerticalDragUpdate: (details) {
            final currentPos = FaderCurve.linearToPosition(widget.aux.returnLevel);
            final delta = -details.delta.dy / trackHeight;
            final newPos = (currentPos + delta).clamp(0.0, 1.0);
            final newVolume = FaderCurve.positionToLinear(newPos);
            widget.onVolumeChange(newVolume);
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
                // dB markers
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
    const dbValues = [0, -6, -12, -24, -48];
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
                  widget.aux.color.withOpacity(0.9),
                  widget.aux.color.withOpacity(0.7),
                  widget.aux.color.withOpacity(0.6),
                  widget.aux.color.withOpacity(0.7),
                  widget.aux.color.withOpacity(0.8),
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
    final db = _volumeToDb(widget.aux.returnLevel);
    final isHot = widget.aux.returnLevel > 0.95;

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
          color: isHot ? FluxForgeTheme.accentRed : FluxForgeTheme.textSecondary,
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
              widget.aux.isMuted,
              FluxForgeTheme.accentRed,
              widget.onMuteToggle,
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: _buildChannelButton(
              'S',
              widget.aux.isSoloed,
              FluxForgeTheme.accentYellow,
              widget.onSoloToggle,
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

  Widget _buildOutputLabel() {
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
        'Master',
        style: TextStyle(fontSize: 8, color: FluxForgeTheme.textSecondary),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Per-track send level row in the right panel
class _SendRow extends StatefulWidget {
  final String trackName;
  final double level;
  final bool isPreFader;
  final Color color;
  final ValueChanged<double> onLevelChange;
  final VoidCallback onPrePostToggle;

  const _SendRow({
    required this.trackName,
    required this.level,
    required this.isPreFader,
    required this.color,
    required this.onLevelChange,
    required this.onPrePostToggle,
  });

  @override
  State<_SendRow> createState() => _SendRowState();
}

class _SendRowState extends State<_SendRow> {
  bool _dragging = false;
  DateTime _lastTapUp = DateTime(0);
  bool _sendDragged = false;

  @override
  Widget build(BuildContext context) {
    final dbStr = widget.level > 0.001
        ? FaderCurve.linearToDbString(widget.level)
        : '-inf';

    return Container(
      height: 40,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle.withOpacity(0.5)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          // Track name
          SizedBox(
            width: 56,
            child: Text(
              widget.trackName,
              style: TextStyle(
                fontSize: 9,
                color: FluxForgeTheme.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          // Pre/Post toggle
          GestureDetector(
            onTap: widget.onPrePostToggle,
            child: Container(
              width: 28,
              height: 16,
              decoration: BoxDecoration(
                color: widget.isPreFader
                    ? widget.color.withOpacity(0.2)
                    : FluxForgeTheme.bgDeep,
                borderRadius: BorderRadius.circular(2),
                border: Border.all(
                  color: widget.isPreFader
                      ? widget.color.withOpacity(0.5)
                      : FluxForgeTheme.borderSubtle,
                  width: 0.5,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                widget.isPreFader ? 'PRE' : 'PST',
                style: TextStyle(
                  fontSize: 7,
                  fontWeight: FontWeight.bold,
                  color: widget.isPreFader
                      ? widget.color
                      : FluxForgeTheme.textTertiary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Horizontal fader (mini DAW style)
          Expanded(
            child: Listener(
              onPointerDown: (_) {
                _sendDragged = false;
              },
              onPointerUp: (_) {
                if (_sendDragged) return;
                final now = DateTime.now();
                if (now.difference(_lastTapUp).inMilliseconds < 300) {
                  widget.onLevelChange(1.0);
                  _lastTapUp = DateTime(0);
                } else {
                  _lastTapUp = now;
                }
              },
              child: GestureDetector(
              onHorizontalDragStart: (details) {
                _sendDragged = true;
                setState(() => _dragging = true);
              },
              onHorizontalDragEnd: (_) => setState(() => _dragging = false),
              onHorizontalDragUpdate: (details) {
                final delta = details.delta.dx / 80;
                widget.onLevelChange((widget.level + delta).clamp(0.0, kMaxVolume));
              },
              child: Container(
                height: 20,
                decoration: BoxDecoration(
                  color: FluxForgeTheme.bgDeepest,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: _dragging
                        ? widget.color.withOpacity(0.5)
                        : FluxForgeTheme.borderSubtle,
                    width: 0.5,
                  ),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final trackWidth = constraints.maxWidth;
                    final thumbWidth = 14.0;
                    final usableWidth = trackWidth - thumbWidth;
                    final thumbX = usableWidth * widget.level;

                    return Stack(
                      children: [
                        // Track center line
                        Center(
                          child: Container(
                            height: 2,
                            decoration: BoxDecoration(
                              color: FluxForgeTheme.bgDeep,
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                        ),
                        // Fill
                        Positioned(
                          left: 0,
                          top: 4,
                          bottom: 4,
                          width: thumbX + thumbWidth / 2,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  widget.color.withOpacity(0.15),
                                  widget.color.withOpacity(0.3),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        // Thumb (mini fader cap)
                        Positioned(
                          left: thumbX,
                          top: 2,
                          bottom: 2,
                          child: Container(
                            width: thumbWidth,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: _dragging
                                    ? [
                                        widget.color.withOpacity(0.9),
                                        widget.color.withOpacity(0.7),
                                      ]
                                    : [
                                        Colors.grey.shade300,
                                        Colors.grey.shade500,
                                      ],
                              ),
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(
                                color: _dragging
                                    ? widget.color
                                    : Colors.grey.shade600,
                                width: 0.5,
                              ),
                            ),
                            child: Center(
                              child: Container(
                                width: 6,
                                height: 1,
                                color: (_dragging ? Colors.white : FluxForgeTheme.bgVoid)
                                    .withOpacity(0.4),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            ),
          ),
          const SizedBox(width: 4),
          // dB readout
          SizedBox(
            width: 34,
            child: Container(
              height: 16,
              decoration: BoxDecoration(
                color: FluxForgeTheme.bgDeep,
                borderRadius: BorderRadius.circular(2),
              ),
              alignment: Alignment.center,
              child: Text(
                dbStr,
                style: TextStyle(
                  fontSize: 8,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                  color: FluxForgeTheme.textTertiary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
