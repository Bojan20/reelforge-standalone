/// OSC Trigger Service — Maps OSC messages to Custom Events and RTPC
///
/// Features:
/// - Address → Event: OSC address pattern triggers custom event
/// - Address → RTPC: OSC float argument maps to RTPC parameter
/// - UDP listener in Rust background thread (zero Dart thread impact)
/// - Polling-based: Timer polls Rust OSC buffer every 10ms
///
/// Example OSC messages:
/// /slot/reel_stop           → triggers "REEL_STOP" event
/// /rtpc/anticipation 0.8    → sets RTPC "anticipation" to 0.8
/// /trigger/custom_win 1.0   → triggers custom event with float param

import 'dart:async';
import 'dart:ffi';
import 'package:flutter/foundation.dart';
import 'package:ffi/ffi.dart';

import '../providers/subsystems/rtpc_system_provider.dart';
import 'server_audio_bridge.dart' show EventRegistryLocator;

/// OSC address → event mapping
class OscEventMapping {
  final String address;   // e.g., "/slot/reel_stop"
  final String eventId;   // e.g., "REEL_STOP" or "custom_my_sound"

  const OscEventMapping({required this.address, required this.eventId});

  Map<String, dynamic> toJson() => {'address': address, 'eventId': eventId};
  factory OscEventMapping.fromJson(Map<String, dynamic> json) => OscEventMapping(
    address: json['address'] as String? ?? '',
    eventId: json['eventId'] as String? ?? '',
  );
}

/// OSC address → RTPC mapping
class OscRtpcMapping {
  final String address;   // e.g., "/rtpc/anticipation"
  final int rtpcId;
  final double minValue;
  final double maxValue;

  const OscRtpcMapping({
    required this.address,
    required this.rtpcId,
    this.minValue = 0.0,
    this.maxValue = 1.0,
  });

  Map<String, dynamic> toJson() => {
    'address': address, 'rtpcId': rtpcId,
    'minValue': minValue, 'maxValue': maxValue,
  };
  factory OscRtpcMapping.fromJson(Map<String, dynamic> json) => OscRtpcMapping(
    address: json['address'] as String? ?? '',
    rtpcId: json['rtpcId'] as int? ?? 0,
    minValue: (json['minValue'] as num?)?.toDouble() ?? 0.0,
    maxValue: (json['maxValue'] as num?)?.toDouble() ?? 1.0,
  );
}

/// OSC Trigger Service — singleton
class OscTriggerService with ChangeNotifier {
  OscTriggerService._();
  static final instance = OscTriggerService._();

  Timer? _pollTimer;
  bool _serverRunning = false;
  int _port = 8000;

  final List<OscEventMapping> _eventMappings = [];
  final List<OscRtpcMapping> _rtpcMappings = [];

  RtpcSystemProvider? _rtpcProvider;

  // FFI
  static DynamicLibrary? _lib;
  static DynamicLibrary _loadLib() {
    _lib ??= DynamicLibrary.process();
    return _lib!;
  }
  static final _oscStart = _loadLib().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('osc_start');
  static final _oscStop = _loadLib().lookupFunction<
      Void Function(), void Function()>('osc_stop');
  static final _oscIsRunning = _loadLib().lookupFunction<
      Int32 Function(), int Function()>('osc_is_running');
  static final _oscPollMessages = _loadLib().lookupFunction<
      Uint32 Function(Pointer<Pointer<Utf8>>, Pointer<Pointer<Utf8>>, Pointer<Float>, Pointer<Int32>, Uint32),
      int Function(Pointer<Pointer<Utf8>>, Pointer<Pointer<Utf8>>, Pointer<Float>, Pointer<Int32>, int)>('osc_poll_messages');
  static final _freeRustString = _loadLib().lookupFunction<
      Void Function(Pointer<Utf8>), void Function(Pointer<Utf8>)>('free_rust_string');

  // Stats
  int _messageCount = 0;
  int _triggerCount = 0;
  int _rtpcCount = 0;
  String? _lastAddress;

  // Getters
  bool get serverRunning => _serverRunning;
  int get port => _port;
  int get messageCount => _messageCount;
  int get triggerCount => _triggerCount;
  int get rtpcCount => _rtpcCount;
  String? get lastAddress => _lastAddress;
  List<OscEventMapping> get eventMappings => List.unmodifiable(_eventMappings);
  List<OscRtpcMapping> get rtpcMappings => List.unmodifiable(_rtpcMappings);

  /// Initialize
  void init(RtpcSystemProvider rtpcProvider) {
    _rtpcProvider = rtpcProvider;
  }

