/// Pure helpers for resolving the PremiumSlotPreview placement rectangle
/// on the HELIX screen.  Extracted from `helix_screen.dart` so the fallback
/// path can be unit-tested without spinning up a full widget tree.
///
/// **Sprint 15 Faza 4.D.3 — Async edge case tests.**
///
/// The live `HelixScreen._resolveSlotPreviewRect()` walks a `GlobalKey` to
/// find the laid-out `RenderBox`.  On first build (before the post-frame
/// callback fires), in headless tests, and after a screen disposal mid-
/// build, that lookup fails and the method must fall back to a deterministic
/// rect computed from `MediaQuery.size` plus three layout constants.  Bugs
/// in that fallback would cause the slot context-lens overlay to draw in
/// the wrong place — but reproducing the bug requires a full widget tree.
///
/// By isolating the math here we get:
///   * cheap unit coverage (no widget pumping)
///   * a single source of truth that both production and tests share
///   * a stable contract (function signature) future refactors can rely on
library;

import 'dart:ui';

/// Compute the fallback rect for `PremiumSlotPreview` placement when the
/// GlobalKey-backed RenderBox lookup fails.
///
/// All parameters are pure values — no widget context required.
///
/// * [screenSize] — the current `MediaQuery.of(context).size`.
/// * [gridWidthRatio] — fraction of `screenSize.width` to allocate to the
///   slot preview (e.g. `0.6` = 60 % of the viewport).
/// * [leftOffsetPx] — horizontal margin from the left edge of the screen.
/// * [vInsetPx] — symmetric top/bottom inset (top == bottom).
///
/// Returns a `Rect.fromLTWH(leftOffsetPx, vInsetPx, gridWidth,
/// screenSize.height - 2 * vInsetPx)`.
///
/// Contract:
///   * Width is `screenSize.width * gridWidthRatio` — clamped at 0 if
///     `gridWidthRatio < 0` would otherwise underflow.
///   * Height is `screenSize.height - 2 * vInsetPx` — also clamped at 0
///     when the inset is so large it would invert the rect.
///   * `gridWidthRatio == 0` or `screenSize.width == 0` yields a 0-width
///     rect at the requested origin (not an invalid rect).
///   * Output is finite even when inputs are finite; NaN/Infinity in
///     either dimension propagates (caller responsibility).
Rect computeSlotRectFallback({
  required Size screenSize,
  required double gridWidthRatio,
  required double leftOffsetPx,
  required double vInsetPx,
}) {
  // Defensive: never let arithmetic produce a negative width/height that
  // Rect.fromLTWH would interpret as an inverted rect.
  final rawWidth = screenSize.width * gridWidthRatio;
  final width = rawWidth.isFinite && rawWidth > 0 ? rawWidth : 0.0;
  final rawHeight = screenSize.height - 2 * vInsetPx;
  final height = rawHeight.isFinite && rawHeight > 0 ? rawHeight : 0.0;
  return Rect.fromLTWH(leftOffsetPx, vInsetPx, width, height);
}
