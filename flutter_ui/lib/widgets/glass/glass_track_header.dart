/// Glass Track Header Widget
///
/// Liquid Glass styled track header for timeline:
/// - Frosted glass background with track color tint
/// - M/S/I/R glass buttons
/// - Glass volume slider
/// - Specular highlights and glow effects

import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/liquid_glass_theme.dart';
import '../../providers/theme_mode_provider.dart';
import '../../models/timeline_models.dart';
import '../timeline/track_header_simple.dart';

// ==============================================================================
// THEME-AWARE TRACK HEADER
// ==============================================================================

/// Theme-aware track header that switches between Glass and Classic styles
class ThemeAwareTrackHeader extends StatelessWidget {
  final TimelineTrack track;
  final double width;
  final double height;
  final int trackNumber;
  final bool isSelected;
  final double signalLevel;
  final VoidCallback? onMuteToggle;
  final VoidCallback? onSoloToggle;
  final VoidCallback? onArmToggle;
  final VoidCallback? onInputMonitorToggle;
  final VoidCallback? onClick;
  final ValueChanged<double>? onVolumeChange;
  final ValueChanged<String>? onRename;
  final void Function(Offset position)? onContextMenu;
  final ValueChanged<double>? onHeightChange;

  const ThemeAwareTrackHeader({
    super.key,
    required this.track,
    this.width = 160,
    this.height = 56,
    this.trackNumber = 1,
    this.isSelected = false,
    this.signalLevel = 0.0,
    this.onMuteToggle,
    this.onSoloToggle,
    this.onArmToggle,
    this.onInputMonitorToggle,
    this.onClick,
    this.onVolumeChange,
    this.onRename,
    this.onContextMenu,
    this.onHeightChange,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;

    if (isGlassMode) {
      return GlassTrackHeader(
        track: track,
        width: width,
        height: height,
        trackNumber: trackNumber,
        isSelected: isSelected,
        signalLevel: signalLevel,
        onMuteToggle: onMuteToggle,
        onSoloToggle: onSoloToggle,
        onArmToggle: onArmToggle,
        onInputMonitorToggle: onInputMonitorToggle,
        onClick: onClick,
        onVolumeChange: onVolumeChange,
        onRename: onRename,
        onContextMenu: onContextMenu,
        onHeightChange: onHeightChange,
      );
    }

    // Classic mode - use original TrackHeaderSimple
    return TrackHeaderSimple(
      track: track,
      width: width,
      height: height,
      trackNumber: trackNumber,
      isSelected: isSelected,
      signalLevel: signalLevel,
      onMuteToggle: onMuteToggle,
      onSoloToggle: onSoloToggle,
      onArmToggle: onArmToggle,
      onInputMonitorToggle: onInputMonitorToggle,
      onClick: onClick,
      onVolumeChange: onVolumeChange,
      onRename: onRename,
      onContextMenu: onContextMenu,
      onHeightChange: onHeightChange,
    );
  }
}

// ==============================================================================
// GLASS TRACK HEADER
// ==============================================================================

class GlassTrackHeader extends StatefulWidget {
  final TimelineTrack track;
  final double width;
  final double height;
  final int trackNumber;
  final bool isSelected;
  final double signalLevel;

  // Callbacks
  final VoidCallback? onMuteToggle;
  final VoidCallback? onSoloToggle;
  final VoidCallback? onArmToggle;
  final VoidCallback? onInputMonitorToggle;
  final VoidCallback? onClick;
  final ValueChanged<double>? onVolumeChange;
  final ValueChanged<String>? onRename;
  final void Function(Offset position)? onContextMenu;
  final ValueChanged<double>? onHeightChange;

  const GlassTrackHeader({
    super.key,
    required this.track,
    this.width = 180,
    this.height = 60,
    this.trackNumber = 1,
    this.isSelected = false,
    this.signalLevel = 0.0,
    this.onMuteToggle,
    this.onSoloToggle,
    this.onArmToggle,
    this.onInputMonitorToggle,
    this.onClick,
    this.onVolumeChange,
    this.onRename,
    this.onContextMenu,
    this.onHeightChange,
  });

