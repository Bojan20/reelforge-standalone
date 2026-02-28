import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../providers/device_preview_provider.dart';

/// Device Preview panel — monitoring-only device simulation
/// Shows in Control Room / Monitor section
class DevicePreviewPanel extends StatefulWidget {
  const DevicePreviewPanel({super.key});

  @override
  State<DevicePreviewPanel> createState() => _DevicePreviewPanelState();
}

class _DevicePreviewPanelState extends State<DevicePreviewPanel> {
  late final DevicePreviewProvider _provider;
  DeviceCategory? _selectedCategory;

  @override
  void initState() {
    super.initState();
    _provider = GetIt.instance<DevicePreviewProvider>();
    _provider.init();
    _provider.addListener(_onChanged);
  }

  @override
  void dispose() {
    _provider.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1E),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: _provider.active
              ? const Color(0xFF4FC3F7).withValues(alpha: 0.5)
              : const Color(0xFF333338),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(),
          if (_provider.active) ...[
            const SizedBox(height: 6),
            _buildCategorySelector(),
            const SizedBox(height: 6),
            _buildProfileList(),
            if (_provider.currentFrCurve != null) ...[
              const SizedBox(height: 6),
              _buildFrCurveDisplay(),
            ],
            if (_provider.currentProfile != null) ...[
              const SizedBox(height: 4),
              _buildProfileDetails(),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final profile = _provider.currentProfile;
    return Row(
      children: [
        GestureDetector(
          onTap: _provider.toggleActive,
          child: Container(
            width: 10, height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _provider.active
                  ? const Color(0xFF4FC3F7)
                  : const Color(0xFF555555),
            ),
          ),
        ),
        const SizedBox(width: 6),
        const Text(
          'DEVICE PREVIEW',
          style: TextStyle(
            color: Color(0xFF888888),
            fontSize: 9,
            fontWeight: FontWeight.w700,
            fontFamily: 'JetBrains Mono',
            letterSpacing: 1.2,
          ),
        ),
        const Spacer(),
        if (profile != null) ...[
          Text(
            profile.name,
            style: const TextStyle(
              color: Color(0xFFCCCCCC),
              fontSize: 9,
              fontFamily: 'JetBrains Mono',
            ),
          ),
          const SizedBox(width: 6),
        ],
        if (_provider.active && _provider.currentProfileId != 0)
          GestureDetector(
            onTap: _provider.bypass,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF555555)),
                borderRadius: BorderRadius.circular(3),
              ),
              child: const Text(
                'BYPASS',
                style: TextStyle(
                  color: Color(0xFF888888),
                  fontSize: 7,
                  fontFamily: 'JetBrains Mono',
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCategorySelector() {
    final categories = DeviceCategory.values
        .where((c) => c != DeviceCategory.custom)
        .toList();

    return SizedBox(
      height: 22,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 4),
        itemBuilder: (context, index) {
          final cat = categories[index];
          final isSelected = _selectedCategory == cat;
          final count = _provider.profilesByCategory(cat).length;
          return GestureDetector(
            onTap: () => setState(() => _selectedCategory = isSelected ? null : cat),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF2A3A4A) : const Color(0xFF222226),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: isSelected ? const Color(0xFF4FC3F7) : const Color(0xFF333338),
                ),
              ),
              child: Text(
                '${cat.displayName} ($count)',
                style: TextStyle(
                  color: isSelected ? const Color(0xFF4FC3F7) : const Color(0xFF888888),
                  fontSize: 8,
                  fontFamily: 'JetBrains Mono',
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildProfileList() {
    final profiles = _selectedCategory != null
        ? _provider.profilesByCategory(_selectedCategory!)
        : _provider.profiles;

    if (profiles.isEmpty) {
      return const SizedBox(
        height: 30,
        child: Center(
          child: Text(
            'Select a category',
            style: TextStyle(color: Color(0xFF555555), fontSize: 9),
          ),
        ),
      );
    }

    return SizedBox(
      height: 80,
      child: ListView.builder(
        itemCount: profiles.length,
        itemBuilder: (context, index) {
          final p = profiles[index];
          final isActive = p.id == _provider.currentProfileId;
          return GestureDetector(
            onTap: () => _provider.loadProfile(p.id),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              margin: const EdgeInsets.only(bottom: 1),
              decoration: BoxDecoration(
                color: isActive ? const Color(0xFF1E2E3E) : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
              child: Row(
                children: [
                  if (isActive)
                    const Icon(Icons.speaker, size: 10, color: Color(0xFF4FC3F7))
                  else
                    const SizedBox(width: 10),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      p.name,
                      style: TextStyle(
                        color: isActive ? const Color(0xFF4FC3F7) : const Color(0xFFAAAAAA),
                        fontSize: 9,
                        fontFamily: 'JetBrains Mono',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    p.stereoMode == 'mono' ? 'M' : p.stereoMode == 'stereo' ? 'S' : 'N',
                    style: const TextStyle(
                      color: Color(0xFF666666),
                      fontSize: 7,
                      fontFamily: 'JetBrains Mono',
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFrCurveDisplay() {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: const Color(0xFF111114),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: const Color(0xFF2A2A2E)),
      ),
      child: CustomPaint(
        painter: _FrCurvePainter(
          frCurve: _provider.currentFrCurve!,
          color: const Color(0xFF4FC3F7),
        ),
      ),
    );
  }

  Widget _buildProfileDetails() {
    final p = _provider.currentProfile!;
    return Wrap(
      spacing: 8,
      children: [
        _detailChip('HPF', '${p.hpfFreq.toInt()} Hz'),
        _detailChip('DRC', '${(p.drcAmount * 100).toInt()}%'),
        _detailChip('DIST', p.distortion == 'none' ? 'OFF' : p.distortion.toUpperCase()),
        _detailChip('NOISE', '${p.envNoiseFloor.toInt()} dB'),
      ],
    );
  }

  Widget _detailChip(String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: const TextStyle(
            color: Color(0xFF555555),
            fontSize: 7,
            fontFamily: 'JetBrains Mono',
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFF999999),
            fontSize: 7,
            fontFamily: 'JetBrains Mono',
          ),
        ),
      ],
    );
  }
}

/// FR curve painter
class _FrCurvePainter extends CustomPainter {
  final List<List<double>> frCurve;
  final Color color;

  _FrCurvePainter({required this.frCurve, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (frCurve.isEmpty || size.width <= 0 || size.height <= 0) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..isAntiAlias = true;

    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;

    final gridPaint = Paint()
      ..color = const Color(0xFF222228)
      ..strokeWidth = 0.5;

    // Grid lines
    for (int db = -30; db <= 10; db += 10) {
      final y = _dbToY(db.toDouble(), size);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    // 0dB line
    final zeroY = _dbToY(0, size);
    canvas.drawLine(
      Offset(0, zeroY), Offset(size.width, zeroY),
      Paint()..color = const Color(0xFF333338)..strokeWidth = 0.5,
    );

    // FR curve
    final path = Path();
    final fillPath = Path();
    for (int i = 0; i < frCurve.length; i++) {
      final freq = frCurve[i][0];
      final gain = frCurve[i][1];
      final x = _freqToX(freq, size);
      final y = _dbToY(gain, size);
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }
    fillPath.lineTo(_freqToX(frCurve.last[0], size), size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);
  }

  double _freqToX(double freq, Size size) {
    final logMin = math.log(20) / math.ln10;
    final logMax = math.log(20000) / math.ln10;
    final logFreq = math.log(freq.clamp(20, 20000)) / math.ln10;
    return ((logFreq - logMin) / (logMax - logMin)) * size.width;
  }

  double _dbToY(double db, Size size) {
    // Range: -40dB to +10dB
    return ((10 - db) / 50) * size.height;
  }

  @override
  bool shouldRepaint(_FrCurvePainter oldDelegate) =>
      oldDelegate.frCurve != frCurve;
}
