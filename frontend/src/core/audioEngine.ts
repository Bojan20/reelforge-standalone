import type { AudioFileObject, PlayCommand, FadeCommand, StopCommand, ExecuteCommand, GameEvent, BusId, MixSnapshot, ControlBus } from './types';
import { layeredMusicSystem } from './layeredMusicSystem';
import { AudioBufferCache } from './audioBufferCache';
import { MASTER_INSERT_FALLBACK_MS, FADE_RETRY_DELAY_MS } from './audioConstants';
import { wireVoiceWithInserts, disposeVoiceInserts, disposeAllVoiceInserts } from './voiceInsertDSP';
import { AudioContextManager } from './AudioContextManager';
import { SnapshotManager, type SnapshotTransitionOptions } from './mixSnapshots';
import { ControlBusManager, parseControlPath } from './controlBus';
import { IntensityLayerSystem, type IntensityLayerConfig } from './intensityLayers';
import { DuckingManager, type DuckingRule } from './duckingManager';
import { SoundVariationManager, type VariationContainer, type VariationPlayResult } from './soundVariations';
import { VoiceConcurrencyManager, type VoiceConcurrencyRule, type ActiveVoice } from './voiceConcurrency';
import { SequenceContainerManager, type SequenceContainer, type SequencePlayOptions } from './sequenceContainer';
import { StingerManager, type Stinger, type StingerPlayOptions, type MusicBeatInfo } from './stingerManager';
import { ParameterModifierManager, type LFOConfig, type EnvelopeConfig, type CurveConfig, type ModifierTarget } from './parameterModifiers';
import { BlendContainerManager, type BlendContainer, type BlendPlayOptions } from './blendContainer';
import { PriorityManager, type PriorityConfig, type BusPriorityLimit } from './prioritySystem';
import { EventGroupManager, type EventGroup, type EventGroupMember } from './eventGroups';
import { RTPCManager, type RTPCDefinition, type RTPCBinding } from './rtpc';
import { GameSyncManager, type StateGroup, type SwitchGroup, type Trigger } from './gameSync';
import { MarkerManager, type AssetMarkers, type Marker, type MarkerRegion } from './markers';
import { PlaylistManager, type Playlist, type PlaylistTrack, type PlaylistMode, type PlaylistLoopMode } from './playlist';
import { MusicTransitionManager, type TransitionRule, type MusicTrackInfo } from './musicTransition';
import { InteractiveMusicController, type InteractiveMusicConfig, type MusicState } from './interactiveMusic';
import { AudioDiagnosticsManager, audioLogger, type DiagnosticsSnapshot, type DiagnosticEvent, type DiagnosticEventType } from './audioDiagnostics';
import { AudioProfiler, FrameTimeMonitor, audioProfiler, frameMonitor, type ProfileReport, type ProfileSample, type ProfileCategory } from './audioProfiler';
import { PluginChain, createPlugin, type DSPPlugin, type PluginConfig } from './dspPlugins';
import { SpatialAudioManager, SpatialVoiceManager, type SpatialSourceConfig, type Vector3, type Orientation3D, type AudioZone, type ActiveSpatialSource, SPATIAL_PRESETS } from './spatialAudio';

// Audio debug flag - controlled via VITE_AUDIO_DEBUG env var or window.AUDIO_DEBUG
const AUDIO_DEBUG = (() => {
  if (typeof import.meta !== 'undefined' && (import.meta as any).env?.VITE_AUDIO_DEBUG === 'true') {
    return true;
  }
  if (typeof window !== 'undefined' && (window as any).AUDIO_DEBUG === true) {
    return true;
  }
  return false;
})();

// Conditional logger - only logs when AUDIO_DEBUG is true
const debugLog = AUDIO_DEBUG
  ? (...args: unknown[]) => console.log('[AudioEngine]', ...args)
  : () => {};

// Expose debug toggle to console
if (typeof window !== 'undefined') {
  (window as any).AUDIO_DEBUG_ENABLE = () => {
    (window as any).AUDIO_DEBUG = true;
    console.log('[AudioEngine] Debug logging enabled. Create new AudioEngine instance to see logs.');
  };
}

export interface AudioEngineState {
  audioContextRef: React.MutableRefObject<AudioContext | null>;
  audioSourceRef: React.MutableRefObject<AudioBufferSourceNode | null>;
  gainNodeRef: React.MutableRefObject<GainNode | null>;
  panNodeRef: React.MutableRefObject<StereoPannerNode | null>;
  audioRef: React.MutableRefObject<HTMLAudioElement | null>;
  eventAudioRefsMap: React.MutableRefObject<Map<string, HTMLAudioElement[]>>;
  soundAudioMap: React.MutableRefObject<Map<string, { audio: HTMLAudioElement; gainNode?: GainNode; source?: AudioBufferSourceNode; panNode?: StereoPannerNode; eventId?: string; instanceKey?: string; voiceKey?: string }[]>>;
  busGainsRef: React.MutableRefObject<Record<BusId, GainNode> | null>;
  masterGainRef: React.MutableRefObject<GainNode | null>;
  masterInsertConnected?: boolean; // Set to true when MasterInsertDSP wires the master output
}

export class AudioEngine {
  private audioFiles: AudioFileObject[];
  /** O(1) lookup index for audio files by name */
  private audioFileIndex: Map<string, AudioFileObject> = new Map();
  private state: AudioEngineState;
  private setIsPlaying: (playing: boolean) => void;
  private setCurrentPlayingSound: (sound: string) => void;
  private setPlayingEvents: React.Dispatch<React.SetStateAction<Set<string>>>;
  private bufferCache: AudioBufferCache | null = null;

  // Track active timeouts for cleanup on dispose
  private activeTimeouts: Set<ReturnType<typeof setTimeout>> = new Set();

  /**
   * Create a tracked timeout that will be cleaned up on dispose
   */
  private safeTimeout(callback: () => void, delay: number): ReturnType<typeof setTimeout> {
    const id = setTimeout(() => {
      this.activeTimeouts.delete(id);
      callback();
    }, delay);
    this.activeTimeouts.add(id);
    return id;
  }

  /**
   * Clear all active timeouts
   */
  private clearAllTimeouts(): void {
    this.activeTimeouts.forEach(id => clearTimeout(id));
    this.activeTimeouts.clear();
  }

  constructor(
    audioFiles: AudioFileObject[],
    state: AudioEngineState,
    setIsPlaying: (playing: boolean) => void,
    setCurrentPlayingSound: (sound: string) => void,
    setPlayingEvents: React.Dispatch<React.SetStateAction<Set<string>>>
  ) {
    this.audioFiles = audioFiles;
    this.rebuildAudioFileIndex();
    this.state = state;
    this.setIsPlaying = setIsPlaying;
    this.setCurrentPlayingSound = setCurrentPlayingSound;
    this.setPlayingEvents = setPlayingEvents;
    this.initializeBuses();
  }

  /**
   * Rebuild the O(1) lookup index for audio files
   * Call this when audioFiles array changes
   */
  private rebuildAudioFileIndex(): void {
    this.audioFileIndex.clear();
    for (const file of this.audioFiles) {
      this.audioFileIndex.set(file.name, file);
    }
    debugLog(`📁 Audio file index built: ${this.audioFileIndex.size} files`);
  }

  /**
   * Get audio file by name - O(1) lookup
   */
  getAudioFile(name: string): AudioFileObject | undefined {
    return this.audioFileIndex.get(name);
  }

  /**
   * Update audio files and rebuild index
   */
  updateAudioFiles(audioFiles: AudioFileObject[]): void {
    this.audioFiles = audioFiles;
    this.rebuildAudioFileIndex();
  }

  private initializeBuses() {
    if (!this.state.audioContextRef.current) {
      this.state.audioContextRef.current = AudioContextManager.getContext();
      debugLog('🎵 AudioContext obtained from singleton');
    }

    const ctx = this.state.audioContextRef.current;

    // Initialize buffer cache
    if (!this.bufferCache) {
      this.bufferCache = new AudioBufferCache(ctx, 100, 30 * 60 * 1000);
      debugLog('💾 AudioBuffer cache initialized');
    }

    if (!this.state.masterGainRef.current) {
      this.state.masterGainRef.current = ctx.createGain();
      this.state.masterGainRef.current.gain.value = 1;
      // NOTE: Do NOT connect to destination here!
      // MasterInsertDSP will wire: masterGain → [insert chain] → destination
      // This allows insert plugins (EQ, Compressor, VanEQ, etc.) to process the signal
      debugLog('🎚️ Master gain created (waiting for MasterInsertDSP to wire)');

      // FALLBACK: If MasterInsertDSP doesn't wire within 2 seconds, connect directly
      // This ensures audio works even if insert system fails to initialize
      const masterGain = this.state.masterGainRef.current;
      const destination = ctx.destination;
      const stateRef = this.state;
      this.safeTimeout(() => {
        try {
          // Check if MasterInsertDSP has marked itself as connected
          if (masterGain && !stateRef.masterInsertConnected) {
            masterGain.connect(destination);
            stateRef.masterInsertConnected = true; // Prevent double connection
            debugLog('⚠️ FALLBACK: Master gain connected directly to destination (MasterInsertDSP did not wire)');
          }
        } catch (e) {
          // Already connected or context closed - ignore
        }
      }, MASTER_INSERT_FALLBACK_MS);
    }

    if (!this.state.busGainsRef.current) {
      this.state.busGainsRef.current = {
        master: ctx.createGain(),
        music: ctx.createGain(),
        sfx: ctx.createGain(),
        ambience: ctx.createGain(),
        voice: ctx.createGain()
      };

      Object.entries(this.state.busGainsRef.current).forEach(([busId, busGain]) => {
        busGain.gain.value = 1;
        busGain.connect(this.state.masterGainRef.current!);
        debugLog(`🎚️ Bus ${busId} created and connected to master`);
      });
    }
  }

  getBusVolume(bus: BusId): number {
    if (!this.state.busGainsRef.current || !this.state.audioContextRef.current) {
      return 1;
    }

    if (bus === 'master') {
      return this.state.masterGainRef.current?.gain.value ?? 1;
    }

    const busGain = this.state.busGainsRef.current[bus];
    return busGain?.gain.value ?? 1;
  }

  setBusVolume(bus: BusId, value: number) {
    if (!this.state.busGainsRef.current || !this.state.audioContextRef.current) {
      console.warn(`⚠️ setBusVolume called but buses not initialized yet`);
      this.initializeBuses();
    }

    // Master bus controls the master gain directly
    if (bus === 'master') {
      if (this.state.masterGainRef.current) {
        debugLog(`🎚️ Setting MASTER volume to ${value}, current: ${this.state.masterGainRef.current.gain.value}`);
        this.state.masterGainRef.current.gain.value = value;
      }
      return;
    }

    const busGain = this.state.busGainsRef.current![bus];
    if (!busGain) {
      console.warn(`⚠️ Bus gain not found for: ${bus}`);
      return;
    }
    debugLog(`🎚️ Setting ${bus} volume to ${value}, current: ${busGain.gain.value}`);
    busGain.gain.value = value;
  }

  private getBusInput(bus: BusId = 'sfx'): GainNode {
    if (!this.state.busGainsRef.current) {
      this.initializeBuses();
    }
    return this.state.busGainsRef.current![bus] ?? this.state.busGainsRef.current!.sfx;
  }

  async playSound(soundId: string, volume: number = 1, loop: boolean = false, currentPlayingSound: string, isPlaying: boolean, bus: BusId = 'sfx', pan: number = 0): Promise<void> {
    const audioFile = this.audioFileIndex.get(soundId);

    if (!audioFile) {
      alert("❌ Audio file not found: " + soundId);
      return;
    }

    if (currentPlayingSound === soundId && isPlaying) {
      return;
    }

    if (this.state.audioSourceRef.current) {
      try {
        this.state.audioSourceRef.current.stop();
      } catch (e) {
      }
      this.state.audioSourceRef.current = null;
    }

    if (this.state.audioRef.current) {
      this.state.audioRef.current.pause();
      this.state.audioRef.current = null;
    }

    if (this.state.soundAudioMap.current.has(soundId)) {
      const existingObjects = this.state.soundAudioMap.current.get(soundId) || [];
      existingObjects.forEach(obj => {
        if (obj.source && !obj.eventId) {
          try {
            obj.source.stop();
          } catch (e) {}
        }
      });
      this.state.soundAudioMap.current.set(
        soundId,
        existingObjects.filter(obj => obj.eventId)
      );
    }

    if (loop) {
      try {
        if (!this.state.audioContextRef.current) {
          this.state.audioContextRef.current = AudioContextManager.getContext();
        }

        const audioContext = this.state.audioContextRef.current;
        await AudioContextManager.resume();

        // Use cache instead of direct fetch+decode
        const audioBuffer = await this.bufferCache!.getBuffer(soundId, audioFile.url);

        const source = audioContext.createBufferSource();
        source.buffer = audioBuffer;
        source.loop = true;
        source.loopStart = 0;
        source.loopEnd = audioBuffer.duration;

        const localGain = audioContext.createGain();
        localGain.gain.value = volume;

        const panNode = audioContext.createStereoPanner();
        panNode.pan.value = pan;

        // Generate voice key for asset insert tracking
        const voiceKey = `${soundId}:${Date.now()}:${Math.random().toString(36).substr(2, 9)}`;

        source.connect(panNode);
        panNode.connect(localGain);

        // Wire through asset inserts if defined, otherwise connect directly to bus
        const outputNode = wireVoiceWithInserts(voiceKey, soundId, localGain);
        outputNode.connect(this.getBusInput(bus));
        source.start(0);

        this.state.audioSourceRef.current = source;
        this.state.gainNodeRef.current = localGain;
        this.state.panNodeRef.current = panNode;

        if (!this.state.soundAudioMap.current.has(soundId)) {
          this.state.soundAudioMap.current.set(soundId, []);
        }
        this.state.soundAudioMap.current.get(soundId)!.push({
          audio: new Audio(),
          gainNode: localGain,
          source: source,
          panNode: panNode,
          voiceKey: voiceKey,
        });

        this.setIsPlaying(true);
        this.setCurrentPlayingSound(soundId);
        debugLog(`▶ Playing (Web Audio API): ${soundId} (volume: ${volume}, loop: ${loop}, pan: ${pan}, bus: ${bus})`);

        source.onended = () => {
          // Dispose voice insert chain when voice ends
          disposeVoiceInserts(voiceKey);

          if (!loop) {
            this.setIsPlaying(false);
            this.setCurrentPlayingSound("");
          }
          const audioObjects = this.state.soundAudioMap.current.get(soundId) || [];
          const index = audioObjects.findIndex(obj => obj.source === source && !obj.eventId);
          if (index > -1) {
            audioObjects.splice(index, 1);
            if (audioObjects.length === 0) {
              this.state.soundAudioMap.current.delete(soundId);
            }
          }
        };
      } catch (err) {
        console.error("❌ Web Audio API error:", err);
        alert("❌ Failed to play audio: " + (err as Error).message);
        this.setIsPlaying(false);
        this.setCurrentPlayingSound("");
      }
    } else {
      try {
        if (!this.state.audioContextRef.current) {
          this.state.audioContextRef.current = AudioContextManager.getContext();
        }

        const audioContext = this.state.audioContextRef.current;
        await AudioContextManager.resume();

        // Use cache instead of direct fetch+decode
        const audioBuffer = await this.bufferCache!.getBuffer(soundId, audioFile.url);

        const source = audioContext.createBufferSource();
        source.buffer = audioBuffer;
        source.loop = false;

        const localGain = audioContext.createGain();
        localGain.gain.value = volume;

        const panNode = audioContext.createStereoPanner();
        panNode.pan.value = pan;

        // Generate voice key for asset insert tracking
        const voiceKey = `${soundId}:${Date.now()}:${Math.random().toString(36).substr(2, 9)}`;

        source.connect(panNode);
        panNode.connect(localGain);

        // Wire through asset inserts if defined, otherwise connect directly to bus
        const outputNode = wireVoiceWithInserts(voiceKey, soundId, localGain);
        outputNode.connect(this.getBusInput(bus));
        source.start(0);

        this.state.audioSourceRef.current = source;
        this.state.gainNodeRef.current = localGain;
        this.state.panNodeRef.current = panNode;

        if (!this.state.soundAudioMap.current.has(soundId)) {
          this.state.soundAudioMap.current.set(soundId, []);
        }
        this.state.soundAudioMap.current.get(soundId)!.push({
          audio: new Audio(),
          gainNode: localGain,
          source: source,
          panNode: panNode,
          voiceKey: voiceKey,
        });

        this.setIsPlaying(true);
        this.setCurrentPlayingSound(soundId);
        debugLog(`▶ Playing (Web Audio API): ${soundId} (volume: ${volume}, loop: ${loop}, pan: ${pan}, bus: ${bus})`);

        source.onended = () => {
          // Dispose voice insert chain when voice ends
          disposeVoiceInserts(voiceKey);

          this.setIsPlaying(false);
          this.setCurrentPlayingSound("");

          const audioObjects = this.state.soundAudioMap.current.get(soundId) || [];
          const index = audioObjects.findIndex(obj => obj.source === source && !obj.eventId);
          if (index > -1) {
            audioObjects.splice(index, 1);
            if (audioObjects.length === 0) {
              this.state.soundAudioMap.current.delete(soundId);
            }
          }
        };
      } catch (err) {
        console.error("❌ Web Audio API error:", err);
        alert("❌ Failed to play audio: " + (err as Error).message);
        this.setIsPlaying(false);
        this.setCurrentPlayingSound("");
      }
    }
  }

