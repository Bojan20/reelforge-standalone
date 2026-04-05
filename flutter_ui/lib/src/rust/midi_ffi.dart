/// MIDI FFI Extensions
///
/// Additional MIDI bindings not in the main NativeFFI class:
/// - Live input event polling (lock-free buffer drain)
/// - Raw MIDI byte send
/// - Data types for MIDI event parsing

import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'native_ffi.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// MIDI DATA TYPES
// ═══════════════════════════════════════════════════════════════════════════════

/// MIDI recording state
enum MidiRecordingState {
  stopped,
  armed,
  recording,
  paused,
}

/// Raw MIDI input event (3 bytes: status, data1, data2)
class MidiInputEventRaw {
  final int status;
  final int data1;
  final int data2;

  const MidiInputEventRaw({
    required this.status,
    required this.data1,
    required this.data2,
  });

  int get channel => status & 0x0F;
  int get messageType => status & 0xF0;

  bool get isNoteOn => messageType == 0x90 && data2 > 0;
  bool get isNoteOff => messageType == 0x80 || (messageType == 0x90 && data2 == 0);
  bool get isCC => messageType == 0xB0;
  bool get isPitchBend => messageType == 0xE0;
  bool get isProgramChange => messageType == 0xC0;

  int get note => data1;
  int get velocity => data2;
  int get ccNumber => data1;
  int get ccValue => data2;
  int get pitchBendValue => data1 | (data2 << 7);

  @override
  String toString() {
    if (isNoteOn) return 'NoteOn(ch=$channel, note=$note, vel=$velocity)';
    if (isNoteOff) return 'NoteOff(ch=$channel, note=$note)';
    if (isCC) return 'CC(ch=$channel, cc=$ccNumber, val=$ccValue)';
    if (isPitchBend) return 'PitchBend(ch=$channel, val=$pitchBendValue)';
    if (isProgramChange) return 'PC(ch=$channel, prog=$data1)';
    return 'MIDI(0x${status.toRadixString(16)}, $data1, $data2)';
  }
}

/// MIDI device info
class MidiDeviceInfo {
  final int index;
  final String name;
  final bool isInput;

  const MidiDeviceInfo({
    required this.index,
    required this.name,
    required this.isInput,
  });

  @override
  String toString() => '${isInput ? "IN" : "OUT"}[$index]: $name';
}

// ═══════════════════════════════════════════════════════════════════════════════
// MIDI LIVE INPUT POLLING + RAW SEND
// ═══════════════════════════════════════════════════════════════════════════════

extension MidiLiveInputFFI on NativeFFI {
  static final _midiPollInputEvents = loadNativeLibrary().lookupFunction<
      Uint32 Function(Pointer<Uint8> outBuffer, Uint32 maxEvents),
      int Function(Pointer<Uint8> outBuffer, int maxEvents)>('midi_poll_input_events');

  static final _midiPendingInputCount = loadNativeLibrary().lookupFunction<
      Uint32 Function(),
      int Function()>('midi_pending_input_count');

  static final _midiSendRaw = loadNativeLibrary().lookupFunction<
      Int32 Function(Pointer<Uint8> data, Uint8 len),
      int Function(Pointer<Uint8> data, int len)>('midi_send_raw');

  /// Poll pending MIDI input events. Returns list of raw events.
  /// Drains the input buffer — events are consumed.
  /// Call this from a Timer for live input monitoring / trigger mapping.
  List<MidiInputEventRaw> midiPollInputEvents({int maxEvents = 64}) {
    final bufSize = maxEvents * 3;
    final buf = calloc<Uint8>(bufSize);
    try {
      final count = _midiPollInputEvents(buf, maxEvents);
      final events = <MidiInputEventRaw>[];
      for (int i = 0; i < count; i++) {
        events.add(MidiInputEventRaw(
          status: buf[i * 3],
          data1: buf[i * 3 + 1],
          data2: buf[i * 3 + 2],
        ));
      }
      return events;
    } finally {
      calloc.free(buf);
    }
  }

  /// Get count of pending MIDI input events without consuming them
  int midiPendingInputCount() => _midiPendingInputCount();

  /// Send raw MIDI bytes (1-3 bytes). Returns true on success.
  bool midiSendRaw(List<int> bytes) {
    if (bytes.isEmpty || bytes.length > 3) return false;
    final buf = calloc<Uint8>(bytes.length);
    try {
      for (int i = 0; i < bytes.length; i++) {
        buf[i] = bytes[i];
      }
      return _midiSendRaw(buf, bytes.length) == 1;
    } finally {
      calloc.free(buf);
    }
  }

  /// List input devices as typed objects
  List<MidiDeviceInfo> midiListInputDevices() {
    final count = midiScanInputDevices();
    final names = midiGetAllInputDevices();
    return List.generate(
      count < names.length ? count : names.length,
      (i) => MidiDeviceInfo(index: i, name: names[i], isInput: true),
    );
  }

  /// List output devices as typed objects
  List<MidiDeviceInfo> midiListOutputDevices() {
    final count = midiScanOutputDevices();
    final names = midiGetAllOutputDevices();
    return List.generate(
      count < names.length ? count : names.length,
      (i) => MidiDeviceInfo(index: i, name: names[i], isInput: false),
    );
  }
}
