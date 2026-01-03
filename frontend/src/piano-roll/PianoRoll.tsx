/**
 * ReelForge PianoRoll
 *
 * MIDI note editor:
 * - Piano keyboard
 * - Note grid
 * - Velocity editing
 * - Selection/drag
 * - Zoom/scroll
 *
 * @module piano-roll/PianoRoll
 */

import { useRef, useEffect, useCallback, useState, useMemo } from 'react';
import './PianoRoll.css';

// ============ Types ============

export interface MidiNote {
  id: string;
  pitch: number;      // 0-127
  start: number;      // beats
  duration: number;   // beats
  velocity: number;   // 0-127
}

export interface PianoRollProps {
  /** MIDI notes */
  notes: MidiNote[];
  /** On notes change */
  onChange?: (notes: MidiNote[]) => void;
  /** Total length in beats */
  length?: number;
  /** Beats per bar */
  beatsPerBar?: number;
  /** Pixels per beat */
  pixelsPerBeat?: number;
  /** Row height (pixels per semitone) */
  rowHeight?: number;
  /** Min visible pitch */
  minPitch?: number;
  /** Max visible pitch */
  maxPitch?: number;
  /** Snap to grid (beats) */
  snap?: number;
  /** Playhead position (beats) */
  playhead?: number;
  /** Keyboard width */
  keyboardWidth?: number;
  /** Show velocity lane */
  showVelocity?: boolean;
  /** Velocity lane height */
  velocityHeight?: number;
  /** On note select */
  onNoteSelect?: (noteIds: string[]) => void;
  /** On playhead change */
  onPlayheadChange?: (beat: number) => void;
  /** Custom class */
  className?: string;
}

// ============ Note Names ============

const NOTE_NAMES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

function getPitchName(pitch: number): string {
  const octave = Math.floor(pitch / 12) - 1;
  const note = NOTE_NAMES[pitch % 12];
  return `${note}${octave}`;
}

function isBlackKey(pitch: number): boolean {
  const note = pitch % 12;
  return [1, 3, 6, 8, 10].includes(note);
}

// ============ PianoRoll Component ============

