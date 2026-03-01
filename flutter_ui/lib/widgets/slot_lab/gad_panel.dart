import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../providers/slot_lab/gad_provider.dart';

/// GAD Panel — Gameplay-Aware DAW (MASTER_SPEC §15).
///
/// Dual timeline editor, 8-type track manager, and Bake To Slot pipeline.
class GadPanel extends StatefulWidget {
  const GadPanel({super.key});

  @override
  State<GadPanel> createState() => _GadPanelState();
}

class _GadPanelState extends State<GadPanel> with SingleTickerProviderStateMixin {
  late final GadProvider _provider;
  late final TabController _tabCtrl;
  final _trackNameCtrl = TextEditingController();
  GadTrackType _selectedType = GadTrackType.musicLayer;

  @override
  void initState() {
    super.initState();
    _provider = GetIt.instance<GadProvider>();
    _provider.addListener(_onUpdate);
    _tabCtrl = TabController(length: 3, vsync: this);
    if (!_provider.initialized) _provider.initialize();
  }

  @override
  void dispose() {
    _provider.removeListener(_onUpdate);
    _tabCtrl.dispose();
    _trackNameCtrl.dispose();
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF3A3A5C), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 6),
          _buildTabBar(),
          const SizedBox(height: 6),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _buildTabContent(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.videogame_asset, size: 14, color: Color(0xFF40C8FF)),
        const SizedBox(width: 4),
        Text(
          'Gameplay-Aware DAW',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        // BPM display
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF40C8FF).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '${_provider.bpm.toStringAsFixed(0)} BPM  |  ${_provider.lengthBars} bars',
            style: const TextStyle(color: Color(0xFF40C8FF), fontSize: 9, fontWeight: FontWeight.w500),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '${_provider.trackCount} tracks',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 9),
        ),
      ],
    );
  }

  Widget _buildTabBar() {
    return SizedBox(
      height: 24,
      child: TabBar(
        controller: _tabCtrl,
        onTap: (_) => setState(() {}),
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        indicatorSize: TabBarIndicatorSize.tab,
        indicatorColor: const Color(0xFF40C8FF),
        indicatorWeight: 2,
        labelPadding: const EdgeInsets.symmetric(horizontal: 10),
        labelColor: const Color(0xFF40C8FF),
        unselectedLabelColor: Colors.white54,
        labelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 10),
        dividerColor: Colors.transparent,
        tabs: const [
          Tab(text: 'Tracks'),
          Tab(text: 'Timeline'),
          Tab(text: 'Bake'),
        ],
      ),
    );
  }

  Widget _buildTabContent() {
    return switch (_tabCtrl.index) {
      0 => _buildTracksTab(),
      1 => _buildTimelineTab(),
      2 => _buildBakeTab(),
      _ => const SizedBox.shrink(),
    };
  }

  // ─── Tracks Tab ───

  Widget _buildTracksTab() {
    return Column(
      key: const ValueKey('tracks'),
      children: [
        _buildAddTrackRow(),
        const SizedBox(height: 6),
        Expanded(child: _buildTrackList()),
      ],
    );
  }

  Widget _buildAddTrackRow() {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 24,
            child: TextField(
              controller: _trackNameCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 10),
              decoration: InputDecoration(
                hintText: 'Track name...',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 10),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                filled: true,
                fillColor: const Color(0xFF2A2A3E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        _buildTypeDropdown(),
        const SizedBox(width: 4),
        _buildIconButton(Icons.add, 'Add', () {
          if (_trackNameCtrl.text.isNotEmpty) {
            _provider.addTrack(_trackNameCtrl.text, _selectedType);
            _trackNameCtrl.clear();
          }
        }),
      ],
    );
  }

  Widget _buildTypeDropdown() {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A3E),
        borderRadius: BorderRadius.circular(4),
      ),
      child: DropdownButton<GadTrackType>(
        value: _selectedType,
        onChanged: (v) => setState(() => _selectedType = v!),
        underline: const SizedBox.shrink(),
        isDense: true,
        dropdownColor: const Color(0xFF2A2A3E),
        style: const TextStyle(color: Colors.white, fontSize: 10),
        items: GadTrackType.values.map((t) => DropdownMenuItem(
          value: t,
          child: Text(t.label, style: const TextStyle(fontSize: 10)),
        )).toList(),
      ),
    );
  }

  Widget _buildTrackList() {
    if (_provider.tracks.isEmpty) {
      return Center(
        child: Text(
          'No tracks — add tracks above',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 10),
        ),
      );
    }

    return ListView.builder(
      itemCount: _provider.tracks.length,
      itemBuilder: (_, i) => _buildTrackItem(_provider.tracks[i]),
    );
  }

  Widget _buildTrackItem(GadTrackData track) {
    return Container(
      margin: const EdgeInsets.only(bottom: 3),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF252538),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: Color(track.trackType == 'MusicLayer' ? 0xFF9370DB
              : track.trackType == 'Transient' ? 0xFFFF9040
              : track.trackType == 'JackpotLadder' ? 0xFFFFD740
              : 0xFF40C8FF).withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              color: Color(_typeColor(track.trackType)),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.name,
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w500),
                ),
                Text(
                  '${track.trackType}  ${track.hookBinding != null ? "→ ${track.hookBinding}" : "• No binding"}',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 8),
                ),
              ],
            ),
          ),
          // Metadata badges
          _metaBadge('E:${track.emotionalBias.toStringAsFixed(1)}', const Color(0xFFE040FB)),
          const SizedBox(width: 3),
          _metaBadge('W:${track.energyWeight.toStringAsFixed(1)}', const Color(0xFFFF9800)),
          const SizedBox(width: 3),
          _metaBadge('H:${track.harmonicDensity}', const Color(0xFF4CAF50)),
          const SizedBox(width: 4),
          InkWell(
            onTap: () => _provider.removeTrack(track.id),
            child: Icon(Icons.close, size: 12, color: Colors.white.withValues(alpha: 0.3)),
          ),
        ],
      ),
    );
  }

  Widget _metaBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w500)),
    );
  }

  int _typeColor(String type) => switch (type) {
    'MusicLayer' => 0xFF9370DB,
    'Transient' => 0xFFFF9040,
    'ReelBound' => 0xFF40C8FF,
    'CascadeLayer' => 0xFF40FF90,
    'JackpotLadder' => 0xFFFFD740,
    'Ui' => 0xFF9E9E9E,
    'System' => 0xFF607D8B,
    'AmbientPad' => 0xFF4DB6AC,
    _ => 0xFF808080,
  };

  // ─── Timeline Tab ───

  Widget _buildTimelineTab() {
    return Column(
      key: const ValueKey('timeline'),
      children: [
        _buildBpmRow(),
        const SizedBox(height: 6),
        Expanded(child: _buildTimelineVisual()),
      ],
    );
  }

  Widget _buildBpmRow() {
    return Row(
      children: [
        Text('BPM', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 10)),
        const SizedBox(width: 6),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              activeTrackColor: const Color(0xFF40C8FF),
              inactiveTrackColor: const Color(0xFF2A2A3E),
              thumbColor: const Color(0xFF40C8FF),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
            ),
            child: Slider(
              value: _provider.bpm.clamp(40.0, 300.0),
              min: 40, max: 300,
              onChanged: (v) => _provider.setBpm(v.roundToDouble()),
            ),
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            '${_provider.bpm.toStringAsFixed(0)}',
            style: const TextStyle(color: Color(0xFF40C8FF), fontSize: 11, fontWeight: FontWeight.w600),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineVisual() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E30),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF3A3A5C), width: 0.5),
      ),
      child: Column(
        children: [
          // Bar ruler
          SizedBox(
            height: 20,
            child: CustomPaint(
              painter: _BarRulerPainter(_provider.lengthBars),
              size: const Size(double.infinity, 20),
            ),
          ),
          const Divider(height: 1, color: Color(0xFF3A3A5C)),
          // Musical timeline label
          _timelineRow('Musical', const Color(0xFF9370DB), '${_provider.lengthBars} bars @ ${_provider.bpm.toStringAsFixed(0)} BPM'),
          const Divider(height: 1, color: Color(0xFF2A2A3E)),
          // Gameplay timeline label
          _timelineRow('Gameplay', const Color(0xFFFF9040), 'Frame-based • Hook events'),
          const Divider(height: 1, color: Color(0xFF2A2A3E)),
          // Anchor points
          Expanded(
            child: Center(
              child: Text(
                'Add anchors to sync Musical ↔ Gameplay timelines',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 9),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _timelineRow(String label, Color color, String desc) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Container(
            width: 6, height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Text(desc, style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 9)),
        ],
      ),
    );
  }

  // ─── Bake Tab ───

  Widget _buildBakeTab() {
    return Column(
      key: const ValueKey('bake'),
      children: [
        _buildBakeControls(),
        const SizedBox(height: 6),
        if (_provider.bakeSteps.isNotEmpty) ...[
          _buildBakeProgress(),
          const SizedBox(height: 6),
          Expanded(child: _buildBakeStepList()),
        ] else
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.layers, size: 32, color: Colors.white.withValues(alpha: 0.15)),
                  const SizedBox(height: 8),
                  Text(
                    '11-Step Bake To Slot Pipeline',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 10),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Freeze → Validate → Stems → Mapping → DPM\nSAMCL → PBSE → Safety → DRC → Manifest → Trace',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.2), fontSize: 8),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBakeControls() {
    return Row(
      children: [
        _buildActionButton(
          icon: Icons.auto_fix_high,
          label: 'Validate',
          color: const Color(0xFF4CAF50),
          onTap: () => _provider.validate(),
        ),
        const SizedBox(width: 6),
        _buildActionButton(
          icon: Icons.play_arrow,
          label: _provider.baking ? 'Baking...' : 'Bake To Slot',
          color: const Color(0xFFFF9800),
          onTap: _provider.baking ? null : () => _provider.bake(),
        ),
        const Spacer(),
        if (_provider.bakeSuccess != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: (_provider.bakeSuccess! ? const Color(0xFF4CAF50) : const Color(0xFFF44336)).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _provider.bakeSuccess! ? 'PASSED' : 'FAILED',
              style: TextStyle(
                color: _provider.bakeSuccess! ? const Color(0xFF4CAF50) : const Color(0xFFF44336),
                fontSize: 9, fontWeight: FontWeight.w700,
              ),
            ),
          ),
        if (_provider.validationErrors.isNotEmpty) ...[
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFF44336).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${_provider.validationErrors.length} errors',
              style: const TextStyle(color: Color(0xFFF44336), fontSize: 9),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBakeProgress() {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: _provider.bakeProgress,
            backgroundColor: const Color(0xFF2A2A3E),
            valueColor: AlwaysStoppedAnimation(
              _provider.bakeSuccess == true ? const Color(0xFF4CAF50) : const Color(0xFFFF9800),
            ),
            minHeight: 3,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${(_provider.bakeProgress * 100).toStringAsFixed(0)}% complete',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 8),
        ),
      ],
    );
  }

  Widget _buildBakeStepList() {
    return ListView.builder(
      itemCount: _provider.bakeSteps.length,
      itemBuilder: (_, i) {
        final step = _provider.bakeSteps[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(
            children: [
              Icon(
                step.passed ? Icons.check_circle : Icons.cancel,
                size: 12,
                color: step.passed ? const Color(0xFF4CAF50) : const Color(0xFFF44336),
              ),
              const SizedBox(width: 6),
              Text(
                '${i + 1}. ${step.name}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: step.passed ? 0.7 : 0.5),
                  fontSize: 10,
                ),
              ),
              if (step.error != null) ...[
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    step.error!,
                    style: const TextStyle(color: Color(0xFFF44336), fontSize: 8),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // ─── Shared Widgets ───

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: onTap != null ? 0.15 : 0.05),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color.withValues(alpha: onTap != null ? 1.0 : 0.3)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: color.withValues(alpha: onTap != null ? 0.9 : 0.3),
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIconButton(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 24, height: 24,
          decoration: BoxDecoration(
            color: const Color(0xFF40C8FF).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(icon, size: 14, color: const Color(0xFF40C8FF)),
        ),
      ),
    );
  }
}

/// Simple bar ruler painter for timeline.
class _BarRulerPainter extends CustomPainter {
  final int totalBars;
  _BarRulerPainter(this.totalBars);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF3A3A5C)
      ..strokeWidth = 0.5;

    final textStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.3),
      fontSize: 8,
    );

    final barWidth = size.width / totalBars.clamp(1, totalBars);
    for (int i = 0; i <= totalBars && i <= 64; i++) {
      final x = i * barWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);

      if (i % 4 == 0 && i < totalBars) {
        final tp = TextPainter(
          text: TextSpan(text: '${i + 1}', style: textStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x + 2, 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BarRulerPainter oldDelegate) =>
      oldDelegate.totalBars != totalBars;
}