  playEvent(selectedEvent: GameEvent, project?: { spriteItems: Array<{ soundId: string; bus?: string }> }, fadeInDuration?: number, volumeMultiplier?: number): void {
    if (!selectedEvent || selectedEvent.commands.length === 0) {
      alert("No commands to play in this event");
      return;
    }

    const eventId = selectedEvent.id;

    debugLog(`🎮 [${eventId}] playEvent called: fadeInDuration=${fadeInDuration}, volumeMultiplier=${volumeMultiplier}, commands=${selectedEvent.commands.length}`);

    // If event is already playing, stop it first (restart)
    if (this.state.eventAudioRefsMap.current.has(eventId)) {
      const existingAudios = this.state.eventAudioRefsMap.current.get(eventId) || [];
      existingAudios.forEach(audio => {
        audio.pause();
        audio.currentTime = 0;
      });
      this.state.eventAudioRefsMap.current.delete(eventId);

      // Stop only Web Audio API sounds for this event
      this.state.soundAudioMap.current.forEach((audioObjects, soundId) => {
        const remainingObjects = audioObjects.filter(obj => {
          if (obj.eventId === eventId) {
            if (obj.source) {
              try {
                obj.source.stop();
              } catch (e) {}
            }
            return false;
          }
          return true;
        });

        if (remainingObjects.length === 0) {
          this.state.soundAudioMap.current.delete(soundId);
        } else {
          this.state.soundAudioMap.current.set(soundId, remainingObjects);
        }
      });
    }

    const eventAudios: HTMLAudioElement[] = [];
    this.state.eventAudioRefsMap.current.set(eventId, eventAudios);

    // Don't add to playingEvents yet - wait until we actually play something
    this.setCurrentPlayingSound(`Playing: ${eventId}`);

    const playCommands = selectedEvent.commands.filter(cmd => cmd.type === "Play") as PlayCommand[];
    const fadeCommands = selectedEvent.commands.filter(cmd => cmd.type === "Fade") as FadeCommand[];
    const stopCommands = selectedEvent.commands.filter(cmd => cmd.type === "Stop") as StopCommand[];
    const executeCommands = selectedEvent.commands.filter(cmd => cmd.type === "Execute") as ExecuteCommand[];

    // Use object to share count between callbacks
    const audioCount = {
      active: playCommands.filter(cmd => !cmd.loop).length,  // Only non-looping sounds
      looping: 0,  // Will be incremented when looping sounds are successfully created
      fadeCommands: fadeCommands.length,  // Track fade commands
      executeCommands: executeCommands.length  // Track execute commands
    };

    // Track if any sound was actually played
    let anySoundPlayed = false;

    debugLog(`🎬 [${eventId}] Event started with ${audioCount.active} sounds (${audioCount.looping} looping, ${audioCount.fadeCommands} fades, ${audioCount.executeCommands} executes)`);

    const checkAndCleanup = () => {
      debugLog(`🔍 [${eventId}] Checking cleanup: active=${audioCount.active}, looping=${audioCount.looping}, fades=${audioCount.fadeCommands}, executes=${audioCount.executeCommands}`);
      if (audioCount.active === 0 && audioCount.looping === 0 && audioCount.fadeCommands === 0 && audioCount.executeCommands === 0) {
        this.setPlayingEvents(prev => {
          const newSet = new Set(prev);
          newSet.delete(eventId);
          debugLog(`✅ [${eventId}] Removed from playingEvents. Remaining events:`, Array.from(newSet));
          return newSet;
        });
        this.state.eventAudioRefsMap.current.delete(eventId);
      }
    };

    // If no commands at all, cleanup immediately
    if (playCommands.length === 0 && fadeCommands.length === 0 && stopCommands.length === 0 && executeCommands.length === 0) {
      debugLog(`⚠️ [${eventId}] No commands to execute, cleaning up immediately`);
      checkAndCleanup();
      return;
    }

    if (playCommands.length === 0) {
      debugLog(`ℹ️ [${eventId}] No play commands, but has ${fadeCommands.length} fade, ${stopCommands.length} stop, and ${executeCommands.length} execute commands`);
    }

    playCommands.forEach((playCmd) => {
      const audioFile = this.audioFileIndex.get(playCmd.soundId);

      if (!audioFile) {
        console.warn(`Audio file not found: ${playCmd.soundId}, skipping...`);
        if (!playCmd.loop) {
          audioCount.active--;
        }
        checkAndCleanup();
        return;
      }

      const delay = playCmd.delay ?? 0;
      const isLooping = playCmd.loop ?? false;

      this.safeTimeout(async () => {
        try {
          // Generate stable instance key for this sound
          const sprite = project?.spriteItems.find(s => s.soundId === playCmd.soundId);
          const bus = (sprite?.bus ?? 'sfx') as BusId;
          const instanceKey = `${playCmd.soundId}:${bus}:${eventId}`;

          // Handle overlap logic - if overlap is false, stop existing instances of this sound
          if (!playCmd.overlap) {
            const existingSounds = this.state.soundAudioMap.current.get(playCmd.soundId);
            if (existingSounds && existingSounds.length > 0) {
              debugLog(`🚫 [${eventId}] Overlap disabled - stopping ${existingSounds.length} existing instance(s) of ${playCmd.soundId}`);
              existingSounds.forEach(obj => {
                if (obj.source) {
                  try {
                    obj.source.stop();
                  } catch (e) {
                    // Ignore if already stopped
                  }
                }
              });
              // Clear the array after stopping
              this.state.soundAudioMap.current.delete(playCmd.soundId);
            }
          }

          if (isLooping) {
            // Check if this looping sound is already playing with overlap=false
            if (!playCmd.overlap) {
              const existingSounds = this.state.soundAudioMap.current.get(playCmd.soundId);
              if (existingSounds && existingSounds.length > 0) {
                const existingInstance = existingSounds.find(obj => obj.instanceKey === instanceKey);
                if (existingInstance && existingInstance.source && existingInstance.source.loop) {
                  debugLog(`⏭️ [${eventId}] Reusing existing looping instance: ${playCmd.soundId} (instanceKey: ${instanceKey})`);

                  // Update volume if needed
                  // If volumeMultiplier is provided (from Execute command), use it as target volume
                  // Otherwise, use the Play command's volume
                  const targetVolume = volumeMultiplier !== undefined ? volumeMultiplier : (playCmd.volume ?? 1);
                  if (existingInstance.gainNode && existingInstance.gainNode.gain.value !== targetVolume) {
                    const fadeIn = playCmd.fadeIn ?? fadeInDuration ?? 0;
                    if (fadeIn > 0) {
                      layeredMusicSystem.setCurrentVolume(playCmd.soundId, existingInstance.gainNode.gain.value);
                      layeredMusicSystem.executeFade(
                        {
                          type: 'Fade',
                          soundId: playCmd.soundId,
                          targetVolume: targetVolume,
                          duration: fadeIn
                        },
                        existingInstance.gainNode,
                        null
                      );
                    } else {
                      existingInstance.gainNode.gain.value = targetVolume;
                      layeredMusicSystem.setCurrentVolume(playCmd.soundId, targetVolume);
                    }
                  }

                  // Update pan if needed
                  const targetPan = playCmd.pan ?? 0;
                  if (existingInstance.panNode && existingInstance.panNode.pan.value !== targetPan) {
                    existingInstance.panNode.pan.value = targetPan;
                  }

                  return;
                }
              }
            }

            // Check if this looping sound is already playing
            const existingSounds = this.state.soundAudioMap.current.get(playCmd.soundId);
            if (existingSounds && existingSounds.length > 0) {
              const isAlreadyLooping = existingSounds.some(obj => obj.source && obj.source.loop);
              if (isAlreadyLooping) {
                debugLog(`⏭️ [${eventId}] Skipping ${playCmd.soundId} - already looping`);
                // Don't add this event to playingEvents since we're not actually playing anything new
                return;
              }
            }

            // Mark that we're actually playing a sound
            if (!anySoundPlayed) {
              anySoundPlayed = true;
              this.setPlayingEvents(prev => new Set(prev).add(eventId));
            }

            if (!this.state.audioContextRef.current) {
              this.state.audioContextRef.current = AudioContextManager.getContext();
            }

            const audioContext = this.state.audioContextRef.current;
            await AudioContextManager.resume();

            const response = await fetch(audioFile.url);
            const arrayBuffer = await response.arrayBuffer();
            const audioBuffer = await audioContext.decodeAudioData(arrayBuffer);

            const source = audioContext.createBufferSource();
            source.buffer = audioBuffer;
            source.loop = true;
            source.loopStart = 0;
            source.loopEnd = audioBuffer.duration;

            const gainNode = audioContext.createGain();
            // Target volume: ALWAYS from Play command in called event
            const targetVolume = playCmd.volume ?? 1;

            // Fade-in: Execute fadeInDuration overrides Play fadeIn if Execute has fadeInDuration
            const fadeIn = fadeInDuration !== undefined && fadeInDuration > 0 ? fadeInDuration : (playCmd.fadeIn ?? 0);

            // Start volume logic:
            // - If Play.volume is 0, start at 0 (ignore Execute.volume)
            // - Otherwise, if Execute.volume is set, use it as start
            // - Otherwise, if fadeIn > 0, start at 0
            // - Otherwise, start at target
            let startVolume: number;
            if (targetVolume === 0) {
              startVolume = 0;
            } else if (volumeMultiplier !== undefined) {
              startVolume = volumeMultiplier;
            } else if (fadeIn > 0) {
              startVolume = 0;
            } else {
              startVolume = targetVolume;
            }

            debugLog(`🎵 [${eventId}] FadeIn setup for ${playCmd.soundId}: fadeIn=${fadeIn}ms, startVolume=${startVolume}, targetVolume=${targetVolume}, volumeMultiplier=${volumeMultiplier}, fadeInDuration=${fadeInDuration}, playCmd.fadeIn=${playCmd.fadeIn}, playCmd.volume=${playCmd.volume}`);

            // Start with the calculated start volume
            gainNode.gain.value = startVolume;

            const panNode = audioContext.createStereoPanner();
            panNode.pan.value = playCmd.pan ?? 0;

            const sprite = project?.spriteItems.find(s => s.soundId === playCmd.soundId);
            const bus = (sprite?.bus ?? 'sfx') as BusId;

            // Generate voice key for asset insert tracking
            const voiceKey = `${playCmd.soundId}:${eventId}:${Date.now()}:${Math.random().toString(36).substr(2, 9)}`;

            // Wire through asset inserts if defined, otherwise connect directly to bus
            const outputNode = wireVoiceWithInserts(voiceKey, playCmd.soundId, gainNode);
            outputNode.connect(this.getBusInput(bus));

            source.connect(panNode);
            panNode.connect(gainNode);
            source.start(0);

            // Increment looping count only after successful creation
            audioCount.looping++;

            // Apply fade in if specified
            if (fadeIn > 0) {
              layeredMusicSystem.setCurrentVolume(playCmd.soundId, startVolume);
              layeredMusicSystem.executeFade(
                {
                  type: 'Fade',
                  soundId: playCmd.soundId,
                  targetVolume: targetVolume,
                  duration: fadeIn
                },
                gainNode,
                null
              );
            } else {
              layeredMusicSystem.setCurrentVolume(playCmd.soundId, targetVolume);
            }

            const dummyAudio = new Audio();
            eventAudios.push(dummyAudio);

            if (!this.state.soundAudioMap.current.has(playCmd.soundId)) {
              this.state.soundAudioMap.current.set(playCmd.soundId, []);
            }
            this.state.soundAudioMap.current.get(playCmd.soundId)!.push({
              audio: dummyAudio,
              gainNode,
              source,
              panNode,
              eventId,
              instanceKey,
              voiceKey,
            });

            debugLog(`▶ [${eventId}] Playing (Web Audio API): ${playCmd.soundId} (delay: ${delay}ms, startVolume: ${startVolume}, targetVolume: ${targetVolume}, loop: true, fadeIn: ${fadeIn}ms, pan: ${playCmd.pan ?? 0}, instanceKey: ${instanceKey})`);

            source.onended = () => {
              // Dispose voice insert chain when voice ends
              disposeVoiceInserts(voiceKey);

              audioCount.looping--;
              const audioObjects = this.state.soundAudioMap.current.get(playCmd.soundId) || [];
              const index = audioObjects.findIndex(obj => obj.source === source);
              if (index > -1) {
                audioObjects.splice(index, 1);
                if (audioObjects.length === 0) {
                  this.state.soundAudioMap.current.delete(playCmd.soundId);
                }
              }
              debugLog(`🔚 [${eventId}] Looping sound ended: ${playCmd.soundId}, remaining: active=${audioCount.active}, looping=${audioCount.looping}`);
              checkAndCleanup();
            };
          } else {
            // Mark that we're actually playing a sound
            if (!anySoundPlayed) {
              anySoundPlayed = true;
              this.setPlayingEvents(prev => new Set(prev).add(eventId));
            }

            if (!this.state.audioContextRef.current) {
              this.state.audioContextRef.current = AudioContextManager.getContext();
            }

            const audioContext = this.state.audioContextRef.current;
            await AudioContextManager.resume();

            const response = await fetch(audioFile.url);
            const arrayBuffer = await response.arrayBuffer();
            const audioBuffer = await audioContext.decodeAudioData(arrayBuffer);

            const source = audioContext.createBufferSource();
            source.buffer = audioBuffer;
            source.loop = false;

            const gainNode = audioContext.createGain();
            // Target volume: ALWAYS from Play command in called event
            const targetVolume = playCmd.volume ?? 1;

            // Fade-in: Execute fadeInDuration overrides Play fadeIn if Execute has fadeInDuration
            const fadeIn = fadeInDuration !== undefined && fadeInDuration > 0 ? fadeInDuration : (playCmd.fadeIn ?? 0);

            // Start volume logic:
            // - If Play.volume is 0, start at 0 (ignore Execute.volume)
            // - Otherwise, if Execute.volume is set, use it as start
            // - Otherwise, if fadeIn > 0, start at 0
            // - Otherwise, start at target
            let startVolume: number;
            if (targetVolume === 0) {
              startVolume = 0;
            } else if (volumeMultiplier !== undefined) {
              startVolume = volumeMultiplier;
            } else if (fadeIn > 0) {
              startVolume = 0;
            } else {
              startVolume = targetVolume;
            }

            debugLog(`🎵 [${eventId}] FadeIn setup (non-loop) for ${playCmd.soundId}: fadeIn=${fadeIn}ms, startVolume=${startVolume}, targetVolume=${targetVolume}, volumeMultiplier=${volumeMultiplier}, fadeInDuration=${fadeInDuration}, playCmd.fadeIn=${playCmd.fadeIn}, playCmd.volume=${playCmd.volume}`);

            gainNode.gain.value = startVolume;
            layeredMusicSystem.setCurrentVolume(playCmd.soundId, startVolume);

            const panNode = audioContext.createStereoPanner();
            panNode.pan.value = playCmd.pan ?? 0;

            const sprite = project?.spriteItems.find(s => s.soundId === playCmd.soundId);
            const bus = (sprite?.bus ?? 'sfx') as BusId;

            // Generate voice key for asset insert tracking
            const voiceKey = `${playCmd.soundId}:${eventId}:${Date.now()}:${Math.random().toString(36).substr(2, 9)}`;

            // Wire through asset inserts if defined, otherwise connect directly to bus
            const outputNode = wireVoiceWithInserts(voiceKey, playCmd.soundId, gainNode);
            outputNode.connect(this.getBusInput(bus));

            source.connect(panNode);
            panNode.connect(gainNode);
            source.start(0);

            if (!this.state.soundAudioMap.current.has(playCmd.soundId)) {
              this.state.soundAudioMap.current.set(playCmd.soundId, []);
            }
            this.state.soundAudioMap.current.get(playCmd.soundId)!.push({
              audio: new Audio(),
              gainNode,
              source,
              panNode,
              eventId,
              instanceKey,
              voiceKey,
            });

            debugLog(`▶ [${eventId}] Playing: ${playCmd.soundId} (delay: ${delay}ms, startVolume: ${startVolume}, targetVolume: ${targetVolume}, loop: false, pan: ${playCmd.pan ?? 0}, bus: ${bus}, instanceKey: ${instanceKey})`);

            if (fadeIn > 0) {
              debugLog(`🎚️ [${eventId}] Applying linearRamp fade-in: ${playCmd.soundId} from ${startVolume} to ${targetVolume} over ${fadeIn}ms (endTime: ${audioContext.currentTime + fadeIn / 1000})`);
              gainNode.gain.linearRampToValueAtTime(targetVolume, audioContext.currentTime + fadeIn / 1000);
              layeredMusicSystem.setCurrentVolume(playCmd.soundId, targetVolume);
            }

            source.onended = () => {
              // Dispose voice insert chain when voice ends
              disposeVoiceInserts(voiceKey);

              audioCount.active--;
              const audioObjects = this.state.soundAudioMap.current.get(playCmd.soundId) || [];
              const index = audioObjects.findIndex(obj => obj.source === source);
              if (index > -1) {
                audioObjects.splice(index, 1);
                if (audioObjects.length === 0) {
                  this.state.soundAudioMap.current.delete(playCmd.soundId);
                }
              }
              debugLog(`🔚 [${eventId}] Non-looping sound ended: ${playCmd.soundId}, remaining: active=${audioCount.active}, looping=${audioCount.looping}`);
              checkAndCleanup();
            };
          }
        } catch (err) {
          console.error("Error creating audio:", err);
          if (!isLooping) {
            audioCount.active--;
          }
          checkAndCleanup();
        }
      }, delay);
    });

    fadeCommands.forEach((fadeCmd) => {
      const delay = fadeCmd.delay ?? 0;

      this.safeTimeout(() => {
        const attemptFade = (retryCount = 0) => {
          debugLog(`🎚️ [${eventId}] Fade command executing for: ${fadeCmd.soundId}, delay: ${delay}ms, retry: ${retryCount}, overlap: ${fadeCmd.overlap ?? true}`);
          debugLog(`🎚️ [${eventId}] soundAudioMap has ${fadeCmd.soundId}:`, this.state.soundAudioMap.current.has(fadeCmd.soundId));

          if (this.state.soundAudioMap.current.has(fadeCmd.soundId)) {
            const audioObjects = this.state.soundAudioMap.current.get(fadeCmd.soundId) || [];
            debugLog(`🎚️ [${eventId}] Found ${audioObjects.length} audio objects for ${fadeCmd.soundId}`);

            // CRITICAL FIX: Handle overlap=false for Fade commands
            let targetObjects = audioObjects;

            if (!fadeCmd.overlap) {
              // overlap=false: Only fade the instance that belongs to THIS event or the most recent one
              const sprite = project?.spriteItems.find(s => s.soundId === fadeCmd.soundId);
              const bus = (sprite?.bus ?? 'sfx') as BusId;
              const instanceKey = `${fadeCmd.soundId}:${bus}:${eventId}`;

              // First, try to find instance with matching instanceKey (same event)
              let targetInstance = audioObjects.find(obj => obj.instanceKey === instanceKey);

              // If not found, target the most recent instance (last in array)
              if (!targetInstance && audioObjects.length > 0) {
                targetInstance = audioObjects[audioObjects.length - 1];
                debugLog(`🎚️ [${eventId}] overlap=false: No matching instanceKey, targeting most recent instance`);
              }

              if (targetInstance) {
                targetObjects = [targetInstance];
                debugLog(`🎚️ [${eventId}] overlap=false: Targeting single instance (instanceKey: ${targetInstance.instanceKey})`);
              } else {
                console.warn(`⚠️ [${eventId}] overlap=false: No target instance found for ${fadeCmd.soundId}`);
                return;
              }
            }

            targetObjects.forEach(({ audio, gainNode, instanceKey: objInstanceKey }, index) => {
              const currentVolume = gainNode ? gainNode.gain.value : layeredMusicSystem.getCurrentVolume(fadeCmd.soundId);
              const targetVolume = fadeCmd.targetVolume;

              // Skip fade if volume is already at target
              if (Math.abs(currentVolume - targetVolume) < 0.001) {
                debugLog(`🎚️ [${eventId}] Skipping fade for ${fadeCmd.soundId} [${index}] - already at target volume ${targetVolume}`);
                return;
              }

              debugLog(`🎚️ [${eventId}] Starting fade for ${fadeCmd.soundId} [${index}] (instanceKey: ${objInstanceKey}): ${currentVolume.toFixed(3)} -> ${targetVolume} (durationUp: ${fadeCmd.durationUp ?? 'N/A'}ms, durationDown: ${fadeCmd.durationDown ?? 'N/A'}ms)`);

              // Set current volume in layeredMusicSystem to actual gainNode value
              if (gainNode) {
                layeredMusicSystem.setCurrentVolume(fadeCmd.soundId, gainNode.gain.value);
              }

              layeredMusicSystem.executeFade(
                fadeCmd,
                gainNode || null,
                gainNode ? null : audio,
                () => {
                  debugLog(`🎚️ [${eventId}] Faded: ${fadeCmd.soundId} [${index}] to ${targetVolume}`);
                }
              );
            });

            // Decrement fade counter after fade is executed
            audioCount.fadeCommands--;
            debugLog(`✅ [${eventId}] Fade command completed. Remaining fades: ${audioCount.fadeCommands}`);
            checkAndCleanup();
          } else {
            if (retryCount < 10) {
              debugLog(`⏳ [${eventId}] Fade command: Sound ${fadeCmd.soundId} not ready yet, retrying in 100ms...`);
              this.safeTimeout(() => attemptFade(retryCount + 1), FADE_RETRY_DELAY_MS);
            } else {
              console.warn(`⚠️ [${eventId}] Fade command: Sound ${fadeCmd.soundId} not found in soundAudioMap after ${retryCount} retries`);
              audioCount.fadeCommands--;
              checkAndCleanup();
            }
          }
        };

        attemptFade();
      }, delay);
    });

    stopCommands.forEach((stopCmd) => {
      const delay = stopCmd.delay ?? 0;

      this.safeTimeout(() => {
        // Stop HTMLAudioElement sounds from eventAudioRefsMap
        for (const [, audios] of this.state.eventAudioRefsMap.current.entries()) {
          const audiosToStop = audios.filter((audio) => {
            const audioFile = this.audioFiles.find((af) => af.url === audio.src);
            return audioFile && audioFile.name === stopCmd.soundId;
          });

          audiosToStop.forEach((audio) => {
            const fadeOut = stopCmd.fadeOut ?? 0;

            if (fadeOut > 0) {
              // Use RAF-based fade for smoother animation and better CPU efficiency
              const startVolume = audio.volume;
              const startTime = performance.now();
              const fadeDuration = fadeOut;

              const fadeWithRAF = () => {
                const elapsed = performance.now() - startTime;
                const progress = Math.min(1, elapsed / fadeDuration);

                audio.volume = Math.max(0, startVolume * (1 - progress));

                if (progress < 1) {
                  requestAnimationFrame(fadeWithRAF);
                } else {
                  audio.pause();
                  audio.currentTime = 0;
                  const index = audios.indexOf(audio);
                  if (index > -1) {
                    audios.splice(index, 1);
                  }
                  debugLog(`⏹️ [${eventId}] Stopped with fade: ${stopCmd.soundId} (fadeOut: ${fadeOut}ms)`);
                }
              };
              requestAnimationFrame(fadeWithRAF);
            } else {
              audio.pause();
              audio.currentTime = 0;
              const index = audios.indexOf(audio);
              if (index > -1) {
                audios.splice(index, 1);
              }
              debugLog(`⏹️ [${eventId}] Stopped: ${stopCmd.soundId}`);
            }
          });
        }

        // Stop Web Audio API sounds from soundAudioMap
        if (this.state.soundAudioMap.current.has(stopCmd.soundId)) {
          const audioObjects = this.state.soundAudioMap.current.get(stopCmd.soundId) || [];
          const fadeOut = stopCmd.fadeOut ?? 0;

          audioObjects.forEach(({ gainNode, source }) => {
            if (fadeOut > 0 && gainNode) {
              // Use Web Audio API linearRamp for smooth, CPU-efficient fade
              const ctx = this.state.audioContextRef.current;
              if (ctx) {
                const now = ctx.currentTime;
                const fadeSeconds = fadeOut / 1000;
                gainNode.gain.cancelScheduledValues(now);
                gainNode.gain.setValueAtTime(gainNode.gain.value, now);
                gainNode.gain.linearRampToValueAtTime(0, now + fadeSeconds);

                // Schedule stop after fade completes
                this.safeTimeout(() => {
                  if (source) {
                    try {
                      source.stop();
                    } catch (e) {
                      // Already stopped
                    }
                  }
                  debugLog(`⏹️ [${eventId}] Stopped Web Audio with fade: ${stopCmd.soundId} (fadeOut: ${fadeOut}ms)`);
                }, fadeOut);
              }
            } else {
              if (source) {
                try {
                  source.stop();
                } catch (e) {
                  // Already stopped
                }
              }
              debugLog(`⏹️ [${eventId}] Stopped Web Audio: ${stopCmd.soundId}`);
            }
          });

          // Clear the soundAudioMap entry
          this.state.soundAudioMap.current.delete(stopCmd.soundId);
        }
      }, delay);
    });

    // Execute commands - call other events
    executeCommands.forEach((execCmd) => {
      if (!project) {
        console.warn(`⚠️ [${eventId}] Execute command requires project to be passed`);
        return;
      }

      // Find the event to execute by its eventName (we use eventName as ID in the UI)
      const eventToExecute = (project as { events?: GameEvent[] }).events?.find((evt: GameEvent) => evt.eventName === execCmd.eventId);

      if (!eventToExecute) {
        console.warn(`⚠️ [${eventId}] Event not found for Execute command: ${execCmd.eventId}`);
        return;
      }

      const delay = execCmd.delay ?? 0;
      const fadeDuration = execCmd.fadeDuration ?? 0;
      // Only pass volumeMultiplier if Execute command explicitly sets volume
      const volumeMultiplier = execCmd.volume;

      debugLog(`🎬 [${eventId}] Execute command DEBUG:`, {
        execCmdFadeDuration: execCmd.fadeDuration,
        execCmdVolume: execCmd.volume,
        execCmdDelay: execCmd.delay,
        finalFadeDuration: fadeDuration,
        finalVolumeMultiplier: volumeMultiplier,
        finalDelay: delay,
        targetEvent: execCmd.eventId
      });

      if (delay > 0) {
        debugLog(`▶️ [${eventId}] Executing event: ${execCmd.eventId} (delayed ${delay}ms, fadeIn ${fadeDuration}ms, volumeMultiplier ${volumeMultiplier})`);
        this.safeTimeout(() => {
          this.playEvent(eventToExecute, project, fadeDuration, volumeMultiplier);
          audioCount.executeCommands--;
          debugLog(`✅ [${eventId}] Execute command completed. Remaining executes: ${audioCount.executeCommands}`);
          checkAndCleanup();
        }, delay);
      } else {
        debugLog(`▶️ [${eventId}] Executing event: ${execCmd.eventId} (fadeIn ${fadeDuration}ms, volumeMultiplier ${volumeMultiplier})`);
        this.playEvent(eventToExecute, project, fadeDuration, volumeMultiplier);
        audioCount.executeCommands--;
        debugLog(`✅ [${eventId}] Execute command completed. Remaining executes: ${audioCount.executeCommands}`);
        checkAndCleanup();
      }
    });

  }

