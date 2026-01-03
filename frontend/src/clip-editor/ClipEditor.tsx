/**
 * ReelForge Clip Editor
 *
 * Audio clip editing component with:
 * - Trim handles (left/right edges)
 * - Fade in/out handles
 * - Waveform display
 * - Gain adjustment
 * - Selection and multi-edit
 *
 * @module clip-editor/ClipEditor
 */

import { useState, useCallback, useRef, useMemo } from 'react';
import './ClipEditor.css';

// ============ Types ============

export type FadeCurve = 'linear' | 'exponential' | 'logarithmic' | 's-curve';

export interface ClipData {
  id: string;
  name: string;
  startTime: number;
  duration: number;
  sourceOffset: number;
  sourceDuration: number;
  color: string;
  gain: number;
  fadeInDuration: number;
  fadeOutDuration: number;
  fadeInCurve: FadeCurve;
  fadeOutCurve: FadeCurve;
  muted: boolean;
  locked: boolean;
  waveformData?: Float32Array;
}

export interface ClipEditorProps {
  /** Clip data */
  clip: ClipData;
  /** Track height in pixels */
  trackHeight: number;
  /** Pixels per second */
  pixelsPerSecond: number;
  /** Is selected */
  selected?: boolean;
  /** Snap enabled */
  snapEnabled?: boolean;
  /** Snap resolution in seconds */
  snapResolution?: number;
  /** On clip change */
  onChange?: (updates: Partial<ClipData>) => void;
  /** On clip click */
  onClick?: (e: React.MouseEvent) => void;
  /** On clip double click */
  onDoubleClick?: (e: React.MouseEvent) => void;
  /** On context menu */
  onContextMenu?: (e: React.MouseEvent) => void;
}

type DragMode = 'none' | 'move' | 'trim-left' | 'trim-right' | 'fade-in' | 'fade-out' | 'gain';

// ============ Helpers ============

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

function generateFadePath(
  width: number,
  height: number,
  curve: FadeCurve,
  isIn: boolean
): string {
  const points: string[] = [];
  const steps = 20;

  for (let i = 0; i <= steps; i++) {
    const t = i / steps;
    let y: number;

    switch (curve) {
      case 'exponential':
        y = isIn ? t * t : 1 - (1 - t) * (1 - t);
        break;
      case 'logarithmic':
        y = isIn ? Math.sqrt(t) : 1 - Math.sqrt(1 - t);
        break;
      case 's-curve':
        y = t * t * (3 - 2 * t);
        break;
      case 'linear':
      default:
        y = t;
    }

    const x = isIn ? t * width : t * width;
    const yPos = isIn ? (1 - y) * height : y * height;
    points.push(`${i === 0 ? 'M' : 'L'} ${x} ${yPos}`);
  }

  // Close the path
  if (isIn) {
    points.push(`L ${width} ${height}`);
    points.push(`L 0 ${height}`);
  } else {
    points.push(`L ${width} ${height}`);
    points.push(`L 0 ${height}`);
  }
  points.push('Z');

  return points.join(' ');
}

// ============ Component ============

