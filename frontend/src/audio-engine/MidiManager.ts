/**
 * ReelForge MIDI Manager
 *
 * Web MIDI API integration for:
 * - MIDI device enumeration
 * - Note on/off events
 * - Control Change (CC) messages
 * - MIDI learn functionality
 * - MIDI clock sync
 *
 * @module audio-engine/MidiManager
 */

// ============ Types ============

export interface MidiDevice {
  id: string;
  name: string;
  manufacturer: string;
  type: 'input' | 'output';
  state: 'connected' | 'disconnected';
  connection: 'open' | 'closed' | 'pending';
}

export interface MidiNoteEvent {
  type: 'noteon' | 'noteoff';
  channel: number; // 0-15
  note: number; // 0-127
  velocity: number; // 0-127
  timestamp: number;
  deviceId: string;
}

export interface MidiCCEvent {
  type: 'cc';
  channel: number;
  controller: number; // 0-127
  value: number; // 0-127
  timestamp: number;
  deviceId: string;
}

export interface MidiPitchBendEvent {
  type: 'pitchbend';
  channel: number;
  value: number; // -8192 to 8191
  timestamp: number;
  deviceId: string;
}

export interface MidiClockEvent {
  type: 'clock' | 'start' | 'stop' | 'continue';
  timestamp: number;
  deviceId: string;
}

export type MidiEvent = MidiNoteEvent | MidiCCEvent | MidiPitchBendEvent | MidiClockEvent;

export interface MidiMapping {
  id: string;
  parameterId: string;
  deviceId: string | null; // null = any device
  channel: number | null; // null = any channel
  controller: number; // CC number
  minValue: number;
  maxValue: number;
  mode: 'absolute' | 'relative';
}

export interface MidiManagerState {
  isSupported: boolean;
  hasAccess: boolean;
  inputs: MidiDevice[];
  outputs: MidiDevice[];
  activeInputs: Set<string>;
  isLearning: boolean;
  learningParameterId: string | null;
}

type MidiEventListener = (event: MidiEvent) => void;
type NoteListener = (event: MidiNoteEvent) => void;
type CCListener = (event: MidiCCEvent) => void;
type StateListener = (state: MidiManagerState) => void;

// ============ MIDI Manager Class ============

class MidiManagerClass {
  private state: MidiManagerState = {
    isSupported: typeof navigator !== 'undefined' && 'requestMIDIAccess' in navigator,
    hasAccess: false,
    inputs: [],
    outputs: [],
    activeInputs: new Set(),
    isLearning: false,
    learningParameterId: null,
  };

  private midiAccess: MIDIAccess | null = null;
  private mappings = new Map<string, MidiMapping>();

  // Listeners
  private eventListeners = new Set<MidiEventListener>();
  private noteListeners = new Set<NoteListener>();
  private ccListeners = new Set<CCListener>();
  private stateListeners = new Set<StateListener>();
  private parameterCallbacks = new Map<string, (value: number) => void>();

  // MIDI clock
  private clockTicks = 0;
  private lastClockTime = 0;
  private calculatedBPM = 0;

  /**
   * Request MIDI access from browser.
   */
  async requestAccess(sysex = false): Promise<boolean> {
    if (!this.state.isSupported) {
      console.warn('Web MIDI not supported');
      return false;
    }

    try {
      this.midiAccess = await navigator.requestMIDIAccess({ sysex });
      this.state.hasAccess = true;

      // Setup state change listener
      this.midiAccess.onstatechange = this.handleStateChange;

      // Enumerate devices
      this.updateDevices();

      this.notifyStateChange();
      return true;
    } catch (err) {
      console.error('MIDI access denied:', err);
      this.state.hasAccess = false;
      return false;
    }
  }

