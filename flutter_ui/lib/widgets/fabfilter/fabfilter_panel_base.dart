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
import '../../providers/dsp_chain_provider.dart';
import '../../src/rust/native_ffi.dart';

// Re-export DspNodeType for convenience in panel implementations
export '../../providers/dsp_chain_provider.dart' show DspNodeType;

/// State for A/B comparison with full snapshot support
class ABState<T> {
  T? stateA;
  T? stateB;
  bool isB = false;
  bool _hasStoredA = false;
  bool _hasStoredB = false;

  /// Store current state to A slot
  void storeA(T state) {
    stateA = state;
    _hasStoredA = true;
  }

  /// Store current state to B slot
  void storeB(T state) {
    stateB = state;
    _hasStoredB = true;
  }

  /// Get current active state
  T? get current => isB ? stateB : stateA;

  /// Check if A slot has stored state
  bool get hasStoredA => _hasStoredA;

  /// Check if B slot has stored state
  bool get hasStoredB => _hasStoredB;

  /// Toggle between A and B states
  void toggle() => isB = !isB;

  /// Copy A state to B slot
  void copyAToB() {
    stateB = stateA;
    _hasStoredB = _hasStoredA;
  }

  /// Copy B state to A slot
  void copyBToA() {
    stateA = stateB;
    _hasStoredA = _hasStoredB;
  }

  /// Reset all states
  void reset() {
    stateA = null;
    stateB = null;
    isB = false;
    _hasStoredA = false;
    _hasStoredB = false;
  }
}

/// Interface for DSP parameter snapshot
abstract class DspParameterSnapshot {
  /// Create deep copy of this snapshot
  DspParameterSnapshot copy();

  /// Compare with another snapshot
  bool equals(DspParameterSnapshot other);
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

  /// DSP node type for syncing with DspChainProvider
  /// When set, bypass state syncs with the central DSP chain
  final DspNodeType? nodeType;

  /// Callback when settings change
  final VoidCallback? onSettingsChanged;

