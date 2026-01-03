/**
 * ReelForge VanLimit Pro Editor
 *
 * Professional limiter with waveform history, GR visualization, and output metering.
 * Opens in standalone detached window.
 *
 * @module plugin/vanlimit-pro/VanLimitProEditor
 */

import { useState, useCallback, useMemo, useRef, useEffect } from 'react';
import { TopBar } from '../pro-suite/TopBar';
import { NumericControl } from '../pro-suite/NumericControl';
import { WaveformMeter } from './WaveformMeter';
import { getTheme, themeToCSSVars, type ThemeMode } from '../pro-suite/theme';
import { VANLIMIT_PARAM_DESCRIPTORS, VANLIMIT_MODES, VANLIMIT_OVERSAMPLING } from './vanlimitDescriptors';
import '../pro-suite/ProSuite.css';
import './VanLimitProEditor.css';

interface VanLimitProEditorProps {
  params: Record<string, number>;
  onChange: (paramId: string, value: number) => void;
  onReset?: (paramId: string) => void;
  onBypassChange?: (bypassed: boolean) => void;
  bypassed?: boolean;
  readOnly?: boolean;
}

// History for A/B comparison
interface ABState {
  A: Record<string, number>;
  B: Record<string, number>;
}

// Undo history
interface HistoryEntry {
  params: Record<string, number>;
  timestamp: number;
}

// History buffer size
const HISTORY_SIZE = 200;

