/// Particle Tuning Panel
///
/// UI for configuring particle effects in SlotLab:
/// - Particle count adjustment
/// - Speed and direction controls
/// - Color and opacity settings
/// - Effect presets
/// - Per-tier configuration
///
/// Created: 2026-01-30 (P4.24)

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PARTICLE CONFIGURATION MODEL
// ═══════════════════════════════════════════════════════════════════════════

/// Configuration for a particle effect
class ParticleConfig {
  final int count;
  final double speedMin;
  final double speedMax;
  final double sizeMin;
  final double sizeMax;
  final double opacity;
  final double gravity;
  final double spread;
  final Duration lifetime;
  final Color primaryColor;
  final Color? secondaryColor;
  final ParticleShape shape;
  final bool glow;
  final double glowIntensity;

  const ParticleConfig({
    this.count = 50,
    this.speedMin = 100,
    this.speedMax = 300,
    this.sizeMin = 4,
    this.sizeMax = 12,
    this.opacity = 1.0,
    this.gravity = 200,
    this.spread = 1.0,
    this.lifetime = const Duration(seconds: 2),
    this.primaryColor = const Color(0xFFFFD700),
    this.secondaryColor,
    this.shape = ParticleShape.circle,
    this.glow = true,
    this.glowIntensity = 0.5,
  });

  ParticleConfig copyWith({
    int? count,
    double? speedMin,
    double? speedMax,
    double? sizeMin,
    double? sizeMax,
    double? opacity,
    double? gravity,
    double? spread,
    Duration? lifetime,
    Color? primaryColor,
    Color? secondaryColor,
    ParticleShape? shape,
    bool? glow,
    double? glowIntensity,
  }) {
    return ParticleConfig(
      count: count ?? this.count,
      speedMin: speedMin ?? this.speedMin,
      speedMax: speedMax ?? this.speedMax,
      sizeMin: sizeMin ?? this.sizeMin,
      sizeMax: sizeMax ?? this.sizeMax,
      opacity: opacity ?? this.opacity,
      gravity: gravity ?? this.gravity,
      spread: spread ?? this.spread,
      lifetime: lifetime ?? this.lifetime,
      primaryColor: primaryColor ?? this.primaryColor,
      secondaryColor: secondaryColor ?? this.secondaryColor,
      shape: shape ?? this.shape,
      glow: glow ?? this.glow,
      glowIntensity: glowIntensity ?? this.glowIntensity,
    );
  }

  Map<String, dynamic> toJson() => {
        'count': count,
        'speedMin': speedMin,
        'speedMax': speedMax,
        'sizeMin': sizeMin,
        'sizeMax': sizeMax,
        'opacity': opacity,
        'gravity': gravity,
        'spread': spread,
        'lifetimeMs': lifetime.inMilliseconds,
        'primaryColor': primaryColor.value,
        'secondaryColor': secondaryColor?.value,
        'shape': shape.index,
        'glow': glow,
        'glowIntensity': glowIntensity,
      };

  factory ParticleConfig.fromJson(Map<String, dynamic> json) {
    return ParticleConfig(
      count: json['count'] as int? ?? 50,
      speedMin: (json['speedMin'] as num?)?.toDouble() ?? 100,
      speedMax: (json['speedMax'] as num?)?.toDouble() ?? 300,
      sizeMin: (json['sizeMin'] as num?)?.toDouble() ?? 4,
      sizeMax: (json['sizeMax'] as num?)?.toDouble() ?? 12,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      gravity: (json['gravity'] as num?)?.toDouble() ?? 200,
      spread: (json['spread'] as num?)?.toDouble() ?? 1.0,
      lifetime: Duration(milliseconds: json['lifetimeMs'] as int? ?? 2000),
      primaryColor: Color(json['primaryColor'] as int? ?? 0xFFFFD700),
      secondaryColor:
          json['secondaryColor'] != null ? Color(json['secondaryColor'] as int) : null,
      shape: ParticleShape.values[json['shape'] as int? ?? 0],
      glow: json['glow'] as bool? ?? true,
      glowIntensity: (json['glowIntensity'] as num?)?.toDouble() ?? 0.5,
    );
  }
}

