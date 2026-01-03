/**
 * ReelForge MIDI Editor Hook
 *
 * State management for MIDI editing:
 * - Note CRUD
 * - Selection
 * - Quantization
 * - Transpose
 * - Copy/paste
 *
 * @module midi-editor/useMidiEditor
 */

import { useState, useCallback, useMemo } from 'react';
import type { MidiNote } from './PianoRoll';

// ============ Types ============

export interface UseMidiEditorOptions {
  /** Initial notes */
  initialNotes?: MidiNote[];
  /** On change callback */
  onChange?: (notes: MidiNote[]) => void;
}

export interface UseMidiEditorReturn {
  /** All notes */
  notes: MidiNote[];
  /** Selected note IDs */
  selectedNoteIds: string[];
  /** Clipboard */
  clipboard: MidiNote[];
  /** Add note */
  addNote: (note: Omit<MidiNote, 'id'>) => string;
  /** Update note */
  updateNote: (noteId: string, updates: Partial<MidiNote>) => void;
  /** Delete note */
  deleteNote: (noteId: string) => void;
  /** Delete selected notes */
  deleteSelected: () => void;
  /** Select note */
  selectNote: (noteId: string, addToSelection?: boolean) => void;
  /** Select multiple notes */
  selectNotes: (noteIds: string[]) => void;
  /** Select all notes */
  selectAll: () => void;
  /** Clear selection */
  clearSelection: () => void;
  /** Copy selected */
  copySelected: () => void;
  /** Paste */
  paste: (atBeat: number) => void;
  /** Duplicate selected */
  duplicateSelected: () => void;
  /** Transpose selected */
  transposeSelected: (semitones: number) => void;
  /** Quantize selected */
  quantizeSelected: (resolution: number) => void;
  /** Set velocity for selected */
  setVelocity: (velocity: number) => void;
  /** Humanize selected (slight randomization) */
  humanizeSelected: (amount: number) => void;
  /** Get notes in time range */
  getNotesInRange: (startBeat: number, endBeat: number) => MidiNote[];
  /** Get notes at pitch */
  getNotesAtPitch: (pitch: number) => MidiNote[];
}

// ============ Helpers ============