  /**
   * Update device lists from MIDI access.
   */
  private updateDevices(): void {
    if (!this.midiAccess) return;

    const inputs: MidiDevice[] = [];
    const outputs: MidiDevice[] = [];

    this.midiAccess.inputs.forEach((input) => {
      inputs.push({
        id: input.id,
        name: input.name || 'Unknown Input',
        manufacturer: input.manufacturer || 'Unknown',
        type: 'input',
        state: input.state,
        connection: input.connection,
      });
    });

    this.midiAccess.outputs.forEach((output) => {
      outputs.push({
        id: output.id,
        name: output.name || 'Unknown Output',
        manufacturer: output.manufacturer || 'Unknown',
        type: 'output',
        state: output.state,
        connection: output.connection,
      });
    });

    this.state.inputs = inputs;
    this.state.outputs = outputs;
  }

  /**
   * Handle MIDI device state changes.
   */
  private handleStateChange = (event: MIDIConnectionEvent): void => {
    this.updateDevices();

    // Re-attach listeners if device reconnected
    if (event.port?.type === 'input' && event.port.state === 'connected') {
      if (this.state.activeInputs.has(event.port.id)) {
        this.attachInputListener(event.port.id);
      }
    }

    this.notifyStateChange();
  };

  /**
   * Enable input device for listening.
   */
  enableInput(deviceId: string): void {
    if (!this.midiAccess) return;

    const input = this.midiAccess.inputs.get(deviceId);
    if (!input) return;

    this.attachInputListener(deviceId);
    this.state.activeInputs.add(deviceId);
    this.notifyStateChange();
  }

  /**
   * Disable input device.
   */
  disableInput(deviceId: string): void {
    if (!this.midiAccess) return;

    const input = this.midiAccess.inputs.get(deviceId);
    if (input) {
      input.onmidimessage = null;
    }

    this.state.activeInputs.delete(deviceId);
    this.notifyStateChange();
  }

  /**
   * Enable all inputs.
   */
  enableAllInputs(): void {
    this.state.inputs.forEach(device => {
      this.enableInput(device.id);
    });
  }

  /**
   * Attach message listener to input.
   */
  private attachInputListener(deviceId: string): void {
    if (!this.midiAccess) return;

    const input = this.midiAccess.inputs.get(deviceId);
    if (!input) return;

    input.onmidimessage = (message: MIDIMessageEvent) => {
      this.handleMidiMessage(message, deviceId);
    };
  }

  /**
   * Handle incoming MIDI message.
   */
  private handleMidiMessage(message: MIDIMessageEvent, deviceId: string): void {
    const data = message.data;
    if (!data || data.length === 0) return;

    const status = data[0];
    const channel = status & 0x0F;
    const type = status & 0xF0;
    const timestamp = message.timeStamp;

    let event: MidiEvent | null = null;

    switch (type) {
      case 0x90: // Note On
        if (data[2] > 0) {
          event = {
            type: 'noteon',
            channel,
            note: data[1],
            velocity: data[2],
            timestamp,
            deviceId,
          };
          this.noteListeners.forEach(fn => fn(event as MidiNoteEvent));
        } else {
          // Velocity 0 = Note Off
          event = {
            type: 'noteoff',
            channel,
            note: data[1],
            velocity: 0,
            timestamp,
            deviceId,
          };
          this.noteListeners.forEach(fn => fn(event as MidiNoteEvent));
        }
        break;

      case 0x80: // Note Off
        event = {
          type: 'noteoff',
          channel,
          note: data[1],
          velocity: data[2],
          timestamp,
          deviceId,
        };
        this.noteListeners.forEach(fn => fn(event as MidiNoteEvent));
        break;

      case 0xB0: // Control Change
        event = {
          type: 'cc',
          channel,
          controller: data[1],
          value: data[2],
          timestamp,
          deviceId,
        };
        this.ccListeners.forEach(fn => fn(event as MidiCCEvent));
        this.handleCCMapping(event as MidiCCEvent);
        break;

      case 0xE0: // Pitch Bend
        const bendValue = (data[2] << 7) | data[1];
        event = {
          type: 'pitchbend',
          channel,
          value: bendValue - 8192,
          timestamp,
          deviceId,
        };
        break;

      case 0xF0: // System messages
        if (status === 0xF8) {
          // MIDI Clock
          this.handleClock(timestamp, deviceId);
          event = { type: 'clock', timestamp, deviceId };
        } else if (status === 0xFA) {
          event = { type: 'start', timestamp, deviceId };
        } else if (status === 0xFC) {
          event = { type: 'stop', timestamp, deviceId };
        } else if (status === 0xFB) {
          event = { type: 'continue', timestamp, deviceId };
        }
        break;
    }

    if (event) {
      this.eventListeners.forEach(fn => fn(event!));
    }

    // Handle MIDI learn
    if (this.state.isLearning && event?.type === 'cc') {
      this.completeLearning(event as MidiCCEvent);
    }
  }

