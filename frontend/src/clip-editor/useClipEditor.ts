/**
 * ReelForge Clip Editor Hook
 *
 * State management for clip editing:
 * - Multi-clip selection
 * - Copy/paste
 * - Undo/redo integration
 * - Batch operations
 *
 * @module clip-editor/useClipEditor
 */

import { useState, useCallback, useMemo } from 'react';
import type { ClipData, FadeCurve } from './ClipEditor';

// ============ Types ============

export interface ClipEditOperation {
  type: 'update' | 'delete' | 'split' | 'merge' | 'duplicate';
  clipIds: string[];
  data?: Partial<ClipData>;
  timestamp: number;
}

export interface UseClipEditorOptions {
  /** On clip change callback */
  onClipChange?: (clipId: string, updates: Partial<ClipData>) => void;
  /** On clips delete callback */
  onClipsDelete?: (clipIds: string[]) => void;
  /** On clip split callback */
  onClipSplit?: (clipId: string, splitTime: number) => void;
  /** On clips merge callback */
  onClipsMerge?: (clipIds: string[]) => void;
  /** On clip duplicate callback */
  onClipDuplicate?: (clipId: string) => void;
}

export interface UseClipEditorReturn {
  /** Selected clip IDs */
  selectedClipIds: string[];
  /** Clipboard contents */
  clipboard: ClipData[];
  /** Select a clip */
  selectClip: (clipId: string, addToSelection?: boolean) => void;
  /** Select multiple clips */
  selectClips: (clipIds: string[]) => void;
  /** Clear selection */
  clearSelection: () => void;
  /** Select all clips */
  selectAll: (allClipIds: string[]) => void;
  /** Update selected clips */
  updateSelectedClips: (updates: Partial<ClipData>) => void;
  /** Delete selected clips */
  deleteSelectedClips: () => void;
  /** Split clip at time */
  splitClip: (clipId: string, splitTime: number) => void;
  /** Merge selected clips */
  mergeSelectedClips: () => void;
  /** Duplicate selected clips */
  duplicateSelectedClips: () => void;
  /** Copy selected clips */
  copySelectedClips: (clips: ClipData[]) => void;
  /** Paste clips */
  pasteClips: (atTime: number) => ClipData[];
  /** Set fade in for selected */
  setFadeIn: (duration: number, curve?: FadeCurve) => void;
  /** Set fade out for selected */
  setFadeOut: (duration: number, curve?: FadeCurve) => void;
  /** Set gain for selected */
  setGain: (gain: number) => void;
  /** Normalize gain for selected */
  normalizeGain: () => void;
  /** Mute/unmute selected */
  toggleMute: () => void;
  /** Lock/unlock selected */
  toggleLock: () => void;
  /** Is any clip selected */
  hasSelection: boolean;
  /** Number of selected clips */
  selectionCount: number;
}

// ============ Helpers ============

