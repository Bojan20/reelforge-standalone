// FLUX_MASTER_TODO 0.5 A.4 — FluxMotion canonical animation tokens.
//
// Sve animacije u FluxForge UI-u biraju jedan od ova 4 tier-a + jednu od
// 5 spring familija. Direktni `Duration(milliseconds: ...)` + `Curves.*`
// kombinacije razbijaju brand motion identity isto kao raw `Color(0x…)`
// razbija brand color identity (vidi `brand_color_ratchet_test.dart`).
//
// Pristup: tier-based duration tokens (instant/quick/standard/slow) +
// per-purpose spring presets (ui/glass/scrubber/elastic/page) — wrapper
// oko `Curves.*` ali sa imenom koje opisuje **namenu**, ne matematiku.
//
// Ratchet pin: `test/lints/flux_motion_ratchet_test.dart` broji raw
// `Duration(milliseconds:` u `lib/widgets/` + `lib/screens/` van animacije
// kontekst-a — fail-CI ako baseline raste.

import 'package:flutter/animation.dart';

/// Canonical durations za UI animacije. Svaki widget bira jedan od 4 tier-a.
class FluxMotion {
  FluxMotion._();

  // ── Tier 1: INSTANT — feedback < 100ms (button press, hover) ────────────
  /// 80ms — najbrži moguć feedback, na granici percepcije.
  /// Use: button press flash, color flip pri tap-u.
  static const Duration instant = Duration(milliseconds: 80);

  // ── Tier 2: QUICK — micro-interactions 120-200ms ─────────────────────────
  /// 150ms — standard hover/tooltip delay, brand-pinned u SPEC-16.
  /// Use: tooltip enter, hover state border, micro-fade.
  static const Duration quick = Duration(milliseconds: 150);

  /// 200ms — micro-interaction confirmation (chip toggle, badge swap).
  static const Duration brisk = Duration(milliseconds: 200);

  // ── Tier 3: STANDARD — panel/modal transitions 280-360ms ─────────────────
  /// 300ms — most common transition tier (panel slide, modal fade).
  /// Use: dock panel resize, modal show/dismiss, tab switch.
  static const Duration standard = Duration(milliseconds: 300);

  /// 360ms — slightly slower for "entrance" feeling (overlay enter).
  static const Duration entrance = Duration(milliseconds: 360);

  // ── Tier 4: SLOW — dramatic / cinematic 480-800ms ────────────────────────
  /// 500ms — deliberate emphasis (orb expansion, focus zoom).
  static const Duration slow = Duration(milliseconds: 500);

  /// 800ms — cinematic (stage transition, win celebration build).
  /// Use ONLY za emocionalno značajne moment-e; preterana upotreba čini UI sporim.
  static const Duration cinematic = Duration(milliseconds: 800);

  // ════════════════════════════════════════════════════════════════════════
  // SPRING FAMILIES — per-purpose curves
  //
  // Imena opisuju namenu (ne matematiku). Sve su iz `Curves.*`, ali pinning
  // ih ovde kao single source of truth znači da ako brand motion identity
  // treba update, mijenjaš na 1 mestu, ne u 200 widget fajlova.
  // ════════════════════════════════════════════════════════════════════════

  /// UI default — small overshoot, prirodno za buttons/chips/badges.
  /// Pokriva 90% UI tranzicija. Ako nisi siguran koju spring koristiti, koristi ovu.
  static const Curve uiSpring = Curves.easeOutCubic;

  /// Glass overlay — smooth ease-in-out za modals/popovers/glass panels.
  /// Bez overshoot-a (overshoot na transparent surface deluje nervozno).
  static const Curve glassSpring = Curves.easeInOutCubic;

  /// Scrubber / drag follow — linearno, real-time praćenje gesta.
  /// Use: timeline scrubber, drag-to-resize, slider thumb.
  static const Curve scrubberSpring = Curves.linear;

  /// Elastic — bouncy, za "celebration" momente (win pop, jackpot land).
  /// Use SAMO za audio-sync / emocionalne moment-e. Inače deluje detinjasto.
  static const Curve elasticSpring = Curves.elasticOut;

  /// Page transition — decelerate easing, mimics native iOS/macOS feel.
  /// Use: route push/pop, splash → main app entry.
  static const Curve pageSpring = Curves.easeOutQuart;

  // ════════════════════════════════════════════════════════════════════════
  // CONVENIENCE: pre-paired (Duration, Curve) tuples za najčešće combos
  // ════════════════════════════════════════════════════════════════════════

  /// `(quick=150ms, uiSpring)` — najčešći button/chip feedback combo.
  static const FluxAnimSpec uiQuick = FluxAnimSpec(quick, uiSpring);

  /// `(standard=300ms, glassSpring)` — modal/panel/dock transition default.
  static const FluxAnimSpec panelStandard =
      FluxAnimSpec(standard, glassSpring);

  /// `(entrance=360ms, glassSpring)` — overlay show.
  static const FluxAnimSpec overlayEnter =
      FluxAnimSpec(entrance, glassSpring);

  /// `(slow=500ms, elasticSpring)` — celebration/win moment.
  static const FluxAnimSpec celebration =
      FluxAnimSpec(slow, elasticSpring);

  /// `(cinematic=800ms, pageSpring)` — dramatic page-level transition.
  static const FluxAnimSpec dramaticPage =
      FluxAnimSpec(cinematic, pageSpring);
}

/// Pair `(Duration, Curve)` za animacije koje uvek idu zajedno.
/// Use sa `AnimatedContainer(duration: spec.duration, curve: spec.curve, …)`
/// ili `AnimationController(duration: spec.duration, …)` + `CurvedAnimation`.
class FluxAnimSpec {
  const FluxAnimSpec(this.duration, this.curve);
  final Duration duration;
  final Curve curve;
}
