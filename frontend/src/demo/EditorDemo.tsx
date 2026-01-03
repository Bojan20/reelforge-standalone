/**
 * ReelForge Editor Demo
 *
 * Integration demo showing all components working together:
 * - Transport Bar
 * - Timeline
 * - Mixer
 * - Keyboard Shortcuts
 *
 * @module demo/EditorDemo
 */

import { useState, useEffect, useCallback } from 'react';
import { TransportBar } from '../transport/TransportBar';
import { Mixer, type ChannelState } from '../mixer/Mixer';
import { useShortcutManager, DEFAULT_SHORTCUTS } from '../shortcuts/useKeyboardShortcuts';
import { ShortcutsPanel } from '../shortcuts/ShortcutsPanel';
import './EditorDemo.css';

// ============ Types ============

interface DemoState {
  isPlaying: boolean;
  isRecording: boolean;
  currentTime: number;
  tempo: number;
  timeSignature: [number, number];
  loopEnabled: boolean;
  loopStart: number;
  loopEnd: number;
  metronomeEnabled: boolean;
  showMixer: boolean;
  showShortcuts: boolean;
}

// ============ Component ============

export function EditorDemo() {
  const [state, setState] = useState<DemoState>({
    isPlaying: false,
    isRecording: false,
    currentTime: 0,
    tempo: 120,
    timeSignature: [4, 4],
    loopEnabled: false,
    loopStart: 0,
    loopEnd: 16,
    metronomeEnabled: false,
    showMixer: true,
    showShortcuts: false,
  });

  const shortcutManager = useShortcutManager();

  // Playback timer
  useEffect(() => {
    if (!state.isPlaying) return;

    const interval = setInterval(() => {
      setState((prev) => {
        let newTime = prev.currentTime + 0.05;

        // Loop handling
        if (prev.loopEnabled && newTime >= prev.loopEnd) {
          newTime = prev.loopStart;
        }

        return { ...prev, currentTime: newTime };
      });
    }, 50);

    return () => clearInterval(interval);
  }, [state.isPlaying]);

  // Register shortcuts
  useEffect(() => {
    // Transport shortcuts
    shortcutManager.register({
      ...DEFAULT_SHORTCUTS.find((s) => s.id === 'transport.play')!,
      action: () =>
        setState((prev) => ({ ...prev, isPlaying: !prev.isPlaying })),
    });

    shortcutManager.register({
      ...DEFAULT_SHORTCUTS.find((s) => s.id === 'transport.stop')!,
      action: () =>
        setState((prev) => ({ ...prev, isPlaying: false, currentTime: 0 })),
    });

    shortcutManager.register({
      ...DEFAULT_SHORTCUTS.find((s) => s.id === 'transport.loop')!,
      action: () =>
        setState((prev) => ({ ...prev, loopEnabled: !prev.loopEnabled })),
    });

    shortcutManager.register({
      ...DEFAULT_SHORTCUTS.find((s) => s.id === 'view.toggleMixer')!,
      action: () =>
        setState((prev) => ({ ...prev, showMixer: !prev.showMixer })),
    });

    // Show shortcuts with ?
    shortcutManager.register({
      id: 'help.shortcuts',
      name: 'Show Shortcuts',
      key: 'Slash',
      modifiers: ['shift'],
      category: 'Help',
      action: () =>
        setState((prev) => ({ ...prev, showShortcuts: !prev.showShortcuts })),
    });
  }, [shortcutManager]);

  // Transport handlers
  const handlePlay = useCallback(() => {
    setState((prev) => ({ ...prev, isPlaying: true }));
  }, []);

  const handlePause = useCallback(() => {
    setState((prev) => ({ ...prev, isPlaying: false }));
  }, []);

  const handleStop = useCallback(() => {
    setState((prev) => ({ ...prev, isPlaying: false, currentTime: 0 }));
  }, []);

  const handleRecord = useCallback(() => {
    setState((prev) => ({
      ...prev,
      isRecording: !prev.isRecording,
      isPlaying: !prev.isRecording ? true : prev.isPlaying,
    }));
  }, []);

  const handleRewind = useCallback(() => {
    setState((prev) => ({
      ...prev,
      currentTime: Math.max(0, prev.currentTime - 4),
    }));
  }, []);

  const handleForward = useCallback(() => {
    setState((prev) => ({
      ...prev,
      currentTime: prev.currentTime + 4,
    }));
  }, []);

  const handleTempoChange = useCallback((tempo: number) => {
    setState((prev) => ({ ...prev, tempo }));
  }, []);

  const handleLoopToggle = useCallback(() => {
    setState((prev) => ({ ...prev, loopEnabled: !prev.loopEnabled }));
  }, []);

  const handleMetronomeToggle = useCallback(() => {
    setState((prev) => ({ ...prev, metronomeEnabled: !prev.metronomeEnabled }));
  }, []);

  // Mixer handlers
  const handleChannelChange = useCallback((channel: ChannelState) => {
    console.log('Channel changed:', channel);
  }, []);

  const handleMasterVolumeChange = useCallback((volume: number) => {
    console.log('Master volume:', volume);
  }, []);

  return (
    <div className="editor-demo">
      {/* Transport Bar */}
      <TransportBar
        isPlaying={state.isPlaying}
        isRecording={state.isRecording}
        currentTime={state.currentTime}
        duration={60}
        tempo={state.tempo}
        timeSignature={state.timeSignature}
        loopEnabled={state.loopEnabled}
        loopStart={state.loopStart}
        loopEnd={state.loopEnd}
        metronomeEnabled={state.metronomeEnabled}
        onPlay={handlePlay}
        onPause={handlePause}
        onStop={handleStop}
        onRecord={handleRecord}
        onRewind={handleRewind}
        onForward={handleForward}
        onTempoChange={handleTempoChange}
        onLoopToggle={handleLoopToggle}
        onMetronomeToggle={handleMetronomeToggle}
      />

      {/* Main Content Area */}
      <div className="editor-demo__content">
        {/* Timeline Placeholder */}
        <div className="editor-demo__timeline">
          <div className="editor-demo__timeline-header">
            <h3>Timeline</h3>
            <span className="editor-demo__time">
              {state.currentTime.toFixed(2)}s
            </span>
          </div>
          <div className="editor-demo__timeline-tracks">
            {/* Placeholder tracks */}
            {['Drums', 'Bass', 'Keys', 'Guitar', 'Vocals', 'FX'].map(
              (name, i) => (
                <div key={name} className="editor-demo__track">
                  <div className="editor-demo__track-header">
                    <span
                      className="editor-demo__track-color"
                      style={{
                        background: [
                          '#4a9eff',
                          '#ff6b6b',
                          '#51cf66',
                          '#ffd43b',
                          '#cc5de8',
                          '#ff922b',
                        ][i],
                      }}
                    />
                    <span className="editor-demo__track-name">{name}</span>
                  </div>
                  <div className="editor-demo__track-content">
                    {/* Playhead */}
                    <div
                      className="editor-demo__playhead"
                      style={{
                        left: `${(state.currentTime / 60) * 100}%`,
                      }}
                    />
                    {/* Sample clip */}
                    {i < 5 && (
                      <div
                        className="editor-demo__clip"
                        style={{
                          left: `${i * 5}%`,
                          width: `${20 + i * 5}%`,
                          background: [
                            '#4a9eff',
                            '#ff6b6b',
                            '#51cf66',
                            '#ffd43b',
                            '#cc5de8',
                          ][i],
                        }}
                      >
                        <span>{name} Clip</span>
                      </div>
                    )}
                  </div>
                </div>
              )
            )}
          </div>
        </div>

        {/* Mixer */}
        {state.showMixer && (
          <div className="editor-demo__mixer">
            <Mixer
              onChannelChange={handleChannelChange}
              onMasterVolumeChange={handleMasterVolumeChange}
              compact
            />
          </div>
        )}
      </div>

      {/* Status Bar */}
      <div className="editor-demo__status">
        <span>ReelForge Editor Demo</span>
        <span>|</span>
        <span>Press ? for shortcuts</span>
        <span>|</span>
        <span>Cmd/Ctrl+M to toggle mixer</span>
        <span>|</span>
        <span>Space to play/pause</span>
      </div>

      {/* Shortcuts Panel Modal */}
      {state.showShortcuts && (
        <div
          className="editor-demo__modal-backdrop"
          onClick={() => setState((prev) => ({ ...prev, showShortcuts: false }))}
        >
          <div
            className="editor-demo__modal"
            onClick={(e) => e.stopPropagation()}
          >
            <ShortcutsPanel
              manager={shortcutManager}
              onClose={() =>
                setState((prev) => ({ ...prev, showShortcuts: false }))
              }
            />
          </div>
        </div>
      )}
    </div>
  );
}

export default EditorDemo;