export function PianoRoll({
  notes,
  onChange,
  length = 16,
  beatsPerBar = 4,
  pixelsPerBeat = 40,
  rowHeight = 16,
  minPitch = 36,
  maxPitch = 96,
  snap = 0.25,
  playhead,
  keyboardWidth = 60,
  showVelocity = true,
  velocityHeight = 80,
  onNoteSelect,
  onPlayheadChange: _onPlayheadChange,
  className = '',
}: PianoRollProps) {
  void _onPlayheadChange; // Reserved for future playhead scrubbing
  const containerRef = useRef<HTMLDivElement>(null);
  const gridCanvasRef = useRef<HTMLCanvasElement>(null);
  const notesCanvasRef = useRef<HTMLCanvasElement>(null);

  const [selectedNotes, setSelectedNotes] = useState<Set<string>>(new Set());
  const [scrollLeft, _setScrollLeft] = useState(0);
  const [scrollTop, _setScrollTop] = useState(0);
  const [_isDragging, setIsDragging] = useState(false);
  const [_dragMode, setDragMode] = useState<'move' | 'resize' | 'draw' | 'select'>('move');
  void _setScrollLeft; void _setScrollTop; void _isDragging; void _dragMode;

  const pitchRange = maxPitch - minPitch + 1;
  const _gridWidth = length * pixelsPerBeat;
  const _gridHeight = pitchRange * rowHeight;
  void _gridWidth; void _gridHeight;

  // Snap value to grid
  const snapToGrid = useCallback(
    (value: number): number => {
      if (snap <= 0) return value;
      return Math.round(value / snap) * snap;
    },
    [snap]
  );

  // Convert pixel to beat
  const pixelToBeat = useCallback(
    (px: number): number => {
      return (px + scrollLeft) / pixelsPerBeat;
    },
    [scrollLeft, pixelsPerBeat]
  );

  // Convert pixel to pitch
  const pixelToPitch = useCallback(
    (py: number): number => {
      const row = Math.floor((py + scrollTop) / rowHeight);
      return maxPitch - row;
    },
    [scrollTop, rowHeight, maxPitch]
  );

  // Draw grid
  const drawGrid = useCallback(() => {
    const canvas = gridCanvasRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const dpr = window.devicePixelRatio || 1;
    const width = canvas.width / dpr;
    const height = canvas.height / dpr;

    ctx.clearRect(0, 0, width, height);

    // Draw pitch rows
    for (let pitch = minPitch; pitch <= maxPitch; pitch++) {
      const y = (maxPitch - pitch) * rowHeight - scrollTop;
      if (y < -rowHeight || y > height) continue;

      const isBlack = isBlackKey(pitch);
      ctx.fillStyle = isBlack ? 'rgba(255, 255, 255, 0.02)' : 'rgba(255, 255, 255, 0.05)';
      ctx.fillRect(0, y, width, rowHeight);

      // Row separator
      ctx.strokeStyle = 'rgba(255, 255, 255, 0.05)';
      ctx.beginPath();
      ctx.moveTo(0, y + rowHeight);
      ctx.lineTo(width, y + rowHeight);
      ctx.stroke();

      // C note highlight
      if (pitch % 12 === 0) {
        ctx.strokeStyle = 'rgba(255, 255, 255, 0.15)';
        ctx.beginPath();
        ctx.moveTo(0, y + rowHeight);
        ctx.lineTo(width, y + rowHeight);
        ctx.stroke();
      }
    }

    // Draw beat lines
    for (let beat = 0; beat <= length; beat++) {
      const x = beat * pixelsPerBeat - scrollLeft;
      if (x < 0 || x > width) continue;

      const isBar = beat % beatsPerBar === 0;
      ctx.strokeStyle = isBar
        ? 'rgba(255, 255, 255, 0.2)'
        : 'rgba(255, 255, 255, 0.08)';
      ctx.lineWidth = isBar ? 1 : 0.5;

      ctx.beginPath();
      ctx.moveTo(x, 0);
      ctx.lineTo(x, height);
      ctx.stroke();
    }

    // Draw playhead
    if (playhead !== undefined) {
      const x = playhead * pixelsPerBeat - scrollLeft;
      if (x >= 0 && x <= width) {
        ctx.strokeStyle = '#ef4444';
        ctx.lineWidth = 2;
        ctx.beginPath();
        ctx.moveTo(x, 0);
        ctx.lineTo(x, height);
        ctx.stroke();
      }
    }
  }, [
    minPitch,
    maxPitch,
    length,
    beatsPerBar,
    pixelsPerBeat,
    rowHeight,
    scrollLeft,
    scrollTop,
    playhead,
  ]);

  // Draw notes
  const drawNotes = useCallback(() => {
    const canvas = notesCanvasRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const dpr = window.devicePixelRatio || 1;
    const width = canvas.width / dpr;
    const height = canvas.height / dpr;

    ctx.clearRect(0, 0, width, height);

    for (const note of notes) {
      const x = note.start * pixelsPerBeat - scrollLeft;
      const y = (maxPitch - note.pitch) * rowHeight - scrollTop;
      const w = note.duration * pixelsPerBeat;
      const h = rowHeight - 2;

      if (x + w < 0 || x > width || y + h < 0 || y > height) continue;

      const isSelected = selectedNotes.has(note.id);

      // Note body
      const alpha = note.velocity / 127;
      ctx.fillStyle = isSelected
        ? `rgba(129, 140, 248, ${0.5 + alpha * 0.5})`
        : `rgba(99, 102, 241, ${0.4 + alpha * 0.4})`;

      ctx.beginPath();
      ctx.roundRect(x + 1, y + 1, w - 2, h, 2);
      ctx.fill();

      // Note border
      ctx.strokeStyle = isSelected ? '#818cf8' : 'rgba(99, 102, 241, 0.8)';
      ctx.lineWidth = isSelected ? 2 : 1;
      ctx.stroke();

      // Velocity indicator (left bar)
      const velHeight = (note.velocity / 127) * h;
      ctx.fillStyle = isSelected ? '#a5b4fc' : '#818cf8';
      ctx.fillRect(x + 2, y + 1 + (h - velHeight), 3, velHeight);
    }
  }, [notes, selectedNotes, pixelsPerBeat, rowHeight, maxPitch, scrollLeft, scrollTop]);

  // Setup canvases
  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;

    const rect = container.getBoundingClientRect();
    const width = rect.width - keyboardWidth;
    const height = rect.height - (showVelocity ? velocityHeight : 0);
    const dpr = window.devicePixelRatio || 1;

    [gridCanvasRef, notesCanvasRef].forEach((ref) => {
      if (ref.current) {
        ref.current.width = width * dpr;
        ref.current.height = height * dpr;
        ref.current.style.width = `${width}px`;
        ref.current.style.height = `${height}px`;

        const ctx = ref.current.getContext('2d');
        if (ctx) ctx.scale(dpr, dpr);
      }
    });

    drawGrid();
    drawNotes();
  }, [keyboardWidth, showVelocity, velocityHeight, drawGrid, drawNotes]);

  // Mouse handlers
  const handleMouseDown = useCallback(
    (e: React.MouseEvent) => {
      const rect = (e.target as HTMLElement).getBoundingClientRect();
      const x = e.clientX - rect.left;
      const y = e.clientY - rect.top;

      const beat = snapToGrid(pixelToBeat(x));
      const pitch = pixelToPitch(y);

      // Check if clicking on existing note
      const clickedNote = notes.find((note) => {
        const noteX = note.start * pixelsPerBeat - scrollLeft;
        const noteY = (maxPitch - note.pitch) * rowHeight - scrollTop;
        const noteW = note.duration * pixelsPerBeat;
        const noteH = rowHeight;

        return x >= noteX && x <= noteX + noteW && y >= noteY && y <= noteY + noteH;
      });

      if (clickedNote) {
        // Select note
        if (e.shiftKey) {
          setSelectedNotes((prev) => {
            const next = new Set(prev);
            if (next.has(clickedNote.id)) {
              next.delete(clickedNote.id);
            } else {
              next.add(clickedNote.id);
            }
            return next;
          });
        } else {
          setSelectedNotes(new Set([clickedNote.id]));
        }
        setDragMode('move');
      } else {
        // Draw new note
        const newNote: MidiNote = {
          id: `note-${Date.now()}`,
          pitch,
          start: beat,
          duration: snap || 0.25,
          velocity: 100,
        };

        onChange?.([...notes, newNote]);
        setSelectedNotes(new Set([newNote.id]));
        setDragMode('resize');
      }

      setIsDragging(true);
    },
    [
      notes,
      onChange,
      pixelsPerBeat,
      rowHeight,
      maxPitch,
      scrollLeft,
      scrollTop,
      snap,
      snapToGrid,
      pixelToBeat,
      pixelToPitch,
    ]
  );

  const handleMouseUp = useCallback(() => {
    setIsDragging(false);
    onNoteSelect?.(Array.from(selectedNotes));
  }, [selectedNotes, onNoteSelect]);

  // Keyboard
  const renderKeyboard = useMemo(() => {
    const keys = [];

    for (let pitch = maxPitch; pitch >= minPitch; pitch--) {
      const isBlack = isBlackKey(pitch);
      const isC = pitch % 12 === 0;
      const y = (maxPitch - pitch) * rowHeight - scrollTop;

      keys.push(
        <div
          key={pitch}
          className={`piano-roll__key ${isBlack ? 'piano-roll__key--black' : 'piano-roll__key--white'}`}
          style={{ top: y, height: rowHeight }}
        >
          {isC && <span className="piano-roll__key-label">{getPitchName(pitch)}</span>}
        </div>
      );
    }

    return keys;
  }, [minPitch, maxPitch, rowHeight, scrollTop]);

  return (
    <div ref={containerRef} className={`piano-roll ${className}`}>
      <div className="piano-roll__keyboard" style={{ width: keyboardWidth }}>
        {renderKeyboard}
      </div>

      <div className="piano-roll__grid-area">
        <canvas ref={gridCanvasRef} className="piano-roll__grid-canvas" />
        <canvas
          ref={notesCanvasRef}
          className="piano-roll__notes-canvas"
          onMouseDown={handleMouseDown}
          onMouseUp={handleMouseUp}
        />
      </div>

      {showVelocity && (
        <div className="piano-roll__velocity" style={{ height: velocityHeight }}>
          <div className="piano-roll__velocity-label">Velocity</div>
          <div className="piano-roll__velocity-bars">
            {notes.map((note) => {
              const x = note.start * pixelsPerBeat - scrollLeft;
              const w = note.duration * pixelsPerBeat;
              const h = (note.velocity / 127) * (velocityHeight - 20);

              return (
                <div
                  key={note.id}
                  className={`piano-roll__velocity-bar ${
                    selectedNotes.has(note.id) ? 'piano-roll__velocity-bar--selected' : ''
                  }`}
                  style={{
                    left: x + keyboardWidth,
                    width: w - 2,
                    height: h,
                  }}
                />
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
}

// ============ usePianoRoll Hook ============

export function usePianoRoll(initialNotes: MidiNote[] = []) {
  const [notes, setNotes] = useState<MidiNote[]>(initialNotes);
  const [selectedNotes, setSelectedNotes] = useState<string[]>([]);

  const addNote = useCallback((note: Omit<MidiNote, 'id'>) => {
    const newNote: MidiNote = {
      ...note,
      id: `note-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
    };
    setNotes((prev) => [...prev, newNote]);
    return newNote.id;
  }, []);

  const removeNote = useCallback((id: string) => {
    setNotes((prev) => prev.filter((n) => n.id !== id));
    setSelectedNotes((prev) => prev.filter((nid) => nid !== id));
  }, []);

  const updateNote = useCallback((id: string, updates: Partial<MidiNote>) => {
    setNotes((prev) =>
      prev.map((n) => (n.id === id ? { ...n, ...updates } : n))
    );
  }, []);

  const clear = useCallback(() => {
    setNotes([]);
    setSelectedNotes([]);
  }, []);

  return {
    notes,
    setNotes,
    selectedNotes,
    setSelectedNotes,
    addNote,
    removeNote,
    updateNote,
    clear,
  };
}

export default PianoRoll;
