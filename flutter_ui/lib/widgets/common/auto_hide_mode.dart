/// P2.16: Auto-Hide Mode — Panels that hide when not in use
///
/// Provides auto-hiding functionality for panels to maximize workspace
/// when focus is needed on primary content.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Panels that support auto-hide
enum AutoHidePanel {
  leftZone,
  rightZone,
  lowerZone,
  toolbar,
  browser,
  inspector,
}

extension AutoHidePanelExtension on AutoHidePanel {
  String get displayName {
    switch (this) {
      case AutoHidePanel.leftZone:
        return 'Left Zone';
      case AutoHidePanel.rightZone:
        return 'Right Zone';
      case AutoHidePanel.lowerZone:
        return 'Lower Zone';
      case AutoHidePanel.toolbar:
        return 'Toolbar';
      case AutoHidePanel.browser:
        return 'Browser';
      case AutoHidePanel.inspector:
        return 'Inspector';
    }
  }

  IconData get icon {
    switch (this) {
      case AutoHidePanel.leftZone:
        return Icons.vertical_split;
      case AutoHidePanel.rightZone:
        return Icons.vertical_split;
      case AutoHidePanel.lowerZone:
        return Icons.view_stream;
      case AutoHidePanel.toolbar:
        return Icons.space_bar;
      case AutoHidePanel.browser:
        return Icons.folder_open;
      case AutoHidePanel.inspector:
        return Icons.info_outline;
    }
  }

  /// Edge where panel appears from
  AutoHideEdge get edge {
    switch (this) {
      case AutoHidePanel.leftZone:
      case AutoHidePanel.browser:
        return AutoHideEdge.left;
      case AutoHidePanel.rightZone:
      case AutoHidePanel.inspector:
        return AutoHideEdge.right;
      case AutoHidePanel.lowerZone:
        return AutoHideEdge.bottom;
      case AutoHidePanel.toolbar:
        return AutoHideEdge.top;
    }
  }
}

/// Edge from which panel slides in
enum AutoHideEdge {
  left,
  right,
  top,
  bottom,
}

/// Auto-hide trigger mode
enum AutoHideTrigger {
  hover,      // Show on mouse hover
  click,      // Show on click only
  hotKey,     // Show with keyboard shortcut
  proximity,  // Show when mouse is near edge
}

extension AutoHideTriggerExtension on AutoHideTrigger {
  String get displayName {
    switch (this) {
      case AutoHideTrigger.hover:
        return 'Hover';
      case AutoHideTrigger.click:
        return 'Click';
      case AutoHideTrigger.hotKey:
        return 'Hotkey';
      case AutoHideTrigger.proximity:
        return 'Proximity';
    }
  }
}

/// Configuration for auto-hide behavior
class AutoHideConfig {
  final bool globalEnabled;
  final Set<AutoHidePanel> enabledPanels;
  final AutoHideTrigger trigger;
  final Duration showDelay;
  final Duration hideDelay;
  final double proximityThreshold;
  final bool showTabStrip;
  final bool animateTransition;

  const AutoHideConfig({
    this.globalEnabled = false,
    this.enabledPanels = const {},
    this.trigger = AutoHideTrigger.hover,
    this.showDelay = const Duration(milliseconds: 200),
    this.hideDelay = const Duration(milliseconds: 500),
    this.proximityThreshold = 10.0,
    this.showTabStrip = true,
    this.animateTransition = true,
  });

  AutoHideConfig copyWith({
    bool? globalEnabled,
    Set<AutoHidePanel>? enabledPanels,
    AutoHideTrigger? trigger,
    Duration? showDelay,
    Duration? hideDelay,
    double? proximityThreshold,
    bool? showTabStrip,
    bool? animateTransition,
  }) {
    return AutoHideConfig(
      globalEnabled: globalEnabled ?? this.globalEnabled,
      enabledPanels: enabledPanels ?? this.enabledPanels,
      trigger: trigger ?? this.trigger,
      showDelay: showDelay ?? this.showDelay,
      hideDelay: hideDelay ?? this.hideDelay,
      proximityThreshold: proximityThreshold ?? this.proximityThreshold,
      showTabStrip: showTabStrip ?? this.showTabStrip,
      animateTransition: animateTransition ?? this.animateTransition,
    );
  }

  bool isPanelEnabled(AutoHidePanel panel) {
    return globalEnabled && enabledPanels.contains(panel);
  }

  Map<String, dynamic> toJson() => {
    'globalEnabled': globalEnabled,
    'enabledPanels': enabledPanels.map((p) => p.index).toList(),
    'trigger': trigger.index,
    'showDelayMs': showDelay.inMilliseconds,
    'hideDelayMs': hideDelay.inMilliseconds,
    'proximityThreshold': proximityThreshold,
    'showTabStrip': showTabStrip,
    'animateTransition': animateTransition,
  };

