/**
 * ReelForge Offline Bounce Engine
 *
 * High-quality offline rendering and export.
 * Supports various formats and quality settings.
 *
 * @module audio-processing/OfflineBounce
 */

// ============ Types ============

export type ExportFormat = 'wav' | 'mp3' | 'ogg' | 'flac' | 'aac';
export type BitDepth = 16 | 24 | 32;
export type SampleRateOption = 44100 | 48000 | 88200 | 96000 | 192000;

export interface BounceOptions {
  format: ExportFormat;
  sampleRate: SampleRateOption;
  bitDepth: BitDepth;
  channels: 1 | 2;
  normalize?: boolean;
  normalizeTarget?: number; // dB
  dither?: boolean;
  ditherType?: 'triangular' | 'rectangular' | 'noise-shaped';
}

export interface BounceRegion {
  startTime: number; // In seconds
  endTime: number;
  fadeIn?: number; // In seconds
  fadeOut?: number;
}

export interface BounceProgress {
  phase: 'preparing' | 'rendering' | 'encoding' | 'finalizing';
  progress: number; // 0-100
  currentTime?: number;
  totalTime?: number;
}

export interface BounceResult {
  blob: Blob;
  duration: number;
  peakLevel: number;
  clipCount: number;
  fileSize: number;
  processingTime: number;
}

export type ProgressCallback = (progress: BounceProgress) => void;

// ============ WAV Encoder ============

