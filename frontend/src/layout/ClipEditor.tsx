/**
 * ReelForge Clip Editor
 *
 * Lower zone component for detailed audio clip editing:
 * - Zoomable waveform display
 * - Selection tool for range selection
 * - Fade in/out handles
 * - Clip info sidebar (duration, sample rate, etc.)
 * - Audio processing tools
 *
 * @module layout/ClipEditor
 */

import { memo, useRef, useEffect, useCallback, useState } from 'react';

// ============ Types ============

export interface ClipEditorClip {
  id: string;
  name: string;
  duration: number;
  sampleRate: number;
  channels: number;
  bitDepth: number;
  waveform?: number[] | Float32Array;
  fadeIn: number;
  fadeOut: number;
  gain: number;
  color?: string;
}

export interface ClipEditorSelection {
  start: number; // in seconds
  end: number;
}

export interface ClipEditorProps {
  /** Currently selected clip to edit */
  clip: ClipEditorClip | null;
  /** Current selection range */
  selection?: ClipEditorSelection | null;
  /** Zoom level (pixels per second) */
  zoom?: number;
  /** Scroll offset in seconds */
  scrollOffset?: number;
  /** On selection change */
  onSelectionChange?: (selection: ClipEditorSelection | null) => void;
  /** On zoom change */
  onZoomChange?: (zoom: number) => void;
  /** On scroll change */
  onScrollChange?: (offset: number) => void;
  /** On fade in change */
  onFadeInChange?: (clipId: string, fadeIn: number) => void;
  /** On fade out change */
  onFadeOutChange?: (clipId: string, fadeOut: number) => void;
  /** On gain change */
  onGainChange?: (clipId: string, gain: number) => void;
  /** On normalize */
  onNormalize?: (clipId: string) => void;
  /** On reverse */
  onReverse?: (clipId: string) => void;
  /** On trim to selection */
  onTrimToSelection?: (clipId: string, selection: ClipEditorSelection) => void;
}

// ============ Tool Types ============

type EditorTool = 'select' | 'zoom' | 'fade' | 'cut';

// ============ Waveform Canvas ============

interface WaveformCanvasProps {
  waveform: number[] | Float32Array | undefined;
  width: number;
  height: number;
  color: string;
  zoom: number;
  scrollOffset: number;
  duration: number;
  selection: ClipEditorSelection | null;
  fadeIn: number;
  fadeOut: number;
}

