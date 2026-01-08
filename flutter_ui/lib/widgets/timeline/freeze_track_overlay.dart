// Freeze Track Overlay
//
// Visual overlay and controls for frozen tracks:
// - Frozen state indicator
// - Unfreeze button
// - Freeze progress
// - CPU savings display
// - Waveform of frozen audio

import 'package:flutter/material.dart';
import '../../theme/reelforge_theme.dart';

/// Freeze state for a track
enum FreezeState {
  unfrozen,
  freezing,
  frozen,
  unfreezing,
}

/// Frozen track data
class FrozenTrackInfo {
  final String trackId;
  final String trackName;
  final FreezeState state;
  final double? progress; // 0-1 for freezing/unfreezing
  final double cpuSavings; // Percentage CPU saved
  final int frozenAtSampleRate;
  final int frozenBitDepth;
  final double frozenDuration;
  final DateTime? frozenAt;
  final List<String> frozenPlugins;

  FrozenTrackInfo({
    required this.trackId,
    required this.trackName,
    this.state = FreezeState.unfrozen,
    this.progress,
    this.cpuSavings = 0,
    this.frozenAtSampleRate = 48000,
    this.frozenBitDepth = 32,
    this.frozenDuration = 0,
    this.frozenAt,
    this.frozenPlugins = const [],
  });

  bool get isFrozen => state == FreezeState.frozen;
  bool get isProcessing => state == FreezeState.freezing || state == FreezeState.unfreezing;
}

/// Freeze Track Overlay Widget
class FreezeTrackOverlay extends StatelessWidget {
  final FrozenTrackInfo info;
  final double width;
  final double height;
  final VoidCallback? onUnfreeze;
  final VoidCallback? onFreeze;

  const FreezeTrackOverlay({
    super.key,
    required this.info,
    required this.width,
    required this.height,
    this.onUnfreeze,
    this.onFreeze,
  });

  @override
  Widget build(BuildContext context) {
    if (info.state == FreezeState.unfrozen) {
      return const SizedBox.shrink();
    }

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: _getOverlayColor(),
        border: Border.all(color: _getBorderColor(), width: 1),
      ),
      child: Stack(
        children: [
          // Frozen pattern (ice-like)
          if (info.isFrozen)
            Positioned.fill(
              child: CustomPaint(
                painter: _FrozenPatternPainter(),
              ),
            ),
          // Progress bar for freezing/unfreezing
          if (info.isProcessing && info.progress != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: LinearProgressIndicator(
                value: info.progress,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation(_getProgressColor()),
                minHeight: 3,
              ),
            ),
          // Status badge
          Positioned(
            right: 8,
            top: 8,
            child: _buildStatusBadge(),
          ),
          // Info overlay (shown on hover in actual implementation)
          if (info.isFrozen)
            Positioned(
              left: 8,
              bottom: 8,
              child: _buildInfoChip(),
            ),
        ],
      ),
    );
  }

  Color _getOverlayColor() {
    switch (info.state) {
      case FreezeState.unfrozen:
        return Colors.transparent;
      case FreezeState.freezing:
        return const Color(0xFF00BCD4).withValues(alpha: 0.15);
      case FreezeState.frozen:
        return const Color(0xFF00BCD4).withValues(alpha: 0.1);
      case FreezeState.unfreezing:
        return const Color(0xFFFF9800).withValues(alpha: 0.15);
    }
  }

  Color _getBorderColor() {
    switch (info.state) {
      case FreezeState.unfrozen:
        return Colors.transparent;
      case FreezeState.freezing:
        return const Color(0xFF00BCD4).withValues(alpha: 0.5);
      case FreezeState.frozen:
        return const Color(0xFF00BCD4).withValues(alpha: 0.3);
      case FreezeState.unfreezing:
        return const Color(0xFFFF9800).withValues(alpha: 0.5);
    }
  }

  Color _getProgressColor() {
    return info.state == FreezeState.unfreezing
        ? const Color(0xFFFF9800)
        : const Color(0xFF00BCD4);
  }

  Widget _buildStatusBadge() {
    IconData icon;
    String label;
    Color color;

    switch (info.state) {
      case FreezeState.unfrozen:
        return const SizedBox.shrink();
      case FreezeState.freezing:
        icon = Icons.ac_unit;
        label = 'Freezing...';
        color = const Color(0xFF00BCD4);
        break;
      case FreezeState.frozen:
        icon = Icons.ac_unit;
        label = 'Frozen';
        color = const Color(0xFF00BCD4);
        break;
      case FreezeState.unfreezing:
        icon = Icons.whatshot;
        label = 'Unfreezing...';
        color = const Color(0xFFFF9800);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
          ),
          if (info.isProcessing && info.progress != null) ...[
            const SizedBox(width: 4),
            Text(
              '${(info.progress! * 100).toInt()}%',
              style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 9),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgDeep.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (info.cpuSavings > 0) ...[
            const Icon(Icons.speed, size: 10, color: ReelForgeTheme.accentGreen),
            const SizedBox(width: 3),
            Text(
              '-${info.cpuSavings.toStringAsFixed(0)}% CPU',
              style: const TextStyle(color: ReelForgeTheme.accentGreen, fontSize: 9),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            '${info.frozenPlugins.length} plugins frozen',
            style: const TextStyle(color: Colors.white54, fontSize: 9),
          ),
        ],
      ),
    );
  }
}

