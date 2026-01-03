/**
 * ReelForge MIDI Editor Module
 *
 * Piano roll and MIDI editing:
 * - Note editing
 * - Velocity lane
 * - Quantization
 * - Transpose
 *
 * @module midi-editor
 */

export { PianoRoll, generateNoteId } from './PianoRoll';
export type { PianoRollProps, MidiNote } from './PianoRoll';

export { useMidiEditor } from './useMidiEditor';
export type { UseMidiEditorOptions, UseMidiEditorReturn } from './useMidiEditor';