const WaveformCanvas = memo(function WaveformCanvas({
  waveform,
  width,
  height,
  color,
  zoom,
  scrollOffset,
  duration,
  selection,
  fadeIn,
  fadeOut,
}: WaveformCanvasProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas || !waveform || waveform.length === 0) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    // Set canvas size with DPI scaling
    const dpr = window.devicePixelRatio || 1;
    canvas.width = width * dpr;
    canvas.height = height * dpr;
    ctx.scale(dpr, dpr);

    // Clear
    ctx.clearRect(0, 0, width, height);

    // Draw background
    ctx.fillStyle = 'var(--rf-bg-0)';
    ctx.fillRect(0, 0, width, height);

    // Draw grid lines
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.05)';
    ctx.lineWidth = 1;

    // Horizontal center line
    ctx.beginPath();
    ctx.moveTo(0, height / 2);
    ctx.lineTo(width, height / 2);
    ctx.stroke();

    // Vertical grid (every second)
    const pixelsPerSecond = zoom;
    const startSecond = Math.floor(scrollOffset);
    const endSecond = Math.ceil(scrollOffset + width / pixelsPerSecond);

    for (let s = startSecond; s <= endSecond; s++) {
      const x = (s - scrollOffset) * pixelsPerSecond;
      if (x >= 0 && x <= width) {
        ctx.beginPath();
        ctx.moveTo(x, 0);
        ctx.lineTo(x, height);
        ctx.stroke();
      }
    }

    // Calculate visible portion of waveform
    const samplesPerPixel = Math.max(1, Math.floor(waveform.length / (duration * zoom)));
    const startSample = Math.floor((scrollOffset / duration) * waveform.length);
    const visibleSamples = Math.ceil((width / zoom) * (waveform.length / duration));

    // Draw waveform
    ctx.fillStyle = color;
    ctx.globalAlpha = 0.8;

    const centerY = height / 2;
    const maxAmplitude = height / 2 - 4;

    for (let px = 0; px < width; px++) {
      const sampleIndex = startSample + Math.floor((px / width) * visibleSamples);
      if (sampleIndex < 0 || sampleIndex >= waveform.length) continue;

      // Get min/max for this pixel column
      let min = 0;
      let max = 0;
      const endSample = Math.min(sampleIndex + samplesPerPixel, waveform.length);

      for (let i = sampleIndex; i < endSample; i++) {
        const sample = waveform[i];
        if (sample < min) min = sample;
        if (sample > max) max = sample;
      }

      // Apply fade envelope
      const time = (sampleIndex / waveform.length) * duration;
      let envelope = 1;
      if (time < fadeIn) {
        envelope = time / fadeIn;
      } else if (time > duration - fadeOut) {
        envelope = (duration - time) / fadeOut;
      }

      min *= envelope;
      max *= envelope;

      const y1 = centerY - max * maxAmplitude;
      const y2 = centerY - min * maxAmplitude;
      const barHeight = Math.max(1, y2 - y1);

      ctx.fillRect(px, y1, 1, barHeight);
    }

    // Draw selection
    if (selection) {
      const selStartX = (selection.start - scrollOffset) * zoom;
      const selEndX = (selection.end - scrollOffset) * zoom;

      if (selEndX > 0 && selStartX < width) {
        ctx.globalAlpha = 0.2;
        ctx.fillStyle = '#0ea5e9';
        ctx.fillRect(
          Math.max(0, selStartX),
          0,
          Math.min(width, selEndX) - Math.max(0, selStartX),
          height
        );

        // Selection borders
        ctx.globalAlpha = 1;
        ctx.strokeStyle = '#0ea5e9';
        ctx.lineWidth = 2;

        if (selStartX >= 0 && selStartX <= width) {
          ctx.beginPath();
          ctx.moveTo(selStartX, 0);
          ctx.lineTo(selStartX, height);
          ctx.stroke();
        }

        if (selEndX >= 0 && selEndX <= width) {
          ctx.beginPath();
          ctx.moveTo(selEndX, 0);
          ctx.lineTo(selEndX, height);
          ctx.stroke();
        }
      }
    }

    // Draw fade overlays
    ctx.globalAlpha = 0.4;

    // Fade in
    if (fadeIn > 0) {
      const fadeInX = fadeIn * zoom;
      const gradient = ctx.createLinearGradient(0, 0, fadeInX, 0);
      gradient.addColorStop(0, 'rgba(0, 0, 0, 0.6)');
      gradient.addColorStop(1, 'transparent');
      ctx.fillStyle = gradient;
      ctx.fillRect(0, 0, fadeInX, height);
    }

    // Fade out
    if (fadeOut > 0) {
      const fadeOutStartX = (duration - fadeOut - scrollOffset) * zoom;
      const fadeOutEndX = (duration - scrollOffset) * zoom;
      const gradient = ctx.createLinearGradient(fadeOutStartX, 0, fadeOutEndX, 0);
      gradient.addColorStop(0, 'transparent');
      gradient.addColorStop(1, 'rgba(0, 0, 0, 0.6)');
      ctx.fillStyle = gradient;
      ctx.fillRect(fadeOutStartX, 0, fadeOutEndX - fadeOutStartX, height);
    }

    ctx.globalAlpha = 1;
  }, [waveform, width, height, color, zoom, scrollOffset, duration, selection, fadeIn, fadeOut]);

  return (
    <canvas
      ref={canvasRef}
      className="rf-clip-editor__waveform-canvas"
      style={{ width, height }}
    />
  );
});

// ============ Toolbar ============

interface ToolbarProps {
  tool: EditorTool;
  onToolChange: (tool: EditorTool) => void;
  hasSelection: boolean;
  onNormalize?: () => void;
  onReverse?: () => void;
  onTrimToSelection?: () => void;
}

const Toolbar = memo(function Toolbar({
  tool,
  onToolChange,
  hasSelection,
  onNormalize,
  onReverse,
  onTrimToSelection,
}: ToolbarProps) {
  const tools: { id: EditorTool; icon: string; label: string }[] = [
    { id: 'select', icon: '⬚', label: 'Selection' },
    { id: 'zoom', icon: '🔍', label: 'Zoom' },
    { id: 'fade', icon: '⟋', label: 'Fade' },
    { id: 'cut', icon: '✂', label: 'Cut' },
  ];

  return (
    <div className="rf-clip-editor__tools">
      {tools.map((t) => (
        <button
          key={t.id}
          className={`rf-clip-editor__tool-btn ${tool === t.id ? 'active' : ''}`}
          onClick={() => onToolChange(t.id)}
          title={t.label}
        >
          {t.icon}
        </button>
      ))}

      <div style={{ width: 1, height: 16, background: 'var(--rf-border)', margin: '0 4px' }} />

      <button
        className="rf-clip-editor__tool-btn"
        onClick={onNormalize}
        title="Normalize"
      >
        📊
      </button>
      <button
        className="rf-clip-editor__tool-btn"
        onClick={onReverse}
        title="Reverse"
      >
        ⇆
      </button>
      <button
        className="rf-clip-editor__tool-btn"
        onClick={onTrimToSelection}
        disabled={!hasSelection}
        title="Trim to Selection"
        style={{ opacity: hasSelection ? 1 : 0.5 }}
      >
        ⊞
      </button>
    </div>
  );
});

