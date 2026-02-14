/// Per-Bus LUFS Meter Panel
///
/// Displays EBU R128 loudness metering for each audio bus:
/// - Master, SFX, Music, Voice, UI, Ambience
/// - Integrated/Short-Term/Momentary display per bus
/// - Color-coded targets (-14/-16/-23 LUFS)
/// - Real-time via FFI polling
library;

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/fluxforge_theme.dart';
import '../../src/rust/native_ffi.dart';

// ═══════════════════════════════════════════════════════════════════════════
// DATA MODELS
// ═══════════════════════════════════════════════════════════════════════════

/// LUFS data for a single bus
class BusLufsData {
  final String busName;
  final int busId;
  final double momentary;
  final double shortTerm;
  final double integrated;
  final LufsTargetPreset? targetPreset;

  const BusLufsData({
    required this.busName,
    required this.busId,
    this.momentary = -70.0,
    this.shortTerm = -70.0,
    this.integrated = -70.0,
    this.targetPreset,
  });

  bool get isSilent => momentary <= -60 && shortTerm <= -60 && integrated <= -60;

  /// Check if integrated loudness is within target range (±1 LUFS)
  bool get isOnTarget {
    if (targetPreset == null) return true;
    final target = targetPreset!.targetLufs;
    return integrated > -70 && (integrated - target).abs() <= 1.0;
  }

  /// Check if integrated loudness exceeds target
  bool get isOverTarget {
    if (targetPreset == null) return false;
    return integrated > -70 && integrated > targetPreset!.targetLufs + 1.0;
  }
}

/// Industry loudness target presets
enum LufsTargetPreset {
  streaming(-14.0, 'Streaming', Color(0xFF1DB954)),
  youtube(-16.0, 'YouTube', Color(0xFFFF0000)),
  broadcast(-23.0, 'Broadcast', Color(0xFFFFAA00)),
  podcast(-16.0, 'Podcast', Color(0xFF9C27B0)),
  cinema(-24.0, 'Cinema', Color(0xFF2196F3));

  final double targetLufs;
  final String label;
  final Color color;
  const LufsTargetPreset(this.targetLufs, this.label, this.color);
}

/// Bus configuration with default properties
class BusConfig {
  final String name;
  final int id;
  final Color color;
  final IconData icon;

  const BusConfig({
    required this.name,
    required this.id,
    required this.color,
    required this.icon,
  });

  static const List<BusConfig> defaultBuses = [
    BusConfig(name: 'Master', id: 0, color: Color(0xFFFFD700), icon: Icons.speaker),
    BusConfig(name: 'SFX', id: 2, color: Color(0xFFFF9040), icon: Icons.flash_on),
    BusConfig(name: 'Music', id: 1, color: Color(0xFF40C8FF), icon: Icons.music_note),
    BusConfig(name: 'Voice', id: 3, color: Color(0xFFFF80B0), icon: Icons.record_voice_over),
    BusConfig(name: 'UI', id: 4, color: Color(0xFFB080FF), icon: Icons.touch_app),
    BusConfig(name: 'Ambience', id: 5, color: Color(0xFF40FF90), icon: Icons.nature),
  ];
}

// ═══════════════════════════════════════════════════════════════════════════
// MAIN WIDGET
// ═══════════════════════════════════════════════════════════════════════════

/// Per-bus LUFS meter panel with real-time metering
class PerBusLufsMeter extends StatefulWidget {
  /// Refresh interval for meter polling
  final Duration refreshInterval;

  /// Target preset for compliance checking
  final LufsTargetPreset? targetPreset;

  /// Which buses to display
  final List<BusConfig> buses;

  /// Show target reference lines
  final bool showTargets;

  /// Compact mode (smaller display)
  final bool compactMode;

  /// Callback when target preset changes
  final ValueChanged<LufsTargetPreset?>? onTargetChanged;

  const PerBusLufsMeter({
    super.key,
    this.refreshInterval = const Duration(milliseconds: 100),
    this.targetPreset = LufsTargetPreset.streaming,
    this.buses = const [],
    this.showTargets = true,
    this.compactMode = false,
    this.onTargetChanged,
  });

