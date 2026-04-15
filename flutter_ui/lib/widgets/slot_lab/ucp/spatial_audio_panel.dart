import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../../providers/slot_lab/spatial_audio_provider.dart';

/// UCP-15: 3D Spatial Audio Panel — VR/AR Slot Audio Authoring
///
/// Top-down casino floor view, per-reel spatial params, room acoustics,
/// HRTF config, and VR export format selection.
class SpatialAudioPanel extends StatefulWidget {
  const SpatialAudioPanel({super.key});

  @override
  State<SpatialAudioPanel> createState() => _SpatialAudioPanelState();
}

class _SpatialAudioPanelState extends State<SpatialAudioPanel> {
  SpatialAudioProvider? _provider;

  @override
  void initState() {
    super.initState();
    try {
      _provider = GetIt.instance<SpatialAudioProvider>();
      _provider?.addListener(_onUpdate);
    } catch (_) {}
  }

  @override
  void dispose() {
    _provider?.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = _provider;
    if (p == null) {
      return const Center(
        child: Text('Spatial Audio not available',
            style: TextStyle(color: Colors.grey)),
      );
    }

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF3A3A5C), width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Left: Room config ────────────────────────────────
          SizedBox(width: 200, child: _buildRoomConfig(p)),
          const SizedBox(width: 8),
          // ─── Center: Top-down scene view ───────────────────────
          Expanded(flex: 3, child: _buildSceneView(p)),
          const SizedBox(width: 8),
          // ─── Right: Spatial params + exports ───────────────────
          SizedBox(width: 200, child: _buildSpatialParams(p)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ROOM CONFIG
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildRoomConfig(SpatialAudioProvider p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.view_in_ar, color: Color(0xFF44CCCC), size: 14),
            SizedBox(width: 6),
            Text('Room Setup',
                style: TextStyle(
                    color: Color(0xFFCCCCCC),
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 6),

        // Dimensions
        _configLabel('Dimensions'),
        _configValue(
            '${p.environment.width.toStringAsFixed(0)}×'
            '${p.environment.depth.toStringAsFixed(0)}×'
            '${p.environment.height.toStringAsFixed(0)}m'),
        const SizedBox(height: 4),

        // RT60
        _configLabel('Reverb Time (RT60)'),
        _buildRt60Bar(p.rt60),
        const SizedBox(height: 6),

        // Materials
        _configLabel('Floor Material'),
        _buildMaterialSelector(p, p.environment.floor, p.setFloorMaterial),
        const SizedBox(height: 4),

        _configLabel('Wall Material'),
        _buildMaterialSelector(p, p.environment.walls, p.setWallMaterial),
        const SizedBox(height: 4),

        // Crowd density
        _configLabel('Crowd Density'),
        _buildSliderRow(p.environment.crowdDensity, (v) => p.setCrowdDensity(v)),
        const SizedBox(height: 8),

        // HRTF
        _configLabel('HRTF Profile'),
        const SizedBox(height: 2),
        for (final h in HrtfProfile.values) _buildHrtfOption(p, h),

        const SizedBox(height: 8),

        // Toggles
        _buildToggle('Head Tracking', p.headTrackingEnabled,
            (v) => p.setHeadTracking(v)),
        _buildToggle('Room Correction', p.roomCorrectionEnabled,
            (v) => p.setRoomCorrection(v)),
        _buildToggle('Haptic Sync', p.hapticSyncEnabled,
            (v) => p.setHapticSync(v)),
      ],
    );
  }

  Widget _buildRt60Bar(double rt60) {
    final normalized = (rt60 / 3.0).clamp(0.0, 1.0);
    final color = rt60 < 0.8
        ? const Color(0xFF44CC44) // Dry
        : rt60 < 1.5
            ? const Color(0xFFCCCC44) // Normal
            : const Color(0xFFCC4444); // Very reverberant

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Container(
                height: 6,
                decoration: BoxDecoration(
                  color: const Color(0xFF0D0D1A),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: normalized,
                  child: Container(
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text('${rt60.toStringAsFixed(2)}s',
                style: TextStyle(
                    color: color, fontSize: 9, fontFamily: 'monospace')),
          ],
        ),
      ],
    );
  }

  Widget _buildMaterialSelector(
      SpatialAudioProvider p, SurfaceMaterial current, void Function(SurfaceMaterial) onSelect) {
    return Wrap(
      spacing: 3,
      runSpacing: 2,
      children: [
        for (final m in SurfaceMaterial.values)
          GestureDetector(
            onTap: () => onSelect(m),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: m == current
                    ? const Color(0xFF44CCCC).withAlpha(30)
                    : const Color(0xFF0D0D1A),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                    color: m == current
                        ? const Color(0xFF44CCCC).withAlpha(80)
                        : const Color(0xFF2A2A4C),
                    width: 0.5),
              ),
              child: Text(m.displayName,
                  style: TextStyle(
                      color: m == current
                          ? const Color(0xFF44CCCC)
                          : const Color(0xFF888888),
                      fontSize: 8)),
            ),
          ),
      ],
    );
  }

  Widget _buildSliderRow(double value, void Function(double) onChange) {
    return Row(
      children: [
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              activeTrackColor: const Color(0xFF44CCCC),
              inactiveTrackColor: const Color(0xFF2A2A4C),
              thumbColor: const Color(0xFF44CCCC),
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(
              value: value,
              onChanged: onChange,
            ),
          ),
        ),
        SizedBox(
          width: 28,
          child: Text('${(value * 100).toStringAsFixed(0)}%',
              style: const TextStyle(
                  color: Color(0xFF888888),
                  fontSize: 8,
                  fontFamily: 'monospace')),
        ),
      ],
    );
  }

  Widget _buildHrtfOption(SpatialAudioProvider p, HrtfProfile h) {
    final active = p.hrtfProfile == h;
    return GestureDetector(
      onTap: () => p.setHrtfProfile(h),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 1),
        child: Row(
          children: [
            Icon(
              active ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 10,
              color: active
                  ? const Color(0xFF44CCCC)
                  : const Color(0xFF555577),
            ),
            const SizedBox(width: 4),
            Text(h.displayName,
                style: TextStyle(
                    color: active
                        ? const Color(0xFFCCCCCC)
                        : const Color(0xFF888888),
                    fontSize: 9)),
          ],
        ),
      ),
    );
  }

  Widget _buildToggle(String label, bool value, void Function(bool) onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(
          children: [
            Icon(
              value ? Icons.check_box : Icons.check_box_outline_blank,
              size: 11,
              color: value
                  ? const Color(0xFF44CCCC)
                  : const Color(0xFF555577),
            ),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    color: value
                        ? const Color(0xFFCCCCCC)
                        : const Color(0xFF888888),
                    fontSize: 9)),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SCENE VIEW — Top-down 2D representation of the 3D casino
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSceneView(SpatialAudioProvider p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.map, color: Color(0xFF888888), size: 14),
            SizedBox(width: 6),
            Text('Casino Floor (Top-Down)',
                style: TextStyle(
                    color: Color(0xFFCCCCCC),
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 4),
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF0D0D1A),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFF2A2A4C), width: 0.5),
            ),
            child: CustomPaint(
              painter: _CasinoFloorPainter(
                environment: p.environment,
                listener: p.listener,
                slotMachines: p.slotMachines,
                ambientSources: p.ambientSources,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SPATIAL PARAMS + EXPORT
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSpatialParams(SpatialAudioProvider p) {
    final reelParams = p.getReelSpatialParams();
    final ambientAtt = p.getAmbientAttenuations();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Per-reel spatial params
        const Text('Per-Reel Spatial',
            style: TextStyle(
                color: Color(0xFFCCCCCC),
                fontSize: 11,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        for (int i = 0; i < reelParams.length; i++)
          _buildReelRow(i, reelParams[i]),

        const SizedBox(height: 8),

        // Ambient sources
        const Text('Ambient Sources',
            style: TextStyle(
                color: Color(0xFF888888),
                fontSize: 9,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        for (final s in p.ambientSources)
          _buildAmbientRow(s, ambientAtt[s.id] ?? 0),

        const SizedBox(height: 8),

        // Export formats
        const Text('VR Export Formats',
            style: TextStyle(
                color: Color(0xFF888888),
                fontSize: 9,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (final f in SpatialExportFormat.values)
                  _buildExportToggle(p, f),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReelRow(int index, Map<String, double> params) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          SizedBox(
            width: 35,
            child: Text('R${index + 1}',
                style: const TextStyle(
                    color: Color(0xFF44CCCC),
                    fontSize: 10,
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'az: ${params['azimuth']?.toStringAsFixed(1)}° '
                  'el: ${params['elevation']?.toStringAsFixed(1)}°',
                  style: const TextStyle(
                      color: Color(0xFF999999),
                      fontSize: 8,
                      fontFamily: 'monospace'),
                ),
                Text(
                  'dist: ${params['distance']?.toStringAsFixed(2)}m '
                  'ITD: ${params['itd_us']?.toStringAsFixed(0)}μs',
                  style: const TextStyle(
                      color: Color(0xFF777777),
                      fontSize: 8,
                      fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAmbientRow(SpatialAudioSource source, double attenuation) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(source.name,
                style: const TextStyle(color: Color(0xFF999999), fontSize: 8)),
          ),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF0D0D1A),
              borderRadius: BorderRadius.circular(2),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: attenuation,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF44CCCC),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text('${(attenuation * 100).toStringAsFixed(0)}%',
              style: const TextStyle(
                  color: Color(0xFF888888),
                  fontSize: 8,
                  fontFamily: 'monospace')),
        ],
      ),
    );
  }

  Widget _buildExportToggle(SpatialAudioProvider p, SpatialExportFormat f) {
    final active = p.selectedExports.contains(f);
    return GestureDetector(
      onTap: () => p.toggleExportFormat(f),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 1),
        child: Row(
          children: [
            Icon(
              active ? Icons.check_box : Icons.check_box_outline_blank,
              size: 11,
              color: active
                  ? const Color(0xFF44CCCC)
                  : const Color(0xFF555577),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(f.displayName,
                  style: TextStyle(
                      color: active
                          ? const Color(0xFFCCCCCC)
                          : const Color(0xFF888888),
                      fontSize: 9)),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _configLabel(String label) {
    return Text(label,
        style: const TextStyle(
            color: Color(0xFF888888),
            fontSize: 9,
            fontWeight: FontWeight.w600));
  }

  Widget _configValue(String value) {
    return Text(value,
        style: const TextStyle(
            color: Color(0xFFCCCCCC),
            fontSize: 9,
            fontFamily: 'monospace'));
  }
}

// =============================================================================
// CASINO FLOOR PAINTER — Top-down 2D view
// =============================================================================

class _CasinoFloorPainter extends CustomPainter {
  final CasinoEnvironment environment;
  final SpatialListener listener;
  final List<SpatialSlotMachine> slotMachines;
  final List<SpatialAudioSource> ambientSources;

  _CasinoFloorPainter({
    required this.environment,
    required this.listener,
    required this.slotMachines,
    required this.ambientSources,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / environment.width;
    final scaleZ = size.height / environment.depth;
    final scale = math.min(scaleX, scaleZ) * 0.8;
    final offsetX = size.width / 2;
    final offsetZ = size.height / 2;

    Offset toScreen(double x, double z) {
      return Offset(offsetX + x * scale, offsetZ + z * scale);
    }

    // Room boundary
    final roomPaint = Paint()
      ..color = const Color(0xFF2A2A4C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final halfW = environment.width / 2;
    final halfD = environment.depth / 2;
    canvas.drawRect(
      Rect.fromPoints(
        toScreen(-halfW, -halfD),
        toScreen(halfW, halfD),
      ),
      roomPaint,
    );

    // Grid
    final gridPaint = Paint()
      ..color = const Color(0xFF1A1A3A)
      ..strokeWidth = 0.5;
    for (double x = -halfW; x <= halfW; x += 2) {
      canvas.drawLine(toScreen(x, -halfD), toScreen(x, halfD), gridPaint);
    }
    for (double z = -halfD; z <= halfD; z += 2) {
      canvas.drawLine(toScreen(-halfW, z), toScreen(halfW, z), gridPaint);
    }

    // Ambient sources (circles with distance rings)
    for (final src in ambientSources) {
      final pos = toScreen(src.position.x, src.position.z);
      final rangePaint = Paint()
        ..color = const Color(0xFF44CCCC).withAlpha(20)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pos, src.maxDistance * scale, rangePaint);

      final refPaint = Paint()
        ..color = const Color(0xFF44CCCC).withAlpha(40)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5;
      canvas.drawCircle(pos, src.refDistance * scale, refPaint);

      // Source dot
      final dotPaint = Paint()
        ..color = const Color(0xFF44CCCC).withAlpha(100)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pos, 3, dotPaint);
    }

    // Slot machines
    for (final machine in slotMachines) {
      final pos = toScreen(machine.position.x, machine.position.z);
      final isPlayer = machine.id == 'player_machine';

      // Machine body
      final machinePaint = Paint()
        ..color = isPlayer
            ? const Color(0xFFFFCC00).withAlpha(60)
            : const Color(0xFF888888).withAlpha(40)
        ..style = PaintingStyle.fill;
      final w = machine.cabinetWidth * scale;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: pos, width: w, height: w * 0.4),
          const Radius.circular(2),
        ),
        machinePaint,
      );

      // Machine border
      final borderPaint = Paint()
        ..color = isPlayer
            ? const Color(0xFFFFCC00)
            : const Color(0xFF888888)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isPlayer ? 1.0 : 0.5;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: pos, width: w, height: w * 0.4),
          const Radius.circular(2),
        ),
        borderPaint,
      );

      // Reel dots
      for (int i = 0; i < machine.reelCount; i++) {
        final reelPos = machine.reelPosition(i);
        final rPos = toScreen(reelPos.x, reelPos.z);
        final reelPaint = Paint()
          ..color = isPlayer
              ? const Color(0xFFFFCC00)
              : const Color(0xFF888888)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(rPos, 2, reelPaint);
      }
    }

    // Listener (player) — triangle pointing forward
    final listenerPos = toScreen(listener.position.x, listener.position.z);
    final headRad = listener.headYaw * math.pi / 180;
    final triSize = 8.0;

    final path = Path();
    path.moveTo(
      listenerPos.dx + triSize * math.sin(headRad),
      listenerPos.dy - triSize * math.cos(headRad),
    );
    path.lineTo(
      listenerPos.dx - triSize * 0.6 * math.sin(headRad + 2.3),
      listenerPos.dy + triSize * 0.6 * math.cos(headRad + 2.3),
    );
    path.lineTo(
      listenerPos.dx - triSize * 0.6 * math.sin(headRad - 2.3),
      listenerPos.dy + triSize * 0.6 * math.cos(headRad - 2.3),
    );
    path.close();

    final listenerPaint = Paint()
      ..color = const Color(0xFF44FF44)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, listenerPaint);

    // Listener hearing cone
    final conePaint = Paint()
      ..color = const Color(0xFF44FF44).withAlpha(15)
      ..style = PaintingStyle.fill;
    final coneRadius = 5.0 * scale;
    canvas.drawArc(
      Rect.fromCircle(center: listenerPos, radius: coneRadius),
      headRad - math.pi / 2 - math.pi / 4,
      math.pi / 2,
      true,
      conePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CasinoFloorPainter old) => true;
}
