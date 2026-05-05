/// FLUX_MASTER_TODO 2.1.8 — Slot preview size cycle.
///
/// Four-stage cycle for the SlotLab live preview:
///
///   `off` → (F11) → `full` → (Esc) → `large` → (Esc) → `medium` → (Esc) → `off`
///
/// `large` (80%) and `medium` (50%) are picture-in-picture overlays that
/// float over the live SlotLab UI so the author keeps mixer + lower zone
/// visible while previewing reels. `full` covers the entire screen via
/// `PremiumSlotPreview`. `off` is the no-preview baseline.
///
/// The transition logic is extracted as pure functions so the cycle is
/// unit-testable without pumping the full `SlotLabScreen` widget.
enum SlotPreviewSize {
  /// No preview overlay — baseline SlotLab UI.
  off,

  /// 100% — `PremiumSlotPreview` replaces the screen entirely.
  full,

  /// 80% picture-in-picture — slot_lab visible behind dim backdrop.
  large,

  /// 50% picture-in-picture — slot_lab visible behind dim backdrop.
  medium,
}

/// Pure transition functions for the [SlotPreviewSize] cycle.
///
/// Extracted from `_SlotLabScreenState` so the state machine can be tested
/// in isolation. Calling `setState` and clearing the splash flag remain the
/// caller's responsibility.
extension SlotPreviewSizeTransitions on SlotPreviewSize {
  /// `true` when any preview overlay is visible (large / medium / full).
  bool get isPreviewMode => this != SlotPreviewSize.off;

  /// `true` when the preview is rendered as a picture-in-picture overlay.
  /// (`full` replaces the screen instead of overlaying it.)
  bool get isPictureInPicture =>
      this == SlotPreviewSize.large || this == SlotPreviewSize.medium;

  /// Width / height fraction of the screen for PiP rendering.
  /// Returns `null` for `off` (no overlay) and `full` (no fraction — covers all).
  double? get fractionFactor => switch (this) {
        SlotPreviewSize.large => 0.80,
        SlotPreviewSize.medium => 0.50,
        SlotPreviewSize.full => null,
        SlotPreviewSize.off => null,
      };

  /// Cycle one step down: `full` → `large` → `medium` → `off`.
  /// `off` is idempotent — repeated calls stay at `off`.
  ///
  /// This is the Escape-key / PiP-backdrop-tap behavior.
  SlotPreviewSize cycleDown() => switch (this) {
        SlotPreviewSize.full => SlotPreviewSize.large,
        SlotPreviewSize.large => SlotPreviewSize.medium,
        SlotPreviewSize.medium => SlotPreviewSize.off,
        SlotPreviewSize.off => SlotPreviewSize.off,
      };

  /// Snap to `full` from any state (F11 trigger).
  /// No-op when already at `full` so repeated F11 presses don't re-enter.
  ///
  /// Returns the new size; the caller is responsible for `setState` and
  /// for clearing any one-shot flags (e.g. splash) on transitions where
  /// they would replay incorrectly.
  SlotPreviewSize enterFull() =>
      this == SlotPreviewSize.full ? this : SlotPreviewSize.full;
}
