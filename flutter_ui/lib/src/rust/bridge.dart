/// ReelForge Rust Bridge
///
/// FFI bindings for the Rust audio engine.
/// Generated types and API wrappers for Flutter.

library;

import 'dart:ffi';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge.dart';

part 'bridge_generated.dart';

/// Load the native library
DynamicLibrary _loadLibrary() {
  if (Platform.isLinux) {
    return DynamicLibrary.open('librf_bridge.so');
  } else if (Platform.isMacOS) {
    return DynamicLibrary.open('librf_bridge.dylib');
  } else if (Platform.isWindows) {
    return DynamicLibrary.open('rf_bridge.dll');
  }
  throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
}

/// Singleton for the Rust bridge
class RustBridge {
  static RustBridge? _instance;
  static RustBridge get instance => _instance ??= RustBridge._();

  late final DynamicLibrary _lib;
  bool _initialized = false;

  RustBridge._() {
    _lib = _loadLibrary();
  }

  /// Initialize the bridge
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
  }

  /// Check if initialized
  bool get isInitialized => _initialized;
}