  @override
  State<GlassTrackHeader> createState() => _GlassTrackHeaderState();
}

class _GlassTrackHeaderState extends State<GlassTrackHeader> {
  bool _isHovered = false;
  bool _isResizing = false;
  bool _isEditingName = false;
  late TextEditingController _nameController;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.track.name);
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(GlassTrackHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.name != widget.track.name && !_isEditingName) {
      _nameController.text = widget.track.name;
    }
  }

  bool get _showVolume => _isHovered || widget.height > 50;

  @override
  Widget build(BuildContext context) {
    final track = widget.track;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onClick,
        onDoubleTap: () => setState(() => _isEditingName = true),
        onSecondaryTapDown: (d) =>
            widget.onContextMenu?.call(d.globalPosition),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: LiquidGlassTheme.blurLight,
              sigmaY: LiquidGlassTheme.blurLight,
            ),
            child: AnimatedContainer(
              duration: LiquidGlassTheme.animFast,
              width: widget.width,
              height: widget.height,
              decoration: BoxDecoration(
                // Glass background with track color tint
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    track.color.withValues(alpha: widget.isSelected ? 0.2 : 0.1),
                    track.color.withValues(alpha: widget.isSelected ? 0.1 : 0.05),
                    Colors.white.withValues(alpha: widget.isSelected ? 0.08 : 0.04),
                  ],
                ),
                border: Border(
                  // Left color accent
                  left: BorderSide(
                    color: track.color.withValues(
                        alpha: widget.isSelected ? 1.0 : 0.6),
                    width: 3,
                  ),
                  // Bottom border
                  bottom: BorderSide(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                  // Right border for selection
                  right: widget.isSelected
                      ? BorderSide(
                          color: track.color.withValues(alpha: 0.4),
                        )
                      : BorderSide.none,
                ),
                // Selection glow
                boxShadow: widget.isSelected
                    ? [
                        BoxShadow(
                          color: track.color.withValues(alpha: 0.2),
                          blurRadius: 12,
                          spreadRadius: -2,
                        ),
                      ]
                    : null,
              ),
              child: Stack(
                children: [
                  // Specular highlight (top edge)
                  Positioned(
                    top: 0,
                    left: 3,
                    right: 0,
                    height: 1,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0.3),
                            Colors.white.withValues(alpha: 0.1),
                            Colors.white.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Main content
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Row 1: Track number + name + buttons
                        SizedBox(
                          height: 22,
                          child: Row(
                            children: [
                              // Track number
                              Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.1),
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    '${widget.trackNumber}',
                                    style: TextStyle(
                                      color: LiquidGlassTheme.textSecondary,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Name
                              Expanded(child: _buildName()),
                              const SizedBox(width: 6),
                              // M/S/I/R buttons
                              _GlassMiniButton(
                                label: 'M',
                                active: track.muted,
                                activeColor: LiquidGlassTheme.accentOrange,
                                onTap: widget.onMuteToggle,
                              ),
                              const SizedBox(width: 3),
                              _GlassMiniButton(
                                label: 'S',
                                active: track.soloed,
                                activeColor: LiquidGlassTheme.accentYellow,
                                onTap: widget.onSoloToggle,
                              ),
                              const SizedBox(width: 3),
                              _GlassMiniButton(
                                label: 'I',
                                active: track.inputMonitor,
                                activeColor: LiquidGlassTheme.accentCyan,
                                onTap: widget.onInputMonitorToggle,
                              ),
                              const SizedBox(width: 3),
                              _GlassRecordButton(
                                armed: track.armed,
                                onTap: widget.onArmToggle,
                              ),
                            ],
                          ),
                        ),
                        // Row 2: Volume (if shown)
                        if (_showVolume && widget.height > 46) ...[
                          const SizedBox(height: 6),
                          _buildVolumeRow(),
                        ],
                      ],
                    ),
                  ),

                  // Meter bar (right edge)
                  Positioned(
                    top: 6,
                    bottom: 6,
                    right: 4,
                    width: 4,
                    child: _GlassMeterBar(level: widget.signalLevel),
                  ),

                  // Resize handle
                  if (_isHovered || _isResizing)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 6,
                      child: _buildResizeHandle(),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildName() {
    if (_isEditingName) {
      return TextField(
        controller: _nameController,
        focusNode: _focusNode,
        autofocus: true,
        style: const TextStyle(
          color: LiquidGlassTheme.textPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        decoration: const InputDecoration(
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
          isDense: true,
        ),
        onSubmitted: (_) => _submitName(),
        onTapOutside: (_) => _submitName(),
      );
    }

    return Text(
      widget.track.name,
      style: TextStyle(
        color: widget.track.muted
            ? LiquidGlassTheme.textTertiary
            : LiquidGlassTheme.textPrimary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      overflow: TextOverflow.ellipsis,
    );
  }

  void _submitName() {
    final trimmed = _nameController.text.trim();
    if (trimmed.isNotEmpty && trimmed != widget.track.name) {
      widget.onRename?.call(trimmed);
    }
    setState(() => _isEditingName = false);
  }

  Widget _buildVolumeRow() {
    return Row(
      children: [
        Text(
          'Vol',
          style: TextStyle(
            fontSize: 9,
            color: LiquidGlassTheme.textTertiary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _GlassVolumeSlider(
            value: widget.track.volume,
            color: widget.track.color,
            onChanged: widget.onVolumeChange,
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 32,
          child: Text(
            _formatDb(widget.track.volume),
            style: TextStyle(
              fontSize: 10,
              fontFamily: 'monospace',
              color: LiquidGlassTheme.textSecondary,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildResizeHandle() {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      child: GestureDetector(
        onVerticalDragStart: (_) => setState(() => _isResizing = true),
        onVerticalDragEnd: (_) => setState(() => _isResizing = false),
        onVerticalDragUpdate: (d) {
          final newHeight = (widget.height + d.delta.dy).clamp(36.0, 160.0);
          widget.onHeightChange?.call(newHeight);
        },
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                widget.track.color
                    .withValues(alpha: _isResizing ? 0.5 : 0.3),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDb(double linear) {
    if (linear <= 0) return '-∞';
    final db = 20 * (math.log(linear) / math.ln10);
    return db <= -60 ? '-∞' : '${db >= 0 ? "+" : ""}${db.toStringAsFixed(0)}';
  }
}

// ==============================================================================
// GLASS MINI BUTTON
// ==============================================================================

class _GlassMiniButton extends StatefulWidget {
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback? onTap;

  const _GlassMiniButton({
    required this.label,
    required this.active,
    required this.activeColor,
    this.onTap,
  });

  @override
  State<_GlassMiniButton> createState() => _GlassMiniButtonState();
}

class _GlassMiniButtonState extends State<_GlassMiniButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final showActive = _pressed ? !widget.active : widget.active;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap?.call();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: LiquidGlassTheme.animFast,
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: showActive
              ? widget.activeColor.withValues(alpha: 0.3)
              : Colors.black.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: showActive
                ? widget.activeColor.withValues(alpha: 0.7)
                : Colors.white.withValues(alpha: 0.15),
          ),
          boxShadow: showActive
              ? [
                  BoxShadow(
                    color: widget.activeColor.withValues(alpha: 0.4),
                    blurRadius: 8,
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: showActive ? widget.activeColor : LiquidGlassTheme.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}

// ==============================================================================
// GLASS RECORD BUTTON
// ==============================================================================

class _GlassRecordButton extends StatefulWidget {
  final bool armed;
  final VoidCallback? onTap;

  const _GlassRecordButton({required this.armed, this.onTap});

  @override
  State<_GlassRecordButton> createState() => _GlassRecordButtonState();
}

class _GlassRecordButtonState extends State<_GlassRecordButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final showArmed = _pressed ? !widget.armed : widget.armed;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap?.call();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: LiquidGlassTheme.animFast,
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: showArmed
              ? LiquidGlassTheme.accentRed.withValues(alpha: 0.3)
              : Colors.black.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: showArmed
                ? LiquidGlassTheme.accentRed.withValues(alpha: 0.7)
                : Colors.white.withValues(alpha: 0.15),
          ),
          boxShadow: showArmed
              ? [
                  BoxShadow(
                    color: LiquidGlassTheme.accentRed.withValues(alpha: 0.5),
                    blurRadius: 10,
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: showArmed
                  ? LiquidGlassTheme.accentRed
                  : LiquidGlassTheme.textTertiary,
              boxShadow: showArmed
                  ? [
                      BoxShadow(
                        color: LiquidGlassTheme.accentRed,
                        blurRadius: 6,
                      ),
                    ]
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

// ==============================================================================
// GLASS VOLUME SLIDER
// ==============================================================================

class _GlassVolumeSlider extends StatelessWidget {
  final double value;
  final Color color;
  final ValueChanged<double>? onChanged;

  static const double _minDb = -60.0;
  static const double _maxDb = 6.0;

  const _GlassVolumeSlider({
    required this.value,
    required this.color,
    this.onChanged,
  });

  double _linearToDb(double linear) {
    if (linear <= 0.0001) return _minDb;
    return 20.0 * math.log(linear) / math.ln10;
  }

  double _dbToLinear(double db) {
    if (db <= _minDb) return 0.0;
    return math.pow(10.0, db / 20.0).toDouble();
  }

  double _dbToNormalized(double db) {
    if (db <= _minDb) return 0.0;
    if (db >= _maxDb) return 1.0;
    return (db - _minDb) / (_maxDb - _minDb);
  }

  double _normalizedToDb(double normalized) {
    if (normalized <= 0.0) return _minDb;
    if (normalized >= 1.0) return _maxDb;
    return _minDb + (normalized * (_maxDb - _minDb));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final db = _linearToDb(value);
        final normalized = _dbToNormalized(db);

        return GestureDetector(
          onHorizontalDragUpdate: (d) {
            if (onChanged != null) {
              final normalizedPos =
                  (d.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
              final newDb = _normalizedToDb(normalizedPos);
              final newLinear = _dbToLinear(newDb).clamp(0.0, 1.5);
              onChanged!(newLinear);
            }
          },
          onDoubleTap: () => onChanged?.call(1.0),
          child: Container(
            height: 10,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            child: Stack(
              children: [
                // Fill
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: FractionallySizedBox(
                    widthFactor: normalized.clamp(0.0, 1.0),
                    alignment: Alignment.centerLeft,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            color.withValues(alpha: 0.6),
                            color,
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.5),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Unity mark (0dB)
                Positioned(
                  left: constraints.maxWidth * _dbToNormalized(0) - 1,
                  top: 0,
                  bottom: 0,
                  width: 2,
                  child: Container(
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ==============================================================================
// GLASS METER BAR
// ==============================================================================

class _GlassMeterBar extends StatelessWidget {
  final double level;

  const _GlassMeterBar({required this.level});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(2),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(1),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: FractionallySizedBox(
            heightFactor: level.clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    LiquidGlassTheme.accentGreen,
                    LiquidGlassTheme.accentYellow,
                    LiquidGlassTheme.accentRed,
                  ],
                  stops: [0.0, 0.7, 1.0],
                ),
                boxShadow: [
                  BoxShadow(
                    color: LiquidGlassTheme.accentGreen.withValues(alpha: 0.5),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
