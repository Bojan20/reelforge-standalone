/**
 * ReelForge Piano Roll / MIDI Editor
 *
 * MIDI note editing with:
 * - Piano keyboard sidebar
 * - Note grid with snap
 * - Velocity lane
 * - Note add/delete/resize/move
 * - Multi-selection
 *
 * @module midi-editor/PianoRoll
 */

import { useState, useCallback, useRef, useMemo } from 'react';
import './PianoRoll.css';

// ============ Types ============

export interface MidiNote {
  id: string;
  pitch: number; // 0-127
  velocity: number; // 0-127
  startTime: number; // beats
  duration: number; // beats
  selected?: boolean;
}

export interface PianoRollProps {
  /** MIDI notes */
  notes: MidiNote[];
  /** Duration in beats */
  duration: number;
  /** Tempo BPM */
  tempo: number;
  /** Time signature */
  timeSignature: [number, number];
  /** Pixels per beat */
  pixelsPerBeat?: number;
  /** Note height in pixels */
  noteHeight?: number;
  /** Visible pitch range */
  pitchRange?: [number, number];
  /** Snap resolution in beats */
  snapResolution?: number;
  /** Snap enabled */
  snapEnabled?: boolean;
  /** Show velocity lane */
  showVelocity?: boolean;
  /** Velocity lane height */
  velocityLaneHeight?: number;
  /** On note add */
  onNoteAdd?: (note: Omit<MidiNote, 'id'>) => void;
  /** On note change */
  onNoteChange?: (noteId: string, updates: Partial<MidiNote>) => void;
  /** On note delete */
  onNoteDelete?: (noteId: string) => void;
  /** On selection change */
  onSelectionChange?: (noteIds: string[]) => void;
  /** On playhead position */
  playheadPosition?: number;
}

type DragMode = 'none' | 'note-move' | 'note-resize' | 'velocity' | 'select-box';

// ============ Constants ============

const NOTE_NAMES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
const KEYBOARD_WIDTH = 60;
const DEFAULT_VELOCITY = 100;

// ============ Helpers ============

function getNoteInfo(pitch: number): { name: string; octave: number; isBlack: boolean } {
  const octave = Math.floor(pitch / 12) - 1;
  const noteIndex = pitch % 12;
  const name = NOTE_NAMES[noteIndex];
  const isBlack = name.includes('#');
  return { name, octave, isBlack };
}

