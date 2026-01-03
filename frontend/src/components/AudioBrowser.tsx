/**
 * AudioBrowser Component
 *
 * Cubase MediaBay-inspired audio browser with:
 * - Waveform preview before import
 * - Pre-listen functionality (play without importing)
 * - Filter by format, duration, sample rate
 * - Drag and drop support
 *
 * @module components/AudioBrowser
 */

import { useState, useCallback, useRef, useEffect, useMemo, memo } from 'react';
import './AudioBrowser.css';
import { useDraggable, type DragItem } from '../core/dragDropSystem';

// ============ Types ============

export interface AudioFileInfo {
  /** Unique ID */
  id: string;
  /** File name */
  name: string;
  /** File object (for import) */
  file: File;
  /** Duration in seconds */
  duration: number;
  /** Sample rate */
  sampleRate: number;
  /** Number of channels */
  channels: number;
  /** File format (mp3, wav, etc) */
  format: string;
  /** File size in bytes */
  size: number;
  /** Waveform data for visualization */
  waveform: number[];
  /** Detected BPM (if loop) */
  bpm?: number;
  /** Is this a loop? */
  isLoop?: boolean;
}

export interface AudioBrowserProps {
  /** Pre-loaded files to display */
  files?: AudioFileInfo[];
  /** Called when user imports selected files */
  onImport?: (files: AudioFileInfo[]) => void;
  /** Called when user starts preview */
  onPreviewStart?: (file: AudioFileInfo) => void;
  /** Called when user stops preview */
  onPreviewStop?: () => void;
  /** Show import button */
  showImport?: boolean;
  /** Allow multiple selection */
  multiSelect?: boolean;
  /** Custom class */
  className?: string;
}

// ============ Utilities ============

function formatDuration(seconds: number): string {
  const mins = Math.floor(seconds / 60);
  const secs = Math.floor(seconds % 60);
  const ms = Math.floor((seconds % 1) * 100);
  return `${mins}:${secs.toString().padStart(2, '0')}.${ms.toString().padStart(2, '0')}`;
}

function formatFileSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

function formatSampleRate(sr: number): string {
  return `${(sr / 1000).toFixed(1)}kHz`;
}

function getFileFormat(filename: string): string {
  const ext = filename.split('.').pop()?.toLowerCase() ?? '';
  return ext.toUpperCase();
}

// Generate waveform from AudioBuffer
async function generateWaveform(audioBuffer: AudioBuffer, samples: number = 100): Promise<number[]> {
  const channelData = audioBuffer.getChannelData(0);
  const blockSize = Math.floor(channelData.length / samples);
  const waveform: number[] = [];

  for (let i = 0; i < samples; i++) {
    let sum = 0;
    const start = i * blockSize;
    const end = Math.min(start + blockSize, channelData.length);

    for (let j = start; j < end; j++) {
      sum += Math.abs(channelData[j]);
    }

    waveform.push(sum / (end - start));
  }

  // Normalize
  const max = Math.max(...waveform, 0.001);
  return waveform.map(v => v / max);
}

// Simple BPM detection for loops
function detectBPM(audioBuffer: AudioBuffer): number | undefined {
  // Skip for very short files
  if (audioBuffer.duration < 1) return undefined;

  // Common loop durations at various BPMs
  const duration = audioBuffer.duration;

  // Check if duration matches common bar lengths
  // 4 bars at 120 BPM = 8 seconds
  // 2 bars at 120 BPM = 4 seconds
  // 1 bar at 120 BPM = 2 seconds

  const commonBPMs = [80, 90, 100, 110, 120, 128, 130, 140, 150, 160, 170, 180];

  for (const bpm of commonBPMs) {
    const barLength = 240 / bpm; // 4 beats at given BPM
    const bars1 = duration / barLength;
    const bars2 = duration / (barLength * 2);
    const bars4 = duration / (barLength * 4);

    // Check if duration is close to 1, 2, 4, or 8 bars
    for (const bars of [bars1, bars2, bars4]) {
      const rounded = Math.round(bars);
      if (rounded >= 1 && rounded <= 16 && Math.abs(bars - rounded) < 0.05) {
        return bpm;
      }
    }
  }

  return undefined;
}

// ============ Components ============

