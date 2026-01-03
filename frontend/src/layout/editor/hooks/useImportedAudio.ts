/**
 * useImportedAudio - Audio Import Hook
 *
 * Manages imported audio files:
 * - File import and processing
 * - IndexedDB persistence
 * - Waveform generation
 * - Sample rate conversion
 *
 * @module layout/editor/hooks/useImportedAudio
 */

import { useState, useCallback, useEffect, useRef } from 'react';
import { rfDebug } from '../../../core/dspMetrics';
import { createAudioBlobUrl } from '../../../utils/audioBufferToWav';
import {
  resampleAudioBuffer,
  needsSampleRateConversion,
  DEFAULT_PROJECT_SAMPLE_RATE,
} from '../../../utils/sampleRateConversion';
import type { ImportOptions } from '../../../components/ImportOptionsDialog';

// ============ Types ============

export interface ImportedFile {
  id: string;
  name: string;
  file: File;
  buffer: AudioBuffer;
  duration: number;
  sampleRate: number;
  channels: number;
  waveform: number[];
  blobUrl: string;
}

export interface UseImportedAudioReturn {
  /** Imported audio files */
  importedFiles: ImportedFile[];
  /** Is importing */
  isImporting: boolean;
  /** Import progress (0-1) */
  importProgress: number;
  /** Import a single file */
  importFile: (file: File, options?: ImportOptions) => Promise<ImportedFile | null>;
  /** Import multiple files */
  importFiles: (files: File[], options?: ImportOptions) => Promise<ImportedFile[]>;
  /** Remove imported file */
  removeFile: (fileId: string) => void;
  /** Remove multiple files */
  removeFiles: (fileIds: string[]) => void;
  /** Clear all imported files */
  clearAll: () => void;
  /** Get file by ID */
  getFile: (fileId: string) => ImportedFile | undefined;
  /** Get AudioBuffer by ID */
  getBuffer: (fileId: string) => AudioBuffer | undefined;
}

// ============ Helpers ============

/**
 * Generate waveform peak data for visualization.
 *
 * Cubase-style: Uses dynamic sample count based on audio duration.
 * Target: ~100 samples per second for smooth display at any zoom level.
 *
 * For 30s audio @ 100 samples/sec = 3000 points (vs old fixed 200)
 */
async function generateWaveform(buffer: AudioBuffer, samplesPerSecond = 100): Promise<number[]> {
  const channelData = buffer.getChannelData(0);
  const duration = buffer.duration;

  // Dynamic sample count: longer audio = more samples
  // Minimum 200, maximum 10000 (for very long files)
  const sampleCount = Math.min(10000, Math.max(200, Math.ceil(duration * samplesPerSecond)));

  const blockSize = Math.floor(channelData.length / sampleCount);
  const waveform: number[] = [];

  for (let i = 0; i < sampleCount; i++) {
    const start = i * blockSize;
    let max = 0;
    for (let j = start; j < start + blockSize && j < channelData.length; j++) {
      const abs = Math.abs(channelData[j]);
      if (abs > max) max = abs;
    }
    waveform.push(max);
  }

  return waveform;
}

let importIdCounter = 0;

// ============ Hook ============

export function useImportedAudio(
  audioContext: AudioContext,
  initialFiles?: File[]
): UseImportedAudioReturn {
  const [importedFiles, setImportedFiles] = useState<ImportedFile[]>([]);
  const [isImporting, setIsImporting] = useState(false);
  const [importProgress, setImportProgress] = useState(0);

  const initialFilesProcessed = useRef(false);

  // Import a single file
  const importFile = useCallback(async (
    file: File,
    options?: ImportOptions
  ): Promise<ImportedFile | null> => {
    try {
      // Read file as ArrayBuffer
      const arrayBuffer = await file.arrayBuffer();

      // Decode audio
      let buffer = await audioContext.decodeAudioData(arrayBuffer.slice(0));

      // Sample rate conversion if needed
      const targetRate = typeof options?.sampleRate === 'number'
        ? options.sampleRate
        : DEFAULT_PROJECT_SAMPLE_RATE;
      if (needsSampleRateConversion(buffer, targetRate)) {
        buffer = await resampleAudioBuffer(buffer, targetRate);
        rfDebug('Import', `Resampled ${file.name} to ${targetRate}Hz`);
      }

      // Generate waveform
      const waveform = await generateWaveform(buffer);

      // Create blob URL for preview
      const blobUrl = createAudioBlobUrl(buffer);

      // Create imported file record
      const imported: ImportedFile = {
        id: `import-${++importIdCounter}-${Date.now()}`,
        name: file.name.replace(/\.[^/.]+$/, ''), // Remove extension
        file,
        buffer,
        duration: buffer.duration,
        sampleRate: buffer.sampleRate,
        channels: buffer.numberOfChannels,
        waveform,
        blobUrl,
      };

      setImportedFiles(prev => [...prev, imported]);
      rfDebug('Import', `Imported ${file.name} (${buffer.duration.toFixed(2)}s)`);

      return imported;
    } catch (error) {
      console.error(`Failed to import ${file.name}:`, error);
      return null;
    }
  }, [audioContext]);

  // Import multiple files
  const importFiles = useCallback(async (
    files: File[],
    options?: ImportOptions
  ): Promise<ImportedFile[]> => {
    if (files.length === 0) return [];

    setIsImporting(true);
    setImportProgress(0);

    const imported: ImportedFile[] = [];

    for (let i = 0; i < files.length; i++) {
      const result = await importFile(files[i], options);
      if (result) {
        imported.push(result);
      }
      setImportProgress((i + 1) / files.length);
    }

    setIsImporting(false);
    setImportProgress(0);

    return imported;
  }, [importFile]);

  // Remove file
  const removeFile = useCallback((fileId: string) => {
    setImportedFiles(prev => {
      const file = prev.find(f => f.id === fileId);
      if (file?.blobUrl) {
        URL.revokeObjectURL(file.blobUrl);
      }
      return prev.filter(f => f.id !== fileId);
    });
  }, []);

  // Remove multiple files
  const removeFiles = useCallback((fileIds: string[]) => {
    const idsSet = new Set(fileIds);
    setImportedFiles(prev => {
      for (const file of prev) {
        if (idsSet.has(file.id) && file.blobUrl) {
          URL.revokeObjectURL(file.blobUrl);
        }
      }
      return prev.filter(f => !idsSet.has(f.id));
    });
  }, []);

  // Clear all
  const clearAll = useCallback(() => {
    // Revoke all blob URLs
    for (const file of importedFiles) {
      if (file.blobUrl) {
        URL.revokeObjectURL(file.blobUrl);
      }
    }
    setImportedFiles([]);
  }, [importedFiles]);

  // Get file by ID
  const getFile = useCallback((fileId: string): ImportedFile | undefined => {
    return importedFiles.find(f => f.id === fileId);
  }, [importedFiles]);

  // Get buffer by ID
  const getBuffer = useCallback((fileId: string): AudioBuffer | undefined => {
    return importedFiles.find(f => f.id === fileId)?.buffer;
  }, [importedFiles]);

  // Process initial files
  useEffect(() => {
    if (initialFiles && initialFiles.length > 0 && !initialFilesProcessed.current) {
      initialFilesProcessed.current = true;
      importFiles(initialFiles);
    }
  }, [initialFiles, importFiles]);

  return {
    importedFiles,
    isImporting,
    importProgress,
    importFile,
    importFiles,
    removeFile,
    removeFiles,
    clearAll,
    getFile,
    getBuffer,
  };
}

export default useImportedAudio;
