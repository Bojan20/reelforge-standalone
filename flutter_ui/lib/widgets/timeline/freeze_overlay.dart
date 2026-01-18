// Freeze Track UI Overlay
// Displays frozen state indicator and controls on track headers

import 'dart:ffi' as ffi;
import 'package:flutter/material.dart';

// FFI bindings for freeze operations
typedef TrackFreezeNative = ffi.Int32 Function(
    ffi.Uint64 trackId, ffi.Double startTime, ffi.Double endTime);
typedef TrackFreezeDart = int Function(
    int trackId, double startTime, double endTime);

typedef TrackUnfreezeNative = ffi.Int32 Function(ffi.Uint64 trackId);
typedef TrackUnfreezeDart = int Function(int trackId);

typedef TrackIsFrozenNative = ffi.Int32 Function(ffi.Uint64 trackId);
typedef TrackIsFrozenDart = int Function(int trackId);

typedef FreezeCacheSizeMbNative = ffi.Float Function();
typedef FreezeCacheSizeMbDart = double Function();

typedef FreezeClearCacheNative = ffi.Void Function();
typedef FreezeClearCacheDart = void Function();

/// Freeze state for a track
enum FreezeState {
  unfrozen,
  freezing,
  frozen,
  unfreezing,
}

/// Freeze indicator widget shown on track header
class FreezeIndicator extends StatelessWidget {
  final FreezeState state;
  final double progress;
  final VoidCallback? onTap;

  const FreezeIndicator({
    super.key,
    required this.state,
    this.progress = 0.0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: _backgroundColor,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: _borderColor,
            width: 1,
          ),
        ),
        child: _buildContent(),
      ),
    );
  }

  Color get _backgroundColor {
    switch (state) {
      case FreezeState.unfrozen:
        return const Color(0xFF1a1a20);
      case FreezeState.freezing:
      case FreezeState.unfreezing:
        return const Color(0xFF1a2a3a);
      case FreezeState.frozen:
        return const Color(0xFF0a3a5a);
    }
  }

  Color get _borderColor {
    switch (state) {
      case FreezeState.unfrozen:
        return const Color(0xFF3a3a40);
      case FreezeState.freezing:
      case FreezeState.unfreezing:
        return const Color(0xFF4a9eff);
      case FreezeState.frozen:
        return const Color(0xFF40c8ff);
    }
  }

  Widget _buildContent() {
    switch (state) {
      case FreezeState.unfrozen:
        return const Icon(
          Icons.ac_unit,
          size: 14,
          color: Color(0xFF6a6a70),
        );
      case FreezeState.freezing:
      case FreezeState.unfreezing:
        return SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            value: progress,
            strokeWidth: 2,
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF4a9eff)),
            backgroundColor: const Color(0xFF2a2a30),
          ),
        );
      case FreezeState.frozen:
        return const Icon(
          Icons.ac_unit,
          size: 14,
          color: Color(0xFF40c8ff),
        );
    }
  }
}

/// Frozen track waveform overlay
class FrozenWaveformOverlay extends StatelessWidget {
  final double width;
  final double height;

  const FrozenWaveformOverlay({
    super.key,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF40c8ff).withValues(alpha: 0.1),
            const Color(0xFF40c8ff).withValues(alpha: 0.05),
          ],
        ),
      ),
      child: CustomPaint(
        painter: _FrozenPatternPainter(),
      ),
    );
  }
}

class _FrozenPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF40c8ff).withValues(alpha: 0.15)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // Draw diagonal lines pattern
    const spacing = 12.0;
    for (double x = -size.height; x < size.width; x += spacing) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Freeze context menu
class FreezeContextMenu extends StatelessWidget {
  final int trackId;
  final FreezeState state;
  final VoidCallback onFreeze;
  final VoidCallback onUnfreeze;
  final VoidCallback? onClose;

  const FreezeContextMenu({
    super.key,
    required this.trackId,
    required this.state,
    required this.onFreeze,
    required this.onUnfreeze,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFF3a3a40),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(),
          const Divider(color: Color(0xFF3a3a40), height: 1),
          if (state == FreezeState.unfrozen) ...[
            _buildMenuItem(
              icon: Icons.ac_unit,
              label: 'Freeze Track',
              onTap: onFreeze,
            ),
            _buildMenuItem(
              icon: Icons.ac_unit,
              label: 'Freeze with Tail (5s)',
              onTap: onFreeze,
              subtitle: 'Include reverb/delay tails',
            ),
          ],
          if (state == FreezeState.frozen) ...[
            _buildMenuItem(
              icon: Icons.whatshot,
              label: 'Unfreeze Track',
              onTap: onUnfreeze,
            ),
            _buildMenuItem(
              icon: Icons.refresh,
              label: 'Re-freeze Track',
              onTap: () {
                onUnfreeze();
                Future.delayed(const Duration(milliseconds: 100), onFreeze);
              },
              subtitle: 'Update frozen audio',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(
            state == FreezeState.frozen ? Icons.ac_unit : Icons.ac_unit_outlined,
            size: 16,
            color: state == FreezeState.frozen
                ? const Color(0xFF40c8ff)
                : const Color(0xFF6a6a70),
          ),
          const SizedBox(width: 8),
          Text(
            'Track ${trackId + 1}',
            style: const TextStyle(
              color: Color(0xFFe0e0e0),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: state == FreezeState.frozen
                  ? const Color(0xFF40c8ff).withValues(alpha: 0.2)
                  : const Color(0xFF3a3a40),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              state == FreezeState.frozen ? 'FROZEN' : 'LIVE',
              style: TextStyle(
                color: state == FreezeState.frozen
                    ? const Color(0xFF40c8ff)
                    : const Color(0xFF8a8a90),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    String? subtitle,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          onTap();
          onClose?.call();
        },
        hoverColor: const Color(0xFF2a2a30),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 16, color: const Color(0xFF8a8a90)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: Color(0xFFe0e0e0),
                        fontSize: 12,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Color(0xFF6a6a70),
                          fontSize: 10,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Freeze cache info widget
class FreezeCacheInfo extends StatelessWidget {
  final double cacheSizeMb;
  final int frozenTrackCount;
  final VoidCallback onClearCache;

  const FreezeCacheInfo({
    super.key,
    required this.cacheSizeMb,
    required this.frozenTrackCount,
    required this.onClearCache,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFF3a3a40),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(
                Icons.ac_unit,
                size: 16,
                color: Color(0xFF40c8ff),
              ),
              const SizedBox(width: 8),
              const Text(
                'Freeze Cache',
                style: TextStyle(
                  color: Color(0xFFe0e0e0),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 16),
                color: const Color(0xFF6a6a70),
                onPressed: onClearCache,
                tooltip: 'Clear freeze cache',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildStat('Frozen Tracks', frozenTrackCount.toString()),
              const SizedBox(width: 24),
              _buildStat('Cache Size', '${cacheSizeMb.toStringAsFixed(1)} MB'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF6a6a70),
            fontSize: 10,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFFe0e0e0),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
