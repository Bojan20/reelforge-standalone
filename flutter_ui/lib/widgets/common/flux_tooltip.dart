/// FluxTooltip — centralized tooltip widget for SPRINT 1 SPEC-16.
///
/// Replaces inline `Tooltip(...)` usage across the app with a consistent
/// look: 150ms delay, brand-gold background, optional keyboard shortcut hint
/// rendered as a separate line.
///
/// Usage:
/// ```
/// FluxTooltip(
///   message: 'Audio Assign',
///   shortcutHint: '1',
///   child: IconButton(...),
/// )
/// ```
///
/// The shortcut hint is rendered with a leading `⌘`/`⇧` glyph if it starts
/// with the `Cmd+`/`Shift+` prefix, otherwise it's shown verbatim.
library;

import 'package:flutter/material.dart';
import '../../theme/fluxforge_theme.dart';

class FluxTooltip extends StatelessWidget {
  /// The primary tooltip message.
  final String message;

  /// Optional keyboard shortcut hint, e.g. `Cmd+K`, `Shift+1`, `Space`.
  /// Rendered as a second line in muted text.
  final String? shortcutHint;

  /// The child widget that receives the tooltip on hover/long-press.
  final Widget child;

  /// Show below the child by default, override if needed.
  final bool preferBelow;

  /// Wait duration before showing — uniform 150ms across the app.
  ///
  /// Public so tests and other tooltip surfaces (e.g. a future custom
  /// overlay that doesn't go through `Tooltip`) can pin the same delay
  /// without re-deriving the magic constant.
  static const Duration kWaitDuration = Duration(milliseconds: 150);

  const FluxTooltip({
    super.key,
    required this.message,
    required this.child,
    this.shortcutHint,
    this.preferBelow = true,
  });

  /// Pure shortcut-formatter, exposed as a public static so the
  /// `Cmd+ → ⌘` / `Shift+ → ⇧` mapping is testable without pumping a
  /// widget tree. Order of replacements matters — modifiers that share
  /// a glyph (Alt+ and Option+ both → ⌥) collapse to the same output.
  ///
  /// Mirrors the macOS keyboard symbol set:
  ///   * `Cmd+`     → `⌘`
  ///   * `Ctrl+`    → `⌃`
  ///   * `Shift+`   → `⇧`
  ///   * `Alt+`     → `⌥`
  ///   * `Option+`  → `⌥`
  ///
  /// Anything not matching one of those prefixes passes through verbatim
  /// so callers can write `'⌘K'` or `'Space'` literally and still get
  /// rendered correctly.
  static String formatShortcut(String raw) {
    return raw
        .replaceAll('Cmd+', '⌘')
        .replaceAll('Ctrl+', '⌃')
        .replaceAll('Shift+', '⇧')
        .replaceAll('Alt+', '⌥')
        .replaceAll('Option+', '⌥');
  }

  @override
  Widget build(BuildContext context) {
    final hasHint = shortcutHint != null && shortcutHint!.isNotEmpty;
    return Tooltip(
      richMessage: WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: FluxForgeTheme.textPrimary,
                  letterSpacing: 0.2,
                ),
              ),
              if (hasHint) ...[
                const SizedBox(height: 2),
                Text(
                  formatShortcut(shortcutHint!),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: FluxForgeTheme.brandGold.withValues(alpha: 0.95),
                    fontFamily: 'JetBrainsMono',
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      waitDuration: kWaitDuration,
      preferBelow: preferBelow,
      decoration: BoxDecoration(
        color: const Color(0xF20A0A10),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: FluxForgeTheme.brandGold.withValues(alpha: 0.32),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      child: child,
    );
  }
}
