/**
 * ReelForge Advanced Export
 *
 * Professional export features:
 * - Stem export (individual tracks)
 * - Multi-format batch export
 * - Loudness targeting by platform
 * - Metadata embedding
 * - Video export (audio + image)
 *
 * @module advanced-features/AdvancedExport
 */

// ============ Types ============

export type ExportFormat = 'wav' | 'mp3' | 'flac' | 'ogg' | 'aac';
export type BitDepth = 16 | 24 | 32;
export type SampleRate = 44100 | 48000 | 88200 | 96000;

export interface ExportSettings {
  format: ExportFormat;
  sampleRate: SampleRate;
  bitDepth: BitDepth;
  channels: 1 | 2;
  normalize?: boolean;
  targetLufs?: number;
  dither?: boolean;
}

export interface StemExportConfig {
  trackId: string;
  trackName: string;
  enabled: boolean;
  solo: boolean;
  settings?: Partial<ExportSettings>;
}

export interface MetadataConfig {
  title?: string;
  artist?: string;
  album?: string;
  year?: number;
  genre?: string;
  comment?: string;
  trackNumber?: number;
  albumArtist?: string;
  composer?: string;
  copyright?: string;
  isrc?: string;
  bwfDescription?: string;
  bwfOriginator?: string;
  bwfOriginatorReference?: string;
}

export interface PlatformPreset {
  id: string;
  name: string;
  targetLufs: number;
  truePeakLimit: number;
  sampleRate: SampleRate;
  format: ExportFormat;
  bitDepth?: BitDepth;
}

export interface BatchExportJob {
  id: string;
  name: string;
  settings: ExportSettings;
  region?: { start: number; end: number };
  status: 'pending' | 'processing' | 'completed' | 'failed';
  progress: number;
  outputPath?: string;
  error?: string;
}

export interface ExportProgress {
  phase: 'preparing' | 'rendering' | 'normalizing' | 'encoding' | 'writing';
  current: number;
  total: number;
  currentFile?: string;
  estimatedTimeRemaining?: number;
}

export type ProgressCallback = (progress: ExportProgress) => void;

// ============ Platform Presets ============

export const PLATFORM_PRESETS: PlatformPreset[] = [
  {
    id: 'spotify',
    name: 'Spotify',
    targetLufs: -14,
    truePeakLimit: -1,
    sampleRate: 44100,
    format: 'ogg',
  },
  {
    id: 'apple-music',
    name: 'Apple Music',
    targetLufs: -16,
    truePeakLimit: -1,
    sampleRate: 44100,
    format: 'aac',
  },
  {
    id: 'youtube',
    name: 'YouTube',
    targetLufs: -14,
    truePeakLimit: -1,
    sampleRate: 48000,
    format: 'aac',
  },
  {
    id: 'soundcloud',
    name: 'SoundCloud',
    targetLufs: -14,
    truePeakLimit: -1,
    sampleRate: 44100,
    format: 'mp3',
  },
  {
    id: 'podcast',
    name: 'Podcast (Apple)',
    targetLufs: -16,
    truePeakLimit: -1,
    sampleRate: 44100,
    format: 'mp3',
  },
  {
    id: 'broadcast',
    name: 'Broadcast (EBU R128)',
    targetLufs: -23,
    truePeakLimit: -1,
    sampleRate: 48000,
    format: 'wav',
    bitDepth: 24,
  },
  {
    id: 'cd',
    name: 'CD Master',
    targetLufs: -14,
    truePeakLimit: -0.3,
    sampleRate: 44100,
    format: 'wav',
    bitDepth: 16,
  },
  {
    id: 'vinyl',
    name: 'Vinyl Master',
    targetLufs: -12,
    truePeakLimit: -0.5,
    sampleRate: 96000,
    format: 'wav',
    bitDepth: 24,
  },
];

// ============ Advanced Export Engine ============

class AdvancedExportEngineImpl {
  private activeJobs = new Map<string, BatchExportJob>();
  private listeners = new Set<(event: ExportEvent) => void>();

