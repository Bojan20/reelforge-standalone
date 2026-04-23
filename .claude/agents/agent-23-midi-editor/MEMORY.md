# Agent 23: MIDIEditor — Memory

## What Exists
- MidiBuffer in process(), TrackType::Instrument, MIDI forwarding to all 5 formats
- Basic MIDI clip widget and piano roll widget in widgets/mice/

## What's Missing
- Full note input/editing, velocity/CC lanes, quantization, expression map editor, pitch bend, MIDI learn

## Data Flow
Piano Roll → MidiBuffer → Engine process() → Plugin process()
