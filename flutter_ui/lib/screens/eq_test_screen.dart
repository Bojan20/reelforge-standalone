// EQ Test Screen
//
// Test screen to preview all EQ widgets before integration

import 'package:flutter/material.dart';
import '../theme/reelforge_theme.dart';
import '../widgets/eq/pro_eq_editor.dart';
import '../widgets/eq/pultec_eq.dart';
import '../widgets/eq/api550_eq.dart';
import '../widgets/eq/neve1073_eq.dart';
import '../widgets/eq/morph_pad.dart';

class EqTestScreen extends StatefulWidget {
  const EqTestScreen({super.key});

  @override
  State<EqTestScreen> createState() => _EqTestScreenState();
}

class _EqTestScreenState extends State<EqTestScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Analog EQ params
  PultecParams _pultecParams = const PultecParams();
  Api550Params _apiParams = const Api550Params();
  Neve1073Params _neveParams = const Neve1073Params();

  // Morph pad
  Offset _morphPosition = const Offset(0.5, 0.5);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ReelForgeTheme.bgVoid,
      appBar: AppBar(
        backgroundColor: ReelForgeTheme.bgDeep,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: ReelForgeTheme.textSecondary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'EQ Test Lab',
          style: TextStyle(
            color: ReelForgeTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: ReelForgeTheme.accentBlue,
          labelColor: ReelForgeTheme.accentBlue,
          unselectedLabelColor: ReelForgeTheme.textTertiary,
          tabs: const [
            Tab(text: 'Pro EQ 64'),
            Tab(text: 'Pultec'),
            Tab(text: 'API 550'),
            Tab(text: 'Neve 1073'),
            Tab(text: 'Morph Pad'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildProEqTab(),
          _buildPultecTab(),
          _buildApiTab(),
          _buildNeveTab(),
          _buildMorphTab(),
        ],
      ),
    );
  }

  Widget _buildProEqTab() {
    // Fullscreen Pro-EQ with VanEQ Pro styling
    return Container(
      color: ReelForgeTheme.bgVoid, // VanEQ Pro background
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Center(
            child: ProEqEditor(
              trackId: 'master',
              width: constraints.maxWidth - 32,
              height: constraints.maxHeight - 16,
            ),
          );
        },
      ),
    );
  }

  // ignore: unused_element
  Widget _buildProEqFeatures() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        children: [
          _featureChip('64 Bands', Icons.graphic_eq),
          _featureChip('Dynamic EQ', Icons.compress),
          _featureChip('Linear Phase', Icons.waves),
          _featureChip('M/S Mode', Icons.swap_horiz),
          _featureChip('EQ Match', Icons.compare),
          _featureChip('A/B Compare', Icons.compare_arrows),
        ],
      ),
    );
  }

  Widget _featureChip(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgSurface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: ReelForgeTheme.accentBlue),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: ReelForgeTheme.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildPultecTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pultec EQP-1A',
            style: TextStyle(
              color: ReelForgeTheme.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Legendary passive tube EQ • Famous "Boost & Cut" trick • Smooth musical curves',
            style: TextStyle(
              color: ReelForgeTheme.textTertiary,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Center(
              child: PultecEq(
                initialParams: _pultecParams,
                onParamsChanged: (params) {
                  setState(() => _pultecParams = params);
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildPultecInfo(),
        ],
      ),
    );
  }

  Widget _buildPultecInfo() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.lightbulb_outline, color: ReelForgeTheme.accentOrange, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Pro tip: Boost AND cut at the same frequency for the famous "Pultec trick" - adds harmonic richness!',
              style: TextStyle(color: ReelForgeTheme.textSecondary, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApiTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'API 550A',
            style: TextStyle(
              color: ReelForgeTheme.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '3-band discrete EQ • Proportional Q • Punchy American character',
            style: TextStyle(
              color: ReelForgeTheme.textTertiary,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Center(
              child: Api550Eq(
                initialParams: _apiParams,
                onParamsChanged: (params) {
                  setState(() => _apiParams = params);
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildApiInfo(),
        ],
      ),
    );
  }

  Widget _buildApiInfo() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.music_note, color: ReelForgeTheme.accentGreen, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Classic on drums, vocals, and guitars. The proportional Q gives it that "musical" feel.',
              style: TextStyle(color: ReelForgeTheme.textSecondary, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNeveTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Neve 1073',
            style: TextStyle(
              color: ReelForgeTheme.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Legendary preamp/EQ • Inductor-based filters • Transformer saturation',
            style: TextStyle(
              color: ReelForgeTheme.textTertiary,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Center(
              child: Neve1073Eq(
                initialParams: _neveParams,
                onParamsChanged: (params) {
                  setState(() => _neveParams = params);
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildNeveInfo(),
        ],
      ),
    );
  }

  Widget _buildNeveInfo() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, color: ReelForgeTheme.accentCyan, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'The sound of countless hit records. Smooth highs, punchy lows, musical in any setting.',
              style: TextStyle(color: ReelForgeTheme.textSecondary, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMorphTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Preset Morph Pad',
            style: TextStyle(
              color: ReelForgeTheme.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'XY pad for blending between 4 presets • Smooth interpolation • Pro-Q 4 doesn\'t have this!',
            style: TextStyle(
              color: ReelForgeTheme.textTertiary,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Center(
              child: SizedBox(
                width: 400,
                height: 400,
                child: MorphPad(
                  x: _morphPosition.dx,
                  y: _morphPosition.dy,
                  onPositionChanged: (pos) {
                    setState(() => _morphPosition = pos);
                  },
                  presetA: MorphPreset(
                    name: 'Warm',
                    color: ReelForgeTheme.accentOrange,
                    parameters: {'bass': 3.0, 'mid': -1.0, 'treble': -2.0},
                  ),
                  presetB: MorphPreset(
                    name: 'Bright',
                    color: ReelForgeTheme.accentCyan,
                    parameters: {'bass': -1.0, 'mid': 1.0, 'treble': 4.0},
                  ),
                  presetC: MorphPreset(
                    name: 'Flat',
                    color: ReelForgeTheme.textTertiary,
                    parameters: {'bass': 0.0, 'mid': 0.0, 'treble': 0.0},
                  ),
                  presetD: MorphPreset(
                    name: 'Scooped',
                    color: ReelForgeTheme.accentPurple,
                    parameters: {'bass': 4.0, 'mid': -4.0, 'treble': 3.0},
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildMorphInfo(),
        ],
      ),
    );
  }

  Widget _buildMorphInfo() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.touch_app, color: ReelForgeTheme.accentOrange, size: 20),
              const SizedBox(width: 12),
              Text(
                'Drag to blend between presets',
                style: TextStyle(color: ReelForgeTheme.textSecondary, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Position: X=${_morphPosition.dx.toStringAsFixed(2)}, Y=${_morphPosition.dy.toStringAsFixed(2)}',
            style: TextStyle(color: ReelForgeTheme.accentBlue, fontSize: 12, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }
}
