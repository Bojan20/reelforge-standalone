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
  /** Pre-computed waveform peaks (fallback) */
  waveform?: number[] | Float32Array;
  /** AudioBuffer for high-resolution LOD rendering (Cubase-style) */
  audioBuffer?: AudioBuffer;
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

// ============ Cubase-Style LOD Waveform Canvas ============

interface WaveformCanvasProps {
  /** Pre-computed waveform peaks (fallback) */
  waveform: number[] | Float32Array | undefined;
  /** AudioBuffer for high-resolution LOD rendering (Cubase-style) */
  audioBuffer?: AudioBuffer;
  width: number;
  height: number;
  color: string;
  zoom: number;
  scrollOffset: number;
  duration: number;
  selection: ClipEditorSelection | null;
  fadeIn: number;
  fadeOut: number;
  /** Number of audio channels to display */
  channels: number;
}

/**
 * Cubase-Style LOD Waveform Renderer
 *
 * Features:
 * - Direct AudioBuffer access for zoom-dependent detail
 * - Stereo channel display (split view)
 * - Min/Max peak envelope with RMS layer
 * - Clip detection (red highlights)
 * - Anti-aliased rendering at high zoom
 * - Automatic LOD based on zoom level
 */
const WaveformCanvas = memo(function WaveformCanvas({
  waveform,
  audioBuffer,
  width,
  height,
  color,
  zoom,
  scrollOffset,
  duration,
  selection,
  fadeIn,
  fadeOut,
  channels,
}: WaveformCanvasProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    // Set canvas size with DPI scaling for crisp rendering
    const dpr = window.devicePixelRatio || 1;
    canvas.width = width * dpr;
    canvas.height = height * dpr;
    ctx.scale(dpr, dpr);

    // Clear
    ctx.clearRect(0, 0, width, height);

    // Draw background
    const computedStyle = getComputedStyle(document.documentElement);
    const bgColor = computedStyle.getPropertyValue('--rf-bg-0').trim() || '#0a0a0c';
    ctx.fillStyle = bgColor;
    ctx.fillRect(0, 0, width, height);

    // Draw grid lines
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.08)';
    ctx.lineWidth = 1;

    // Vertical grid (time markers)
    const pixelsPerSecond = zoom;
    const endSecond = Math.ceil(scrollOffset + width / pixelsPerSecond);

    // Determine grid resolution based on zoom
    let gridStep = 1; // 1 second
    if (zoom > 200) gridStep = 0.1;
    else if (zoom > 50) gridStep = 0.5;

    for (let s = Math.floor(scrollOffset / gridStep) * gridStep; s <= endSecond; s += gridStep) {
      const x = (s - scrollOffset) * pixelsPerSecond;
      if (x >= 0 && x <= width) {
        ctx.globalAlpha = s % 1 === 0 ? 0.15 : 0.05;
        ctx.beginPath();
        ctx.moveTo(x, 0);
        ctx.lineTo(x, height);
        ctx.stroke();
      }
    }
    ctx.globalAlpha = 1;

    // Determine number of channels to render
    const numChannels = audioBuffer ? Math.min(audioBuffer.numberOfChannels, 2) : (channels > 1 ? 2 : 1);
    const channelHeight = height / numChannels;
    const channelPadding = numChannels > 1 ? 2 : 0;

    // Colors
    const waveformFill = computedStyle.getPropertyValue('--rf-waveform-fill').trim() || color;
    const waveformRms = computedStyle.getPropertyValue('--rf-waveform-rms').trim() || color;
    const waveformClip = computedStyle.getPropertyValue('--rf-waveform-clip').trim() || '#ff3366';

    // Draw center line for each channel
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.1)';
    for (let ch = 0; ch < numChannels; ch++) {
      const centerY = ch * channelHeight + channelHeight / 2;
      ctx.beginPath();
      ctx.moveTo(0, centerY);
      ctx.lineTo(width, centerY);
      ctx.stroke();
    }

    // Render each channel
    for (let ch = 0; ch < numChannels; ch++) {
      const channelTop = ch * channelHeight + channelPadding;
      const channelBottom = (ch + 1) * channelHeight - channelPadding;
      const centerY = (channelTop + channelBottom) / 2;
      const amplitude = (channelBottom - channelTop) / 2 - 2;

      // Get samples for this channel
      let samples: { peaks: number[]; rms: number[] };

      if (audioBuffer) {
        // LOD mode: Read directly from AudioBuffer
        samples = extractPeaksFromBuffer(
          audioBuffer,
          ch,
          scrollOffset,
          duration,
          width,
          fadeIn,
          fadeOut
        );
      } else if (waveform && waveform.length > 0) {
        // Fallback: Use pre-computed peaks (mono only)
        samples = extractPeaksFromWaveform(
          waveform,
          scrollOffset,
          duration,
          width,
          fadeIn,
          fadeOut
        );
      } else {
        continue; // No data
      }

      // Draw RMS layer (inner, brighter)
      ctx.fillStyle = waveformRms;
      ctx.globalAlpha = 0.9;

      for (let x = 0; x < width; x++) {
        const rms = samples.rms[x] || 0;
        const rmsHeight = rms * amplitude;
        if (rmsHeight > 0) {
          ctx.fillRect(x, centerY - rmsHeight, 1, Math.max(1, rmsHeight * 2));
        }
      }

      // Draw peak layer (outer, semi-transparent)
      ctx.fillStyle = waveformFill;
      ctx.globalAlpha = 0.5;

      for (let x = 0; x < width; x++) {
        const peak = samples.peaks[x * 2] || 0; // max
        const min = samples.peaks[x * 2 + 1] || 0; // min
        const rms = samples.rms[x] || 0;

        const peakTop = centerY - peak * amplitude;
        const peakBottom = centerY - min * amplitude;
        const rmsHeight = rms * amplitude;

        // Clip detection
        const isClipped = Math.abs(peak) >= 0.99 || Math.abs(min) >= 0.99;
        if (isClipped) {
          ctx.fillStyle = waveformClip;
          ctx.globalAlpha = 0.8;
        }

        // Draw peak above RMS
        if (peak * amplitude > rmsHeight) {
          ctx.fillRect(x, peakTop, 1, centerY - rmsHeight - peakTop);
        }
        if (Math.abs(min) * amplitude > rmsHeight) {
          ctx.fillRect(x, centerY + rmsHeight, 1, peakBottom - (centerY + rmsHeight));
        }

        if (isClipped) {
          ctx.fillStyle = waveformFill;
          ctx.globalAlpha = 0.5;
        }
      }

      // Channel separator line
      if (numChannels > 1 && ch < numChannels - 1) {
        ctx.strokeStyle = 'rgba(255, 255, 255, 0.15)';
        ctx.beginPath();
        ctx.moveTo(0, channelBottom + channelPadding);
        ctx.lineTo(width, channelBottom + channelPadding);
        ctx.stroke();
      }
    }

    // Draw selection
    if (selection) {
      const selStartX = (selection.start - scrollOffset) * zoom;
      const selEndX = (selection.end - scrollOffset) * zoom;

      if (selEndX > 0 && selStartX < width) {
        // Selection fill
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
    ctx.globalAlpha = 0.5;

    // Fade in
    if (fadeIn > 0) {
      const fadeInWidth = (fadeIn - scrollOffset) * zoom;
      if (fadeInWidth > 0) {
        const gradient = ctx.createLinearGradient(0, 0, Math.min(width, fadeInWidth), 0);
        gradient.addColorStop(0, 'rgba(0, 0, 0, 0.7)');
        gradient.addColorStop(1, 'transparent');
        ctx.fillStyle = gradient;
        ctx.fillRect(0, 0, Math.min(width, fadeInWidth), height);

        // Fade curve line
        ctx.strokeStyle = '#40c8ff';
        ctx.lineWidth = 1.5;
        ctx.beginPath();
        for (let x = 0; x <= Math.min(width, fadeInWidth); x++) {
          const t = x / fadeInWidth;
          const y = height - (t * t * height); // Exponential fade
          if (x === 0) ctx.moveTo(x, y);
          else ctx.lineTo(x, y);
        }
        ctx.stroke();
      }
    }

    // Fade out
    if (fadeOut > 0) {
      const fadeOutStart = (duration - fadeOut - scrollOffset) * zoom;
      const fadeOutEnd = (duration - scrollOffset) * zoom;
      if (fadeOutEnd > 0 && fadeOutStart < width) {
        const startX = Math.max(0, fadeOutStart);
        const endX = Math.min(width, fadeOutEnd);
        const gradient = ctx.createLinearGradient(startX, 0, endX, 0);
        gradient.addColorStop(0, 'transparent');
        gradient.addColorStop(1, 'rgba(0, 0, 0, 0.7)');
        ctx.fillStyle = gradient;
        ctx.fillRect(startX, 0, endX - startX, height);

        // Fade curve line
        ctx.strokeStyle = '#40c8ff';
        ctx.lineWidth = 1.5;
        ctx.beginPath();
        for (let x = startX; x <= endX; x++) {
          const t = (x - fadeOutStart) / (fadeOutEnd - fadeOutStart);
          const y = t * t * height; // Exponential fade
          if (x === startX) ctx.moveTo(x, y);
          else ctx.lineTo(x, y);
        }
        ctx.stroke();
      }
    }

    ctx.globalAlpha = 1;
  }, [waveform, audioBuffer, width, height, color, zoom, scrollOffset, duration, selection, fadeIn, fadeOut, channels]);

  return (
    <canvas
      ref={canvasRef}
      className="rf-clip-editor__waveform-canvas"
      style={{ width, height }}
    />
  );
});

