/// MIDI Trigger Service — Maps MIDI input to Custom Events and RTPC
///
/// Features:
/// - Note → Event: MIDI note triggers custom event (velocity → volume)
/// - CC → RTPC: MIDI CC maps to RTPC parameter
/// - Learn mode: press "Learn" → play MIDI note → auto-bind
/// - Polling-based: Timer polls Rust MIDI input buffer every 5ms
///
/// Uses existing midi_bridge.rs EVENT_BUFFER via FFI polling.

import 'dart:async';
import 'dart:ffi';
import 'package:flutter/foundation.dart';
import 'package:ffi/ffi.dart';

import '../providers/subsystems/rtpc_system_provider.dart';
import 'server_audio_bridge.dart' show EventRegistryLocator;

/// MIDI note → event mapping
class MidiNoteMapping {
  final int note;     // 0-127
  final int channel;  // 1-16 (0 = any)
  final String eventId;
  final bool velocityToVolume; // map velocity 0-127 → volume 0.0-1.0

  const MidiNoteMapping({
    required this.note,
    this.channel = 0,
    required this.eventId,
    this.velocityToVolume = true,
  });

  Map<String, dynamic> toJson() => {
    'note': note, 'channel': channel, 'eventId': eventId,
    'velocityToVolume': velocityToVolume,
  };

  factory MidiNoteMapping.fromJson(Map<String, dynamic> json) => MidiNoteMapping(
    note: json['note'] as int? ?? 60,
    channel: json['channel'] as int? ?? 0,
    eventId: json['eventId'] as String? ?? '',
    velocityToVolume: json['velocityToVolume'] as bool? ?? true,
  );
}

/// MIDI CC → RTPC mapping
class MidiCcMapping {
  final int cc;       // 0-127
  final int channel;  // 1-16 (0 = any)
  final int rtpcId;
  final double minValue;
  final double maxValue;

  const MidiCcMapping({
    required this.cc,
    this.channel = 0,
    required this.rtpcId,
    this.minValue = 0.0,
    this.maxValue = 1.0,
  });

  Map<String, dynamic> toJson() => {
    'cc': cc, 'channel': channel, 'rtpcId': rtpcId,
    'minValue': minValue, 'maxValue': maxValue,
  };

  factory MidiCcMapping.fromJson(Map<String, dynamic> json) => MidiCcMapping(
    cc: json['cc'] as int? ?? 1,
    channel: json['channel'] as int? ?? 0,
    rtpcId: json['rtpcId'] as int? ?? 0,
    minValue: (json['minValue'] as num?)?.toDouble() ?? 0.0,
    maxValue: (json['maxValue'] as num?)?.toDouble() ?? 1.0,
  );
}

/// MIDI Trigger Service
class MidiTriggerService with ChangeNotifier {
  MidiTriggerService._();
  static final instance = MidiTriggerService._();

  Timer? _pollTimer;
  bool _enabled = false;
  bool _learnMode = false;
  String? _learnTargetEventId;
  int? _learnTargetRtpcId;

  final List<MidiNoteMapping> _noteMappings = [];
  final List<MidiCcMapping> _ccMappings = [];

  RtpcSystemProvider? _rtpcProvider;

  // FFI — load native library directly (same lib as NativeFFI)
  static DynamicLibrary? _nativeLib;
  static DynamicLibrary _loadLib() {
    _nativeLib ??= DynamicLibrary.process(); // macOS: symbols in process
    return _nativeLib!;
  }
  static final _pollInputEvents = _loadLib().lookupFunction<
      Uint32 Function(Pointer<Uint8>, Uint32),
      int Function(Pointer<Uint8>, int)>('midi_poll_input_events');

  // Stats
  int _noteOnCount = 0;
  int _ccCount = 0;
  int? _lastNote;
  int? _lastVelocity;
  int? _lastCc;
  int? _lastCcValue;

  // Getters
  bool get enabled => _enabled;
  bool get learnMode => _learnMode;
  List<MidiNoteMapping> get noteMappings => List.unmodifiable(_noteMappings);
  List<MidiCcMapping> get ccMappings => List.unmodifiable(_ccMappings);
  int get noteOnCount => _noteOnCount;
  int get ccCount => _ccCount;
  int? get lastNote => _lastNote;
  int? get lastVelocity => _lastVelocity;

  /// Initialize with RTPC provider for CC→RTPC mapping
  void init(RtpcSystemProvider rtpcProvider) {
    _rtpcProvider = rtpcProvider;
  }