  stopEvent(selectedEvent: GameEvent | null): void {
    if (!selectedEvent) return;

    const eventId = selectedEvent.id;

    if (this.state.eventAudioRefsMap.current.has(eventId)) {
      const eventAudios = this.state.eventAudioRefsMap.current.get(eventId) || [];
      eventAudios.forEach(audio => {
        audio.pause();
        audio.currentTime = 0;
      });
      this.state.eventAudioRefsMap.current.delete(eventId);
    }

    // Stop only sounds belonging to this event
    this.state.soundAudioMap.current.forEach((audioObjects, soundId) => {
      const remainingObjects = audioObjects.filter(obj => {
        if (obj.eventId === eventId) {
          // Stop this sound as it belongs to the event
          if (obj.source) {
            try {
              obj.source.stop();
            } catch (e) {}
          } else {
            obj.audio.pause();
            obj.audio.currentTime = 0;
          }
          return false; // Remove from array
        }
        return true; // Keep in array
      });

      if (remainingObjects.length === 0) {
        this.state.soundAudioMap.current.delete(soundId);
      } else {
        this.state.soundAudioMap.current.set(soundId, remainingObjects);
      }
    });

    this.setPlayingEvents(prev => {
      const newSet = new Set(prev);
      newSet.delete(eventId);
      return newSet;
    });

    // Only clear current playing sound if no events are playing
    if (this.state.eventAudioRefsMap.current.size === 0) {
      this.setCurrentPlayingSound("");
    }
  }

  stopAllAudio(): void {
    if (this.state.audioRef.current) {
      this.state.audioRef.current.pause();
      this.state.audioRef.current = null;
    }
    if (this.state.audioSourceRef.current) {
      try {
        this.state.audioSourceRef.current.stop();
      } catch (e) {}
      this.state.audioSourceRef.current = null;
    }

    this.state.eventAudioRefsMap.current.forEach(audios => {
      audios.forEach(audio => {
        audio.pause();
      });
    });
    this.state.eventAudioRefsMap.current.clear();

    this.state.soundAudioMap.current.forEach((audioObjects) => {
      audioObjects.forEach(({ audio, source }) => {
        if (source) {
          try {
            source.stop();
          } catch (e) {}
        } else {
          audio.pause();
        }
      });
    });
    this.state.soundAudioMap.current.clear();

    // Dispose all voice insert chains
    disposeAllVoiceInserts();

    this.setIsPlaying(false);
    this.setPlayingEvents(new Set());
    this.setCurrentPlayingSound("");
  }

  /**
   * Clear audio buffer cache
   */
  clearCache(): void {
    if (this.bufferCache) {
      this.bufferCache.clear();
    }
  }

  /**
   * Get cache statistics
   */
  getCacheStats() {
    return this.bufferCache?.getStats() || null;
  }