/**
 * Extract peak data directly from AudioBuffer (LOD rendering)
 */
function extractPeaksFromBuffer(
  buffer: AudioBuffer,
  channel: number,
  scrollOffset: number,
  duration: number,
  width: number,
  fadeIn: number,
  fadeOut: number
): { peaks: number[]; rms: number[] } {
  const channelData = buffer.getChannelData(Math.min(channel, buffer.numberOfChannels - 1));
  const sampleRate = buffer.sampleRate;

  const visibleDuration = duration;
  const startTime = Math.max(0, scrollOffset);
  const endTime = Math.min(buffer.duration, scrollOffset + visibleDuration);

  const startSample = Math.floor(startTime * sampleRate);
  const endSample = Math.min(channelData.length, Math.floor(endTime * sampleRate));
  const totalSamples = endSample - startSample;

  const peaks: number[] = [];
  const rms: number[] = [];

  for (let x = 0; x < width; x++) {
    const sampleStart = startSample + Math.floor((x / width) * totalSamples);
    const sampleEnd = startSample + Math.floor(((x + 1) / width) * totalSamples);
    const samplesPerPixel = sampleEnd - sampleStart;

    let min = 0;
    let max = 0;
    let sumSquares = 0;

    for (let i = sampleStart; i < sampleEnd && i < channelData.length; i++) {
      const val = channelData[i];
      if (val < min) min = val;
      if (val > max) max = val;
      sumSquares += val * val;
    }

    // Apply fade envelope
    const time = (sampleStart / sampleRate);
    let envelope = 1;
    if (fadeIn > 0 && time < fadeIn) {
      envelope = time / fadeIn;
    } else if (fadeOut > 0 && time > buffer.duration - fadeOut) {
      envelope = (buffer.duration - time) / fadeOut;
    }

    max *= envelope;
    min *= envelope;

    peaks.push(max, min);
    rms.push(samplesPerPixel > 0 ? Math.sqrt(sumSquares / samplesPerPixel) * envelope : 0);
  }

  return { peaks, rms };
}

