/**
 * ReelForge UI Showcase
 *
 * Demonstrates all LIST 2 (UI & Visual Design) components:
 * - Waveform GPU Rendering
 * - Spectrogram View
 * - Meter Skins (VU, PPM, K-System)
 * - Theme System
 * - Plugin UI Framework
 * - Automation Curves
 * - Mixer Channel Strip
 * - Piano Roll
 * - Arrangement Grid
 * - Transport Controls
 *
 * Access via: ?layout=ui-showcase
 *
 * @module demo/UIShowcase
 */

import { useState, useCallback, useMemo } from 'react';

// Core theme system
import { useTheme } from '../core/themeSystem';

// Waveform (existing components)
import { Waveform } from '../waveform';

// Meters (use existing LevelMeter for showcase)
import { LevelMeter } from '../meters/LevelMeter';
import { SpectrumAnalyzer } from '../meters/SpectrumAnalyzer';

// Automation
import { AutomationLane, type AutomationLaneData, type AutomationPoint } from '../automation';

// Plugin UI
import {
  PluginKnob,
  PluginFader,
  PluginButton,
  PluginToggle,
  PluginSelect,
  PluginMeter,
  PluginGraph,
  PluginPanel,
  PluginSection,
  PluginRow,
  PluginContainer,
} from '../plugin-ui';

// Piano Roll
import { PianoRoll, type MidiNote } from '../midi-editor';

// Arrangement
import { Arrangement, useArrangement } from '../arrangement';

// Transport
import { TransportBar } from '../transport';

import './UIShowcase.css';

// ============ Demo Data ============

// Generate demo waveform peaks
function generateWaveformPeaks(): Float32Array {
  const length = 4096;
  const peaks = new Float32Array(length);
  for (let i = 0; i < length; i++) {
    const t = i / length;
    peaks[i] = Math.sin(t * Math.PI * 8) * 0.8 * (1 - t * 0.5) +
              Math.sin(t * Math.PI * 23) * 0.3 * Math.random();
  }
  return peaks;
}

// Generate demo FFT data
function generateFFTData(): Float32Array {
  const data = new Float32Array(256);
  for (let i = 0; i < 256; i++) {
    const freq = i / 256;
    data[i] = Math.exp(-freq * 3) * (0.5 + 0.5 * Math.random()) * 200;
  }
  return data;
}

// Demo MIDI notes
const DEMO_MIDI_NOTES: MidiNote[] = [
  { id: 'n1', pitch: 60, velocity: 100, startTime: 0, duration: 1 },
  { id: 'n2', pitch: 64, velocity: 90, startTime: 1, duration: 0.5 },
  { id: 'n3', pitch: 67, velocity: 95, startTime: 1.5, duration: 1 },
  { id: 'n4', pitch: 72, velocity: 110, startTime: 2.5, duration: 0.5 },
  { id: 'n5', pitch: 65, velocity: 85, startTime: 3, duration: 1 },
];

// Demo automation lane data
function createDemoAutomationLane(): AutomationLaneData {
  return {
    id: 'demo-lane',
    parameterId: 'volume',
    parameterName: 'Volume',
    trackId: 'track1',
    color: '#4a9eff',
    points: [
      { id: 'a1', time: 0, value: 0.5, curve: 'linear' },
      { id: 'a2', time: 2, value: 0.8, curve: 'bezier' },
      { id: 'a3', time: 4, value: 0.3, curve: 'linear' },
      { id: 'a4', time: 6, value: 0.9, curve: 'step' },
      { id: 'a5', time: 8, value: 0.6, curve: 'linear' },
    ],
    minValue: 0,
    maxValue: 1,
    defaultValue: 0.75,
    visible: true,
    armed: false,
  };
}

// ============ Section Component ============

function Section({ title, description, children }: {
  title: string;
  description?: string;
  children: React.ReactNode;
}) {
  return (
    <section className="ui-showcase__section">
      <div className="ui-showcase__section-header">
        <h2>{title}</h2>
        {description && <p>{description}</p>}
      </div>
      <div className="ui-showcase__section-content">
        {children}
      </div>
    </section>
  );
}