  /**
   * Preload audio files into cache
   */
  async preloadAudioFiles(soundIds?: string[]): Promise<void> {
    if (!this.bufferCache) return;

    const filesToPreload = soundIds
      ? this.audioFiles.filter(f => soundIds.includes(f.name))
      : this.audioFiles;

    const files = filesToPreload.map(f => ({
      soundId: f.name,
      url: f.url
    }));

    await this.bufferCache.preload(files);
  }

  /**
   * Get the AudioContext.
   * Used by MasterInsertDSP to wire up insert chain.
   */
  getAudioContext(): AudioContext | null {
    return this.state.audioContextRef.current;
  }

  /**
   * Get the master gain node.
   * Used by MasterInsertDSP to insert between master and destination.
   */
  getMasterGainNode(): GainNode | null {
    return this.state.masterGainRef.current;
  }

  /**
   * Get the bus gain nodes.
   * Used by BusInsertDSP to insert between bus gains and master.
   */
  getBusGainNodes(): Record<BusId, GainNode> | null {
    return this.state.busGainsRef.current;
  }

  rerouteSoundToBus(soundId: string, newBus: BusId): void {
    debugLog(`🔀 [REROUTE] Starting reroute for ${soundId} to bus: ${newBus}`);

    const audioObjects = this.state.soundAudioMap.current.get(soundId);

    if (!audioObjects || audioObjects.length === 0) {
      debugLog(`⚠️ [REROUTE] No audio objects found in soundAudioMap for ${soundId}`);

      if (this.state.gainNodeRef.current && this.state.audioSourceRef.current) {
        debugLog(`🔀 [REROUTE] Found gainNodeRef, attempting to reroute...`);
        try {
          this.state.gainNodeRef.current.disconnect();
          this.state.gainNodeRef.current.connect(this.getBusInput(newBus));
          debugLog(`✅ [REROUTE] Successfully rerouted gainNodeRef to ${newBus}`);
        } catch (err) {
          console.error(`❌ [REROUTE] Failed to reroute gainNodeRef:`, err);
        }
      } else {
        debugLog(`⚠️ [REROUTE] No gainNodeRef or audioSourceRef found`);
      }
      return;
    }

    debugLog(`🔀 [REROUTE] Found ${audioObjects.length} instance(s) of ${soundId}`);

    let reroutedCount = 0;
    audioObjects.forEach(({ gainNode, eventId }, index) => {
      if (gainNode) {
        try {
          debugLog(`  🔌 [REROUTE] Disconnecting instance ${index}${eventId ? ` (event: ${eventId})` : ' (command inspector)'}`);
          gainNode.disconnect();
          gainNode.connect(this.getBusInput(newBus));
          debugLog(`  ✅ [REROUTE] Reconnected to ${newBus}`);
          reroutedCount++;
        } catch (err) {
          console.error(`  ❌ [REROUTE] Failed to reroute instance ${index}:`, err);
        }
      } else {
        debugLog(`  ⚠️ [REROUTE] Instance ${index} has no gainNode`);
      }
    });

    if (this.state.gainNodeRef.current && this.state.audioSourceRef.current) {
      try {
        debugLog(`🔀 [REROUTE] Also rerouting gainNodeRef...`);
        this.state.gainNodeRef.current.disconnect();
        this.state.gainNodeRef.current.connect(this.getBusInput(newBus));
        debugLog(`✅ [REROUTE] gainNodeRef rerouted to ${newBus}`);
      } catch (err) {
        console.error(`❌ [REROUTE] Failed to reroute gainNodeRef:`, err);
      }
    }

    debugLog(`✅ [REROUTE] Completed! Rerouted ${reroutedCount}/${audioObjects.length} instances of ${soundId} to ${newBus}`);
  }

  ensureLoopingLayer(spriteId: string, initialVolume: number, bus: BusId = 'music'): void {
    const audioObjects = this.state.soundAudioMap.current.get(spriteId);

    if (audioObjects && audioObjects.length > 0) {
      debugLog(`🎵 [LAYER] Layer ${spriteId} already playing, updating volume to ${initialVolume}`);
      audioObjects.forEach(obj => {
        if (obj.gainNode) {
          obj.gainNode.gain.value = initialVolume;
        }
      });
      return;
    }

    const audioFile = this.audioFileIndex.get(spriteId);
    if (!audioFile) {
      console.warn(`⚠️ [LAYER] Audio file not found: ${spriteId}`);
      return;
    }

    debugLog(`🎵 [LAYER] Starting loop for ${spriteId} with volume ${initialVolume}`);

    (async () => {
      try {
        if (!this.state.audioContextRef.current) {
          this.state.audioContextRef.current = AudioContextManager.getContext();
        }

        const audioContext = this.state.audioContextRef.current;
        await AudioContextManager.resume();

        // Use cache instead of direct fetch+decode
        const audioBuffer = await this.bufferCache!.getBuffer(spriteId, audioFile.url);

        const source = audioContext.createBufferSource();
        source.buffer = audioBuffer;
        source.loop = true;
        source.loopStart = 0;
        source.loopEnd = audioBuffer.duration;

        const localGain = audioContext.createGain();
        localGain.gain.value = initialVolume;

        // Generate voice key for asset insert tracking
        const voiceKey = `${spriteId}:layer:${Date.now()}:${Math.random().toString(36).substr(2, 9)}`;

        source.connect(localGain);

        // Wire through asset inserts if defined, otherwise connect directly to bus
        const outputNode = wireVoiceWithInserts(voiceKey, spriteId, localGain);
        outputNode.connect(this.getBusInput(bus));
        source.start(0);

        if (!this.state.soundAudioMap.current.has(spriteId)) {
          this.state.soundAudioMap.current.set(spriteId, []);
        }
        this.state.soundAudioMap.current.get(spriteId)!.push({
          audio: new Audio(),
          gainNode: localGain,
          source: source,
          voiceKey: voiceKey,
        });

        debugLog(`✅ [LAYER] Layer ${spriteId} started looping at volume ${initialVolume}`);
      } catch (err) {
        console.error(`❌ [LAYER] Failed to start layer ${spriteId}:`, err);
      }
    })();
  }

  fadeLayerToVolume(spriteId: string, targetVolume: number, fadeMs: number): void {
    const audioObjects = this.state.soundAudioMap.current.get(spriteId);

    if (!audioObjects || audioObjects.length === 0) {
      console.warn(`⚠️ [LAYER] Cannot fade ${spriteId}: not playing`);
      return;
    }

    debugLog(`🎚️ [LAYER] Fading ${spriteId} to ${targetVolume} over ${fadeMs}ms`);

    const ctx = this.state.audioContextRef.current;
    if (!ctx) return;

    const now = ctx.currentTime;
    const fadeSeconds = fadeMs / 1000;

    audioObjects.forEach((obj, index) => {
      if (obj.gainNode) {
        // Use Web Audio API linearRamp for smooth, CPU-efficient fade
        obj.gainNode.gain.cancelScheduledValues(now);
        obj.gainNode.gain.setValueAtTime(obj.gainNode.gain.value, now);
        obj.gainNode.gain.linearRampToValueAtTime(targetVolume, now + fadeSeconds);
        debugLog(`✅ [LAYER] Fading ${spriteId}[${index}] to ${targetVolume} over ${fadeMs}ms`);
      }
    });
  }

  // ============ MIX SNAPSHOTS ============

  private snapshotManager: SnapshotManager | null = null;

  /**
   * Initialize snapshot manager (call once after engine is ready)
   */
  initSnapshots(customSnapshots?: MixSnapshot[]): void {
    this.snapshotManager = new SnapshotManager(
      (bus, volume) => this.setBusVolume(bus, volume),
      (layer) => {
        // Handle music layer change through layered music system
        debugLog(`🎵 [SNAPSHOT] Switching music layer to: ${layer}`);
        // Integration with layeredMusicSystem would go here
      },
      customSnapshots
    );
    debugLog('📸 [SNAPSHOT] SnapshotManager initialized');
  }

  /**
   * Transition to a mix snapshot
   */
  transitionToSnapshot(snapshotId: string, options?: SnapshotTransitionOptions): boolean {
    if (!this.snapshotManager) {
      this.initSnapshots();
    }
    debugLog(`📸 [SNAPSHOT] Transitioning to: ${snapshotId}`);
    return this.snapshotManager!.transitionTo(snapshotId, options);
  }

  /**
   * Get current snapshot ID
   */
  getCurrentSnapshotId(): string | null {
    return this.snapshotManager?.getCurrentSnapshotId() ?? null;
  }

  /**
   * Register a custom snapshot
   */
  registerSnapshot(snapshot: MixSnapshot): void {
    if (!this.snapshotManager) {
      this.initSnapshots();
    }
    this.snapshotManager!.registerSnapshot(snapshot);
  }

  /**
   * Get all snapshots
   */
  getSnapshots(): MixSnapshot[] {
    return this.snapshotManager?.getSnapshots() ?? [];
  }

  /**
   * Capture current mix state as a new snapshot
   */
  captureSnapshot(id: string, name: string): MixSnapshot | null {
    if (!this.snapshotManager) {
      this.initSnapshots();
    }
    return this.snapshotManager!.captureCurrentState(id, name, (bus) => this.getBusVolume(bus));
  }

  // ============ CONTROL BUS (RTPC) ============

  private controlBusManager: ControlBusManager | null = null;

  /**
   * Initialize control bus manager
   */
  initControlBuses(customBuses?: ControlBus[]): void {
    this.controlBusManager = new ControlBusManager(
      (path, value) => this.applyControlValue(path, value),
      customBuses
    );
    debugLog('🎛️ [CONTROL BUS] ControlBusManager initialized');
  }

  /**
   * Apply control bus value to target path
   */
  private applyControlValue(path: string, value: number): void {
    const parsed = parseControlPath(path);

    if (parsed.type === 'master' && parsed.param === 'volume') {
      this.setBusVolume('master', value);
    } else if (parsed.type === 'bus' && parsed.busId && parsed.param === 'volume') {
      this.setBusVolume(parsed.busId, value);
    } else if (parsed.type === 'bus' && parsed.busId && parsed.param === 'pan') {
      // Pan control would be implemented here
      debugLog(`🎛️ [CONTROL BUS] Pan control not yet implemented: ${path} = ${value}`);
    } else {
      debugLog(`⚠️ [CONTROL BUS] Unknown path: ${path}`);
    }
  }

  /**
   * Set control bus value (triggers all targets)
   */
  setControlBus(busId: string, value: number): void {
    if (!this.controlBusManager) {
      this.initControlBuses();
    }
    debugLog(`🎛️ [CONTROL BUS] Setting ${busId} = ${value}`);
    this.controlBusManager!.setValue(busId, value);
  }

  /**
   * Get control bus value
   */
  getControlBusValue(busId: string): number | undefined {
    return this.controlBusManager?.getValue(busId);
  }

  /**
   * Register a custom control bus
   */
  registerControlBus(bus: ControlBus): void {
    if (!this.controlBusManager) {
      this.initControlBuses();
    }
    this.controlBusManager!.registerBus(bus);
  }

  /**
   * Get all control buses
   */
  getControlBuses(): ControlBus[] {
    return this.controlBusManager?.getBuses() ?? [];
  }

  /**
   * Reset all control buses to defaults
   */
  resetControlBuses(): void {
    this.controlBusManager?.resetToDefaults();
  }

  // ============ INTENSITY LAYERS ============

  private intensityLayerSystem: IntensityLayerSystem | null = null;

  /**
   * Initialize intensity layer system
   */
  initIntensityLayers(customConfigs?: IntensityLayerConfig[]): void {
    if (!this.state.audioContextRef.current) return;

    this.intensityLayerSystem = new IntensityLayerSystem(
      this.state.audioContextRef.current,
      async (assetId) => {
        // Load buffer through cache
        const audioFile = this.audioFileIndex.get(assetId);
        if (!audioFile) throw new Error(`Asset not found: ${assetId}`);
        return this.bufferCache!.getBuffer(assetId, audioFile.url);
      },
      (bus) => this.state.busGainsRef.current?.[bus] ?? null,
      customConfigs
    );
    debugLog('🎵 [INTENSITY] IntensityLayerSystem initialized');
  }

  /**
   * Start an intensity layer configuration
   */
  async startIntensityLayers(configId: string, initialIntensity: number = 0): Promise<boolean> {
    if (!this.intensityLayerSystem) {
      this.initIntensityLayers();
    }
    debugLog(`🎵 [INTENSITY] Starting config: ${configId} at ${initialIntensity}`);
    return this.intensityLayerSystem!.startConfig(configId, initialIntensity);
  }

  /**
   * Stop intensity layers
   */
  async stopIntensityLayers(fadeOutMs: number = 500): Promise<void> {
    await this.intensityLayerSystem?.stopConfig(fadeOutMs);
  }

  /**
   * Set music intensity (0-1)
   */
  setMusicIntensity(intensity: number, transitionMs?: number): void {
    if (!this.intensityLayerSystem) return;
    debugLog(`🎵 [INTENSITY] Setting intensity to ${intensity}`);
    this.intensityLayerSystem.setIntensity(intensity, transitionMs);
  }

  /**
   * Get current music intensity
   */
  getMusicIntensity(): number {
    return this.intensityLayerSystem?.getCurrentIntensity() ?? 0;
  }

  /**
   * Switch to different layer config
   */
  async switchIntensityConfig(configId: string, crossfadeMs: number = 1000): Promise<boolean> {
    if (!this.intensityLayerSystem) {
      this.initIntensityLayers();
    }
    return this.intensityLayerSystem!.switchConfig(configId, crossfadeMs);
  }

  // ============ DUCKING ============

  private duckingManager: DuckingManager | null = null;

  /**
   * Initialize ducking system
   */
  initDucking(customRules?: DuckingRule[]): void {
    if (!this.state.audioContextRef.current) return;

    this.duckingManager = new DuckingManager(
      this.state.audioContextRef.current,
      (bus) => this.state.busGainsRef.current?.[bus] ?? null,
      customRules
    );
    debugLog('🔊 [DUCKING] DuckingManager initialized');
  }

  /**
   * Start the ducking system
   */
  startDucking(): void {
    if (!this.duckingManager) {
      this.initDucking();
    }
    this.duckingManager!.start();
    debugLog('🔊 [DUCKING] Started');
  }

  /**
   * Stop the ducking system
   */
  stopDucking(): void {
    this.duckingManager?.stop();
    debugLog('🔊 [DUCKING] Stopped');
  }

  /**
   * Notify ducking that a sound started (call from play methods)
   */
  notifyDuckingSoundStart(bus: BusId): void {
    this.duckingManager?.notifySoundStart(bus);
  }

  /**
   * Notify ducking that a sound stopped
   */
  notifyDuckingSoundStop(bus: BusId): void {
    this.duckingManager?.notifySoundStop(bus);
  }

  /**
   * Register custom ducking rule
   */
  registerDuckingRule(rule: DuckingRule): void {
    if (!this.duckingManager) {
      this.initDucking();
    }
    this.duckingManager!.registerRule(rule);
  }

  /**
   * Get current duck level for a bus
   */
  getDuckLevel(bus: BusId): number {
    return this.duckingManager?.getDuckLevel(bus) ?? 1.0;
  }

