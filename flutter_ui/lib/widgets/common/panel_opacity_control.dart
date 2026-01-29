/// P2.15: Panel Opacity Control — Adjustable panel transparency
///
/// Allows users to adjust the opacity of floating panels, overlays,
/// and secondary UI elements to improve focus on primary content.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Panel types that support opacity control
enum OpacityPanel {
  inspector,
  browser,
  mixer,
  lowerZone,
  timeline,
  overlay,
  dialogs,
}

extension OpacityPanelExtension on OpacityPanel {
  String get displayName {
    switch (this) {
      case OpacityPanel.inspector:
        return 'Inspector';
      case OpacityPanel.browser:
        return 'Browser';
      case OpacityPanel.mixer:
        return 'Mixer';
      case OpacityPanel.lowerZone:
        return 'Lower Zone';
      case OpacityPanel.timeline:
        return 'Timeline';
      case OpacityPanel.overlay:
        return 'Overlays';
      case OpacityPanel.dialogs:
        return 'Dialogs';
    }
  }

  IconData get icon {
    switch (this) {
      case OpacityPanel.inspector:
        return Icons.info_outline;
      case OpacityPanel.browser:
        return Icons.folder_open;
      case OpacityPanel.mixer:
        return Icons.tune;
      case OpacityPanel.lowerZone:
        return Icons.view_stream;
      case OpacityPanel.timeline:
        return Icons.timeline;
      case OpacityPanel.overlay:
        return Icons.layers;
      case OpacityPanel.dialogs:
        return Icons.crop_square;
    }
  }

  /// Default opacity for each panel type
  double get defaultOpacity {
    switch (this) {
      case OpacityPanel.inspector:
        return 1.0;
      case OpacityPanel.browser:
        return 1.0;
      case OpacityPanel.mixer:
        return 1.0;
      case OpacityPanel.lowerZone:
        return 0.95;
      case OpacityPanel.timeline:
        return 1.0;
      case OpacityPanel.overlay:
        return 0.9;
      case OpacityPanel.dialogs:
        return 0.95;
    }
  }
}

/// Panel opacity configuration
class PanelOpacityConfig {
  final Map<OpacityPanel, double> opacities;
  final bool globalEnabled;
  final double globalMultiplier;

  const PanelOpacityConfig({
    this.opacities = const {},
    this.globalEnabled = true,
    this.globalMultiplier = 1.0,
  });

  double getOpacity(OpacityPanel panel) {
    if (!globalEnabled) return 1.0;
    final base = opacities[panel] ?? panel.defaultOpacity;
    return (base * globalMultiplier).clamp(0.3, 1.0);
  }

  PanelOpacityConfig copyWith({
    Map<OpacityPanel, double>? opacities,
    bool? globalEnabled,
    double? globalMultiplier,
  }) {
    return PanelOpacityConfig(
      opacities: opacities ?? this.opacities,
      globalEnabled: globalEnabled ?? this.globalEnabled,
      globalMultiplier: globalMultiplier ?? this.globalMultiplier,
    );
  }

  Map<String, dynamic> toJson() => {
    'opacities': opacities.map((k, v) => MapEntry(k.index.toString(), v)),
    'globalEnabled': globalEnabled,
    'globalMultiplier': globalMultiplier,
  };

