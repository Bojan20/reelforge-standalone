export type BusId = 'master' | 'music' | 'sfx' | 'ambience' | 'voice';

export interface BusConfig {
  id: BusId;
  name: string;
  volume: number;
  muted?: boolean;
  solo?: boolean;
}

export interface AudioSpriteFile {
  id: string;
  fileName: string;
  filePath: string;
  format: string;
  duration?: number;
  waveformData?: number[];
  dateAdded: string;
}

export interface AudioSpriteItem {
  id: string;
  soundId: string;
  spriteId: string;
  startTime: number;
  duration: number;
  tags: string[];
  name?: string;
  color?: string;
  bus?: BusId;
  bpm?: number;
  beatsPerBar?: number;
  loopBars?: number;
  bpmConfidence?: number;
}

export interface SpriteList {
  id: string;
  name: string;
  spriteIds: string[];
  description?: string;
}

export type CommandType = "Play" | "Stop" | "Fade" | "Pause" | "Execute";

export interface BaseCommand {
  type: CommandType;
  /** Unique command ID for React keys and drag/drop tracking */
  id?: string;
}

export interface PlayCommand extends BaseCommand {
  type: "Play";
  soundId: string;
  volume?: number;
  loop?: boolean;
  loopCount?: number;
  fadeIn?: number;
  delay?: number;
  pan?: number;
  overlap?: boolean;
}

export interface StopCommand extends BaseCommand {
  type: "Stop";
  soundId: string;
  volume?: number;
  pan?: number;
  fadeOut?: number;
  delay?: number;
  overlap?: boolean;
}

export interface FadeCommand extends BaseCommand {
  type: "Fade";
  soundId: string;
  targetVolume: number;
  pan?: number;
  duration?: number;
  durationUp?: number;
  durationDown?: number;
  delay?: number;
  overlap?: boolean;
}

export interface PauseCommand extends BaseCommand {
  type: "Pause";
  soundId: string;
  volume?: number;
  fadeOut?: number;
  pan?: number;
  delay?: number;
  overall?: boolean;
}

export interface ExecuteCommand extends BaseCommand {
  type: "Execute";
  eventId: string; // ID of the event to execute
  delay?: number;
  fadeDuration?: number;
  volume?: number;
}

export type Command = PlayCommand | StopCommand | FadeCommand | PauseCommand | ExecuteCommand;

export interface GameEvent {
  id: string;
  eventName: string;
  commands: Command[];
  description?: string;
  tags?: string[];
}

export interface ReelForgeProject {
  id: string;
  name: string;
  createdAt: string;
  updatedAt: string;
  spriteFiles: AudioSpriteFile[];
  spriteItems: AudioSpriteItem[];
  spriteLists: SpriteList[];
  events: GameEvent[];
  buses: BusConfig[];
  settings?: {
    defaultVolume?: number;
    sampleRate?: number;
    exportFormat?: "json" | "xml" | "csv";
  };
}

export interface TemplateSoundManifest {
  id: string;
  src: string[];
}

export interface TemplateSoundSprite {
  soundId: string;
  spriteId: string;
  startTime: number;
  duration: number;
  tags: string[];
}

export interface TemplateCommand {
  command: "Play" | "Stop" | "Fade" | "Pause" | "Execute" | "Set";
  spriteId?: string;
  commandId?: string;
  volume?: number;
  loop?: number;
  loopCount?: number;
  delay?: number;
  durationUp?: number;
  durationDown?: number;
  duration?: number;
  fadeDuration?: number;
  pan?: number;
  overall?: boolean;
}

export interface TemplateJSON {
  soundManifest: TemplateSoundManifest[];
  soundDefinitions: {
    soundSprites: {
      [key: string]: TemplateSoundSprite;
    };
  };
  commands: {
    [eventId: string]: TemplateCommand[];
  };
}

export interface AudioFileObject {
  id: number;
  name: string;
  file: File;
  url: string;
  duration: number;
  size: string;
}

export interface SoundUsage {
  soundId: string;
  spriteIds: string[];
  eventNames: string[];
  hasFile: boolean;
}

// ============ MIX SNAPSHOTS ============
// Instant preset states for the entire mix (Unity-inspired)

export interface MixSnapshotBusState {
  volume: number;
  muted?: boolean;
  pan?: number;
}

export interface MixSnapshot {
  id: string;
  name: string;
  description?: string;
  /** Bus states keyed by BusId */
  buses: Partial<Record<BusId, MixSnapshotBusState>>;
  /** Master volume */
  master?: MixSnapshotBusState;
  /** Optional: music layer to activate */
  musicLayer?: string;
  /** Default transition duration in ms */
  transitionMs?: number;
}

// ============ CONTROL BUS (RTPC) ============
// One input controls multiple parameters (Unreal-inspired)

export type ControlBusCurve = 'linear' | 'exponential' | 'logarithmic' | 'scurve';

export interface ControlBusTarget {
  /** Target path: "bus.music.volume", "bus.sfx.pan", "master.volume" */
  path: string;
  /** Scale factor applied to normalized input (0-1) */
  scale?: number;
  /** Offset added after scaling */
  offset?: number;
  /** Curve type for non-linear mapping */
  curve?: ControlBusCurve;
  /** Invert the input (1 becomes 0, 0 becomes 1) */
  invert?: boolean;
}

export interface ControlBus {
  id: string;
  name: string;
  description?: string;
  /** Range of input values [min, max], default [0, 1] */
  range?: [number, number];
  /** Default value */
  defaultValue?: number;
  /** Current value (runtime) */
  value?: number;
  /** Target parameters this control bus affects */
  targets: ControlBusTarget[];
  /** Smoothing time in ms for value changes */
  smoothingMs?: number;
}