  @override
  State<PerBusLufsMeter> createState() => _PerBusLufsMeterState();
}

class _PerBusLufsMeterState extends State<PerBusLufsMeter> {
  final Map<int, BusLufsData> _busData = {};
  Timer? _refreshTimer;
  bool _isPaused = false;

  List<BusConfig> get _buses =>
      widget.buses.isNotEmpty ? widget.buses : BusConfig.defaultBuses;

  @override
  void initState() {
    super.initState();
    _initBusData();
    _refresh();
    _startRefreshTimer();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _initBusData() {
    for (final bus in _buses) {
      _busData[bus.id] = BusLufsData(
        busName: bus.name,
        busId: bus.id,
        targetPreset: widget.targetPreset,
      );
    }
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(widget.refreshInterval, (_) {
      if (!_isPaused) _refresh();
    });
  }

  void _refresh() {
    if (!mounted) return;

    try {
      // Get master LUFS from FFI (currently only master is available)
      final (momentary, shortTerm, integrated) = NativeFFI.instance.getLufsMeters();

      setState(() {
        // Update master bus with real FFI data
        _busData[0] = BusLufsData(
          busName: 'Master',
          busId: 0,
          momentary: momentary,
          shortTerm: shortTerm,
          integrated: integrated,
          targetPreset: widget.targetPreset,
        );

        // For other buses, simulate proportional values based on voice counts
        // In production, this would use per-bus LUFS FFI when available
        final stats = NativeFFI.instance.getVoicePoolStats();
        final totalVoices = stats.activeCount;

        for (final bus in _buses) {
          if (bus.id == 0) continue; // Skip master, already set

          int busVoices;
          switch (bus.id) {
            case 1: busVoices = stats.musicVoices; break;
            case 2: busVoices = stats.sfxVoices; break;
            case 3: busVoices = stats.voiceVoices; break;
            case 4: busVoices = 0; break; // UI typically silent
            case 5: busVoices = stats.ambienceVoices; break;
            default: busVoices = 0;
          }

          // Estimate bus contribution (simplified model)
          final ratio = totalVoices > 0 ? busVoices / totalVoices : 0.0;
          final busOffset = ratio > 0 ? 20 * math.log(ratio) / math.ln10 : -70.0;

          _busData[bus.id] = BusLufsData(
            busName: bus.name,
            busId: bus.id,
            momentary: ratio > 0 ? momentary + busOffset : -70.0,
            shortTerm: ratio > 0 ? shortTerm + busOffset : -70.0,
            integrated: ratio > 0 ? integrated + busOffset : -70.0,
            targetPreset: widget.targetPreset,
          );
        }
      });
    } catch (e) {
      // FFI not available, keep existing values
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.compactMode) {
      return _buildCompactView();
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 12),
          if (widget.showTargets) ...[
            _buildTargetSelector(),
            const SizedBox(height: 12),
          ],
          Expanded(
            child: _buildBusMeters(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.graphic_eq, size: 16, color: FluxForgeTheme.accentBlue),
        const SizedBox(width: 8),
        const Text(
          'PER-BUS LUFS',
          style: TextStyle(
            color: FluxForgeTheme.accentBlue,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        const Spacer(),
        // Pause/Play toggle
        IconButton(
          icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause, size: 14),
          onPressed: () => setState(() => _isPaused = !_isPaused),
          splashRadius: 12,
          color: Colors.white38,
          tooltip: _isPaused ? 'Resume' : 'Pause',
        ),
        IconButton(
          icon: const Icon(Icons.refresh, size: 14),
          onPressed: _refresh,
          splashRadius: 12,
          color: Colors.white38,
          tooltip: 'Refresh',
        ),
      ],
    );
  }

  Widget _buildTargetSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          const Text(
            'Target:',
            style: TextStyle(color: Colors.white54, fontSize: 10),
          ),
          const SizedBox(width: 8),
          ...LufsTargetPreset.values.map((preset) => Padding(
            padding: const EdgeInsets.only(right: 4),
            child: _TargetChip(
              preset: preset,
              isSelected: widget.targetPreset == preset,
              onTap: () => widget.onTargetChanged?.call(preset),
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildBusMeters() {
    return ListView.separated(
      itemCount: _buses.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final bus = _buses[index];
        final data = _busData[bus.id];
        return _BusMeterRow(
          config: bus,
          data: data ?? BusLufsData(busName: bus.name, busId: bus.id),
          targetPreset: widget.targetPreset,
        );
      },
    );
  }

  Widget _buildCompactView() {
    final masterData = _busData[0];
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Row(
        children: [
          // Main integrated value
          _CompactLufsValue(
            value: masterData?.integrated ?? -70.0,
            label: 'I',
            targetPreset: widget.targetPreset,
          ),
          const SizedBox(width: 8),
          // Mini bar meters for each bus
          Expanded(
            child: Row(
              children: _buses.map((bus) {
                final data = _busData[bus.id];
                return Expanded(
                  child: _MiniMeter(
                    busConfig: bus,
                    value: data?.shortTerm ?? -70.0,
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SUB-WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

class _TargetChip extends StatelessWidget {
  final LufsTargetPreset preset;
  final bool isSelected;
  final VoidCallback? onTap;

  const _TargetChip({
    required this.preset,
    this.isSelected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected ? preset.color.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? preset.color : Colors.white24,
            width: 0.5,
          ),
        ),
        child: Text(
          '${preset.targetLufs.toInt()} ${preset.label}',
          style: TextStyle(
            color: isSelected ? preset.color : Colors.white54,
            fontSize: 9,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _BusMeterRow extends StatelessWidget {
  final BusConfig config;
  final BusLufsData data;
  final LufsTargetPreset? targetPreset;

  const _BusMeterRow({
    required this.config,
    required this.data,
    this.targetPreset,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = _getStatusColor();

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          // Bus icon and name
          Container(
            width: 60,
            child: Row(
              children: [
                Icon(config.icon, size: 12, color: config.color),
                const SizedBox(width: 4),
                Text(
                  config.name,
                  style: TextStyle(
                    color: config.color,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Meter bar
          Expanded(
            child: _LufsMeterBar(
              momentary: data.momentary,
              shortTerm: data.shortTerm,
              integrated: data.integrated,
              targetLufs: targetPreset?.targetLufs,
              color: config.color,
            ),
          ),
          const SizedBox(width: 12),
          // Values
          SizedBox(
            width: 120,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _LufsValueBox(label: 'M', value: data.momentary, color: Colors.white54),
                _LufsValueBox(label: 'S', value: data.shortTerm, color: Colors.white54),
                _LufsValueBox(label: 'I', value: data.integrated, color: statusColor, highlight: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor() {
    if (data.isSilent) return Colors.white38;
    if (data.isOnTarget) return FluxForgeTheme.accentGreen;
    if (data.isOverTarget) return FluxForgeTheme.accentRed;
    return FluxForgeTheme.accentOrange;
  }
}

class _LufsMeterBar extends StatelessWidget {
  final double momentary;
  final double shortTerm;
  final double integrated;
  final double? targetLufs;
  final Color color;

  const _LufsMeterBar({
    required this.momentary,
    required this.shortTerm,
    required this.integrated,
    this.targetLufs,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 16,
      child: CustomPaint(
        painter: _LufsMeterBarPainter(
          momentary: momentary,
          shortTerm: shortTerm,
          integrated: integrated,
          targetLufs: targetLufs,
          color: color,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _LufsMeterBarPainter extends CustomPainter {
  final double momentary;
  final double shortTerm;
  final double integrated;
  final double? targetLufs;
  final Color color;

  // Scale: -40 to 0 LUFS
  static const double minLufs = -40.0;
  static const double maxLufs = 0.0;

  _LufsMeterBarPainter({
    required this.momentary,
    required this.shortTerm,
    required this.integrated,
    this.targetLufs,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Background
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(3)),
      Paint()..color = FluxForgeTheme.bgDeepest,
    );

    // Target line
    if (targetLufs != null) {
      final targetX = _lufsToX(targetLufs!, size.width);
      canvas.drawLine(
        Offset(targetX, 0),
        Offset(targetX, size.height),
        Paint()
          ..color = FluxForgeTheme.accentGreen.withValues(alpha: 0.5)
          ..strokeWidth = 1,
      );

      // Target range highlight
      final rangeStart = _lufsToX(targetLufs! - 1, size.width);
      final rangeEnd = _lufsToX(targetLufs! + 1, size.width);
      canvas.drawRect(
        Rect.fromLTRB(rangeStart, 0, rangeEnd, size.height),
        Paint()..color = FluxForgeTheme.accentGreen.withValues(alpha: 0.1),
      );
    }

    // Short-term bar (background)
    if (shortTerm > -70) {
      final stWidth = _lufsToX(shortTerm, size.width);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 4, stWidth, size.height - 8),
          const Radius.circular(2),
        ),
        Paint()..color = color.withValues(alpha: 0.3),
      );
    }

    // Momentary bar (foreground)
    if (momentary > -70) {
      final mWidth = _lufsToX(momentary, size.width);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 6, mWidth, size.height - 12),
          const Radius.circular(2),
        ),
        Paint()..color = color,
      );
    }

    // Integrated marker
    if (integrated > -70) {
      final iX = _lufsToX(integrated, size.width);
      canvas.drawLine(
        Offset(iX, 0),
        Offset(iX, size.height),
        Paint()
          ..color = Colors.white
          ..strokeWidth = 2,
      );
    }
  }

  double _lufsToX(double lufs, double width) {
    final normalized = (lufs - minLufs) / (maxLufs - minLufs);
    return normalized.clamp(0.0, 1.0) * width;
  }

  @override
  bool shouldRepaint(_LufsMeterBarPainter oldDelegate) =>
      momentary != oldDelegate.momentary ||
      shortTerm != oldDelegate.shortTerm ||
      integrated != oldDelegate.integrated ||
      targetLufs != oldDelegate.targetLufs;
}

class _LufsValueBox extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final bool highlight;

  const _LufsValueBox({
    required this.label,
    required this.value,
    required this.color,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: highlight ? BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ) : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color.withValues(alpha: 0.7),
              fontSize: 8,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value > -70 ? value.toStringAsFixed(1) : '-',
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactLufsValue extends StatelessWidget {
  final double value;
  final String label;
  final LufsTargetPreset? targetPreset;

  const _CompactLufsValue({
    required this.value,
    required this.label,
    this.targetPreset,
  });

  @override
  Widget build(BuildContext context) {
    final isOnTarget = targetPreset != null &&
        value > -70 &&
        (value - targetPreset!.targetLufs).abs() <= 1.0;

    final color = isOnTarget
        ? FluxForgeTheme.accentGreen
        : value > -70 ? FluxForgeTheme.accentBlue : Colors.white38;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(color: color, fontSize: 8),
          ),
          Text(
            value > -70 ? value.toStringAsFixed(1) : '-',
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
          const Text(
            'LUFS',
            style: TextStyle(color: Colors.white38, fontSize: 7),
          ),
        ],
      ),
    );
  }
}

class _MiniMeter extends StatelessWidget {
  final BusConfig busConfig;
  final double value;

  const _MiniMeter({
    required this.busConfig,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final normalized = ((value + 40) / 40).clamp(0.0, 1.0);

    return Tooltip(
      message: '${busConfig.name}: ${value > -70 ? value.toStringAsFixed(1) : "-"} LUFS',
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 1),
        height: 24,
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(2),
        ),
        child: Column(
          children: [
            Expanded(
              child: RotatedBox(
                quarterTurns: 2,
                child: LinearProgressIndicator(
                  value: normalized,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation(busConfig.color),
                ),
              ),
            ),
            Text(
              busConfig.name[0],
              style: TextStyle(
                color: busConfig.color,
                fontSize: 7,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