/// Custom painter for frozen pattern
class _FrozenPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF00BCD4).withValues(alpha: 0.05)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // Draw subtle ice crystal pattern
    const spacing = 30.0;
    for (var x = 0.0; x < size.width + spacing; x += spacing) {
      for (var y = 0.0; y < size.height + spacing; y += spacing) {
        _drawSnowflake(canvas, Offset(x, y), 8, paint);
      }
    }
  }

  void _drawSnowflake(Canvas canvas, Offset center, double radius, Paint paint) {
    for (var i = 0; i < 6; i++) {
      final angle = i * 3.14159 / 3;
      final endX = center.dx + radius * 0.7 * (i.isEven ? 1 : 0.7) * (angle == 0 ? 1 : angle.abs() < 2 ? 0.8 : 0.6);
      final endY = center.dy + radius * 0.7 * (i.isEven ? 1 : 0.7);
      canvas.drawLine(center, Offset(endX, endY), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Freeze Track Button Widget (for track header)
class FreezeTrackButton extends StatelessWidget {
  final FrozenTrackInfo info;
  final VoidCallback? onPressed;

  const FreezeTrackButton({
    super.key,
    required this.info,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isFrozen = info.isFrozen;
    final isProcessing = info.isProcessing;

    return Tooltip(
      message: isFrozen ? 'Unfreeze Track' : 'Freeze Track',
      child: GestureDetector(
        onTap: isProcessing ? null : onPressed,
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: isFrozen
                ? const Color(0xFF00BCD4).withValues(alpha: 0.2)
                : ReelForgeTheme.bgDeep,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isFrozen
                  ? const Color(0xFF00BCD4)
                  : Colors.white24,
            ),
          ),
          child: isProcessing
              ? const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    valueColor: AlwaysStoppedAnimation(Color(0xFF00BCD4)),
                  ),
                )
              : Icon(
                  isFrozen ? Icons.ac_unit : Icons.ac_unit_outlined,
                  size: 14,
                  color: isFrozen ? const Color(0xFF00BCD4) : Colors.white38,
                ),
        ),
      ),
    );
  }
}

/// Freeze options dialog
class FreezeOptionsDialog extends StatefulWidget {
  final String trackName;
  final List<String> plugins;
  final void Function(FreezeOptions options)? onFreeze;

  const FreezeOptionsDialog({
    super.key,
    required this.trackName,
    required this.plugins,
    this.onFreeze,
  });

  @override
  State<FreezeOptionsDialog> createState() => _FreezeOptionsDialogState();
}

class _FreezeOptionsDialogState extends State<FreezeOptionsDialog> {
  bool _includeInserts = true;
  bool _includeSends = false;
  bool _tailMode = true;
  double _tailLength = 2.0; // seconds

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: ReelForgeTheme.bgMid,
      title: Row(
        children: [
          const Icon(Icons.ac_unit, color: Color(0xFF00BCD4), size: 20),
          const SizedBox(width: 8),
          Text(
            'Freeze Track: ${widget.trackName}',
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
        ],
      ),
      content: SizedBox(
        width: 350,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This will render the track with all effects to reduce CPU usage.',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              value: _includeInserts,
              onChanged: (v) => setState(() => _includeInserts = v ?? true),
              title: const Text('Include Insert Effects', style: TextStyle(color: Colors.white, fontSize: 13)),
              subtitle: Text(
                '${widget.plugins.length} plugins',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              activeColor: const Color(0xFF00BCD4),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
            CheckboxListTile(
              value: _includeSends,
              onChanged: (v) => setState(() => _includeSends = v ?? false),
              title: const Text('Include Send Effects', style: TextStyle(color: Colors.white, fontSize: 13)),
              activeColor: const Color(0xFF00BCD4),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
            const Divider(height: 24, color: ReelForgeTheme.borderSubtle),
            CheckboxListTile(
              value: _tailMode,
              onChanged: (v) => setState(() => _tailMode = v ?? true),
              title: const Text('Extend for Effect Tail', style: TextStyle(color: Colors.white, fontSize: 13)),
              activeColor: const Color(0xFF00BCD4),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
            if (_tailMode) ...[
              Row(
                children: [
                  const Text('Tail Length:', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Slider(
                      value: _tailLength,
                      min: 0.5,
                      max: 10.0,
                      divisions: 19,
                      label: '${_tailLength.toStringAsFixed(1)}s',
                      activeColor: const Color(0xFF00BCD4),
                      onChanged: (v) => setState(() => _tailLength = v),
                    ),
                  ),
                  Text(
                    '${_tailLength.toStringAsFixed(1)}s',
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'JetBrains Mono'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: () {
            widget.onFreeze?.call(FreezeOptions(
              includeInserts: _includeInserts,
              includeSends: _includeSends,
              tailLength: _tailMode ? _tailLength : 0,
            ));
            Navigator.pop(context);
          },
          icon: const Icon(Icons.ac_unit, size: 16),
          label: const Text('Freeze'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00BCD4),
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}

class FreezeOptions {
  final bool includeInserts;
  final bool includeSends;
  final double tailLength;

  FreezeOptions({
    this.includeInserts = true,
    this.includeSends = false,
    this.tailLength = 2.0,
  });
}