  /**
   * Handle MIDI clock for tempo sync.
   */
  private handleClock(timestamp: number, _deviceId: string): void {
    this.clockTicks++;

    // 24 ticks per quarter note
    if (this.clockTicks >= 24) {
      const elapsed = timestamp - this.lastClockTime;
      if (elapsed > 0) {
        this.calculatedBPM = 60000 / elapsed;
      }
      this.lastClockTime = timestamp;
      this.clockTicks = 0;
    }
  }

  /**
   * Handle CC mapping to parameters.
   */
  private handleCCMapping(event: MidiCCEvent): void {
    this.mappings.forEach((mapping) => {
      // Check device match
      if (mapping.deviceId && mapping.deviceId !== event.deviceId) return;
      // Check channel match
      if (mapping.channel !== null && mapping.channel !== event.channel) return;
      // Check controller match
      if (mapping.controller !== event.controller) return;

      // Calculate normalized value
      let normalizedValue: number;
      if (mapping.mode === 'relative') {
        // Relative mode: 64 = no change, <64 = decrease, >64 = increase
        const delta = event.value < 64 ? event.value - 128 : event.value;
        normalizedValue = delta / 127;
      } else {
        // Absolute mode
        normalizedValue = event.value / 127;
      }

      // Scale to min/max range
      const scaledValue = mapping.minValue + normalizedValue * (mapping.maxValue - mapping.minValue);

      // Call parameter callback
      const callback = this.parameterCallbacks.get(mapping.parameterId);
      if (callback) {
        callback(scaledValue);
      }
    });
  }

  // ============ MIDI Learn ============

  /**
   * Start MIDI learn mode for a parameter.
   */
  startLearning(parameterId: string): void {
    this.state.isLearning = true;
    this.state.learningParameterId = parameterId;
    this.notifyStateChange();
  }

  /**
   * Cancel MIDI learn.
   */
  cancelLearning(): void {
    this.state.isLearning = false;
    this.state.learningParameterId = null;
    this.notifyStateChange();
  }

  /**
   * Complete MIDI learn with received CC.
   */
  private completeLearning(event: MidiCCEvent): void {
    if (!this.state.learningParameterId) return;

    const mapping: MidiMapping = {
      id: `mapping_${Date.now()}`,
      parameterId: this.state.learningParameterId,
      deviceId: event.deviceId,
      channel: event.channel,
      controller: event.controller,
      minValue: 0,
      maxValue: 1,
      mode: 'absolute',
    };

    this.mappings.set(mapping.id, mapping);

    this.state.isLearning = false;
    this.state.learningParameterId = null;
    this.notifyStateChange();
  }

  // ============ Mapping Management ============

  /**
   * Add a MIDI mapping manually.
   */
  addMapping(mapping: MidiMapping): void {
    this.mappings.set(mapping.id, mapping);
  }

  /**
   * Remove a mapping.
   */
  removeMapping(mappingId: string): void {
    this.mappings.delete(mappingId);
  }

  /**
   * Get all mappings.
   */
  getMappings(): MidiMapping[] {
    return Array.from(this.mappings.values());
  }

  /**
   * Register parameter callback.
   */
  registerParameter(parameterId: string, callback: (value: number) => void): () => void {
    this.parameterCallbacks.set(parameterId, callback);
    return () => this.parameterCallbacks.delete(parameterId);
  }

