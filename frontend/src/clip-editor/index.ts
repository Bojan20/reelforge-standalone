/**
 * ReelForge Clip Editor Module
 *
 * Audio clip editing components:
 * - Trim/resize
 * - Fade handles
 * - Waveform display
 * - Multi-selection
 *
 * @module clip-editor
 */

export { ClipEditor } from './ClipEditor';
export type { ClipEditorProps, ClipData, FadeCurve } from './ClipEditor';

export { useClipEditor } from './useClipEditor';
export type { UseClipEditorOptions, UseClipEditorReturn } from './useClipEditor';