  /// Enable MIDI trigger polling
  void enable() {
    if (_enabled) return;
    _enabled = true;
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 5), (_) => _poll());
    notifyListeners();
  }

  /// Disable MIDI trigger polling
  void disable() {
    _enabled = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    notifyListeners();
  }

  /// Start learn mode — next MIDI note will be mapped to targetEventId
  void startLearnNote(String eventId) {
    _learnMode = true;
    _learnTargetEventId = eventId;
    _learnTargetRtpcId = null;
    notifyListeners();
  }

  /// Start learn mode for CC → RTPC
  void startLearnCc(int rtpcId) {
    _learnMode = true;
    _learnTargetRtpcId = rtpcId;
    _learnTargetEventId = null;
    notifyListeners();
  }

  /// Cancel learn mode
  void cancelLearn() {
    _learnMode = false;
    _learnTargetEventId = null;
    _learnTargetRtpcId = null;
    notifyListeners();
  }

  /// Add a note→event mapping
  void addNoteMapping(MidiNoteMapping mapping) {
    _noteMappings.removeWhere((m) => m.note == mapping.note && m.channel == mapping.channel);
    _noteMappings.add(mapping);
    notifyListeners();
  }

  /// Add a CC→RTPC mapping
  void addCcMapping(MidiCcMapping mapping) {
    _ccMappings.removeWhere((m) => m.cc == mapping.cc && m.channel == mapping.channel);
    _ccMappings.add(mapping);
    notifyListeners();
  }

  /// Remove mappings
  void removeNoteMapping(int note, int channel) {
    _noteMappings.removeWhere((m) => m.note == note && m.channel == channel);
    notifyListeners();
  }

  void removeCcMapping(int cc, int channel) {
    _ccMappings.removeWhere((m) => m.cc == cc && m.channel == channel);
    notifyListeners();
  }

  /// Poll MIDI input buffer from Rust
  void _poll() {
    if (!_enabled) return;

    // Allocate buffer for up to 64 events (3 bytes each)
    final bufSize = 64 * 3;
    final buf = calloc<Uint8>(bufSize);
    try {
      final count = _pollInputEvents(buf, 64);
      for (int i = 0; i < count; i++) {
        final status = buf[i * 3];
        final data1 = buf[i * 3 + 1];
        final data2 = buf[i * 3 + 2];
        _processMidiMessage(status, data1, data2);
      }
    } finally {
      calloc.free(buf);
    }
  }

  /// Process a single MIDI message
  void _processMidiMessage(int status, int data1, int data2) {
    final msgType = status & 0xF0;
    final channel = (status & 0x0F) + 1; // 1-based

    switch (msgType) {
      case 0x90: // Note On
        if (data2 > 0) {
          _handleNoteOn(data1, data2, channel);
        } else {
          // Note On with velocity 0 = Note Off
        }
      case 0x80: // Note Off
        break; // We only trigger on Note On
      case 0xB0: // Control Change
        _handleCC(data1, data2, channel);
    }
  }

  void _handleNoteOn(int note, int velocity, int channel) {
    _noteOnCount++;
    _lastNote = note;
    _lastVelocity = velocity;

    // Learn mode: auto-bind this note to target event
    if (_learnMode && _learnTargetEventId != null) {
      addNoteMapping(MidiNoteMapping(
        note: note,
        channel: 0, // Any channel
        eventId: _learnTargetEventId!,
      ));
      _learnMode = false;
      _learnTargetEventId = null;
      notifyListeners();
      return;
    }

    // Find mapping for this note
    for (final mapping in _noteMappings) {
      if (mapping.note == note && (mapping.channel == 0 || mapping.channel == channel)) {
        // Trigger event
        if (EventRegistryLocator.isSet) {
          EventRegistryLocator.instance.triggerEvent(mapping.eventId);
        }
        break;
      }
    }

    notifyListeners();
  }

  void _handleCC(int cc, int value, int channel) {
    _ccCount++;
    _lastCc = cc;
    _lastCcValue = value;

    // Learn mode: auto-bind this CC to target RTPC
    if (_learnMode && _learnTargetRtpcId != null) {
      addCcMapping(MidiCcMapping(
        cc: cc,
        channel: 0,
        rtpcId: _learnTargetRtpcId!,
      ));
      _learnMode = false;
      _learnTargetRtpcId = null;
      notifyListeners();
      return;
    }

    // Find mapping for this CC
    for (final mapping in _ccMappings) {
      if (mapping.cc == cc && (mapping.channel == 0 || mapping.channel == channel)) {
        // Map CC 0-127 → RTPC min-max range
        final normalized = value / 127.0;
        final rtpcValue = mapping.minValue + normalized * (mapping.maxValue - mapping.minValue);
        _rtpcProvider?.setRtpc(mapping.rtpcId, rtpcValue, interpolationMs: 50);
        break;
      }
    }

    notifyListeners();
  }

  /// Serialize for project save
  Map<String, dynamic> toJson() => {
    'noteMappings': _noteMappings.map((m) => m.toJson()).toList(),
    'ccMappings': _ccMappings.map((m) => m.toJson()).toList(),
    'enabled': _enabled,
  };

  /// Load from project
  void loadFromJson(Map<String, dynamic> json) {
    _noteMappings.clear();
    _ccMappings.clear();
    final notes = json['noteMappings'] as List?;
    if (notes != null) {
      _noteMappings.addAll(notes.map((n) => MidiNoteMapping.fromJson(n as Map<String, dynamic>)));
    }
    final ccs = json['ccMappings'] as List?;
    if (ccs != null) {
      _ccMappings.addAll(ccs.map((c) => MidiCcMapping.fromJson(c as Map<String, dynamic>)));
    }
    if (json['enabled'] == true && (_noteMappings.isNotEmpty || _ccMappings.isNotEmpty)) {
      enable();
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}