interface WaveformDisplayProps {
  waveform: number[];
  playProgress?: number;
  height?: number;
  color?: string;
}

function WaveformDisplay({ waveform, playProgress = 0, height = 60, color = '#3b82f6' }: WaveformDisplayProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const dpr = window.devicePixelRatio || 1;
    const rect = canvas.getBoundingClientRect();

    canvas.width = rect.width * dpr;
    canvas.height = rect.height * dpr;
    ctx.scale(dpr, dpr);

    const width = rect.width;
    const barWidth = width / waveform.length;
    const centerY = height / 2;

    // Clear
    ctx.clearRect(0, 0, width, height);

    // Draw waveform
    waveform.forEach((value, i) => {
      const x = i * barWidth;
      const barHeight = value * (height * 0.8);
      const isPlayed = (i / waveform.length) < playProgress;

      ctx.fillStyle = isPlayed ? color : '#444';
      ctx.fillRect(x, centerY - barHeight / 2, barWidth - 1, barHeight);
    });

    // Draw playhead
    if (playProgress > 0 && playProgress < 1) {
      const playX = playProgress * width;
      ctx.fillStyle = '#fff';
      ctx.fillRect(playX - 1, 0, 2, height);
    }
  }, [waveform, playProgress, height, color]);

  return (
    <canvas
      ref={canvasRef}
      className="rf-audio-browser__waveform-canvas"
      style={{ width: '100%', height }}
    />
  );
}

// ============ Draggable Audio Item ============

interface DraggableAudioItemProps {
  file: AudioFileInfo;
  isSelected: boolean;
  isPlaying: boolean;
  playProgress: number;
  onSelect: (id: string, e: React.MouseEvent) => void;
  onTogglePreview: (file: AudioFileInfo) => void;
}

const DraggableAudioItem = memo(function DraggableAudioItem({
  file,
  isSelected,
  isPlaying,
  playProgress,
  onSelect,
  onTogglePreview,
}: DraggableAudioItemProps) {
  // Create drag item for timeline drop
  const dragItem: DragItem = {
    type: 'audio-asset',
    id: `audio-${file.id}`,
    label: file.name,
    data: {
      duration: file.duration,
      waveform: file.waveform,
      sampleRate: file.sampleRate,
      channels: file.channels,
      bpm: file.bpm,
      isLoop: file.isLoop,
    },
  };

  const { isDragging, dragHandlers } = useDraggable(dragItem);

  return (
    <div
      {...dragHandlers}
      className={`rf-audio-browser__item ${isSelected ? 'selected' : ''} ${
        isPlaying ? 'playing' : ''
      } ${isDragging ? 'dragging' : ''}`}
      onClick={(e) => onSelect(file.id, e)}
      onDoubleClick={() => onTogglePreview(file)}
    >
      <div className={`rf-audio-browser__item-icon ${file.isLoop ? 'loop' : 'oneshot'}`}>
        {file.isLoop ? '🔄' : '▶'}
      </div>
      <div className="rf-audio-browser__item-info">
        <div className="rf-audio-browser__item-name">{file.name}</div>
        <div className="rf-audio-browser__item-meta">
          <span className="rf-audio-browser__item-duration">
            {formatDuration(file.duration)}
          </span>
          <span className="rf-audio-browser__item-format">{file.format}</span>
          <span className="rf-audio-browser__item-sr">
            {formatSampleRate(file.sampleRate)}
          </span>
          {file.bpm && (
            <span style={{ color: '#10b981' }}>{file.bpm} BPM</span>
          )}
        </div>
      </div>
      <div className="rf-audio-browser__item-waveform">
        <WaveformDisplay
          waveform={file.waveform}
          playProgress={isPlaying ? playProgress : 0}
          height={20}
          color="#3b82f6"
        />
      </div>
    </div>
  );
});

// ============ Main Component ============