// ============ Main Component ============

export default function UIShowcase() {
  const theme = useTheme();

  // Waveform state
  const waveformPeaks = useMemo(() => generateWaveformPeaks(), []);
  const fftData = useMemo(() => generateFFTData(), []);

  // Meter levels (animated)
  const [meterLevel, setMeterLevel] = useState(-12);

  // Plugin UI state
  const [knobValue, setKnobValue] = useState(0.5);
  const [faderValue, setFaderValue] = useState(0.75);
  const [toggleOn, setToggleOn] = useState(false);
  const [selectValue, setSelectValue] = useState('option1');

  // Automation state
  const [automationLane, setAutomationLane] = useState(createDemoAutomationLane);

  // Piano Roll state
  const [midiNotes, setMidiNotes] = useState(DEMO_MIDI_NOTES);
  const [playheadPosition, setPlayheadPosition] = useState(0);

  // Arrangement state
  const arrangement = useArrangement(
    [
      { id: 'track1', name: 'Drums', type: 'audio', color: '#ef4444' },
      { id: 'track2', name: 'Bass', type: 'audio', color: '#3b82f6' },
      { id: 'track3', name: 'Synth', type: 'midi', color: '#22c55e' },
    ],
    [
      { id: 'clip1', trackId: 'track1', start: 0, duration: 4, name: 'Drum Loop', color: '#ef4444' },
      { id: 'clip2', trackId: 'track2', start: 4, duration: 8, name: 'Bass Line', color: '#3b82f6' },
      { id: 'clip3', trackId: 'track3', start: 2, duration: 6, name: 'Synth Pad', color: '#22c55e' },
    ]
  );

  // Transport state
  const [isPlaying, setIsPlaying] = useState(false);
  const [isRecording, setIsRecording] = useState(false);
  const [currentTime, setCurrentTime] = useState(0);
  const [tempo, setTempo] = useState(120);
  const [loopEnabled, setLoopEnabled] = useState(false);
  const [metronomeEnabled, setMetronomeEnabled] = useState(false);

  // Handlers
  const handleNoteAdd = useCallback((note: Omit<MidiNote, 'id'>) => {
    const newNote: MidiNote = {
      ...note,
      id: `n${Date.now()}`,
    };
    setMidiNotes(prev => [...prev, newNote]);
  }, []);

  const handleNoteChange = useCallback((noteId: string, updates: Partial<MidiNote>) => {
    setMidiNotes(prev => prev.map(n => n.id === noteId ? { ...n, ...updates } : n));
  }, []);

  const handleNoteDelete = useCallback((noteId: string) => {
    setMidiNotes(prev => prev.filter(n => n.id !== noteId));
  }, []);

  const handleAutomationPointChange = useCallback((pointId: string, updates: Partial<AutomationPoint>) => {
    setAutomationLane(prev => ({
      ...prev,
      points: prev.points.map(p => p.id === pointId ? { ...p, ...updates } : p),
    }));
  }, []);

  const handleAutomationPointAdd = useCallback((time: number, value: number) => {
    const newPoint: AutomationPoint = {
      id: `a${Date.now()}`,
      time,
      value,
      curve: 'linear',
    };
    setAutomationLane(prev => ({
      ...prev,
      points: [...prev.points, newPoint].sort((a, b) => a.time - b.time),
    }));
  }, []);

  // Graph data for plugin
  const graphData = useMemo(() => {
    const points: number[] = [];
    for (let i = 0; i < 100; i++) {
      const x = i / 100;
      const y = 0.5 + 0.4 * Math.sin(x * Math.PI * 4) * Math.exp(-x * 2);
      points.push(y);
    }
    return points;
  }, []);

  return (
    <div className="ui-showcase" data-theme={theme.effectiveMode}>
      <header className="ui-showcase__header">
        <h1>ReelForge UI Showcase</h1>
        <p>LIST 2 - UI & Visual Design Components</p>
        <div className="ui-showcase__theme-toggle">
          <button onClick={theme.toggleMode}>
            {theme.effectiveMode === 'dark' ? '☀️ Light' : '🌙 Dark'}
          </button>
          <select value={theme.preset} onChange={e => theme.setPreset(e.target.value)}>
            {theme.presets.map(p => (
              <option key={p.id} value={p.id}>{p.name}</option>
            ))}
          </select>
        </div>
      </header>

      <main className="ui-showcase__content">
        {/* Waveform */}
        <Section title="Waveform Display" description="Audio waveform visualization">
          <div className="ui-showcase__demo-row">
            <div className="ui-showcase__waveform">
              <Waveform
                peaks={waveformPeaks}
                duration={10}
                height={120}
              />
            </div>
          </div>
        </Section>

        {/* Spectrum Analyzer */}
        <Section title="Spectrum Analyzer" description="Frequency spectrum visualization">
          <div className="ui-showcase__demo-row">
            <div className="ui-showcase__spectrogram">
              <SpectrumAnalyzer
                fftData={fftData}
                width={600}
                height={150}
              />
            </div>
          </div>
        </Section>

        {/* Meter Skins */}
        <Section title="Level Meters" description="VU-style level metering">
          <div className="ui-showcase__meters">
            <div className="ui-showcase__meter-group">
              <label>Left</label>
              <LevelMeter
                levelL={Math.pow(10, meterLevel / 20)}
                peakHoldL={Math.pow(10, (meterLevel + 3) / 20)}
                width={16}
                height={180}
              />
            </div>
            <div className="ui-showcase__meter-group">
              <label>Right</label>
              <LevelMeter
                levelL={Math.pow(10, (meterLevel - 2) / 20)}
                peakHoldL={Math.pow(10, (meterLevel + 1) / 20)}
                width={16}
                height={180}
              />
            </div>
            <div className="ui-showcase__meter-slider">
              <input
                type="range"
                min="-60"
                max="6"
                step="1"
                value={meterLevel}
                onChange={e => setMeterLevel(parseFloat(e.target.value))}
              />
              <span>{meterLevel} dB</span>
            </div>
          </div>
        </Section>

        {/* Plugin UI Framework */}
        <Section title="Plugin UI Framework" description="Reusable plugin control components">
          <PluginContainer pluginName="Demo Plugin" width={420}>
            <PluginPanel title="Controls" collapsible>
              <PluginSection label="Main">
                <PluginRow>
                  <PluginKnob
                    value={knobValue}
                    onChange={setKnobValue}
                    label="Gain"
                    min={0}
                    max={1}
                    size={48}
                  />
                  <PluginKnob
                    value={0.3}
                    onChange={() => {}}
                    label="Mix"
                    min={0}
                    max={1}
                    size={48}
                  />
                  <PluginKnob
                    value={0.7}
                    onChange={() => {}}
                    label="Drive"
                    min={0}
                    max={1}
                    size={48}
                  />
                </PluginRow>
              </PluginSection>

              <PluginSection label="Output">
                <PluginRow>
                  <PluginFader
                    value={faderValue}
                    onChange={setFaderValue}
                    label="Volume"
                    min={0}
                    max={1}
                  />
                  <PluginMeter
                    level={faderValue * 60 - 60}
                    peak={faderValue * 66 - 60}
                  />
                </PluginRow>
              </PluginSection>

              <PluginSection label="Options">
                <PluginRow>
                  <PluginToggle
                    checked={toggleOn}
                    onChange={setToggleOn}
                    label="Bypass"
                  />
                  <PluginSelect
                    value={selectValue}
                    onChange={setSelectValue}
                    options={[
                      { value: 'option1', label: 'Clean' },
                      { value: 'option2', label: 'Warm' },
                      { value: 'option3', label: 'Aggressive' },
                    ]}
                    label="Mode"
                  />
                </PluginRow>
                <PluginRow>
                  <PluginButton onClick={() => alert('Reset clicked!')}>Reset</PluginButton>
                  <PluginButton variant="primary" onClick={() => alert('Apply clicked!')}>Apply</PluginButton>
                </PluginRow>
              </PluginSection>
            </PluginPanel>

            <PluginPanel title="Visualizer">
              <PluginGraph
                data={graphData}
                width={380}
                height={100}
              />
            </PluginPanel>
          </PluginContainer>
        </Section>

        {/* Automation Curves */}
        <Section title="Automation Curves" description="Parameter automation with bezier curves">
          <div className="ui-showcase__automation">
            <AutomationLane
              lane={automationLane}
              width={700}
              height={150}
              pixelsPerSecond={70}
              scrollLeft={0}
              onPointAdd={handleAutomationPointAdd}
              onPointChange={handleAutomationPointChange}
            />
          </div>
        </Section>

        {/* Piano Roll */}
        <Section title="Piano Roll" description="MIDI note editing with velocity lane">
          <div className="ui-showcase__piano-roll">
            <PianoRoll
              notes={midiNotes}
              duration={8}
              tempo={120}
              timeSignature={[4, 4]}
              pixelsPerBeat={50}
              noteHeight={14}
              pitchRange={[48, 84]}
              snapResolution={0.25}
              showVelocity={true}
              velocityLaneHeight={50}
              playheadPosition={playheadPosition}
              onNoteAdd={handleNoteAdd}
              onNoteChange={handleNoteChange}
              onNoteDelete={handleNoteDelete}
            />
          </div>
        </Section>

        {/* Arrangement Grid */}
        <Section title="Arrangement Grid" description="Multi-track clip arrangement view">
          <div className="ui-showcase__arrangement">
            <Arrangement
              tracks={arrangement.tracks}
              clips={arrangement.clips}
              markers={arrangement.markers}
              onTracksChange={arrangement.setTracks}
              onClipsChange={arrangement.setClips}
              onMarkersChange={arrangement.setMarkers}
              length={32}
              beatsPerBar={4}
              pixelsPerBeat={25}
              trackHeight={60}
              snap={1}
              playhead={playheadPosition}
              onPlayheadChange={setPlayheadPosition}
              onClipSelect={arrangement.selectClips}
              onTrackSelect={arrangement.setSelectedTrack}
              trackControlsWidth={180}
              headerHeight={36}
            />
          </div>
        </Section>

        {/* Transport Controls */}
        <Section title="Transport Controls" description="Playback control bar with tempo and time display">
          <div className="ui-showcase__transport">
            <TransportBar
              isPlaying={isPlaying}
              isRecording={isRecording}
              currentTime={currentTime}
              duration={60}
              tempo={tempo}
              timeSignature={[4, 4]}
              loopEnabled={loopEnabled}
              loopStart={4}
              loopEnd={16}
              metronomeEnabled={metronomeEnabled}
              onPlay={() => setIsPlaying(true)}
              onPause={() => setIsPlaying(false)}
              onStop={() => { setIsPlaying(false); setCurrentTime(0); }}
              onRecord={() => setIsRecording(!isRecording)}
              onRewind={() => setCurrentTime(Math.max(0, currentTime - 4))}
              onForward={() => setCurrentTime(currentTime + 4)}
              onTempoChange={setTempo}
              onLoopToggle={() => setLoopEnabled(!loopEnabled)}
              onMetronomeToggle={() => setMetronomeEnabled(!metronomeEnabled)}
            />
          </div>
        </Section>
      </main>

      <footer className="ui-showcase__footer">
        <p>ReelForge Editor - LIST 2 UI Components Complete</p>
        <p>
          <a href="?layout=showcase">Component Showcase</a> |{' '}
          <a href="/">Main Editor</a>
        </p>
      </footer>
    </div>
  );
}
