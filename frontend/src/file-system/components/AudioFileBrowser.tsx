/**
 * ReelForge Audio File Browser
 *
 * File browser component for audio files with:
 * - Grid/List view
 * - Sorting and filtering
 * - Audio preview
 * - Drag-drop to timeline
 *
 * @module file-system/components/AudioFileBrowser
 */

import { useState, useCallback, useMemo, useRef, useEffect } from 'react';
import {
  AudioMetadataExtractor,
  formatDuration,
  formatBPM,
  type AudioMetadata,
} from '../AudioMetadata';
import { formatFileSize } from '../ProjectArchive';
import './AudioFileBrowser.css';

// ============ Types ============

export interface AudioFileItem extends AudioMetadata {
  id: string;
  file?: File;
  arrayBuffer?: ArrayBuffer;
}

export type ViewMode = 'grid' | 'list';
export type SortBy = 'name' | 'duration' | 'bpm' | 'size' | 'date';
export type SortOrder = 'asc' | 'desc';

export interface AudioFileBrowserProps {
  files: AudioFileItem[];
  onFileSelect?: (file: AudioFileItem) => void;
  onFileDoubleClick?: (file: AudioFileItem) => void;
  onFileDrop?: (file: AudioFileItem, target: unknown) => void;
  onFilesImport?: (files: AudioFileItem[]) => void;
  selectedIds?: Set<string>;
  onSelectionChange?: (ids: Set<string>) => void;
  viewMode?: ViewMode;
  showPreview?: boolean;
  showBPM?: boolean;
  className?: string;
}

// ============ Audio File Browser Component ============