export function AudioBrowser({
  files: externalFiles,
  onImport,
  onPreviewStart,
  onPreviewStop,
  showImport = true,
  multiSelect = true,
  className = '',
}: AudioBrowserProps) {
  // State
  const [files, setFiles] = useState<AudioFileInfo[]>(externalFiles ?? []);
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [previewingId, setPreviewingId] = useState<string | null>(null);
  const [playProgress, setPlayProgress] = useState(0);
  const [searchQuery, setSearchQuery] = useState('');
  const [showFilters, setShowFilters] = useState(false);
  const [formatFilter, setFormatFilter] = useState<string>('all');
  const [isDragging, setIsDragging] = useState(false);
  const [isLoading, setIsLoading] = useState(false);

  // Refs
  const audioContextRef = useRef<AudioContext | null>(null);
  const sourceNodeRef = useRef<AudioBufferSourceNode | null>(null);
  const audioBufferCacheRef = useRef<Map<string, AudioBuffer>>(new Map());
  const animationFrameRef = useRef<number>(0);
  const startTimeRef = useRef<number>(0);

  // Sync with external files
  useEffect(() => {
    if (externalFiles) {
      setFiles(externalFiles);
    }
  }, [externalFiles]);

  // Get or create audio context
  const getAudioContext = useCallback(() => {
    if (!audioContextRef.current) {
      audioContextRef.current = new AudioContext();
    }
    return audioContextRef.current;
  }, []);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      if (sourceNodeRef.current) {
        sourceNodeRef.current.stop();
      }
      if (animationFrameRef.current) {
        cancelAnimationFrame(animationFrameRef.current);
      }
    };
  }, []);

  // Filter files
  const filteredFiles = useMemo(() => {
    let result = files;

    // Search filter
    if (searchQuery) {
      const query = searchQuery.toLowerCase();
      result = result.filter(f => f.name.toLowerCase().includes(query));
    }

    // Format filter
    if (formatFilter !== 'all') {
      result = result.filter(f => f.format.toLowerCase() === formatFilter.toLowerCase());
    }

    return result;
  }, [files, searchQuery, formatFilter]);

  // Get selected file for preview
  const selectedFile = useMemo(() => {
    if (selectedIds.size === 1) {
      const id = Array.from(selectedIds)[0];
      return files.find(f => f.id === id) ?? null;
    }
    return null;
  }, [selectedIds, files]);

  // Process dropped files
  const processFiles = useCallback(async (fileList: FileList | File[]) => {
    setIsLoading(true);
    const ctx = getAudioContext();
    const newFiles: AudioFileInfo[] = [];

    const audioFiles = Array.from(fileList).filter(f =>
      /\.(mp3|wav|ogg|m4a|flac|aiff|aif)$/i.test(f.name)
    );

    for (const file of audioFiles) {
      try {
        const arrayBuffer = await file.arrayBuffer();
        const audioBuffer = await ctx.decodeAudioData(arrayBuffer.slice(0));

        const waveform = await generateWaveform(audioBuffer);
        const bpm = detectBPM(audioBuffer);

        const info: AudioFileInfo = {
          id: `${file.name}-${Date.now()}-${Math.random().toString(36).slice(2)}`,
          name: file.name,
          file,
          duration: audioBuffer.duration,
          sampleRate: audioBuffer.sampleRate,
          channels: audioBuffer.numberOfChannels,
          format: getFileFormat(file.name),
          size: file.size,
          waveform,
          bpm,
          isLoop: bpm !== undefined,
        };

        // Cache the audio buffer
        audioBufferCacheRef.current.set(info.id, audioBuffer);
        newFiles.push(info);
      } catch (err) {
        console.error('Failed to process audio file:', file.name, err);
      }
    }

    setFiles(prev => [...prev, ...newFiles]);
    setIsLoading(false);

    // Auto-select first new file
    if (newFiles.length > 0) {
      setSelectedIds(new Set([newFiles[0].id]));
    }
  }, [getAudioContext]);

  // Handle file selection
  const handleSelect = useCallback((id: string, event: React.MouseEvent) => {
    setSelectedIds(prev => {
      const next = new Set(prev);

      if (multiSelect && (event.ctrlKey || event.metaKey)) {
        // Toggle selection
        if (next.has(id)) {
          next.delete(id);
        } else {
          next.add(id);
        }
      } else if (multiSelect && event.shiftKey && prev.size > 0) {
        // Range selection
        const fileIds = filteredFiles.map(f => f.id);
        const lastSelected = Array.from(prev).pop()!;
        const lastIdx = fileIds.indexOf(lastSelected);
        const currentIdx = fileIds.indexOf(id);
        const start = Math.min(lastIdx, currentIdx);
        const end = Math.max(lastIdx, currentIdx);

        for (let i = start; i <= end; i++) {
          next.add(fileIds[i]);
        }
      } else {
        // Single selection
        next.clear();
        next.add(id);
      }

      return next;
    });
  }, [multiSelect, filteredFiles]);

  // Start preview playback
  const startPreview = useCallback(async (file: AudioFileInfo) => {
    const ctx = getAudioContext();

    // Stop current preview
    if (sourceNodeRef.current) {
      sourceNodeRef.current.stop();
      sourceNodeRef.current = null;
    }

    // Get cached buffer or decode
    let buffer = audioBufferCacheRef.current.get(file.id);
    if (!buffer) {
      const arrayBuffer = await file.file.arrayBuffer();
      buffer = await ctx.decodeAudioData(arrayBuffer);
      audioBufferCacheRef.current.set(file.id, buffer);
    }

    // Create and start source
    const source = ctx.createBufferSource();
    source.buffer = buffer;
    source.connect(ctx.destination);
    source.start();

    sourceNodeRef.current = source;
    setPreviewingId(file.id);
    startTimeRef.current = ctx.currentTime;

    // Update progress
    const updateProgress = () => {
      if (!sourceNodeRef.current || previewingId !== file.id) return;

      const elapsed = ctx.currentTime - startTimeRef.current;
      const progress = Math.min(elapsed / buffer!.duration, 1);
      setPlayProgress(progress);

      if (progress < 1) {
        animationFrameRef.current = requestAnimationFrame(updateProgress);
      } else {
        // Playback ended
        setPreviewingId(null);
        setPlayProgress(0);
      }
    };

    animationFrameRef.current = requestAnimationFrame(updateProgress);

    // Handle end of playback
    source.onended = () => {
      if (previewingId === file.id) {
        setPreviewingId(null);
        setPlayProgress(0);
      }
    };

    onPreviewStart?.(file);
  }, [getAudioContext, previewingId, onPreviewStart]);

  // Stop preview playback
  const stopPreview = useCallback(() => {
    if (sourceNodeRef.current) {
      sourceNodeRef.current.stop();
      sourceNodeRef.current = null;
    }
    if (animationFrameRef.current) {
      cancelAnimationFrame(animationFrameRef.current);
    }
    setPreviewingId(null);
    setPlayProgress(0);
    onPreviewStop?.();
  }, [onPreviewStop]);

  // Toggle preview
  const togglePreview = useCallback((file: AudioFileInfo) => {
    if (previewingId === file.id) {
      stopPreview();
    } else {
      startPreview(file);
    }
  }, [previewingId, startPreview, stopPreview]);

  // Handle import
  const handleImport = useCallback(() => {
    const selectedFiles = files.filter(f => selectedIds.has(f.id));
    onImport?.(selectedFiles);
  }, [files, selectedIds, onImport]);

  // Drag and drop handlers
  const handleDragOver = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    setIsDragging(true);
  }, []);

  const handleDragLeave = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    setIsDragging(false);
  }, []);

  const handleDrop = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    setIsDragging(false);

    if (e.dataTransfer.files.length > 0) {
      processFiles(e.dataTransfer.files);
    }
  }, [processFiles]);

  // File input handler
  const handleFileInput = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.files && e.target.files.length > 0) {
      processFiles(e.target.files);
    }
    e.target.value = '';
  }, [processFiles]);

  // Get unique formats for filter
  const availableFormats = useMemo(() => {
    const formats = new Set(files.map(f => f.format));
    return Array.from(formats).sort();
  }, [files]);

  return (
    <div
      className={`rf-audio-browser ${className}`}
      onDragOver={handleDragOver}
      onDragLeave={handleDragLeave}
      onDrop={handleDrop}
    >
      {/* Header */}
      <div className="rf-audio-browser__header">
        <div className="rf-audio-browser__search">
          <span className="rf-audio-browser__search-icon">🔍</span>
          <input
            type="text"
            className="rf-audio-browser__search-input"
            placeholder="Search files..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
          />
        </div>
        <button
          className={`rf-audio-browser__filter-btn ${showFilters ? 'active' : ''}`}
          onClick={() => setShowFilters(!showFilters)}
        >
          Filters
        </button>
        <label className="rf-audio-browser__filter-btn" style={{ cursor: 'pointer' }}>
          + Add
          <input
            type="file"
            accept="audio/*"
            multiple
            style={{ display: 'none' }}
            onChange={handleFileInput}
          />
        </label>
      </div>

      {/* Filters */}
      {showFilters && (
        <div className="rf-audio-browser__filters">
          <div className="rf-audio-browser__filter-group">
            <span className="rf-audio-browser__filter-label">Format</span>
            <select
              className="rf-audio-browser__filter-select"
              value={formatFilter}
              onChange={(e) => setFormatFilter(e.target.value)}
            >
              <option value="all">All</option>
              {availableFormats.map(fmt => (
                <option key={fmt} value={fmt}>{fmt}</option>
              ))}
            </select>
          </div>
        </div>
      )}

      {/* File list */}
      <div className="rf-audio-browser__list">
        {isLoading && (
          <div className="rf-audio-browser__loading">
            <div className="rf-audio-browser__loading-spinner" />
            Loading files...
          </div>
        )}

        {!isLoading && filteredFiles.length === 0 && (
          <div className="rf-audio-browser__empty">
            <div className="rf-audio-browser__empty-icon">📁</div>
            <div className="rf-audio-browser__empty-text">No audio files</div>
            <div className="rf-audio-browser__empty-hint">
              Drag & drop files here or click "+ Add"
            </div>
          </div>
        )}

        {filteredFiles.map(file => (
          <DraggableAudioItem
            key={file.id}
            file={file}
            isSelected={selectedIds.has(file.id)}
            isPlaying={previewingId === file.id}
            playProgress={playProgress}
            onSelect={handleSelect}
            onTogglePreview={togglePreview}
          />
        ))}
      </div>

      {/* Preview panel */}
      {selectedFile && (
        <div className="rf-audio-browser__preview">
          <div className="rf-audio-browser__preview-header">
            <div className="rf-audio-browser__preview-title">{selectedFile.name}</div>
            <div className="rf-audio-browser__preview-controls">
              <button
                className={`rf-audio-browser__preview-btn ${
                  previewingId === selectedFile.id ? 'stop' : ''
                }`}
                onClick={() => togglePreview(selectedFile)}
                title={previewingId === selectedFile.id ? 'Stop' : 'Play'}
              >
                {previewingId === selectedFile.id ? '⏹' : '▶'}
              </button>
            </div>
          </div>

          <div className="rf-audio-browser__waveform">
            <WaveformDisplay
              waveform={selectedFile.waveform}
              playProgress={previewingId === selectedFile.id ? playProgress : 0}
              height={60}
            />
          </div>

          <div className="rf-audio-browser__preview-meta">
            <div className="rf-audio-browser__meta-item">
              <span className="rf-audio-browser__meta-label">Duration</span>
              <span className="rf-audio-browser__meta-value">
                {formatDuration(selectedFile.duration)}
              </span>
            </div>
            <div className="rf-audio-browser__meta-item">
              <span className="rf-audio-browser__meta-label">Sample Rate</span>
              <span className="rf-audio-browser__meta-value">
                {formatSampleRate(selectedFile.sampleRate)}
              </span>
            </div>
            <div className="rf-audio-browser__meta-item">
              <span className="rf-audio-browser__meta-label">Channels</span>
              <span className="rf-audio-browser__meta-value">
                {selectedFile.channels === 1 ? 'Mono' : 'Stereo'}
              </span>
            </div>
            <div className="rf-audio-browser__meta-item">
              <span className="rf-audio-browser__meta-label">Size</span>
              <span className="rf-audio-browser__meta-value">
                {formatFileSize(selectedFile.size)}
              </span>
            </div>
          </div>

          {showImport && (
            <button
              className="rf-audio-browser__import-btn"
              onClick={handleImport}
              disabled={selectedIds.size === 0}
            >
              Import {selectedIds.size > 1 ? `${selectedIds.size} Files` : 'Selected'}
            </button>
          )}
        </div>
      )}

      {/* Drop zone overlay */}
      <div className={`rf-audio-browser__dropzone ${isDragging ? 'active' : ''}`}>
        <span className="rf-audio-browser__dropzone-text">
          Drop audio files here
        </span>
      </div>
    </div>
  );
}

export default AudioBrowser;