/**
 * Extract peak data from pre-computed waveform (fallback)
 */
function extractPeaksFromWaveform(
  waveform: number[] | Float32Array,
  scrollOffset: number,
  duration: number,
  width: number,
  fadeIn: number,
  fadeOut: number
): { peaks: number[]; rms: number[] } {
  const peaks: number[] = [];
  const rms: number[] = [];

  const samplesPerSecond = waveform.length / duration;
  const startSample = Math.floor(scrollOffset * samplesPerSecond);
  const visibleSamples = Math.ceil(duration * samplesPerSecond);
  const samplesPerPixel = Math.max(1, Math.ceil(visibleSamples / width));

  for (let x = 0; x < width; x++) {
    const sampleStart = startSample + Math.floor((x / width) * visibleSamples);
    const sampleEnd = Math.min(sampleStart + samplesPerPixel, waveform.length);

    let max = 0;
    let sumSquares = 0;
    let count = 0;

    for (let i = sampleStart; i < sampleEnd; i++) {
      const val = Math.abs(waveform[i] || 0);
      if (val > max) max = val;
      sumSquares += val * val;
      count++;
    }

    // Apply fade envelope
    const time = (sampleStart / waveform.length) * duration;
    let envelope = 1;
    if (fadeIn > 0 && time < fadeIn) {
      envelope = time / fadeIn;
    } else if (fadeOut > 0 && time > duration - fadeOut) {
      envelope = (duration - time) / fadeOut;
    }

    // Pre-computed waveform is usually unsigned (0-1), mirror for display
    peaks.push(max * envelope, -max * envelope);
    rms.push(count > 0 ? Math.sqrt(sumSquares / count) * envelope : 0);
  }

  return { peaks, rms };
}

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
            audioBuffer={clip.audioBuffer}
            width={containerSize.width}
            height={containerSize.height}
            color={clip.color || '#4a9eff'}
            zoom={zoom}
            scrollOffset={scrollOffset}
            duration={clip.duration}
            selection={selection}
            fadeIn={clip.fadeIn}
            fadeOut={clip.fadeOut}
            channels={clip.channels}
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
