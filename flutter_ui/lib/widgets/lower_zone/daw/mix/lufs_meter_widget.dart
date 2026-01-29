/// LUFS Meter Widget (P0.2) — Real-time loudness metering
///
/// Displays integrated, short-term, and momentary LUFS values
/// with color-coded zones for streaming/broadcast compliance.
///
/// Created: 2026-01-29
library;

import 'dart:async';
import 'package:flutter/material.dart';
import '../../lower_zone_types.dart';
import '../../../../src/rust/native_ffi.dart';

/// Loudness target presets
enum LufsTarget {
  streaming(-14.0, 'Streaming'),
  broadcast(-23.0, 'Broadcast'),
  apple(-16.0, 'Apple Music'),
  youtube(-14.0, 'YouTube'),
  spotify(-14.0, 'Spotify'),
  club(-8.0, 'Club'),
  custom(0.0, 'Custom');

  final double lufs;
  final String label;
  const LufsTarget(this.lufs, this.label);
}

/// LUFS meter data
class LufsData {
  final double momentary;    // LUFS-M (400ms window)
  final double shortTerm;    // LUFS-S (3s window)
  final double integrated;   // LUFS-I (full program)

  const LufsData({
    required this.momentary,
    required this.shortTerm,
    required this.integrated,
  });

  static const empty = LufsData(
    momentary: -70.0,
    shortTerm: -70.0,
    integrated: -70.0,
  );
}

/// Compact LUFS meter for channel strip
class LufsMeterWidget extends StatefulWidget {
  final double width;
  final double height;
  final LufsTarget target;
  final bool showLabels;

  const LufsMeterWidget({
    super.key,
    this.width = 100,
    this.height = 60,
    this.target = LufsTarget.streaming,
    this.showLabels = true,
  });

  @override
  State<LufsMeterWidget> createState() => _LufsMeterWidgetState();
}

class _LufsMeterWidgetState extends State<LufsMeterWidget> {
  Timer? _timer;
  LufsData _data = LufsData.empty;