  /**
   * Dispose all managers
   */
  disposeManagers(): void {
    // Clear all tracked timeouts first to prevent callbacks firing after dispose
    this.clearAllTimeouts();

    this.snapshotManager?.dispose();
    this.controlBusManager?.dispose();
    this.intensityLayerSystem?.dispose();
    this.duckingManager?.dispose();
    this.variationManager?.dispose();
    this.concurrencyManager?.dispose();
    this.sequenceManager?.dispose();
    this.stingerManager?.dispose();
    this.modifierManager?.dispose();
    this.blendManager?.dispose();
    this.priorityManager?.dispose();
    this.eventGroupManager?.dispose();
    this.rtpcManager?.dispose();
    this.gameSyncManager?.dispose();
    this.markerManager?.dispose();
    this.playlistManager?.dispose();
    this.musicTransitionManager?.dispose();
    this.interactiveMusicController?.dispose();
    this.diagnosticsManager?.dispose();
    this.profiler?.dispose();
    this.frameMonitor?.dispose();
    this.busPluginChains.forEach(chain => chain.dispose());
    this.busPluginChains.clear();
    this.spatialManager?.dispose();
    this.spatialVoiceManager?.dispose();
    this.snapshotManager = null;
    this.controlBusManager = null;
    this.intensityLayerSystem = null;
    this.duckingManager = null;
    this.variationManager = null;
    this.concurrencyManager = null;
    this.sequenceManager = null;
    this.stingerManager = null;
    this.modifierManager = null;
    this.blendManager = null;
    this.priorityManager = null;
    this.eventGroupManager = null;
    this.rtpcManager = null;
    this.gameSyncManager = null;
    this.markerManager = null;
    this.playlistManager = null;
    this.musicTransitionManager = null;
    this.interactiveMusicController = null;
    this.diagnosticsManager = null;
    this.profiler = null;
    this.frameMonitor = null;
    this.spatialManager = null;
    this.spatialVoiceManager = null;
  }

  // ============ SOUND VARIATIONS ============

  private variationManager: SoundVariationManager | null = null;

  /**
   * Initialize variation manager (call once after engine is ready)
   */
  initVariations(seed?: number, containers?: VariationContainer[]): void {
    this.variationManager = new SoundVariationManager(seed);
    if (containers) {
      containers.forEach(c => this.variationManager!.registerContainer(c));
    }
    debugLog('🎲 [VARIATION] SoundVariationManager initialized');
  }

  /**
   * Register a variation container
   */
  registerVariationContainer(container: VariationContainer): void {
    if (!this.variationManager) {
      this.initVariations();
    }
    this.variationManager!.registerContainer(container);
    debugLog(`🎲 [VARIATION] Registered container: ${container.id}`);
  }

  /**
   * Get next variation for a container (for custom playback)
   */
  getNextVariation(containerId: string): VariationPlayResult | null {
    if (!this.variationManager) {
      this.initVariations();
    }
    return this.variationManager!.getNextVariation(containerId);
  }

  /**
   * Get variation result for playback (returns asset + modifiers)
   * Use this to get variation and then trigger via game event
   */
  getVariationForPlay(
    containerId: string,
    baseVolume: number = 1.0
  ): { assetId: string; volume: number; pitchMultiplier: number } | null {
    const variation = this.getNextVariation(containerId);
    if (!variation) {
      console.warn(`[VARIATION] Container not found: ${containerId}`);
      return null;
    }

    debugLog(`🎲 [VARIATION] Selected ${variation.assetId} (pitch=${variation.pitchMultiplier.toFixed(3)}, vol=${variation.volumeMultiplier.toFixed(3)})`);

    return {
      assetId: variation.assetId,
      volume: baseVolume * variation.volumeMultiplier,
      pitchMultiplier: variation.pitchMultiplier,
    };
  }

  /**
   * Set seed for reproducibility (casino compliance)
   */
  setVariationSeed(seed: number): void {
    if (!this.variationManager) {
      this.initVariations(seed);
    } else {
      this.variationManager.setSeed(seed);
    }
    debugLog(`🎲 [VARIATION] Seed set to: ${seed}`);
  }

  /**
   * Reset all variation containers
   */
  resetVariations(): void {
    this.variationManager?.resetAll();
    debugLog('🎲 [VARIATION] All containers reset');
  }

  /**
   * Get all registered variation containers
   */
  getVariationContainers(): VariationContainer[] {
    return this.variationManager?.getContainers() ?? [];
  }

  // ============ VOICE CONCURRENCY ============

  private concurrencyManager: VoiceConcurrencyManager | null = null;

  /**
   * Initialize concurrency manager (call once after engine is ready)
   */
  initConcurrency(rules?: VoiceConcurrencyRule[], globalLimit?: number): void {
    this.concurrencyManager = new VoiceConcurrencyManager(rules, globalLimit);
    debugLog('🔊 [CONCURRENCY] VoiceConcurrencyManager initialized');
  }

  /**
   * Request a voice slot (returns null if rejected by policy)
   */
  requestVoice(
    soundId: string,
    bus: BusId,
    volume: number,
    priority?: number
  ): { voiceId: string; volumeMultiplier: number } | null {
    if (!this.concurrencyManager) {
      this.initConcurrency();
    }
    return this.concurrencyManager!.requestVoice(soundId, bus, volume, priority);
  }

  /**
   * Register audio nodes for a voice (for cleanup when killed)
   */
  registerVoiceNodes(
    voiceId: string,
    source: AudioBufferSourceNode,
    gainNode: GainNode
  ): void {
    this.concurrencyManager?.registerVoiceNodes(voiceId, source, gainNode);
  }

  /**
   * Mark voice as ended naturally
   */
  voiceEnded(voiceId: string): void {
    this.concurrencyManager?.voiceEnded(voiceId);
  }

  /**
   * Kill a specific voice
   */
  killVoice(voiceId: string): boolean {
    return this.concurrencyManager?.killVoice(voiceId) ?? false;
  }

  /**
   * Kill all voices
   */
  killAllVoices(): void {
    this.concurrencyManager?.killAll();
    debugLog('🔊 [CONCURRENCY] All voices killed');
  }

  /**
   * Add or update a concurrency rule
   */
  addConcurrencyRule(rule: VoiceConcurrencyRule): void {
    if (!this.concurrencyManager) {
      this.initConcurrency();
    }
    this.concurrencyManager!.addRule(rule);
    debugLog(`🔊 [CONCURRENCY] Rule added for: ${rule.soundPattern}`);
  }

  /**
   * Get current voice count
   */
  getVoiceCount(): number {
    return this.concurrencyManager?.getVoiceCount() ?? 0;
  }

  /**
   * Get voice count for a specific pattern
   */
  getPatternVoiceCount(pattern: string): number {
    return this.concurrencyManager?.getPatternVoiceCount(pattern) ?? 0;
  }

  /**
   * Get all active voices (for debugging)
   */
  getActiveVoices(): ActiveVoice[] {
    return this.concurrencyManager?.getActiveVoices() ?? [];
  }

  /**
   * Get all concurrency rules
   */
  getConcurrencyRules(): VoiceConcurrencyRule[] {
    return this.concurrencyManager?.getRules() ?? [];
  }

  // ============ SEQUENCE CONTAINERS ============

  private sequenceManager: SequenceContainerManager | null = null;

  /**
   * Initialize sequence manager
   */
  initSequences(containers?: SequenceContainer[]): void {
    this.sequenceManager = new SequenceContainerManager(
      (assetId, bus, volume, _pitch) => {
        // Play callback - use internal play method
        this.playSoundInternal(assetId, bus, volume);
        return assetId;
      },
      (voiceId) => {
        // Stop callback
        this.stopSoundInternal(voiceId);
      },
      containers
    );
    debugLog('🎬 [SEQUENCE] SequenceContainerManager initialized');
  }

  /**
   * Play a sequence
   */
  playSequence(containerId: string, options?: SequencePlayOptions): boolean {
    if (!this.sequenceManager) {
      this.initSequences();
    }
    debugLog(`🎬 [SEQUENCE] Playing: ${containerId}`);
    return this.sequenceManager!.playSequence(containerId, options);
  }

  /**
   * Stop a sequence
   */
  stopSequence(containerId: string): void {
    this.sequenceManager?.stopSequence(containerId);
    debugLog(`🎬 [SEQUENCE] Stopped: ${containerId}`);
  }

  /**
   * Pause a sequence
   */
  pauseSequence(containerId: string): void {
    this.sequenceManager?.pauseSequence(containerId);
  }

  /**
   * Resume a sequence
   */
  resumeSequence(containerId: string): void {
    this.sequenceManager?.resumeSequence(containerId);
  }

  /**
   * Stop all sequences
   */
  stopAllSequences(): void {
    this.sequenceManager?.stopAll();
    debugLog('🎬 [SEQUENCE] All sequences stopped');
  }

  /**
   * Register a sequence container
   */
  registerSequence(container: SequenceContainer): void {
    if (!this.sequenceManager) {
      this.initSequences();
    }
    this.sequenceManager!.registerContainer(container);
    debugLog(`🎬 [SEQUENCE] Registered: ${container.id}`);
  }

  /**
   * Check if sequence is playing
   */
  isSequencePlaying(containerId: string): boolean {
    return this.sequenceManager?.isPlaying(containerId) ?? false;
  }

  /**
   * Get all sequence containers
   */
  getSequenceContainers(): SequenceContainer[] {
    return this.sequenceManager?.getContainers() ?? [];
  }

  // ============ STINGERS ============

  private stingerManager: StingerManager | null = null;

  /**
   * Initialize stinger manager
   */
  initStingers(stingers?: Stinger[]): void {
    this.stingerManager = new StingerManager(
      (assetId, bus, volume) => {
        // Play callback
        this.playSoundInternal(assetId, bus, volume);
        return assetId;
      },
      (voiceId, fadeMs) => {
        // Stop callback
        if (fadeMs) {
          this.fadeOutSoundInternal(voiceId, fadeMs);
        } else {
          this.stopSoundInternal(voiceId);
        }
      },
      (duckLevel, fadeMs) => {
        // Music duck callback
        this.setMusicDuck(duckLevel, fadeMs);
      },
      stingers
    );
    debugLog('🎵 [STINGER] StingerManager initialized');
  }

  /**
   * Set music duck level (for stinger ducking)
   */
  private setMusicDuck(level: number, fadeMs: number): void {
    const musicBus = this.state.busGainsRef.current?.music;
    if (!musicBus) return;

    const ctx = this.state.audioContextRef.current;
    if (!ctx) return;

    const now = ctx.currentTime;
    musicBus.gain.cancelScheduledValues(now);
    musicBus.gain.setValueAtTime(musicBus.gain.value, now);
    musicBus.gain.linearRampToValueAtTime(level, now + fadeMs / 1000);
  }

  /**
   * Trigger a stinger
   */
  triggerStinger(stingerId: string, options?: StingerPlayOptions): boolean {
    if (!this.stingerManager) {
      this.initStingers();
    }
    debugLog(`🎵 [STINGER] Triggering: ${stingerId}`);
    return this.stingerManager!.triggerStinger(stingerId, options);
  }

  /**
   * Update beat info for beat-synced stingers
   */
  updateMusicBeatInfo(beatInfo: MusicBeatInfo): void {
    this.stingerManager?.updateBeatInfo(beatInfo);
  }

  /**
   * Stop all stingers
   */
  stopAllStingers(): void {
    this.stingerManager?.stopAll();
    debugLog('🎵 [STINGER] All stingers stopped');
  }

  /**
   * Register a stinger
   */
  registerStinger(stinger: Stinger): void {
    if (!this.stingerManager) {
      this.initStingers();
    }
    this.stingerManager!.registerStinger(stinger);
    debugLog(`🎵 [STINGER] Registered: ${stinger.id}`);
  }

  /**
   * Check if a stinger is playing
   */
  isStingerPlaying(): boolean {
    return this.stingerManager?.isPlaying() ?? false;
  }

  /**
   * Get current stinger
   */
  getCurrentStinger(): Stinger | null {
    return this.stingerManager?.getCurrentStinger() ?? null;
  }

  /**
   * Get all registered stingers
   */
  getStingers(): Stinger[] {
    return this.stingerManager?.getStingers() ?? [];
  }

  /**
   * Get stingers by tag
   */
  getStingersByTag(tag: string): Stinger[] {
    return this.stingerManager?.getStingersByTag(tag) ?? [];
  }

  // ============ HELPER METHODS ============

  /**
   * Simple play sound helper (used by sequences/stingers)
   */
  private playSoundInternal(soundId: string, _bus: BusId, volume: number): void {
    const audioFile = this.audioFileIndex.get(soundId);
    if (!audioFile) {
      console.warn(`[AUDIO] Sound not found: ${soundId}`);
      return;
    }

    // Create a simple play command event
    const event: GameEvent = {
      id: `_internal_${soundId}_${Date.now()}`,
      eventName: soundId,
      commands: [{
        type: 'Play',
        soundId,
        volume,
      } as PlayCommand],
    };

    // Use the existing playEvent method
    this.playEvent(event);
  }

  /**
   * Simple stop sound helper
   */
  private stopSoundInternal(soundId: string): void {
    const audioObjects = this.state.soundAudioMap.current.get(soundId);
    if (audioObjects) {
      audioObjects.forEach(obj => {
        if (obj.source) {
          try {
            obj.source.stop();
          } catch {
            // Already stopped
          }
        }
        if (obj.audio) {
          obj.audio.pause();
          obj.audio.currentTime = 0;
        }
      });
      this.state.soundAudioMap.current.delete(soundId);
    }
  }

  /**
   * Fade out a sound
   */
  private fadeOutSoundInternal(soundId: string, fadeMs: number): void {
    const audioObjects = this.state.soundAudioMap.current.get(soundId);
    if (!audioObjects) return;

    const ctx = this.state.audioContextRef.current;
    if (!ctx) return;

    const now = ctx.currentTime;
    const fadeSeconds = fadeMs / 1000;

    audioObjects.forEach(obj => {
      if (obj.gainNode) {
        obj.gainNode.gain.cancelScheduledValues(now);
        obj.gainNode.gain.setValueAtTime(obj.gainNode.gain.value, now);
        obj.gainNode.gain.linearRampToValueAtTime(0, now + fadeSeconds);

        // Schedule stop after fade
        this.safeTimeout(() => {
          if (obj.source) {
            try {
              obj.source.stop();
            } catch {
              // Already stopped
            }
          }
          if (obj.audio) {
            obj.audio.pause();
          }
        }, fadeMs + 50);
      }
    });
  }

  // ============ PARAMETER MODIFIERS ============

  private modifierManager: ParameterModifierManager | null = null;

  /**
   * Initialize parameter modifier manager
   */
  initModifiers(): void {
    this.modifierManager = new ParameterModifierManager((_modifierId, value, targets) => {
      // Apply modifier value to targets
      targets.forEach(target => {
        const finalValue = target.mode === 'multiply'
          ? value * target.depth
          : value * target.depth;

        if (target.type === 'bus' && target.property === 'volume') {
          // Apply to bus volume
          const busGain = this.state.busGainsRef.current?.[target.targetId as BusId];
          if (busGain) {
            busGain.gain.value = Math.max(0, Math.min(2, finalValue));
          }
        }
      });
    });
    debugLog('🎛️ [MODIFIER] ParameterModifierManager initialized');
  }

  /**
   * Create an LFO
   */
  createLFO(config: LFOConfig): void {
    if (!this.modifierManager) this.initModifiers();
    this.modifierManager!.createLFO(config);
    debugLog(`🎛️ [MODIFIER] LFO created: ${config.id}`);
  }

  /**
   * Create an envelope
   */
  createEnvelope(config: EnvelopeConfig): void {
    if (!this.modifierManager) this.initModifiers();
    this.modifierManager!.createEnvelope(config);
    debugLog(`🎛️ [MODIFIER] Envelope created: ${config.id}`);
  }

  /**
   * Create an automation curve
   */
  createCurve(config: CurveConfig): void {
    if (!this.modifierManager) this.initModifiers();
    this.modifierManager!.createCurve(config);
    debugLog(`🎛️ [MODIFIER] Curve created: ${config.id}`);
  }

  /**
   * Start an LFO with targets
   */
  startLFO(id: string, targets: ModifierTarget[]): boolean {
    if (!this.modifierManager) this.initModifiers();
    return this.modifierManager!.startLFO(id, targets);
  }

  /**
   * Trigger an envelope
   */
  triggerEnvelope(id: string, targets: ModifierTarget[]): boolean {
    if (!this.modifierManager) this.initModifiers();
    return this.modifierManager!.triggerEnvelope(id, targets);
  }

  /**
   * Release an envelope
   */
  releaseEnvelope(id: string): boolean {
    return this.modifierManager?.releaseEnvelope(id) ?? false;
  }

  /**
   * Start a curve
   */
  startCurve(id: string, targets: ModifierTarget[]): boolean {
    if (!this.modifierManager) this.initModifiers();
    return this.modifierManager!.startCurve(id, targets);
  }

