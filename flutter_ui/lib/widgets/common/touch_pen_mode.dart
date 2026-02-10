/// P2.13: Touch/Pen Mode — Optimized controls for touch and pen input
///
/// Provides larger hit targets, gesture-based controls, and touch-friendly
/// UI elements for tablet and pen display users.

import 'dart:async';
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Input mode for the application
enum InputMode {
  mouse,
  touch,
  pen,
  auto,
}

extension InputModeExtension on InputMode {
  String get displayName {
    switch (this) {
      case InputMode.mouse:
        return 'Mouse';
      case InputMode.touch:
        return 'Touch';
      case InputMode.pen:
        return 'Pen/Stylus';
      case InputMode.auto:
        return 'Auto-Detect';
    }
  }

  IconData get icon {
    switch (this) {
      case InputMode.mouse:
        return Icons.mouse;
      case InputMode.touch:
        return Icons.touch_app;
      case InputMode.pen:
        return Icons.edit;
      case InputMode.auto:
        return Icons.auto_mode;
    }
  }

  /// Hit target size multiplier
  double get hitTargetMultiplier {
    switch (this) {
      case InputMode.mouse:
        return 1.0;
      case InputMode.touch:
        return 1.5;
      case InputMode.pen:
        return 1.25;
      case InputMode.auto:
        return 1.0;
    }
  }

  /// Minimum touch target size (Material guidelines: 48dp for touch)
  double get minHitTarget {
    switch (this) {
      case InputMode.mouse:
        return 24.0;
      case InputMode.touch:
        return 48.0;
      case InputMode.pen:
        return 36.0;
      case InputMode.auto:
        return 24.0;
    }
  }
}

/// Touch/Pen mode configuration
class TouchPenConfig {
  final InputMode mode;
  final bool hapticFeedback;
  final bool longPressPreview;
  final double gestureThreshold;
  final bool showTouchIndicators;
  final bool enablePressureInput;
  final double pressureSensitivity;

  const TouchPenConfig({
    this.mode = InputMode.auto,
    this.hapticFeedback = true,
    this.longPressPreview = true,
    this.gestureThreshold = 20.0,
    this.showTouchIndicators = false,
    this.enablePressureInput = true,
    this.pressureSensitivity = 1.0,
  });

  TouchPenConfig copyWith({
    InputMode? mode,
    bool? hapticFeedback,
    bool? longPressPreview,
    double? gestureThreshold,
    bool? showTouchIndicators,
    bool? enablePressureInput,
    double? pressureSensitivity,
  }) {
    return TouchPenConfig(
      mode: mode ?? this.mode,
      hapticFeedback: hapticFeedback ?? this.hapticFeedback,
      longPressPreview: longPressPreview ?? this.longPressPreview,
      gestureThreshold: gestureThreshold ?? this.gestureThreshold,
      showTouchIndicators: showTouchIndicators ?? this.showTouchIndicators,
      enablePressureInput: enablePressureInput ?? this.enablePressureInput,
      pressureSensitivity: pressureSensitivity ?? this.pressureSensitivity,
    );
  }

  Map<String, dynamic> toJson() => {
    'mode': mode.index,
    'hapticFeedback': hapticFeedback,
    'longPressPreview': longPressPreview,
    'gestureThreshold': gestureThreshold,
    'showTouchIndicators': showTouchIndicators,
    'enablePressureInput': enablePressureInput,
    'pressureSensitivity': pressureSensitivity,
  };

