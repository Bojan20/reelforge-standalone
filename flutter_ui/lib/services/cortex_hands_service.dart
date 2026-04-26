/// CortexHandsService — Flutter-native pointer i key injection
///
/// Daje CORTEX-u RUKE bez macOS Accessibility / TCC permisija.
/// Sve se radi kroz Flutter-ov vlastiti input pipeline:
///   - Pointer eventi → WidgetsBinding.handlePointerEvent
///   - Key eventi     → platformDispatcher.onKeyData (Flutter keymap pipeline)
///   - Text input     → clipboard + Cmd+V simulacija
///
/// NEMA osascript. NEMA CGEvent. NEMA TCC.
/// Radi unutar Flutter sandbox-a, uvek, bez dialoga.
///
/// Endpointi (eksponirani kroz CortexEyeServer):
///   POST /hands/tap       {"x":450,"y":300}
///   POST /hands/tap       {"x":450,"y":300,"double":true}
///   POST /hands/swipe     {"from":{"x":100,"y":200},"to":{"x":500,"y":200},"ms":300}
///   POST /hands/scroll    {"x":800,"y":400,"dx":0,"dy":-120}
///   POST /hands/key       {"key":"cmd+k"}
///   POST /hands/input     {"text":"hello world"}
library;

import 'dart:async';
import 'dart:ui' show KeyData, KeyEventType;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

// ═══════════════════════════════════════════════════════════════════════════
// CORTEX HANDS SERVICE
// ═══════════════════════════════════════════════════════════════════════════

class CortexHandsService {
  CortexHandsService._();
  static final instance = CortexHandsService._();

  // Unique pointer ID counter (avoid collision with real input: start visoko)
  int _pointerCounter = 0x7735_0000;
  int get _nextPointer {
    _pointerCounter++;
    if (_pointerCounter > 0x7735_FFFF) _pointerCounter = 0x7735_0000;
    return _pointerCounter;
  }

  // Statistike
  int _tapCount = 0;
  int _keyCount = 0;

  // ─── TAP ────────────────────────────────────────────────────────────────

  /// Simulira klik na Flutter koordinatu (logičke piksele, ne fizičke).
  /// Flutter layout koordinate — iste koje widget system koristi.
  Future<Map<String, dynamic>> tap(
    double x,
    double y, {
    bool isDouble = false,
    Duration tapDuration = const Duration(milliseconds: 80),
  }) async {
    await _singleTap(x, y, tapDuration);
    if (isDouble) {
      await Future.delayed(const Duration(milliseconds: 120));
      await _singleTap(x, y, tapDuration);
    }
    _tapCount++;
    return {
      'ok': true,
      'x': x,
      'y': y,
      'double': isDouble,
      'totalTaps': _tapCount,
    };
  }

  Future<void> _singleTap(double x, double y, Duration duration) async {
    final pointer = _nextPointer;
    final position = Offset(x, y);
    final downTs = Duration(milliseconds: DateTime.now().millisecondsSinceEpoch);

    WidgetsBinding.instance.handlePointerEvent(PointerDownEvent(
      timeStamp: downTs,
      position: position,
      pointer: pointer,
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    ));

    await Future.delayed(duration);

    WidgetsBinding.instance.handlePointerEvent(PointerUpEvent(
      timeStamp: Duration(milliseconds: DateTime.now().millisecondsSinceEpoch),
      position: position,
      pointer: pointer,
      kind: PointerDeviceKind.mouse,
      buttons: 0,
    ));
  }

  // ─── SWIPE ──────────────────────────────────────────────────────────────

  /// Simulira swipe gestu od `from` do `to` u zadatom trajanju.
  /// `steps` = broj međutočaka (više = glađe).
  Future<Map<String, dynamic>> swipe({
    required Offset from,
    required Offset to,
    Duration duration = const Duration(milliseconds: 300),
    int steps = 20,
  }) async {
    final pointer = _nextPointer;
    final stepDelay = Duration(
      microseconds: (duration.inMicroseconds / steps).round().clamp(1, 999999),
    );

    WidgetsBinding.instance.handlePointerEvent(PointerDownEvent(
      timeStamp: Duration(milliseconds: DateTime.now().millisecondsSinceEpoch),
      position: from,
      pointer: pointer,
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    ));

    Offset prev = from;
    for (var i = 1; i <= steps; i++) {
      await Future.delayed(stepDelay);
      final t = i / steps;
      final current = Offset.lerp(from, to, t)!;
      WidgetsBinding.instance.handlePointerEvent(PointerMoveEvent(
        timeStamp: Duration(milliseconds: DateTime.now().millisecondsSinceEpoch),
        position: current,
        delta: current - prev,
        pointer: pointer,
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryMouseButton,
      ));
      prev = current;
    }

    WidgetsBinding.instance.handlePointerEvent(PointerUpEvent(
      timeStamp: Duration(milliseconds: DateTime.now().millisecondsSinceEpoch),
      position: to,
      pointer: pointer,
      kind: PointerDeviceKind.mouse,
      buttons: 0,
    ));

    return {
      'ok': true,
      'from': {'x': from.dx, 'y': from.dy},
      'to': {'x': to.dx, 'y': to.dy},
      'steps': steps,
      'durationMs': duration.inMilliseconds,
    };
  }

