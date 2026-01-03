/**
 * ReelForge Audio Recorder
 *
 * Real-time audio recording with:
 * - MediaRecorder for compressed formats
 * - AudioWorklet for raw PCM capture
 * - Real-time level monitoring
 * - Punch-in/out recording
 *
 * @module audio-engine/AudioRecorder
 */

import { AudioContextManager } from '../core/AudioContextManager';
import { AudioDeviceManager } from './AudioDeviceManager';

// ============ Types ============

export type RecordingFormat = 'wav' | 'webm' | 'mp3' | 'ogg';
export type RecordingState = 'inactive' | 'recording' | 'paused';

export interface RecordingOptions {
  format?: RecordingFormat;
  sampleRate?: number;
  channels?: 1 | 2;
  bitDepth?: 16 | 24 | 32;
  // For compressed formats
  bitRate?: number;
  // Monitoring
  monitorInput?: boolean;
  // Punch in/out
  punchIn?: number; // Start time in seconds
  punchOut?: number; // End time in seconds
}

export interface RecordingResult {
  blob: Blob;
  duration: number;
  sampleRate: number;
  channels: number;
  format: RecordingFormat;
  peakLevel: number;
}

export interface RecorderState {
  state: RecordingState;
  duration: number;
  peakLevel: number;
  rmsLevel: number;
  clipCount: number;
  isMonitoring: boolean;
}

type RecorderListener = (state: RecorderState) => void;
type LevelListener = (peak: number, rms: number) => void;

// ============ Audio Recorder Class ============

class AudioRecorderClass {
  private state: RecorderState = {
    state: 'inactive',
    duration: 0,
    peakLevel: 0,
    rmsLevel: 0,
    clipCount: 0,
    isMonitoring: false,
  };

  private mediaRecorder: MediaRecorder | null = null;
  private recordedChunks: Blob[] = [];
  private audioWorklet: AudioWorkletNode | null = null;
  private rawPcmBuffer: Float32Array[] = [];

  // Audio nodes
  private sourceNode: MediaStreamAudioSourceNode | null = null;
  private analyzerNode: AnalyserNode | null = null;
  private gainNode: GainNode | null = null;
  private monitorNode: GainNode | null = null;

  // Timing
  private startTime = 0;
  private pausedDuration = 0;
  private animationFrame: number | null = null;

  // Listeners
  private stateListeners = new Set<RecorderListener>();
  private levelListeners = new Set<LevelListener>();

  // Options
  private options: RecordingOptions = {};

  /**
   * Start recording.
   */
  async start(options: RecordingOptions = {}): Promise<void> {
    if (this.state.state !== 'inactive') {
      throw new Error('Recording already in progress');
    }

    this.options = {
      format: 'wav',
      sampleRate: 48000,
      channels: 2,
      bitDepth: 24,
      bitRate: 192000,
      monitorInput: false,
      ...options,
    };

    // Get or open input stream
    let stream = AudioDeviceManager.getInputStream();
    if (!stream) {
      stream = await AudioDeviceManager.openInputStream({
        sampleRate: this.options.sampleRate,
        channelCount: this.options.channels,
      });
    }

    const ctx = AudioContextManager.getContext();
    await AudioContextManager.resume();

    // Create audio graph
    this.sourceNode = ctx.createMediaStreamSource(stream);
    this.analyzerNode = ctx.createAnalyser();
    this.analyzerNode.fftSize = 2048;
    this.analyzerNode.smoothingTimeConstant = 0.3;

    this.gainNode = ctx.createGain();
    this.gainNode.gain.value = 1.0;

    // Connect source → gain → analyzer
    this.sourceNode.connect(this.gainNode);
    this.gainNode.connect(this.analyzerNode);

    // Monitor output (optional)
    if (this.options.monitorInput) {
      this.monitorNode = ctx.createGain();
      this.monitorNode.gain.value = 1.0;
      this.analyzerNode.connect(this.monitorNode);
      this.monitorNode.connect(ctx.destination);
      this.updateState({ isMonitoring: true });
    }

    // Start recording based on format
    if (this.options.format === 'wav') {
      await this.startPcmRecording(stream);
    } else {
      this.startMediaRecording(stream);
    }

    // Reset state
    this.startTime = performance.now();
    this.pausedDuration = 0;
    this.rawPcmBuffer = [];
    this.recordedChunks = [];

    this.updateState({
      state: 'recording',
      duration: 0,
      peakLevel: 0,
      rmsLevel: 0,
      clipCount: 0,
    });

    // Start metering
    this.startMetering();
  }