  factory TouchPenConfig.fromJson(Map<String, dynamic> json) {
    return TouchPenConfig(
      mode: InputMode.values[json['mode'] as int? ?? 3],
      hapticFeedback: json['hapticFeedback'] as bool? ?? true,
      longPressPreview: json['longPressPreview'] as bool? ?? true,
      gestureThreshold: (json['gestureThreshold'] as num?)?.toDouble() ?? 20.0,
      showTouchIndicators: json['showTouchIndicators'] as bool? ?? false,
      enablePressureInput: json['enablePressureInput'] as bool? ?? true,
      pressureSensitivity: (json['pressureSensitivity'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

/// Provider for touch/pen mode settings
class TouchPenModeProvider extends ChangeNotifier {
  static final TouchPenModeProvider instance = TouchPenModeProvider._();
  TouchPenModeProvider._();

  static const String _storageKey = 'touch_pen_config';

  TouchPenConfig _config = const TouchPenConfig();
  InputMode _detectedMode = InputMode.mouse;
  bool _initialized = false;

  TouchPenConfig get config => _config;
  InputMode get detectedMode => _detectedMode;
  bool get initialized => _initialized;

  /// Get effective mode (auto-detected or manual)
  InputMode get effectiveMode {
    if (_config.mode == InputMode.auto) {
      return _detectedMode;
    }
    return _config.mode;
  }

  /// Get current hit target multiplier
  double get hitTargetMultiplier => effectiveMode.hitTargetMultiplier;

  /// Get minimum hit target size
  double get minHitTarget => effectiveMode.minHitTarget;

  Future<void> init() async {
    if (_initialized) return;

    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_storageKey);
    if (json != null) {
      try {
        final map = Map<String, dynamic>.from(
          Map.castFrom(Uri.splitQueryString(json).map(
            (k, v) => MapEntry(k, _parseValue(v)),
          )),
        );
        _config = TouchPenConfig.fromJson(map);
      } catch (e) { /* ignored */ }
    }

    _initialized = true;
    notifyListeners();
  }

  dynamic _parseValue(String value) {
    if (value == 'true') return true;
    if (value == 'false') return false;
    final asInt = int.tryParse(value);
    if (asInt != null) return asInt;
    final asDouble = double.tryParse(value);
    if (asDouble != null) return asDouble;
    return value;
  }

  Future<void> setConfig(TouchPenConfig config) async {
    _config = config;
    notifyListeners();
    await _persist();
  }

  Future<void> setMode(InputMode mode) async {
    _config = _config.copyWith(mode: mode);
    notifyListeners();
    await _persist();
  }

  void updateDetectedMode(PointerDeviceKind kind) {
    final newMode = switch (kind) {
      PointerDeviceKind.touch => InputMode.touch,
      PointerDeviceKind.stylus => InputMode.pen,
      PointerDeviceKind.invertedStylus => InputMode.pen,
      _ => InputMode.mouse,
    };

    if (newMode != _detectedMode) {
      _detectedMode = newMode;
      notifyListeners();
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final json = _config.toJson();
    final encoded = json.entries
        .map((e) => '${e.key}=${e.value}')
        .join('&');
    await prefs.setString(_storageKey, encoded);
  }

  /// Trigger haptic feedback if enabled
  void triggerHaptic([HapticFeedbackType type = HapticFeedbackType.lightImpact]) {
    if (!_config.hapticFeedback) return;

    switch (type) {
      case HapticFeedbackType.lightImpact:
        HapticFeedback.lightImpact();
        break;
      case HapticFeedbackType.mediumImpact:
        HapticFeedback.mediumImpact();
        break;
      case HapticFeedbackType.heavyImpact:
        HapticFeedback.heavyImpact();
        break;
      case HapticFeedbackType.selectionClick:
        HapticFeedback.selectionClick();
        break;
    }
  }
}

enum HapticFeedbackType {
  lightImpact,
  mediumImpact,
  heavyImpact,
  selectionClick,
}

/// Wrapper widget that provides touch-optimized hit targets
class TouchOptimizedTarget extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onDoubleTap;
  final double? minWidth;
  final double? minHeight;

  const TouchOptimizedTarget({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.onDoubleTap,
    this.minWidth,
    this.minHeight,
  });

  @override
  Widget build(BuildContext context) {
    final provider = TouchPenModeProvider.instance;
    final minSize = provider.minHitTarget;

    return GestureDetector(
      onTap: () {
        provider.triggerHaptic(HapticFeedbackType.lightImpact);
        onTap?.call();
      },
      onLongPress: () {
        provider.triggerHaptic(HapticFeedbackType.mediumImpact);
        onLongPress?.call();
      },
      onDoubleTap: () {
        provider.triggerHaptic(HapticFeedbackType.lightImpact);
        onDoubleTap?.call();
      },
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: minWidth ?? minSize,
          minHeight: minHeight ?? minSize,
        ),
        child: child,
      ),
    );
  }
}

/// Touch-optimized slider with larger handle
class TouchSlider extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;
  final String? label;
  final bool showValue;

  const TouchSlider({
    super.key,
    required this.value,
    this.min = 0.0,
    this.max = 1.0,
    this.onChanged,
    this.onChangeEnd,
    this.label,
    this.showValue = true,
  });

  @override
  State<TouchSlider> createState() => _TouchSliderState();
}

class _TouchSliderState extends State<TouchSlider> {
  double? _activeValue;