  // ─── SCROLL ─────────────────────────────────────────────────────────────

  /// Simulira scroll na poziciji (x, y).
  /// dx/dy su u logičkim pikselima — pozitivni dy = scroll down.
  Future<Map<String, dynamic>> scroll(
    double x,
    double y, {
    double dx = 0,
    double dy = -120,
  }) async {
    final pointer = _nextPointer;
    WidgetsBinding.instance.handlePointerEvent(PointerScrollEvent(
      timeStamp: Duration(milliseconds: DateTime.now().millisecondsSinceEpoch),
      position: Offset(x, y),
      scrollDelta: Offset(dx, dy),
      kind: PointerDeviceKind.mouse,
    ));
    return {'ok': true, 'x': x, 'y': y, 'dx': dx, 'dy': dy};
  }

  // ─── KEY PRESS ──────────────────────────────────────────────────────────

  /// Simulira pritisak tastera.
  /// Podržani formati:
  ///   "cmd+k"   → Meta+K (macOS Command palette)
  ///   "escape"  → Escape
  ///   "enter"   → Enter
  ///   "tab"     → Tab
  ///   "cmd+z"   → Undo
  ///   "cmd+shift+z" → Redo
  ///   "space"   → Space
  ///   "f1"..."f12"
  ///   "up/down/left/right"
  Future<Map<String, dynamic>> pressKey(String combo) async {
    final parsed = _parseCombo(combo);
    if (parsed == null) {
      return {'ok': false, 'error': 'Nepoznata kombinacija: $combo'};
    }

    final logicalKey = parsed.$1;
    final physical = parsed.$2;
    final modifiers = parsed.$3;

    // Inject key DOWN
    await _injectKey(logicalKey, physical, modifiers, isDown: true);
    await Future.delayed(const Duration(milliseconds: 60));
    // Inject key UP
    await _injectKey(logicalKey, physical, modifiers, isDown: false);

    _keyCount++;
    return {
      'ok': true,
      'combo': combo,
      'logicalId': logicalKey.keyId.toRadixString(16),
      'totalKeys': _keyCount,
    };
  }

  Future<void> _injectKey(
    LogicalKeyboardKey logical,
    int physical,
    Set<LogicalKeyboardKey> modifiers,
    {required bool isDown}
  ) async {
    // Modifier keys DOWN (before main key)
    if (isDown) {
      for (final mod in modifiers) {
        final modPhys = _physicalFor(mod);
        WidgetsBinding.instance.platformDispatcher.onKeyData?.call(KeyData(
          type: KeyEventType.down,
          timeStamp: Duration(milliseconds: DateTime.now().millisecondsSinceEpoch),
          logical: mod.keyId,
          physical: modPhys,
          character: null,
          synthesized: true,
        ));
      }
    }

    // Main key event
    WidgetsBinding.instance.platformDispatcher.onKeyData?.call(KeyData(
      type: isDown ? KeyEventType.down : KeyEventType.up,
      timeStamp: Duration(milliseconds: DateTime.now().millisecondsSinceEpoch),
      logical: logical.keyId,
      physical: physical,
      character: isDown && modifiers.isEmpty ? _charFor(logical) : null,
      synthesized: true,
    ));

    // Modifier keys UP (after main key)
    if (!isDown) {
      for (final mod in modifiers) {
        final modPhys = _physicalFor(mod);
        WidgetsBinding.instance.platformDispatcher.onKeyData?.call(KeyData(
          type: KeyEventType.up,
          timeStamp: Duration(milliseconds: DateTime.now().millisecondsSinceEpoch),
          logical: mod.keyId,
          physical: modPhys,
          character: null,
          synthesized: true,
        ));
      }
    }
  }

  // ─── TEXT INPUT ─────────────────────────────────────────────────────────