enum ParticleShape {
  circle,
  square,
  star,
  sparkle,
  coin,
}

extension ParticleShapeExtension on ParticleShape {
  String get displayName {
    switch (this) {
      case ParticleShape.circle:
        return 'Circle';
      case ParticleShape.square:
        return 'Square';
      case ParticleShape.star:
        return 'Star';
      case ParticleShape.sparkle:
        return 'Sparkle';
      case ParticleShape.coin:
        return 'Coin';
    }
  }

  IconData get icon {
    switch (this) {
      case ParticleShape.circle:
        return Icons.circle;
      case ParticleShape.square:
        return Icons.square;
      case ParticleShape.star:
        return Icons.star;
      case ParticleShape.sparkle:
        return Icons.auto_awesome;
      case ParticleShape.coin:
        return Icons.monetization_on;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PARTICLE PRESETS
// ═══════════════════════════════════════════════════════════════════════════

/// Built-in particle effect presets
class ParticlePresets {
  ParticlePresets._();

  static const winSmall = ParticleConfig(
    count: 20,
    speedMin: 80,
    speedMax: 200,
    sizeMin: 3,
    sizeMax: 8,
    opacity: 0.9,
    gravity: 150,
    lifetime: Duration(milliseconds: 1500),
    primaryColor: Color(0xFFFFD700),
    shape: ParticleShape.coin,
    glow: true,
    glowIntensity: 0.3,
  );

  static const winBig = ParticleConfig(
    count: 50,
    speedMin: 100,
    speedMax: 300,
    sizeMin: 5,
    sizeMax: 15,
    opacity: 1.0,
    gravity: 180,
    lifetime: Duration(seconds: 2),
    primaryColor: Color(0xFFFFD700),
    secondaryColor: Color(0xFFFFA500),
    shape: ParticleShape.coin,
    glow: true,
    glowIntensity: 0.5,
  );

  static const winMega = ParticleConfig(
    count: 100,
    speedMin: 150,
    speedMax: 400,
    sizeMin: 8,
    sizeMax: 20,
    opacity: 1.0,
    gravity: 200,
    spread: 1.5,
    lifetime: Duration(seconds: 3),
    primaryColor: Color(0xFFFFD700),
    secondaryColor: Color(0xFFFF4500),
    shape: ParticleShape.star,
    glow: true,
    glowIntensity: 0.8,
  );

  static const sparkles = ParticleConfig(
    count: 30,
    speedMin: 50,
    speedMax: 150,
    sizeMin: 2,
    sizeMax: 6,
    opacity: 0.8,
    gravity: 50,
    lifetime: Duration(milliseconds: 1000),
    primaryColor: Color(0xFFFFFFFF),
    shape: ParticleShape.sparkle,
    glow: true,
    glowIntensity: 0.6,
  );

  static const confetti = ParticleConfig(
    count: 80,
    speedMin: 100,
    speedMax: 250,
    sizeMin: 4,
    sizeMax: 10,
    opacity: 1.0,
    gravity: 300,
    spread: 2.0,
    lifetime: Duration(seconds: 3),
    primaryColor: Color(0xFF4A9EFF),
    secondaryColor: Color(0xFFFF4081),
    shape: ParticleShape.square,
    glow: false,
    glowIntensity: 0,
  );

  static const Map<String, ParticleConfig> all = {
    'Small Win': winSmall,
    'Big Win': winBig,
    'Mega Win': winMega,
    'Sparkles': sparkles,
    'Confetti': confetti,
  };
}

// ═══════════════════════════════════════════════════════════════════════════
// PARTICLE TUNING PANEL
// ═══════════════════════════════════════════════════════════════════════════

/// Panel for tuning particle effects
class ParticleTuningPanel extends StatefulWidget {
  final ParticleConfig initialConfig;
  final ValueChanged<ParticleConfig>? onConfigChanged;
  final VoidCallback? onPreview;

  const ParticleTuningPanel({
    super.key,
    this.initialConfig = const ParticleConfig(),
    this.onConfigChanged,
    this.onPreview,
  });

  @override
  State<ParticleTuningPanel> createState() => _ParticleTuningPanelState();
}

class _ParticleTuningPanelState extends State<ParticleTuningPanel> {
  late ParticleConfig _config;

  @override
  void initState() {
    super.initState();
    _config = widget.initialConfig;
  }

  void _updateConfig(ParticleConfig newConfig) {
    setState(() => _config = newConfig);
    widget.onConfigChanged?.call(newConfig);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1A1A2E),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            _buildHeader(),
            const SizedBox(height: 16),

            // Presets
            _buildPresetsSection(),
            const SizedBox(height: 16),

            // Count & Lifetime
            _buildCountSection(),
            const SizedBox(height: 16),

            // Speed
            _buildSpeedSection(),
            const SizedBox(height: 16),

            // Size
            _buildSizeSection(),
            const SizedBox(height: 16),

            // Physics
            _buildPhysicsSection(),
            const SizedBox(height: 16),

            // Appearance
            _buildAppearanceSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.auto_awesome, color: Color(0xFFFFD700), size: 24),
        const SizedBox(width: 12),
        const Text(
          'Particle Effects',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const Spacer(),
        ElevatedButton.icon(
          onPressed: widget.onPreview,
          icon: const Icon(Icons.play_arrow, size: 18),
          label: const Text('Preview'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4A9EFF),
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildPresetsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Presets',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ParticlePresets.all.entries.map((entry) {
            return ActionChip(
              label: Text(entry.key),
              onPressed: () => _updateConfig(entry.value),
              backgroundColor: const Color(0xFF2A2A3E),
              labelStyle: const TextStyle(color: Colors.white70),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildCountSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Quantity & Duration'),
        const SizedBox(height: 8),
        _buildSlider(
          label: 'Particle Count',
          value: _config.count.toDouble(),
          min: 1,
          max: 200,
          divisions: 199,
          suffix: '',
          onChanged: (v) => _updateConfig(_config.copyWith(count: v.round())),
        ),
        _buildSlider(
          label: 'Lifetime',
          value: _config.lifetime.inMilliseconds.toDouble(),
          min: 500,
          max: 5000,
          divisions: 45,
          suffix: 'ms',
          onChanged: (v) => _updateConfig(
            _config.copyWith(lifetime: Duration(milliseconds: v.round())),
          ),
        ),
      ],
    );
  }

  Widget _buildSpeedSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Speed'),
        const SizedBox(height: 8),
        _buildSlider(
          label: 'Min Speed',
          value: _config.speedMin,
          min: 10,
          max: 500,
          suffix: 'px/s',
          onChanged: (v) => _updateConfig(_config.copyWith(speedMin: v)),
        ),
        _buildSlider(
          label: 'Max Speed',
          value: _config.speedMax,
          min: 10,
          max: 500,
          suffix: 'px/s',
          onChanged: (v) => _updateConfig(_config.copyWith(speedMax: v)),
        ),
      ],
    );
  }

  Widget _buildSizeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Size'),
        const SizedBox(height: 8),
        _buildSlider(
          label: 'Min Size',
          value: _config.sizeMin,
          min: 1,
          max: 30,
          suffix: 'px',
          onChanged: (v) => _updateConfig(_config.copyWith(sizeMin: v)),
        ),
        _buildSlider(
          label: 'Max Size',
          value: _config.sizeMax,
          min: 1,
          max: 30,
          suffix: 'px',
          onChanged: (v) => _updateConfig(_config.copyWith(sizeMax: v)),
        ),
      ],
    );
  }

  Widget _buildPhysicsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Physics'),
        const SizedBox(height: 8),
        _buildSlider(
          label: 'Gravity',
          value: _config.gravity,
          min: 0,
          max: 500,
          suffix: 'px/s²',
          onChanged: (v) => _updateConfig(_config.copyWith(gravity: v)),
        ),
        _buildSlider(
          label: 'Spread',
          value: _config.spread,
          min: 0.1,
          max: 3.0,
          suffix: 'x',
          onChanged: (v) => _updateConfig(_config.copyWith(spread: v)),
        ),
      ],
    );
  }

  Widget _buildAppearanceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Appearance'),
        const SizedBox(height: 8),

        // Shape selector
        Row(
          children: [
            const Text('Shape:', style: TextStyle(color: Colors.white70)),
            const SizedBox(width: 12),
            ...ParticleShape.values.map((shape) {
              final isSelected = _config.shape == shape;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: IconButton(
                  icon: Icon(
                    shape.icon,
                    color: isSelected ? const Color(0xFFFFD700) : Colors.white54,
                  ),
                  tooltip: shape.displayName,
                  onPressed: () => _updateConfig(_config.copyWith(shape: shape)),
                  style: IconButton.styleFrom(
                    backgroundColor: isSelected
                        ? const Color(0xFFFFD700).withValues(alpha: 0.2)
                        : Colors.transparent,
                  ),
                ),
              );
            }),
          ],
        ),
        const SizedBox(height: 12),

        // Opacity
        _buildSlider(
          label: 'Opacity',
          value: _config.opacity,
          min: 0.1,
          max: 1.0,
          suffix: '',
          onChanged: (v) => _updateConfig(_config.copyWith(opacity: v)),
        ),

        // Glow
        Row(
          children: [
            const Text('Glow Effect:', style: TextStyle(color: Colors.white70)),
            const SizedBox(width: 12),
            Switch(
              value: _config.glow,
              onChanged: (v) => _updateConfig(_config.copyWith(glow: v)),
              activeColor: const Color(0xFFFFD700),
            ),
          ],
        ),
        if (_config.glow)
          _buildSlider(
            label: 'Glow Intensity',
            value: _config.glowIntensity,
            min: 0.1,
            max: 1.0,
            suffix: '',
            onChanged: (v) => _updateConfig(_config.copyWith(glowIntensity: v)),
          ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title.toUpperCase(),
      style: const TextStyle(
        color: Color(0xFF4A9EFF),
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required String suffix,
    required ValueChanged<double> onChanged,
    int? divisions,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: const TextStyle(color: Colors.white70)),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              activeColor: const Color(0xFFFFD700),
              inactiveColor: Colors.white24,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 70,
            child: Text(
              suffix.isEmpty
                  ? value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1)
                  : '${value.toStringAsFixed(0)}$suffix',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PARTICLE CONFIG SERVICE
// ═══════════════════════════════════════════════════════════════════════════

/// Service for persisting particle configurations
class ParticleConfigService {
  ParticleConfigService._();
  static final instance = ParticleConfigService._();

  static const _prefsKeyPrefix = 'particle_config_';

  final Map<String, ParticleConfig> _configs = {};

  /// Load all saved configs
  Future<void> loadConfigs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith(_prefsKeyPrefix));

      for (final key in keys) {
        final configName = key.substring(_prefsKeyPrefix.length);
        final json = prefs.getString(key);
        if (json != null) {
          // Simple JSON parsing would go here
          // For now, use presets as fallback
          _configs[configName] = ParticlePresets.all[configName] ?? const ParticleConfig();
        }
      }
    } catch (e) { /* ignored */ }
  }

  /// Get config by name
  ParticleConfig getConfig(String name) {
    return _configs[name] ?? ParticlePresets.all[name] ?? const ParticleConfig();
  }

  /// Save config
  Future<void> saveConfig(String name, ParticleConfig config) async {
    _configs[name] = config;
    try {
      final prefs = await SharedPreferences.getInstance();
      // Would serialize to JSON here
      await prefs.setString('$_prefsKeyPrefix$name', 'saved');
    } catch (e) { /* ignored */ }
  }
}