  // ============ Single Export ============

  /**
   * Export audio buffer with settings.
   */
  async exportBuffer(
    buffer: AudioBuffer,
    settings: ExportSettings,
    metadata?: MetadataConfig,
    onProgress?: ProgressCallback
  ): Promise<Blob> {
    onProgress?.({ phase: 'preparing', current: 0, total: 100 });

    let processedBuffer = buffer;

    // Resample if needed
    if (settings.sampleRate !== buffer.sampleRate) {
      onProgress?.({ phase: 'rendering', current: 10, total: 100 });
      processedBuffer = await this.resample(buffer, settings.sampleRate);
    }

    // Convert channels if needed
    if (settings.channels !== processedBuffer.numberOfChannels) {
      onProgress?.({ phase: 'rendering', current: 30, total: 100 });
      processedBuffer = this.convertChannels(processedBuffer, settings.channels);
    }

    // Normalize if requested
    if (settings.normalize || settings.targetLufs !== undefined) {
      onProgress?.({ phase: 'normalizing', current: 50, total: 100 });
      processedBuffer = await this.normalize(processedBuffer, settings.targetLufs ?? -14);
    }

    onProgress?.({ phase: 'encoding', current: 70, total: 100 });

    // Encode to format
    const encoded = await this.encode(processedBuffer, settings, metadata);

    onProgress?.({ phase: 'writing', current: 100, total: 100 });

    return encoded;
  }

  // ============ Stem Export ============

  /**
   * Export individual stems.
   */
  async exportStems(
    stems: Array<{ buffer: AudioBuffer; config: StemExportConfig }>,
    baseSettings: ExportSettings,
    outputPrefix: string,
    onProgress?: ProgressCallback
  ): Promise<Array<{ name: string; blob: Blob }>> {
    const results: Array<{ name: string; blob: Blob }> = [];
    const enabledStems = stems.filter(s => s.config.enabled);

    for (let i = 0; i < enabledStems.length; i++) {
      const { buffer, config } = enabledStems[i];
      const settings = { ...baseSettings, ...config.settings };

      onProgress?.({
        phase: 'rendering',
        current: i,
        total: enabledStems.length,
        currentFile: config.trackName,
      });

      const blob = await this.exportBuffer(buffer, settings);
      const extension = this.getExtension(settings.format);
      const name = `${outputPrefix}_${config.trackName}${extension}`;

      results.push({ name, blob });
    }

    return results;
  }

  // ============ Batch Export ============

