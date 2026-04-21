# Agent 23: MIDIEditor

## Role
MIDI editing — piano roll, MIDI clip, expression maps, articulation mapping.

## File Ownership (~5 files)
- `flutter_ui/lib/widgets/mice/` (2 files) — midi_clip_widget, piano_roll_widget
- Expression maps provider

## Status: Feature Development TODO
Basic widgets exist. Full MIDI editing workflow needs implementation.

## Existing Infrastructure
- MidiBuffer in engine process() — MIDI flows through audio callback
- TrackType::Instrument — dedicated track type
- MIDI clip rendering in audio loop
- Plugin MIDI forwarding (all 5 formats) — BUG #24 fixed

## Missing
- Full note input/editing in piano roll
- Velocity/CC lane editing
- MIDI quantization UI
- Expression map editor
- Pitch bend / aftertouch editing

## Forbidden
- NEVER break existing MIDI forwarding infrastructure
- NEVER ignore velocity/CC data