  factory PanelOpacityConfig.fromJson(Map<String, dynamic> json) {
    final opacitiesJson = json['opacities'] as Map<String, dynamic>? ?? {};
    final opacities = <OpacityPanel, double>{};

    for (final entry in opacitiesJson.entries) {
      final index = int.tryParse(entry.key);
      if (index != null && index < OpacityPanel.values.length) {
        opacities[OpacityPanel.values[index]] = (entry.value as num).toDouble();
      }
    }

    return PanelOpacityConfig(
      opacities: opacities,
      globalEnabled: json['globalEnabled'] as bool? ?? true,
      globalMultiplier: (json['globalMultiplier'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

/// Provider for panel opacity settings
class PanelOpacityProvider extends ChangeNotifier {
  static final PanelOpacityProvider instance = PanelOpacityProvider._();
  PanelOpacityProvider._();

  static const String _storageKey = 'panel_opacity_config';

  PanelOpacityConfig _config = const PanelOpacityConfig();
  bool _initialized = false;

  PanelOpacityConfig get config => _config;
  bool get initialized => _initialized;

  /// Get opacity for a specific panel
  double getOpacity(OpacityPanel panel) => _config.getOpacity(panel);

  /// Check if opacity controls are enabled
  bool get isEnabled => _config.globalEnabled;

  Future<void> init() async {
    if (_initialized) return;

    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_storageKey);
    if (json != null) {
      try {
        _config = PanelOpacityConfig.fromJson(jsonDecode(json) as Map<String, dynamic>);
      } catch (e) {
        debugPrint('[PanelOpacity] Load error: $e');
      }
    }

    _initialized = true;
    notifyListeners();
  }

  Future<void> setConfig(PanelOpacityConfig config) async {
    _config = config;
    notifyListeners();
    await _persist();
  }

  Future<void> setOpacity(OpacityPanel panel, double opacity) async {
    final newOpacities = Map<OpacityPanel, double>.from(_config.opacities);
    newOpacities[panel] = opacity.clamp(0.3, 1.0);
    _config = _config.copyWith(opacities: newOpacities);
    notifyListeners();
    await _persist();
  }

  Future<void> setGlobalEnabled(bool enabled) async {
    _config = _config.copyWith(globalEnabled: enabled);
    notifyListeners();
    await _persist();
  }

  Future<void> setGlobalMultiplier(double multiplier) async {
    _config = _config.copyWith(globalMultiplier: multiplier.clamp(0.5, 1.0));
    notifyListeners();
    await _persist();
  }

  Future<void> resetToDefaults() async {
    _config = const PanelOpacityConfig();
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(_config.toJson()));
  }
}

/// Wrapper widget that applies opacity to its child
class OpacityControlledPanel extends StatelessWidget {
  final OpacityPanel panel;
  final Widget child;
  final bool animate;

  const OpacityControlledPanel({
    super.key,
    required this.panel,
    required this.child,
    this.animate = true,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PanelOpacityProvider.instance,
      builder: (context, _) {
        final opacity = PanelOpacityProvider.instance.getOpacity(panel);

        if (animate) {
          return AnimatedOpacity(
            opacity: opacity,
            duration: const Duration(milliseconds: 200),
            child: child,
          );
        }

        return Opacity(opacity: opacity, child: child);
      },
    );
  }
}

/// Panel opacity control settings panel
class PanelOpacityControlPanel extends StatefulWidget {
  const PanelOpacityControlPanel({super.key});

  @override
  State<PanelOpacityControlPanel> createState() => _PanelOpacityControlPanelState();
}

class _PanelOpacityControlPanelState extends State<PanelOpacityControlPanel> {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PanelOpacityProvider.instance,
      builder: (context, _) {
        final provider = PanelOpacityProvider.instance;
        final config = provider.config;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF121216),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(provider),
              const SizedBox(height: 16),
              _buildGlobalControls(config, provider),
              const SizedBox(height: 16),
              if (config.globalEnabled) ...[
                const Divider(color: Color(0xFF2A2A35)),
                const SizedBox(height: 16),
                _buildPanelList(config, provider),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(PanelOpacityProvider provider) {
    return Row(
      children: [
        const Icon(Icons.opacity, size: 18, color: Color(0xFF4A9EFF)),
        const SizedBox(width: 8),
        const Text(
          'Panel Opacity',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const Spacer(),
        TextButton(
          onPressed: () => provider.resetToDefaults(),
          child: const Text(
            'Reset',
            style: TextStyle(fontSize: 12, color: Color(0xFF808080)),
          ),
        ),
      ],
    );
  }

  Widget _buildGlobalControls(PanelOpacityConfig config, PanelOpacityProvider provider) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Enable Opacity Control',
                    style: TextStyle(fontSize: 12, color: Colors.white),
                  ),
                  Text(
                    config.globalEnabled ? 'Active' : 'Disabled',
                    style: TextStyle(
                      fontSize: 10,
                      color: config.globalEnabled
                          ? const Color(0xFF40FF90)
                          : const Color(0xFF808080),
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: config.globalEnabled,
              onChanged: (value) => provider.setGlobalEnabled(value),
              activeColor: const Color(0xFF4A9EFF),
            ),
          ],
        ),
        if (config.globalEnabled) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Global Multiplier',
                style: TextStyle(fontSize: 12, color: Color(0xFF808080)),
              ),
              Text(
                '${(config.globalMultiplier * 100).toInt()}%',
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: Color(0xFF4A9EFF),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: const Color(0xFF4A9EFF),
              inactiveTrackColor: const Color(0xFF2A2A35),
              thumbColor: const Color(0xFF4A9EFF),
              overlayColor: const Color(0xFF4A9EFF).withOpacity(0.2),
            ),
            child: Slider(
              value: config.globalMultiplier,
              min: 0.5,
              max: 1.0,
              onChanged: (value) => provider.setGlobalMultiplier(value),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPanelList(PanelOpacityConfig config, PanelOpacityProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Panel Settings',
          style: TextStyle(fontSize: 12, color: Color(0xFF808080)),
        ),
        const SizedBox(height: 12),
        ...OpacityPanel.values.map(
          (panel) => _buildPanelOpacitySlider(panel, config, provider),
        ),
      ],
    );
  }

  Widget _buildPanelOpacitySlider(
    OpacityPanel panel,
    PanelOpacityConfig config,
    PanelOpacityProvider provider,
  ) {
    final opacity = config.opacities[panel] ?? panel.defaultOpacity;
    final effectiveOpacity = config.getOpacity(panel);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          Row(
            children: [
              Icon(panel.icon, size: 14, color: const Color(0xFF808080)),
              const SizedBox(width: 8),
              Text(
                panel.displayName,
                style: const TextStyle(fontSize: 12, color: Colors.white),
              ),
              const Spacer(),
              Container(
                width: 50,
                height: 20,
                decoration: BoxDecoration(
                  color: Color.fromRGBO(74, 158, 255, effectiveOpacity),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFF4A9EFF)),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${(effectiveOpacity * 100).toInt()}%',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              activeTrackColor: const Color(0xFF4A9EFF),
              inactiveTrackColor: const Color(0xFF2A2A35),
              thumbColor: const Color(0xFF4A9EFF),
              overlayColor: const Color(0xFF4A9EFF).withOpacity(0.2),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: opacity,
              min: 0.3,
              max: 1.0,
              onChanged: (value) => provider.setOpacity(panel, value),
            ),
          ),
        ],
      ),
    );
  }
}

/// Quick opacity preset buttons
class OpacityPresetButtons extends StatelessWidget {
  const OpacityPresetButtons({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildPresetButton('Focus', 0.6, Icons.center_focus_strong),
        const SizedBox(width: 8),
        _buildPresetButton('Normal', 1.0, Icons.tune),
        const SizedBox(width: 8),
        _buildPresetButton('Dim', 0.75, Icons.brightness_low),
      ],
    );
  }

  Widget _buildPresetButton(String label, double multiplier, IconData icon) {
    return GestureDetector(
      onTap: () => PanelOpacityProvider.instance.setGlobalMultiplier(multiplier),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A20),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFF2A2A35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: const Color(0xFF808080)),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Color(0xFF808080)),
            ),
          ],
        ),
      ),
    );
  }
}