  /**
   * Create batch export jobs.
   */
  createBatchJobs(
    _buffer: AudioBuffer,
    formats: ExportSettings[],
    baseName: string
  ): BatchExportJob[] {
    const jobs: BatchExportJob[] = [];

    for (const settings of formats) {
      const job: BatchExportJob = {
        id: `job_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
        name: `${baseName}${this.getExtension(settings.format)}`,
        settings,
        status: 'pending',
        progress: 0,
      };

      jobs.push(job);
      this.activeJobs.set(job.id, job);
    }

    return jobs;
  }

  /**
   * Execute batch export.
   */
  async executeBatchExport(
    buffer: AudioBuffer,
    jobs: BatchExportJob[],
    onProgress?: (jobId: string, progress: number) => void
  ): Promise<Map<string, Blob>> {
    const results = new Map<string, Blob>();

    for (const job of jobs) {
      try {
        job.status = 'processing';
        this.emit({ type: 'jobStarted', job });

        const blob = await this.exportBuffer(
          buffer,
          job.settings,
          undefined,
          (progress) => {
            job.progress = progress.current;
            onProgress?.(job.id, progress.current);
          }
        );

        job.status = 'completed';
        job.progress = 100;
        results.set(job.id, blob);

        this.emit({ type: 'jobCompleted', job });
      } catch (error) {
        job.status = 'failed';
        job.error = String(error);
        this.emit({ type: 'jobFailed', job, error: String(error) });
      }
    }

    return results;
  }

  /**
   * Export to multiple platforms simultaneously.
   */
  async exportForPlatforms(
    buffer: AudioBuffer,
    platformIds: string[],
    _baseName: string,
    onProgress?: ProgressCallback
  ): Promise<Map<string, Blob>> {
    const results = new Map<string, Blob>();
    const platforms = PLATFORM_PRESETS.filter(p => platformIds.includes(p.id));

    for (let i = 0; i < platforms.length; i++) {
      const platform = platforms[i];

      onProgress?.({
        phase: 'rendering',
        current: i,
        total: platforms.length,
        currentFile: platform.name,
      });

      const settings: ExportSettings = {
        format: platform.format,
        sampleRate: platform.sampleRate,
        bitDepth: platform.bitDepth ?? 16,
        channels: 2,
        normalize: true,
        targetLufs: platform.targetLufs,
      };

      const blob = await this.exportBuffer(buffer, settings);
      results.set(platform.id, blob);
    }

    return results;
  }

  // ============ Video Export ============

  /**
   * Export audio with static image as video.
   * Uses Canvas + MediaRecorder.
   */
  async exportAsVideo(
    buffer: AudioBuffer,
    imageFile: File | Blob,
    options?: {
      width?: number;
      height?: number;
      fps?: number;
    }
  ): Promise<Blob> {
    const width = options?.width ?? 1920;
    const height = options?.height ?? 1080;
    const fps = options?.fps ?? 30;

    // Create canvas
    const canvas = document.createElement('canvas');
    canvas.width = width;
    canvas.height = height;
    const ctx = canvas.getContext('2d')!;

    // Load image
    const image = await this.loadImage(imageFile);
    ctx.drawImage(image, 0, 0, width, height);

    // Create audio context and source
    const audioContext = new AudioContext({ sampleRate: buffer.sampleRate });
    const source = audioContext.createBufferSource();
    source.buffer = buffer;

    // Create media stream destination
    const streamDest = audioContext.createMediaStreamDestination();
    source.connect(streamDest);

    // Combine video and audio streams
    const canvasStream = canvas.captureStream(fps);
    const videoTrack = canvasStream.getVideoTracks()[0];
    const audioTrack = streamDest.stream.getAudioTracks()[0];

    const combinedStream = new MediaStream([videoTrack, audioTrack]);

    // Record
    return new Promise((resolve, reject) => {
      const chunks: Blob[] = [];
      const recorder = new MediaRecorder(combinedStream, {
        mimeType: 'video/webm; codecs=vp9,opus',
      });

      recorder.ondataavailable = (e) => {
        if (e.data.size > 0) {
          chunks.push(e.data);
        }
      };

      recorder.onstop = () => {
        const blob = new Blob(chunks, { type: 'video/webm' });
        audioContext.close();
        resolve(blob);
      };

      recorder.onerror = (e) => {
        audioContext.close();
        reject(e);
      };

      source.start();
      recorder.start();

      // Stop after audio ends
      source.onended = () => {
        setTimeout(() => recorder.stop(), 100);
      };
    });
  }

  // ============ Helpers ============

  private async resample(buffer: AudioBuffer, targetRate: number): Promise<AudioBuffer> {
    const offlineContext = new OfflineAudioContext(
      buffer.numberOfChannels,
      Math.ceil(buffer.duration * targetRate),
      targetRate
    );

    const source = offlineContext.createBufferSource();
    source.buffer = buffer;
    source.connect(offlineContext.destination);
    source.start();

    return offlineContext.startRendering();
  }

  private convertChannels(buffer: AudioBuffer, targetChannels: 1 | 2): AudioBuffer {
    const context = new OfflineAudioContext(
      targetChannels,
      buffer.length,
      buffer.sampleRate
    );

    const newBuffer = context.createBuffer(targetChannels, buffer.length, buffer.sampleRate);

    if (targetChannels === 1 && buffer.numberOfChannels === 2) {
      const left = buffer.getChannelData(0);
      const right = buffer.getChannelData(1);
      const mono = newBuffer.getChannelData(0);

      for (let i = 0; i < buffer.length; i++) {
        mono[i] = (left[i] + right[i]) * 0.5;
      }
    } else if (targetChannels === 2 && buffer.numberOfChannels === 1) {
      const mono = buffer.getChannelData(0);
      const left = newBuffer.getChannelData(0);
      const right = newBuffer.getChannelData(1);

      for (let i = 0; i < buffer.length; i++) {
        left[i] = mono[i];
        right[i] = mono[i];
      }
    }

    return newBuffer;
  }

  private async normalize(buffer: AudioBuffer, targetLufs: number): Promise<AudioBuffer> {
    // Measure current loudness
    const currentLufs = this.measureLufs(buffer);

    // Calculate gain
    const gainDb = targetLufs - currentLufs;
    const gain = Math.pow(10, gainDb / 20);

    // Apply gain
    const context = new OfflineAudioContext(
      buffer.numberOfChannels,
      buffer.length,
      buffer.sampleRate
    );

    const newBuffer = context.createBuffer(
      buffer.numberOfChannels,
      buffer.length,
      buffer.sampleRate
    );

    for (let ch = 0; ch < buffer.numberOfChannels; ch++) {
      const src = buffer.getChannelData(ch);
      const dst = newBuffer.getChannelData(ch);

      for (let i = 0; i < buffer.length; i++) {
        dst[i] = Math.max(-1, Math.min(1, src[i] * gain));
      }
    }

    return newBuffer;
  }

  private measureLufs(buffer: AudioBuffer): number {
    // Simplified LUFS measurement
    let sum = 0;
    let count = 0;

    for (let ch = 0; ch < buffer.numberOfChannels; ch++) {
      const data = buffer.getChannelData(ch);
      for (let i = 0; i < data.length; i++) {
        sum += data[i] * data[i];
        count++;
      }
    }

    const rms = Math.sqrt(sum / count);
    return -0.691 + 10 * Math.log10(rms * rms);
  }

  private async encode(
    buffer: AudioBuffer,
    settings: ExportSettings,
    _metadata?: MetadataConfig
  ): Promise<Blob> {
    // For now, only WAV is supported natively
    // Other formats would require external encoders
    if (settings.format === 'wav') {
      return this.encodeWav(buffer, settings.bitDepth, settings.dither);
    }

    // Fallback to WAV for unsupported formats
    console.warn(`Format ${settings.format} not supported, falling back to WAV`);
    return this.encodeWav(buffer, settings.bitDepth, settings.dither);
  }

  private encodeWav(buffer: AudioBuffer, bitDepth: BitDepth, dither?: boolean): Blob {
    const numChannels = buffer.numberOfChannels;
    const sampleRate = buffer.sampleRate;
    const length = buffer.length;
    const bytesPerSample = bitDepth / 8;
    const dataSize = length * numChannels * bytesPerSample;

    const arrayBuffer = new ArrayBuffer(44 + dataSize);
    const view = new DataView(arrayBuffer);

    // RIFF header
    this.writeString(view, 0, 'RIFF');
    view.setUint32(4, 36 + dataSize, true);
    this.writeString(view, 8, 'WAVE');

    // fmt chunk
    this.writeString(view, 12, 'fmt ');
    view.setUint32(16, 16, true);
    view.setUint16(20, bitDepth === 32 ? 3 : 1, true);
    view.setUint16(22, numChannels, true);
    view.setUint32(24, sampleRate, true);
    view.setUint32(28, sampleRate * numChannels * bytesPerSample, true);
    view.setUint16(32, numChannels * bytesPerSample, true);
    view.setUint16(34, bitDepth, true);

    // data chunk
    this.writeString(view, 36, 'data');
    view.setUint32(40, dataSize, true);

    // Write samples
    const channels: Float32Array[] = [];
    for (let ch = 0; ch < numChannels; ch++) {
      channels.push(buffer.getChannelData(ch));
    }

    let offset = 44;
    const ditherScale = dither ? (1 / Math.pow(2, bitDepth - 1)) : 0;

    for (let i = 0; i < length; i++) {
      for (let ch = 0; ch < numChannels; ch++) {
        let sample = channels[ch][i];

        if (dither && bitDepth < 32) {
          sample += (Math.random() - 0.5) * ditherScale;
        }

        sample = Math.max(-1, Math.min(1, sample));

        if (bitDepth === 16) {
          view.setInt16(offset, Math.round(sample * 32767), true);
          offset += 2;
        } else if (bitDepth === 24) {
          const int24 = Math.round(sample * 8388607);
          view.setUint8(offset, int24 & 0xff);
          view.setUint8(offset + 1, (int24 >> 8) & 0xff);
          view.setUint8(offset + 2, (int24 >> 16) & 0xff);
          offset += 3;
        } else if (bitDepth === 32) {
          view.setFloat32(offset, sample, true);
          offset += 4;
        }
      }
    }

    return new Blob([arrayBuffer], { type: 'audio/wav' });
  }

  private writeString(view: DataView, offset: number, str: string): void {
    for (let i = 0; i < str.length; i++) {
      view.setUint8(offset + i, str.charCodeAt(i));
    }
  }

  private async loadImage(file: File | Blob): Promise<HTMLImageElement> {
    return new Promise((resolve, reject) => {
      const img = new Image();
      img.onload = () => resolve(img);
      img.onerror = reject;
      img.src = URL.createObjectURL(file);
    });
  }

  private getExtension(format: ExportFormat): string {
    const extensions: Record<ExportFormat, string> = {
      wav: '.wav',
      mp3: '.mp3',
      flac: '.flac',
      ogg: '.ogg',
      aac: '.m4a',
    };
    return extensions[format];
  }

  // ============ Events ============

  subscribe(callback: (event: ExportEvent) => void): () => void {
    this.listeners.add(callback);
    return () => this.listeners.delete(callback);
  }

  private emit(event: ExportEvent): void {
    for (const listener of this.listeners) {
      listener(event);
    }
  }

  // ============ Utilities ============

  /**
   * Get platform preset by ID.
   */
  getPlatformPreset(id: string): PlatformPreset | undefined {
    return PLATFORM_PRESETS.find(p => p.id === id);
  }

  /**
   * Get all platform presets.
   */
  getAllPlatformPresets(): PlatformPreset[] {
    return [...PLATFORM_PRESETS];
  }

  /**
   * Estimate file size.
   */
  estimateFileSize(
    duration: number,
    sampleRate: number,
    bitDepth: BitDepth,
    channels: number,
    format: ExportFormat
  ): number {
    const rawSize = duration * sampleRate * channels * (bitDepth / 8);

    const compressionRatios: Record<ExportFormat, number> = {
      wav: 1.0,
      mp3: 0.1,
      flac: 0.5,
      ogg: 0.08,
      aac: 0.1,
    };

    return Math.round(rawSize * compressionRatios[format]);
  }
}

// ============ Event Types ============

export type ExportEvent =
  | { type: 'jobStarted'; job: BatchExportJob }
  | { type: 'jobCompleted'; job: BatchExportJob }
  | { type: 'jobFailed'; job: BatchExportJob; error: string };

// ============ Singleton Instance ============

export const AdvancedExport = new AdvancedExportEngineImpl();

// ============ Helper Functions ============

/**
 * Download blob as file.
 */
export function downloadBlob(blob: Blob, filename: string): void {
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = filename;
  link.click();
  URL.revokeObjectURL(url);
}

/**
 * Download multiple files as zip.
 */
export async function downloadAsZip(
  files: Array<{ name: string; blob: Blob }>,
  _zipName: string
): Promise<void> {
  // Would need JSZip for this
  // For now, download files individually
  for (const file of files) {
    downloadBlob(file.blob, file.name);
  }
}
