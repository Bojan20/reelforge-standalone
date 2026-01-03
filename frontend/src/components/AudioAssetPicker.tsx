/**
 * ReelForge Audio Asset Picker
 *
 * Dropdown for selecting imported audio files as asset IDs.
 * Features:
 * - Fuzzy search matching
 * - Waveform preview
 * - Match status indicator
 * - Keyboard navigation
 */

import { useState, useEffect, useRef, useCallback, useMemo } from 'react';
import './AudioAssetPicker.css';

export interface AudioAssetOption {
  /** Unique ID (usually filename) */
  id: string;
  /** Display name */
  name: string;
  /** Duration in seconds */
  duration?: number;
  /** Waveform data for preview */
  waveform?: number[];
}

interface AudioAssetPickerProps {
  /** Current asset ID value */
  value: string;
  /** Callback when value changes */
  onChange: (assetId: string) => void;
  /** Available audio assets */
  audioAssets: AudioAssetOption[];
  /** Label for the field */
  label?: string;
  /** Placeholder text */
  placeholder?: string;
  /** Show error state if asset not found */
  showMissingWarning?: boolean;
  /** Callback to play preview (click) */
  onPreview?: (assetId: string) => void;
  /** Callback to play short preview on hover (auto-plays first 1.5s) */
  onHoverPreview?: (assetId: string) => void;
  /** Callback to stop hover preview */
  onHoverPreviewStop?: () => void;
  /** Delay before hover preview starts (ms) */
  hoverPreviewDelay?: number;
}

// Fuzzy match score - higher is better
function fuzzyMatch(query: string, target: string): number {
  if (!query) return 1;

  const q = query.toLowerCase();
  const t = target.toLowerCase();

  // Exact match
  if (t === q) return 100;

  // Starts with
  if (t.startsWith(q)) return 80;

  // Contains
  if (t.includes(q)) return 60;

  // Remove extension and try again
  const tNoExt = t.replace(/\.[^/.]+$/, '');
  if (tNoExt === q) return 90;
  if (tNoExt.startsWith(q)) return 70;
  if (tNoExt.includes(q)) return 50;

  // Fuzzy character match
  let score = 0;
  let qIdx = 0;
  for (let i = 0; i < t.length && qIdx < q.length; i++) {
    if (t[i] === q[qIdx]) {
      score += 10;
      qIdx++;
    }
  }

  return qIdx === q.length ? score : 0;
}

function formatDuration(seconds: number): string {
  const mins = Math.floor(seconds / 60);
  const secs = Math.floor(seconds % 60);
  const ms = Math.floor((seconds % 1) * 100);
  return mins > 0 ? `${mins}:${secs.toString().padStart(2, '0')}` : `${secs}.${ms.toString().padStart(2, '0')}s`;
}