  /**
   * Start PCM recording via ScriptProcessor (AudioWorklet preferred when available).
   */
  private async startPcmRecording(_stream: MediaStream): Promise<void> {
    const ctx = AudioContextManager.getContext();

    // Use ScriptProcessor for now (AudioWorklet requires separate file)
    const bufferSize = 4096;
    const processor = ctx.createScriptProcessor(bufferSize, this.options.channels!, this.options.channels!);

    processor.onaudioprocess = (e: AudioProcessingEvent) => {
      if (this.state.state !== 'recording') return;

      // Capture all input channels
      const channels: Float32Array[] = [];
      for (let ch = 0; ch < e.inputBuffer.numberOfChannels; ch++) {
        channels.push(new Float32Array(e.inputBuffer.getChannelData(ch)));
      }

      // Interleave and store
      const interleaved = this.interleaveChannels(channels);
      this.rawPcmBuffer.push(interleaved);
    };

    // Connect
    this.gainNode!.connect(processor);
    processor.connect(ctx.destination); // Required for ScriptProcessor to work

    this.audioWorklet = processor as unknown as AudioWorkletNode;
  }

  /**
   * Start MediaRecorder for compressed formats.
   */
  private startMediaRecording(stream: MediaStream): void {
    const mimeType = this.getMimeType(this.options.format!);

    if (!MediaRecorder.isTypeSupported(mimeType)) {
      throw new Error(`Format ${this.options.format} not supported`);
    }

    this.mediaRecorder = new MediaRecorder(stream, {
      mimeType,
      audioBitsPerSecond: this.options.bitRate,
    });

    this.mediaRecorder.ondataavailable = (e) => {
      if (e.data.size > 0) {
        this.recordedChunks.push(e.data);
      }
    };

    this.mediaRecorder.start(100); // Collect data every 100ms
  }

  /**
   * Pause recording.
   */
  pause(): void {
    if (this.state.state !== 'recording') return;

    if (this.mediaRecorder?.state === 'recording') {
      this.mediaRecorder.pause();
    }

    this.pausedDuration += performance.now() - this.startTime;
    this.updateState({ state: 'paused' });
  }

  /**
   * Resume recording.
   */
  resume(): void {
    if (this.state.state !== 'paused') return;

    if (this.mediaRecorder?.state === 'paused') {
      this.mediaRecorder.resume();
    }

    this.startTime = performance.now();
    this.updateState({ state: 'recording' });
  }

  /**
   * Stop recording and return result.
   */
  async stop(): Promise<RecordingResult> {
    if (this.state.state === 'inactive') {
      throw new Error('No recording in progress');
    }

    // Stop metering
    this.stopMetering();

    // Stop nodes
    if (this.audioWorklet) {
      this.audioWorklet.disconnect();
      this.audioWorklet = null;
    }

    if (this.monitorNode) {
      this.monitorNode.disconnect();
      this.monitorNode = null;
    }

    if (this.analyzerNode) {
      this.analyzerNode.disconnect();
      this.analyzerNode = null;
    }

    if (this.gainNode) {
      this.gainNode.disconnect();
      this.gainNode = null;
    }

    if (this.sourceNode) {
      this.sourceNode.disconnect();
      this.sourceNode = null;
    }

    // Calculate duration
    const duration = this.state.duration;

    let blob: Blob;
    let format = this.options.format!;

    if (this.options.format === 'wav') {
      // Create WAV from PCM buffer
      blob = this.createWavBlob();
    } else {
      // Stop MediaRecorder and wait for final chunk
      await new Promise<void>((resolve) => {
        if (this.mediaRecorder) {
          this.mediaRecorder.onstop = () => resolve();
          this.mediaRecorder.stop();
        } else {
          resolve();
        }
      });

      blob = new Blob(this.recordedChunks, { type: this.getMimeType(format) });
    }

    // Reset state
    const peakLevel = this.state.peakLevel;
    this.updateState({
      state: 'inactive',
      duration: 0,
      peakLevel: 0,
      rmsLevel: 0,
      isMonitoring: false,
    });

    this.mediaRecorder = null;
    this.recordedChunks = [];
    this.rawPcmBuffer = [];

    return {
      blob,
      duration,
      sampleRate: this.options.sampleRate!,
      channels: this.options.channels!,
      format,
      peakLevel,
    };
  }

