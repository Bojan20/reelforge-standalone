/// Accessibility Settings Panel — P3-09
///
/// Complete settings panel for accessibility features:
/// - High contrast mode (Off/Increased/Maximum)
/// - Color blindness simulation (Protanopia/Deuteranopia/Tritanopia/Achromatopsia)
/// - Screen reader announcements toggle
/// - Focus highlight toggle
/// - Text scale slider
/// - Large pointer mode
///
/// Usage:
///   AccessibilitySettingsPanel()
library;

import 'package:flutter/material.dart';
import '../../services/accessibility/accessibility_service.dart';

/// Full accessibility settings panel
class AccessibilitySettingsPanel extends StatefulWidget {
  const AccessibilitySettingsPanel({super.key});

  @override
  State<AccessibilitySettingsPanel> createState() => _AccessibilitySettingsPanelState();
}

class _AccessibilitySettingsPanelState extends State<AccessibilitySettingsPanel> {
  @override
  void initState() {
    super.initState();
    AccessibilityService.instance.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    AccessibilityService.instance.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final service = AccessibilityService.instance;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          const Text(
            'Accessibility',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Customize FluxForge for your needs',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 24),

          // High Contrast
          _buildSection(
            title: 'High Contrast',
            subtitle: 'Increase color contrast for better visibility',
            icon: Icons.contrast,
            child: _buildHighContrastSelector(service),
          ),
          const SizedBox(height: 20),

          // Color Blindness
          _buildSection(
            title: 'Color Blindness Mode',
            subtitle: 'Simulate color blindness for testing',
            icon: Icons.palette_outlined,
            child: _buildColorBlindnessSelector(service),
          ),
          const SizedBox(height: 20),

          // Text Scale
          _buildSection(
            title: 'Text Size',
            subtitle: 'Scale: ${(service.textScale * 100).toInt()}%',
            icon: Icons.text_fields,
            child: _buildTextScaleSlider(service),
          ),
          const SizedBox(height: 20),

          // Toggles Section
          _buildSection(
            title: 'Assistance Features',
            subtitle: 'Additional accessibility options',
            icon: Icons.accessibility_new,
            child: Column(
              children: [
                _buildToggle(
                  title: 'Screen Reader',
                  subtitle: 'Announce actions for screen readers',
                  value: service.screenReaderEnabled,
                  onChanged: (v) => service.setScreenReaderEnabled(v),
                ),
                const Divider(color: Colors.white12, height: 24),
                _buildToggle(
                  title: 'Focus Highlight',
                  subtitle: 'Enhanced focus indicators',
                  value: service.focusHighlightEnabled,
                  onChanged: (v) => service.setFocusHighlightEnabled(v),
                ),
                const Divider(color: Colors.white12, height: 24),
                _buildToggle(
                  title: 'Large Pointer',
                  subtitle: 'Increased cursor size',
                  value: service.largePointerEnabled,
                  onChanged: (v) => service.setLargePointerEnabled(v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Preview
          _buildPreviewSection(service),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF4A9EFF), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildHighContrastSelector(AccessibilityService service) {
    return Row(
      children: HighContrastMode.values.map((mode) {
        final isSelected = service.highContrastMode == mode;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: mode != HighContrastMode.maximum ? 8 : 0),
            child: InkWell(
              onTap: () => service.setHighContrastMode(mode),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF4A9EFF).withValues(alpha: 0.2)
                      : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected ? const Color(0xFF4A9EFF) : Colors.white12,
                  ),
                ),
                child: Column(
                  children: [
                    _buildContrastPreview(mode),
                    const SizedBox(height: 8),
                    Text(
                      mode.displayName,
                      style: TextStyle(
                        color: isSelected ? const Color(0xFF4A9EFF) : Colors.white70,
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildContrastPreview(HighContrastMode mode) {
    final colors = switch (mode) {
      HighContrastMode.off => [Colors.grey.shade800, Colors.grey.shade600],
      HighContrastMode.increased => [Colors.grey.shade900, Colors.grey.shade400],
      HighContrastMode.maximum => [Colors.black, Colors.white],
    };

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: colors[0],
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 4),
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: colors[1],
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ],
    );
  }

  Widget _buildColorBlindnessSelector(AccessibilityService service) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: ColorBlindnessMode.values.map((mode) {
        final isSelected = service.colorBlindnessMode == mode;
        return InkWell(
          onTap: () => service.setColorBlindnessMode(mode),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF4A9EFF).withValues(alpha: 0.2)
                  : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? const Color(0xFF4A9EFF) : Colors.white12,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildColorBlindnessIcon(mode, isSelected),
                const SizedBox(width: 8),
                Text(
                  mode == ColorBlindnessMode.none ? 'None' : mode.displayName.split(' ')[0],
                  style: TextStyle(
                    color: isSelected ? const Color(0xFF4A9EFF) : Colors.white70,
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildColorBlindnessIcon(ColorBlindnessMode mode, bool isSelected) {
    final colors = switch (mode) {
      ColorBlindnessMode.none => [Colors.red, Colors.green, Colors.blue],
      ColorBlindnessMode.protanopia => [Colors.yellow, Colors.blue, Colors.grey],
      ColorBlindnessMode.deuteranopia => [Colors.yellow, Colors.grey, Colors.blue],
      ColorBlindnessMode.tritanopia => [Colors.red, Colors.green, Colors.grey],
      ColorBlindnessMode.achromatopsia => [Colors.grey.shade700, Colors.grey.shade500, Colors.grey.shade300],
    };

    return Row(
      children: colors.map((c) {
        return Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.only(right: 2),
          decoration: BoxDecoration(
            color: c,
            shape: BoxShape.circle,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTextScaleSlider(AccessibilityService service) {
    return Column(
      children: [
        Row(
          children: [
            const Text('A', style: TextStyle(color: Colors.white54, fontSize: 10)),
            Expanded(
              child: Slider(
                value: service.textScale,
                min: 0.8,
                max: 2.0,
                divisions: 12,
                activeColor: const Color(0xFF4A9EFF),
                inactiveColor: Colors.white24,
                onChanged: (v) => service.setTextScale(v),
              ),
            ),
            const Text('A', style: TextStyle(color: Colors.white54, fontSize: 18)),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '80%',
              style: TextStyle(color: Colors.white38, fontSize: 10),
            ),
            Text(
              '${(service.textScale * 100).toInt()}%',
              style: const TextStyle(
                color: Color(0xFF4A9EFF),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '200%',
              style: TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildToggle({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: const Color(0xFF4A9EFF),
        ),
      ],
    );
  }

  Widget _buildPreviewSection(AccessibilityService service) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Preview',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildColorSwatch('Red', Colors.red, service),
              const SizedBox(width: 8),
              _buildColorSwatch('Green', Colors.green, service),
              const SizedBox(width: 8),
              _buildColorSwatch('Blue', Colors.blue, service),
              const SizedBox(width: 8),
              _buildColorSwatch('Yellow', Colors.yellow, service),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Sample Text',
            style: TextStyle(
              color: service.applyHighContrast(Colors.white70),
              fontSize: 14 * service.textScale,
            ),
          ),
          Text(
            'This is how text will appear with current settings.',
            style: TextStyle(
              color: service.applyHighContrast(Colors.white54),
              fontSize: 12 * service.textScale,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColorSwatch(String name, Color color, AccessibilityService service) {
    final simulated = service.simulateColorBlindness(color);
    final contrasted = service.applyHighContrast(simulated);

    return Expanded(
      child: Column(
        children: [
          Container(
            height: 32,
            decoration: BoxDecoration(
              color: contrasted,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white24),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            name,
            style: TextStyle(
              color: Colors.white54,
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact accessibility quick menu
class AccessibilityQuickMenu extends StatefulWidget {
  const AccessibilityQuickMenu({super.key});

  @override
  State<AccessibilityQuickMenu> createState() => _AccessibilityQuickMenuState();
}

class _AccessibilityQuickMenuState extends State<AccessibilityQuickMenu> {
  @override
  void initState() {
    super.initState();
    AccessibilityService.instance.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    AccessibilityService.instance.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final service = AccessibilityService.instance;

    return PopupMenuButton<String>(
      icon: Icon(
        Icons.accessibility_new,
        color: service.isHighContrastEnabled || service.isColorBlindnessSimulated
            ? const Color(0xFF4A9EFF)
            : Colors.white54,
        size: 20,
      ),
      tooltip: 'Accessibility options',
      color: const Color(0xFF1A1A20),
      itemBuilder: (context) => [
        PopupMenuItem(
          enabled: false,
          child: Text(
            'Quick Settings',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'contrast',
          child: Row(
            children: [
              Icon(
                Icons.contrast,
                color: service.isHighContrastEnabled
                    ? const Color(0xFF4A9EFF)
                    : Colors.white54,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'High Contrast: ${service.highContrastMode.displayName}',
                style: TextStyle(
                  color: service.isHighContrastEnabled
                      ? const Color(0xFF4A9EFF)
                      : Colors.white,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'reader',
          child: Row(
            children: [
              Icon(
                Icons.record_voice_over,
                color: service.screenReaderEnabled
                    ? const Color(0xFF4A9EFF)
                    : Colors.white54,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Screen Reader: ${service.screenReaderEnabled ? "On" : "Off"}',
                style: TextStyle(
                  color: service.screenReaderEnabled
                      ? const Color(0xFF4A9EFF)
                      : Colors.white,
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'settings',
          child: Row(
            children: [
              Icon(Icons.settings, color: Colors.white54, size: 18),
              SizedBox(width: 8),
              Text('All Settings...', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      ],
      onSelected: (value) {
        switch (value) {
          case 'contrast':
            // Cycle through contrast modes
            final nextIndex = (service.highContrastMode.index + 1) %
                HighContrastMode.values.length;
            service.setHighContrastMode(HighContrastMode.values[nextIndex]);
            break;
          case 'reader':
            service.setScreenReaderEnabled(!service.screenReaderEnabled);
            break;
          case 'settings':
            _showFullSettings(context);
            break;
        }
      },
    );
  }

  void _showFullSettings(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF121216),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SizedBox(
          width: 400,
          height: 600,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.accessibility_new, color: Color(0xFF4A9EFF)),
                    const SizedBox(width: 8),
                    const Text(
                      'Accessibility Settings',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white54),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
              const Expanded(child: AccessibilitySettingsPanel()),
            ],
          ),
        ),
      ),
    );
  }
}