// ============ Info Sidebar ============

interface InfoSidebarProps {
  clip: ClipEditorClip;
  selection: ClipEditorSelection | null;
  onFadeInChange?: (fadeIn: number) => void;
  onFadeOutChange?: (fadeOut: number) => void;
  onGainChange?: (gain: number) => void;
}

const InfoSidebar = memo(function InfoSidebar({
  clip,
  selection,
  onFadeInChange,
  onFadeOutChange,
  onGainChange,
}: InfoSidebarProps) {
  const formatTime = (seconds: number): string => {
    const mins = Math.floor(seconds / 60);
    const secs = seconds % 60;
    return `${mins}:${secs.toFixed(3).padStart(6, '0')}`;
  };

  return (
    <div className="rf-clip-editor__sidebar">
      {/* Clip Info */}
      <div className="rf-clip-editor__info">
        <div className="rf-clip-editor__info-label">Duration</div>
        <div className="rf-clip-editor__info-value">{formatTime(clip.duration)}</div>
      </div>

      <div className="rf-clip-editor__info">
        <div className="rf-clip-editor__info-label">Sample Rate</div>
        <div className="rf-clip-editor__info-value">{clip.sampleRate / 1000} kHz</div>
      </div>

      <div className="rf-clip-editor__info">
        <div className="rf-clip-editor__info-label">Channels</div>
        <div className="rf-clip-editor__info-value">{clip.channels === 2 ? 'Stereo' : 'Mono'}</div>
      </div>

      <div className="rf-clip-editor__info">
        <div className="rf-clip-editor__info-label">Bit Depth</div>
        <div className="rf-clip-editor__info-value">{clip.bitDepth}-bit</div>
      </div>

      {/* Selection Info */}
      {selection && (
        <>
          <div style={{ height: 1, background: 'var(--rf-border)', margin: '12px 0' }} />
          <div className="rf-clip-editor__info">
            <div className="rf-clip-editor__info-label">Selection</div>
            <div className="rf-clip-editor__info-value">
              {formatTime(selection.start)} → {formatTime(selection.end)}
            </div>
          </div>
          <div className="rf-clip-editor__info">
            <div className="rf-clip-editor__info-label">Length</div>
            <div className="rf-clip-editor__info-value">
              {formatTime(selection.end - selection.start)}
            </div>
          </div>
        </>
      )}

      {/* Fades */}
      <div style={{ height: 1, background: 'var(--rf-border)', margin: '12px 0' }} />

      <div className="rf-clip-editor__info">
        <div className="rf-clip-editor__info-label">Fade In</div>
        <input
          type="range"
          min={0}
          max={clip.duration / 2}
          step={0.01}
          value={clip.fadeIn}
          onChange={(e) => onFadeInChange?.(parseFloat(e.target.value))}
          style={{ width: '100%' }}
        />
        <div className="rf-clip-editor__info-value">{clip.fadeIn.toFixed(2)}s</div>
      </div>

      <div className="rf-clip-editor__info">
        <div className="rf-clip-editor__info-label">Fade Out</div>
        <input
          type="range"
          min={0}
          max={clip.duration / 2}
          step={0.01}
          value={clip.fadeOut}
          onChange={(e) => onFadeOutChange?.(parseFloat(e.target.value))}
          style={{ width: '100%' }}
        />
        <div className="rf-clip-editor__info-value">{clip.fadeOut.toFixed(2)}s</div>
      </div>

      {/* Gain */}
      <div className="rf-clip-editor__info">
        <div className="rf-clip-editor__info-label">Gain</div>
        <input
          type="range"
          min={-24}
          max={12}
          step={0.1}
          value={clip.gain}
          onChange={(e) => onGainChange?.(parseFloat(e.target.value))}
          style={{ width: '100%' }}
        />
        <div className="rf-clip-editor__info-value">
          {clip.gain >= 0 ? '+' : ''}{clip.gain.toFixed(1)} dB
        </div>
      </div>
    </div>
  );
});

// ============ Clip Editor Component ============