  @override
  Widget build(BuildContext context) {
    final provider = TouchPenModeProvider.instance;
    final thumbSize = 20.0 * provider.hitTargetMultiplier;
    final trackHeight = 4.0 * provider.hitTargetMultiplier;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null || widget.showValue)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (widget.label != null)
                  Text(
                    widget.label!,
                    style: const TextStyle(fontSize: 11, color: Color(0xFF808080)),
                  ),
                if (widget.showValue)
                  Text(
                    (_activeValue ?? widget.value).toStringAsFixed(2),
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: Color(0xFF4A9EFF),
                    ),
                  ),
              ],
            ),
          ),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: trackHeight,
            thumbShape: RoundSliderThumbShape(enabledThumbRadius: thumbSize / 2),
            overlayShape: RoundSliderOverlayShape(overlayRadius: thumbSize),
            activeTrackColor: const Color(0xFF4A9EFF),
            inactiveTrackColor: const Color(0xFF2A2A35),
            thumbColor: const Color(0xFF4A9EFF),
            overlayColor: const Color(0xFF4A9EFF).withOpacity(0.2),
          ),
          child: Slider(
            value: _activeValue ?? widget.value,
            min: widget.min,
            max: widget.max,
            onChanged: (value) {
              setState(() => _activeValue = value);
              provider.triggerHaptic(HapticFeedbackType.selectionClick);
              widget.onChanged?.call(value);
            },
            onChangeEnd: (value) {
              setState(() => _activeValue = null);
              widget.onChangeEnd?.call(value);
            },
          ),
        ),
      ],
    );
  }
}

/// Touch-optimized button with larger hit area
class TouchButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final EdgeInsets? padding;

  const TouchButton({
    super.key,
    required this.child,
    this.onPressed,
    this.onLongPress,
    this.backgroundColor,
    this.foregroundColor,
    this.padding,
  });

  @override
  State<TouchButton> createState() => _TouchButtonState();
}