export function VanLimitProEditor({
  params,
  onChange,
  onReset,
  onBypassChange,
  bypassed = false,
  readOnly = false,
}: VanLimitProEditorProps) {
  // Theme state
  const [themeMode, setThemeMode] = useState<ThemeMode>('auto');
  const theme = useMemo(() => getTheme(themeMode), [themeMode]);
  const cssVars = useMemo(() => themeToCSSVars(theme), [theme]);

  // A/B comparison state
  const [abState, setABState] = useState<'A' | 'B'>('A');
  const [abParams, setABParams] = useState<ABState>({ A: { ...params }, B: { ...params } });

  // Undo/Redo state
  const [history, setHistory] = useState<HistoryEntry[]>([{ params: { ...params }, timestamp: Date.now() }]);
  const [historyIndex, setHistoryIndex] = useState(0);

  // Simulated metering (would come from DSP in real implementation)
  const [inputHistory, setInputHistory] = useState<number[]>(new Array(HISTORY_SIZE).fill(0.1));
  const [outputHistory, setOutputHistory] = useState<number[]>(new Array(HISTORY_SIZE).fill(0.1));
  const [grHistory, setGRHistory] = useState<number[]>(new Array(HISTORY_SIZE).fill(0));
  const [currentGR, setCurrentGR] = useState(0);
  const [outputLevel, setOutputLevel] = useState(0.5);

  // Container ref for sizing
  const containerRef = useRef<HTMLDivElement>(null);
  const [dimensions, setDimensions] = useState({ width: 800, height: 350 });

  // Update dimensions on resize
  useEffect(() => {
    const updateDimensions = () => {
      if (containerRef.current) {
        const rect = containerRef.current.getBoundingClientRect();
        setDimensions({ width: rect.width, height: rect.height });
      }
    };

    updateDimensions();
    window.addEventListener('resize', updateDimensions);
    return () => window.removeEventListener('resize', updateDimensions);
  }, []);

  // Simulate metering (in real app, this would come from AudioWorklet)
  useEffect(() => {
    const interval = setInterval(() => {
      // Simulate input with musical dynamics
      const time = Date.now() / 1000;
      const baseInput = 0.4 + 0.3 * Math.sin(time * 0.5) + Math.random() * 0.2;
      const inputLevel = Math.max(0.05, Math.min(1, baseInput));

      setInputHistory(prev => [...prev.slice(1), inputLevel]);

      // Calculate limiting based on threshold and ceiling
      const inputDb = 20 * Math.log10(inputLevel);
      const threshold = params.threshold ?? -6;
      const ceiling = params.ceiling ?? -0.3;

      let gr = 0;
      if (inputDb > threshold) {
        // Limiting - hard knee
        gr = threshold - inputDb;
      }

      // Apply ceiling
      const outputDb = Math.min(ceiling, inputDb + gr);
      const output = Math.pow(10, outputDb / 20);

      setCurrentGR(gr);
      setGRHistory(prev => [...prev.slice(1), gr]);
      setOutputLevel(output);
      setOutputHistory(prev => [...prev.slice(1), output]);
    }, 30);

    return () => clearInterval(interval);
  }, [params.threshold, params.ceiling]);

  // Get descriptor by id
  const getDescriptor = useCallback((id: string) => {
    return VANLIMIT_PARAM_DESCRIPTORS.find(d => d.id === id);
  }, []);

  // Handle param change with history
  const handleParamChange = useCallback((paramId: string, value: number) => {
    if (readOnly) return;

    // Update current A/B slot
    setABParams(prev => ({
      ...prev,
      [abState]: { ...prev[abState], [paramId]: value },
    }));

    // Call external onChange
    onChange(paramId, value);

    // Add to history
    setHistory(prev => {
      const newEntry = { params: { ...params, [paramId]: value }, timestamp: Date.now() };
      const truncated = prev.slice(0, historyIndex + 1);
      return [...truncated, newEntry].slice(-50);
    });
    setHistoryIndex(prev => prev + 1);
  }, [readOnly, abState, onChange, params, historyIndex]);

  // Handle param reset
  const handleParamReset = useCallback((paramId: string) => {
    if (readOnly) return;
    if (onReset) {
      onReset(paramId);
    } else {
      const desc = getDescriptor(paramId);
      if (desc) {
        handleParamChange(paramId, desc.default);
      }
    }
  }, [readOnly, onReset, getDescriptor, handleParamChange]);

  // A/B toggle
  const handleABToggle = useCallback(() => {
    const newState = abState === 'A' ? 'B' : 'A';
    setABState(newState);

    const newParams = abParams[newState];
    Object.entries(newParams).forEach(([id, value]) => {
      if (params[id] !== value) {
        onChange(id, value);
      }
    });
  }, [abState, abParams, params, onChange]);

  // A/B copy
  const handleABCopy = useCallback(() => {
    setABParams(prev => ({
      ...prev,
      [abState === 'A' ? 'B' : 'A']: { ...prev[abState] },
    }));
  }, [abState]);

  // Undo
  const handleUndo = useCallback(() => {
    if (historyIndex > 0) {
      const newIndex = historyIndex - 1;
      setHistoryIndex(newIndex);
      const entry = history[newIndex];
      Object.entries(entry.params).forEach(([id, value]) => {
        onChange(id, value);
      });
    }
  }, [historyIndex, history, onChange]);

  // Redo
  const handleRedo = useCallback(() => {
    if (historyIndex < history.length - 1) {
      const newIndex = historyIndex + 1;
      setHistoryIndex(newIndex);
      const entry = history[newIndex];
      Object.entries(entry.params).forEach(([id, value]) => {
        onChange(id, value);
      });
    }
  }, [historyIndex, history, onChange]);

  // Mode
  const currentMode = VANLIMIT_MODES[params.mode ?? 1];
  const handleModeChange = useCallback((mode: string) => {
    const index = VANLIMIT_MODES.indexOf(mode as typeof VANLIMIT_MODES[number]);
    if (index >= 0) {
      handleParamChange('mode', index);
    }
  }, [handleParamChange]);

  // Oversampling
  const currentOS = VANLIMIT_OVERSAMPLING[params.oversampling ?? 1];
  const handleOSChange = useCallback((os: string) => {
    const index = VANLIMIT_OVERSAMPLING.indexOf(os as typeof VANLIMIT_OVERSAMPLING[number]);
    if (index >= 0) {
      handleParamChange('oversampling', index);
    }
  }, [handleParamChange]);

  // Bypass toggle
  const handleBypassToggle = useCallback(() => {
    if (onBypassChange) {
      onBypassChange(!bypassed);
    }
  }, [bypassed, onBypassChange]);

  // True peak toggle
  const truePeakEnabled = params.truePeak === 1;
  const handleTruePeakToggle = useCallback(() => {
    handleParamChange('truePeak', truePeakEnabled ? 0 : 1);
  }, [truePeakEnabled, handleParamChange]);

  return (
    <div
      className="vp-plugin-container vanlimit-pro"
      style={cssVars as React.CSSProperties}
    >
      <TopBar
        pluginName="VanLimit Pro"
        abState={abState}
        onABToggle={handleABToggle}
        onABCopy={handleABCopy}
        canUndo={historyIndex > 0}
        canRedo={historyIndex < history.length - 1}
        onUndo={handleUndo}
        onRedo={handleRedo}
        qualityMode={currentMode}
        qualityOptions={[...VANLIMIT_MODES]}
        onQualityChange={handleModeChange}
        themeMode={themeMode}
        onThemeModeChange={setThemeMode}
        bypassed={bypassed}
        onBypassToggle={handleBypassToggle}
        theme={theme}
        readOnly={readOnly}
      />

      <div className="vp-plugin-main" style={{ backgroundColor: theme.bgPrimary }}>
        {/* Central visualization */}
        <div
          ref={containerRef}
          className="vp-plugin-visualization vanlimit-visualization"
          style={{ backgroundColor: theme.bgGraph }}
        >
          <WaveformMeter
            ceiling={params.ceiling ?? -0.3}
            threshold={params.threshold ?? -6}
            inputHistory={inputHistory}
            outputHistory={outputHistory}
            grHistory={grHistory}
            currentGR={currentGR}
            outputLevel={outputLevel}
            truePeak={truePeakEnabled}
            theme={theme}
            width={dimensions.width}
            height={dimensions.height}
          />
        </div>

        {/* Parameter strip */}
        <div className="vp-param-strip" style={{ backgroundColor: theme.bgPanel }}>
          {/* Main limiting group */}
          <div className="vp-param-group">
            <span className="vp-param-group-label" style={{ color: theme.textMuted }}>
              LIMIT
            </span>
            <NumericControl
              value={params.ceiling ?? -0.3}
              min={-12}
              max={0}
              step={0.1}
              fineStep={0.01}
              defaultValue={-0.3}
              label="Ceiling"
              unit=" dB"
              decimals={1}
              onChange={(v) => handleParamChange('ceiling', v)}
              onReset={() => handleParamReset('ceiling')}
              theme={theme}
              readOnly={readOnly}
              width={65}
            />
            <NumericControl
              value={params.threshold ?? -6}
              min={-24}
              max={0}
              step={0.5}
              fineStep={0.1}
              defaultValue={-6}
              label="Threshold"
              unit=" dB"
              decimals={1}
              onChange={(v) => handleParamChange('threshold', v)}
              onReset={() => handleParamReset('threshold')}
              theme={theme}
              readOnly={readOnly}
              width={70}
            />
          </div>

          {/* Timing group */}
          <div className="vp-param-group">
            <span className="vp-param-group-label" style={{ color: theme.textMuted }}>
              TIME
            </span>
            <NumericControl
              value={params.release ?? 100}
              min={10}
              max={1000}
              step={10}
              fineStep={1}
              defaultValue={100}
              label="Release"
              unit=" ms"
              decimals={0}
              onChange={(v) => handleParamChange('release', v)}
              onReset={() => handleParamReset('release')}
              theme={theme}
              readOnly={readOnly}
              width={60}
            />
            <NumericControl
              value={params.lookahead ?? 3}
              min={0}
              max={10}
              step={0.5}
              fineStep={0.1}
              defaultValue={3}
              label="Lookahead"
              unit=" ms"
              decimals={1}
              onChange={(v) => handleParamChange('lookahead', v)}
              onReset={() => handleParamReset('lookahead')}
              theme={theme}
              readOnly={readOnly}
              width={70}
            />
          </div>

          {/* Options group */}
          <div className="vp-param-group">
            <span className="vp-param-group-label" style={{ color: theme.textMuted }}>
              OPT
            </span>
            <div className="vp-option-select">
              <label style={{ color: theme.textMuted }}>OS</label>
              <select
                value={currentOS}
                onChange={(e) => handleOSChange(e.target.value)}
                disabled={readOnly}
                style={{
                  backgroundColor: theme.inputBg,
                  color: theme.textPrimary,
                  borderColor: theme.inputBorder,
                }}
              >
                {VANLIMIT_OVERSAMPLING.map((opt) => (
                  <option key={opt} value={opt}>{opt}</option>
                ))}
              </select>
            </div>
            <NumericControl
              value={params.stereoLink ?? 100}
              min={0}
              max={100}
              step={10}
              fineStep={1}
              defaultValue={100}
              label="Link"
              unit="%"
              decimals={0}
              onChange={(v) => handleParamChange('stereoLink', v)}
              onReset={() => handleParamReset('stereoLink')}
              theme={theme}
              readOnly={readOnly}
              width={50}
            />
            <div
              className="vp-toggle"
              onClick={handleTruePeakToggle}
              style={{ opacity: readOnly ? 0.5 : 1 }}
            >
              <span className="vp-toggle-label" style={{ color: theme.textSecondary }}>
                TP
              </span>
              <div className={`vp-toggle-switch ${truePeakEnabled ? 'active' : ''}`} />
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