export const ClipEditor = memo(function ClipEditor({
  clip,
  selection = null,
  zoom = 100,
  scrollOffset = 0,
  onSelectionChange,
  onZoomChange,
  onScrollChange,
  onFadeInChange,
  onFadeOutChange,
  onGainChange,
  onNormalize,
  onReverse,
  onTrimToSelection,
}: ClipEditorProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const [containerSize, setContainerSize] = useState({ width: 800, height: 200 });
  const [tool, setTool] = useState<EditorTool>('select');
  const [isDragging, setIsDragging] = useState(false);
  const [dragStart, setDragStart] = useState<number | null>(null);

  // Measure container
  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;

    const observer = new ResizeObserver((entries) => {
      for (const entry of entries) {
        setContainerSize({
          width: entry.contentRect.width,
          height: entry.contentRect.height,
        });
      }
    });

    observer.observe(container);
    return () => observer.disconnect();
  }, []);

  // Mouse handlers for selection
  const handleMouseDown = useCallback((e: React.MouseEvent) => {
    if (tool !== 'select' || !clip) return;

    const rect = e.currentTarget.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const time = scrollOffset + x / zoom;

    setIsDragging(true);
    setDragStart(time);
    onSelectionChange?.({ start: time, end: time });
  }, [tool, clip, scrollOffset, zoom, onSelectionChange]);

  const handleMouseMove = useCallback((e: React.MouseEvent) => {
    if (!isDragging || dragStart === null || !clip) return;

    const rect = e.currentTarget.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const time = Math.max(0, Math.min(clip.duration, scrollOffset + x / zoom));

    onSelectionChange?.({
      start: Math.min(dragStart, time),
      end: Math.max(dragStart, time),
    });
  }, [isDragging, dragStart, clip, scrollOffset, zoom, onSelectionChange]);

  const handleMouseUp = useCallback(() => {
    setIsDragging(false);
    setDragStart(null);
  }, []);

  // Wheel handler for zoom/scroll
  const handleWheel = useCallback((e: React.WheelEvent) => {
    e.preventDefault();

    if (e.ctrlKey || e.metaKey) {
      // Zoom
      const delta = e.deltaY > 0 ? 0.9 : 1.1;
      const newZoom = Math.max(10, Math.min(500, zoom * delta));
      onZoomChange?.(newZoom);
    } else {
      // Scroll
      const delta = e.deltaX !== 0 ? e.deltaX : e.deltaY;
      const newOffset = Math.max(0, scrollOffset + delta / zoom);
      onScrollChange?.(newOffset);
    }
  }, [zoom, scrollOffset, onZoomChange, onScrollChange]);

  if (!clip) {
    return (
      <div className="rf-clip-editor">
        <div className="rf-clip-editor__header">
          <div className="rf-clip-editor__title">
            <span>✏️</span>
            <span>Clip Editor</span>
          </div>
        </div>
        <div className="rf-clip-editor__empty">
          <span className="rf-clip-editor__empty-icon">🎵</span>
          <span>Select a clip to edit</span>
        </div>
      </div>
    );
  }

  return (
    <div className="rf-clip-editor">
      {/* Header */}
      <div className="rf-clip-editor__header">
        <div className="rf-clip-editor__title">
          <span>✏️</span>
          <span>{clip.name}</span>
        </div>
        <Toolbar
          tool={tool}
          onToolChange={setTool}
          hasSelection={selection !== null && selection.end > selection.start}
          onNormalize={() => onNormalize?.(clip.id)}
          onReverse={() => onReverse?.(clip.id)}
          onTrimToSelection={() => selection && onTrimToSelection?.(clip.id, selection)}
        />
      </div>

      {/* Content */}
      <div className="rf-clip-editor__content">
        {/* Waveform Area */}
        <div
          ref={containerRef}
          className="rf-clip-editor__waveform"
          onMouseDown={handleMouseDown}
          onMouseMove={handleMouseMove}
          onMouseUp={handleMouseUp}
          onMouseLeave={handleMouseUp}
          onWheel={handleWheel}
        >
          <WaveformCanvas
            waveform={clip.waveform}
            width={containerSize.width}
            height={containerSize.height}
            color={clip.color || '#4a9eff'}
            zoom={zoom}
            scrollOffset={scrollOffset}
            duration={clip.duration}
            selection={selection}
            fadeIn={clip.fadeIn}
            fadeOut={clip.fadeOut}
          />
        </div>

        {/* Info Sidebar */}
        <InfoSidebar
          clip={clip}
          selection={selection}
          onFadeInChange={(v) => onFadeInChange?.(clip.id, v)}
          onFadeOutChange={(v) => onFadeOutChange?.(clip.id, v)}
          onGainChange={(v) => onGainChange?.(clip.id, v)}
        />
      </div>
    </div>
  );
});

export default ClipEditor;