export default function AudioAssetPicker({
  value,
  onChange,
  audioAssets,
  label = 'Asset',
  placeholder = 'Select audio file...',
  showMissingWarning = true,
  onPreview,
  onHoverPreview,
  onHoverPreviewStop,
  hoverPreviewDelay = 300,
}: AudioAssetPickerProps) {
  const [isOpen, setIsOpen] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [highlightedIndex, setHighlightedIndex] = useState(0);
  const [hoveringAssetId, setHoveringAssetId] = useState<string | null>(null);

  const containerRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const listRef = useRef<HTMLDivElement>(null);
  const hoverTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const activeHoverPreviewRef = useRef<string | null>(null);

  // Filter and sort results by fuzzy match
  const filteredAssets = useMemo(() => {
    if (!searchQuery) return audioAssets;

    return audioAssets
      .map(asset => ({ asset, score: fuzzyMatch(searchQuery, asset.name) }))
      .filter(({ score }) => score > 0)
      .sort((a, b) => b.score - a.score)
      .map(({ asset }) => asset);
  }, [audioAssets, searchQuery]);

  // Check if current value exists
  const currentAsset = useMemo(() => {
    return audioAssets.find(a => a.id === value || a.name === value);
  }, [audioAssets, value]);

  const isMissing = value && !currentAsset && showMissingWarning;

  // Close on outside click
  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (containerRef.current && !containerRef.current.contains(e.target as Node)) {
        setIsOpen(false);
      }
    };
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  // Reset highlight on filter change
  useEffect(() => {
    setHighlightedIndex(0);
  }, [filteredAssets.length]);

  // Keyboard navigation
  const handleKeyDown = useCallback((e: React.KeyboardEvent) => {
    if (!isOpen) {
      if (e.key === 'ArrowDown' || e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        setIsOpen(true);
      }
      return;
    }

    switch (e.key) {
      case 'ArrowDown':
        e.preventDefault();
        setHighlightedIndex(prev => Math.min(prev + 1, filteredAssets.length - 1));
        break;
      case 'ArrowUp':
        e.preventDefault();
        setHighlightedIndex(prev => Math.max(prev - 1, 0));
        break;
      case 'Enter':
        e.preventDefault();
        if (filteredAssets[highlightedIndex]) {
          selectAsset(filteredAssets[highlightedIndex]);
        }
        break;
      case 'Escape':
        e.preventDefault();
        setIsOpen(false);
        break;
      case 'Tab':
        setIsOpen(false);
        break;
    }
  }, [isOpen, filteredAssets, highlightedIndex]);

  // Keep highlighted item in view
  useEffect(() => {
    if (listRef.current && isOpen) {
      const item = listRef.current.children[highlightedIndex] as HTMLElement;
      if (item) {
        item.scrollIntoView({ block: 'nearest' });
      }
    }
  }, [highlightedIndex, isOpen]);

  const selectAsset = useCallback((asset: AudioAssetOption) => {
    onChange(asset.name); // Use name as assetId for matching
    setSearchQuery('');
    setIsOpen(false);
  }, [onChange]);

  const handlePreview = useCallback((e: React.MouseEvent, assetId: string) => {
    e.stopPropagation();
    onPreview?.(assetId);
  }, [onPreview]);

  // Hover preview handlers
  const startHoverPreview = useCallback((assetId: string) => {
    if (!onHoverPreview) return;

    // Clear any existing timer
    if (hoverTimerRef.current) {
      clearTimeout(hoverTimerRef.current);
    }

    setHoveringAssetId(assetId);

    // Start preview after delay
    hoverTimerRef.current = setTimeout(() => {
      if (activeHoverPreviewRef.current !== assetId) {
        // Stop previous preview if different asset
        if (activeHoverPreviewRef.current) {
          onHoverPreviewStop?.();
        }
        activeHoverPreviewRef.current = assetId;
        onHoverPreview(assetId);
      }
    }, hoverPreviewDelay);
  }, [onHoverPreview, onHoverPreviewStop, hoverPreviewDelay]);

  const stopHoverPreview = useCallback(() => {
    // Clear timer
    if (hoverTimerRef.current) {
      clearTimeout(hoverTimerRef.current);
      hoverTimerRef.current = null;
    }

    setHoveringAssetId(null);

    // Stop active preview
    if (activeHoverPreviewRef.current) {
      activeHoverPreviewRef.current = null;
      onHoverPreviewStop?.();
    }
  }, [onHoverPreviewStop]);

  // Cleanup on unmount or dropdown close
  useEffect(() => {
    if (!isOpen) {
      stopHoverPreview();
    }
    return () => {
      if (hoverTimerRef.current) {
        clearTimeout(hoverTimerRef.current);
      }
    };
  }, [isOpen, stopHoverPreview]);

  const displayValue = isOpen ? searchQuery : (currentAsset?.name || value || '');

  return (
    <div className="rf-audio-picker-field">
      {label && <label className="rf-audio-picker-label">{label}</label>}

      <div
        className={`rf-audio-picker ${isOpen ? 'is-open' : ''} ${isMissing ? 'is-missing' : ''}`}
        ref={containerRef}
      >
        <div className="rf-audio-picker-input-row">
          <input
            ref={inputRef}
            type="text"
            className="rf-audio-picker-input"
            value={displayValue}
            onChange={(e) => {
              setSearchQuery(e.target.value);
              if (!isOpen) setIsOpen(true);
            }}
            onFocus={() => {
              setIsOpen(true);
              setSearchQuery('');
            }}
            onKeyDown={handleKeyDown}
            placeholder={placeholder}
          />

          {/* Status indicator */}
          {value && (
            <span className={`rf-audio-picker-status ${currentAsset ? 'is-linked' : 'is-unlinked'}`}>
              {currentAsset ? '✓' : '⚠'}
            </span>
          )}

          {/* Toggle button */}
          <button
            type="button"
            className="rf-audio-picker-toggle"
            onClick={() => setIsOpen(!isOpen)}
            tabIndex={-1}
          >
            {isOpen ? '▲' : '▼'}
          </button>
        </div>

        {/* Missing warning */}
        {isMissing && !isOpen && (
          <div className="rf-audio-picker-warning">
            Asset not imported: {value}
          </div>
        )}

        {/* Current asset info */}
        {!isOpen && currentAsset && currentAsset.duration && (
          <div className="rf-audio-picker-info">
            {formatDuration(currentAsset.duration)}
            {currentAsset.waveform && (
              <MiniWaveform data={currentAsset.waveform} />
            )}
          </div>
        )}

        {/* Dropdown */}
        {isOpen && (
          <div className="rf-audio-picker-dropdown">
            {filteredAssets.length === 0 ? (
              <div className="rf-audio-picker-empty">
                {audioAssets.length === 0
                  ? 'No audio files imported'
                  : `No matches for "${searchQuery}"`
                }
              </div>
            ) : (
              <>
                <div className="rf-audio-picker-count">
                  {filteredAssets.length} file{filteredAssets.length !== 1 ? 's' : ''}
                </div>

                <div
                  className="rf-audio-picker-list"
                  ref={listRef}
                  onMouseLeave={stopHoverPreview}
                >
                  {filteredAssets.map((asset, idx) => (
                    <div
                      key={asset.id}
                      className={`rf-audio-picker-item ${idx === highlightedIndex ? 'is-highlighted' : ''} ${asset.id === value || asset.name === value ? 'is-selected' : ''} ${hoveringAssetId === asset.name ? 'is-previewing' : ''}`}
                      onClick={() => selectAsset(asset)}
                      onMouseEnter={() => {
                        setHighlightedIndex(idx);
                        startHoverPreview(asset.name);
                      }}
                    >
                      {/* Hover preview indicator */}
                      {hoveringAssetId === asset.name && onHoverPreview && (
                        <span className="rf-audio-picker-item-preview-indicator">♫</span>
                      )}

                      <div className="rf-audio-picker-item-main">
                        <span className="rf-audio-picker-item-name">{asset.name}</span>
                        {asset.duration && (
                          <span className="rf-audio-picker-item-duration">
                            {formatDuration(asset.duration)}
                          </span>
                        )}
                      </div>

                      {asset.waveform && (
                        <MiniWaveform data={asset.waveform} />
                      )}

                      {onPreview && (
                        <button
                          type="button"
                          className="rf-audio-picker-item-preview"
                          onClick={(e) => handlePreview(e, asset.name)}
                          title="Play full preview"
                        >
                          ▶
                        </button>
                      )}
                    </div>
                  ))}
                </div>
              </>
            )}
          </div>
        )}
      </div>
    </div>
  );
}

// Mini waveform display
function MiniWaveform({ data }: { data: number[] }) {
  // Downsample to ~20 bars
  const bars = 20;
  const step = Math.max(1, Math.floor(data.length / bars));
  const samples: number[] = [];

  for (let i = 0; i < bars && i * step < data.length; i++) {
    let max = 0;
    for (let j = 0; j < step && i * step + j < data.length; j++) {
      max = Math.max(max, Math.abs(data[i * step + j]));
    }
    samples.push(max);
  }

  return (
    <div className="rf-audio-picker-waveform">
      {samples.map((v, i) => (
        <div
          key={i}
          className="rf-audio-picker-waveform-bar"
          style={{ height: `${Math.max(10, v * 100)}%` }}
        />
      ))}
    </div>
  );
}
