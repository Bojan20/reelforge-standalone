/// FluxForge Studio Stinger Preview Panel
///
/// P4.11: Stinger Preview
/// - Visual preview of stinger playback
/// - Sync point visualization on beat grid
/// - Music ducking preview
/// - Priority and interrupt testing
/// - Quick trigger buttons
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/middleware_models.dart';
import '../../providers/middleware_provider.dart';
import '../../theme/fluxforge_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// STINGER PREVIEW PANEL
// ═══════════════════════════════════════════════════════════════════════════════

class StingerPreviewPanel extends StatefulWidget {
  final int? stingerId;
  final double height;

  const StingerPreviewPanel({
    super.key,
    this.stingerId,
    this.height = 280,
  });

  @override
  State<StingerPreviewPanel> createState() => _StingerPreviewPanelState();
}

class _StingerPreviewPanelState extends State<StingerPreviewPanel>
    with SingleTickerProviderStateMixin {
  // Playback state
  bool _isMusicPlaying = false;
  bool _isStingerTriggered = false;
  double _musicPosition = 0.0; // 0-1 in current bar
  double _stingerProgress = 0.0; // 0-1 playback progress
  double _duckingAmount = 0.0; // 0-1 ducking level

  // Preview settings
  double _previewTempo = 120.0;
  int _beatsPerBar = 4;

  // Animation
  late AnimationController _animationController;
  Timer? _beatTimer;
  int _currentBeat = 0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
  }

  @override
  void dispose() {
    _beatTimer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  Stinger? _getStinger(MiddlewareProvider provider) {
    if (widget.stingerId == null) return null;
    return provider.stingers.where((s) => s.id == widget.stingerId).firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MiddlewareProvider>(
      builder: (context, provider, _) {
        final stinger = _getStinger(provider);
        final stingers = provider.stingers;

        return Container(
          height: widget.height,
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgDeep,
            border: Border(
              top: BorderSide(color: FluxForgeTheme.border.withValues(alpha: 0.3)),
            ),
          ),
          child: Column(
            children: [
              _buildHeader(stinger),
              Expanded(
                child: Row(
                  children: [
                    // Left: Quick trigger buttons
                    SizedBox(
                      width: 180,
                      child: _buildQuickTriggers(stingers),
                    ),
                    // Divider
                    Container(
                      width: 1,
                      color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.2),
                    ),
                    // Center: Beat grid visualization
                    Expanded(
                      child: _buildBeatGridVisualization(stinger),
                    ),
                    // Divider
                    Container(
                      width: 1,
                      color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.2),
                    ),
                    // Right: Stinger details
                    SizedBox(
                      width: 200,
                      child: stinger != null
                          ? _buildStingerDetails(stinger)
                          : _buildEmptyDetails(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // HEADER
  // ═══════════════════════════════════════════════════════════════════════════════

  Widget _buildHeader(Stinger? stinger) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.2)),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.flash_on, size: 16, color: Colors.amber),
          const SizedBox(width: 8),
          Text(
            'Stinger Preview',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (stinger != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                stinger.name,
                style: TextStyle(color: Colors.amber, fontSize: 11),
              ),
            ),
          ],
          const Spacer(),
          // Music transport controls
          _buildMusicTransport(),
        ],
      ),
    );
  }

  Widget _buildMusicTransport() {
    return Row(
      children: [
        // Tempo
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.pink.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              Icon(Icons.speed, size: 12, color: Colors.pink),
              const SizedBox(width: 4),
              Text(
                '${_previewTempo.toStringAsFixed(0)} BPM',
                style: TextStyle(color: Colors.pink, fontSize: 10),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // Time signature
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgDeep,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '$_beatsPerBar/4',
            style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 10),
          ),
        ),
        const SizedBox(width: 12),
        // Play/Stop music
        IconButton(
          icon: Icon(
            _isMusicPlaying ? Icons.pause : Icons.play_arrow,
            size: 20,
            color: _isMusicPlaying ? Colors.pink : FluxForgeTheme.textPrimary,
          ),
          onPressed: _toggleMusic,
          tooltip: _isMusicPlaying ? 'Stop Music' : 'Play Music',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // QUICK TRIGGERS
  // ═══════════════════════════════════════════════════════════════════════════════

  Widget _buildQuickTriggers(List<Stinger> stingers) {
    return Container(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quick Triggers',
            style: TextStyle(
              color: FluxForgeTheme.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: stingers.length,
              itemBuilder: (context, index) {
                final stinger = stingers[index];
                final isSelected = widget.stingerId == stinger.id;
                final isTriggered = _isStingerTriggered && isSelected;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _buildTriggerButton(stinger, isSelected, isTriggered),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTriggerButton(Stinger stinger, bool isSelected, bool isTriggered) {
    return Material(
      color: isTriggered
          ? Colors.amber.withValues(alpha: 0.3)
          : isSelected
              ? FluxForgeTheme.accent.withValues(alpha: 0.2)
              : FluxForgeTheme.bgSurface,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: () => _triggerStinger(stinger),
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isTriggered
                  ? Colors.amber
                  : isSelected
                      ? FluxForgeTheme.accent.withValues(alpha: 0.5)
                      : FluxForgeTheme.borderSubtle.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              // Priority badge
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: _getPriorityColor(stinger.priority).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    stinger.priority.toString(),
                    style: TextStyle(
                      color: _getPriorityColor(stinger.priority),
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Name
              Expanded(
                child: Text(
                  stinger.name,
                  style: TextStyle(
                    color: isTriggered ? Colors.amber : FluxForgeTheme.textPrimary,
                    fontSize: 11,
                    fontWeight: isTriggered ? FontWeight.w600 : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Sync point icon
              Icon(
                _getSyncPointIcon(stinger.syncPoint),
                size: 14,
                color: FluxForgeTheme.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // BEAT GRID VISUALIZATION
  // ═══════════════════════════════════════════════════════════════════════════════

  Widget _buildBeatGridVisualization(Stinger? stinger) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // Beat grid
          Expanded(
            child: CustomPaint(
              painter: _BeatGridPainter(
                beatsPerBar: _beatsPerBar,
                currentBeat: _currentBeat,
                musicPosition: _musicPosition,
                stingerTriggered: _isStingerTriggered,
                stingerProgress: _stingerProgress,
                duckingAmount: _duckingAmount,
                syncPoint: stinger?.syncPoint ?? MusicSyncPoint.beat,
              ),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: 8),
          // Legend
          _buildLegend(stinger),
        ],
      ),
    );
  }

  Widget _buildLegend(Stinger? stinger) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildLegendItem(Colors.pink, 'Music'),
        const SizedBox(width: 16),
        _buildLegendItem(Colors.amber, 'Stinger'),
        const SizedBox(width: 16),
        _buildLegendItem(Colors.purple, 'Ducking'),
        if (stinger != null) ...[
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgSurface,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'Sync: ${stinger.syncPoint.displayName}',
              style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 10),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: color),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 10),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // STINGER DETAILS
  // ═══════════════════════════════════════════════════════════════════════════════

  Widget _buildStingerDetails(Stinger stinger) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sync Point
            _buildDetailRow('Sync Point', stinger.syncPoint.displayName),
            if (stinger.syncPoint == MusicSyncPoint.customGrid)
              _buildDetailRow('Grid', '${stinger.customGridBeats} beats'),
            const SizedBox(height: 8),
            // Priority
            _buildDetailRow(
              'Priority',
              '${stinger.priority}',
              valueColor: _getPriorityColor(stinger.priority),
            ),
            _buildDetailRow(
              'Can Interrupt',
              stinger.canInterrupt ? 'Yes' : 'No',
              valueColor: stinger.canInterrupt ? Colors.green : FluxForgeTheme.textMuted,
            ),
            const SizedBox(height: 12),
            // Ducking section
            Text(
              'MUSIC DUCKING',
              style: TextStyle(
                color: Colors.purple,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            _buildDetailRow('Duck Level', '${stinger.musicDuckDb.toStringAsFixed(1)} dB'),
            _buildDetailRow('Attack', '${stinger.duckAttackMs.toStringAsFixed(0)} ms'),
            _buildDetailRow('Release', '${stinger.duckReleaseMs.toStringAsFixed(0)} ms'),
            const SizedBox(height: 16),
            // Ducking preview
            _buildDuckingMeter(stinger),
            const SizedBox(height: 16),
            // Trigger button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: Icon(Icons.flash_on, size: 16),
                label: const Text('Trigger'),
                onPressed: () => _triggerStinger(stinger),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 11),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? FluxForgeTheme.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDuckingMeter(Stinger stinger) {
    final duckLevel = stinger.musicDuckDb.abs() / 30.0; // Normalize to 0-1

    return Column(
      children: [
        Container(
          height: 20,
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgSurface,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Stack(
            children: [
              // Full bar (music level without ducking)
              Container(
                decoration: BoxDecoration(
                  color: Colors.pink.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              // Ducked level
              FractionallySizedBox(
                widthFactor: 1.0 - (_duckingAmount * duckLevel),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.pink,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Music Level',
          style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 9),
        ),
      ],
    );
  }

  Widget _buildEmptyDetails() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.flash_off, size: 32, color: FluxForgeTheme.textMuted),
          const SizedBox(height: 8),
          Text(
            'Select a stinger',
            style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════════

  Color _getPriorityColor(int priority) {
    if (priority >= 80) return Colors.red;
    if (priority >= 60) return Colors.orange;
    if (priority >= 40) return Colors.yellow;
    return Colors.green;
  }

  IconData _getSyncPointIcon(MusicSyncPoint syncPoint) {
    switch (syncPoint) {
      case MusicSyncPoint.immediate:
        return Icons.flash_on;
      case MusicSyncPoint.beat:
        return Icons.music_note;
      case MusicSyncPoint.bar:
        return Icons.view_week;
      case MusicSyncPoint.marker:
        return Icons.location_on;
      case MusicSyncPoint.customGrid:
        return Icons.grid_on;
      case MusicSyncPoint.segmentEnd:
        return Icons.last_page;
    }
  }

  void _toggleMusic() {
    setState(() => _isMusicPlaying = !_isMusicPlaying);

    if (_isMusicPlaying) {
      final beatDuration = Duration(milliseconds: (60000 / _previewTempo).round());
      _beatTimer = Timer.periodic(beatDuration, (timer) {
        setState(() {
          _currentBeat = (_currentBeat + 1) % _beatsPerBar;
          _musicPosition = _currentBeat / _beatsPerBar;
        });
      });
    } else {
      _beatTimer?.cancel();
      setState(() {
        _currentBeat = 0;
        _musicPosition = 0;
      });
    }
  }

  void _triggerStinger(Stinger stinger) {
    if (_isStingerTriggered) return;

    setState(() {
      _isStingerTriggered = true;
      _stingerProgress = 0;
      _duckingAmount = 0;
    });

    // Animate stinger playback
    _animationController.reset();
    _animationController.duration = const Duration(milliseconds: 1500);
    _animationController.forward();

    _animationController.addListener(_updateStingerProgress);
    _animationController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _animationController.removeListener(_updateStingerProgress);
        setState(() {
          _isStingerTriggered = false;
          _stingerProgress = 0;
          _duckingAmount = 0;
        });
      }
    });
  }

  void _updateStingerProgress() {
    setState(() {
      _stingerProgress = _animationController.value;

      // Simulate ducking envelope
      if (_animationController.value < 0.1) {
        _duckingAmount = _animationController.value * 10; // Attack
      } else if (_animationController.value > 0.8) {
        _duckingAmount = (1.0 - _animationController.value) * 5; // Release
      } else {
        _duckingAmount = 1.0; // Sustain
      }
    });
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PAINTERS
// ═══════════════════════════════════════════════════════════════════════════════

class _BeatGridPainter extends CustomPainter {
  final int beatsPerBar;
  final int currentBeat;
  final double musicPosition;
  final bool stingerTriggered;
  final double stingerProgress;
  final double duckingAmount;
  final MusicSyncPoint syncPoint;

  _BeatGridPainter({
    required this.beatsPerBar,
    required this.currentBeat,
    required this.musicPosition,
    required this.stingerTriggered,
    required this.stingerProgress,
    required this.duckingAmount,
    required this.syncPoint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final beatWidth = size.width / beatsPerBar;

    // Draw beat grid background
    for (int i = 0; i < beatsPerBar; i++) {
      final isCurrentBeat = i == currentBeat;
      final rect = Rect.fromLTWH(i * beatWidth + 2, 0, beatWidth - 4, size.height);

      // Beat background
      final bgPaint = Paint()
        ..color = isCurrentBeat
            ? Colors.pink.withValues(alpha: 0.3)
            : FluxForgeTheme.bgSurface;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        bgPaint,
      );

      // Beat border
      final borderPaint = Paint()
        ..color = isCurrentBeat ? Colors.pink : FluxForgeTheme.borderSubtle.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isCurrentBeat ? 2 : 1;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        borderPaint,
      );

      // Beat number
      final textSpan = TextSpan(
        text: '${i + 1}',
        style: TextStyle(
          color: isCurrentBeat ? Colors.pink : FluxForgeTheme.textMuted,
          fontSize: 12,
          fontWeight: isCurrentBeat ? FontWeight.bold : FontWeight.normal,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(
          i * beatWidth + (beatWidth - textPainter.width) / 2,
          size.height - 20,
        ),
      );
    }

    // Draw sync point indicator
    _drawSyncPointIndicator(canvas, size, beatWidth);

    // Draw stinger overlay
    if (stingerTriggered) {
      final stingerRect = Rect.fromLTWH(
        0,
        size.height * 0.1,
        size.width * stingerProgress,
        size.height * 0.3,
      );
      final stingerPaint = Paint()
        ..color = Colors.amber.withValues(alpha: 0.5);
      canvas.drawRRect(
        RRect.fromRectAndRadius(stingerRect, const Radius.circular(4)),
        stingerPaint,
      );

      // Stinger waveform simulation
      _drawStingerWaveform(canvas, size, stingerProgress);
    }

    // Draw ducking effect
    if (duckingAmount > 0) {
      final duckRect = Rect.fromLTWH(
        0,
        size.height * 0.5,
        size.width,
        size.height * 0.15 * (1 - duckingAmount),
      );
      final duckPaint = Paint()
        ..color = Colors.purple.withValues(alpha: 0.3);
      canvas.drawRect(duckRect, duckPaint);
    }
  }

  void _drawSyncPointIndicator(Canvas canvas, Size size, double beatWidth) {
    double indicatorX;
    switch (syncPoint) {
      case MusicSyncPoint.immediate:
        indicatorX = musicPosition * size.width;
      case MusicSyncPoint.beat:
        indicatorX = (currentBeat + 1) % beatsPerBar * beatWidth;
      case MusicSyncPoint.bar:
        indicatorX = 0;
      case MusicSyncPoint.marker:
      case MusicSyncPoint.customGrid:
      case MusicSyncPoint.segmentEnd:
        indicatorX = size.width;
    }

    final indicatorPaint = Paint()
      ..color = Colors.green
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(indicatorX, 0),
      Offset(indicatorX, size.height),
      indicatorPaint,
    );

    // Draw triangle marker
    final path = Path()
      ..moveTo(indicatorX, 0)
      ..lineTo(indicatorX - 6, 8)
      ..lineTo(indicatorX + 6, 8)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.green);
  }

  void _drawStingerWaveform(Canvas canvas, Size size, double progress) {
    final path = Path();
    final waveHeight = size.height * 0.12;
    final centerY = size.height * 0.25;

    for (int i = 0; i < (size.width * progress).round(); i += 3) {
      final amplitude = (i / size.width) < 0.2
          ? (i / (size.width * 0.2)) // Attack
          : (i / size.width) > 0.7
              ? 1 - ((i / size.width - 0.7) / 0.3) // Release
              : 1.0; // Sustain

      final y = centerY + (i % 6 < 3 ? 1 : -1) * waveHeight * amplitude * (0.5 + 0.5 * ((i * 7) % 11) / 11);

      if (i == 0) {
        path.moveTo(i.toDouble(), y);
      } else {
        path.lineTo(i.toDouble(), y);
      }
    }

    final paint = Paint()
      ..color = Colors.amber
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_BeatGridPainter oldDelegate) {
    return currentBeat != oldDelegate.currentBeat ||
        musicPosition != oldDelegate.musicPosition ||
        stingerTriggered != oldDelegate.stingerTriggered ||
        stingerProgress != oldDelegate.stingerProgress ||
        duckingAmount != oldDelegate.duckingAmount;
  }
}