  factory AutoHideConfig.fromJson(Map<String, dynamic> json) {
    final panelIndices = (json['enabledPanels'] as List?)?.cast<int>() ?? [];
    final enabledPanels = panelIndices
        .where((i) => i < AutoHidePanel.values.length)
        .map((i) => AutoHidePanel.values[i])
        .toSet();

    return AutoHideConfig(
      globalEnabled: json['globalEnabled'] as bool? ?? false,
      enabledPanels: enabledPanels,
      trigger: AutoHideTrigger.values[json['trigger'] as int? ?? 0],
      showDelay: Duration(milliseconds: json['showDelayMs'] as int? ?? 200),
      hideDelay: Duration(milliseconds: json['hideDelayMs'] as int? ?? 500),
      proximityThreshold: (json['proximityThreshold'] as num?)?.toDouble() ?? 10.0,
      showTabStrip: json['showTabStrip'] as bool? ?? true,
      animateTransition: json['animateTransition'] as bool? ?? true,
    );
  }
}

/// Provider for auto-hide settings
class AutoHideModeProvider extends ChangeNotifier {
  static final AutoHideModeProvider instance = AutoHideModeProvider._();
  AutoHideModeProvider._();

  static const String _storageKey = 'auto_hide_config';

  AutoHideConfig _config = const AutoHideConfig();
  final Map<AutoHidePanel, bool> _visiblePanels = {};
  final Map<AutoHidePanel, bool> _pinnedPanels = {};
  bool _initialized = false;

  AutoHideConfig get config => _config;
  bool get initialized => _initialized;

  /// Check if a panel is currently visible
  bool isPanelVisible(AutoHidePanel panel) {
    if (!_config.isPanelEnabled(panel)) return true; // Not auto-hide, always visible
    return _visiblePanels[panel] ?? false;
  }

  /// Check if a panel is pinned (won't auto-hide)
  bool isPanelPinned(AutoHidePanel panel) {
    return _pinnedPanels[panel] ?? false;
  }

  Future<void> init() async {
    if (_initialized) return;

    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_storageKey);
    if (json != null) {
      try {
        _config = AutoHideConfig.fromJson(jsonDecode(json) as Map<String, dynamic>);
      } catch (e) { /* ignored */ }
    }

    _initialized = true;
    notifyListeners();
  }

  Future<void> setConfig(AutoHideConfig config) async {
    _config = config;
    notifyListeners();
    await _persist();
  }

  Future<void> setGlobalEnabled(bool enabled) async {
    _config = _config.copyWith(globalEnabled: enabled);
    notifyListeners();
    await _persist();
  }

  Future<void> togglePanel(AutoHidePanel panel, bool enabled) async {
    final newPanels = Set<AutoHidePanel>.from(_config.enabledPanels);
    if (enabled) {
      newPanels.add(panel);
    } else {
      newPanels.remove(panel);
    }
    _config = _config.copyWith(enabledPanels: newPanels);
    notifyListeners();
    await _persist();
  }

  void showPanel(AutoHidePanel panel) {
    if (_config.isPanelEnabled(panel)) {
      _visiblePanels[panel] = true;
      notifyListeners();
    }
  }

  void hidePanel(AutoHidePanel panel) {
    if (_config.isPanelEnabled(panel) && !isPanelPinned(panel)) {
      _visiblePanels[panel] = false;
      notifyListeners();
    }
  }

  void togglePanelPin(AutoHidePanel panel) {
    _pinnedPanels[panel] = !(_pinnedPanels[panel] ?? false);
    notifyListeners();
  }

  void showAllPanels() {
    for (final panel in AutoHidePanel.values) {
      _visiblePanels[panel] = true;
    }
    notifyListeners();
  }

  void hideAllPanels() {
    for (final panel in AutoHidePanel.values) {
      if (!isPanelPinned(panel)) {
        _visiblePanels[panel] = false;
      }
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(_config.toJson()));
  }
}

/// Wrapper widget that provides auto-hide functionality
class AutoHideWrapper extends StatefulWidget {
  final AutoHidePanel panel;
  final Widget child;
  final double collapsedSize;
  final double expandedSize;

  const AutoHideWrapper({
    super.key,
    required this.panel,
    required this.child,
    this.collapsedSize = 4.0,
    required this.expandedSize,
  });

  @override
  State<AutoHideWrapper> createState() => _AutoHideWrapperState();
}

