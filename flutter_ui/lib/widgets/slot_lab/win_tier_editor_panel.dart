/// Win Tier Editor Panel (P5)
///
/// UI za konfigurisanje win tier sistema u SlotLab sekciji.
/// Omogućava dizajnerima da definišu:
/// - Regular win tiers (WIN_LOW, WIN_EQUAL, WIN_1-6)
/// - Big win tiers (BIG_WIN_TIER_1-5)
/// - Display labels za svaki tier
/// - Rollup duration i tick rate
/// - Particle i visual intensity settings
///
/// Sve izmene se čuvaju u SlotLabProjectProvider.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/win_tier_config.dart';
import '../../providers/slot_lab_project_provider.dart';
import '../../theme/fluxforge_theme.dart';

/// Main Win Tier Editor Panel
class WinTierEditorPanel extends StatefulWidget {
  /// Callback when configuration changes
  final VoidCallback? onConfigChanged;

  const WinTierEditorPanel({
    super.key,
    this.onConfigChanged,
  });

  @override
  State<WinTierEditorPanel> createState() => _WinTierEditorPanelState();
}

class _WinTierEditorPanelState extends State<WinTierEditorPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SlotLabProjectProvider>(
      builder: (context, provider, _) {
        final config = provider.winConfiguration;

        return Column(
          children: [
            // Header
            _buildHeader(provider, config),

            // Tab Bar
            Container(
              color: const Color(0xFF1a1a24),
              child: TabBar(
                controller: _tabController,
                indicatorColor: FluxForgeTheme.accentBlue,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white54,
                tabs: const [
                  Tab(text: 'Regular Tiers', icon: Icon(Icons.looks_one, size: 16)),
                  Tab(text: 'Big Win Tiers', icon: Icon(Icons.star, size: 16)),
                  Tab(text: 'Presets', icon: Icon(Icons.tune, size: 16)),
                ],
              ),
            ),

            // Tab Content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _RegularTiersTab(config: config, provider: provider, onChanged: widget.onConfigChanged),
                  _BigWinTiersTab(config: config, provider: provider, onChanged: widget.onConfigChanged),
                  _PresetsTab(config: config, provider: provider, onChanged: widget.onConfigChanged),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeader(SlotLabProjectProvider provider, SlotWinConfiguration config) {
    return Container(
      padding: const EdgeInsets.all(12),
      color: const Color(0xFF121218),
      child: Row(
        children: [
          const Icon(Icons.emoji_events, color: Colors.amber, size: 20),
          const SizedBox(width: 8),
          const Text(
            'Win Tier Configuration',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),

          // Source badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _getSourceColor(config.regularWins.source).withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: _getSourceColor(config.regularWins.source).withOpacity(0.5),
              ),
            ),
            child: Text(
              config.regularWins.source.name.toUpperCase(),
              style: TextStyle(
                color: _getSourceColor(config.regularWins.source),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Big win threshold
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'Big Win: ${config.bigWins.threshold.toInt()}x',
              style: const TextStyle(
                color: Colors.amber,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Reset button
          IconButton(
            icon: const Icon(Icons.restore, color: Colors.white54, size: 18),
            tooltip: 'Reset to defaults',
            onPressed: () => _confirmReset(provider),
          ),
        ],
      ),
    );
  }

  Color _getSourceColor(WinTierConfigSource source) {
    return switch (source) {
      WinTierConfigSource.builtin => Colors.grey,
      WinTierConfigSource.gddImport => Colors.green,
      WinTierConfigSource.manual => FluxForgeTheme.accentBlue,
      WinTierConfigSource.custom => Colors.purple,
    };
  }

  void _confirmReset(SlotLabProjectProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1e1e2a),
        title: const Text('Reset Win Tiers?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will reset all win tier configuration to factory defaults.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              provider.resetWinConfiguration();
              Navigator.pop(ctx);
              widget.onConfigChanged?.call();
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// REGULAR TIERS TAB
// ============================================================================

class _RegularTiersTab extends StatelessWidget {
  final SlotWinConfiguration config;
  final SlotLabProjectProvider provider;
  final VoidCallback? onChanged;

  const _RegularTiersTab({
    required this.config,
    required this.provider,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tiers = config.regularWins.tiers;

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: tiers.length,
      itemBuilder: (context, index) {
        final tier = tiers[index];
        return _RegularTierCard(
          tier: tier,
          onUpdate: (updated) {
            provider.updateRegularWinTier(tier.tierId, updated);
            onChanged?.call();
          },
        );
      },
    );
  }
}

class _RegularTierCard extends StatefulWidget {
  final WinTierDefinition tier;
  final ValueChanged<WinTierDefinition> onUpdate;

  const _RegularTierCard({
    required this.tier,
    required this.onUpdate,
  });

  @override
  State<_RegularTierCard> createState() => _RegularTierCardState();
}

class _RegularTierCardState extends State<_RegularTierCard> {
  late TextEditingController _labelController;
  late TextEditingController _fromController;
  late TextEditingController _toController;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: widget.tier.displayLabel);
    _fromController = TextEditingController(text: widget.tier.fromMultiplier.toString());
    _toController = TextEditingController(text: widget.tier.toMultiplier.toString());
  }

  @override
  void didUpdateWidget(covariant _RegularTierCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tier != widget.tier) {
      _labelController.text = widget.tier.displayLabel;
      _fromController.text = widget.tier.fromMultiplier.toString();
      _toController.text = widget.tier.toMultiplier.toString();
    }
  }

  @override
  void dispose() {
    _labelController.dispose();
    _fromController.dispose();
    _toController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tier = widget.tier;

    return Card(
      color: const Color(0xFF1a1a24),
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          // Header row
          ListTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _getTierColor(tier.tierId).withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _getTierColor(tier.tierId)),
              ),
              child: Center(
                child: Text(
                  tier.tierId == -1 ? 'L' : (tier.tierId == 0 ? '=' : tier.tierId.toString()),
                  style: TextStyle(
                    color: _getTierColor(tier.tierId),
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            title: Text(
              tier.stageName,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text(
              '${tier.fromMultiplier}x – ${tier.toMultiplier}x  •  ${tier.displayLabel.isEmpty ? "(no label)" : tier.displayLabel}',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            trailing: IconButton(
              icon: Icon(
                _isExpanded ? Icons.expand_less : Icons.expand_more,
                color: Colors.white54,
              ),
              onPressed: () => setState(() => _isExpanded = !_isExpanded),
            ),
          ),

          // Expanded editor
          if (_isExpanded) _buildEditor(),
        ],
      ),
    );
  }

  Widget _buildEditor() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF121218),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Display Label
          _buildTextField(
            label: 'Display Label',
            hint: 'e.g., "Nice Win!", "Great!", or leave empty',
            controller: _labelController,
            onChanged: (value) => _updateTier(displayLabel: value),
          ),
          const SizedBox(height: 12),

          // Multiplier Range
          Row(
            children: [
              Expanded(
                child: _buildTextField(
                  label: 'From (x bet)',
                  controller: _fromController,
                  keyboardType: TextInputType.number,
                  onChanged: (value) {
                    final v = double.tryParse(value);
                    if (v != null) _updateTier(fromMultiplier: v);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTextField(
                  label: 'To (x bet)',
                  controller: _toController,
                  keyboardType: TextInputType.number,
                  onChanged: (value) {
                    final v = double.tryParse(value);
                    if (v != null) _updateTier(toMultiplier: v);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Rollup Settings
          Row(
            children: [
              Expanded(
                child: _buildSlider(
                  label: 'Rollup Duration',
                  value: widget.tier.rollupDurationMs.toDouble(),
                  min: 0,
                  max: 5000,
                  divisions: 50,
                  suffix: 'ms',
                  onChanged: (v) => _updateTier(rollupDurationMs: v.toInt()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSlider(
                  label: 'Tick Rate',
                  value: widget.tier.rollupTickRate.toDouble(),
                  min: 5,
                  max: 30,
                  divisions: 25,
                  suffix: '/s',
                  onChanged: (v) => _updateTier(rollupTickRate: v.toInt()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Particle Burst
          _buildSlider(
            label: 'Particle Burst Count',
            value: widget.tier.particleBurstCount.toDouble(),
            min: 0,
            max: 100,
            divisions: 20,
            suffix: '',
            onChanged: (v) => _updateTier(particleBurstCount: v.toInt()),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    String? hint,
    required TextEditingController controller,
    TextInputType? keyboardType,
    required ValueChanged<String> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
            filled: true,
            fillColor: const Color(0xFF1a1a24),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: Colors.white12),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: Colors.white12),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: FluxForgeTheme.accentBlue),
            ),
          ),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String suffix,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
            Text(
              '${value.toInt()}$suffix',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            activeColor: FluxForgeTheme.accentBlue,
            inactiveColor: Colors.white12,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  void _updateTier({
    String? displayLabel,
    double? fromMultiplier,
    double? toMultiplier,
    int? rollupDurationMs,
    int? rollupTickRate,
    int? particleBurstCount,
  }) {
    widget.onUpdate(widget.tier.copyWith(
      displayLabel: displayLabel,
      fromMultiplier: fromMultiplier,
      toMultiplier: toMultiplier,
      rollupDurationMs: rollupDurationMs,
      rollupTickRate: rollupTickRate,
      particleBurstCount: particleBurstCount,
    ));
  }

  Color _getTierColor(int tierId) {
    if (tierId == -1) return Colors.grey;
    if (tierId == 0) return Colors.white54;
    if (tierId <= 2) return Colors.green;
    if (tierId <= 4) return Colors.amber;
    return Colors.orange;
  }
}

// ============================================================================
// BIG WIN TIERS TAB
// ============================================================================

class _BigWinTiersTab extends StatelessWidget {
  final SlotWinConfiguration config;
  final SlotLabProjectProvider provider;
  final VoidCallback? onChanged;

  const _BigWinTiersTab({
    required this.config,
    required this.provider,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Big Win Threshold
        _buildThresholdCard(context),
        const SizedBox(height: 12),

        // Big Win Tiers
        ...config.bigWins.tiers.map((tier) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _BigWinTierCard(
            tier: tier,
            onUpdate: (updated) {
              provider.updateBigWinTier(tier.tierId, updated);
              onChanged?.call();
            },
          ),
        )),
      ],
    );
  }

  Widget _buildThresholdCard(BuildContext context) {
    return Card(
      color: const Color(0xFF1a1a24),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.star, color: Colors.amber, size: 18),
                SizedBox(width: 8),
                Text(
                  'Big Win Threshold',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Wins at or above this multiplier trigger Big Win celebration',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                    ),
                    child: Slider(
                      value: config.bigWins.threshold,
                      min: 10,
                      max: 50,
                      divisions: 40,
                      activeColor: Colors.amber,
                      inactiveColor: Colors.white12,
                      label: '${config.bigWins.threshold.toInt()}x',
                      onChanged: (v) {
                        provider.setBigWinThreshold(v);
                        onChanged?.call();
                      },
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${config.bigWins.threshold.toInt()}x',
                    style: const TextStyle(
                      color: Colors.amber,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BigWinTierCard extends StatefulWidget {
  final BigWinTierDefinition tier;
  final ValueChanged<BigWinTierDefinition> onUpdate;

  const _BigWinTierCard({
    required this.tier,
    required this.onUpdate,
  });

  @override
  State<_BigWinTierCard> createState() => _BigWinTierCardState();
}

class _BigWinTierCardState extends State<_BigWinTierCard> {
  late TextEditingController _labelController;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: widget.tier.displayLabel);
  }

  @override
  void didUpdateWidget(covariant _BigWinTierCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tier.displayLabel != widget.tier.displayLabel) {
      _labelController.text = widget.tier.displayLabel;
    }
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tier = widget.tier;
    final color = _getTierColor(tier.tierId);

    return Card(
      color: const Color(0xFF1a1a24),
      child: Column(
        children: [
          ListTile(
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [color, color.withOpacity(0.6)],
                ),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.4),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  tier.tierId.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
            ),
            title: Text(
              tier.stageName,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text(
              '${tier.fromMultiplier.toInt()}x – ${tier.toMultiplier.isFinite ? "${tier.toMultiplier.toInt()}x" : "∞"}  •  "${tier.displayLabel.isEmpty ? "(no label)" : tier.displayLabel}"',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            trailing: IconButton(
              icon: Icon(
                _isExpanded ? Icons.expand_less : Icons.expand_more,
                color: Colors.white54,
              ),
              onPressed: () => setState(() => _isExpanded = !_isExpanded),
            ),
          ),

          if (_isExpanded) _buildEditor(),
        ],
      ),
    );
  }

  Widget _buildEditor() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF121218),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Display Label
          const Text('Display Label (shown in plaque)',
            style: TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 4),
          TextField(
            controller: _labelController,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'e.g., "BIG WIN!", "MEGA!", or custom',
              hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
              filled: true,
              fillColor: const Color(0xFF1a1a24),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Colors.white12),
              ),
            ),
            onChanged: (value) => _updateTier(displayLabel: value),
          ),
          const SizedBox(height: 16),

          // Duration & Tick Rate
          Row(
            children: [
              Expanded(child: _buildSlider(
                label: 'Duration',
                value: widget.tier.durationMs.toDouble(),
                min: 1000,
                max: 20000,
                divisions: 38,
                suffix: 'ms',
                onChanged: (v) => _updateTier(durationMs: v.toInt()),
              )),
              const SizedBox(width: 12),
              Expanded(child: _buildSlider(
                label: 'Tick Rate',
                value: widget.tier.rollupTickRate.toDouble(),
                min: 2,
                max: 20,
                divisions: 18,
                suffix: '/s',
                onChanged: (v) => _updateTier(rollupTickRate: v.toInt()),
              )),
            ],
          ),
          const SizedBox(height: 12),

          // Visual & Audio Intensity
          Row(
            children: [
              Expanded(child: _buildSlider(
                label: 'Visual Intensity',
                value: widget.tier.visualIntensity,
                min: 1.0,
                max: 2.0,
                divisions: 10,
                suffix: 'x',
                onChanged: (v) => _updateTier(visualIntensity: v),
              )),
              const SizedBox(width: 12),
              Expanded(child: _buildSlider(
                label: 'Audio Intensity',
                value: widget.tier.audioIntensity,
                min: 1.0,
                max: 2.0,
                divisions: 10,
                suffix: 'x',
                onChanged: (v) => _updateTier(audioIntensity: v),
              )),
            ],
          ),
          const SizedBox(height: 12),

          // Particles
          _buildSlider(
            label: 'Particle Multiplier',
            value: widget.tier.particleMultiplier,
            min: 0.5,
            max: 3.0,
            divisions: 25,
            suffix: 'x',
            onChanged: (v) => _updateTier(particleMultiplier: v),
          ),
        ],
      ),
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String suffix,
    required ValueChanged<double> onChanged,
  }) {
    final displayValue = suffix == 'x'
        ? value.toStringAsFixed(1)
        : value.toInt().toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
            Text(
              '$displayValue$suffix',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            activeColor: _getTierColor(widget.tier.tierId),
            inactiveColor: Colors.white12,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  void _updateTier({
    String? displayLabel,
    int? durationMs,
    int? rollupTickRate,
    double? visualIntensity,
    double? audioIntensity,
    double? particleMultiplier,
  }) {
    widget.onUpdate(widget.tier.copyWith(
      displayLabel: displayLabel,
      durationMs: durationMs,
      rollupTickRate: rollupTickRate,
      visualIntensity: visualIntensity,
      audioIntensity: audioIntensity,
      particleMultiplier: particleMultiplier,
    ));
  }

  Color _getTierColor(int tierId) {
    return switch (tierId) {
      1 => Colors.amber,           // Tier 1 (20x-50x)
      2 => Colors.orange,          // Tier 2 (50x-100x)
      3 => Colors.deepOrange,      // Tier 3 (100x-250x)
      4 => Colors.red,             // Tier 4 (250x-500x)
      5 => Colors.purple,          // Tier 5 (500x+)
      _ => Colors.amber,
    };
  }
}

// ============================================================================
// PRESETS TAB
// ============================================================================

class _PresetsTab extends StatelessWidget {
  final SlotWinConfiguration config;
  final SlotLabProjectProvider provider;
  final VoidCallback? onChanged;

  const _PresetsTab({
    required this.config,
    required this.provider,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Built-in presets
        const Text(
          'BUILT-IN PRESETS',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),

        _PresetCard(
          name: 'Standard',
          description: 'Default configuration for medium volatility slots',
          icon: Icons.balance,
          color: FluxForgeTheme.accentBlue,
          isActive: config.regularWins.configId == 'default',
          onApply: () {
            provider.resetWinConfiguration();
            onChanged?.call();
          },
        ),

        _PresetCard(
          name: 'High Volatility',
          description: 'Higher big win thresholds, longer celebrations',
          icon: Icons.trending_up,
          color: Colors.orange,
          isActive: config.regularWins.configId == 'high_volatility',
          onApply: () {
            provider.applyWinTierPreset(SlotWinConfigurationPresets.highVolatility);
            onChanged?.call();
          },
        ),

        _PresetCard(
          name: 'Jackpot Focus',
          description: 'Emphasis on big wins, streamlined regular tiers',
          icon: Icons.emoji_events,
          color: Colors.amber,
          isActive: config.regularWins.configId == 'jackpot',
          onApply: () {
            provider.applyWinTierPreset(SlotWinConfigurationPresets.jackpotFocus);
            onChanged?.call();
          },
        ),

        _PresetCard(
          name: 'Mobile Optimized',
          description: 'Faster celebrations, optimized for mobile sessions',
          icon: Icons.phone_android,
          color: Colors.green,
          isActive: config.regularWins.configId == 'mobile',
          onApply: () {
            provider.applyWinTierPreset(SlotWinConfigurationPresets.mobileOptimized);
            onChanged?.call();
          },
        ),

        const SizedBox(height: 24),

        // Export/Import
        const Text(
          'EXPORT / IMPORT',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),

        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.download, size: 16),
                label: const Text('Export JSON'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white24),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () => _exportConfig(context),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.upload, size: 16),
                label: const Text('Import JSON'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white24),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () => _importConfig(context),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _exportConfig(BuildContext context) {
    final json = provider.exportWinConfigurationJson();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1e1e2a),
        title: const Text('Export Win Tier Config', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: SelectableText(
              json,
              style: const TextStyle(
                color: Colors.white70,
                fontFamily: 'monospace',
                fontSize: 11,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _importConfig(BuildContext context) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1e1e2a),
        title: const Text('Import Win Tier Config', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 500,
          height: 300,
          child: TextField(
            controller: controller,
            maxLines: null,
            expands: true,
            style: const TextStyle(
              color: Colors.white70,
              fontFamily: 'monospace',
              fontSize: 11,
            ),
            decoration: const InputDecoration(
              hintText: 'Paste JSON configuration here...',
              hintStyle: TextStyle(color: Colors.white24),
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final success = provider.importWinConfigurationJson(controller.text);
              Navigator.pop(ctx);
              if (success) {
                onChanged?.call();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Win tier configuration imported')),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Failed to import configuration'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Import'),
          ),
        ],
      ),
    );
  }
}

class _PresetCard extends StatelessWidget {
  final String name;
  final String description;
  final IconData icon;
  final Color color;
  final bool isActive;
  final VoidCallback onApply;

  const _PresetCard({
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
    required this.isActive,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: isActive ? color.withOpacity(0.15) : const Color(0xFF1a1a24),
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isActive ? color : Colors.transparent,
          width: isActive ? 2 : 0,
        ),
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(
          name,
          style: TextStyle(
            color: Colors.white,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        subtitle: Text(
          description,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        trailing: isActive
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'ACTIVE',
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            : TextButton(
                onPressed: onApply,
                child: const Text('Apply'),
              ),
      ),
    );
  }
}