  @override
  void initState() {
    super.initState();
    // Update at 5fps (200ms) — sufficient for LUFS
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      _updateMeters();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _updateMeters() {
    final ffi = NativeFFI.instance;
    final (momentary, shortTerm, integrated) = ffi.getLufsMeters();
    if (mounted) {
      setState(() {
        _data = LufsData(
          momentary: momentary,
          shortTerm: shortTerm,
          integrated: integrated,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.width,
      height: widget.height,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeep,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LowerZoneColors.borderSubtle),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showLabels)
            Text(
              'LUFS',
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.bold,
                color: LowerZoneColors.textMuted,
              ),
            ),
          const SizedBox(height: 2),
          Expanded(
            child: Row(
              children: [
                // LUFS bars
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildLufsBar('I', _data.integrated),
                      const SizedBox(height: 2),
                      _buildLufsBar('S', _data.shortTerm),
                      const SizedBox(height: 2),
                      _buildLufsBar('M', _data.momentary),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                // Big integrated value
                _buildIntegratedBadge(_data.integrated),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLufsBar(String label, double value) {
    // Range: -60 to 0 LUFS
    final normalized = ((value + 60) / 60).clamp(0.0, 1.0);
    final color = _getLufsColor(value);

    return Row(
      children: [
        SizedBox(
          width: 10,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 7,
              fontWeight: FontWeight.bold,
              color: LowerZoneColors.textMuted,
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 8,
            decoration: BoxDecoration(
              color: LowerZoneColors.bgMid,
              borderRadius: BorderRadius.circular(2),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: normalized,
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIntegratedBadge(double value) {
    final color = _getLufsColor(value);
    final displayValue = value > -70 ? value.toStringAsFixed(1) : '--';

    return Container(
      width: 32,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color, width: 1),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            displayValue,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          if (widget.showLabels)
            Text(
              'LUFS',
              style: TextStyle(
                fontSize: 6,
                color: LowerZoneColors.textMuted,
              ),
            ),
        ],
      ),
    );
  }

  Color _getLufsColor(double value) {
    final target = widget.target.lufs;

    if (value > -70) {
      final diff = value - target;
      if (diff > 3) {
        // Too loud (>3dB over target) — red
        return LowerZoneColors.error;
      } else if (diff > 1) {
        // Slightly loud (1-3dB over target) — orange
        return LowerZoneColors.warning;
      } else if (diff > -3) {
        // On target (±1dB) — green
        return LowerZoneColors.success;
      } else if (diff > -6) {
        // Slightly quiet (3-6dB under target) — cyan
        return LowerZoneColors.dawAccent;
      } else {
        // Too quiet (>6dB under target) — muted
        return LowerZoneColors.textSecondary;
      }
    }
    return LowerZoneColors.textMuted;
  }
}

/// Large LUFS meter for dedicated metering panel
class LufsMeterLargeWidget extends StatefulWidget {
  final LufsTarget target;
  final ValueChanged<LufsTarget>? onTargetChanged;

  const LufsMeterLargeWidget({
    super.key,
    this.target = LufsTarget.streaming,
    this.onTargetChanged,
  });

  @override
  State<LufsMeterLargeWidget> createState() => _LufsMeterLargeWidgetState();
}

class _LufsMeterLargeWidgetState extends State<LufsMeterLargeWidget> {
  Timer? _timer;
  LufsData _data = LufsData.empty;
  double _truePeakL = -70.0;
  double _truePeakR = -70.0;
  double _maxTruePeak = -70.0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      _updateMeters();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _updateMeters() {
    final ffi = NativeFFI.instance;
    final (momentary, shortTerm, integrated) = ffi.getLufsMeters();
    final (tpL, tpR) = ffi.getTruePeakMeters();

    if (mounted) {
      setState(() {
        _data = LufsData(
          momentary: momentary,
          shortTerm: shortTerm,
          integrated: integrated,
        );
        _truePeakL = tpL;
        _truePeakR = tpR;
        _maxTruePeak = tpL > tpR ? tpL : tpR;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeep,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with target selector
          Row(
            children: [
              const Icon(Icons.graphic_eq, size: 16, color: LowerZoneColors.textSecondary),
              const SizedBox(width: 8),
              Text(
                'LOUDNESS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: LowerZoneColors.textSecondary,
                ),
              ),
              const Spacer(),
              _buildTargetSelector(),
            ],
          ),
          const SizedBox(height: 12),

          // Big integrated value
          Center(
            child: _buildBigIntegrated(),
          ),
          const SizedBox(height: 12),

          // LUFS bars
          _buildMeterRow('Integrated', _data.integrated, 'LUFS-I'),
          const SizedBox(height: 6),
          _buildMeterRow('Short-term', _data.shortTerm, 'LUFS-S'),
          const SizedBox(height: 6),
          _buildMeterRow('Momentary', _data.momentary, 'LUFS-M'),
          const SizedBox(height: 12),

          // True Peak
          _buildTruePeakRow(),
        ],
      ),
    );
  }

  Widget _buildTargetSelector() {
    return PopupMenuButton<LufsTarget>(
      initialValue: widget.target,
      onSelected: widget.onTargetChanged,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: LowerZoneColors.bgMid,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: LowerZoneColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${widget.target.label} (${widget.target.lufs.toStringAsFixed(0)})',
              style: TextStyle(
                fontSize: 10,
                color: LowerZoneColors.textSecondary,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down, size: 14, color: LowerZoneColors.textSecondary),
          ],
        ),
      ),
      itemBuilder: (_) => LufsTarget.values
          .where((t) => t != LufsTarget.custom)
          .map((t) => PopupMenuItem(
                value: t,
                child: Text('${t.label} (${t.lufs.toStringAsFixed(0)} LUFS)'),
              ))
          .toList(),
    );
  }

  Widget _buildBigIntegrated() {
    final value = _data.integrated;
    final target = widget.target.lufs;
    final diff = value - target;
    final color = _getLufsColor(value);
    final displayValue = value > -70 ? value.toStringAsFixed(1) : '--';

    return Column(
      children: [
        Text(
          displayValue,
          style: TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.bold,
            color: color,
            fontFamily: 'monospace',
          ),
        ),
        Text(
          'LUFS',
          style: TextStyle(
            fontSize: 12,
            color: LowerZoneColors.textMuted,
          ),
        ),
        if (value > -70)
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              diff >= 0 ? '+${diff.toStringAsFixed(1)}' : diff.toStringAsFixed(1),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMeterRow(String label, double value, String suffix) {
    final normalized = ((value + 60) / 60).clamp(0.0, 1.0);
    final targetNormalized = ((widget.target.lufs + 60) / 60).clamp(0.0, 1.0);
    final color = _getLufsColor(value);
    final displayValue = value > -70 ? value.toStringAsFixed(1) : '--';

    return Row(
      children: [
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: LowerZoneColors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              // Background
              Container(
                height: 12,
                decoration: BoxDecoration(
                  color: LowerZoneColors.bgMid,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              // Value bar
              FractionallySizedBox(
                widthFactor: normalized,
                child: Container(
                  height: 12,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              // Target indicator
              Positioned(
                left: targetNormalized * 200 - 1, // Approximate width
                child: Container(
                  width: 2,
                  height: 12,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 45,
          child: Text(
            displayValue,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTruePeakRow() {
    final isTooHot = _maxTruePeak > -1.0;
    final color = isTooHot ? LowerZoneColors.error : LowerZoneColors.success;
    final displayL = _truePeakL > -70 ? _truePeakL.toStringAsFixed(1) : '--';
    final displayR = _truePeakR > -70 ? _truePeakR.toStringAsFixed(1) : '--';

    return Row(
      children: [
        Text(
          'True Peak',
          style: TextStyle(
            fontSize: 10,
            color: LowerZoneColors.textSecondary,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: color),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'L: $displayL',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: color,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'R: $displayR',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: color,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'dBTP',
                style: TextStyle(
                  fontSize: 8,
                  color: LowerZoneColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Color _getLufsColor(double value) {
    final target = widget.target.lufs;

    if (value > -70) {
      final diff = value - target;
      if (diff > 3) {
        return LowerZoneColors.error;
      } else if (diff > 1) {
        return LowerZoneColors.warning;
      } else if (diff > -3) {
        return LowerZoneColors.success;
      } else if (diff > -6) {
        return LowerZoneColors.dawAccent;
      } else {
        return LowerZoneColors.textSecondary;
      }
    }
    return LowerZoneColors.textMuted;
  }
}

/// Compact LUFS badge for status bars
class LufsBadge extends StatefulWidget {
  final LufsTarget target;

  const LufsBadge({
    super.key,
    this.target = LufsTarget.streaming,
  });

  @override
  State<LufsBadge> createState() => _LufsBadgeState();
}

class _LufsBadgeState extends State<LufsBadge> {
  Timer? _timer;
  double _integrated = -70.0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final (_, _, integrated) = NativeFFI.instance.getLufsMeters();
      if (mounted) {
        setState(() => _integrated = integrated);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.target.lufs;
    final diff = _integrated - target;
    Color color;

    if (_integrated > -70) {
      if (diff.abs() <= 1) {
        color = LowerZoneColors.success;
      } else if (diff > 1) {
        color = LowerZoneColors.warning;
      } else {
        color = LowerZoneColors.textSecondary;
      }
    } else {
      color = LowerZoneColors.textMuted;
    }

    final displayValue = _integrated > -70 ? _integrated.toStringAsFixed(1) : '--';

    return Tooltip(
      message: 'Integrated LUFS (target: ${target.toStringAsFixed(0)})',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: color),
        ),
        child: Text(
          '$displayValue LUFS',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: color,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}
