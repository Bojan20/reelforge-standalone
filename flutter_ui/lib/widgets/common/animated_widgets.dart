/// ReelForge Animated Widgets
///
/// Professional micro-interactions and animations:
/// - Smooth hover states
/// - Press feedback
/// - Value change animations
/// - Loading indicators
/// - Transitions
/// - Glow effects

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/reelforge_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ANIMATED BUTTON
// ═══════════════════════════════════════════════════════════════════════════

/// Professional animated button with hover, press, and glow effects
class AnimatedButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final Color? color;
  final Color? hoverColor;
  final Color? pressColor;
  final bool enabled;
  final bool showGlow;
  final EdgeInsets padding;
  final BorderRadius? borderRadius;

  const AnimatedButton({
    super.key,
    required this.child,
    this.onPressed,
    this.color,
    this.hoverColor,
    this.pressColor,
    this.enabled = true,
    this.showGlow = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    this.borderRadius,
  });

  @override
  State<AnimatedButton> createState() => _AnimatedButtonState();
}

class _AnimatedButtonState extends State<AnimatedButton>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  bool _isPressed = false;
  late AnimationController _glowController;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  Color get _backgroundColor {
    if (!widget.enabled) return ReelForgeTheme.bgDeepest;
    if (_isPressed) return widget.pressColor ?? ReelForgeTheme.bgElevated;
    if (_isHovered) return widget.hoverColor ?? ReelForgeTheme.bgSurface;
    return widget.color ?? ReelForgeTheme.bgMid;
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          widget.onPressed?.call();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedBuilder(
          animation: _glowController,
          builder: (context, child) {
            return AnimatedContainer(
              duration: ReelForgeTheme.fastDuration,
              curve: ReelForgeTheme.smoothCurve,
              padding: widget.padding,
              decoration: BoxDecoration(
                color: _backgroundColor,
                borderRadius: widget.borderRadius ?? BorderRadius.circular(4),
                border: Border.all(
                  color: _isHovered && widget.enabled
                      ? ReelForgeTheme.accentBlue.withValues(alpha: 0.5)
                      : ReelForgeTheme.borderSubtle,
                  width: 1,
                ),
                boxShadow: widget.showGlow && _isHovered
                    ? [
                        BoxShadow(
                          color: ReelForgeTheme.accentBlue.withValues(
                            alpha: 0.2 + _glowController.value * 0.1,
                          ),
                          blurRadius: 8,
                          spreadRadius: -2,
                        ),
                      ]
                    : null,
              ),
              transform: _isPressed
                  ? (Matrix4.identity()..scale(0.98))
                  : Matrix4.identity(),
              child: AnimatedDefaultTextStyle(
                duration: ReelForgeTheme.fastDuration,
                style: ReelForgeTheme.button.copyWith(
                  color: widget.enabled
                      ? (_isHovered
                          ? ReelForgeTheme.textPrimary
                          : ReelForgeTheme.textSecondary)
                      : ReelForgeTheme.textDisabled,
                ),
                child: child!,
              ),
            );
          },
          child: widget.child,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ANIMATED VALUE DISPLAY
// ═══════════════════════════════════════════════════════════════════════════

/// Smoothly animated numeric value display
class AnimatedValue extends StatelessWidget {
  final double value;
  final String Function(double) formatter;
  final TextStyle? style;
  final Duration duration;
  final Curve curve;

  const AnimatedValue({
    super.key,
    required this.value,
    required this.formatter,
    this.style,
    this.duration = const Duration(milliseconds: 200),
    this.curve = Curves.easeOutCubic,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: value, end: value),
      duration: duration,
      curve: curve,
      builder: (context, animValue, _) {
        return Text(
          formatter(animValue),
          style: style ?? ReelForgeTheme.mono,
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ANIMATED PROGRESS BAR
// ═══════════════════════════════════════════════════════════════════════════

/// Smooth animated progress bar with glow
class AnimatedProgress extends StatelessWidget {
  final double value; // 0.0 - 1.0
  final Color? color;
  final Color? backgroundColor;
  final double height;
  final BorderRadius? borderRadius;
  final bool showGlow;

  const AnimatedProgress({
    super.key,
    required this.value,
    this.color,
    this.backgroundColor,
    this.height = 4,
    this.borderRadius,
    this.showGlow = true,
  });

  @override
  Widget build(BuildContext context) {
    final progressColor = color ?? ReelForgeTheme.accentBlue;

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: backgroundColor ?? ReelForgeTheme.bgDeepest,
        borderRadius: borderRadius ?? BorderRadius.circular(height / 2),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              // Progress fill
              AnimatedContainer(
                duration: ReelForgeTheme.normalDuration,
                curve: ReelForgeTheme.smoothCurve,
                width: constraints.maxWidth * value.clamp(0, 1),
                decoration: BoxDecoration(
                  color: progressColor,
                  borderRadius: borderRadius ?? BorderRadius.circular(height / 2),
                  boxShadow: showGlow && value > 0
                      ? ReelForgeTheme.glowShadow(progressColor, intensity: 0.4)
                      : null,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ANIMATED ICON BUTTON
// ═══════════════════════════════════════════════════════════════════════════

/// Icon button with rotation, scale, and color animations
class AnimatedIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? color;
  final Color? activeColor;
  final bool isActive;
  final double size;
  final bool rotateOnPress;
  final double rotationAngle;

  const AnimatedIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.color,
    this.activeColor,
    this.isActive = false,
    this.size = 20,
    this.rotateOnPress = false,
    this.rotationAngle = math.pi / 4,
  });

  @override
  State<AnimatedIconButton> createState() => _AnimatedIconButtonState();
}

class _AnimatedIconButtonState extends State<AnimatedIconButton>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  bool _isPressed = false;
  late AnimationController _controller;
  late Animation<double> _rotation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: ReelForgeTheme.normalDuration,
    );
    _rotation = Tween<double>(begin: 0, end: widget.rotationAngle)
        .animate(CurvedAnimation(parent: _controller, curve: ReelForgeTheme.smoothCurve));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(AnimatedIconButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  Color get _iconColor {
    if (widget.isActive) {
      return widget.activeColor ?? ReelForgeTheme.accentBlue;
    }
    if (_isHovered) {
      return ReelForgeTheme.textPrimary;
    }
    return widget.color ?? ReelForgeTheme.textSecondary;
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          widget.onPressed?.call();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return AnimatedContainer(
              duration: ReelForgeTheme.fastDuration,
              transform: Matrix4.identity()
                ..scale(_isPressed ? 0.9 : (_isHovered ? 1.1 : 1.0)),
              transformAlignment: Alignment.center,
              child: Transform.rotate(
                angle: widget.rotateOnPress ? _rotation.value : 0,
                child: AnimatedDefaultTextStyle(
                  duration: ReelForgeTheme.fastDuration,
                  style: TextStyle(color: _iconColor),
                  child: Icon(
                    widget.icon,
                    size: widget.size,
                    color: _iconColor,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PULSE ANIMATION
// ═══════════════════════════════════════════════════════════════════════════

/// Pulsing indicator (like record arm)
class PulseIndicator extends StatefulWidget {
  final Color color;
  final double size;
  final bool isActive;
  final Duration duration;

  const PulseIndicator({
    super.key,
    this.color = ReelForgeTheme.accentRed,
    this.size = 8,
    this.isActive = true,
    this.duration = const Duration(milliseconds: 1000),
  });

  @override
  State<PulseIndicator> createState() => _PulseIndicatorState();
}

class _PulseIndicatorState extends State<PulseIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    if (widget.isActive) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(PulseIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        _controller.repeat(reverse: true);
      } else {
        _controller.stop();
        _controller.value = 0;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final opacity = widget.isActive ? 0.5 + _controller.value * 0.5 : 1.0;
        final scale = widget.isActive ? 1.0 + _controller.value * 0.2 : 1.0;

        return Transform.scale(
          scale: scale,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color.withValues(alpha: opacity),
              boxShadow: widget.isActive
                  ? [
                      BoxShadow(
                        color: widget.color.withValues(alpha: 0.4 * _controller.value),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// LOADING SPINNER
// ═══════════════════════════════════════════════════════════════════════════

/// Professional loading spinner
class LoadingSpinner extends StatefulWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const LoadingSpinner({
    super.key,
    this.size = 24,
    this.color,
    this.strokeWidth = 2,
  });

  @override
  State<LoadingSpinner> createState() => _LoadingSpinnerState();
}

class _LoadingSpinnerState extends State<LoadingSpinner>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Transform.rotate(
          angle: _controller.value * 2 * math.pi,
          child: CustomPaint(
            size: Size(widget.size, widget.size),
            painter: _SpinnerPainter(
              color: widget.color ?? ReelForgeTheme.accentBlue,
              strokeWidth: widget.strokeWidth,
              progress: _controller.value,
            ),
          ),
        );
      },
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double progress;

  _SpinnerPainter({
    required this.color,
    required this.strokeWidth,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Background arc
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = color.withValues(alpha: 0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );

    // Active arc
    final sweepAngle = 1.5; // radians
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweepAngle,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SpinnerPainter oldDelegate) =>
      progress != oldDelegate.progress;
}

// ═══════════════════════════════════════════════════════════════════════════
// ANIMATED EXPANDABLE
// ═══════════════════════════════════════════════════════════════════════════

/// Smooth expand/collapse animation
class AnimatedExpandable extends StatelessWidget {
  final Widget child;
  final bool isExpanded;
  final Duration duration;
  final Curve curve;

  const AnimatedExpandable({
    super.key,
    required this.child,
    required this.isExpanded,
    this.duration = const Duration(milliseconds: 200),
    this.curve = Curves.easeOutCubic,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedCrossFade(
      firstChild: const SizedBox(width: double.infinity),
      secondChild: child,
      crossFadeState: isExpanded
          ? CrossFadeState.showSecond
          : CrossFadeState.showFirst,
      duration: duration,
      firstCurve: curve,
      secondCurve: curve,
      sizeCurve: curve,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ANIMATED TOOLTIP
// ═══════════════════════════════════════════════════════════════════════════

/// Tooltip with smooth fade animation
class AnimatedTooltip extends StatefulWidget {
  final Widget child;
  final String message;
  final String? shortcut;
  final Duration showDelay;

  const AnimatedTooltip({
    super.key,
    required this.child,
    required this.message,
    this.shortcut,
    this.showDelay = const Duration(milliseconds: 500),
  });

  @override
  State<AnimatedTooltip> createState() => _AnimatedTooltipState();
}

class _AnimatedTooltipState extends State<AnimatedTooltip> {
  OverlayEntry? _overlayEntry;
  bool _isShowing = false;

  void _showTooltip() {
    if (_isShowing) return;

    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox;
    final position = renderBox.localToGlobal(Offset.zero);

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: position.dx,
        top: position.dy - 40,
        child: Material(
          color: Colors.transparent,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: ReelForgeTheme.fastDuration,
            builder: (context, opacity, child) {
              return Opacity(
                opacity: opacity,
                child: Transform.translate(
                  offset: Offset(0, 4 * (1 - opacity)),
                  child: child,
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: ReelForgeTheme.bgElevated,
                borderRadius: BorderRadius.circular(4),
                boxShadow: ReelForgeTheme.elevatedShadow,
                border: Border.all(color: ReelForgeTheme.borderSubtle),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.message,
                    style: ReelForgeTheme.bodySmall.copyWith(
                      color: ReelForgeTheme.textPrimary,
                    ),
                  ),
                  if (widget.shortcut != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: ReelForgeTheme.bgDeepest,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: Text(
                        widget.shortcut!,
                        style: ReelForgeTheme.monoSmall.copyWith(
                          color: ReelForgeTheme.textTertiary,
                          fontSize: 9,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(_overlayEntry!);
    _isShowing = true;
  }

  void _hideTooltip() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _isShowing = false;
  }

  @override
  void dispose() {
    _hideTooltip();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        Future.delayed(widget.showDelay, () {
          if (mounted) _showTooltip();
        });
      },
      onExit: (_) => _hideTooltip(),
      child: widget.child,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ANIMATED GLOW CONTAINER
// ═══════════════════════════════════════════════════════════════════════════

/// Container with animated glow effect
class GlowContainer extends StatefulWidget {
  final Widget child;
  final Color glowColor;
  final bool isGlowing;
  final double glowIntensity;
  final Duration duration;

  const GlowContainer({
    super.key,
    required this.child,
    this.glowColor = ReelForgeTheme.accentBlue,
    this.isGlowing = false,
    this.glowIntensity = 0.5,
    this.duration = const Duration(milliseconds: 1500),
  });

  @override
  State<GlowContainer> createState() => _GlowContainerState();
}

class _GlowContainerState extends State<GlowContainer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    if (widget.isGlowing) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(GlowContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isGlowing != oldWidget.isGlowing) {
      if (widget.isGlowing) {
        _controller.repeat(reverse: true);
      } else {
        _controller.stop();
        _controller.value = 0;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            boxShadow: widget.isGlowing
                ? [
                    BoxShadow(
                      color: widget.glowColor.withValues(
                        alpha: widget.glowIntensity * (0.5 + _controller.value * 0.5),
                      ),
                      blurRadius: 12 + _controller.value * 8,
                      spreadRadius: -2,
                    ),
                  ]
                : null,
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
