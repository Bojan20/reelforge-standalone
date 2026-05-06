/// FLUX_MASTER_TODO 3.4.1 / 3.4.3 / 3.4.4 — Live compliance provider.
///
/// 200ms timer poll-uje `rgai_live_snapshot_json()` FFI fn i broadcast-uje
/// novi snapshot kao ChangeNotifier. UI widget-i (Omnibar traffic lights,
/// LDW guard overlay, near-miss tracker) konzumiraju kroz `Consumer` ili
/// `ListenableBuilder`.
///
/// **Lifecycle:**
/// 1. App startup wire u `service_locator.dart` (lazy singleton).
/// 2. `start()` se zove kad SlotLab postane vidljiv (provider ide active).
///    - Lazy `rgai_live_init()` se poziva ako nije već.
///    - `Timer.periodic(200ms)` start.
/// 3. `stop()` na navigation away (cancel timer, čuva poslednji snapshot
///    za UI rebuild bez promene).
/// 4. Audio thread / spin engine nezavisno poziva `rgaiLiveRecordSpin()`
///    iz `SlotLabCoordinator.spin()` ili sličnog flow-a.
///
/// **Thread safety:** Provider je single-threaded (UI thread). FFI poll
/// vraća owned String (Rust → Dart copy preko `toDartString`), parse u
/// model je nakon free-a — bez race-a sa Rust-side memory.

library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../models/live_compliance.dart';
import '../../src/rust/native_ffi.dart';

/// Default poll interval. 200ms = 5 Hz, taman za UI traffic light update
/// bez preteranog FFI overhead-a (svaki poll je <100μs sa atomic loads).
const Duration _kDefaultPollInterval = Duration(milliseconds: 200);

/// Live compliance state holder. Notifies kad snapshot promeni
/// (deep-equality check izbegava trash rebuild-ove na ne-promene).
class LiveComplianceProvider extends ChangeNotifier {
  /// FFI surface — injected radi testabilnosti (u testovima može biti
  /// stub koji vraća kanonske JSON snapshot-ove).
  final NativeFFI _ffi;

  /// Poll interval (overridable za test brzinu).
  final Duration _pollInterval;

  Timer? _pollTimer;
  LiveComplianceSnapshot _snapshot = LiveComplianceSnapshot.empty();
  bool _ffiInitDone = false;

  LiveComplianceProvider({
    NativeFFI? ffi,
    Duration pollInterval = _kDefaultPollInterval,
  })  : _ffi = ffi ?? NativeFFI.instance,
        _pollInterval = pollInterval;

  /// Trenutni snapshot. Default je empty (spinsTotal=0, no jurisdictions).
  LiveComplianceSnapshot get snapshot => _snapshot;

  /// True dok timer poll-uje.
  bool get isRunning => _pollTimer != null;

  /// Start poll loop. Idempotent — drugi `start()` poziv je no-op.
  /// Lazy `rgai_live_init` na prvi start (re-init je no-op posle prve
  /// inicijalizacije, samo reset counters — koje takoreći žele uvek
  /// posle session config).
  void start() {
    if (_pollTimer != null) return;
    if (!_ffiInitDone) {
      _ffi.rgaiLiveInit(); // null = inherit jurisdictions iz rgai_init
      _ffiInitDone = true;
    }
    // Immediate poll pa tek timer — UI vidi tačno stanje na boot bez
    // čekanja prvi 200ms tick.
    _poll();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _poll());
  }

  /// Stop poll loop. Snapshot ostaje (UI prikazuje poslednje stanje
  /// dok provider ne start-uje opet).
  void stop() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Reset live counters bez stop-a. Tipično se zove kad korisnik kreira
  /// novi game model ili prelazi na drugu sesiju.
  void reset() {
    _ffi.rgaiLiveReset();
    _poll(); // sync UI immediately
  }

  /// Record one spin from the spin pipeline. Wraps FFI call sa zero
  /// overhead-om; ne notifikuje listeners (poll tick će pokupiti).
  void recordSpin({
    required double win,
    required double bet,
    required bool nearMiss,
    required double arousal,
  }) {
    _ffi.rgaiLiveRecordSpin(
      win: win,
      bet: bet,
      nearMiss: nearMiss,
      arousal: arousal,
    );
  }

  /// Single poll cycle. Decode FFI JSON, deep-equal vs prethodno, notify
  /// samo na promenu.
  void _poll() {
    final raw = _ffi.rgaiLiveSnapshotJson();
    if (raw == null) return;
    LiveComplianceSnapshot next;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      next = LiveComplianceSnapshot.fromJson(decoded);
    } catch (_) {
      // Defensive — malformed JSON ne sme da ruši poll loop.
      return;
    }
    if (_isSameSnapshot(_snapshot, next)) return;
    _snapshot = next;
    notifyListeners();
  }

  /// Brz deep-equal — proverava polja koja UI gleda. Isključuje internal
  /// optimization "ratio == ratio" precizan float compare jer i 0.0001
  /// promena treba rebuild traffic light-a.
  static bool _isSameSnapshot(
    LiveComplianceSnapshot a,
    LiveComplianceSnapshot b,
  ) {
    if (a.spinsTotal != b.spinsTotal) return false;
    if (a.ldwCount != b.ldwCount) return false;
    if (a.nearMissCount != b.nearMissCount) return false;
    if (a.jurisdictions.length != b.jurisdictions.length) return false;
    for (var i = 0; i < a.jurisdictions.length; i++) {
      final ja = a.jurisdictions[i];
      final jb = b.jurisdictions[i];
      if (ja.code != jb.code) return false;
      if (ja.status != jb.status) return false;
      // worst_metric / worst_utilization se zanemaruju za equality
      // jer ne menjaju traffic light boju (samo tooltip detail).
    }
    return true;
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
