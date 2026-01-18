/// Glass Content Wrapper
///
/// Wraps any widget with Glass styling (backdrop blur, glass tint).
/// Use this to add Glass effects to existing widgets without rewriting them.

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/liquid_glass_theme.dart';
import '../../providers/theme_mode_provider.dart';

/// Conditionally wraps content with Glass styling based on theme mode
class ThemeAwareWrapper extends StatelessWidget {
  final Widget child;

  const ThemeAwareWrapper({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;

    if (isGlassMode) {
      return GlassContentWrapper(child: child);
    }

    return child;
  }
}

/// Wraps content with Glass backdrop blur and subtle tint
class GlassContentWrapper extends StatelessWidget {
  final Widget child;
  final double blurAmount;
  final double tintOpacity;
  final EdgeInsets? padding;

  const GlassContentWrapper({
    super.key,
    required this.child,
    this.blurAmount = LiquidGlassTheme.blurLight,
    this.tintOpacity = 0.05,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: blurAmount,
          sigmaY: blurAmount,
        ),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: tintOpacity + 0.03),
                Colors.white.withValues(alpha: tintOpacity),
                Colors.white.withValues(alpha: tintOpacity - 0.02),
              ],
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Wraps a panel with Glass styling and optional header
class GlassPanelWrapper extends StatelessWidget {
  final String? title;
  final IconData? icon;
  final Widget child;
  final VoidCallback? onClose;
  final List<Widget>? actions;

  const GlassPanelWrapper({
    super.key,
    this.title,
    this.icon,
    required this.child,
    this.onClose,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: LiquidGlassTheme.blurAmount,
          sigmaY: LiquidGlassTheme.blurAmount,
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.1),
                Colors.white.withValues(alpha: 0.05),
              ],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.1),
            ),
          ),
          child: Column(
            children: [
              if (title != null) _buildHeader(),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 14,
              color: LiquidGlassTheme.textSecondary,
            ),
            const SizedBox(width: 8),
          ],
          Text(
            title!.toUpperCase(),
            style: const TextStyle(
              color: LiquidGlassTheme.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
          const Spacer(),
          if (actions != null) ...actions!,
          if (onClose != null)
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              color: LiquidGlassTheme.textTertiary,
              onPressed: onClose,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: 24,
                minHeight: 24,
              ),
            ),
        ],
      ),
    );
  }
}
