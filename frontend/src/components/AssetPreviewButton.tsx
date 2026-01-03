/**
 * Asset Preview Button Component
 *
 * Compact play/stop button for audio assets with:
 * - Play/Stop toggle
 * - Mini progress indicator
 * - Hover preview (optional)
 *
 * @module components/AssetPreviewButton
 */

import React, { memo, useCallback, useEffect, useState } from 'react';
import { PreviewEngine } from '../core/previewEngine';
import './AssetPreviewButton.css';

// ============ TYPES ============

export interface AssetPreviewButtonProps {
  assetId: string;
  size?: 'small' | 'medium' | 'large';
  showProgress?: boolean;
  hoverPreview?: boolean;
  loop?: boolean;
  volume?: number;
  className?: string;
  onPlayStateChange?: (playing: boolean) => void;
}

// ============ COMPONENT ============

const AssetPreviewButton: React.FC<AssetPreviewButtonProps> = memo(({
  assetId,
  size = 'medium',
  showProgress = true,
  hoverPreview = false,
  loop = false,
  volume = 1,
  className = '',
  onPlayStateChange,
}) => {
  const [isPlaying, setIsPlaying] = useState(false);
  const [progress, setProgress] = useState(0);
  const [_isHovering, setIsHovering] = useState(false);

  // Subscribe to preview engine state
  useEffect(() => {
    const unsubscribe = PreviewEngine.subscribe((event) => {
      if (event.assetId === assetId) {
        switch (event.type) {
          case 'play':
            setIsPlaying(true);
            onPlayStateChange?.(true);
            break;
          case 'stop':
          case 'ended':
            setIsPlaying(false);
            setProgress(0);
            onPlayStateChange?.(false);
            break;
          case 'timeUpdate':
            const state = PreviewEngine.getState();
            if (state.duration > 0) {
              setProgress((state.currentTime / state.duration) * 100);
            }
            break;
        }
      }
    });

    // Check initial state
    setIsPlaying(PreviewEngine.isAssetPlaying(assetId));

    return unsubscribe;
  }, [assetId, onPlayStateChange]);

  // Handle click
  const handleClick = useCallback(async (e: React.MouseEvent) => {
    e.stopPropagation();

    if (isPlaying) {
      PreviewEngine.stopAsset(assetId);
    } else {
      await PreviewEngine.playAsset(assetId, { loop, volume });
    }
  }, [assetId, isPlaying, loop, volume]);

  // Handle hover preview
  const handleMouseEnter = useCallback(async () => {
    setIsHovering(true);
    if (hoverPreview && !isPlaying) {
      await PreviewEngine.playAsset(assetId, {
        loop: false,
        volume: volume * 0.5, // Lower volume for hover preview
      });
    }
  }, [assetId, hoverPreview, isPlaying, volume]);

  const handleMouseLeave = useCallback(() => {
    setIsHovering(false);
    if (hoverPreview && isPlaying) {
      PreviewEngine.stopAsset(assetId);
    }
  }, [assetId, hoverPreview, isPlaying]);

  // Size classes
  const sizeClass = `asset-preview-btn--${size}`;

  return (
    <button
      className={`asset-preview-btn ${sizeClass} ${isPlaying ? 'playing' : ''} ${className}`}
      onClick={handleClick}
      onMouseEnter={handleMouseEnter}
      onMouseLeave={handleMouseLeave}
      title={isPlaying ? 'Stop' : 'Play'}
    >
      {/* Progress Ring */}
      {showProgress && isPlaying && (
        <svg className="asset-preview-btn__progress" viewBox="0 0 36 36">
          <circle
            className="asset-preview-btn__progress-bg"
            cx="18"
            cy="18"
            r="16"
            fill="none"
            strokeWidth="2"
          />
          <circle
            className="asset-preview-btn__progress-fill"
            cx="18"
            cy="18"
            r="16"
            fill="none"
            strokeWidth="2"
            strokeDasharray={`${progress} 100`}
            transform="rotate(-90 18 18)"
          />
        </svg>
      )}

      {/* Icon */}
      <span className="asset-preview-btn__icon">
        {isPlaying ? (
          <svg viewBox="0 0 24 24" fill="currentColor">
            <rect x="6" y="5" width="4" height="14" rx="1" />
            <rect x="14" y="5" width="4" height="14" rx="1" />
          </svg>
        ) : (
          <svg viewBox="0 0 24 24" fill="currentColor">
            <path d="M8 5.14v13.72a1 1 0 001.5.86l11-6.86a1 1 0 000-1.72l-11-6.86A1 1 0 008 5.14z" />
          </svg>
        )}
      </span>
    </button>
  );
});

AssetPreviewButton.displayName = 'AssetPreviewButton';
export default AssetPreviewButton;