  /**
   * Stop a modifier
   */
  stopModifier(id: string): void {
    this.modifierManager?.stopModifier(id);
  }

  /**
   * Set BPM for synced LFOs
   */
  setModifierBpm(bpm: number): void {
    this.modifierManager?.setBpm(bpm);
  }

  /**
   * Get modifier value
   */
  getModifierValue(id: string): number {
    return this.modifierManager?.getValue(id) ?? 0;
  }

  /**
   * Stop all modifiers
   */
  stopAllModifiers(): void {
    this.modifierManager?.stopAll();
  }

  // ============ BLEND CONTAINERS ============

  private blendManager: BlendContainerManager | null = null;

  /**
   * Initialize blend container manager
   */
  initBlendContainers(containers?: BlendContainer[]): void {
    this.blendManager = new BlendContainerManager(
      (assetId, bus, volume, _loop) => {
        // Play callback
        this.playSoundInternal(assetId, bus, volume);
        return assetId;
      },
      (voiceId) => {
        // Stop callback
        this.stopSoundInternal(voiceId);
      },
      (voiceId, volume) => {
        // Set volume callback
        const audioObjects = this.state.soundAudioMap.current.get(voiceId);
        if (audioObjects) {
          audioObjects.forEach(obj => {
            if (obj.gainNode) {
              obj.gainNode.gain.value = volume;
            }
          });
        }
      },
      containers
    );
    debugLog('🎚️ [BLEND] BlendContainerManager initialized');
  }

  /**
   * Start a blend container
   */
  startBlendContainer(containerId: string, options?: BlendPlayOptions): boolean {
    if (!this.blendManager) this.initBlendContainers();
    debugLog(`🎚️ [BLEND] Starting: ${containerId}`);
    return this.blendManager!.startContainer(containerId, options);
  }

  /**
   * Stop a blend container
   */
  stopBlendContainer(containerId: string): void {
    this.blendManager?.stopContainer(containerId);
    debugLog(`🎚️ [BLEND] Stopped: ${containerId}`);
  }

  /**
   * Set blend parameter value
   */
  setBlendValue(containerId: string, value: number, immediate?: boolean): void {
    this.blendManager?.setParameterValue(containerId, value, immediate);
  }

  /**
   * Get blend parameter value
   */
  getBlendValue(containerId: string): number {
    return this.blendManager?.getParameterValue(containerId) ?? 0;
  }

  /**
   * Register a blend container
   */
  registerBlendContainer(container: BlendContainer): void {
    if (!this.blendManager) this.initBlendContainers();
    this.blendManager!.registerContainer(container);
    debugLog(`🎚️ [BLEND] Registered: ${container.id}`);
  }

  /**
   * Check if blend container is playing
   */
  isBlendContainerPlaying(containerId: string): boolean {
    return this.blendManager?.isPlaying(containerId) ?? false;
  }

  /**
   * Get all blend containers
   */
  getBlendContainers(): BlendContainer[] {
    return this.blendManager?.getContainers() ?? [];
  }

  /**
   * Stop all blend containers
   */
  stopAllBlendContainers(): void {
    this.blendManager?.stopAll();
  }

  // ============ PRIORITY SYSTEM ============

  private priorityManager: PriorityManager | null = null;

  /**
   * Initialize priority manager
   */
  initPriority(configs?: Record<string, PriorityConfig>, busLimits?: BusPriorityLimit[]): void {
    this.priorityManager = new PriorityManager(
      (soundId, fadeMs) => {
        // Preempt callback
        this.fadeOutSoundInternal(soundId, fadeMs);
      },
      (assetId, bus, volume) => {
        // Play callback
        this.playSoundInternal(assetId, bus, volume);
        return assetId;
      },
      configs,
      busLimits
    );
    debugLog('🎯 [PRIORITY] PriorityManager initialized');
  }

  /**
   * Play with priority
   */
  playWithPriority(
    assetId: string,
    bus: BusId,
    volume: number,
    priorityKey?: string
  ): { allowed: boolean; soundId: string | null; preempted: string[] } {
    if (!this.priorityManager) this.initPriority();
    const result = this.priorityManager!.requestPlay(assetId, bus, volume, priorityKey);
    if (result.allowed) {
      debugLog(`🎯 [PRIORITY] Playing: ${assetId} (preempted: ${result.preempted.length})`);
    }
    return result;
  }

  /**
   * Boost sound priority
   */
  boostPriority(soundId: string, amount?: number, durationMs?: number): boolean {
    return this.priorityManager?.boostPriority(soundId, amount, durationMs) ?? false;
  }

  /**
   * Register priority config
   */
  registerPriorityConfig(key: string, config: PriorityConfig): void {
    if (!this.priorityManager) this.initPriority();
    this.priorityManager!.registerConfig(key, config);
  }

  /**
   * Set bus priority limit
   */
  setBusPriorityLimit(limit: BusPriorityLimit): void {
    if (!this.priorityManager) this.initPriority();
    this.priorityManager!.setBusLimit(limit);
  }

  /**
   * Mark priority sound as ended
   */
  prioritySoundEnded(soundId: string): void {
    this.priorityManager?.soundEnded(soundId);
  }

  /**
   * Get active priority sound count
   */
  getPrioritySoundCount(bus?: BusId): number {
    return this.priorityManager?.getActiveSoundCount(bus) ?? 0;
  }

  // ============ EVENT GROUPS ============

  private eventGroupManager: EventGroupManager | null = null;

  /**
   * Initialize event group manager
   */
  initEventGroups(groups?: EventGroup[]): void {
    this.eventGroupManager = new EventGroupManager(
      (voiceId, fadeMs) => {
        // Stop callback
        this.fadeOutSoundInternal(voiceId, fadeMs);
      },
      (assetId, bus, volume) => {
        // Play callback
        this.playSoundInternal(assetId, bus, volume);
        return assetId;
      },
      groups
    );
    debugLog('👥 [GROUP] EventGroupManager initialized');
  }

  /**
   * Play with event group rules
   */
  playWithGroup(
    memberId: string,
    bus: BusId,
    volume: number
  ): { allowed: boolean; voiceId: string | null; stopped: string[] } {
    if (!this.eventGroupManager) this.initEventGroups();
    const result = this.eventGroupManager!.requestPlay(memberId, bus, volume);
    if (result.allowed) {
      debugLog(`👥 [GROUP] Playing: ${memberId} (stopped: ${result.stopped.length})`);
    }
    return result;
  }

  /**
   * Mark group member as ended
   */
  groupMemberEnded(memberId: string, voiceId?: string): void {
    this.eventGroupManager?.memberEnded(memberId, voiceId);
  }

  /**
   * Stop all members of a group
   */
  stopEventGroup(groupId: string, fadeMs?: number): void {
    this.eventGroupManager?.stopGroup(groupId, fadeMs);
    debugLog(`👥 [GROUP] Stopped group: ${groupId}`);
  }

  /**
   * Register event group
   */
  registerEventGroup(group: EventGroup): void {
    if (!this.eventGroupManager) this.initEventGroups();
    this.eventGroupManager!.registerGroup(group);
    debugLog(`👥 [GROUP] Registered: ${group.id}`);
  }

  /**
   * Add member to event group
   */
  addMemberToEventGroup(groupId: string, member: EventGroupMember): boolean {
    if (!this.eventGroupManager) this.initEventGroups();
    return this.eventGroupManager!.addMemberToGroup(groupId, member);
  }

  /**
   * Check if event group is active
   */
  isEventGroupActive(groupId: string): boolean {
    return this.eventGroupManager?.isGroupActive(groupId) ?? false;
  }

  /**
   * Get active member for group
   */
  getActiveGroupMember(groupId: string): string | null {
    return this.eventGroupManager?.getActiveMember(groupId) ?? null;
  }

  /**
   * Get all event groups
   */
  getEventGroups(): EventGroup[] {
    return this.eventGroupManager?.getGroups() ?? [];
  }

  /**
   * Stop all event groups
   */
  stopAllEventGroups(fadeMs?: number): void {
    this.eventGroupManager?.stopAll(fadeMs);
  }

  // ============ RTPC (Real-Time Parameter Control) ============

  private rtpcManager: RTPCManager | null = null;

  private initRTPC(): void {
    if (this.rtpcManager) return;

    this.rtpcManager = new RTPCManager(
      // setVolume callback
      (targetId: string, targetType: 'sound' | 'bus', value: number) => {
        if (targetType === 'bus') {
          this.setBusVolume(targetId as BusId, value);
        } else {
          // Set volume on all instances of this sound
          const instances = this.state.soundAudioMap.current.get(targetId);
          instances?.forEach(instance => {
            if (instance.gainNode) {
              instance.gainNode.gain.value = value;
            }
          });
        }
      },
      // setPitch callback
      (targetId: string, value: number) => {
        const instances = this.state.soundAudioMap.current.get(targetId);
        instances?.forEach(instance => {
          if (instance.source) {
            instance.source.playbackRate.value = value;
          }
        });
      },
      // setFilter callback - simplified, would need proper filter nodes
      (_targetId: string, _type: 'lowpass' | 'highpass', _value: number) => {
        // Would need BiquadFilterNode implementation
      }
    );
  }

  /**
   * Set RTPC value
   */
  setRTPC(name: string, value: number): void {
    if (!this.rtpcManager) this.initRTPC();
    this.rtpcManager!.setRTPCValue(name, value);
  }

  /**
   * Get RTPC value
   */
  getRTPC(name: string): number | null {
    return this.rtpcManager?.getRTPCValue(name) ?? null;
  }

  /**
   * Reset RTPC to default
   */
  resetRTPC(name: string): void {
    this.rtpcManager?.resetRTPC(name);
  }

  /**
   * Reset all RTPCs
   */
  resetAllRTPCs(): void {
    this.rtpcManager?.resetAll();
  }

  /**
   * Register custom RTPC
   */
  registerRTPC(definition: RTPCDefinition): void {
    if (!this.rtpcManager) this.initRTPC();
    this.rtpcManager!.registerRTPC(definition);
  }

  /**
   * Add binding to RTPC
   */
  addRTPCBinding(rtpcName: string, binding: RTPCBinding): boolean {
    if (!this.rtpcManager) this.initRTPC();
    return this.rtpcManager!.addBinding(rtpcName, binding);
  }

  /**
   * Get all active RTPC values
   */
  getAllRTPCValues(): Record<string, number> {
    return this.rtpcManager?.getActiveValues() ?? {};
  }

  /**
   * Get all RTPC definitions
   */
  getRTPCDefinitions(): RTPCDefinition[] {
    return this.rtpcManager?.getDefinitions() ?? [];
  }

  // ============ GAME SYNC (States, Switches, Triggers) ============

  private gameSyncManager: GameSyncManager | null = null;

  private initGameSync(): void {
    if (this.gameSyncManager) return;

    this.gameSyncManager = new GameSyncManager(
      // play callback
      (assetId: string, bus: BusId, volume: number) => {
        this.playSound(assetId, volume, false, '', false, bus).catch(() => {});
        return assetId;
      },
      // stop callback
      (assetId: string, _fadeMs?: number) => {
        // Stop all instances of this sound
        const instances = this.state.soundAudioMap.current.get(assetId);
        instances?.forEach(instance => {
          if (instance.source) {
            try { instance.source.stop(); } catch (_e) {}
          }
        });
        this.state.soundAudioMap.current.delete(assetId);
      },
      // stopAll callback
      (_bus?: BusId, _fadeMs?: number) => {
        this.stopAllAudio();
      },
      // setVolume callback
      (targetId: string, targetType: 'sound' | 'bus', volume: number, _fadeMs?: number) => {
        if (targetType === 'bus') {
          this.setBusVolume(targetId as BusId, volume);
        }
      },
      // setRTPC callback
      (name: string, value: number) => {
        this.setRTPC(name, value);
      }
    );
  }

  /**
   * Set game state
   */
  setGameState(groupName: string, stateName: string): boolean {
    if (!this.gameSyncManager) this.initGameSync();
    return this.gameSyncManager!.setState(groupName, stateName);
  }

  /**
   * Get current game state
   */
  getGameState(groupName: string): string | null {
    return this.gameSyncManager?.getState(groupName) ?? null;
  }

  /**
   * Set switch value
   */
  setSwitch(groupName: string, valueName: string): boolean {
    if (!this.gameSyncManager) this.initGameSync();
    return this.gameSyncManager!.setSwitch(groupName, valueName);
  }

  /**
   * Get current switch value
   */
  getSwitch(groupName: string): string | null {
    return this.gameSyncManager?.getSwitch(groupName) ?? null;
  }

  /**
   * Play sound based on switch
   */
  playSwitched(groupName: string, bus: BusId = 'sfx', volume: number = 1): string | null {
    if (!this.gameSyncManager) this.initGameSync();
    return this.gameSyncManager!.playSwitched(groupName, bus, volume);
  }

  /**
   * Post a trigger
   */
  postTrigger(name: string): boolean {
    if (!this.gameSyncManager) this.initGameSync();
    return this.gameSyncManager!.postTrigger(name);
  }

  /**
   * Register custom state group
   */
  registerStateGroup(group: StateGroup): void {
    if (!this.gameSyncManager) this.initGameSync();
    this.gameSyncManager!.registerStateGroup(group);
  }

  /**
   * Register custom switch group
   */
  registerSwitchGroup(group: SwitchGroup): void {
    if (!this.gameSyncManager) this.initGameSync();
    this.gameSyncManager!.registerSwitchGroup(group);
  }

  /**
   * Register custom trigger
   */
  registerTrigger(trigger: Trigger): void {
    if (!this.gameSyncManager) this.initGameSync();
    this.gameSyncManager!.registerTrigger(trigger);
  }

  /**
   * Get game sync snapshot
   */
  getGameSyncSnapshot(): { states: Record<string, string>; switches: Record<string, string> } {
    return this.gameSyncManager?.getSnapshot() ?? { states: {}, switches: {} };
  }

  /**
   * Restore game sync from snapshot
   */
  restoreGameSyncSnapshot(snapshot: { states: Record<string, string>; switches: Record<string, string> }): void {
    this.gameSyncManager?.restoreSnapshot(snapshot);
  }

  /**
   * Get all state groups
   */
  getStateGroups(): StateGroup[] {
    return this.gameSyncManager?.getStateGroups() ?? [];
  }

  /**
   * Get all switch groups
   */
  getSwitchGroups(): SwitchGroup[] {
    return this.gameSyncManager?.getSwitchGroups() ?? [];
  }

  /**
   * Get all triggers
   */
  getTriggers(): Trigger[] {
    return this.gameSyncManager?.getTriggers() ?? [];
  }

  // ============ MARKERS & CUE POINTS ============

  private markerManager: MarkerManager | null = null;

  private initMarkers(): void {
    if (this.markerManager) return;

    this.markerManager = new MarkerManager(
      // play callback
      (assetId: string, bus: BusId, volume: number) => {
        this.playSound(assetId, volume, false, '', false, bus).catch(() => {});
      },
      // stop callback
      (assetId: string) => {
        const instances = this.state.soundAudioMap.current.get(assetId);
        instances?.forEach(instance => {
          if (instance.source) {
            try { instance.source.stop(); } catch (_e) {}
          }
        });
      },
      // setRTPC callback
      (name: string, value: number) => {
        this.setRTPC(name, value);
      },
      // postTrigger callback
      (name: string) => {
        this.postTrigger(name);
      }
    );
  }

  /**
   * Register markers for an asset
   */
  registerAssetMarkers(markers: AssetMarkers): void {
    if (!this.markerManager) this.initMarkers();
    this.markerManager!.registerAssetMarkers(markers);
  }

  /**
   * Get markers for an asset
   */
  getAssetMarkers(assetId: string): AssetMarkers | null {
    return this.markerManager?.getAssetMarkers(assetId) ?? null;
  }

  /**
   * Add a marker to an asset
   */
  addMarker(assetId: string, marker: Marker): boolean {
    if (!this.markerManager) this.initMarkers();
    return this.markerManager!.addMarker(assetId, marker);
  }

