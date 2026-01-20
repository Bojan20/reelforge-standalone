/// FabFilter Panel Base Widget
///
/// Common base class for all FabFilter-style panels with:
/// - Header with title, bypass, A/B comparison
/// - Bottom bar with resize, help, settings
/// - Undo/Redo support
/// - Full screen mode

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'fabfilter_theme.dart';

/// State for A/B comparison
class ABState<T> {
  T? stateA;
  T? stateB;
  bool isB = false;

  void storeA(T state) => stateA = state;
  void storeB(T state) => stateB = state;
  T? get current => isB ? stateB : stateA;

  void toggle() => isB = !isB;

  void copyAToB() => stateB = stateA;
  void copyBToA() => stateA = stateB;
}

/// Base class for FabFilter-style DSP panels
abstract class FabFilterPanelBase extends StatefulWidget {
  /// Panel title (e.g., "PRO-Q 4")
  final String title;

  /// Icon for the panel
  final IconData icon;

  /// Accent color
  final Color accentColor;

  /// Track ID
  final int trackId;

  /// Sample rate
  final double sampleRate;

  /// Callback when settings change
  final VoidCallback? onSettingsChanged;

  const FabFilterPanelBase({
    super.key,
    required this.title,
    required this.icon,
    required this.trackId,
    this.accentColor = FabFilterColors.blue,
    this.sampleRate = 48000.0,
    this.onSettingsChanged,
  });
}

