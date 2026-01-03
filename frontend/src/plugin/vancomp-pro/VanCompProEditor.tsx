/**
 * ReelForge VanComp Pro Editor
 *
 * Professional compressor with GR meter, I/O visualization, and full control.
 * Opens in standalone detached window.
 *
 * @module plugin/vancomp-pro/VanCompProEditor
 */

import { useState, useCallback, useMemo, useRef, useEffect } from 'react';
import { TopBar } from '../pro-suite/TopBar';
import { NumericControl } from '../pro-suite/NumericControl';
import { GRMeter } from './GRMeter';
import { getTheme, themeToCSSVars, type ThemeMode } from '../pro-suite/theme';
import { VANCOMP_PARAM_DESCRIPTORS, VANCOMP_QUALITY_MODES } from './vancompDescriptors';
import '../pro-suite/ProSuite.css';
import './VanCompProEditor.css';

interface VanCompProEditorProps {
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

export function VanCompProEditor({
  params,
  onChange,
  onReset,
  onBypassChange,
  bypassed = false,
  readOnly = false,
}: VanCompProEditorProps) {
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
  const [inputLevel, setInputLevel] = useState(0.3);
  const [outputLevel, setOutputLevel] = useState(0.25);
  const [grAmount, setGRAmount] = useState(0);
  const [grHistory, setGRHistory] = useState<number[]>(new Array(100).fill(0));

  // Container ref for sizing
  const containerRef = useRef<HTMLDivElement>(null);
  const [dimensions, setDimensions] = useState({ width: 800, height: 400 });

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
      // Simulate input with some variation
      const baseInput = 0.3 + Math.random() * 0.4;
      setInputLevel(baseInput);

      // Calculate simulated GR based on threshold and ratio
      const inputDb = 20 * Math.log10(baseInput);
      const threshold = params.threshold ?? -20;
      const ratio = params.ratio ?? 4;

      let gr = 0;
      if (inputDb > threshold) {
        gr = -((inputDb - threshold) * (1 - 1 / ratio));
      }

      setGRAmount(gr);
      setGRHistory(prev => {
        const next = [...prev.slice(1), gr];
        return next;
      });

      // Output level accounts for GR and makeup
      const makeup = params.makeup ?? 0;
      const outputDb = inputDb + gr + makeup;
      setOutputLevel(Math.pow(10, outputDb / 20));
    }, 50);

    return () => clearInterval(interval);
  }, [params.threshold, params.ratio, params.makeup]);

  // Get descriptor by id
  const getDescriptor = useCallback((id: string) => {
    return VANCOMP_PARAM_DESCRIPTORS.find(d => d.id === id);
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

    // Add to history (debounced)
    setHistory(prev => {
      const newEntry = { params: { ...params, [paramId]: value }, timestamp: Date.now() };
      // Remove any future entries if we're in the middle of history
      const truncated = prev.slice(0, historyIndex + 1);
      return [...truncated, newEntry].slice(-50); // Keep last 50 entries
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

    // Apply params from new slot
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

  // Quality mode
  const qualityMode = VANCOMP_QUALITY_MODES[params.quality ?? 1];
  const handleQualityChange = useCallback((mode: string) => {
    const index = VANCOMP_QUALITY_MODES.indexOf(mode as typeof VANCOMP_QUALITY_MODES[number]);
    if (index >= 0) {
      handleParamChange('quality', index);
    }
  }, [handleParamChange]);

  // Bypass toggle
  const handleBypassToggle = useCallback(() => {
    if (onBypassChange) {
      onBypassChange(!bypassed);
    }
  }, [bypassed, onBypassChange]);

  // Auto gain toggle
  const autoGainEnabled = params.autoGain === 1;
  const handleAutoGainToggle = useCallback(() => {
    handleParamChange('autoGain', autoGainEnabled ? 0 : 1);
  }, [autoGainEnabled, handleParamChange]);

  return (
    <div
      className="vp-plugin-container vancomp-pro"
      style={cssVars as React.CSSProperties}
    >
      <TopBar
        pluginName="VanComp Pro"
        abState={abState}
        onABToggle={handleABToggle}
        onABCopy={handleABCopy}
        canUndo={historyIndex > 0}
        canRedo={historyIndex < history.length - 1}
        onUndo={handleUndo}
        onRedo={handleRedo}
        qualityMode={qualityMode}
        qualityOptions={[...VANCOMP_QUALITY_MODES]}
        onQualityChange={handleQualityChange}
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
          className="vp-plugin-visualization vancomp-visualization"
          style={{ backgroundColor: theme.bgGraph }}
        >
          <GRMeter
            threshold={params.threshold ?? -20}
            ratio={params.ratio ?? 4}
            knee={params.knee ?? 6}
            inputLevel={inputLevel}
            outputLevel={outputLevel}
            grAmount={grAmount}
            grHistory={grHistory}
            theme={theme}
            width={dimensions.width}
            height={dimensions.height}
          />
        </div>

        {/* Parameter strip */}
        <div className="vp-param-strip" style={{ backgroundColor: theme.bgPanel }}>
          {/* Compression group */}
          <div className="vp-param-group">
            <span className="vp-param-group-label" style={{ color: theme.textMuted }}>
              COMP
            </span>
            <NumericControl
              value={params.threshold ?? -20}
              min={-60}
              max={0}
              step={0.5}
              fineStep={0.1}
              defaultValue={-20}
              label="Threshold"
              unit=" dB"
              decimals={1}
              onChange={(v) => handleParamChange('threshold', v)}
              onReset={() => handleParamReset('threshold')}
              theme={theme}
              readOnly={readOnly}
              width={70}
            />
            <NumericControl
              value={params.ratio ?? 4}
              min={1}
              max={20}
              step={0.5}
              fineStep={0.1}
              defaultValue={4}
              label="Ratio"
              unit=":1"
              decimals={1}
              onChange={(v) => handleParamChange('ratio', v)}
              onReset={() => handleParamReset('ratio')}
              theme={theme}
              readOnly={readOnly}
              width={55}
            />
            <NumericControl
              value={params.knee ?? 6}
              min={0}
              max={24}
              step={1}
              fineStep={0.5}
              defaultValue={6}
              label="Knee"
              unit=" dB"
              decimals={1}
              onChange={(v) => handleParamChange('knee', v)}
              onReset={() => handleParamReset('knee')}
              theme={theme}
              readOnly={readOnly}
              width={55}
            />
          </div>

          {/* Timing group */}
          <div className="vp-param-group">
            <span className="vp-param-group-label" style={{ color: theme.textMuted }}>
              TIME
            </span>
            <NumericControl
              value={params.attack ?? 10}
              min={0.1}
              max={100}
              step={1}
              fineStep={0.1}
              defaultValue={10}
              label="Attack"
              unit=" ms"
              decimals={1}
              onChange={(v) => handleParamChange('attack', v)}
              onReset={() => handleParamReset('attack')}
              theme={theme}
              readOnly={readOnly}
              width={60}
            />
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
          </div>

          {/* Output group */}
          <div className="vp-param-group">
            <span className="vp-param-group-label" style={{ color: theme.textMuted }}>
              OUT
            </span>
            <NumericControl
              value={params.makeup ?? 0}
              min={-12}
              max={24}
              step={0.5}
              fineStep={0.1}
              defaultValue={0}
              label="Makeup"
              unit=" dB"
              decimals={1}
              onChange={(v) => handleParamChange('makeup', v)}
              onReset={() => handleParamReset('makeup')}
              theme={theme}
              readOnly={readOnly}
              width={60}
            />
            <NumericControl
              value={params.mix ?? 100}
              min={0}
              max={100}
              step={5}
              fineStep={1}
              defaultValue={100}
              label="Mix"
              unit="%"
              decimals={0}
              onChange={(v) => handleParamChange('mix', v)}
              onReset={() => handleParamReset('mix')}
              theme={theme}
              readOnly={readOnly}
              width={50}
            />
          </div>

          {/* Sidechain group */}
          <div className="vp-param-group">
            <span className="vp-param-group-label" style={{ color: theme.textMuted }}>
              SC
            </span>
            <NumericControl
              value={params.scHpf ?? 20}
              min={20}
              max={500}
              step={10}
              fineStep={1}
              defaultValue={20}
              label="HPF"
              unit=" Hz"
              decimals={0}
              onChange={(v) => handleParamChange('scHpf', v)}
              onReset={() => handleParamReset('scHpf')}
              theme={theme}
              readOnly={readOnly}
              width={55}
            />
            <div
              className="vp-toggle"
              onClick={handleAutoGainToggle}
              style={{ opacity: readOnly ? 0.5 : 1 }}
            >
              <span className="vp-toggle-label" style={{ color: theme.textSecondary }}>
                Auto
              </span>
              <div className={`vp-toggle-switch ${autoGainEnabled ? 'active' : ''}`} />
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