  /**
   * Add a region to an asset
   */
  addMarkerRegion(assetId: string, region: MarkerRegion): boolean {
    if (!this.markerManager) this.initMarkers();
    return this.markerManager!.addRegion(assetId, region);
  }

  /**
   * Generate beat markers for an asset
   */
  generateBeatMarkers(
    assetId: string,
    bpm: number,
    duration: number,
    timeSignature?: [number, number],
    beatOffset?: number
  ): void {
    if (!this.markerManager) this.initMarkers();
    this.markerManager!.generateBeatMarkers(assetId, bpm, duration, timeSignature, beatOffset);
  }

  /**
   * Start tracking markers for a playing voice
   */
  startMarkerTracking(assetId: string, voiceId: string, audioStartTime?: number): void {
    if (!this.markerManager) this.initMarkers();
    this.markerManager!.startTracking(assetId, voiceId, audioStartTime);
  }

  /**
   * Stop tracking markers for a voice
   */
  stopMarkerTracking(voiceId: string): void {
    this.markerManager?.stopTracking(voiceId);
  }

  /**
   * Get loop points for an asset
   */
  getLoopPoints(assetId: string): { start: number; end: number } | null {
    return this.markerManager?.getLoopPoints(assetId) ?? null;
  }

  /**
   * Get entry point for transitions
   */
  getEntryPoint(assetId: string): number | null {
    return this.markerManager?.getEntryPoint(assetId) ?? null;
  }

  /**
   * Get exit point for transitions
   */
  getExitPoint(assetId: string): number | null {
    return this.markerManager?.getExitPoint(assetId) ?? null;
  }

  /**
   * Register marker action callback
   */
  registerMarkerCallback(callbackId: string, callback: () => void): void {
    if (!this.markerManager) this.initMarkers();
    this.markerManager!.registerActionCallback(callbackId, callback);
  }

  // ============ PLAYLIST SYSTEM ============

  private playlistManager: PlaylistManager | null = null;

  private initPlaylist(): void {
    if (this.playlistManager) return;

    this.playlistManager = new PlaylistManager(
      // play callback
      (assetId: string, bus: BusId, volume: number) => {
        this.playSound(assetId, volume, false, '', false, bus).catch(() => {});
        return assetId;
      },
      // stop callback
      (voiceId: string, fadeMs?: number) => {
        const instances = this.state.soundAudioMap.current.get(voiceId);
        if (instances && instances.length > 0 && fadeMs && fadeMs > 0) {
          const ctx = this.state.audioContextRef.current;
          instances.forEach(instance => {
            if (instance.gainNode && ctx) {
              instance.gainNode.gain.linearRampToValueAtTime(0, ctx.currentTime + fadeMs / 1000);
            }
          });
          this.safeTimeout(() => {
            instances.forEach(instance => {
              if (instance.source) {
                try { instance.source.stop(); } catch (_e) {}
              }
            });
          }, fadeMs);
        } else {
          instances?.forEach(instance => {
            if (instance.source) {
              try { instance.source.stop(); } catch (_e) {}
            }
          });
        }
      }
    );
  }

  /**
   * Register a playlist
   */
  registerPlaylist(playlist: Playlist): void {
    if (!this.playlistManager) this.initPlaylist();
    this.playlistManager!.registerPlaylist(playlist);
  }

  /**
   * Start playing a playlist
   */
  startPlaylist(playlistId: string, startIndex?: number): boolean {
    if (!this.playlistManager) this.initPlaylist();
    return this.playlistManager!.startPlaylist(playlistId, startIndex);
  }

  /**
   * Stop a playlist
   */
  stopPlaylist(playlistId: string, fadeMs?: number): void {
    this.playlistManager?.stopPlaylist(playlistId, fadeMs);
  }

  /**
   * Pause a playlist
   */
  pausePlaylist(playlistId: string): void {
    this.playlistManager?.pausePlaylist(playlistId);
  }

  /**
   * Resume a playlist
   */
  resumePlaylist(playlistId: string): void {
    this.playlistManager?.resumePlaylist(playlistId);
  }

  /**
   * Next track in playlist
   */
  playlistNextTrack(playlistId: string): boolean {
    return this.playlistManager?.nextTrack(playlistId) ?? false;
  }

  /**
   * Previous track in playlist
   */
  playlistPreviousTrack(playlistId: string): boolean {
    return this.playlistManager?.previousTrack(playlistId) ?? false;
  }

  /**
   * Jump to track in playlist
   */
  playlistJumpToTrack(playlistId: string, trackIndex: number): boolean {
    return this.playlistManager?.jumpToTrack(playlistId, trackIndex) ?? false;
  }

  /**
   * Notify playlist that current track ended
   */
  notifyPlaylistTrackEnded(playlistId: string): void {
    this.playlistManager?.notifyTrackEnded(playlistId);
  }

  /**
   * Set playlist mode
   */
  setPlaylistMode(playlistId: string, mode: PlaylistMode): void {
    this.playlistManager?.setPlaylistMode(playlistId, mode);
  }

  /**
   * Set playlist loop mode
   */
  setPlaylistLoopMode(playlistId: string, loopMode: PlaylistLoopMode): void {
    this.playlistManager?.setLoopMode(playlistId, loopMode);
  }

  /**
   * Get current playlist track
   */
  getCurrentPlaylistTrack(playlistId: string): PlaylistTrack | null {
    return this.playlistManager?.getCurrentTrack(playlistId) ?? null;
  }

  /**
   * Add track to playlist
   */
  addPlaylistTrack(playlistId: string, track: PlaylistTrack, index?: number): boolean {
    if (!this.playlistManager) this.initPlaylist();
    return this.playlistManager!.addTrack(playlistId, track, index);
  }

  /**
   * Get all playlists
   */
  getPlaylists(): Playlist[] {
    return this.playlistManager?.getPlaylists() ?? [];
  }

  // ============ MUSIC TRANSITIONS ============

  private musicTransitionManager: MusicTransitionManager | null = null;

  private initMusicTransition(): void {
    if (this.musicTransitionManager) return;

    this.musicTransitionManager = new MusicTransitionManager(
      // play callback
      (assetId: string, bus: BusId, volume: number, _startTime?: number) => {
        this.playSound(assetId, volume, true, '', false, bus).catch(() => {});
        return assetId;
      },
      // stop callback
      (voiceId: string, fadeMs?: number) => {
        const instances = this.state.soundAudioMap.current.get(voiceId);
        if (instances && fadeMs && fadeMs > 0) {
          const ctx = this.state.audioContextRef.current;
          instances.forEach(instance => {
            if (instance.gainNode && ctx) {
              instance.gainNode.gain.linearRampToValueAtTime(0, ctx.currentTime + fadeMs / 1000);
            }
          });
          this.safeTimeout(() => {
            instances?.forEach(instance => {
              if (instance.source) try { instance.source.stop(); } catch (_e) {}
            });
          }, fadeMs);
        } else {
          instances?.forEach(instance => {
            if (instance.source) try { instance.source.stop(); } catch (_e) {}
          });
        }
      },
      // setVolume callback
      (voiceId: string, volume: number, fadeMs?: number) => {
        const instances = this.state.soundAudioMap.current.get(voiceId);
        const ctx = this.state.audioContextRef.current;
        instances?.forEach(instance => {
          if (instance.gainNode && ctx) {
            if (fadeMs && fadeMs > 0) {
              instance.gainNode.gain.linearRampToValueAtTime(volume, ctx.currentTime + fadeMs / 1000);
            } else {
              instance.gainNode.gain.value = volume;
            }
          }
        });
      },
      // getPlaybackTime callback
      (_voiceId: string) => {
        // Would need to track actual playback time
        return null;
      }
    );
  }

  /**
   * Transition music to a new track
   */
  transitionMusicTo(track: MusicTrackInfo, ruleId?: string, immediate?: boolean): boolean {
    if (!this.musicTransitionManager) this.initMusicTransition();
    return this.musicTransitionManager!.transitionTo(track, ruleId, immediate);
  }

  /**
   * Register music transition rule
   */
  registerMusicTransitionRule(rule: TransitionRule): void {
    if (!this.musicTransitionManager) this.initMusicTransition();
    this.musicTransitionManager!.registerRule(rule);
  }

  /**
   * Cancel pending music transition
   */
  cancelMusicTransition(): boolean {
    return this.musicTransitionManager?.cancelTransition() ?? false;
  }

  /**
   * Get current music track
   */
  getCurrentMusicTrack(): MusicTrackInfo | null {
    return this.musicTransitionManager?.getCurrentTrack() ?? null;
  }

  // ============ INTERACTIVE MUSIC ============

  private interactiveMusicController: InteractiveMusicController | null = null;

  private initInteractiveMusic(): void {
    if (this.interactiveMusicController) return;

    this.interactiveMusicController = new InteractiveMusicController(
      // play callback
      (assetId: string, bus: BusId, volume: number, loop: boolean) => {
        this.playSound(assetId, volume, loop, '', false, bus).catch(() => {});
        return assetId;
      },
      // stop callback
      (voiceId: string, fadeMs?: number) => {
        const instances = this.state.soundAudioMap.current.get(voiceId);
        if (instances && fadeMs && fadeMs > 0) {
          const ctx = this.state.audioContextRef.current;
          instances.forEach(instance => {
            if (instance.gainNode && ctx) {
              instance.gainNode.gain.linearRampToValueAtTime(0, ctx.currentTime + fadeMs / 1000);
            }
          });
          this.safeTimeout(() => {
            instances?.forEach(instance => {
              if (instance.source) try { instance.source.stop(); } catch (_e) {}
            });
          }, fadeMs);
        } else {
          instances?.forEach(instance => {
            if (instance.source) try { instance.source.stop(); } catch (_e) {}
          });
        }
      },
      // setVolume callback
      (voiceId: string, volume: number, fadeMs?: number) => {
        const instances = this.state.soundAudioMap.current.get(voiceId);
        const ctx = this.state.audioContextRef.current;
        instances?.forEach(instance => {
          if (instance.gainNode && ctx) {
            if (fadeMs && fadeMs > 0) {
              instance.gainNode.gain.linearRampToValueAtTime(volume, ctx.currentTime + fadeMs / 1000);
            } else {
              instance.gainNode.gain.value = volume;
            }
          }
        });
      }
    );
  }

  /**
   * Activate interactive music config
   */
  activateInteractiveMusic(configId: string): boolean {
    if (!this.interactiveMusicController) this.initInteractiveMusic();
    return this.interactiveMusicController!.activateConfig(configId);
  }

  /**
   * Set interactive music state
   */
  setMusicState(state: MusicState, immediate?: boolean): boolean {
    if (!this.interactiveMusicController) this.initInteractiveMusic();
    return this.interactiveMusicController!.setState(state, immediate);
  }

  /**
   * Set interactive music intensity
   */
  setInteractiveMusicIntensity(intensity: number, immediate?: boolean): void {
    this.interactiveMusicController?.setIntensity(intensity, immediate);
  }

  /**
   * Get interactive music intensity
   */
  getInteractiveMusicIntensity(): number {
    return this.interactiveMusicController?.getIntensity() ?? 0.5;
  }

  /**
   * Duck interactive music
   */
  duckInteractiveMusic(level?: number): void {
    this.interactiveMusicController?.duck(level);
  }

  /**
   * Unduck interactive music
   */
  unduckInteractiveMusic(fadeMs?: number): void {
    this.interactiveMusicController?.unduck(fadeMs);
  }

  /**
   * Handle win for interactive music
   */
  handleInteractiveMusicWin(tier: 'small' | 'medium' | 'big' | 'mega' | 'epic'): void {
    this.interactiveMusicController?.handleWin(tier);
  }

  /**
   * Handle win end for interactive music
   */
  handleInteractiveMusicWinEnd(): void {
    this.interactiveMusicController?.handleWinEnd();
  }

  /**
   * Handle feature start for interactive music
   */
  handleInteractiveMusicFeatureStart(feature: 'freespins' | 'bonus'): void {
    this.interactiveMusicController?.handleFeatureStart(feature);
  }

  /**
   * Handle feature end for interactive music
   */
  handleInteractiveMusicFeatureEnd(feature: 'freespins' | 'bonus'): void {
    this.interactiveMusicController?.handleFeatureEnd(feature);
  }

  /**
   * Register interactive music config
   */
  registerInteractiveMusicConfig(config: InteractiveMusicConfig): void {
    if (!this.interactiveMusicController) this.initInteractiveMusic();
    this.interactiveMusicController!.registerConfig(config);
  }

  /**
   * Get interactive music configs
   */
  getInteractiveMusicConfigs(): InteractiveMusicConfig[] {
    return this.interactiveMusicController?.getConfigs() ?? [];
  }

  /**
   * Stop interactive music
   */
  stopInteractiveMusic(fadeMs?: number): void {
    this.interactiveMusicController?.stopAll(fadeMs);
  }

  // ============ AUDIO DIAGNOSTICS ============

  private diagnosticsManager: AudioDiagnosticsManager | null = null;

  /**
   * Initialize diagnostics manager
   */
  initDiagnostics(): void {
    if (this.diagnosticsManager) return;

    this.diagnosticsManager = new AudioDiagnosticsManager(
      // getVoiceCountCallback
      () => {
        let count = 0;
        this.state.soundAudioMap.current.forEach(voices => {
          count += voices.length;
        });
        return count;
      },
      // getVoicesPerBusCallback
      () => {
        const perBus: Record<BusId, number> = { master: 0, music: 0, sfx: 0, ambience: 0, voice: 0 };
        // Note: Would need to track bus per voice for accurate counting
        // For now, count total voices as sfx
        this.state.soundAudioMap.current.forEach(voices => {
          perBus.sfx += voices.length;
        });
        return perBus;
      },
      // getCacheStatsCallback
      () => {
        if (!this.bufferCache) return { count: 0, memoryBytes: 0 };
        const stats = this.bufferCache.getStats();
        // Estimate ~1MB per cached buffer (rough average)
        return { count: stats.size, memoryBytes: stats.size * 1024 * 1024 };
      },
      // getContextCallback
      () => this.state.audioContextRef.current,
      // getActiveManagersCallback
      () => {
        const active: string[] = [];
        if (this.snapshotManager) active.push('SnapshotManager');
        if (this.controlBusManager) active.push('ControlBusManager');
        if (this.intensityLayerSystem) active.push('IntensityLayerSystem');
        if (this.duckingManager) active.push('DuckingManager');
        if (this.variationManager) active.push('SoundVariationManager');
        if (this.concurrencyManager) active.push('VoiceConcurrencyManager');
        if (this.sequenceManager) active.push('SequenceContainerManager');
        if (this.stingerManager) active.push('StingerManager');
        if (this.modifierManager) active.push('ParameterModifierManager');
        if (this.blendManager) active.push('BlendContainerManager');
        if (this.priorityManager) active.push('PriorityManager');
        if (this.eventGroupManager) active.push('EventGroupManager');
        if (this.rtpcManager) active.push('RTPCManager');
        if (this.gameSyncManager) active.push('GameSyncManager');
        if (this.markerManager) active.push('MarkerManager');
        if (this.playlistManager) active.push('PlaylistManager');
        if (this.musicTransitionManager) active.push('MusicTransitionManager');
        if (this.interactiveMusicController) active.push('InteractiveMusicController');
        return active;
      }
    );
  }

  /**
   * Enable/disable diagnostics
   */
  setDiagnosticsEnabled(enabled: boolean): void {
    if (!this.diagnosticsManager) this.initDiagnostics();
    this.diagnosticsManager!.setEnabled(enabled);
  }

  /**
   * Get diagnostics snapshot
   */
  getDiagnosticsSnapshot(): DiagnosticsSnapshot | null {
    return this.diagnosticsManager?.getSnapshot() ?? null;
  }

  /**
   * Log diagnostic event
   */
  logDiagnosticEvent(
    type: DiagnosticEventType,
    source: string,
    details: string,
    data?: Record<string, unknown>
  ): void {
    this.diagnosticsManager?.logEvent(type, source, details, data);
  }