  /**
   * Cancel recording without saving.
   */
  cancel(): void {
    if (this.state.state === 'inactive') return;

    this.stopMetering();

    // Disconnect everything
    this.audioWorklet?.disconnect();
    this.monitorNode?.disconnect();
    this.analyzerNode?.disconnect();
    this.gainNode?.disconnect();
    this.sourceNode?.disconnect();

    if (this.mediaRecorder?.state !== 'inactive') {
      this.mediaRecorder?.stop();
    }

    this.audioWorklet = null;
    this.monitorNode = null;
    this.analyzerNode = null;
    this.gainNode = null;
    this.sourceNode = null;
    this.mediaRecorder = null;
    this.recordedChunks = [];
    this.rawPcmBuffer = [];

    this.updateState({
      state: 'inactive',
      duration: 0,
      peakLevel: 0,
      rmsLevel: 0,
      clipCount: 0,
      isMonitoring: false,
    });
  }

  /**
   * Set input gain (0-2, 1 = unity).
   */
  setInputGain(value: number): void {
    if (this.gainNode) {
      this.gainNode.gain.value = Math.max(0, Math.min(2, value));
    }
  }

  /**
   * Set monitor gain.
   */
  setMonitorGain(value: number): void {
    if (this.monitorNode) {
      this.monitorNode.gain.value = Math.max(0, Math.min(2, value));
    }
  }

  /**
   * Toggle monitoring on/off.
   */
  toggleMonitoring(enabled: boolean): void {
    if (!this.sourceNode) return;

    const ctx = AudioContextManager.getContext();

    if (enabled && !this.monitorNode) {
      this.monitorNode = ctx.createGain();
      this.monitorNode.gain.value = 1.0;
      this.analyzerNode?.connect(this.monitorNode);
      this.monitorNode.connect(ctx.destination);
    } else if (!enabled && this.monitorNode) {
      this.monitorNode.disconnect();
      this.monitorNode = null;
    }

    this.updateState({ isMonitoring: enabled });
  }

  /**
   * Start metering animation loop.
   */
  private startMetering(): void {
    const analyzerData = new Float32Array(this.analyzerNode?.fftSize || 2048);

    const updateMeter = () => {
      if (!this.analyzerNode || this.state.state === 'inactive') return;

      this.analyzerNode.getFloatTimeDomainData(analyzerData);

      // Calculate peak and RMS
      let peak = 0;
      let sumSquares = 0;

      for (let i = 0; i < analyzerData.length; i++) {
        const sample = Math.abs(analyzerData[i]);
        if (sample > peak) peak = sample;
        sumSquares += sample * sample;
      }

      const rms = Math.sqrt(sumSquares / analyzerData.length);

      // Check for clipping
      let clipCount = this.state.clipCount;
      if (peak >= 0.99) clipCount++;

      // Update duration
      let duration = this.state.duration;
      if (this.state.state === 'recording') {
        duration = (performance.now() - this.startTime + this.pausedDuration) / 1000;
      }

      this.updateState({ peakLevel: peak, rmsLevel: rms, clipCount, duration });

      // Notify level listeners
      this.levelListeners.forEach(fn => fn(peak, rms));

      this.animationFrame = requestAnimationFrame(updateMeter);
    };

    updateMeter();
  }

  /**
   * Stop metering.
   */
  private stopMetering(): void {
    if (this.animationFrame !== null) {
      cancelAnimationFrame(this.animationFrame);
      this.animationFrame = null;
    }
  }

  /**
   * Interleave multi-channel audio.
   */
  private interleaveChannels(channels: Float32Array[]): Float32Array {
    if (channels.length === 1) return channels[0];

    const length = channels[0].length;
    const numChannels = channels.length;
    const result = new Float32Array(length * numChannels);

    for (let i = 0; i < length; i++) {
      for (let ch = 0; ch < numChannels; ch++) {
        result[i * numChannels + ch] = channels[ch][i];
      }
    }

    return result;
  }

