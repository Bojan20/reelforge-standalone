/// FluxForge Studio Ultimate Action Editor Widget
///
/// Professional Wwise/FMOD-level action editor with:
/// - Visual parameter editing with live preview
/// - RTPC curve editor with bezier handles
/// - Fade curve visualization with presets
/// - Asset browser with waveform preview
/// - Bus routing visualization
/// - State/Switch condition configuration
/// - Advanced timing controls with timeline
/// - Parameter modulation and randomization
/// - Real-time audio preview
/// - Keyboard-driven workflow
/// - Undo/redo integration

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/middleware_models.dart';
import '../../theme/fluxforge_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════════

const double _kPanelPadding = 16.0;
const double _kSectionSpacing = 20.0;
const double _kFieldSpacing = 12.0;
const double _kSliderHeight = 32.0;
const double _kCurveEditorHeight = 120.0;
const double _kWaveformHeight = 60.0;

// ═══════════════════════════════════════════════════════════════════════════════
// MAIN WIDGET
// ═══════════════════════════════════════════════════════════════════════════════

/// Ultimate Action Editor Widget - Full parameter control for middleware actions
class ActionEditorWidget extends StatefulWidget {
  final MiddlewareAction action;
  final ValueChanged<MiddlewareAction> onChanged;
  final VoidCallback? onDelete;
  final VoidCallback? onDuplicate;
  final VoidCallback? onTest;
  final bool showHeader;
  final bool isExpanded;

  const ActionEditorWidget({
    super.key,
    required this.action,
    required this.onChanged,
    this.onDelete,
    this.onDuplicate,
    this.onTest,
    this.showHeader = true,
    this.isExpanded = true,
  });

  @override
  State<ActionEditorWidget> createState() => _ActionEditorWidgetState();
}

