/**
 * ReelForge M7.1 Preview Mix Sync Hook
 *
 * Provides integration between AudioEngine actions and PreviewMixContext.
 * Call these handlers instead of direct AudioEngine methods to keep
 * preview mix state in sync.
 *
 * Also integrates with BusInsertContext for WebAudio ducking.
 */

import { useCallback } from 'react';
import { usePreviewMix } from '../core/PreviewMixContext';
import type { BusId } from '../core/types';
import type { AudioEngine } from '../core/audioEngine';
import { busInsertDSP, DUCKING_CONFIG } from '../core/busInsertDSP';

interface UsePreviewMixSyncOptions {
  audioEngine?: AudioEngine | null;
}

export function usePreviewMixSync({ audioEngine }: UsePreviewMixSyncOptions = {}) {
  const {
    setBusGain,
    onVoiceStart,
    onVoiceEnd,
    onStopAll,
    fullReset,
    snapshot,
  } = usePreviewMix();

  /**
   * Call when StopAll is triggered (from UI or RuntimeCore).
   * Syncs preview mix state with the action.
   */
  const handleStopAll = useCallback(() => {
    // Stop all audio in engine
    audioEngine?.stopAllAudio();
    // Reset preview mix state (clears voices, resets ducking)
    onStopAll();
    // Reset WebAudio ducking
    busInsertDSP.resetDucking();
  }, [audioEngine, onStopAll]);

  /**
   * Call when a sound starts playing on a bus.
   * If the bus is the ducker bus (VO), triggers WebAudio ducking.
   */
  const handleVoiceStart = useCallback((busId: BusId) => {
    onVoiceStart(busId);
    // Trigger WebAudio ducking if voice starts on ducker bus
    if (busId === DUCKING_CONFIG.DUCKER_BUS) {
      busInsertDSP.onDuckerVoiceStart();
    }
  }, [onVoiceStart]);

  /**
   * Call when a sound ends on a bus.
   * If the bus is the ducker bus (VO), removes WebAudio ducking.
   */
  const handleVoiceEnd = useCallback((busId: BusId) => {
    onVoiceEnd(busId);
    // Remove WebAudio ducking if voice ends on ducker bus
    if (busId === DUCKING_CONFIG.DUCKER_BUS) {
      busInsertDSP.onDuckerVoiceEnd();
    }
  }, [onVoiceEnd]);

  /**
   * Call when SetBusGain action is executed.
   */
  const handleSetBusGain = useCallback((busId: BusId, gain: number) => {
    // Update both AudioEngine and preview mix state
    audioEngine?.setBusVolume(busId, gain);
    setBusGain(busId, gain);
  }, [audioEngine, setBusGain]);

  /**
   * Call on project load or session reset.
   * Fully resets preview mix state.
   */
  const handleFullReset = useCallback(() => {
    audioEngine?.stopAllAudio();
    fullReset();
    // Reset WebAudio ducking
    busInsertDSP.resetDucking();
  }, [audioEngine, fullReset]);

  /**
   * Sync preview mix gains with AudioEngine current state.
   * Call this after project load to sync initial state.
   */
  const syncFromAudioEngine = useCallback(() => {
    if (!audioEngine) return;

    const buses: BusId[] = ['master', 'music', 'sfx', 'ambience', 'voice'];
    for (const busId of buses) {
      const gain = audioEngine.getBusVolume(busId);
      setBusGain(busId, gain);
    }
  }, [audioEngine, setBusGain]);

  /**
   * Get current WebAudio ducking state.
   */
  const getDuckingState = useCallback(() => {
    return busInsertDSP.getDuckingState();
  }, []);

  return {
    handleStopAll,
    handleVoiceStart,
    handleVoiceEnd,
    handleSetBusGain,
    handleFullReset,
    syncFromAudioEngine,
    getDuckingState,
    snapshot,
  };
}
