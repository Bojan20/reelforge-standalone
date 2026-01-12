/// GlassPanel - Glassmorphism container widget
///
/// Creates a frosted glass effect panel with subtle blur and glow.
/// Used throughout the DAW for panels, cards, and floating elements.

import 'dart:ui';
import 'package:flutter/material.dart';
import '../../theme/fluxforge_theme.dart';

class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final Color? backgroundColor;
  final Color? borderColor;
  final double borderWidth;
  final double blurAmount;
  final List<BoxShadow>? shadows;
  final bool showGlow;
  final Color? glowColor;

  const GlassPanel({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = 8,
    this.backgroundColor,
    this.borderColor,
    this.borderWidth = 1,
    this.blurAmount = 10,
    this.shadows,
    this.showGlow = false,
    this.glowColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          if (showGlow)
            BoxShadow(
              color: (glowColor ?? FluxForgeTheme.accentBlue).withValues(alpha: 0.2),
              blurRadius: 20,
              spreadRadius: -5,
            ),
          ...?shadows,
          ...FluxForgeTheme.subtleShadow,
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurAmount, sigmaY: blurAmount),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: backgroundColor ?? FluxForgeTheme.bgSurface.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(
                color: borderColor ?? FluxForgeTheme.borderSubtle,
                width: borderWidth,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Animated glass panel with hover effects
class AnimatedGlassPanel extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final bool selected;
  final Color? selectedColor;

  const AnimatedGlassPanel({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = 8,
    this.onTap,
    this.onDoubleTap,
    this.selected = false,
    this.selectedColor,
  });

  @override
  State<AnimatedGlassPanel> createState() => _AnimatedGlassPanelState();
}

class _AnimatedGlassPanelState extends State<AnimatedGlassPanel>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.selectedColor ?? FluxForgeTheme.accentBlue;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        child: AnimatedContainer(
          duration: FluxForgeTheme.fastDuration,
          curve: FluxForgeTheme.smoothCurve,
          margin: widget.margin,
          transform: Matrix4.identity()
            ..scale(_isPressed ? 0.98 : 1.0),
          decoration: BoxDecoration(
            color: _isHovered
                ? FluxForgeTheme.bgHover.withValues(alpha: 0.9)
                : FluxForgeTheme.bgSurface.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(widget.borderRadius),
            border: Border.all(
              color: widget.selected
                  ? color
                  : _isHovered
                      ? FluxForgeTheme.borderMedium
                      : FluxForgeTheme.borderSubtle,
              width: widget.selected ? 2 : 1,
            ),
            boxShadow: [
              if (widget.selected)
                BoxShadow(
                  color: color.withValues(alpha: 0.3),
                  blurRadius: 12,
                  spreadRadius: -2,
                ),
              ...FluxForgeTheme.subtleShadow,
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Padding(
                padding: widget.padding ?? EdgeInsets.zero,
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