  /// Start OSC server on port
  bool start({int port = 8000}) {
    if (_serverRunning) return false;
    _port = port;
    final ok = _oscStart(port) == 1;
    if (ok) {
      _serverRunning = true;
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(const Duration(milliseconds: 10), (_) => _poll());
      notifyListeners();
    }
    return ok;
  }

  /// Stop OSC server
  void stop() {
    _oscStop();
    _serverRunning = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    notifyListeners();
  }

  /// Add event mapping
  void addEventMapping(OscEventMapping mapping) {
    _eventMappings.removeWhere((m) => m.address == mapping.address);
    _eventMappings.add(mapping);
    notifyListeners();
  }

  /// Add RTPC mapping
  void addRtpcMapping(OscRtpcMapping mapping) {
    _rtpcMappings.removeWhere((m) => m.address == mapping.address);
    _rtpcMappings.add(mapping);
    notifyListeners();
  }

  void removeEventMapping(String address) {
    _eventMappings.removeWhere((m) => m.address == address);
    notifyListeners();
  }

  void removeRtpcMapping(String address) {
    _rtpcMappings.removeWhere((m) => m.address == address);
    notifyListeners();
  }

  /// Poll OSC messages from Rust
  void _poll() {
    if (!_serverRunning) return;

    // Periodically verify Rust server is still alive (skip initial zero)
    if (_messageCount > 0 && _messageCount % 100 == 0) {
      final rustRunning = _oscIsRunning() == 1;
      if (!rustRunning && _serverRunning) {
        _serverRunning = false;
        _pollTimer?.cancel();
        notifyListeners();
        return;
      }
    }

    const maxEvents = 32;
    final addrs = calloc<Pointer<Utf8>>(maxEvents);
    final strs = calloc<Pointer<Utf8>>(maxEvents);
    final floats = calloc<Float>(maxEvents);
    final ints = calloc<Int32>(maxEvents);

    try {
      final count = _oscPollMessages(addrs, strs, floats, ints, maxEvents);
      for (int i = 0; i < count; i++) {
        final addrPtr = addrs[i];
        final strPtr = strs[i];
        final address = addrPtr.toDartString();
        final stringArg = strPtr == nullptr ? null : strPtr.toDartString();
        final floatArg = floats[i];
        final intArg = ints[i];

        // Free Rust-allocated strings
        _freeRustString(addrPtr);
        if (strPtr != nullptr) _freeRustString(strPtr);

        _messageCount++;
        _lastAddress = address;

        _routeMessage(
          address,
          floatArg.isNaN ? null : floatArg.toDouble(),
          intArg == -2147483648 ? null : intArg,
          stringArg,
        );
      }
      if (count > 0) notifyListeners();
    } finally {
      calloc.free(addrs);
      calloc.free(strs);
      calloc.free(floats);
      calloc.free(ints);
    }
  }

  /// Route an OSC message to event or RTPC
  void _routeMessage(String address, double? floatArg, int? intArg, [String? stringArg]) {
    // Check event mappings
    for (final mapping in _eventMappings) {
      if (mapping.address == address) {
        if (EventRegistryLocator.trigger(mapping.eventId)) {
          _triggerCount++;
        }
        return;
      }
    }

    // Check RTPC mappings
    for (final mapping in _rtpcMappings) {
      if (mapping.address == address && floatArg != null) {
        final value = mapping.minValue + floatArg * (mapping.maxValue - mapping.minValue);
        _rtpcProvider?.setRtpc(mapping.rtpcId, value.clamp(mapping.minValue, mapping.maxValue), interpolationMs: 50);
        _rtpcCount++;
        return;
      }
    }
  }

  /// Serialize
  Map<String, dynamic> toJson() => {
    'port': _port,
    'eventMappings': _eventMappings.map((m) => m.toJson()).toList(),
    'rtpcMappings': _rtpcMappings.map((m) => m.toJson()).toList(),
  };

  void loadFromJson(Map<String, dynamic> json) {
    _port = json['port'] as int? ?? 8000;
    _eventMappings.clear();
    _rtpcMappings.clear();
    final events = json['eventMappings'] as List?;
    if (events != null) {
      _eventMappings.addAll(events.map((e) => OscEventMapping.fromJson(e as Map<String, dynamic>)));
    }
    final rtpcs = json['rtpcMappings'] as List?;
    if (rtpcs != null) {
      _rtpcMappings.addAll(rtpcs.map((r) => OscRtpcMapping.fromJson(r as Map<String, dynamic>)));
    }
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