class _TouchButtonState extends State<TouchButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final provider = TouchPenModeProvider.instance;
    final minSize = provider.minHitTarget;
    final defaultPadding = EdgeInsets.symmetric(
      horizontal: 16 * provider.hitTargetMultiplier,
      vertical: 8 * provider.hitTargetMultiplier,
    );

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: () {
        provider.triggerHaptic(HapticFeedbackType.lightImpact);
        widget.onPressed?.call();
      },
      onLongPress: () {
        provider.triggerHaptic(HapticFeedbackType.mediumImpact);
        widget.onLongPress?.call();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        constraints: BoxConstraints(minWidth: minSize, minHeight: minSize),
        padding: widget.padding ?? defaultPadding,
        decoration: BoxDecoration(
          color: _isPressed
              ? (widget.backgroundColor ?? const Color(0xFF4A9EFF)).withOpacity(0.8)
              : widget.backgroundColor ?? const Color(0xFF4A9EFF),
          borderRadius: BorderRadius.circular(8),
        ),
        child: DefaultTextStyle(
          style: TextStyle(
            color: widget.foregroundColor ?? Colors.white,
            fontWeight: FontWeight.w500,
          ),
          child: IconTheme(
            data: IconThemeData(color: widget.foregroundColor ?? Colors.white),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Touch/Pen mode settings panel
class TouchPenModePanel extends StatefulWidget {
  const TouchPenModePanel({super.key});

  @override
  State<TouchPenModePanel> createState() => _TouchPenModePanelState();
}

class _TouchPenModePanelState extends State<TouchPenModePanel> {
  @override
  Widget build(BuildContext context) {
    final provider = TouchPenModeProvider.instance;
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
          _buildHeader(),
          const SizedBox(height: 16),
          _buildModeSelector(config),
          const SizedBox(height: 16),
          _buildDetectedInfo(provider),
          const SizedBox(height: 16),
          _buildToggleOptions(config, provider),
          const SizedBox(height: 16),
          _buildSensitivitySlider(config, provider),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.touch_app, size: 18, color: Color(0xFF4A9EFF)),
        const SizedBox(width: 8),
        const Text(
          'Touch & Pen Settings',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildModeSelector(TouchPenConfig config) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Input Mode',
          style: TextStyle(fontSize: 12, color: Color(0xFF808080)),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: InputMode.values.map((mode) {
            final isSelected = config.mode == mode;
            return GestureDetector(
              onTap: () => TouchPenModeProvider.instance.setMode(mode),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF4A9EFF).withOpacity(0.2)
                      : const Color(0xFF1A1A20),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF4A9EFF)
                        : const Color(0xFF2A2A35),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      mode.icon,
                      size: 16,
                      color: isSelected
                          ? const Color(0xFF4A9EFF)
                          : const Color(0xFF808080),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      mode.displayName,
                      style: TextStyle(
                        fontSize: 12,
                        color: isSelected
                            ? const Color(0xFF4A9EFF)
                            : const Color(0xFF808080),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildDetectedInfo(TouchPenModeProvider provider) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2A2A35)),
      ),
      child: Row(
        children: [
          Icon(
            provider.detectedMode.icon,
            size: 20,
            color: const Color(0xFF40FF90),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Detected Input',
                style: TextStyle(fontSize: 10, color: Color(0xFF808080)),
              ),
              Text(
                provider.detectedMode.displayName,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF40FF90),
                ),
              ),
            ],
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'Effective Mode',
                style: TextStyle(fontSize: 10, color: Color(0xFF808080)),
              ),
              Text(
                provider.effectiveMode.displayName,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF4A9EFF),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildToggleOptions(TouchPenConfig config, TouchPenModeProvider provider) {
    return Column(
      children: [
        _buildToggle(
          'Haptic Feedback',
          'Vibration feedback on touch',
          config.hapticFeedback,
          (value) => provider.setConfig(config.copyWith(hapticFeedback: value)),
        ),
        _buildToggle(
          'Long Press Preview',
          'Show preview on long press',
          config.longPressPreview,
          (value) => provider.setConfig(config.copyWith(longPressPreview: value)),
        ),
        _buildToggle(
          'Touch Indicators',
          'Show visual touch points',
          config.showTouchIndicators,
          (value) => provider.setConfig(config.copyWith(showTouchIndicators: value)),
        ),
        _buildToggle(
          'Pressure Input',
          'Use pen pressure for velocity',
          config.enablePressureInput,
          (value) => provider.setConfig(config.copyWith(enablePressureInput: value)),
        ),
      ],
    );
  }

  Widget _buildToggle(
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

  Widget _buildSensitivitySlider(TouchPenConfig config, TouchPenModeProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Pressure Sensitivity',
              style: TextStyle(fontSize: 12, color: Colors.white),
            ),
            Text(
              '${(config.pressureSensitivity * 100).toInt()}%',
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: Color(0xFF4A9EFF),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: const Color(0xFF4A9EFF),
            inactiveTrackColor: const Color(0xFF2A2A35),
            thumbColor: const Color(0xFF4A9EFF),
            overlayColor: const Color(0xFF4A9EFF).withOpacity(0.2),
          ),
          child: Slider(
            value: config.pressureSensitivity,
            min: 0.1,
            max: 2.0,
            onChanged: (value) {
              provider.setConfig(config.copyWith(pressureSensitivity: value));
            },
          ),
        ),
      ],
    );
  }
}
