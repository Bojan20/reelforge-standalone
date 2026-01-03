/**
 * ReelForge Audio Device Manager
 *
 * Manages audio input/output device enumeration and selection.
 * Provides real-time device change monitoring.
 *
 * @module audio-engine/AudioDeviceManager
 */

export interface AudioDeviceInfo {
  deviceId: string;
  label: string;
  kind: 'audioinput' | 'audiooutput';
  groupId: string;
  isDefault: boolean;
}

export interface AudioDeviceState {
  inputs: AudioDeviceInfo[];
  outputs: AudioDeviceInfo[];
  selectedInputId: string | null;
  selectedOutputId: string | null;
  hasPermission: boolean;
  isEnumerating: boolean;
  error: string | null;
}

type DeviceChangeListener = (state: AudioDeviceState) => void;

class AudioDeviceManagerClass {
  private state: AudioDeviceState = {
    inputs: [],
    outputs: [],
    selectedInputId: null,
    selectedOutputId: null,
    hasPermission: false,
    isEnumerating: false,
    error: null,
  };

  private listeners = new Set<DeviceChangeListener>();
  private mediaStream: MediaStream | null = null;

  constructor() {
    // Listen for device changes
    if (typeof navigator !== 'undefined' && navigator.mediaDevices) {
      navigator.mediaDevices.addEventListener('devicechange', () => {
        this.enumerateDevices();
      });
    }
  }

  /**
   * Request microphone permission and enumerate devices.
   */
  async requestPermission(): Promise<boolean> {
    if (!navigator.mediaDevices?.getUserMedia) {
      this.updateState({ error: 'getUserMedia not supported' });
      return false;
    }

    try {
      // Request temporary stream to get permission
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });

      // Stop the stream immediately - we just needed permission
      stream.getTracks().forEach(track => track.stop());

      this.updateState({ hasPermission: true, error: null });
      await this.enumerateDevices();
      return true;
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Permission denied';
      this.updateState({ hasPermission: false, error: message });
      return false;
    }
  }

  /**
   * Enumerate all audio devices.
   */
  async enumerateDevices(): Promise<void> {
    if (!navigator.mediaDevices?.enumerateDevices) {
      this.updateState({ error: 'Device enumeration not supported' });
      return;
    }

    this.updateState({ isEnumerating: true });

    try {
      const devices = await navigator.mediaDevices.enumerateDevices();

      const inputs: AudioDeviceInfo[] = [];
      const outputs: AudioDeviceInfo[] = [];

      let defaultInputId: string | null = null;
      let defaultOutputId: string | null = null;

      for (const device of devices) {
        if (device.kind === 'audioinput') {
          const isDefault = device.deviceId === 'default' ||
            device.label.toLowerCase().includes('default');

          inputs.push({
            deviceId: device.deviceId,
            label: device.label || `Microphone ${inputs.length + 1}`,
            kind: 'audioinput',
            groupId: device.groupId,
            isDefault,
          });

          if (isDefault) defaultInputId = device.deviceId;
        } else if (device.kind === 'audiooutput') {
          const isDefault = device.deviceId === 'default' ||
            device.label.toLowerCase().includes('default');

          outputs.push({
            deviceId: device.deviceId,
            label: device.label || `Speaker ${outputs.length + 1}`,
            kind: 'audiooutput',
            groupId: device.groupId,
            isDefault,
          });

          if (isDefault) defaultOutputId = device.deviceId;
        }
      }

      // Select defaults if not already selected
      const selectedInputId = this.state.selectedInputId || defaultInputId || inputs[0]?.deviceId || null;
      const selectedOutputId = this.state.selectedOutputId || defaultOutputId || outputs[0]?.deviceId || null;

      this.updateState({
        inputs,
        outputs,
        selectedInputId,
        selectedOutputId,
        isEnumerating: false,
        error: null,
      });
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to enumerate devices';
      this.updateState({ isEnumerating: false, error: message });
    }
  }

  /**
   * Select input device.
   */
  selectInput(deviceId: string): void {
    if (this.state.inputs.some(d => d.deviceId === deviceId)) {
      this.updateState({ selectedInputId: deviceId });

      // If we have an active stream, recreate it with new device
      if (this.mediaStream) {
        this.openInputStream();
      }
    }
  }

  /**
   * Select output device.
   * Note: Output device selection requires setSinkId on audio elements.
   */
  selectOutput(deviceId: string): void {
    if (this.state.outputs.some(d => d.deviceId === deviceId)) {
      this.updateState({ selectedOutputId: deviceId });
    }
  }

  /**
   * Open input stream from selected device.
   */
  async openInputStream(constraints?: MediaTrackConstraints): Promise<MediaStream> {
    if (!this.state.selectedInputId) {
      throw new Error('No input device selected');
    }

    // Close existing stream
    this.closeInputStream();

    const stream = await navigator.mediaDevices.getUserMedia({
      audio: {
        deviceId: { exact: this.state.selectedInputId },
        echoCancellation: constraints?.echoCancellation ?? false,
        noiseSuppression: constraints?.noiseSuppression ?? false,
        autoGainControl: constraints?.autoGainControl ?? false,
        sampleRate: constraints?.sampleRate,
        channelCount: constraints?.channelCount ?? 2,
      },
    });

    this.mediaStream = stream;
    return stream;
  }

  /**
   * Close input stream.
   */
  closeInputStream(): void {
    if (this.mediaStream) {
      this.mediaStream.getTracks().forEach(track => track.stop());
      this.mediaStream = null;
    }
  }

  /**
   * Get current input stream.
   */
  getInputStream(): MediaStream | null {
    return this.mediaStream;
  }

  /**
   * Set output device on an audio element.
   */
  async setOutputDevice(element: HTMLMediaElement): Promise<void> {
    if (!this.state.selectedOutputId) return;

    // Check if setSinkId is supported
    if ('setSinkId' in element && typeof (element as HTMLMediaElement & { setSinkId: (id: string) => Promise<void> }).setSinkId === 'function') {
      await (element as HTMLMediaElement & { setSinkId: (id: string) => Promise<void> }).setSinkId(this.state.selectedOutputId);
    }
  }

  /**
   * Get current state.
   */
  getState(): Readonly<AudioDeviceState> {
    return { ...this.state };
  }

  /**
   * Subscribe to state changes.
   */
  subscribe(listener: DeviceChangeListener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  /**
   * Update state and notify listeners.
   */
  private updateState(partial: Partial<AudioDeviceState>): void {
    this.state = { ...this.state, ...partial };
    this.listeners.forEach(fn => fn(this.state));
  }

  /**
   * Check if audio devices are supported.
   */
  isSupported(): boolean {
    return typeof navigator !== 'undefined' &&
      !!navigator.mediaDevices?.enumerateDevices &&
      !!navigator.mediaDevices?.getUserMedia;
  }

  /**
   * Dispose and cleanup.
   */
  dispose(): void {
    this.closeInputStream();
    this.listeners.clear();
  }
}

// Singleton instance
export const AudioDeviceManager = new AudioDeviceManagerClass();