  const FabFilterPanelBase({
    super.key,
    required this.title,
    required this.icon,
    required this.trackId,
    this.accentColor = FabFilterColors.blue,
    this.sampleRate = 48000.0,
    this.nodeType,
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
  bool _hasStoredA = false;
  bool _hasStoredB = false;

  bool get bypassed => _bypassed;
  bool get isFullScreen => _isFullScreen;
  bool get showExpertMode => _showExpertMode;
  bool get isStateB => _isStateB;
  bool get hasStoredA => _hasStoredA;
  bool get hasStoredB => _hasStoredB;

  /// Override in subclass to return the insert chain slot index.
  /// Used for direct FFI bypass calls (more reliable than DspChainProvider lookup).
  int get processorSlotIndex => -1;

  void toggleBypass() {
    setState(() => _bypassed = !_bypassed);
    onBypassChanged(_bypassed);
  }

  void toggleFullScreen() => setState(() => _isFullScreen = !_isFullScreen);
  void toggleExpertMode() => setState(() => _showExpertMode = !_showExpertMode);

  void toggleAB() {
    // Before switching, store current state to the active slot
    if (_isStateB) {
      storeStateB();
    } else {
      storeStateA();
    }

    setState(() => _isStateB = !_isStateB);

    // After switching, restore from the new active slot
    if (_isStateB && _hasStoredB) {
      restoreStateB();
    } else if (!_isStateB && _hasStoredA) {
      restoreStateA();
    }

    onABToggle(_isStateB);
  }

  /// Copy current state to A and B (for initialization)
  void initABFromCurrent() {
    storeStateA();
    storeStateB();
    _hasStoredA = true;
    _hasStoredB = true;
  }

  /// Copy active state to the other slot
  void copyCurrentToOther() {
    if (_isStateB) {
      copyBToA();
    } else {
      copyAToB();
    }
  }

  /// Override to handle bypass change
  /// Uses direct FFI call when processorSlotIndex is available (most reliable),
  /// falls back to DspChainProvider lookup otherwise.
  void onBypassChanged(bool bypassed) {
    final slotIdx = processorSlotIndex;
    if (slotIdx >= 0) {
      // Direct FFI — bypasses DspChainProvider indirection entirely
      NativeFFI.instance.insertSetBypass(widget.trackId, slotIdx, bypassed);
      // Keep DspChainProvider UI state in sync
      _syncBypassUiState(bypassed);
    } else if (widget.nodeType != null) {
      // Fallback: DspChainProvider lookup
      _syncBypassToDspChain(bypassed);
    }
  }

  /// Update DspChainProvider UI state without triggering another FFI call
  void _syncBypassUiState(bool bypassed) {
    final nodeType = widget.nodeType;
    if (nodeType == null) return;
    DspChainProvider.instance.setNodeBypassUiOnly(
        widget.trackId, nodeType, bypassed);
  }

  /// Sync bypass state with DspChainProvider (fallback path)
  void _syncBypassToDspChain(bool bypassed) {
    final nodeType = widget.nodeType;
    if (nodeType == null) return;

    final dspProvider = DspChainProvider.instance;
    final chain = dspProvider.getChain(widget.trackId);

    // Find node by type
    final node = chain.nodes.cast<DspNode?>().firstWhere(
          (n) => n?.type == nodeType,
          orElse: () => null,
        );

    if (node != null) {
      // Only toggle if state is different (avoid infinite loops)
      if (node.bypass != bypassed) {
        dspProvider.toggleNodeBypass(widget.trackId, node.id);
      }
    }
  }

  /// Override to handle A/B toggle
  void onABToggle(bool isB) {}

  /// Override to capture current state to A slot
  void storeStateA() {
    _hasStoredA = true;
  }

  /// Override to capture current state to B slot
  void storeStateB() {
    _hasStoredB = true;
  }

  /// Override to restore state from A slot
  void restoreStateA() {}

  /// Override to restore state from B slot
  void restoreStateB() {}

  /// Override to copy A state to B
  void copyAToB() {
    _hasStoredB = _hasStoredA;
  }

  /// Override to copy B state to A
  void copyBToA() {
    _hasStoredA = _hasStoredB;
  }

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
        _buildABButton('A', !_isStateB, _hasStoredA, () {
          if (_isStateB) toggleAB();
        }, () {
          // Long press: force store current to A
          storeStateA();
          setState(() {});
        }),
        const SizedBox(width: 4),
        _buildABButton('B', _isStateB, _hasStoredB, () {
          if (!_isStateB) toggleAB();
        }, () {
          // Long press: force store current to B
          storeStateB();
          setState(() {});
        }),
        const SizedBox(width: 8),
        // Copy button: copies active state to the other slot
        Tooltip(
          message: _isStateB ? 'Copy B → A' : 'Copy A → B',
          child: GestureDetector(
            onTap: copyCurrentToOther,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: FabFilterDecorations.toggleInactive(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.content_copy,
                    size: 12,
                    color: FabFilterColors.textTertiary,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    _isStateB ? '→A' : '→B',
                    style: const TextStyle(
                      fontSize: 8,
                      color: FabFilterColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildABButton(
    String label,
    bool isActive,
    bool hasStored,
    VoidCallback onTap,
    VoidCallback onLongPress,
  ) {
    return Tooltip(
      message: hasStored
          ? '$label: Stored (long-press to overwrite)'
          : '$label: Empty (long-press to store)',
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          width: 26,
          height: 26,
          decoration: isActive
              ? FabFilterDecorations.toggleActive(widget.accentColor)
              : FabFilterDecorations.toggleInactive(),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: isActive ? widget.accentColor : FabFilterColors.textTertiary,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              // Stored indicator dot
              if (hasStored)
                Positioned(
                  right: 3,
                  top: 3,
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: isActive
                          ? widget.accentColor
                          : FabFilterColors.textTertiary.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
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

  /// Wrap panel content with FabFilter-style bypass overlay.
  /// When bypassed, dims the entire GUI and shows a centered "BYPASSED" label.
  /// Call this in your build() method: `return wrapWithBypassOverlay(yourContent);`
  Widget wrapWithBypassOverlay(Widget child) {
    if (!_bypassed) return child;
    return Stack(
      children: [
        child,
        // Dim overlay
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              color: const Color(0xA0000000),
              alignment: Alignment.center,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xCC1A1A20),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: FabFilterColors.orange, width: 1),
                ),
                child: const Text(
                  'BYPASSED',
                  style: TextStyle(
                    color: FabFilterColors.orange,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
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