/// State mixin for FabFilter panels
mixin FabFilterPanelMixin<T extends FabFilterPanelBase> on State<T> {
  bool _bypassed = false;
  bool _isFullScreen = false;
  bool _showExpertMode = false;

  // A/B state is managed by subclass
  bool _isStateB = false;

  bool get bypassed => _bypassed;
  bool get isFullScreen => _isFullScreen;
  bool get showExpertMode => _showExpertMode;
  bool get isStateB => _isStateB;

  void toggleBypass() => setState(() => _bypassed = !_bypassed);
  void toggleFullScreen() => setState(() => _isFullScreen = !_isFullScreen);
  void toggleExpertMode() => setState(() => _showExpertMode = !_showExpertMode);

  void toggleAB() {
    setState(() => _isStateB = !_isStateB);
    onABToggle(_isStateB);
  }

  /// Override to handle A/B toggle
  void onABToggle(bool isB) {}

  /// Override to store state A
  void storeStateA() {}

  /// Override to store state B
  void storeStateB() {}

  /// Build the main panel header
  Widget buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: FabFilterColors.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          // Icon and title
          Icon(widget.icon, color: widget.accentColor, size: 18),
          const SizedBox(width: 8),
          Text(widget.title, style: FabFilterText.title),

          const SizedBox(width: 16),

          // Expert mode toggle
          _buildExpertToggle(),

          const Spacer(),

          // A/B comparison
          _buildABComparison(),

          const SizedBox(width: 12),

          // Bypass
          _buildBypassButton(),

          const SizedBox(width: 8),

          // Full screen
          _buildFullScreenButton(),
        ],
      ),
    );
  }

  Widget _buildExpertToggle() {
    return GestureDetector(
      onTap: toggleExpertMode,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: _showExpertMode
            ? FabFilterDecorations.toggleActive(widget.accentColor)
            : FabFilterDecorations.toggleInactive(),
        child: Text(
          'EXPERT',
          style: TextStyle(
            color: _showExpertMode
                ? widget.accentColor
                : FabFilterColors.textTertiary,
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildABComparison() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildABButton('A', !_isStateB, () {
          if (_isStateB) toggleAB();
        }, storeStateA),
        const SizedBox(width: 4),
        _buildABButton('B', _isStateB, () {
          if (!_isStateB) toggleAB();
        }, storeStateB),
        const SizedBox(width: 8),
        // Copy button
        GestureDetector(
          onTap: () {
            // Copy current to other
            if (_isStateB) {
              // Copy B to A would require subclass implementation
            } else {
              // Copy A to B
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: FabFilterDecorations.toggleInactive(),
            child: const Icon(
              Icons.copy,
              size: 12,
              color: FabFilterColors.textTertiary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildABButton(
    String label,
    bool isActive,
    VoidCallback onTap,
    VoidCallback onLongPress,
  ) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: 26,
        height: 26,
        decoration: isActive
            ? FabFilterDecorations.toggleActive(widget.accentColor)
            : FabFilterDecorations.toggleInactive(),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isActive ? widget.accentColor : FabFilterColors.textTertiary,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBypassButton() {
    return GestureDetector(
      onTap: toggleBypass,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: _bypassed
            ? FabFilterDecorations.toggleActive(FabFilterColors.orange)
            : FabFilterDecorations.toggleInactive(),
        child: Text(
          'BYPASS',
          style: TextStyle(
            color: _bypassed
                ? FabFilterColors.orange
                : FabFilterColors.textTertiary,
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildFullScreenButton() {
    return GestureDetector(
      onTap: toggleFullScreen,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: FabFilterDecorations.toggleInactive(),
        child: Icon(
          _isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
          size: 16,
          color: FabFilterColors.textTertiary,
        ),
      ),
    );
  }

  /// Build the bottom toolbar
  Widget buildBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: const BoxDecoration(
        color: FabFilterColors.bgMid,
        border: Border(
          top: BorderSide(color: FabFilterColors.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          // Help
          _buildBottomButton(Icons.help_outline, 'Help', () {
            // Show help
          }),

          const SizedBox(width: 8),

          // MIDI Learn
          _buildBottomButton(Icons.music_note, 'MIDI', () {
            // Toggle MIDI learn
          }),

          const Spacer(),

          // Resize options
          _buildResizeButton(),
        ],
      ),
    );
  }

  Widget _buildBottomButton(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(4),
          child: Icon(
            icon,
            size: 14,
            color: FabFilterColors.textTertiary,
          ),
        ),
      ),
    );
  }

  Widget _buildResizeButton() {
    return PopupMenuButton<double>(
      tooltip: 'Interface Size',
      icon: const Icon(
        Icons.aspect_ratio,
        size: 14,
        color: FabFilterColors.textTertiary,
      ),
      color: FabFilterColors.bgMid,
      itemBuilder: (context) => [
        _buildResizeItem('Small', 0.8),
        _buildResizeItem('Medium', 1.0),
        _buildResizeItem('Large', 1.2),
        _buildResizeItem('Extra Large', 1.5),
      ],
      onSelected: (scale) {
        // Handle resize
      },
    );
  }

  PopupMenuItem<double> _buildResizeItem(String label, double scale) {
    return PopupMenuItem(
      value: scale,
      child: Text(
        label,
        style: const TextStyle(
          color: FabFilterColors.textSecondary,
          fontSize: 12,
        ),
      ),
    );
  }

  /// Build a section with label
  Widget buildSection(String label, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(label, style: FabFilterText.sectionHeader),
        ),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: FabFilterDecorations.section(),
          child: child,
        ),
      ],
    );
  }

  /// Build a toggle button
  Widget buildToggle(
    String label,
    bool value,
    ValueChanged<bool> onChanged, {
    Color? activeColor,
  }) {
    final color = activeColor ?? widget.accentColor;
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: value
            ? FabFilterDecorations.toggleActive(color)
            : FabFilterDecorations.toggleInactive(),
        child: Text(
          label,
          style: TextStyle(
            color: value ? color : FabFilterColors.textTertiary,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  /// Build a dropdown selector
  Widget buildDropdown<E>(
    String label,
    E value,
    List<E> items,
    String Function(E) labelFn,
    ValueChanged<E> onChanged,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: FabFilterText.paramLabel,
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: FabFilterDecorations.toggleInactive(),
          child: DropdownButton<E>(
            value: value,
            dropdownColor: FabFilterColors.bgMid,
            style: const TextStyle(
              color: FabFilterColors.textSecondary,
              fontSize: 10,
            ),
            underline: const SizedBox(),
            isDense: true,
            items: items
                .map((e) => DropdownMenuItem(
                      value: e,
                      child: Text(labelFn(e)),
                    ))
                .toList(),
            onChanged: (v) => v != null ? onChanged(v) : null,
          ),
        ),
      ],
    );
  }

  /// Build a parameter slider row
  Widget buildSliderRow(
    String label,
    double value,
    double min,
    double max,
    String display,
    ValueChanged<double> onChanged, {
    Color? color,
    bool logarithmic = false,
  }) {
    final sliderColor = color ?? widget.accentColor;

    // Convert to/from log scale if needed
    double sliderValue;
    if (logarithmic && min > 0) {
      sliderValue = (math.log(value) - math.log(min)) /
          (math.log(max) - math.log(min));
    } else {
      sliderValue = (value - min) / (max - min);
    }

    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(label, style: FabFilterText.paramLabel),
        ),
        Expanded(
          child: SliderTheme(
            data: fabFilterSliderTheme(sliderColor),
            child: Slider(
              value: sliderValue.clamp(0.0, 1.0),
              onChanged: (v) {
                double newValue;
                if (logarithmic && min > 0) {
                  newValue = math.exp(
                      math.log(min) + v * (math.log(max) - math.log(min)));
                } else {
                  newValue = min + v * (max - min);
                }
                onChanged(newValue.clamp(min, max));
              },
            ),
          ),
        ),
        SizedBox(
          width: 60,
          child: Text(
            display,
            style: FabFilterText.paramValue(sliderColor),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}