export function ClipEditor({
  clip,
  trackHeight,
  pixelsPerSecond,
  selected = false,
  snapEnabled = true,
  snapResolution = 0.125,
  onChange,
  onClick,
  onDoubleClick,
  onContextMenu,
}: ClipEditorProps) {
  const [dragMode, setDragMode] = useState<DragMode>('none');
  const [isHovering, setIsHovering] = useState(false);

  const clipRef = useRef<HTMLDivElement>(null);
  const dragStartRef = useRef({
    x: 0,
    y: 0,
    startTime: 0,
    duration: 0,
    sourceOffset: 0,
    fadeIn: 0,
    fadeOut: 0,
    gain: 0,
  });

  // Calculated dimensions
  const clipWidth = clip.duration * pixelsPerSecond;
  const clipLeft = clip.startTime * pixelsPerSecond;
  const fadeInWidth = clip.fadeInDuration * pixelsPerSecond;
  const fadeOutWidth = clip.fadeOutDuration * pixelsPerSecond;
  const contentHeight = trackHeight - 8; // Padding

  // Snap helper
  const snapTime = useCallback(
    (time: number): number => {
      if (!snapEnabled) return time;
      return Math.round(time / snapResolution) * snapResolution;
    },
    [snapEnabled, snapResolution]
  );

  // Handle drag start
  const handleDragStart = useCallback(
    (e: React.MouseEvent, mode: DragMode) => {
      if (clip.locked) return;
      e.preventDefault();
      e.stopPropagation();

      setDragMode(mode);
      dragStartRef.current = {
        x: e.clientX,
        y: e.clientY,
        startTime: clip.startTime,
        duration: clip.duration,
        sourceOffset: clip.sourceOffset,
        fadeIn: clip.fadeInDuration,
        fadeOut: clip.fadeOutDuration,
        gain: clip.gain,
      };

      const handleMouseMove = (e: MouseEvent) => {
        const deltaX = e.clientX - dragStartRef.current.x;
        const deltaY = e.clientY - dragStartRef.current.y;
        const deltaTime = deltaX / pixelsPerSecond;

        switch (mode) {
          case 'move': {
            const newStart = snapTime(dragStartRef.current.startTime + deltaTime);
            onChange?.({ startTime: Math.max(0, newStart) });
            break;
          }

          case 'trim-left': {
            const maxTrim = dragStartRef.current.duration - 0.1;
            const trimAmount = clamp(deltaTime, -dragStartRef.current.sourceOffset, maxTrim);
            const snappedTrim = snapTime(trimAmount);

            onChange?.({
              startTime: dragStartRef.current.startTime + snappedTrim,
              duration: dragStartRef.current.duration - snappedTrim,
              sourceOffset: dragStartRef.current.sourceOffset + snappedTrim,
            });
            break;
          }

          case 'trim-right': {
            const maxDuration = clip.sourceDuration - clip.sourceOffset;
            const newDuration = clamp(
              dragStartRef.current.duration + deltaTime,
              0.1,
              maxDuration
            );
            onChange?.({ duration: snapTime(newDuration) });
            break;
          }

          case 'fade-in': {
            const maxFade = clip.duration - clip.fadeOutDuration - 0.05;
            const newFade = clamp(dragStartRef.current.fadeIn + deltaTime, 0, maxFade);
            onChange?.({ fadeInDuration: snapTime(newFade) });
            break;
          }

          case 'fade-out': {
            const maxFade = clip.duration - clip.fadeInDuration - 0.05;
            const newFade = clamp(dragStartRef.current.fadeOut - deltaTime, 0, maxFade);
            onChange?.({ fadeOutDuration: snapTime(newFade) });
            break;
          }

          case 'gain': {
            // Vertical drag for gain (-60dB to +12dB range)
            const gainDelta = -deltaY * 0.5; // dB per pixel
            const newGain = clamp(dragStartRef.current.gain + gainDelta, -60, 12);
            onChange?.({ gain: Math.round(newGain * 10) / 10 });
            break;
          }
        }
      };

      const handleMouseUp = () => {
        setDragMode('none');
        window.removeEventListener('mousemove', handleMouseMove);
        window.removeEventListener('mouseup', handleMouseUp);
      };

      window.addEventListener('mousemove', handleMouseMove);
      window.addEventListener('mouseup', handleMouseUp);
    },
    [clip, pixelsPerSecond, snapTime, onChange]
  );

  // Render waveform
  const waveformPath = useMemo(() => {
    if (!clip.waveformData || clip.waveformData.length === 0) {
      return null;
    }

    const data = clip.waveformData;
    const samplesPerPixel = data.length / clipWidth;
    const midY = contentHeight / 2;
    const amplitude = contentHeight / 2 - 2;

    let path = `M 0 ${midY}`;

    for (let x = 0; x < clipWidth; x++) {
      const sampleIndex = Math.floor(x * samplesPerPixel);
      const sample = data[Math.min(sampleIndex, data.length - 1)] || 0;
      const y = midY - sample * amplitude;
      path += ` L ${x} ${y}`;
    }

    // Mirror for bottom half
    for (let x = clipWidth - 1; x >= 0; x--) {
      const sampleIndex = Math.floor(x * samplesPerPixel);
      const sample = data[Math.min(sampleIndex, data.length - 1)] || 0;
      const y = midY + sample * amplitude;
      path += ` L ${x} ${y}`;
    }

    path += ' Z';
    return path;
  }, [clip.waveformData, clipWidth, contentHeight]);

  // Cursor based on position
  const getCursor = useCallback((mode: DragMode): string => {
    switch (mode) {
      case 'move':
        return 'move';
      case 'trim-left':
      case 'trim-right':
        return 'ew-resize';
      case 'fade-in':
      case 'fade-out':
        return 'col-resize';
      case 'gain':
        return 'ns-resize';
      default:
        return 'default';
    }
  }, []);

  return (
    <div
      ref={clipRef}
      className={`clip-editor ${selected ? 'clip-editor--selected' : ''} ${
        clip.muted ? 'clip-editor--muted' : ''
      } ${clip.locked ? 'clip-editor--locked' : ''} ${
        dragMode !== 'none' ? 'clip-editor--dragging' : ''
      }`}
      style={{
        left: clipLeft,
        width: clipWidth,
        height: contentHeight,
        backgroundColor: clip.color,
        cursor: getCursor(dragMode),
      }}
      onClick={onClick}
      onDoubleClick={onDoubleClick}
      onContextMenu={onContextMenu}
      onMouseEnter={() => setIsHovering(true)}
      onMouseLeave={() => setIsHovering(false)}
    >
      {/* Waveform */}
      <svg className="clip-editor__waveform" width={clipWidth} height={contentHeight}>
        {waveformPath && (
          <path
            d={waveformPath}
            fill="rgba(255, 255, 255, 0.3)"
            stroke="rgba(255, 255, 255, 0.5)"
            strokeWidth={0.5}
          />
        )}

        {/* Fade In */}
        {fadeInWidth > 0 && (
          <path
            d={generateFadePath(fadeInWidth, contentHeight, clip.fadeInCurve, true)}
            fill="rgba(0, 0, 0, 0.4)"
            className="clip-editor__fade-in"
          />
        )}

        {/* Fade Out */}
        {fadeOutWidth > 0 && (
          <g transform={`translate(${clipWidth - fadeOutWidth}, 0)`}>
            <path
              d={generateFadePath(fadeOutWidth, contentHeight, clip.fadeOutCurve, false)}
              fill="rgba(0, 0, 0, 0.4)"
              className="clip-editor__fade-out"
            />
          </g>
        )}
      </svg>

      {/* Clip Name */}
      <div className="clip-editor__name">
        {clip.name}
        {clip.gain !== 0 && (
          <span className="clip-editor__gain">
            {clip.gain > 0 ? '+' : ''}{clip.gain.toFixed(1)} dB
          </span>
        )}
      </div>

      {/* Trim Handles */}
      {!clip.locked && (isHovering || selected) && (
        <>
          <div
            className="clip-editor__handle clip-editor__handle--left"
            onMouseDown={(e) => handleDragStart(e, 'trim-left')}
          />
          <div
            className="clip-editor__handle clip-editor__handle--right"
            onMouseDown={(e) => handleDragStart(e, 'trim-right')}
          />
        </>
      )}

      {/* Fade Handles */}
      {!clip.locked && (isHovering || selected) && (
        <>
          <div
            className="clip-editor__fade-handle clip-editor__fade-handle--in"
            style={{ left: fadeInWidth - 6 }}
            onMouseDown={(e) => handleDragStart(e, 'fade-in')}
          />
          <div
            className="clip-editor__fade-handle clip-editor__fade-handle--out"
            style={{ right: fadeOutWidth - 6 }}
            onMouseDown={(e) => handleDragStart(e, 'fade-out')}
          />
        </>
      )}

      {/* Move area (center) */}
      <div
        className="clip-editor__move-area"
        onMouseDown={(e) => handleDragStart(e, 'move')}
      />

      {/* Selection outline */}
      {selected && <div className="clip-editor__selection" />}

      {/* Muted overlay */}
      {clip.muted && <div className="clip-editor__muted-overlay" />}

      {/* Locked indicator */}
      {clip.locked && (
        <div className="clip-editor__locked-indicator">🔒</div>
      )}
    </div>
  );
}

export default ClipEditor;
