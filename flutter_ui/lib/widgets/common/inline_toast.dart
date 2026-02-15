/// Inline Toast Widget
///
/// Compact, non-intrusive notification that appears inline in the header.
/// Replaces SnackBar for audio assignment feedback.
/// Auto-dismisses with fade animation.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import '../../theme/fluxforge_theme.dart';

/// Toast severity determines accent color and icon.
enum ToastType { success, info, warning, error }

/// Data for a single toast notification.
class ToastData {
  final String message;
  final ToastType type;
  final IconData? icon;

  const ToastData({required this.message, this.type = ToastType.success, this.icon});

  Color get color => switch (type) {
    ToastType.success => FluxForgeTheme.accentGreen,
    ToastType.info => FluxForgeTheme.accentCyan,
    ToastType.warning => FluxForgeTheme.accentOrange,
    ToastType.error => FluxForgeTheme.accentRed,
  };

  IconData get effectiveIcon => icon ?? switch (type) {
    ToastType.success => Icons.check_circle_outline,
    ToastType.info => Icons.info_outline,
    ToastType.warning => Icons.warning_amber_rounded,
    ToastType.error => Icons.error_outline,
  };
}

/// Mixin that adds toast capability to any StatefulWidget.
///
/// Usage:
/// ```dart
/// class _MyState extends State<MyWidget> with InlineToastMixin {
///   void doSomething() {
///     showToast('Done!');
///   }
///
///   @override
///   Widget build(BuildContext context) {
///     return Row(children: [
///       // ... your widgets ...
///       buildToastWidget(), // Place in header row
///     ]);
///   }
/// }
/// ```
mixin InlineToastMixin<T extends StatefulWidget> on State<T>, TickerProviderStateMixin<T> {
  ToastData? _toastData;
  Timer? _toastTimer;
  late final AnimationController _toastAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  );
  late final Animation<double> _toastOpacity = CurvedAnimation(
    parent: _toastAnim,
    curve: Curves.easeOut,
    reverseCurve: Curves.easeIn,
  );

  void showToast(String message, {ToastType type = ToastType.success, IconData? icon, int durationMs = 2000}) {
    _toastTimer?.cancel();
    setState(() => _toastData = ToastData(message: message, type: type, icon: icon));
    _toastAnim.forward(from: 0);
    _toastTimer = Timer(Duration(milliseconds: durationMs), () {
      _toastAnim.reverse().then((_) {
        if (mounted) setState(() => _toastData = null);
      });
    });
  }

  void disposeToast() {
    _toastTimer?.cancel();
    _toastAnim.dispose();
  }

  /// Build the toast widget — place this in your header Row.
  Widget buildToastWidget() {
    if (_toastData == null) return const SizedBox.shrink();
    final d = _toastData!;
    return FadeTransition(
      opacity: _toastOpacity,
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        constraints: const BoxConstraints(maxWidth: 360),
        decoration: BoxDecoration(
          color: d.color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: d.color.withOpacity(0.3), width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(d.effectiveIcon, color: d.color, size: 13),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                d.message,
                style: TextStyle(color: d.color, fontSize: 10, fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