  /**
   * Create WAV blob from PCM buffer.
   */
  private createWavBlob(): Blob {
    // Concatenate all buffers
    const totalLength = this.rawPcmBuffer.reduce((sum, buf) => sum + buf.length, 0);
    const pcmData = new Float32Array(totalLength);

    let offset = 0;
    for (const buf of this.rawPcmBuffer) {
      pcmData.set(buf, offset);
      offset += buf.length;
    }

    // Convert to Int16 for standard WAV
    const numChannels = this.options.channels!;
    const sampleRate = this.options.sampleRate!;
    const bytesPerSample = this.options.bitDepth === 16 ? 2 : this.options.bitDepth === 24 ? 3 : 4;
    const numSamples = pcmData.length / numChannels;

    // WAV header
    const headerSize = 44;
    const dataSize = numSamples * numChannels * bytesPerSample;
    const buffer = new ArrayBuffer(headerSize + dataSize);
    const view = new DataView(buffer);

    // RIFF header
    this.writeString(view, 0, 'RIFF');
    view.setUint32(4, 36 + dataSize, true);
    this.writeString(view, 8, 'WAVE');

    // fmt chunk
    this.writeString(view, 12, 'fmt ');
    view.setUint32(16, 16, true); // chunk size
    view.setUint16(20, bytesPerSample === 4 ? 3 : 1, true); // format (1=PCM, 3=IEEE float)
    view.setUint16(22, numChannels, true);
    view.setUint32(24, sampleRate, true);
    view.setUint32(28, sampleRate * numChannels * bytesPerSample, true);
    view.setUint16(32, numChannels * bytesPerSample, true);
    view.setUint16(34, bytesPerSample * 8, true);

    // data chunk
    this.writeString(view, 36, 'data');
    view.setUint32(40, dataSize, true);

    // Write samples
    if (bytesPerSample === 2) {
      // 16-bit
      for (let i = 0; i < pcmData.length; i++) {
        const sample = Math.max(-1, Math.min(1, pcmData[i]));
        view.setInt16(headerSize + i * 2, sample * 0x7FFF, true);
      }
    } else if (bytesPerSample === 4) {
      // 32-bit float
      for (let i = 0; i < pcmData.length; i++) {
        view.setFloat32(headerSize + i * 4, pcmData[i], true);
      }
    } else {
      // 24-bit
      for (let i = 0; i < pcmData.length; i++) {
        const sample = Math.max(-1, Math.min(1, pcmData[i]));
        const intSample = Math.floor(sample * 0x7FFFFF);
        const byteOffset = headerSize + i * 3;
        view.setUint8(byteOffset, intSample & 0xFF);
        view.setUint8(byteOffset + 1, (intSample >> 8) & 0xFF);
        view.setUint8(byteOffset + 2, (intSample >> 16) & 0xFF);
      }
    }

    return new Blob([buffer], { type: 'audio/wav' });
  }

  /**
   * Write string to DataView.
   */
  private writeString(view: DataView, offset: number, str: string): void {
    for (let i = 0; i < str.length; i++) {
      view.setUint8(offset + i, str.charCodeAt(i));
    }
  }

  /**
   * Get MIME type for format.
   */
  private getMimeType(format: RecordingFormat): string {
    const types: Record<RecordingFormat, string> = {
      wav: 'audio/wav',
      webm: 'audio/webm;codecs=opus',
      mp3: 'audio/mpeg',
      ogg: 'audio/ogg;codecs=opus',
    };
    return types[format];
  }

  /**
   * Get current state.
   */
  getState(): Readonly<RecorderState> {
    return { ...this.state };
  }

  /**
   * Subscribe to state changes.
   */
  subscribe(listener: RecorderListener): () => void {
    this.stateListeners.add(listener);
    return () => this.stateListeners.delete(listener);
  }

  /**
   * Subscribe to level updates (called every frame).
   */
  onLevelChange(listener: LevelListener): () => void {
    this.levelListeners.add(listener);
    return () => this.levelListeners.delete(listener);
  }

  /**
   * Update state and notify listeners.
   */
  private updateState(partial: Partial<RecorderState>): void {
    this.state = { ...this.state, ...partial };
    this.stateListeners.forEach(fn => fn(this.state));
  }

  /**
   * Check supported formats.
   */
  getSupportedFormats(): RecordingFormat[] {
    const formats: RecordingFormat[] = ['wav']; // WAV always supported

    if (MediaRecorder.isTypeSupported('audio/webm;codecs=opus')) {
      formats.push('webm');
    }
    if (MediaRecorder.isTypeSupported('audio/ogg;codecs=opus')) {
      formats.push('ogg');
    }
    if (MediaRecorder.isTypeSupported('audio/mpeg')) {
      formats.push('mp3');
    }

    return formats;
  }
}

// Singleton instance
export const AudioRecorder = new AudioRecorderClass();