class _AutoHideWrapperState extends State<AutoHideWrapper>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  Timer? _showTimer;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _showTimer?.cancel();
    _hideTimer?.cancel();
    super.dispose();
  }

  void _scheduleShow() {
    _hideTimer?.cancel();
    final config = AutoHideModeProvider.instance.config;
    _showTimer = Timer(config.showDelay, () {
      AutoHideModeProvider.instance.showPanel(widget.panel);
      _controller.forward();
    });
  }

  void _scheduleHide() {
    _showTimer?.cancel();
    final provider = AutoHideModeProvider.instance;
    if (provider.isPanelPinned(widget.panel)) return;

    final config = provider.config;
    _hideTimer = Timer(config.hideDelay, () {
      provider.hidePanel(widget.panel);
      _controller.reverse();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AutoHideModeProvider.instance,
      builder: (context, _) {
        final provider = AutoHideModeProvider.instance;
        final config = provider.config;

        if (!config.isPanelEnabled(widget.panel)) {
          return widget.child;
        }

        final isVisible = provider.isPanelVisible(widget.panel);
        final isPinned = provider.isPanelPinned(widget.panel);

        // Update animation state
        if (isVisible && _controller.isDismissed) {
          _controller.forward();
        } else if (!isVisible && _controller.isCompleted) {
          _controller.reverse();
        }

        return MouseRegion(
          onEnter: (_) => _scheduleShow(),
          onExit: (_) => _scheduleHide(),
          child: Stack(
            children: [
              // Collapsed trigger area
              _buildTriggerArea(config),
              // Animated panel
              AnimatedBuilder(
                animation: _animation,
                builder: (context, child) {
                  return _buildAnimatedPanel(config.animateTransition);
                },
              ),
              // Pin button
              if (isVisible && config.showTabStrip)
                _buildPinButton(isPinned),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTriggerArea(AutoHideConfig config) {
    final edge = widget.panel.edge;

    return Positioned(
      left: edge == AutoHideEdge.left ? 0 : null,
      right: edge == AutoHideEdge.right ? 0 : null,
      top: edge == AutoHideEdge.top ? 0 : null,
      bottom: edge == AutoHideEdge.bottom ? 0 : null,
      width: edge == AutoHideEdge.left || edge == AutoHideEdge.right
          ? config.proximityThreshold
          : null,
      height: edge == AutoHideEdge.top || edge == AutoHideEdge.bottom
          ? config.proximityThreshold
          : null,
      child: Container(
        color: Colors.transparent,
      ),
    );
  }

  Widget _buildAnimatedPanel(bool animate) {
    final edge = widget.panel.edge;
    final size = _animation.value * widget.expandedSize +
        (1 - _animation.value) * widget.collapsedSize;

    Widget panel = SizedBox(
      width: edge == AutoHideEdge.left || edge == AutoHideEdge.right ? size : null,
      height: edge == AutoHideEdge.top || edge == AutoHideEdge.bottom ? size : null,
      child: ClipRect(
        child: OverflowBox(
          alignment: _getAlignment(edge),
          maxWidth: edge == AutoHideEdge.left || edge == AutoHideEdge.right
              ? widget.expandedSize
              : null,
          maxHeight: edge == AutoHideEdge.top || edge == AutoHideEdge.bottom
              ? widget.expandedSize
              : null,
          child: widget.child,
        ),
      ),
    );

    if (!animate) {
      return panel;
    }

    return panel;
  }

  Alignment _getAlignment(AutoHideEdge edge) {
    switch (edge) {
      case AutoHideEdge.left:
        return Alignment.centerLeft;
      case AutoHideEdge.right:
        return Alignment.centerRight;
      case AutoHideEdge.top:
        return Alignment.topCenter;
      case AutoHideEdge.bottom:
        return Alignment.bottomCenter;
    }
  }

  Widget _buildPinButton(bool isPinned) {
    return Positioned(
      right: 8,
      top: 8,
      child: GestureDetector(
        onTap: () => AutoHideModeProvider.instance.togglePanelPin(widget.panel),
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: isPinned
                ? const Color(0xFF4A9EFF).withOpacity(0.2)
                : const Color(0xFF1A1A20),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isPinned
                  ? const Color(0xFF4A9EFF)
                  : const Color(0xFF2A2A35),
            ),
          ),
          child: Icon(
            isPinned ? Icons.push_pin : Icons.push_pin_outlined,
            size: 14,
            color: isPinned
                ? const Color(0xFF4A9EFF)
                : const Color(0xFF808080),
          ),
        ),
      ),
    );
  }
}

/// Auto-hide settings panel
class AutoHideModePanel extends StatefulWidget {
  const AutoHideModePanel({super.key});

  @override
  State<AutoHideModePanel> createState() => _AutoHideModePanelState();
}

class _AutoHideModePanelState extends State<AutoHideModePanel> {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AutoHideModeProvider.instance,
      builder: (context, _) {
        final provider = AutoHideModeProvider.instance;
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
              _buildGlobalToggle(config, provider),
              if (config.globalEnabled) ...[
                const SizedBox(height: 16),
                const Divider(color: Color(0xFF2A2A35)),
                const SizedBox(height: 16),
                _buildTriggerSelector(config, provider),
                const SizedBox(height: 16),
                _buildPanelToggles(config, provider),
                const SizedBox(height: 16),
                _buildTimingSliders(config, provider),
                const SizedBox(height: 16),
                _buildOptions(config, provider),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(AutoHideModeProvider provider) {
    return Row(
      children: [
        const Icon(Icons.auto_awesome, size: 18, color: Color(0xFF4A9EFF)),
        const SizedBox(width: 8),
        const Text(
          'Auto-Hide Mode',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const Spacer(),
        TextButton(
          onPressed: () => provider.showAllPanels(),
          child: const Text(
            'Show All',
            style: TextStyle(fontSize: 11, color: Color(0xFF808080)),
          ),
        ),
      ],
    );
  }

  Widget _buildGlobalToggle(AutoHideConfig config, AutoHideModeProvider provider) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: config.globalEnabled
            ? const Color(0xFF4A9EFF).withOpacity(0.1)
            : const Color(0xFF1A1A20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: config.globalEnabled
              ? const Color(0xFF4A9EFF).withOpacity(0.3)
              : const Color(0xFF2A2A35),
        ),
      ),
      child: Row(
        children: [
          Icon(
            config.globalEnabled ? Icons.visibility_off : Icons.visibility,
            size: 20,
            color: config.globalEnabled
                ? const Color(0xFF4A9EFF)
                : const Color(0xFF808080),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Enable Auto-Hide',
                  style: TextStyle(fontSize: 13, color: Colors.white),
                ),
                Text(
                  config.globalEnabled
                      ? 'Panels hide when not in use'
                      : 'All panels always visible',
                  style: const TextStyle(fontSize: 10, color: Color(0xFF808080)),
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
    );
  }

  Widget _buildTriggerSelector(AutoHideConfig config, AutoHideModeProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Show Trigger',
          style: TextStyle(fontSize: 12, color: Color(0xFF808080)),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: AutoHideTrigger.values.map((trigger) {
            final isSelected = config.trigger == trigger;
            return GestureDetector(
              onTap: () => provider.setConfig(config.copyWith(trigger: trigger)),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF4A9EFF).withOpacity(0.2)
                      : const Color(0xFF1A1A20),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF4A9EFF)
                        : const Color(0xFF2A2A35),
                  ),
                ),
                child: Text(
                  trigger.displayName,
                  style: TextStyle(
                    fontSize: 11,
                    color: isSelected
                        ? const Color(0xFF4A9EFF)
                        : const Color(0xFF808080),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildPanelToggles(AutoHideConfig config, AutoHideModeProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Panels',
          style: TextStyle(fontSize: 12, color: Color(0xFF808080)),
        ),
        const SizedBox(height: 8),
        ...AutoHidePanel.values.map((panel) {
          final isEnabled = config.enabledPanels.contains(panel);
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(panel.icon, size: 16, color: const Color(0xFF808080)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    panel.displayName,
                    style: const TextStyle(fontSize: 12, color: Colors.white),
                  ),
                ),
                Switch(
                  value: isEnabled,
                  onChanged: (value) => provider.togglePanel(panel, value),
                  activeColor: const Color(0xFF4A9EFF),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildTimingSliders(AutoHideConfig config, AutoHideModeProvider provider) {
    return Column(
      children: [
        _buildTimingSlider(
          'Show Delay',
          config.showDelay.inMilliseconds.toDouble(),
          50,
          1000,
          (value) => provider.setConfig(
            config.copyWith(showDelay: Duration(milliseconds: value.toInt())),
          ),
        ),
        const SizedBox(height: 12),
        _buildTimingSlider(
          'Hide Delay',
          config.hideDelay.inMilliseconds.toDouble(),
          100,
          2000,
          (value) => provider.setConfig(
            config.copyWith(hideDelay: Duration(milliseconds: value.toInt())),
          ),
        ),
      ],
    );
  }

  Widget _buildTimingSlider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Color(0xFF808080)),
            ),
            Text(
              '${value.toInt()}ms',
              style: const TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: Color(0xFF4A9EFF),
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
            value: value,
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildOptions(AutoHideConfig config, AutoHideModeProvider provider) {
    return Column(
      children: [
        _buildOptionToggle(
          'Show Tab Strip',
          'Show tab strip when panel is hidden',
          config.showTabStrip,
          (value) => provider.setConfig(config.copyWith(showTabStrip: value)),
        ),
        _buildOptionToggle(
          'Animate Transitions',
          'Smooth slide animation',
          config.animateTransition,
          (value) => provider.setConfig(config.copyWith(animateTransition: value)),
        ),
      ],
    );
  }

  Widget _buildOptionToggle(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 10, color: Color(0xFF808080)),
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
      ),
    );
  }
}
