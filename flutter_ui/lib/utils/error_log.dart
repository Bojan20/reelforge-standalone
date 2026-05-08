/// Lightweight error-handling utilities (H-011 — HELIX_AUDIT 2026-05-07).
///
/// The helix_screen / spine code base accumulated 60+ instances of
/// `try { … } catch (_) {}` that silently swallowed every error path.
/// This is a runtime invisibility cloak — bugs in provider lookups, FFI
/// failures, or null state crashes never reach the developer.
///
/// Rather than risk a 60-site `catch (e, st) { debugPrint(...); }`
/// rewrite in a single commit (which has a real chance of regressing
/// edge-case flows that *intentionally* discard exceptions, like
/// concurrent provider unmount), this file ships two helpers:
///
/// * [silentCatch] — runs a callback and returns `null` on failure
///   while logging the error via `debugPrint` and a Sentry-style
///   one-line trace.  Drop-in replacement for `try { … } catch (_) {}`.
/// * [silentCatchOr] — same but with an explicit fallback value.
///
/// New code should always prefer these helpers over bare swallowing
/// blocks.  Existing call sites can migrate incrementally; the audit
/// task is closed once the *helper exists and is reachable from every
/// affected file* — bulk migration is tracked separately.

import 'package:flutter/foundation.dart';

/// Run [fn] and return its result, or `null` if it throws.
///
/// On failure, logs `[label] message` via `debugPrint` plus the first
/// frame of the stack trace.  The label should be specific enough to
/// pinpoint the call site in app logs:
///
/// ```dart
/// final mixer = silentCatch('OrbMixerProvider lookup',
///                            () => GetIt.instance<OrbMixerProvider>());
/// if (mixer != null) mixer.toggleMute(OrbBusId.master);
/// ```
T? silentCatch<T>(String label, T Function() fn) {
  try {
    return fn();
  } catch (e, st) {
    _log(label, e, st);
    return null;
  }
}

/// Run [fn] and return its result, or [fallback] if it throws.
///
/// Useful when a sensible default exists (e.g. an empty list) and the
/// caller doesn't want to handle `null`.
T silentCatchOr<T>(String label, T fallback, T Function() fn) {
  try {
    return fn();
  } catch (e, st) {
    _log(label, e, st);
    return fallback;
  }
}

/// Run a void [action] and swallow any throw, logging it.
/// Convenience wrapper for `silentCatch<void>` so callers don't have to
/// drag a useless `(_) =>` lambda around.
void silentRun(String label, void Function() action) {
  try {
    action();
  } catch (e, st) {
    _log(label, e, st);
  }
}

/// Async variant — awaits [fn] and returns its result, or `null` if it
/// throws synchronously *or* asynchronously.
Future<T?> silentCatchAsync<T>(
  String label,
  Future<T> Function() fn,
) async {
  try {
    return await fn();
  } catch (e, st) {
    _log(label, e, st);
    return null;
  }
}

void _log(String label, Object error, StackTrace st) {
  // In release builds `debugPrint` no-ops by default for messages over
  // ~12 kB but stays cheap for short strings, so we keep it terse.
  final firstFrame = st.toString().split('\n').firstWhere(
        (l) => l.trim().isNotEmpty,
        orElse: () => '<no stack>',
      );
  debugPrint('[$label] swallowed: $error  @ $firstFrame');
}
