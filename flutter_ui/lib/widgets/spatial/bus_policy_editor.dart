/// Bus Policy Editor — Configure per-bus spatial modifiers
///
/// Features:
/// - 6 bus types: UI, reels, sfx, vo, music, ambience
/// - Per-bus modifiers: width, pan, tau, reverb, doppler, HRTF
/// - Reset to defaults

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auto_spatial_provider.dart';
import '../../spatial/auto_spatial.dart';
import 'spatial_widgets.dart';

/// Bus Policy Editor widget
class BusPolicyEditor extends StatelessWidget {
  const BusPolicyEditor({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AutoSpatialProvider>(
      builder: (context, provider, _) {
        return Row(
          children: [
            // Left: Bus list
            SizedBox(
              width: 160,
              child: _buildBusList(provider),
            ),

            const VerticalDivider(width: 1, color: Color(0xFF3a3a4a)),

            // Right: Policy editor
            Expanded(
              child: provider.selectedBus != null
                  ? _buildPolicyEditor(context, provider)
                  : const Center(
                      child: Text(
                        'Select a bus to edit',
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBusList(AutoSpatialProvider provider) {
    return Column(
      children: [
        // Header
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              const Text(
                'Audio Buses',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: provider.resetAllBusPoliciesToDefaults,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 24),
                ),
                child: const Text(
                  'Reset All',
                  style: TextStyle(fontSize: 10, color: Colors.white54),
                ),
              ),
            ],
          ),
        ),

        const Divider(height: 1, color: Color(0xFF3a3a4a)),

        // Bus list
        Expanded(
          child: ListView.builder(
            itemCount: SpatialBus.values.length,
            itemBuilder: (context, index) {
              final bus = SpatialBus.values[index];
              final isSelected = provider.selectedBus == bus;
              final policy = provider.allPolicies[bus]!;

              return _BusListTile(
                bus: bus,
                policy: policy,
                isSelected: isSelected,
                onTap: () => provider.selectBus(bus),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPolicyEditor(BuildContext context, AutoSpatialProvider provider) {
    final bus = provider.selectedBus!;
    final policy = provider.selectedBusPolicy!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(
                _busIcon(bus),
                color: _busColor(bus),
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                _busDisplayName(bus),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.refresh, size: 14),
                label: const Text('Reset', style: TextStyle(fontSize: 11)),
                style: TextButton.styleFrom(foregroundColor: Colors.white54),
                onPressed: () => provider.resetBusPolicyToDefault(bus),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _busDescription(bus),
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
          const SizedBox(height: 20),

          // Multipliers
          _SectionHeader(title: 'Spatial Multipliers'),
          Row(
            children: [
              Expanded(
                child: SpatialSlider(
                  label: 'Width Mul',
                  value: policy.widthMul,
                  min: 0,
                  max: 2,
                  onChanged: (v) => _updatePolicy(provider, bus, policy, widthMul: v),
                ),
              ),
              Expanded(
                child: SpatialSlider(
                  label: 'Max Pan Mul',
                  value: policy.maxPanMul,
                  min: 0,
                  max: 2,
                  onChanged: (v) => _updatePolicy(provider, bus, policy, maxPanMul: v),
                ),
              ),
              Expanded(
                child: SpatialSlider(
                  label: 'Tau Mul',
                  value: policy.tauMul,
                  min: 0.1,
                  max: 5,
                  onChanged: (v) => _updatePolicy(provider, bus, policy, tauMul: v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Effects
          _SectionHeader(title: 'Effects'),
          Row(
            children: [
              Expanded(
                child: SpatialSlider(
                  label: 'Reverb Mul',
                  value: policy.reverbMul,
                  min: 0,
                  max: 2,
                  onChanged: (v) => _updatePolicy(provider, bus, policy, reverbMul: v),
                ),
              ),
              Expanded(
                child: SpatialSlider(
                  label: 'Doppler Mul',
                  value: policy.dopplerMul,
                  min: 0,
                  max: 2,
                  onChanged: (v) => _updatePolicy(provider, bus, policy, dopplerMul: v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Options
          _SectionHeader(title: 'Options'),
          Row(
            children: [
              SpatialToggle(
                label: 'HRTF Enabled',
                value: policy.enableHRTF,
                onChanged: (v) => _updatePolicy(provider, bus, policy, enableHRTF: v),
              ),
              const SizedBox(width: 32),
              Expanded(
                child: SpatialSlider(
                  label: 'Priority Boost',
                  value: policy.priorityBoost,
                  min: -1,
                  max: 1,
                  onChanged: (v) =>
                      _updatePolicy(provider, bus, policy, priorityBoost: v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Visual preview
          _SectionHeader(title: 'Preview'),
          _PolicyPreview(policy: policy, bus: bus),
        ],
      ),
    );
  }

  void _updatePolicy(
    AutoSpatialProvider provider,
    SpatialBus bus,
    BusPolicy policy, {
    double? widthMul,
    double? maxPanMul,
    double? tauMul,
    double? reverbMul,
    double? dopplerMul,
    bool? enableHRTF,
    double? priorityBoost,
  }) {
    final newPolicy = BusPolicy(
      widthMul: widthMul ?? policy.widthMul,
      maxPanMul: maxPanMul ?? policy.maxPanMul,
      tauMul: tauMul ?? policy.tauMul,
      reverbMul: reverbMul ?? policy.reverbMul,
      dopplerMul: dopplerMul ?? policy.dopplerMul,
      enableHRTF: enableHRTF ?? policy.enableHRTF,
      priorityBoost: priorityBoost ?? policy.priorityBoost,
    );
    provider.updateBusPolicy(bus, newPolicy);
  }

  IconData _busIcon(SpatialBus bus) => switch (bus) {
        SpatialBus.ui => Icons.touch_app,
        SpatialBus.reels => Icons.view_column,
        SpatialBus.sfx => Icons.speaker,
        SpatialBus.vo => Icons.record_voice_over,
        SpatialBus.music => Icons.music_note,
        SpatialBus.ambience => Icons.waves,
      };

  Color _busColor(SpatialBus bus) => switch (bus) {
        SpatialBus.ui => const Color(0xFF4a9eff),
        SpatialBus.reels => const Color(0xFF40ff90),
        SpatialBus.sfx => const Color(0xFFff9040),
        SpatialBus.vo => const Color(0xFFff4060),
        SpatialBus.music => const Color(0xFF40c8ff),
        SpatialBus.ambience => const Color(0xFF9040ff),
      };

  String _busDisplayName(SpatialBus bus) => switch (bus) {
        SpatialBus.ui => 'UI Bus',
        SpatialBus.reels => 'Reels Bus',
        SpatialBus.sfx => 'SFX Bus',
        SpatialBus.vo => 'Voice Bus',
        SpatialBus.music => 'Music Bus',
        SpatialBus.ambience => 'Ambience Bus',
      };

  String _busDescription(SpatialBus bus) => switch (bus) {
        SpatialBus.ui => 'Buttons, menus, UI feedback — wide, fast tracking',
        SpatialBus.reels => 'Reel stops, symbols — narrower, stable positioning',
        SpatialBus.sfx => 'Win sounds, effects — medium tracking, full range',
        SpatialBus.vo => 'Voice, announcements — centered, minimal movement',
        SpatialBus.music => 'Background music — very wide, almost no panning',
        SpatialBus.ambience => 'Ambient loops — full surround, slow movement',
      };
}

/// Bus list tile
class _BusListTile extends StatelessWidget {
  final SpatialBus bus;
  final BusPolicy policy;
  final bool isSelected;
  final VoidCallback onTap;

  const _BusListTile({
    required this.bus,
    required this.policy,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = _busColor(bus);

    return Material(
      color: isSelected ? color.withValues(alpha: 0.15) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: isSelected ? color : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(_busIcon(bus), color: color, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bus.name.toUpperCase(),
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'W:${(policy.widthMul * 100).round()}% P:${(policy.maxPanMul * 100).round()}%',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
              if (policy.enableHRTF)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFF40c8ff).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: const Text(
                    'HRTF',
                    style: TextStyle(
                      color: Color(0xFF40c8ff),
                      fontSize: 7,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _busIcon(SpatialBus bus) => switch (bus) {
        SpatialBus.ui => Icons.touch_app,
        SpatialBus.reels => Icons.view_column,
        SpatialBus.sfx => Icons.speaker,
        SpatialBus.vo => Icons.record_voice_over,
        SpatialBus.music => Icons.music_note,
        SpatialBus.ambience => Icons.waves,
      };

  Color _busColor(SpatialBus bus) => switch (bus) {
        SpatialBus.ui => const Color(0xFF4a9eff),
        SpatialBus.reels => const Color(0xFF40ff90),
        SpatialBus.sfx => const Color(0xFFff9040),
        SpatialBus.vo => const Color(0xFFff4060),
        SpatialBus.music => const Color(0xFF40c8ff),
        SpatialBus.ambience => const Color(0xFF9040ff),
      };
}

/// Section header
class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// Visual preview of policy effects
class _PolicyPreview extends StatelessWidget {
  final BusPolicy policy;
  final SpatialBus bus;

  const _PolicyPreview({required this.policy, required this.bus});

  @override
  Widget build(BuildContext context) {
    final color = _busColor(bus);

    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: const Color(0xFF121216),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF3a3a4a)),
      ),
      child: CustomPaint(
        painter: _PolicyPreviewPainter(
          widthMul: policy.widthMul,
          maxPanMul: policy.maxPanMul,
          color: color,
        ),
        size: Size.infinite,
      ),
    );
  }

  Color _busColor(SpatialBus bus) => switch (bus) {
        SpatialBus.ui => const Color(0xFF4a9eff),
        SpatialBus.reels => const Color(0xFF40ff90),
        SpatialBus.sfx => const Color(0xFFff9040),
        SpatialBus.vo => const Color(0xFFff4060),
        SpatialBus.music => const Color(0xFF40c8ff),
        SpatialBus.ambience => const Color(0xFF9040ff),
      };
}

class _PolicyPreviewPainter extends CustomPainter {
  final double widthMul;
  final double maxPanMul;
  final Color color;

  _PolicyPreviewPainter({
    required this.widthMul,
    required this.maxPanMul,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;

    // Draw stereo field boundaries
    final fieldPaint = Paint()
      ..color = Colors.white12
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawLine(
      Offset(centerX, 0),
      Offset(centerX, size.height),
      fieldPaint,
    );

    // Draw L/R labels
    final labelStyle = TextStyle(
      color: Colors.white24,
      fontSize: 9,
    );
    final leftPainter = TextPainter(
      text: TextSpan(text: 'L', style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    leftPainter.paint(canvas, const Offset(4, 4));

    final rightPainter = TextPainter(
      text: TextSpan(text: 'R', style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    rightPainter.paint(canvas, Offset(size.width - 12, 4));

    // Draw effective pan range
    final panRange = (size.width / 2 - 20) * maxPanMul;
    final panPaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(centerX, centerY),
        width: panRange * 2,
        height: size.height - 20,
      ),
      panPaint,
    );

    // Draw width indicator
    final widthIndicator = widthMul * 40;
    final widthPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(centerX, centerY),
        width: widthIndicator,
        height: widthIndicator,
      ),
      -3.14 / 2,
      3.14,
      false,
      widthPaint,
    );

    // Draw center dot
    canvas.drawCircle(
      Offset(centerX, centerY),
      4,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _PolicyPreviewPainter oldDelegate) {
    return widthMul != oldDelegate.widthMul ||
        maxPanMul != oldDelegate.maxPanMul ||
        color != oldDelegate.color;
  }
}