function generateNoteId(): string {
  return `note-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
}

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

// ============ Hook ============

export function useMidiEditor(options: UseMidiEditorOptions = {}): UseMidiEditorReturn {
  const { initialNotes = [], onChange } = options;

  const [notes, setNotes] = useState<MidiNote[]>(initialNotes);
  const [clipboard, setClipboard] = useState<MidiNote[]>([]);

  // Helper to update notes and trigger callback
  const updateNotes = useCallback(
    (updater: (prev: MidiNote[]) => MidiNote[]) => {
      setNotes((prev) => {
        const next = updater(prev);
        onChange?.(next);
        return next;
      });
    },
    [onChange]
  );

  // Selected note IDs
  const selectedNoteIds = useMemo(
    () => notes.filter((n) => n.selected).map((n) => n.id),
    [notes]
  );

  // Add note
  const addNote = useCallback(
    (note: Omit<MidiNote, 'id'>): string => {
      const id = generateNoteId();
      updateNotes((prev) => [...prev, { ...note, id }]);
      return id;
    },
    [updateNotes]
  );

  // Update note
  const updateNote = useCallback(
    (noteId: string, updates: Partial<MidiNote>) => {
      updateNotes((prev) =>
        prev.map((n) => (n.id === noteId ? { ...n, ...updates } : n))
      );
    },
    [updateNotes]
  );

  // Delete note
  const deleteNote = useCallback(
    (noteId: string) => {
      updateNotes((prev) => prev.filter((n) => n.id !== noteId));
    },
    [updateNotes]
  );

  // Delete selected
  const deleteSelected = useCallback(() => {
    updateNotes((prev) => prev.filter((n) => !n.selected));
  }, [updateNotes]);

  // Select note
  const selectNote = useCallback(
    (noteId: string, addToSelection = false) => {
      updateNotes((prev) =>
        prev.map((n) => ({
          ...n,
          selected: addToSelection
            ? n.id === noteId
              ? !n.selected
              : n.selected
            : n.id === noteId,
        }))
      );
    },
    [updateNotes]
  );

  // Select multiple notes
  const selectNotes = useCallback(
    (noteIds: string[]) => {
      const idsSet = new Set(noteIds);
      updateNotes((prev) =>
        prev.map((n) => ({ ...n, selected: idsSet.has(n.id) }))
      );
    },
    [updateNotes]
  );

  // Select all
  const selectAll = useCallback(() => {
    updateNotes((prev) => prev.map((n) => ({ ...n, selected: true })));
  }, [updateNotes]);

  // Clear selection
  const clearSelection = useCallback(() => {
    updateNotes((prev) => prev.map((n) => ({ ...n, selected: false })));
  }, [updateNotes]);

  // Copy selected
  const copySelected = useCallback(() => {
    const selected = notes.filter((n) => n.selected);
    setClipboard(selected);
  }, [notes]);

  // Paste
  const paste = useCallback(
    (atBeat: number) => {
      if (clipboard.length === 0) return;

      const earliestBeat = Math.min(...clipboard.map((n) => n.startTime));
      const offset = atBeat - earliestBeat;

      const newNotes = clipboard.map((n) => ({
        ...n,
        id: generateNoteId(),
        startTime: n.startTime + offset,
        selected: true,
      }));

      updateNotes((prev) => [
        ...prev.map((n) => ({ ...n, selected: false })),
        ...newNotes,
      ]);
    },
    [clipboard, updateNotes]
  );

  // Duplicate selected
  const duplicateSelected = useCallback(() => {
    const selected = notes.filter((n) => n.selected);
    if (selected.length === 0) return;

    // Find the total duration to offset duplicates
    const maxEnd = Math.max(...selected.map((n) => n.startTime + n.duration));
    const minStart = Math.min(...selected.map((n) => n.startTime));
    const offset = maxEnd - minStart;

    const duplicates = selected.map((n) => ({
      ...n,
      id: generateNoteId(),
      startTime: n.startTime + offset,
    }));

    updateNotes((prev) => [...prev, ...duplicates]);
  }, [notes, updateNotes]);

  // Transpose selected
  const transposeSelected = useCallback(
    (semitones: number) => {
      updateNotes((prev) =>
        prev.map((n) =>
          n.selected
            ? { ...n, pitch: clamp(n.pitch + semitones, 0, 127) }
            : n
        )
      );
    },
    [updateNotes]
  );

  // Quantize selected
  const quantizeSelected = useCallback(
    (resolution: number) => {
      updateNotes((prev) =>
        prev.map((n) =>
          n.selected
            ? {
                ...n,
                startTime: Math.round(n.startTime / resolution) * resolution,
                duration: Math.max(
                  resolution,
                  Math.round(n.duration / resolution) * resolution
                ),
              }
            : n
        )
      );
    },
    [updateNotes]
  );

  // Set velocity
  const setVelocity = useCallback(
    (velocity: number) => {
      const v = clamp(velocity, 1, 127);
      updateNotes((prev) =>
        prev.map((n) => (n.selected ? { ...n, velocity: v } : n))
      );
    },
    [updateNotes]
  );

  // Humanize selected
  const humanizeSelected = useCallback(
    (amount: number) => {
      updateNotes((prev) =>
        prev.map((n) => {
          if (!n.selected) return n;

          // Random offset for timing
          const timeOffset = (Math.random() - 0.5) * amount * 0.1;
          // Random offset for velocity
          const velOffset = Math.round((Math.random() - 0.5) * amount * 0.2 * 127);

          return {
            ...n,
            startTime: Math.max(0, n.startTime + timeOffset),
            velocity: clamp(n.velocity + velOffset, 1, 127),
          };
        })
      );
    },
    [updateNotes]
  );

  // Get notes in time range
  const getNotesInRange = useCallback(
    (startBeat: number, endBeat: number): MidiNote[] => {
      return notes.filter(
        (n) => n.startTime < endBeat && n.startTime + n.duration > startBeat
      );
    },
    [notes]
  );

  // Get notes at pitch
  const getNotesAtPitch = useCallback(
    (pitch: number): MidiNote[] => {
      return notes.filter((n) => n.pitch === pitch);
    },
    [notes]
  );

  return useMemo(
    () => ({
      notes,
      selectedNoteIds,
      clipboard,
      addNote,
      updateNote,
      deleteNote,
      deleteSelected,
      selectNote,
      selectNotes,
      selectAll,
      clearSelection,
      copySelected,
      paste,
      duplicateSelected,
      transposeSelected,
      quantizeSelected,
      setVelocity,
      humanizeSelected,
      getNotesInRange,
      getNotesAtPitch,
    }),
    [
      notes,
      selectedNoteIds,
      clipboard,
      addNote,
      updateNote,
      deleteNote,
      deleteSelected,
      selectNote,
      selectNotes,
      selectAll,
      clearSelection,
      copySelected,
      paste,
      duplicateSelected,
      transposeSelected,
      quantizeSelected,
      setVelocity,
      humanizeSelected,
      getNotesInRange,
      getNotesAtPitch,
    ]
  );
}

export default useMidiEditor;