  /**
   * Log play event for diagnostics
   */
  logDiagnosticPlay(assetId: string, bus: BusId, volume: number): void {
    this.diagnosticsManager?.logPlay(assetId, bus, volume);
  }

  /**
   * Log stop event for diagnostics
   */
  logDiagnosticStop(assetId: string, fadeMs?: number): void {
    this.diagnosticsManager?.logStop(assetId, fadeMs);
  }

  /**
   * Log error for diagnostics
   */
  logDiagnosticError(source: string, message: string, error?: Error): void {
    this.diagnosticsManager?.logError(source, message, error);
  }

  /**
   * Log warning for diagnostics
   */
  logDiagnosticWarning(source: string, message: string): void {
    this.diagnosticsManager?.logWarning(source, message);
  }

  /**
   * Get diagnostic events by type
   */
  getDiagnosticEventsByType(type: DiagnosticEventType, limit?: number): DiagnosticEvent[] {
    return this.diagnosticsManager?.getEventsByType(type, limit) ?? [];
  }

  /**
   * Get diagnostic error count
   */
  getDiagnosticErrorCount(): number {
    return this.diagnosticsManager?.getErrorCount() ?? 0;
  }

  /**
   * Get diagnostic warning count
   */
  getDiagnosticWarningCount(): number {
    return this.diagnosticsManager?.getWarningCount() ?? 0;
  }

  /**
   * Clear diagnostic event log
   */
  clearDiagnosticEventLog(): void {
    this.diagnosticsManager?.clearEventLog();
  }

  /**
   * Export diagnostics as JSON
   */
  exportDiagnosticsJSON(): string {
    return this.diagnosticsManager?.exportJSON() ?? '{}';
  }

  /**
   * Record update time for diagnostics
   */
  recordDiagnosticUpdateTime(timeMs: number): void {
    this.diagnosticsManager?.recordUpdateTime(timeMs);
  }

  /**
   * Update bus level for diagnostics
   */
  updateDiagnosticBusLevel(bus: BusId, level: number): void {
    this.diagnosticsManager?.updateBusLevel(bus, level);
  }

  // ============ AUDIO PROFILER ============

  private profiler: AudioProfiler | null = null;
  private frameMonitor: FrameTimeMonitor | null = null;

  /**
   * Initialize profiler (uses global instances by default)
   */
  initProfiler(): void {
    if (this.profiler) return;
    this.profiler = audioProfiler;
    this.frameMonitor = frameMonitor;
  }

  /**
   * Enable/disable profiling
   */
  setProfilingEnabled(enabled: boolean): void {
    if (!this.profiler) this.initProfiler();
    this.profiler!.setEnabled(enabled);
    this.frameMonitor!.setEnabled(enabled);
  }

  /**
   * Check if profiling is enabled
   */
  isProfilingEnabled(): boolean {
    return this.profiler?.isEnabled() ?? false;
  }

  /**
   * Start profiling an operation
   */
  startProfile(
    category: ProfileCategory,
    operation: string,
    metadata?: Record<string, unknown>
  ): string {
    return this.profiler?.startProfile(category, operation, metadata) ?? '';
  }

  /**
   * End profiling an operation
   */
  endProfile(id: string): ProfileSample | null {
    return this.profiler?.endProfile(id) ?? null;
  }

  /**
   * Profile a synchronous function
   */
  profile<T>(
    category: ProfileCategory,
    operation: string,
    fn: () => T,
    metadata?: Record<string, unknown>
  ): T {
    if (!this.profiler) return fn();
    return this.profiler.profile(category, operation, fn, metadata);
  }

  /**
   * Profile an async function
   */
  async profileAsync<T>(
    category: ProfileCategory,
    operation: string,
    fn: () => Promise<T>,
    metadata?: Record<string, unknown>
  ): Promise<T> {
    if (!this.profiler) return fn();
    return this.profiler.profileAsync(category, operation, fn, metadata);
  }

  /**
   * Generate profiler report
   */
  generateProfilerReport(): ProfileReport | null {
    return this.profiler?.generateReport() ?? null;
  }

  /**
   * Get profiler samples by category
   */
  getProfilerSamplesByCategory(category: ProfileCategory, limit?: number): ProfileSample[] {
    return this.profiler?.getSamplesByCategory(category, limit) ?? [];
  }

  /**
   * Get slow profiler samples
   */
  getSlowProfilerSamples(thresholdMs: number): ProfileSample[] {
    return this.profiler?.getSlowSamples(thresholdMs) ?? [];
  }

  /**
   * Get average time for profiled operation
   */
  getProfilerAverageTime(category: ProfileCategory, operation?: string): number {
    return this.profiler?.getAverageTime(category, operation) ?? 0;
  }

  /**
   * Clear profiler samples
   */
  clearProfiler(): void {
    this.profiler?.clear();
  }

  /**
   * Export profiler data as JSON
   */
  exportProfilerJSON(): string {
    return this.profiler?.exportJSON() ?? '{}';
  }

  /**
   * Get frame time stats
   */
  getFrameTimeStats(): {
    avgFrameTime: number;
    avgFPS: number;
    minFrameTime: number;
    maxFrameTime: number;
    droppedFrames: number;
    jankPercentage: number;
  } | null {
    return this.frameMonitor?.getStats() ?? null;
  }

  /**
   * Get average FPS
   */
  getAverageFPS(): number {
    return this.frameMonitor?.getAverageFPS() ?? 0;
  }

  /**
   * Get jank percentage
   */
  getJankPercentage(): number {
    return this.frameMonitor?.getJank() ?? 0;
  }

  // ============ CONSOLE LOGGER ============

  /**
   * Enable/disable audio console logging
   */
  setAudioLoggingEnabled(enabled: boolean): void {
    audioLogger.setEnabled(enabled);
  }

  /**
   * Set audio log level
   */
  setAudioLogLevel(level: 'verbose' | 'normal' | 'errors'): void {
    audioLogger.setLogLevel(level);
  }

  // ============ DSP PLUGINS ============

  private busPluginChains: Map<BusId, PluginChain> = new Map();

  /**
   * Get or create plugin chain for a bus
   */
  getBusPluginChain(bus: BusId): PluginChain {
    if (!this.busPluginChains.has(bus)) {
      const ctx = this.state.audioContextRef.current;
      if (!ctx) {
        throw new Error('AudioContext not available');
      }

      const chain = new PluginChain(ctx);
      this.busPluginChains.set(bus, chain);

      // Wire: bus gain → plugin chain → master
      const busGain = this.state.busGainsRef.current?.[bus];
      const masterGain = this.state.masterGainRef.current;

      if (busGain && masterGain) {
        busGain.disconnect();
        busGain.connect(chain.inputNode);
        chain.connect(masterGain);
      }
    }

    return this.busPluginChains.get(bus)!;
  }

  /**
   * Add plugin to bus
   */
  addBusPlugin(bus: BusId, pluginConfig: PluginConfig, id?: string): DSPPlugin {
    const chain = this.getBusPluginChain(bus);
    return chain.addPlugin(pluginConfig, id);
  }

  /**
   * Remove plugin from bus
   */
  removeBusPlugin(bus: BusId, pluginId: string): boolean {
    const chain = this.busPluginChains.get(bus);
    if (!chain) return false;
    return chain.removePlugin(pluginId);
  }

  /**
   * Get plugin from bus
   */
  getBusPlugin(bus: BusId, pluginId: string): DSPPlugin | null {
    const chain = this.busPluginChains.get(bus);
    return chain?.getPlugin(pluginId) ?? null;
  }

  /**
   * Get all plugins on a bus
   */
  getBusPlugins(bus: BusId): DSPPlugin[] {
    const chain = this.busPluginChains.get(bus);
    return chain?.getPlugins() ?? [];
  }

  /**
   * Set plugin parameter
   */
  setPluginParameter(bus: BusId, pluginId: string, paramName: string, value: number): void {
    const plugin = this.getBusPlugin(bus, pluginId);
    plugin?.setParameter(paramName, value);
  }

  /**
   * Get plugin parameter
   */
  getPluginParameter(bus: BusId, pluginId: string, paramName: string): number {
    const plugin = this.getBusPlugin(bus, pluginId);
    return plugin?.getParameter(paramName) ?? 0;
  }

  /**
   * Set plugin wet/dry mix
   */
  setPluginWetDry(bus: BusId, pluginId: string, value: number): void {
    const plugin = this.getBusPlugin(bus, pluginId);
    plugin?.setWetDry(value);
  }

  /**
   * Enable/disable plugin
   */
  setPluginEnabled(bus: BusId, pluginId: string, enabled: boolean): void {
    const plugin = this.getBusPlugin(bus, pluginId);
    plugin?.setEnabled(enabled);
  }

  /**
   * Move plugin in chain
   */
  movePluginInChain(bus: BusId, pluginId: string, newIndex: number): boolean {
    const chain = this.busPluginChains.get(bus);
    if (!chain) return false;
    return chain.movePlugin(pluginId, newIndex);
  }

  /**
   * Create standalone plugin (not attached to bus)
   */
  createPlugin(pluginConfig: PluginConfig, id?: string): DSPPlugin {
    const ctx = this.state.audioContextRef.current;
    if (!ctx) {
      throw new Error('AudioContext not available');
    }
    return createPlugin(ctx, pluginConfig, id);
  }

  /**
   * Clear all plugins from a bus
   */
  clearBusPlugins(bus: BusId): void {
    const chain = this.busPluginChains.get(bus);
    if (!chain) return;

    chain.dispose();
    this.busPluginChains.delete(bus);

    // Reconnect bus directly to master
    const busGain = this.state.busGainsRef.current?.[bus];
    const masterGain = this.state.masterGainRef.current;
    if (busGain && masterGain) {
      busGain.connect(masterGain);
    }
  }

  // ============ SPATIAL AUDIO ============

  private spatialManager: SpatialAudioManager | null = null;
  private spatialVoiceManager: SpatialVoiceManager | null = null;

  /**
   * Initialize spatial audio system
   */
  initSpatialAudio(): void {
    if (this.spatialManager) return;

    const ctx = this.state.audioContextRef.current;
    if (!ctx) {
      console.warn('Cannot init spatial audio: AudioContext not available');
      return;
    }

    this.spatialManager = new SpatialAudioManager(ctx);
    this.spatialManager.connect(this.state.masterGainRef.current!);

    // Create voice manager with buffer callback
    this.spatialVoiceManager = new SpatialVoiceManager(
      ctx,
      this.spatialManager,
      async (assetId: string) => {
        const file = this.audioFileIndex.get(assetId);
        if (!file) throw new Error(`Asset not found: ${assetId}`);
        return this.bufferCache!.getBuffer(assetId, file.url);
      }
    );
  }

  /**
   * Set listener position
   */
  setListenerPosition(position: Vector3): void {
    if (!this.spatialManager) this.initSpatialAudio();
    this.spatialManager!.setListenerPosition(position);
  }

  /**
   * Set listener orientation
   */
  setListenerOrientation(orientation: Orientation3D): void {
    if (!this.spatialManager) this.initSpatialAudio();
    this.spatialManager!.setListenerOrientation(orientation);
  }

  /**
   * Get listener position
   */
  getListenerPosition(): Vector3 {
    return this.spatialManager?.getListenerPosition() ?? { x: 0, y: 0, z: 0 };
  }

  /**
   * Create a spatial source
   */
  createSpatialSource(config: Partial<SpatialSourceConfig> & { id: string }): ActiveSpatialSource | null {
    if (!this.spatialManager) this.initSpatialAudio();
    return this.spatialManager!.createSource(config);
  }

  /**
   * Create a spatial source from preset
   */
  createSpatialSourceFromPreset(
    id: string,
    preset: keyof typeof SPATIAL_PRESETS,
    position: Vector3
  ): ActiveSpatialSource | null {
    const presetConfig = SPATIAL_PRESETS[preset];
    return this.createSpatialSource({
      id,
      position,
      ...presetConfig,
    });
  }

  /**
   * Remove a spatial source
   */
  removeSpatialSource(id: string): boolean {
    return this.spatialManager?.removeSource(id) ?? false;
  }

  /**
   * Update spatial source position
   */
  updateSpatialSourcePosition(id: string, position: Vector3): void {
    this.spatialManager?.updateSourcePosition(id, position);
  }

  /**
   * Update spatial source orientation
   */
  updateSpatialSourceOrientation(id: string, orientation: Vector3): void {
    this.spatialManager?.updateSourceOrientation(id, orientation);
  }

  /**
   * Set spatial source volume
   */
  setSpatialSourceVolume(id: string, volume: number): void {
    this.spatialManager?.setSourceVolume(id, volume);
  }

  /**
   * Play a spatial sound
   */
  async playSpatialSound(
    assetId: string,
    sourceConfig: Partial<SpatialSourceConfig> & { id: string },
    volume: number = 1,
    loop: boolean = false
  ): Promise<string | null> {
    if (!this.spatialVoiceManager) this.initSpatialAudio();
    return this.spatialVoiceManager!.playSpatial(assetId, sourceConfig, volume, loop);
  }

  /**
   * Play a spatial sound at position (simplified API)
   */
  async playSpatialSoundAt(
    assetId: string,
    position: Vector3,
    volume: number = 1,
    loop: boolean = false,
    preset: keyof typeof SPATIAL_PRESETS = 'point'
  ): Promise<string | null> {
    const sourceId = `auto_${assetId}_${Date.now()}`;
    const presetConfig = SPATIAL_PRESETS[preset];

    return this.playSpatialSound(assetId, {
      id: sourceId,
      position,
      ...presetConfig,
    }, volume, loop);
  }

  /**
   * Stop a spatial voice
   */
  stopSpatialVoice(voiceId: string, fadeMs: number = 0): boolean {
    return this.spatialVoiceManager?.stopVoice(voiceId, fadeMs) ?? false;
  }

  /**
   * Stop all voices for a spatial source
   */
  stopSpatialSource(sourceId: string, fadeMs: number = 0): void {
    this.spatialVoiceManager?.stopSourceVoices(sourceId, fadeMs);
  }

  /**
   * Register an audio zone
   */
  registerAudioZone(zone: AudioZone): void {
    if (!this.spatialManager) this.initSpatialAudio();
    this.spatialManager!.registerZone(zone);
  }

  /**
   * Remove an audio zone
   */
  removeAudioZone(id: string): boolean {
    return this.spatialManager?.removeZone(id) ?? false;
  }

  /**
   * Get zones at a point
   */
  getAudioZonesAtPoint(point: Vector3): AudioZone[] {
    return this.spatialManager?.getZonesAtPoint(point) ?? [];
  }

  /**
   * Apply occlusion to a spatial source
   */
  applySpatialOcclusion(sourceId: string, factor: number, lowpassFreq?: number): void {
    this.spatialManager?.applyOcclusion(sourceId, factor, lowpassFreq);
  }

  /**
   * Remove occlusion from a spatial source
   */
  removeSpatialOcclusion(sourceId: string): void {
    this.spatialManager?.removeOcclusion(sourceId);
  }

  /**
   * Get distance from listener to source
   */
  getDistanceToSpatialSource(sourceId: string): number | null {
    return this.spatialManager?.getDistanceToSource(sourceId) ?? null;
  }

  /**
   * Get direction from listener to source
   */
  getDirectionToSpatialSource(sourceId: string): Vector3 | null {
    return this.spatialManager?.getDirectionToSource(sourceId) ?? null;
  }

  /**
   * Get active spatial voice count
   */
  getSpatialVoiceCount(): number {
    return this.spatialVoiceManager?.getActiveVoiceCount() ?? 0;
  }

  /**
   * Get spatial source
   */
  getSpatialSource(id: string): ActiveSpatialSource | null {
    return this.spatialManager?.getSource(id) ?? null;
  }

  /**
   * Get spatial presets
   */
  getSpatialPresets(): typeof SPATIAL_PRESETS {
    return SPATIAL_PRESETS;
  }
}