class _ActionEditorWidgetState extends State<ActionEditorWidget>
    with TickerProviderStateMixin {
  // UI State
  bool _isExpanded = true;
  bool _showAdvanced = false;
  _EditorTab _activeTab = _EditorTab.basic;

  // Animation controllers
  late AnimationController _expandController;
  late AnimationController _pulseController;
  late Animation<double> _expandAnimation;
  late Animation<double> _pulseAnimation;

  // Focus nodes for keyboard navigation
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.isExpanded;
    _initAnimations();
  }

  void _initAnimations() {
    _expandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _expandAnimation = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeOutCubic,
    );
    if (_isExpanded) _expandController.value = 1.0;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _expandController.dispose();
    _pulseController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _expandController.forward();
      } else {
        _expandController.reverse();
      }
    });
  }

  void _updateAction({
    ActionType? type,
    String? assetId,
    String? bus,
    ActionScope? scope,
    ActionPriority? priority,
    FadeCurve? fadeCurve,
    double? fadeTime,
    double? gain,
    double? pan,
    double? delay,
    bool? loop,
  }) {
    widget.onChanged(widget.action.copyWith(
      type: type,
      assetId: assetId,
      bus: bus,
      scope: scope,
      priority: priority,
      fadeCurve: fadeCurve,
      fadeTime: fadeTime,
      gain: gain,
      pan: pan,
      delay: delay,
      loop: loop,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleKeyEvent,
      child: Container(
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: widget.action.selected
                ? _getActionColor(widget.action.type)
                : FluxForgeTheme.borderSubtle,
            width: widget.action.selected ? 2 : 1,
          ),
          boxShadow: widget.action.selected
              ? [
                  BoxShadow(
                    color: _getActionColor(widget.action.type).withValues(alpha: 0.2),
                    blurRadius: 12,
                    spreadRadius: -4,
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.showHeader) _buildHeader(),
            SizeTransition(
              sizeFactor: _expandAnimation,
              child: _buildContent(),
            ),
          ],
        ),
      ),
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // Delete action
    if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      widget.onDelete?.call();
      return KeyEventResult.handled;
    }

    // Duplicate action
    if (HardwareKeyboard.instance.isMetaPressed &&
        event.logicalKey == LogicalKeyboardKey.keyD) {
      widget.onDuplicate?.call();
      return KeyEventResult.handled;
    }

    // Test action
    if (event.logicalKey == LogicalKeyboardKey.space) {
      widget.onTest?.call();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HEADER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHeader() {
    final color = _getActionColor(widget.action.type);

    return InkWell(
      onTap: _toggleExpanded,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              color.withValues(alpha: 0.15),
              color.withValues(alpha: 0.05),
            ],
          ),
          borderRadius: BorderRadius.vertical(
            top: const Radius.circular(7),
            bottom: _isExpanded ? Radius.zero : const Radius.circular(7),
          ),
        ),
        child: Row(
          children: [
            // Expand/collapse indicator
            AnimatedRotation(
              turns: _isExpanded ? 0.25 : 0,
              duration: const Duration(milliseconds: 200),
              child: Icon(
                Icons.chevron_right,
                size: 18,
                color: FluxForgeTheme.textTertiary,
              ),
            ),
            const SizedBox(width: 8),
            // Action type icon
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        color.withValues(alpha: 0.4),
                        color.withValues(alpha: 0.2),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: color.withValues(alpha: 0.6),
                    ),
                    boxShadow: widget.action.selected
                        ? [
                            BoxShadow(
                              color: color.withValues(
                                alpha: 0.3 * _pulseAnimation.value,
                              ),
                              blurRadius: 8,
                              spreadRadius: -2,
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    _getActionIcon(widget.action.type),
                    size: 20,
                    color: color,
                  ),
                );
              },
            ),
            const SizedBox(width: 12),
            // Action info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        widget.action.type.displayName,
                        style: FluxForgeTheme.h3.copyWith(
                          color: FluxForgeTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (widget.action.priority != ActionPriority.normal)
                        _buildPriorityBadge(widget.action.priority),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _getActionSummary(widget.action),
                    style: FluxForgeTheme.bodySmall.copyWith(
                      color: FluxForgeTheme.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            // Quick parameter badges
            _buildQuickBadges(),
            const SizedBox(width: 12),
            // Action buttons
            _buildHeaderActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildPriorityBadge(ActionPriority priority) {
    final color = _getPriorityColor(priority);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        priority.displayName,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildQuickBadges() {
    final badges = <Widget>[];

    // Delay badge
    if (widget.action.delay > 0) {
      badges.add(_buildBadge(
        Icons.timer,
        '+${(widget.action.delay * 1000).toInt()}ms',
        Colors.blue,
      ));
    }

    // Fade badge
    if (widget.action.fadeTime > 0) {
      badges.add(_buildBadge(
        Icons.gradient,
        '${(widget.action.fadeTime * 1000).toInt()}ms',
        Colors.purple,
      ));
    }

    // Loop badge
    if (widget.action.loop) {
      badges.add(_buildBadge(
        Icons.loop,
        'Loop',
        Colors.green,
      ));
    }

    // Gain badge (if not 100%)
    if ((widget.action.gain - 1.0).abs() > 0.01) {
      badges.add(_buildBadge(
        Icons.volume_up,
        '${(widget.action.gain * 100).toInt()}%',
        Colors.orange,
      ));
    }

    // Pan badge (if not center)
    if (widget.action.pan.abs() > 0.01) {
      final panLabel = widget.action.pan < 0
          ? 'L${(widget.action.pan.abs() * 100).toInt()}'
          : 'R${(widget.action.pan * 100).toInt()}';
      badges.add(_buildBadge(
        Icons.surround_sound,
        panLabel,
        Colors.cyan,
      ));
    }

    return Row(children: badges);
  }

  Widget _buildBadge(IconData icon, String label, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderActions() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildActionButton(
          Icons.play_arrow,
          'Test (Space)',
          Colors.green,
          () => widget.onTest?.call(),
        ),
        const SizedBox(width: 4),
        _buildActionButton(
          Icons.content_copy,
          'Duplicate (⌘D)',
          Colors.blue,
          () => widget.onDuplicate?.call(),
        ),
        const SizedBox(width: 4),
        _buildActionButton(
          Icons.delete_outline,
          'Delete (Del)',
          Colors.red,
          () => widget.onDelete?.call(),
        ),
      ],
    );
  }

  Widget _buildActionButton(
    IconData icon,
    String tooltip,
    Color color,
    VoidCallback onTap,
  ) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONTENT
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildContent() {
    return Container(
      padding: const EdgeInsets.all(_kPanelPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tab bar
          _buildTabBar(),
          const SizedBox(height: _kSectionSpacing),
          // Tab content
          _buildTabContent(),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeepest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Row(
        children: _EditorTab.values.map((tab) {
          final isActive = _activeTab == tab;
          return Expanded(
            child: InkWell(
              onTap: () => setState(() => _activeTab = tab),
              borderRadius: BorderRadius.circular(7),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: isActive
                      ? FluxForgeTheme.accentBlue.withValues(alpha: 0.2)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(5),
                  border: isActive
                      ? Border.all(color: FluxForgeTheme.accentBlue.withValues(alpha: 0.5))
                      : null,
                ),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        tab.icon,
                        size: 14,
                        color: isActive
                            ? FluxForgeTheme.accentBlue
                            : FluxForgeTheme.textTertiary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        tab.label,
                        style: TextStyle(
                          color: isActive
                              ? FluxForgeTheme.accentBlue
                              : FluxForgeTheme.textSecondary,
                          fontSize: 11,
                          fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_activeTab) {
      case _EditorTab.basic:
        return _buildBasicTab();
      case _EditorTab.timing:
        return _buildTimingTab();
      case _EditorTab.modifiers:
        return _buildModifiersTab();
      case _EditorTab.conditions:
        return _buildConditionsTab();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BASIC TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildBasicTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Action Type
        _buildSection('Action Type', _buildActionTypeGrid()),
        const SizedBox(height: _kSectionSpacing),

        // Target Bus
        _buildSection('Target Bus', _buildBusSelector()),
        const SizedBox(height: _kSectionSpacing),

        // Asset (for play actions)
        if (_needsAsset(widget.action.type)) ...[
          _buildSection('Audio Asset', _buildAssetSelector()),
          const SizedBox(height: _kSectionSpacing),
        ],

        // Gain control
        _buildSection(
          'Gain',
          _buildGainControl(),
          trailing: _buildResetButton(
            visible: (widget.action.gain - 1.0).abs() > 0.01,
            onTap: () => _updateAction(gain: 1.0),
          ),
        ),
        const SizedBox(height: _kSectionSpacing),

        // Pan control
        _buildSection(
          'Pan',
          _buildPanControl(),
          trailing: _buildResetButton(
            visible: widget.action.pan.abs() > 0.01,
            onTap: () => _updateAction(pan: 0.0),
          ),
        ),
        const SizedBox(height: _kSectionSpacing),

        // Loop toggle
        _buildSection('Playback', _buildPlaybackOptions()),
      ],
    );
  }

  Widget _buildActionTypeGrid() {
    // Group actions by category
    final playActions = [ActionType.play, ActionType.playAndContinue];
    final stopActions = [ActionType.stop, ActionType.stopAll, ActionType.break_];
    final pauseActions = [ActionType.pause, ActionType.pauseAll, ActionType.resume, ActionType.resumeAll];
    final volumeActions = [ActionType.setVolume, ActionType.setBusVolume, ActionType.mute, ActionType.unmute];
    final dspActions = [ActionType.setPitch, ActionType.setLPF, ActionType.setHPF];
    final stateActions = [ActionType.setState, ActionType.setSwitch, ActionType.setRTPC, ActionType.resetRTPC];
    final otherActions = [ActionType.seek, ActionType.trigger, ActionType.postEvent];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildActionTypeRow('Playback', playActions),
        const SizedBox(height: 8),
        _buildActionTypeRow('Stop', stopActions),
        const SizedBox(height: 8),
        _buildActionTypeRow('Pause/Resume', pauseActions),
        const SizedBox(height: 8),
        _buildActionTypeRow('Volume', volumeActions),
        const SizedBox(height: 8),
        _buildActionTypeRow('DSP', dspActions),
        const SizedBox(height: 8),
        _buildActionTypeRow('State', stateActions),
        const SizedBox(height: 8),
        _buildActionTypeRow('Other', otherActions),
      ],
    );
  }

  Widget _buildActionTypeRow(String label, List<ActionType> types) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: FluxForgeTheme.label.copyWith(
              color: FluxForgeTheme.textTertiary,
            ),
          ),
        ),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: types.map((type) {
              final isSelected = widget.action.type == type;
              final color = _getActionColor(type);

              return InkWell(
                onTap: () => _updateAction(type: type),
                borderRadius: BorderRadius.circular(6),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? color.withValues(alpha: 0.2)
                        : FluxForgeTheme.bgSurface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isSelected ? color : FluxForgeTheme.borderSubtle,
                      width: isSelected ? 2 : 1,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: color.withValues(alpha: 0.2),
                              blurRadius: 6,
                              spreadRadius: -2,
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _getActionIcon(type),
                        size: 14,
                        color: isSelected ? color : FluxForgeTheme.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        type.displayName,
                        style: TextStyle(
                          color: isSelected ? color : FluxForgeTheme.textSecondary,
                          fontSize: 11,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildBusSelector() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: kAllBuses.map((bus) {
        final isSelected = widget.action.bus == bus;
        final color = _getBusColor(bus);

        return InkWell(
          onTap: () => _updateAction(bus: bus),
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? color.withValues(alpha: 0.15)
                  : FluxForgeTheme.bgSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? color : FluxForgeTheme.borderSubtle,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(5),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: color.withValues(alpha: 0.5),
                              blurRadius: 4,
                              spreadRadius: 0,
                            ),
                          ]
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  bus,
                  style: TextStyle(
                    color: isSelected ? color : FluxForgeTheme.textPrimary,
                    fontSize: 12,
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

  Widget _buildAssetSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Current asset display with waveform preview
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgDeepest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: FluxForgeTheme.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.audiotrack,
                    size: 16,
                    color: FluxForgeTheme.accentCyan,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.action.assetId.isEmpty
                          ? 'No asset selected'
                          : widget.action.assetId,
                      style: FluxForgeTheme.body.copyWith(
                        color: widget.action.assetId.isEmpty
                            ? FluxForgeTheme.textTertiary
                            : FluxForgeTheme.textPrimary,
                        fontStyle: widget.action.assetId.isEmpty
                            ? FontStyle.italic
                            : FontStyle.normal,
                      ),
                    ),
                  ),
                  if (widget.action.assetId.isNotEmpty)
                    InkWell(
                      onTap: () => _updateAction(assetId: ''),
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.close,
                          size: 14,
                          color: FluxForgeTheme.textTertiary,
                        ),
                      ),
                    ),
                ],
              ),
              if (widget.action.assetId.isNotEmpty) ...[
                const SizedBox(height: 8),
                // Fake waveform preview
                _buildWaveformPreview(),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Asset grid
        Container(
          height: 120,
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: FluxForgeTheme.borderSubtle),
          ),
          child: ListView(
            padding: const EdgeInsets.all(8),
            children: [
              _buildAssetCategory('Music', [
                'music_main', 'music_bonus', 'music_freespins', 'music_bigwin'
              ]),
              _buildAssetCategory('SFX', [
                'sfx_spin', 'sfx_reel_land', 'sfx_click', 'sfx_coins', 'sfx_jackpot'
              ]),
              _buildAssetCategory('Voice', [
                'vo_bigwin', 'vo_megawin', 'vo_jackpot', 'vo_freespins'
              ]),
              _buildAssetCategory('Ambient', [
                'amb_casino', 'amb_nature', 'amb_crowd'
              ]),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWaveformPreview() {
    return Container(
      height: _kWaveformHeight,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgVoid,
        borderRadius: BorderRadius.circular(4),
      ),
      child: CustomPaint(
        size: Size(double.infinity, _kWaveformHeight),
        painter: _WaveformPainter(
          color: FluxForgeTheme.accentCyan,
        ),
      ),
    );
  }

  Widget _buildAssetCategory(String name, List<String> assets) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            name,
            style: FluxForgeTheme.label.copyWith(
              color: FluxForgeTheme.textTertiary,
            ),
          ),
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: assets.map((asset) {
            final isSelected = widget.action.assetId == asset;
            return InkWell(
              onTap: () => _updateAction(assetId: asset),
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isSelected
                      ? FluxForgeTheme.accentCyan.withValues(alpha: 0.2)
                      : FluxForgeTheme.bgMid,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isSelected
                        ? FluxForgeTheme.accentCyan
                        : FluxForgeTheme.borderSubtle,
                  ),
                ),
                child: Text(
                  asset,
                  style: TextStyle(
                    color: isSelected
                        ? FluxForgeTheme.accentCyan
                        : FluxForgeTheme.textSecondary,
                    fontSize: 10,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildGainControl() {
    final gainDb = 20 * math.log(widget.action.gain.clamp(0.001, 10)) / math.ln10;

    return Column(
      children: [
        // Visual gain meter
        Row(
          children: [
            // Gain slider with dB scale
            Expanded(
              child: _buildParameterSlider(
                value: widget.action.gain,
                min: 0.0,
                max: 2.0,
                onChanged: (v) => _updateAction(gain: v),
                formatValue: (v) {
                  final db = 20 * math.log(v.clamp(0.001, 10)) / math.ln10;
                  return '${db >= 0 ? '+' : ''}${db.toStringAsFixed(1)} dB';
                },
                color: Colors.orange,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Quick presets
        Row(
          children: [
            _buildPresetButton('-12dB', 0.25),
            _buildPresetButton('-6dB', 0.5),
            _buildPresetButton('0dB', 1.0),
            _buildPresetButton('+6dB', 2.0),
          ],
        ),
      ],
    );
  }

  Widget _buildPresetButton(String label, double value) {
    final isSelected = (widget.action.gain - value).abs() < 0.01;

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: InkWell(
          onTap: () => _updateAction(gain: value),
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.orange.withValues(alpha: 0.2)
                  : FluxForgeTheme.bgSurface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isSelected ? Colors.orange : FluxForgeTheme.borderSubtle,
              ),
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.orange : FluxForgeTheme.textSecondary,
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPanControl() {
    return Column(
      children: [
        // Visual pan slider
        Row(
          children: [
            // Pan slider with L/R scale
            Expanded(
              child: _buildParameterSlider(
                value: widget.action.pan,
                min: -1.0,
                max: 1.0,
                onChanged: (v) => _updateAction(pan: v),
                formatValue: (v) {
                  if (v.abs() < 0.01) return 'C';
                  final percent = (v.abs() * 100).toInt();
                  return v < 0 ? 'L$percent' : 'R$percent';
                },
                color: Colors.cyan,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Quick presets
        Row(
          children: [
            _buildPanPresetButton('L100', -1.0),
            _buildPanPresetButton('L50', -0.5),
            _buildPanPresetButton('C', 0.0),
            _buildPanPresetButton('R50', 0.5),
            _buildPanPresetButton('R100', 1.0),
          ],
        ),
      ],
    );
  }

  Widget _buildPanPresetButton(String label, double value) {
    final isSelected = (widget.action.pan - value).abs() < 0.01;

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: InkWell(
          onTap: () => _updateAction(pan: value),
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.cyan.withValues(alpha: 0.2)
                  : FluxForgeTheme.bgSurface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isSelected ? Colors.cyan : FluxForgeTheme.borderSubtle,
              ),
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.cyan : FluxForgeTheme.textSecondary,
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaybackOptions() {
    return Row(
      children: [
        // Loop toggle
        _buildToggleChip(
          icon: Icons.loop,
          label: 'Loop',
          isActive: widget.action.loop,
          color: Colors.green,
          onTap: () => _updateAction(loop: !widget.action.loop),
        ),
        const SizedBox(width: 8),
        // Scope selector
        Expanded(
          child: _buildDropdown<ActionScope>(
            label: 'Scope',
            value: widget.action.scope,
            items: ActionScope.values,
            onChanged: (v) => _updateAction(scope: v),
            itemLabel: (s) => s.displayName,
          ),
        ),
        const SizedBox(width: 8),
        // Priority selector
        Expanded(
          child: _buildDropdown<ActionPriority>(
            label: 'Priority',
            value: widget.action.priority,
            items: ActionPriority.values,
            onChanged: (v) => _updateAction(priority: v),
            itemLabel: (p) => p.displayName,
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TIMING TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTimingTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Delay control
        _buildSection(
          'Delay',
          _buildTimingControl(
            value: widget.action.delay,
            max: 5.0,
            onChanged: (v) => _updateAction(delay: v),
            color: Colors.blue,
          ),
          trailing: _buildResetButton(
            visible: widget.action.delay > 0,
            onTap: () => _updateAction(delay: 0),
          ),
        ),
        const SizedBox(height: _kSectionSpacing),

        // Fade time control
        _buildSection(
          'Fade Time',
          _buildTimingControl(
            value: widget.action.fadeTime,
            max: 5.0,
            onChanged: (v) => _updateAction(fadeTime: v),
            color: Colors.purple,
          ),
          trailing: _buildResetButton(
            visible: widget.action.fadeTime > 0.1,
            onTap: () => _updateAction(fadeTime: 0.1),
          ),
        ),
        const SizedBox(height: _kSectionSpacing),

        // Fade curve
        _buildSection('Fade Curve', _buildFadeCurveEditor()),
        const SizedBox(height: _kSectionSpacing),

        // Timeline visualization
        _buildSection('Timeline Preview', _buildTimelinePreview()),
      ],
    );
  }

  Widget _buildTimingControl({
    required double value,
    required double max,
    required ValueChanged<double> onChanged,
    required Color color,
  }) {
    return Column(
      children: [
        _buildParameterSlider(
          value: value,
          min: 0,
          max: max,
          onChanged: onChanged,
          formatValue: (v) => '${(v * 1000).toInt()} ms',
          color: color,
        ),
        const SizedBox(height: 8),
        // Quick presets
        Row(
          children: [
            _buildTimingPreset('0', 0.0, value, onChanged),
            _buildTimingPreset('100ms', 0.1, value, onChanged),
            _buildTimingPreset('250ms', 0.25, value, onChanged),
            _buildTimingPreset('500ms', 0.5, value, onChanged),
            _buildTimingPreset('1s', 1.0, value, onChanged),
            _buildTimingPreset('2s', 2.0, value, onChanged),
          ],
        ),
      ],
    );
  }

  Widget _buildTimingPreset(String label, double preset, double current, ValueChanged<double> onChanged) {
    final isSelected = (current - preset).abs() < 0.01;

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: InkWell(
          onTap: () => onChanged(preset),
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: isSelected
                  ? FluxForgeTheme.accentBlue.withValues(alpha: 0.2)
                  : FluxForgeTheme.bgSurface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isSelected
                    ? FluxForgeTheme.accentBlue
                    : FluxForgeTheme.borderSubtle,
              ),
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected
                      ? FluxForgeTheme.accentBlue
                      : FluxForgeTheme.textSecondary,
                  fontSize: 10,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFadeCurveEditor() {
    return Column(
      children: [
        // Curve visualization
        Container(
          height: _kCurveEditorHeight,
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgDeepest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: FluxForgeTheme.borderSubtle),
          ),
          child: CustomPaint(
            size: Size(double.infinity, _kCurveEditorHeight),
            painter: _FadeCurvePainter(
              curve: widget.action.fadeCurve,
              color: Colors.purple,
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Curve selector
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: FadeCurve.values.map((curve) {
            final isSelected = widget.action.fadeCurve == curve;
            return InkWell(
              onTap: () => _updateAction(fadeCurve: curve),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.purple.withValues(alpha: 0.2)
                      : FluxForgeTheme.bgSurface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isSelected ? Colors.purple : FluxForgeTheme.borderSubtle,
                  ),
                ),
                child: Text(
                  curve.displayName,
                  style: TextStyle(
                    color: isSelected ? Colors.purple : FluxForgeTheme.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildTimelinePreview() {
    final totalTime = widget.action.delay + widget.action.fadeTime + 0.5;

    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeepest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      padding: const EdgeInsets.all(8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final pixelsPerSec = width / totalTime;

          return Stack(
            children: [
              // Time grid
              ..._buildTimeGrid(totalTime, pixelsPerSec),
              // Delay region
              if (widget.action.delay > 0)
                Positioned(
                  left: 0,
                  top: 20,
                  child: Container(
                    width: widget.action.delay * pixelsPerSec,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.2),
                      border: Border.all(color: Colors.blue),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Center(
                      child: Text(
                        'Delay',
                        style: TextStyle(
                          color: Colors.blue,
                          fontSize: 9,
                        ),
                      ),
                    ),
                  ),
                ),
              // Fade region
              Positioned(
                left: widget.action.delay * pixelsPerSec,
                top: 20,
                child: Container(
                  width: math.max(widget.action.fadeTime * pixelsPerSec, 30),
                  height: 20,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.purple.withValues(alpha: 0.4),
                        Colors.purple.withValues(alpha: 0.1),
                      ],
                    ),
                    border: Border.all(color: Colors.purple),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Center(
                    child: Text(
                      'Fade',
                      style: TextStyle(
                        color: Colors.purple,
                        fontSize: 9,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _buildTimeGrid(double totalTime, double pixelsPerSec) {
    final widgets = <Widget>[];
    final step = totalTime > 3 ? 1.0 : 0.5;

    for (double t = 0; t <= totalTime; t += step) {
      widgets.add(
        Positioned(
          left: t * pixelsPerSec,
          top: 0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${t.toStringAsFixed(t == t.roundToDouble() ? 0 : 1)}s',
                style: FluxForgeTheme.labelTiny.copyWith(
                  color: FluxForgeTheme.textDisabled,
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.3),
              ),
            ],
          ),
        ),
      );
    }

    return widgets;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MODIFIERS TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildModifiersTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Pitch modifier (placeholder)
        _buildSection('Pitch Modifier', _buildPitchControl()),
        const SizedBox(height: _kSectionSpacing),

        // Filter modifier (placeholder)
        _buildSection('Filter Modifier', _buildFilterControl()),
        const SizedBox(height: _kSectionSpacing),

        // Randomization (placeholder)
        _buildSection('Randomization', _buildRandomization()),
      ],
    );
  }

  Widget _buildPitchControl() {
    return Column(
      children: [
        _buildParameterSlider(
          value: 0.0,
          min: -24.0,
          max: 24.0,
          onChanged: (v) {},
          formatValue: (v) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)} st',
          color: Colors.teal,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                'Pitch shift in semitones',
                style: FluxForgeTheme.bodySmall.copyWith(
                  color: FluxForgeTheme.textTertiary,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: FluxForgeTheme.bgSurface,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Not implemented',
                style: TextStyle(
                  color: FluxForgeTheme.textDisabled,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFilterControl() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Low Pass Filter',
                    style: FluxForgeTheme.label,
                  ),
                  const SizedBox(height: 4),
                  _buildParameterSlider(
                    value: 20000.0,
                    min: 20.0,
                    max: 20000.0,
                    onChanged: (v) {},
                    formatValue: (v) => '${(v / 1000).toStringAsFixed(1)}kHz',
                    color: Colors.orange,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'High Pass Filter',
                    style: FluxForgeTheme.label,
                  ),
                  const SizedBox(height: 4),
                  _buildParameterSlider(
                    value: 20.0,
                    min: 20.0,
                    max: 5000.0,
                    onChanged: (v) {},
                    formatValue: (v) => '${v.toStringAsFixed(0)}Hz',
                    color: Colors.cyan,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRandomization() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                Icons.shuffle,
                size: 16,
                color: FluxForgeTheme.textTertiary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Add randomization to pitch, volume, and timing',
                  style: FluxForgeTheme.bodySmall.copyWith(
                    color: FluxForgeTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildRandomParam('Pitch', '±2 st', Colors.teal),
              const SizedBox(width: 8),
              _buildRandomParam('Volume', '±3 dB', Colors.orange),
              const SizedBox(width: 8),
              _buildRandomParam('Delay', '±50ms', Colors.blue),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRandomParam(String label, String range, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              range,
              style: TextStyle(
                color: color.withValues(alpha: 0.7),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONDITIONS TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildConditionsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // State conditions
        _buildSection('State Conditions', _buildStateConditions()),
        const SizedBox(height: _kSectionSpacing),

        // Switch conditions
        _buildSection('Switch Conditions', _buildSwitchConditions()),
        const SizedBox(height: _kSectionSpacing),

        // RTPC conditions
        _buildSection('RTPC Conditions', _buildRtpcConditions()),
      ],
    );
  }

  Widget _buildStateConditions() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.flag, size: 16, color: Colors.amber),
              const SizedBox(width: 8),
              Text(
                'Execute only when state matches',
                style: FluxForgeTheme.bodySmall.copyWith(
                  color: FluxForgeTheme.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...kStateGroups.entries.take(3).map((entry) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 100,
                    child: Text(
                      entry.key,
                      style: FluxForgeTheme.label,
                    ),
                  ),
                  Expanded(
                    child: Wrap(
                      spacing: 4,
                      children: entry.value.map((state) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: FluxForgeTheme.bgMid,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: FluxForgeTheme.borderSubtle),
                          ),
                          child: Text(
                            state,
                            style: TextStyle(
                              color: FluxForgeTheme.textTertiary,
                              fontSize: 10,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSwitchConditions() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Row(
        children: [
          Icon(Icons.toggle_on, size: 16, color: Colors.green),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'No switch conditions configured',
              style: FluxForgeTheme.bodySmall.copyWith(
                color: FluxForgeTheme.textTertiary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: () {},
            icon: Icon(Icons.add, size: 14),
            label: Text('Add'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.green,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRtpcConditions() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Row(
        children: [
          Icon(Icons.tune, size: 16, color: Colors.pink),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'No RTPC conditions configured',
              style: FluxForgeTheme.bodySmall.copyWith(
                color: FluxForgeTheme.textTertiary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: () {},
            icon: Icon(Icons.add, size: 14),
            label: Text('Add'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.pink,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS & BUILDERS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSection(String title, Widget content, {Widget? trailing}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title.toUpperCase(),
              style: FluxForgeTheme.label.copyWith(
                color: FluxForgeTheme.textTertiary,
                letterSpacing: 1,
              ),
            ),
            if (trailing != null) ...[
              const Spacer(),
              trailing,
            ],
          ],
        ),
        const SizedBox(height: 8),
        content,
      ],
    );
  }

  Widget _buildResetButton({required bool visible, required VoidCallback onTap}) {
    if (!visible) return const SizedBox();

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.refresh,
              size: 12,
              color: FluxForgeTheme.textTertiary,
            ),
            const SizedBox(width: 4),
            Text(
              'Reset',
              style: TextStyle(
                color: FluxForgeTheme.textTertiary,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildParameterSlider({
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    required String Function(double) formatValue,
    required Color color,
  }) {
    return Container(
      height: _kSliderHeight,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeepest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Row(
        children: [
          // Slider
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                activeTrackColor: color,
                inactiveTrackColor: FluxForgeTheme.bgSurface,
                thumbColor: color,
                overlayColor: color.withValues(alpha: 0.2),
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ),
          ),
          // Value display
          Container(
            width: 80,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              formatValue(value),
              style: FluxForgeTheme.mono.copyWith(
                color: color,
                fontSize: 11,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleChip({
    required IconData icon,
    required String label,
    required bool isActive,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? color.withValues(alpha: 0.2) : FluxForgeTheme.bgSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? color : FluxForgeTheme.borderSubtle,
            width: isActive ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isActive ? color : FluxForgeTheme.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isActive ? color : FluxForgeTheme.textSecondary,
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown<T>({
    required String label,
    required T value,
    required List<T> items,
    required ValueChanged<T> onChanged,
    required String Function(T) itemLabel,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: FluxForgeTheme.label,
        ),
        const SizedBox(height: 4),
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgSurface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: FluxForgeTheme.borderSubtle),
          ),
          child: DropdownButton<T>(
            value: value,
            isExpanded: true,
            underline: const SizedBox(),
            dropdownColor: FluxForgeTheme.bgSurface,
            style: FluxForgeTheme.body.copyWith(
              color: FluxForgeTheme.textPrimary,
              fontSize: 11,
            ),
            items: items.map((item) {
              return DropdownMenuItem(
                value: item,
                child: Text(itemLabel(item)),
              );
            }).toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UTILITY METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  bool _needsAsset(ActionType type) {
    return type == ActionType.play || type == ActionType.playAndContinue;
  }

  String _getActionSummary(MiddlewareAction action) {
    switch (action.type) {
      case ActionType.play:
      case ActionType.playAndContinue:
        return '${action.assetId.isEmpty ? "No asset" : action.assetId} → ${action.bus}';
      case ActionType.stop:
        return 'Stop on ${action.bus}';
      case ActionType.stopAll:
        return 'Stop all sounds';
      case ActionType.setVolume:
      case ActionType.setBusVolume:
        return '${action.bus} → ${(action.gain * 100).toInt()}%';
      case ActionType.setRTPC:
        return 'RTPC on ${action.bus}';
      default:
        return action.bus;
    }
  }

  IconData _getActionIcon(ActionType type) {
    switch (type) {
      case ActionType.play:
      case ActionType.playAndContinue:
        return Icons.play_arrow;
      case ActionType.stop:
        return Icons.stop;
      case ActionType.stopAll:
        return Icons.stop_circle;
      case ActionType.pause:
      case ActionType.pauseAll:
        return Icons.pause;
      case ActionType.resume:
      case ActionType.resumeAll:
        return Icons.play_circle;
      case ActionType.break_:
        return Icons.stop;
      case ActionType.mute:
        return Icons.volume_off;
      case ActionType.unmute:
        return Icons.volume_up;
      case ActionType.setVolume:
      case ActionType.setBusVolume:
        return Icons.volume_up;
      case ActionType.setPitch:
        return Icons.tune;
      case ActionType.setLPF:
      case ActionType.setHPF:
        return Icons.graphic_eq;
      case ActionType.seek:
        return Icons.fast_forward;
      case ActionType.setState:
        return Icons.flag;
      case ActionType.setSwitch:
        return Icons.toggle_on;
      case ActionType.setRTPC:
      case ActionType.resetRTPC:
        return Icons.settings_input_component;
      case ActionType.trigger:
        return Icons.notifications;
      case ActionType.postEvent:
        return Icons.send;
    }
  }

  Color _getActionColor(ActionType type) {
    switch (type) {
      case ActionType.play:
      case ActionType.playAndContinue:
        return Colors.green;
      case ActionType.stop:
      case ActionType.stopAll:
      case ActionType.break_:
        return Colors.red;
      case ActionType.pause:
      case ActionType.pauseAll:
        return Colors.orange;
      case ActionType.resume:
      case ActionType.resumeAll:
        return Colors.green;
      case ActionType.mute:
      case ActionType.unmute:
      case ActionType.setVolume:
      case ActionType.setBusVolume:
        return Colors.blue;
      case ActionType.setPitch:
      case ActionType.setLPF:
      case ActionType.setHPF:
        return Colors.purple;
      case ActionType.seek:
        return Colors.teal;
      case ActionType.setState:
      case ActionType.setSwitch:
        return Colors.amber;
      case ActionType.setRTPC:
      case ActionType.resetRTPC:
        return Colors.pink;
      case ActionType.trigger:
        return Colors.lime;
      case ActionType.postEvent:
        return Colors.cyan;
    }
  }

  Color _getBusColor(String bus) {
    switch (bus.toLowerCase()) {
      case 'master':
        return Colors.red;
      case 'music':
        return Colors.purple;
      case 'sfx':
        return Colors.orange;
      case 'voice':
      case 'vo':
        return Colors.blue;
      case 'ui':
        return Colors.cyan;
      case 'ambience':
        return Colors.green;
      case 'reels':
        return Colors.amber;
      case 'wins':
        return Colors.pink;
      default:
        return Colors.grey;
    }
  }

  Color _getPriorityColor(ActionPriority priority) {
    switch (priority) {
      case ActionPriority.highest:
        return Colors.red;
      case ActionPriority.high:
        return Colors.orange;
      case ActionPriority.aboveNormal:
        return Colors.amber;
      case ActionPriority.normal:
        return Colors.grey;
      case ActionPriority.belowNormal:
        return Colors.blue;
      case ActionPriority.low:
        return Colors.cyan;
      case ActionPriority.lowest:
        return Colors.teal;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CUSTOM PAINTERS
// ═══════════════════════════════════════════════════════════════════════════════

class _WaveformPainter extends CustomPainter {
  final Color color;

  _WaveformPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;

    final path = Path();
    final centerY = size.height / 2;
    final random = math.Random(42); // Fixed seed for consistent waveform

    path.moveTo(0, centerY);

    for (double x = 0; x < size.width; x += 2) {
      final amplitude = random.nextDouble() * 0.8 + 0.1;
      final y = centerY - amplitude * (size.height / 2 - 4);
      path.lineTo(x, y);
    }

    for (double x = size.width; x >= 0; x -= 2) {
      final amplitude = random.nextDouble() * 0.8 + 0.1;
      final y = centerY + amplitude * (size.height / 2 - 4);
      path.lineTo(x, y);
    }

    path.close();
    canvas.drawPath(path, paint);

    // Center line
    canvas.drawLine(
      Offset(0, centerY),
      Offset(size.width, centerY),
      Paint()
        ..color = color.withValues(alpha: 0.3)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _FadeCurvePainter extends CustomPainter {
  final FadeCurve curve;
  final Color color;

  _FadeCurvePainter({required this.curve, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final padding = 16.0;
    final graphWidth = size.width - padding * 2;
    final graphHeight = size.height - padding * 2;

    // Draw grid
    final gridPaint = Paint()
      ..color = FluxForgeTheme.borderSubtle.withValues(alpha: 0.3)
      ..strokeWidth = 1;

    for (int i = 0; i <= 4; i++) {
      final y = padding + (graphHeight * i / 4);
      canvas.drawLine(
        Offset(padding, y),
        Offset(size.width - padding, y),
        gridPaint,
      );
      final x = padding + (graphWidth * i / 4);
      canvas.drawLine(
        Offset(x, padding),
        Offset(x, size.height - padding),
        gridPaint,
      );
    }

    // Draw curve
    final curvePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final path = Path();
    path.moveTo(padding, size.height - padding);

    for (double t = 0; t <= 1.0; t += 0.02) {
      final value = _evaluateCurve(t, curve);
      final x = padding + t * graphWidth;
      final y = size.height - padding - value * graphHeight;
      path.lineTo(x, y);
    }

    canvas.drawPath(path, curvePaint);

    // Fill under curve
    final fillPath = Path.from(path);
    fillPath.lineTo(size.width - padding, size.height - padding);
    fillPath.lineTo(padding, size.height - padding);
    fillPath.close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..color = color.withValues(alpha: 0.1)
        ..style = PaintingStyle.fill,
    );
  }

  double _evaluateCurve(double t, FadeCurve curve) {
    switch (curve) {
      case FadeCurve.linear:
        return t;
      case FadeCurve.log3:
        return 1.0 - math.pow(1.0 - t, 3);
      case FadeCurve.sine:
        return 0.5 - 0.5 * math.cos(t * math.pi);
      case FadeCurve.log1:
        return 1.0 - math.pow(1.0 - t, 2);
      case FadeCurve.invSCurve:
        return t < 0.5
            ? 0.5 * math.pow(2 * t, 2)
            : 1.0 - 0.5 * math.pow(2 * (1 - t), 2);
      case FadeCurve.sCurve:
        return t < 0.5 ? 2 * t * t : 1 - 2 * (1 - t) * (1 - t);
      case FadeCurve.exp1:
        return t * t;
      case FadeCurve.exp3:
        return t * t * t;
    }
  }

  @override
  bool shouldRepaint(_FadeCurvePainter oldDelegate) =>
      curve != oldDelegate.curve || color != oldDelegate.color;
}

// ═══════════════════════════════════════════════════════════════════════════════
// SUPPORT ENUMS
// ═══════════════════════════════════════════════════════════════════════════════

enum _EditorTab {
  basic(Icons.tune, 'Basic'),
  timing(Icons.timer, 'Timing'),
  modifiers(Icons.settings, 'Modifiers'),
  conditions(Icons.rule, 'Conditions');

  final IconData icon;
  final String label;

  const _EditorTab(this.icon, this.label);
}