class WavEncoder {
  /**
   * Encode audio buffer to WAV format.
   */
  encode(
    audioBuffer: AudioBuffer,
    bitDepth: BitDepth = 16,
    dither: boolean = false
  ): ArrayBuffer {
    const numChannels = audioBuffer.numberOfChannels;
    const sampleRate = audioBuffer.sampleRate;
    const length = audioBuffer.length;
    const bytesPerSample = bitDepth / 8;
    const dataSize = length * numChannels * bytesPerSample;

    // WAV header is 44 bytes
    const buffer = new ArrayBuffer(44 + dataSize);
    const view = new DataView(buffer);

    // RIFF header
    this.writeString(view, 0, 'RIFF');
    view.setUint32(4, 36 + dataSize, true);
    this.writeString(view, 8, 'WAVE');

    // fmt chunk
    this.writeString(view, 12, 'fmt ');
    view.setUint32(16, 16, true); // Chunk size
    view.setUint16(20, bitDepth === 32 ? 3 : 1, true); // Format (1 = PCM, 3 = Float)
    view.setUint16(22, numChannels, true);
    view.setUint32(24, sampleRate, true);
    view.setUint32(28, sampleRate * numChannels * bytesPerSample, true);
    view.setUint16(32, numChannels * bytesPerSample, true);
    view.setUint16(34, bitDepth, true);

    // data chunk
    this.writeString(view, 36, 'data');
    view.setUint32(40, dataSize, true);

    // Interleave and write samples
    const channels: Float32Array[] = [];
    for (let ch = 0; ch < numChannels; ch++) {
      channels.push(audioBuffer.getChannelData(ch));
    }

    let offset = 44;
    const ditherScale = dither ? (1 / Math.pow(2, bitDepth - 1)) : 0;

    for (let i = 0; i < length; i++) {
      for (let ch = 0; ch < numChannels; ch++) {
        let sample = channels[ch][i];

        // Apply dither
        if (dither && bitDepth < 32) {
          sample += (Math.random() - 0.5) * ditherScale;
        }

        // Clamp
        sample = Math.max(-1, Math.min(1, sample));

        if (bitDepth === 16) {
          const int16 = Math.round(sample * 32767);
          view.setInt16(offset, int16, true);
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

    return buffer;
  }

  private writeString(view: DataView, offset: number, str: string): void {
    for (let i = 0; i < str.length; i++) {
      view.setUint8(offset + i, str.charCodeAt(i));
    }
  }
}

// ============ Offline Bounce Engine ============

export class OfflineBounceEngine {
  private wavEncoder = new WavEncoder();

  /**
   * Bounce audio buffer to file.
   */
  async bounce(
    audioBuffer: AudioBuffer,
    options: BounceOptions,
    onProgress?: ProgressCallback
  ): Promise<BounceResult> {
    const startTime = performance.now();

    onProgress?.({ phase: 'preparing', progress: 0 });

    // Analyze input
    let peakLevel = 0;
    let clipCount = 0;

    for (let ch = 0; ch < audioBuffer.numberOfChannels; ch++) {
      const data = audioBuffer.getChannelData(ch);
      for (let i = 0; i < data.length; i++) {
        const abs = Math.abs(data[i]);
        if (abs > peakLevel) peakLevel = abs;
        if (abs > 1.0) clipCount++;
      }
    }

    // Resample if needed
    let processedBuffer = audioBuffer;
    if (options.sampleRate !== audioBuffer.sampleRate) {
      onProgress?.({ phase: 'rendering', progress: 10 });
      processedBuffer = await this.resample(audioBuffer, options.sampleRate);
    }

    // Convert channels if needed
    if (options.channels !== processedBuffer.numberOfChannels) {
      onProgress?.({ phase: 'rendering', progress: 30 });
      processedBuffer = this.convertChannels(processedBuffer, options.channels);
    }

    // Normalize if requested
    if (options.normalize && peakLevel > 0) {
      onProgress?.({ phase: 'rendering', progress: 50 });
      const targetLinear = Math.pow(10, (options.normalizeTarget ?? -0.1) / 20);
      const gain = targetLinear / peakLevel;
      processedBuffer = this.applyGain(processedBuffer, gain);
    }

    onProgress?.({ phase: 'encoding', progress: 70 });

    // Encode
    let blob: Blob;

    switch (options.format) {
      case 'wav':
        const wavBuffer = this.wavEncoder.encode(
          processedBuffer,
          options.bitDepth,
          options.dither
        );
        blob = new Blob([wavBuffer], { type: 'audio/wav' });
        break;

      case 'mp3':
      case 'ogg':
      case 'flac':
      case 'aac':
        // For other formats, we'd need external encoders
        // Fall back to WAV for now
        const fallbackBuffer = this.wavEncoder.encode(processedBuffer, options.bitDepth);
        blob = new Blob([fallbackBuffer], { type: 'audio/wav' });
        break;

      default:
        throw new Error(`Unsupported format: ${options.format}`);
    }

    onProgress?.({ phase: 'finalizing', progress: 100 });

    return {
      blob,
      duration: processedBuffer.duration,
      peakLevel,
      clipCount,
      fileSize: blob.size,
      processingTime: performance.now() - startTime,
    };
  }

  /**
   * Bounce a region of audio.
   */
  async bounceRegion(
    audioBuffer: AudioBuffer,
    region: BounceRegion,
    options: BounceOptions,
    onProgress?: ProgressCallback
  ): Promise<BounceResult> {
    const startSample = Math.floor(region.startTime * audioBuffer.sampleRate);
    const endSample = Math.min(
      Math.ceil(region.endTime * audioBuffer.sampleRate),
      audioBuffer.length
    );
    const regionLength = endSample - startSample;

    // Create region buffer
    const offlineContext = new OfflineAudioContext(
      audioBuffer.numberOfChannels,
      regionLength,
      audioBuffer.sampleRate
    );

    const regionBuffer = offlineContext.createBuffer(
      audioBuffer.numberOfChannels,
      regionLength,
      audioBuffer.sampleRate
    );

    for (let ch = 0; ch < audioBuffer.numberOfChannels; ch++) {
      const sourceData = audioBuffer.getChannelData(ch);
      const destData = regionBuffer.getChannelData(ch);

      for (let i = 0; i < regionLength; i++) {
        destData[i] = sourceData[startSample + i];
      }
    }

    // Apply fades if specified
    if (region.fadeIn && region.fadeIn > 0) {
      this.applyFade(regionBuffer, region.fadeIn, true);
    }
    if (region.fadeOut && region.fadeOut > 0) {
      this.applyFade(regionBuffer, region.fadeOut, false);
    }

    return this.bounce(regionBuffer, options, onProgress);
  }

  /**
   * Bounce multiple tracks mixed together.
   */
  async bounceMix(
    tracks: Array<{ buffer: AudioBuffer; gain: number; pan: number }>,
    duration: number,
    sampleRate: number,
    options: BounceOptions,
    onProgress?: ProgressCallback
  ): Promise<BounceResult> {
    const length = Math.ceil(duration * sampleRate);

    onProgress?.({ phase: 'preparing', progress: 0 });

    // Create mix buffer
    const mixBuffer = new OfflineAudioContext(2, length, sampleRate).createBuffer(
      2,
      length,
      sampleRate
    );

    const leftData = mixBuffer.getChannelData(0);
    const rightData = mixBuffer.getChannelData(1);

    // Mix tracks
    for (let t = 0; t < tracks.length; t++) {
      const track = tracks[t];
      const { buffer, gain, pan } = track;

      // Calculate pan coefficients
      const panAngle = (pan * Math.PI) / 4; // -1 to 1 -> -45deg to 45deg
      const leftGain = gain * Math.cos(panAngle + Math.PI / 4);
      const rightGain = gain * Math.sin(panAngle + Math.PI / 4);

      for (let ch = 0; ch < buffer.numberOfChannels; ch++) {
        const channelData = buffer.getChannelData(ch);

        for (let i = 0; i < Math.min(buffer.length, length); i++) {
          const sample = channelData[i];

          if (buffer.numberOfChannels === 1) {
            // Mono source
            leftData[i] += sample * leftGain;
            rightData[i] += sample * rightGain;
          } else {
            // Stereo source
            if (ch === 0) {
              leftData[i] += sample * gain * (1 - Math.max(0, pan));
            } else {
              rightData[i] += sample * gain * (1 + Math.min(0, pan));
            }
          }
        }
      }

      onProgress?.({
        phase: 'rendering',
        progress: Math.round(((t + 1) / tracks.length) * 60),
      });
    }

    return this.bounce(mixBuffer, options, onProgress);
  }

  /**
   * Resample audio buffer.
   */
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

  /**
   * Convert between mono and stereo.
   */
  private convertChannels(buffer: AudioBuffer, targetChannels: 1 | 2): AudioBuffer {
    const context = new OfflineAudioContext(
      targetChannels,
      buffer.length,
      buffer.sampleRate
    );

    const newBuffer = context.createBuffer(targetChannels, buffer.length, buffer.sampleRate);

    if (targetChannels === 1 && buffer.numberOfChannels === 2) {
      // Stereo to mono
      const left = buffer.getChannelData(0);
      const right = buffer.getChannelData(1);
      const mono = newBuffer.getChannelData(0);

      for (let i = 0; i < buffer.length; i++) {
        mono[i] = (left[i] + right[i]) * 0.5;
      }
    } else if (targetChannels === 2 && buffer.numberOfChannels === 1) {
      // Mono to stereo
      const mono = buffer.getChannelData(0);
      const left = newBuffer.getChannelData(0);
      const right = newBuffer.getChannelData(1);

      for (let i = 0; i < buffer.length; i++) {
        left[i] = mono[i];
        right[i] = mono[i];
      }
    } else {
      // Same channel count
      for (let ch = 0; ch < targetChannels; ch++) {
        newBuffer.copyToChannel(buffer.getChannelData(ch), ch);
      }
    }

    return newBuffer;
  }

  /**
   * Apply gain to buffer.
   */
  private applyGain(buffer: AudioBuffer, gain: number): AudioBuffer {
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
      const srcData = buffer.getChannelData(ch);
      const dstData = newBuffer.getChannelData(ch);

      for (let i = 0; i < buffer.length; i++) {
        dstData[i] = srcData[i] * gain;
      }
    }

    return newBuffer;
  }

  /**
   * Apply fade to buffer.
   */
  private applyFade(buffer: AudioBuffer, duration: number, fadeIn: boolean): void {
    const fadeSamples = Math.min(
      Math.floor(duration * buffer.sampleRate),
      buffer.length
    );

    for (let ch = 0; ch < buffer.numberOfChannels; ch++) {
      const data = buffer.getChannelData(ch);

      for (let i = 0; i < fadeSamples; i++) {
        const t = i / fadeSamples;
        const gain = fadeIn ? t : 1 - t;
        const index = fadeIn ? i : buffer.length - 1 - i;
        data[index] *= gain;
      }
    }
  }

  /**
   * Get supported export formats.
   */
  getSupportedFormats(): ExportFormat[] {
    // Note: MP3, OGG, FLAC, AAC would require external encoders
    return ['wav'];
  }

  /**
   * Get file extension for format.
   */
  getFileExtension(format: ExportFormat): string {
    const extensions: Record<ExportFormat, string> = {
      wav: '.wav',
      mp3: '.mp3',
      ogg: '.ogg',
      flac: '.flac',
      aac: '.m4a',
    };
    return extensions[format];
  }

  /**
   * Get MIME type for format.
   */
  getMimeType(format: ExportFormat): string {
    const mimeTypes: Record<ExportFormat, string> = {
      wav: 'audio/wav',
      mp3: 'audio/mpeg',
      ogg: 'audio/ogg',
      flac: 'audio/flac',
      aac: 'audio/aac',
    };
    return mimeTypes[format];
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
    const bytesPerSample = bitDepth / 8;
    const rawSize = duration * sampleRate * channels * bytesPerSample;

    // Compression ratios (approximate)
    const compressionRatios: Record<ExportFormat, number> = {
      wav: 1.0,
      mp3: 0.1, // ~10:1
      ogg: 0.08, // ~12:1
      flac: 0.5, // ~2:1
      aac: 0.1, // ~10:1
    };

    return Math.round(rawSize * compressionRatios[format]);
  }
}

// ============ Singleton Instance ============

export const offlineBounceEngine = new OfflineBounceEngine();

// ============ Helper Functions ============

/**
 * Download bounce result.
 */
export function downloadBounceResult(
  result: BounceResult,
  filename: string
): void {
  const url = URL.createObjectURL(result.blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = filename;
  link.click();
  URL.revokeObjectURL(url);
}

/**
 * Format file size for display.
 */
export function formatFileSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
}

/**
 * Format duration for display.
 */
export function formatDuration(seconds: number): string {
  const mins = Math.floor(seconds / 60);
  const secs = Math.floor(seconds % 60);
  const ms = Math.floor((seconds % 1) * 1000);
  return `${mins}:${secs.toString().padStart(2, '0')}.${ms.toString().padStart(3, '0')}`;
}