function generateNoteId(): string {
  return `note-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
}

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

// ============ Component ============

export function PianoRoll({
  notes,
  duration,
  tempo: _tempo,
  timeSignature,
  pixelsPerBeat = 40,
  noteHeight = 16,
  pitchRange = [36, 96], // C2 to C7
  snapResolution = 0.25,
  snapEnabled = true,
  showVelocity = true,
  velocityLaneHeight = 60,
  onNoteAdd,
  onNoteChange,
  onNoteDelete,
  onSelectionChange,
  playheadPosition,
}: PianoRollProps) {
  const [dragMode, setDragMode] = useState<DragMode>('none');
  const [dragNoteId, setDragNoteId] = useState<string | null>(null);
  const [scrollX, setScrollX] = useState(0);
  const [scrollY, setScrollY] = useState(0);
  const [selectBox, setSelectBox] = useState<{ x1: number; y1: number; x2: number; y2: number } | null>(null);

  const containerRef = useRef<HTMLDivElement>(null);
  const dragStartRef = useRef({ x: 0, y: 0, startTime: 0, pitch: 0, duration: 0 });

  // Calculated dimensions
  const pitchCount = pitchRange[1] - pitchRange[0] + 1;
  const gridHeight = pitchCount * noteHeight;
  const gridWidth = duration * pixelsPerBeat;
  const beatsPerBar = timeSignature[0];

  // Snap to grid
  const snapBeat = useCallback(
    (beat: number): number => {
      if (!snapEnabled) return beat;
      return Math.round(beat / snapResolution) * snapResolution;
    },
    [snapEnabled, snapResolution]
  );

  // Convert coordinates
  const beatToX = useCallback((beat: number) => beat * pixelsPerBeat - scrollX, [pixelsPerBeat, scrollX]);
  const xToBeat = useCallback((x: number) => (x + scrollX) / pixelsPerBeat, [pixelsPerBeat, scrollX]);
  const pitchToY = useCallback((pitch: number) => (pitchRange[1] - pitch) * noteHeight - scrollY, [pitchRange, noteHeight, scrollY]);
  const yToPitch = useCallback((y: number) => pitchRange[1] - Math.floor((y + scrollY) / noteHeight), [pitchRange, noteHeight, scrollY]);

  // Get selected notes
  const selectedNotes = useMemo(() => notes.filter((n) => n.selected), [notes]);

  // Handle grid click (add note)
  const handleGridMouseDown = useCallback(
    (e: React.MouseEvent) => {
      if (e.button !== 0) return;

      const rect = (e.currentTarget as HTMLElement).getBoundingClientRect();
      const x = e.clientX - rect.left;
      const y = e.clientY - rect.top;
      const beat = snapBeat(xToBeat(x));
      const pitch = clamp(yToPitch(y), pitchRange[0], pitchRange[1]);

      // Check if clicking on existing note
      const clickedNote = notes.find((note) => {
        const noteX = beatToX(note.startTime);
        const noteY = pitchToY(note.pitch);
        const noteW = note.duration * pixelsPerBeat;
        return x >= noteX && x <= noteX + noteW && y >= noteY && y <= noteY + noteHeight;
      });

      if (clickedNote) {
        // Start dragging note
        const isResizeEdge = x > beatToX(clickedNote.startTime) + clickedNote.duration * pixelsPerBeat - 8;

        if (e.ctrlKey || e.metaKey) {
          // Toggle selection
          onNoteChange?.(clickedNote.id, { selected: !clickedNote.selected });
        } else {
          // Select and start drag
          if (!clickedNote.selected) {
            onSelectionChange?.([clickedNote.id]);
          }

          setDragMode(isResizeEdge ? 'note-resize' : 'note-move');
          setDragNoteId(clickedNote.id);
          dragStartRef.current = {
            x,
            y,
            startTime: clickedNote.startTime,
            pitch: clickedNote.pitch,
            duration: clickedNote.duration,
          };
        }
      } else if (e.shiftKey) {
        // Start selection box
        setDragMode('select-box');
        setSelectBox({ x1: x, y1: y, x2: x, y2: y });
      } else {
        // Add new note
        onSelectionChange?.([]);
        onNoteAdd?.({
          pitch,
          velocity: DEFAULT_VELOCITY,
          startTime: beat,
          duration: snapResolution,
        });
      }
    },
    [notes, snapBeat, xToBeat, yToPitch, beatToX, pitchToY, pitchRange, pixelsPerBeat, noteHeight, snapResolution, onNoteAdd, onNoteChange, onSelectionChange]
  );

  // Handle mouse move
  const handleMouseMove = useCallback(
    (e: React.MouseEvent) => {
      if (dragMode === 'none') return;

      const rect = (e.currentTarget as HTMLElement).getBoundingClientRect();
      const x = e.clientX - rect.left;
      const y = e.clientY - rect.top;

      if (dragMode === 'select-box' && selectBox) {
        setSelectBox({ ...selectBox, x2: x, y2: y });
        return;
      }

      if (!dragNoteId) return;

      const deltaX = x - dragStartRef.current.x;
      const deltaY = y - dragStartRef.current.y;
      const deltaBeat = deltaX / pixelsPerBeat;
      const deltaPitch = -Math.round(deltaY / noteHeight);

      if (dragMode === 'note-move') {
        const newStart = snapBeat(Math.max(0, dragStartRef.current.startTime + deltaBeat));
        const newPitch = clamp(dragStartRef.current.pitch + deltaPitch, pitchRange[0], pitchRange[1]);

        // Move all selected notes
        selectedNotes.forEach((note) => {
          const offsetStart = note.startTime - dragStartRef.current.startTime;
          const offsetPitch = note.pitch - dragStartRef.current.pitch;
          onNoteChange?.(note.id, {
            startTime: snapBeat(Math.max(0, newStart + offsetStart)),
            pitch: clamp(newPitch + offsetPitch, pitchRange[0], pitchRange[1]),
          });
        });
      } else if (dragMode === 'note-resize') {
        const newDuration = snapBeat(Math.max(snapResolution, dragStartRef.current.duration + deltaBeat));
        onNoteChange?.(dragNoteId, { duration: newDuration });
      }
    },
    [dragMode, dragNoteId, selectBox, selectedNotes, pixelsPerBeat, noteHeight, snapBeat, pitchRange, snapResolution, onNoteChange]
  );

  // Handle mouse up
  const handleMouseUp = useCallback(() => {
    if (dragMode === 'select-box' && selectBox) {
      // Select notes in box
      const x1 = Math.min(selectBox.x1, selectBox.x2);
      const x2 = Math.max(selectBox.x1, selectBox.x2);
      const y1 = Math.min(selectBox.y1, selectBox.y2);
      const y2 = Math.max(selectBox.y1, selectBox.y2);

      const selectedIds = notes
        .filter((note) => {
          const noteX = beatToX(note.startTime);
          const noteY = pitchToY(note.pitch);
          const noteW = note.duration * pixelsPerBeat;
          return noteX + noteW >= x1 && noteX <= x2 && noteY + noteHeight >= y1 && noteY <= y2;
        })
        .map((n) => n.id);

      onSelectionChange?.(selectedIds);
    }

    setDragMode('none');
    setDragNoteId(null);
    setSelectBox(null);
  }, [dragMode, selectBox, notes, beatToX, pitchToY, pixelsPerBeat, noteHeight, onSelectionChange]);

  // Handle key press
  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if ((e.key === 'Delete' || e.key === 'Backspace') && selectedNotes.length > 0) {
        selectedNotes.forEach((note) => onNoteDelete?.(note.id));
      }
    },
    [selectedNotes, onNoteDelete]
  );

  // Handle velocity change
  const handleVelocityMouseDown = useCallback(
    (e: React.MouseEvent, noteId: string) => {
      e.stopPropagation();
      setDragMode('velocity');
      setDragNoteId(noteId);

      const handleMove = (e: MouseEvent) => {
        const rect = containerRef.current?.querySelector('.piano-roll__velocity-lane')?.getBoundingClientRect();
        if (!rect) return;
        const y = e.clientY - rect.top;
        const velocity = clamp(Math.round(127 * (1 - y / velocityLaneHeight)), 1, 127);
        onNoteChange?.(noteId, { velocity });
      };

      const handleUp = () => {
        setDragMode('none');
        setDragNoteId(null);
        window.removeEventListener('mousemove', handleMove);
        window.removeEventListener('mouseup', handleUp);
      };

      window.addEventListener('mousemove', handleMove);
      window.addEventListener('mouseup', handleUp);
    },
    [velocityLaneHeight, onNoteChange]
  );

  // Handle scroll
  const handleWheel = useCallback((e: React.WheelEvent) => {
    if (e.shiftKey) {
      setScrollX((prev) => Math.max(0, prev + e.deltaY));
    } else {
      setScrollY((prev) => Math.max(0, prev + e.deltaY));
    }
  }, []);

  // Render piano keyboard
  const renderKeyboard = () => {
    const keys: React.ReactElement[] = [];

    for (let pitch = pitchRange[1]; pitch >= pitchRange[0]; pitch--) {
      const { name, octave, isBlack } = getNoteInfo(pitch);
      const y = pitchToY(pitch);

      keys.push(
        <div
          key={pitch}
          className={`piano-roll__key ${isBlack ? 'piano-roll__key--black' : 'piano-roll__key--white'}`}
          style={{ top: y, height: noteHeight }}
        >
          {name === 'C' && <span className="piano-roll__key-label">{name}{octave}</span>}
        </div>
      );
    }

    return (
      <div className="piano-roll__keyboard" style={{ width: KEYBOARD_WIDTH, height: gridHeight }}>
        {keys}
      </div>
    );
  };

  // Render grid lines
  const renderGrid = () => {
    const lines: React.ReactElement[] = [];

    // Horizontal lines (pitch)
    for (let pitch = pitchRange[0]; pitch <= pitchRange[1]; pitch++) {
      const y = pitchToY(pitch);
      const { isBlack } = getNoteInfo(pitch);
      lines.push(
        <div
          key={`h-${pitch}`}
          className={`piano-roll__grid-line piano-roll__grid-line--h ${isBlack ? 'black' : ''}`}
          style={{ top: y, height: noteHeight }}
        />
      );
    }

    // Vertical lines (beats)
    for (let beat = 0; beat <= duration; beat += snapResolution) {
      const x = beatToX(beat);
      const isBar = beat % beatsPerBar === 0;
      const isBeat = beat % 1 === 0;

      lines.push(
        <div
          key={`v-${beat}`}
          className={`piano-roll__grid-line piano-roll__grid-line--v ${isBar ? 'bar' : isBeat ? 'beat' : ''}`}
          style={{ left: x }}
        />
      );
    }

    return <div className="piano-roll__grid">{lines}</div>;
  };

  // Render notes
  const renderNotes = () => {
    return notes.map((note) => {
      const x = beatToX(note.startTime);
      const y = pitchToY(note.pitch);
      const w = note.duration * pixelsPerBeat;

      return (
        <div
          key={note.id}
          className={`piano-roll__note ${note.selected ? 'selected' : ''}`}
          style={{
            left: x,
            top: y,
            width: w,
            height: noteHeight - 1,
            opacity: note.velocity / 127,
          }}
        >
          <div className="piano-roll__note-resize" />
        </div>
      );
    });
  };

  // Render velocity lane
  const renderVelocityLane = () => {
    if (!showVelocity) return null;

    return (
      <div className="piano-roll__velocity-lane" style={{ height: velocityLaneHeight }}>
        <div className="piano-roll__velocity-grid" style={{ width: gridWidth, marginLeft: KEYBOARD_WIDTH }}>
          {notes.map((note) => {
            const x = beatToX(note.startTime);
            const w = Math.max(4, note.duration * pixelsPerBeat - 2);
            const h = (note.velocity / 127) * velocityLaneHeight;

            return (
              <div
                key={note.id}
                className={`piano-roll__velocity-bar ${note.selected ? 'selected' : ''}`}
                style={{ left: x, width: w, height: h }}
                onMouseDown={(e) => handleVelocityMouseDown(e, note.id)}
              />
            );
          })}
        </div>
      </div>
    );
  };

  return (
    <div
      ref={containerRef}
      className="piano-roll"
      tabIndex={0}
      onKeyDown={handleKeyDown}
      onWheel={handleWheel}
    >
      {/* Main Area */}
      <div className="piano-roll__main">
        {renderKeyboard()}
        <div
          className="piano-roll__grid-container"
          style={{ width: gridWidth, height: gridHeight }}
          onMouseDown={handleGridMouseDown}
          onMouseMove={handleMouseMove}
          onMouseUp={handleMouseUp}
          onMouseLeave={handleMouseUp}
        >
          {renderGrid()}
          {renderNotes()}

          {/* Playhead */}
          {playheadPosition !== undefined && (
            <div
              className="piano-roll__playhead"
              style={{ left: beatToX(playheadPosition) }}
            />
          )}

          {/* Selection box */}
          {selectBox && (
            <div
              className="piano-roll__select-box"
              style={{
                left: Math.min(selectBox.x1, selectBox.x2),
                top: Math.min(selectBox.y1, selectBox.y2),
                width: Math.abs(selectBox.x2 - selectBox.x1),
                height: Math.abs(selectBox.y2 - selectBox.y1),
              }}
            />
          )}
        </div>
      </div>

      {/* Velocity Lane */}
      {renderVelocityLane()}
    </div>
  );
}

export { generateNoteId };
export default PianoRoll;