  // ============ MIDI Output ============

  /**
   * Send note on.
   */
  sendNoteOn(deviceId: string, channel: number, note: number, velocity: number): void {
    this.sendMessage(deviceId, [0x90 | channel, note, velocity]);
  }

  /**
   * Send note off.
   */
  sendNoteOff(deviceId: string, channel: number, note: number, velocity = 0): void {
    this.sendMessage(deviceId, [0x80 | channel, note, velocity]);
  }

  /**
   * Send CC.
   */
  sendCC(deviceId: string, channel: number, controller: number, value: number): void {
    this.sendMessage(deviceId, [0xB0 | channel, controller, value]);
  }

  /**
   * Send raw MIDI message.
   */
  sendMessage(deviceId: string, data: number[]): void {
    if (!this.midiAccess) return;

    const output = this.midiAccess.outputs.get(deviceId);
    if (output) {
      output.send(data);
    }
  }

  // ============ State & Listeners ============

  /**
   * Get current state.
   */
  getState(): Readonly<MidiManagerState> {
    return {
      ...this.state,
      activeInputs: new Set(this.state.activeInputs),
    };
  }

  /**
   * Get calculated BPM from MIDI clock.
   */
  getClockBPM(): number {
    return this.calculatedBPM;
  }

  /**
   * Subscribe to all MIDI events.
   */
  onMidiEvent(listener: MidiEventListener): () => void {
    this.eventListeners.add(listener);
    return () => this.eventListeners.delete(listener);
  }

  /**
   * Subscribe to note events only.
   */
  onNoteEvent(listener: NoteListener): () => void {
    this.noteListeners.add(listener);
    return () => this.noteListeners.delete(listener);
  }

  /**
   * Subscribe to CC events only.
   */
  onCCEvent(listener: CCListener): () => void {
    this.ccListeners.add(listener);
    return () => this.ccListeners.delete(listener);
  }

  /**
   * Subscribe to state changes.
   */
  onStateChange(listener: StateListener): () => void {
    this.stateListeners.add(listener);
    return () => this.stateListeners.delete(listener);
  }

  /**
   * Notify state listeners.
   */
  private notifyStateChange(): void {
    this.stateListeners.forEach(fn => fn(this.getState()));
  }

  /**
   * Dispose and cleanup.
   */
  dispose(): void {
    // Disable all inputs
    this.state.activeInputs.forEach(id => this.disableInput(id));

    this.eventListeners.clear();
    this.noteListeners.clear();
    this.ccListeners.clear();
    this.stateListeners.clear();
    this.parameterCallbacks.clear();
    this.mappings.clear();

    this.midiAccess = null;
    this.state.hasAccess = false;
    this.state.inputs = [];
    this.state.outputs = [];
  }
}

// Singleton instance
export const MidiManager = new MidiManagerClass();

// ============ Utility Functions ============

/**
 * Convert MIDI note number to name.
 */
export function midiNoteToName(note: number): string {
  const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
  const octave = Math.floor(note / 12) - 1;
  const noteName = names[note % 12];
  return `${noteName}${octave}`;
}

/**
 * Convert note name to MIDI number.
 */
export function noteNameToMidi(name: string): number {
  const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
  const match = name.match(/^([A-G]#?)(-?\d+)$/);
  if (!match) return -1;

  const noteName = match[1];
  const octave = parseInt(match[2], 10);
  const noteIndex = names.indexOf(noteName);

  if (noteIndex === -1) return -1;
  return (octave + 1) * 12 + noteIndex;
}

/**
 * Convert MIDI velocity to dB.
 */
export function velocityToDb(velocity: number): number {
  if (velocity === 0) return -Infinity;
  return 20 * Math.log10(velocity / 127);
}

/**
 * Convert dB to MIDI velocity.
 */
export function dbToVelocity(db: number): number {
  if (db <= -60) return 0;
  return Math.round(127 * Math.pow(10, db / 20));
}
