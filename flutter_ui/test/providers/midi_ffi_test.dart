/// MIDI FFI Bindings Tests
///
/// Tests MIDI data models, event parsing, and device info.
/// FFI calls are tested via integration tests (requires native lib).
@Tags(['provider'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/src/rust/midi_ffi.dart';

void main() {
  group('MidiRecordingState', () {
    test('has all expected states', () {
      expect(MidiRecordingState.values.length, 4);
      expect(MidiRecordingState.stopped.index, 0);
      expect(MidiRecordingState.armed.index, 1);
      expect(MidiRecordingState.recording.index, 2);
      expect(MidiRecordingState.paused.index, 3);
    });
  });

  group('MidiInputEventRaw', () {
    test('parses Note On correctly', () {
      final event = MidiInputEventRaw(status: 0x90, data1: 60, data2: 100);
      expect(event.isNoteOn, true);
      expect(event.isNoteOff, false);
      expect(event.channel, 0);
      expect(event.note, 60);
      expect(event.velocity, 100);
      expect(event.messageType, 0x90);
    });

    test('parses Note On on channel 5', () {
      final event = MidiInputEventRaw(status: 0x95, data1: 72, data2: 80);
      expect(event.isNoteOn, true);
      expect(event.channel, 5);
      expect(event.note, 72);
      expect(event.velocity, 80);
    });

    test('parses Note Off correctly', () {
      final event = MidiInputEventRaw(status: 0x80, data1: 60, data2: 64);
      expect(event.isNoteOff, true);
      expect(event.isNoteOn, false);
      expect(event.channel, 0);
      expect(event.note, 60);
    });

    test('Note On with velocity 0 is Note Off', () {
      final event = MidiInputEventRaw(status: 0x90, data1: 60, data2: 0);
      expect(event.isNoteOff, true);
      expect(event.isNoteOn, false);
    });

    test('parses CC correctly', () {
      final event = MidiInputEventRaw(status: 0xB3, data1: 7, data2: 100);
      expect(event.isCC, true);
      expect(event.channel, 3);
      expect(event.ccNumber, 7);
      expect(event.ccValue, 100);
    });

    test('parses Pitch Bend correctly', () {
      final event = MidiInputEventRaw(status: 0xE0, data1: 0, data2: 64);
      expect(event.isPitchBend, true);
      expect(event.pitchBendValue, 8192); // center
    });

    test('pitch bend min value', () {
      final event = MidiInputEventRaw(status: 0xE0, data1: 0, data2: 0);
      expect(event.pitchBendValue, 0);
    });

    test('pitch bend max value', () {
      final event = MidiInputEventRaw(status: 0xE0, data1: 127, data2: 127);
      expect(event.pitchBendValue, 16383);
    });

    test('parses Program Change correctly', () {
      final event = MidiInputEventRaw(status: 0xC0, data1: 42, data2: 0);
      expect(event.isProgramChange, true);
      expect(event.channel, 0);
      expect(event.data1, 42);
    });

    test('toString formats correctly', () {
      expect(
        MidiInputEventRaw(status: 0x90, data1: 60, data2: 100).toString(),
        'NoteOn(ch=0, note=60, vel=100)',
      );
      expect(
        MidiInputEventRaw(status: 0x80, data1: 60, data2: 64).toString(),
        'NoteOff(ch=0, note=60)',
      );
      expect(
        MidiInputEventRaw(status: 0xB0, data1: 7, data2: 100).toString(),
        'CC(ch=0, cc=7, val=100)',
      );
      expect(
        MidiInputEventRaw(status: 0xE0, data1: 0, data2: 64).toString(),
        'PitchBend(ch=0, val=8192)',
      );
      expect(
        MidiInputEventRaw(status: 0xC0, data1: 42, data2: 0).toString(),
        'PC(ch=0, prog=42)',
      );
    });

    test('all 16 channels work', () {
      for (int ch = 0; ch < 16; ch++) {
        final event = MidiInputEventRaw(status: 0x90 | ch, data1: 60, data2: 100);
        expect(event.channel, ch);
        expect(event.isNoteOn, true);
      }
    });
  });

  group('MidiDeviceInfo', () {
    test('creates input device', () {
      final device = MidiDeviceInfo(index: 0, name: 'USB MIDI Controller', isInput: true);
      expect(device.index, 0);
      expect(device.name, 'USB MIDI Controller');
      expect(device.isInput, true);
      expect(device.toString(), 'IN[0]: USB MIDI Controller');
    });

    test('creates output device', () {
      final device = MidiDeviceInfo(index: 2, name: 'Virtual MIDI', isInput: false);
      expect(device.isInput, false);
      expect(device.toString(), 'OUT[2]: Virtual MIDI');
    });
  });
}