function generateClipId(): string {
  return `clip-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
}

// ============ Hook ============

export function useClipEditor(options: UseClipEditorOptions = {}): UseClipEditorReturn {
  const {
    onClipChange,
    onClipsDelete,
    onClipSplit,
    onClipsMerge,
    onClipDuplicate,
  } = options;

  const [selectedClipIds, setSelectedClipIds] = useState<string[]>([]);
  const [clipboard, setClipboard] = useState<ClipData[]>([]);

  // Select a single clip
  const selectClip = useCallback((clipId: string, addToSelection = false) => {
    setSelectedClipIds((prev) => {
      if (addToSelection) {
        // Toggle selection
        return prev.includes(clipId)
          ? prev.filter((id) => id !== clipId)
          : [...prev, clipId];
      }
      return [clipId];
    });
  }, []);

  // Select multiple clips
  const selectClips = useCallback((clipIds: string[]) => {
    setSelectedClipIds(clipIds);
  }, []);

  // Clear selection
  const clearSelection = useCallback(() => {
    setSelectedClipIds([]);
  }, []);

  // Select all
  const selectAll = useCallback((allClipIds: string[]) => {
    setSelectedClipIds(allClipIds);
  }, []);

  // Update selected clips
  const updateSelectedClips = useCallback(
    (updates: Partial<ClipData>) => {
      selectedClipIds.forEach((clipId) => {
        onClipChange?.(clipId, updates);
      });
    },
    [selectedClipIds, onClipChange]
  );

  // Delete selected clips
  const deleteSelectedClips = useCallback(() => {
    if (selectedClipIds.length > 0) {
      onClipsDelete?.(selectedClipIds);
      setSelectedClipIds([]);
    }
  }, [selectedClipIds, onClipsDelete]);

  // Split clip at time
  const splitClip = useCallback(
    (clipId: string, splitTime: number) => {
      onClipSplit?.(clipId, splitTime);
    },
    [onClipSplit]
  );

  // Merge selected clips
  const mergeSelectedClips = useCallback(() => {
    if (selectedClipIds.length > 1) {
      onClipsMerge?.(selectedClipIds);
    }
  }, [selectedClipIds, onClipsMerge]);

  // Duplicate selected clips
  const duplicateSelectedClips = useCallback(() => {
    selectedClipIds.forEach((clipId) => {
      onClipDuplicate?.(clipId);
    });
  }, [selectedClipIds, onClipDuplicate]);

  // Copy selected clips
  const copySelectedClips = useCallback((clips: ClipData[]) => {
    const selectedClips = clips.filter((clip) =>
      selectedClipIds.includes(clip.id)
    );
    setClipboard(selectedClips);
  }, [selectedClipIds]);

  // Paste clips
  const pasteClips = useCallback(
    (atTime: number): ClipData[] => {
      if (clipboard.length === 0) return [];

      // Find earliest clip time to calculate offset
      const earliestTime = Math.min(...clipboard.map((c) => c.startTime));
      const timeOffset = atTime - earliestTime;

      // Create new clips with new IDs and adjusted times
      const newClips = clipboard.map((clip) => ({
        ...clip,
        id: generateClipId(),
        startTime: clip.startTime + timeOffset,
      }));

      return newClips;
    },
    [clipboard]
  );

  // Set fade in for selected
  const setFadeIn = useCallback(
    (duration: number, curve?: FadeCurve) => {
      const updates: Partial<ClipData> = { fadeInDuration: duration };
      if (curve) updates.fadeInCurve = curve;
      updateSelectedClips(updates);
    },
    [updateSelectedClips]
  );

  // Set fade out for selected
  const setFadeOut = useCallback(
    (duration: number, curve?: FadeCurve) => {
      const updates: Partial<ClipData> = { fadeOutDuration: duration };
      if (curve) updates.fadeOutCurve = curve;
      updateSelectedClips(updates);
    },
    [updateSelectedClips]
  );

  // Set gain for selected
  const setGain = useCallback(
    (gain: number) => {
      updateSelectedClips({ gain });
    },
    [updateSelectedClips]
  );

  // Normalize gain (placeholder - actual implementation needs audio analysis)
  const normalizeGain = useCallback(() => {
    // Would analyze peak levels and adjust gain
    // For now, just reset to 0dB
    updateSelectedClips({ gain: 0 });
  }, [updateSelectedClips]);

  // Toggle mute for selected
  const toggleMute = useCallback(() => {
    // Toggle based on first selected clip's state
    selectedClipIds.forEach((clipId, index) => {
      // This is a simplified version - real implementation would
      // check current state and toggle appropriately
      onClipChange?.(clipId, { muted: index === 0 }); // Toggle
    });
  }, [selectedClipIds, onClipChange]);

  // Toggle lock for selected
  const toggleLock = useCallback(() => {
    selectedClipIds.forEach((clipId, index) => {
      onClipChange?.(clipId, { locked: index === 0 }); // Toggle
    });
  }, [selectedClipIds, onClipChange]);

  // Computed values
  const hasSelection = selectedClipIds.length > 0;
  const selectionCount = selectedClipIds.length;

  return useMemo(
    () => ({
      selectedClipIds,
      clipboard,
      selectClip,
      selectClips,
      clearSelection,
      selectAll,
      updateSelectedClips,
      deleteSelectedClips,
      splitClip,
      mergeSelectedClips,
      duplicateSelectedClips,
      copySelectedClips,
      pasteClips,
      setFadeIn,
      setFadeOut,
      setGain,
      normalizeGain,
      toggleMute,
      toggleLock,
      hasSelection,
      selectionCount,
    }),
    [
      selectedClipIds,
      clipboard,
      selectClip,
      selectClips,
      clearSelection,
      selectAll,
      updateSelectedClips,
      deleteSelectedClips,
      splitClip,
      mergeSelectedClips,
      duplicateSelectedClips,
      copySelectedClips,
      pasteClips,
      setFadeIn,
      setFadeOut,
      setGain,
      normalizeGain,
      toggleMute,
      toggleLock,
      hasSelection,
      selectionCount,
    ]
  );
}

export default useClipEditor;