  /// Upisuje tekst u trenutno fokusiran TextInput.
  /// Strategija: clipboard → Cmd+V (paste).
  /// Bez TCC, bez AX API.
  Future<Map<String, dynamic>> typeText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    await Future.delayed(const Duration(milliseconds: 50));
    await pressKey('cmd+v');
    return {'ok': true, 'text': text, 'length': text.length};
  }

  // ─── Statistike ─────────────────────────────────────────────────────────

  Map<String, dynamic> get stats => {
    'tapCount': _tapCount,
    'keyCount': _keyCount,
  };

  // ─── Key Parsing ─────────────────────────────────────────────────────────

  /// Parsira "cmd+k" → (LogicalKey, physicalHid, modifiers)
  (LogicalKeyboardKey, int, Set<LogicalKeyboardKey>)? _parseCombo(String combo) {
    final parts = combo.toLowerCase().split('+');
    final keyName = parts.last.trim();
    final modNames = parts.sublist(0, parts.length - 1).map((s) => s.trim()).toSet();

    final key = _keyMap[keyName];
    if (key == null) {
      debugPrint('[CortexHands] Nepoznat taster: $keyName (combo: $combo)');
      return null;
    }

    final physical = _physicalHid[keyName] ?? 0;

    final mods = <LogicalKeyboardKey>{};
    for (final mod in modNames) {
      switch (mod) {
        case 'cmd': case 'meta': case 'command':
          mods.add(LogicalKeyboardKey.meta);
        case 'shift':
          mods.add(LogicalKeyboardKey.shift);
        case 'alt': case 'opt': case 'option':
          mods.add(LogicalKeyboardKey.alt);
        case 'ctrl': case 'control':
          mods.add(LogicalKeyboardKey.control);
      }
    }

    return (key, physical, mods);
  }

  // Modifier → fizički HID kod
  int _physicalFor(LogicalKeyboardKey mod) {
    if (mod == LogicalKeyboardKey.meta)    return 0x000700E3; // Left GUI
    if (mod == LogicalKeyboardKey.shift)   return 0x000700E1; // Left Shift
    if (mod == LogicalKeyboardKey.alt)     return 0x000700E2; // Left Alt
    if (mod == LogicalKeyboardKey.control) return 0x000700E0; // Left Ctrl
    return 0;
  }

  // Key → karakter (za simple keys bez modifajera)
  String? _charFor(LogicalKeyboardKey key) => _charMap[key];

  // ─── Key Maps (USB HID Usage Table) ─────────────────────────────────────

  static const Map<String, LogicalKeyboardKey> _keyMap = {
    'a': LogicalKeyboardKey.keyA, 'b': LogicalKeyboardKey.keyB,
    'c': LogicalKeyboardKey.keyC, 'd': LogicalKeyboardKey.keyD,
    'e': LogicalKeyboardKey.keyE, 'f': LogicalKeyboardKey.keyF,
    'g': LogicalKeyboardKey.keyG, 'h': LogicalKeyboardKey.keyH,
    'i': LogicalKeyboardKey.keyI, 'j': LogicalKeyboardKey.keyJ,
    'k': LogicalKeyboardKey.keyK, 'l': LogicalKeyboardKey.keyL,
    'm': LogicalKeyboardKey.keyM, 'n': LogicalKeyboardKey.keyN,
    'o': LogicalKeyboardKey.keyO, 'p': LogicalKeyboardKey.keyP,
    'q': LogicalKeyboardKey.keyQ, 'r': LogicalKeyboardKey.keyR,
    's': LogicalKeyboardKey.keyS, 't': LogicalKeyboardKey.keyT,
    'u': LogicalKeyboardKey.keyU, 'v': LogicalKeyboardKey.keyV,
    'w': LogicalKeyboardKey.keyW, 'x': LogicalKeyboardKey.keyX,
    'y': LogicalKeyboardKey.keyY, 'z': LogicalKeyboardKey.keyZ,
    '0': LogicalKeyboardKey.digit0, '1': LogicalKeyboardKey.digit1,
    '2': LogicalKeyboardKey.digit2, '3': LogicalKeyboardKey.digit3,
    '4': LogicalKeyboardKey.digit4, '5': LogicalKeyboardKey.digit5,
    '6': LogicalKeyboardKey.digit6, '7': LogicalKeyboardKey.digit7,
    '8': LogicalKeyboardKey.digit8, '9': LogicalKeyboardKey.digit9,
    'escape': LogicalKeyboardKey.escape,
    'enter': LogicalKeyboardKey.enter,
    'return': LogicalKeyboardKey.enter,
    'tab': LogicalKeyboardKey.tab,
    'space': LogicalKeyboardKey.space,
    'backspace': LogicalKeyboardKey.backspace,
    'delete': LogicalKeyboardKey.delete,
    'left': LogicalKeyboardKey.arrowLeft,
    'right': LogicalKeyboardKey.arrowRight,
    'up': LogicalKeyboardKey.arrowUp,
    'down': LogicalKeyboardKey.arrowDown,
    'home': LogicalKeyboardKey.home,
    'end': LogicalKeyboardKey.end,
    'pageup': LogicalKeyboardKey.pageUp,
    'pagedown': LogicalKeyboardKey.pageDown,
    'f1': LogicalKeyboardKey.f1,   'f2': LogicalKeyboardKey.f2,
    'f3': LogicalKeyboardKey.f3,   'f4': LogicalKeyboardKey.f4,
    'f5': LogicalKeyboardKey.f5,   'f6': LogicalKeyboardKey.f6,
    'f7': LogicalKeyboardKey.f7,   'f8': LogicalKeyboardKey.f8,
    'f9': LogicalKeyboardKey.f9,   'f10': LogicalKeyboardKey.f10,
    'f11': LogicalKeyboardKey.f11, 'f12': LogicalKeyboardKey.f12,
    '/': LogicalKeyboardKey.slash, '.': LogicalKeyboardKey.period,
    ',': LogicalKeyboardKey.comma, '-': LogicalKeyboardKey.minus,
    '=': LogicalKeyboardKey.equal,
  };

  // USB HID Usage IDs za svaki taster (https://usb.org/hid)
  static const Map<String, int> _physicalHid = {
    'a': 0x00070004, 'b': 0x00070005, 'c': 0x00070006, 'd': 0x00070007,
    'e': 0x00070008, 'f': 0x00070009, 'g': 0x0007000A, 'h': 0x0007000B,
    'i': 0x0007000C, 'j': 0x0007000D, 'k': 0x0007000E, 'l': 0x0007000F,
    'm': 0x00070010, 'n': 0x00070011, 'o': 0x00070012, 'p': 0x00070013,
    'q': 0x00070014, 'r': 0x00070015, 's': 0x00070016, 't': 0x00070017,
    'u': 0x00070018, 'v': 0x00070019, 'w': 0x0007001A, 'x': 0x0007001B,
    'y': 0x0007001C, 'z': 0x0007001D,
    '1': 0x0007001E, '2': 0x0007001F, '3': 0x00070020, '4': 0x00070021,
    '5': 0x00070022, '6': 0x00070023, '7': 0x00070024, '8': 0x00070025,
    '9': 0x00070026, '0': 0x00070027,
    'enter': 0x00070028, 'escape': 0x00070029, 'backspace': 0x0007002A,
    'tab': 0x0007002B, 'space': 0x0007002C,
    'f1': 0x0007003A, 'f2': 0x0007003B, 'f3': 0x0007003C, 'f4': 0x0007003D,
    'f5': 0x0007003E, 'f6': 0x0007003F, 'f7': 0x00070040, 'f8': 0x00070041,
    'f9': 0x00070042, 'f10': 0x00070043, 'f11': 0x00070044, 'f12': 0x00070045,
    'right': 0x0007004F, 'left': 0x00070050, 'down': 0x00070051, 'up': 0x00070052,
    'pageup': 0x0007004B, 'pagedown': 0x0007004E,
    'home': 0x0007004A, 'end': 0x0007004D,
    'delete': 0x0007004C,
    '-': 0x0007002D, '=': 0x0007002E, '/': 0x00070038,
    '.': 0x00070037, ',': 0x00070036,
  };

  static final Map<LogicalKeyboardKey, String> _charMap = {
    LogicalKeyboardKey.keyA: 'a', LogicalKeyboardKey.keyB: 'b',
    LogicalKeyboardKey.keyC: 'c', LogicalKeyboardKey.keyD: 'd',
    LogicalKeyboardKey.keyE: 'e', LogicalKeyboardKey.keyF: 'f',
    LogicalKeyboardKey.keyG: 'g', LogicalKeyboardKey.keyH: 'h',
    LogicalKeyboardKey.keyI: 'i', LogicalKeyboardKey.keyJ: 'j',
    LogicalKeyboardKey.keyK: 'k', LogicalKeyboardKey.keyL: 'l',
    LogicalKeyboardKey.keyM: 'm', LogicalKeyboardKey.keyN: 'n',
    LogicalKeyboardKey.keyO: 'o', LogicalKeyboardKey.keyP: 'p',
    LogicalKeyboardKey.keyQ: 'q', LogicalKeyboardKey.keyR: 'r',
    LogicalKeyboardKey.keyS: 's', LogicalKeyboardKey.keyT: 't',
    LogicalKeyboardKey.keyU: 'u', LogicalKeyboardKey.keyV: 'v',
    LogicalKeyboardKey.keyW: 'w', LogicalKeyboardKey.keyX: 'x',
    LogicalKeyboardKey.keyY: 'y', LogicalKeyboardKey.keyZ: 'z',
    LogicalKeyboardKey.digit0: '0', LogicalKeyboardKey.digit1: '1',
    LogicalKeyboardKey.digit2: '2', LogicalKeyboardKey.digit3: '3',
    LogicalKeyboardKey.digit4: '4', LogicalKeyboardKey.digit5: '5',
    LogicalKeyboardKey.digit6: '6', LogicalKeyboardKey.digit7: '7',
    LogicalKeyboardKey.digit8: '8', LogicalKeyboardKey.digit9: '9',
    LogicalKeyboardKey.space: ' ',
  };
}