export function AudioFileBrowser({
  files,
  onFileSelect,
  onFileDoubleClick,
  onFilesImport,
  selectedIds = new Set(),
  onSelectionChange,
  viewMode: initialViewMode = 'list',
  showPreview = true,
  showBPM = true,
  className = '',
}: AudioFileBrowserProps) {
  const [viewMode, setViewMode] = useState<ViewMode>(initialViewMode);
  const [sortBy, setSortBy] = useState<SortBy>('name');
  const [sortOrder, setSortOrder] = useState<SortOrder>('asc');
  const [filter, setFilter] = useState('');
  const [playingId, setPlayingId] = useState<string | null>(null);
  const [isDraggingOver, setIsDraggingOver] = useState(false);
  const [isImporting, setIsImporting] = useState(false);

  const audioRef = useRef<HTMLAudioElement>(null);
  const metadataExtractor = useMemo(() => new AudioMetadataExtractor(), []);

  // Filtered and sorted files
  const displayFiles = useMemo(() => {
    let result = [...files];

    // Filter
    if (filter) {
      const lowerFilter = filter.toLowerCase();
      result = result.filter(f =>
        f.name.toLowerCase().includes(lowerFilter)
      );
    }

    // Sort
    result.sort((a, b) => {
      let comparison = 0;

      switch (sortBy) {
        case 'name':
          comparison = a.name.localeCompare(b.name);
          break;
        case 'duration':
          comparison = a.duration - b.duration;
          break;
        case 'bpm':
          comparison = (a.bpm || 0) - (b.bpm || 0);
          break;
        case 'size':
          comparison = a.fileSize - b.fileSize;
          break;
        case 'date':
          comparison = 0; // Would need date field
          break;
      }

      return sortOrder === 'asc' ? comparison : -comparison;
    });

    return result;
  }, [files, filter, sortBy, sortOrder]);

  // Handle file click
  const handleFileClick = useCallback((file: AudioFileItem, event: React.MouseEvent) => {
    if (event.ctrlKey || event.metaKey) {
      // Multi-select
      const newSelection = new Set(selectedIds);
      if (newSelection.has(file.id)) {
        newSelection.delete(file.id);
      } else {
        newSelection.add(file.id);
      }
      onSelectionChange?.(newSelection);
    } else {
      // Single select
      onSelectionChange?.(new Set([file.id]));
    }

    onFileSelect?.(file);
  }, [selectedIds, onSelectionChange, onFileSelect]);

  // Handle double click
  const handleDoubleClick = useCallback((file: AudioFileItem) => {
    onFileDoubleClick?.(file);
  }, [onFileDoubleClick]);

  // Handle preview play
  const handlePreviewPlay = useCallback((file: AudioFileItem, event: React.MouseEvent) => {
    event.stopPropagation();

    if (playingId === file.id) {
      // Stop
      audioRef.current?.pause();
      setPlayingId(null);
    } else {
      // Play
      if (audioRef.current && file.file) {
        audioRef.current.src = URL.createObjectURL(file.file);
        audioRef.current.play();
        setPlayingId(file.id);
      }
    }
  }, [playingId]);

  // Handle audio end
  useEffect(() => {
    const audio = audioRef.current;
    if (!audio) return;

    const handleEnded = () => setPlayingId(null);
    audio.addEventListener('ended', handleEnded);
    return () => audio.removeEventListener('ended', handleEnded);
  }, []);

  // Handle drag and drop import
  const handleDragOver = useCallback((event: React.DragEvent) => {
    event.preventDefault();
    event.dataTransfer.dropEffect = 'copy';
    setIsDraggingOver(true);
  }, []);

  const handleDragLeave = useCallback(() => {
    setIsDraggingOver(false);
  }, []);

  const handleDrop = useCallback(async (event: React.DragEvent) => {
    event.preventDefault();
    setIsDraggingOver(false);

    const items = event.dataTransfer.files;
    if (items.length === 0) return;

    setIsImporting(true);

    const importedFiles: AudioFileItem[] = [];

    for (let i = 0; i < items.length; i++) {
      const file = items[i];

      // Check if audio file
      if (!file.type.startsWith('audio/')) continue;

      try {
        const metadata = await metadataExtractor.extractFromFile(file);
        importedFiles.push({
          ...metadata,
          id: `file_${Date.now()}_${i}`,
          file,
        });
      } catch (err) {
        console.error(`Failed to import ${file.name}:`, err);
      }
    }

    setIsImporting(false);

    if (importedFiles.length > 0) {
      onFilesImport?.(importedFiles);
    }
  }, [metadataExtractor, onFilesImport]);

  // Handle sort change
  const handleSortChange = useCallback((newSortBy: SortBy) => {
    if (sortBy === newSortBy) {
      setSortOrder(prev => prev === 'asc' ? 'desc' : 'asc');
    } else {
      setSortBy(newSortBy);
      setSortOrder('asc');
    }
  }, [sortBy]);

  // Drag start for file item
  const handleItemDragStart = useCallback((file: AudioFileItem, event: React.DragEvent) => {
    event.dataTransfer.setData('application/json', JSON.stringify({
      type: 'audio-file',
      id: file.id,
      name: file.name,
      duration: file.duration,
    }));
    event.dataTransfer.effectAllowed = 'copy';
  }, []);

  return (
    <div
      className={`audio-file-browser ${className} ${isDraggingOver ? 'dragging-over' : ''}`}
      onDragOver={handleDragOver}
      onDragLeave={handleDragLeave}
      onDrop={handleDrop}
    >
      {/* Toolbar */}
      <div className="audio-file-browser__toolbar">
        <input
          type="text"
          className="audio-file-browser__search"
          placeholder="Search files..."
          value={filter}
          onChange={e => setFilter(e.target.value)}
        />

        <div className="audio-file-browser__view-toggle">
          <button
            className={viewMode === 'list' ? 'active' : ''}
            onClick={() => setViewMode('list')}
            title="List view"
          >
            ☰
          </button>
          <button
            className={viewMode === 'grid' ? 'active' : ''}
            onClick={() => setViewMode('grid')}
            title="Grid view"
          >
            ▦
          </button>
        </div>
      </div>

      {/* List Header */}
      {viewMode === 'list' && (
        <div className="audio-file-browser__header">
          <button
            className={`sort-btn ${sortBy === 'name' ? 'active' : ''}`}
            onClick={() => handleSortChange('name')}
          >
            Name {sortBy === 'name' && (sortOrder === 'asc' ? '↑' : '↓')}
          </button>
          <button
            className={`sort-btn ${sortBy === 'duration' ? 'active' : ''}`}
            onClick={() => handleSortChange('duration')}
          >
            Duration {sortBy === 'duration' && (sortOrder === 'asc' ? '↑' : '↓')}
          </button>
          {showBPM && (
            <button
              className={`sort-btn ${sortBy === 'bpm' ? 'active' : ''}`}
              onClick={() => handleSortChange('bpm')}
            >
              BPM {sortBy === 'bpm' && (sortOrder === 'asc' ? '↑' : '↓')}
            </button>
          )}
          <button
            className={`sort-btn ${sortBy === 'size' ? 'active' : ''}`}
            onClick={() => handleSortChange('size')}
          >
            Size {sortBy === 'size' && (sortOrder === 'asc' ? '↑' : '↓')}
          </button>
        </div>
      )}

      {/* File List */}
      <div className={`audio-file-browser__content ${viewMode}`}>
        {displayFiles.length === 0 ? (
          <div className="audio-file-browser__empty">
            <div className="audio-file-browser__empty-icon">🎵</div>
            <div className="audio-file-browser__empty-text">
              {filter ? 'No files match your search' : 'Drop audio files here'}
            </div>
          </div>
        ) : (
          displayFiles.map(file => (
            <div
              key={file.id}
              className={`audio-file-item ${selectedIds.has(file.id) ? 'selected' : ''}`}
              onClick={e => handleFileClick(file, e)}
              onDoubleClick={() => handleDoubleClick(file)}
              draggable
              onDragStart={e => handleItemDragStart(file, e)}
            >
              {/* Waveform Preview */}
              {viewMode === 'grid' && file.waveformPeaks && (
                <div className="audio-file-item__waveform">
                  <MiniWaveform peaks={file.waveformPeaks} />
                </div>
              )}

              {/* Play Button */}
              {showPreview && (
                <button
                  className={`audio-file-item__play ${playingId === file.id ? 'playing' : ''}`}
                  onClick={e => handlePreviewPlay(file, e)}
                >
                  {playingId === file.id ? '⏸' : '▶'}
                </button>
              )}

              {/* File Info */}
              <div className="audio-file-item__info">
                <div className="audio-file-item__name">{file.name}</div>
                <div className="audio-file-item__meta">
                  <span className="duration">{formatDuration(file.duration)}</span>
                  {showBPM && file.bpm && (
                    <span className="bpm">{formatBPM(file.bpm, file.bpmConfidence)}</span>
                  )}
                  {viewMode === 'list' && (
                    <span className="size">{formatFileSize(file.fileSize)}</span>
                  )}
                </div>
              </div>
            </div>
          ))
        )}
      </div>

      {/* Import Overlay */}
      {isDraggingOver && (
        <div className="audio-file-browser__drop-overlay">
          <div className="audio-file-browser__drop-icon">📥</div>
          <div className="audio-file-browser__drop-text">Drop to import</div>
        </div>
      )}

      {/* Loading Overlay */}
      {isImporting && (
        <div className="audio-file-browser__loading">
          <div className="audio-file-browser__spinner" />
          <div>Importing files...</div>
        </div>
      )}

      {/* Hidden audio element for preview */}
      <audio ref={audioRef} />
    </div>
  );
}

// ============ Mini Waveform Component ============

function MiniWaveform({ peaks }: { peaks: Float32Array }) {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const width = canvas.width;
    const height = canvas.height;
    const midY = height / 2;

    ctx.clearRect(0, 0, width, height);
    ctx.fillStyle = 'rgba(99, 102, 241, 0.6)';

    const step = peaks.length / width;

    for (let x = 0; x < width; x++) {
      const peakIndex = Math.floor(x * step);
      const peak = peaks[peakIndex] || 0;
      const barHeight = peak * midY;

      ctx.fillRect(x, midY - barHeight, 1, barHeight * 2);
    }
  }, [peaks]);

  return <canvas ref={canvasRef} width={100} height={40} />;
}

export default AudioFileBrowser;
