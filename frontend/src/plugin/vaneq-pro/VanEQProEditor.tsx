/**
 * VanEQ Pro - WOW Edition
 * Connected to real audio pipeline
 */

import { useState, useRef, useEffect, useCallback, useMemo } from 'react';
import gsap from 'gsap';
import { SpectrumWebGL } from './SpectrumWebGL';
import { EQCurveWebGL } from './EQCurveWebGL';
import './VanEQProEditor.css';

// ============ Types ============

type FilterType = 'highpass' | 'lowshelf' | 'bell' | 'highshelf' | 'lowpass' | 'notch' | 'bandpass' | 'tilt';

interface Band {
  id: number;
  freq: number;
  gain: number;
  q: number;
  type: FilterType;
  active: boolean;
}

type EQMode = 'minimum' | 'linear' | 'dynamic' | 'match';

interface SpectrumData {
  fftDb: Float32Array | number[];
  sampleRate: number;
}

interface Props {
  params?: Record<string, number>;
  bypassed?: boolean;
  onChange?: (paramId: string, value: number) => void;
  onChangeBatch?: (changes: Record<string, number>) => void;
  spectrumData?: SpectrumData | null;
  onDragStart?: () => void;
  onDragEnd?: () => void;
}

// ============ Constants ============

const CONFIG = {
  freqMin: 20,
  freqMax: 20000,
  dbRange: 48,
  fftSize: 2048,
};

const MARGIN = { left: 50, right: 24, top: 30, bottom: 30 };

const BAND_COLORS = [
  'var(--band-1)', 'var(--band-2)', 'var(--band-3)', 'var(--band-4)',
  'var(--band-5)', 'var(--band-6)', 'var(--band-7)', 'var(--band-8)',
];

// Resolved band colors for canvas drawing (CSS vars not available in canvas)
// Used by band nodes via inline style when needed - FabFilter Pro-Q4 palette
const BAND_COLORS_HEX: string[] = [
  '#ff6b6b', '#ffa94d', '#ffd43b', '#69db7c',
  '#4dabf7', '#9775fa', '#f783ac', '#66d9e8',
];

// Window size presets (FabFilter Pro-Q style dimensions)
type WindowSize = 'S' | 'M' | 'L';
const WINDOW_SIZES: Record<WindowSize, { w: number; h: number; label: string }> = {
  S: { w: 1000, h: 620, label: 'Small' },
  M: { w: 1250, h: 760, label: 'Medium' },
  L: { w: 1550, h: 950, label: 'Large' },
};

// Map from flat param type index to our FilterType
const TYPE_INDEX_TO_FILTER: FilterType[] = [
  'bell',       // 0
  'lowshelf',   // 1
  'highshelf',  // 2
  'lowpass',    // 3
  'highpass',   // 4
  'notch',      // 5
  'bandpass',   // 6
  'tilt',       // 7
];

// Reverse map
const FILTER_TO_TYPE_INDEX: Record<FilterType, number> = {
  bell: 0,
  lowshelf: 1,
  highshelf: 2,
  lowpass: 3,
  highpass: 4,
  notch: 5,
  bandpass: 6,
  tilt: 7,
};

const FILTER_TYPES: { id: FilterType; label: string; path: string }[] = [
  { id: 'highpass', label: 'High Pass', path: 'M2 12h4l4-10h12' },
  { id: 'lowshelf', label: 'Low Shelf', path: 'M2 10h6l4-6h10' },
  { id: 'bell', label: 'Bell', path: 'M2 10h4l3-6 6 0 3 6h4' },
  { id: 'highshelf', label: 'High Shelf', path: 'M2 4h10l4 6h6' },
  { id: 'lowpass', label: 'Low Pass', path: 'M2 2h12l4 10h4' },
];

// ============ Utility Functions ============

function xToFreq(x: number, width: number): number {
  const w = width - MARGIN.left - MARGIN.right;
  const logMin = Math.log10(CONFIG.freqMin);
  const logMax = Math.log10(CONFIG.freqMax);
  const t = (x - MARGIN.left) / w;
  return Math.pow(10, logMin + t * (logMax - logMin));
}

function yToGain(y: number, height: number, dbRange: number = CONFIG.dbRange): number {
  const h = height - MARGIN.top - MARGIN.bottom;
  const fullRange = dbRange * 2;
  return (1 - (y - MARGIN.top) / h) * fullRange - dbRange;
}

function formatFreq(freq: number): string {
  if (freq >= 1000) return (freq / 1000).toFixed(freq >= 10000 ? 0 : 1) + ' kHz';
  return Math.round(freq) + ' Hz';
}

// Format dB value: no sign for 0, + for positive, - for negative
function formatDb(value: number, decimals: number = 1): string {
  const rounded = Number(value.toFixed(decimals));
  if (rounded === 0) return '0.0';
  return rounded > 0 ? `+${rounded.toFixed(decimals)}` : rounded.toFixed(decimals);
}

// Parse frequency input (supports "1k", "1.5k", "1000", "1 kHz", etc.)
function parseFreqInput(input: string): number | null {
  const cleaned = input.toLowerCase().trim().replace(/\s+/g, '').replace('hz', '');
  const kMatch = cleaned.match(/^([\d.]+)k$/);
  if (kMatch) {
    const val = parseFloat(kMatch[1]) * 1000;
    return isNaN(val) ? null : val;
  }
  const val = parseFloat(cleaned);
  return isNaN(val) ? null : val;
}

function valueToArcDeg(value: number, min: number, max: number): number {
  const t = (value - min) / (max - min);
  return t * 270;
}

function valueToRotation(value: number, min: number, max: number): number {
  const t = (value - min) / (max - min);
  return -135 + t * 270;
}

// Convert flat params to Band array
function paramsToBands(params: Record<string, number> | undefined): Band[] {
  const bands: Band[] = [];
  for (let i = 0; i < 8; i++) {
    const enabled = params?.[`band${i}_enabled`] === 1;
    const typeIndex = params?.[`band${i}_type`] ?? 0;
    const freq = params?.[`band${i}_freqHz`] ?? 1000;
    const gain = params?.[`band${i}_gainDb`] ?? 0;
    const q = params?.[`band${i}_q`] ?? 1;

    bands.push({
      id: i + 1,
      freq,
      gain,
      q,
      type: TYPE_INDEX_TO_FILTER[typeIndex] || 'bell',
      active: enabled,
    });
  }
  return bands;
}

// ============ Component ============

export default function VanEQProEditor({
  params,
  bypassed = false,
  onChange,
  onChangeBatch,
  spectrumData,
  onDragStart,
  onDragEnd,
}: Props) {
  // Convert params to bands
  const bands = useMemo(() => paramsToBands(params), [params]);

  // UI State (not synced to host)
  const [selectedBand, setSelectedBand] = useState(1);
  const [eqMode, setEqMode] = useState<EQMode>('minimum');
  const [abState, setAbState] = useState<'A' | 'B'>('A');
  const [analyzerOn, setAnalyzerOn] = useState(true);
  // Quality state removed - replaced by dB range zoom
  const [outputGain, setOutputGain] = useState(0);
  const [soloedBand, setSoloedBand] = useState<number | null>(null);
  const [autoGain, setAutoGain] = useState(false);

  // dB range zoom - selected value shows double range (3→±6, 6→±12, 12→±24)
  type DbZoom = 3 | 6 | 12;
  const [dbZoom, setDbZoom] = useState<DbZoom>(12);
  // Actual display range is double the zoom value
  const dbRange = dbZoom * 2; // 3→6, 6→12, 12→24

  // Window size state (S/M/L) - persisted to localStorage
  const [windowSize, setWindowSize] = useState<WindowSize>(() => {
    try {
      const stored = localStorage.getItem('vaneq_size');
      if (stored === 'S' || stored === 'M' || stored === 'L') return stored;
    } catch { /* ignore */ }
    return 'M';
  });

  // Per-band channel mode (FabFilter style: Stereo/Left/Right/Mid/Side)
  type ChannelMode = 'stereo' | 'left' | 'right' | 'mid' | 'side';
  const [bandChannels, setBandChannels] = useState<ChannelMode[]>(
    Array(8).fill('stereo')
  );

  // Pre-auto-gain output value (to restore when turning off auto gain)
  const preAutoGainOutputRef = useRef<number>(0);

  // Knob edit state (for double-click manual input)
  // null = not editing, otherwise { param, target }
  type EditTarget = 'freq' | 'gain' | 'q';
  const [editingKnob, setEditingKnob] = useState<EditTarget | null>(null);
  const [knobInputValue, setKnobInputValue] = useState('');
  const knobInputRef = useRef<HTMLInputElement>(null);

  // A/B state storage (for copy/swap)
  const abStorageRef = useRef<{ A: Record<string, number>; B: Record<string, number> }>({
    A: {},
    B: {},
  });

  // Container dimensions for WebGL components
  const [containerSize, setContainerSize] = useState({ width: 0, height: 0 });

  // Refs
  const containerRef = useRef<HTMLDivElement>(null);

  // Throttle ref for drag updates (prevents flooding DSP with too many param changes)
  const pendingDragChangesRef = useRef<Record<string, number> | null>(null);
  const dragRafRef = useRef<number>(0);

  // Get active band
  const activeBand = bands.find(b => b.id === selectedBand) || bands[0];

  // Off state (power button) - separate from bypass
  // Off = plugin completely disabled, UI non-interactive
  // Bypass = audio bypassed but UI still interactive
  const [isOff, setIsOff] = useState(false);
  const isPluginOn = !isOff;

  // ============ Send param changes to host ============

  const sendParam = useCallback((paramId: string, value: number) => {
    onChange?.(paramId, value);
  }, [onChange]);

  const sendBatch = useCallback((changes: Record<string, number>) => {
    if (onChangeBatch) {
      onChangeBatch(changes);
    } else if (onChange) {
      // Fallback to individual calls
      for (const [key, val] of Object.entries(changes)) {
        onChange(key, val);
      }
    }
  }, [onChange, onChangeBatch]);

  // Throttled sendBatch for smooth dragging (RAF-based, ~60fps max)
  // Accumulates changes and sends once per frame
  const sendBatchThrottled = useCallback((changes: Record<string, number>) => {
    // Merge with pending changes
    pendingDragChangesRef.current = {
      ...pendingDragChangesRef.current,
      ...changes,
    };

    // If we already have a RAF scheduled, let it handle the send
    if (dragRafRef.current) return;

    // Schedule send on next frame
    dragRafRef.current = requestAnimationFrame(() => {
      dragRafRef.current = 0;
      if (pendingDragChangesRef.current) {
        sendBatch(pendingDragChangesRef.current);
        pendingDragChangesRef.current = null;
      }
    });
  }, [sendBatch]);

  // Read outputGain from params (only when autoGain is OFF)
  useEffect(() => {
    if (!autoGain && params?.outputGainDb !== undefined) {
      setOutputGain(params.outputGainDb);
    }
  }, [params?.outputGainDb, autoGain]);

  // Real-time auto gain compensation - updates output gain as bands change
  // Uses weighted average based on filter type and bandwidth for smoother compensation
  useEffect(() => {
    if (!autoGain) return;

    const activeBands = bands.filter(b => b.active);
    if (activeBands.length === 0) {
      // No active bands - output should be 0
      const newOutput = 0;
      if (Math.abs(outputGain - newOutput) > 0.01) {
        setOutputGain(newOutput);
        sendParam('outputGainDb', newOutput);
      }
      return;
    }

    // Calculate weighted gain compensation
    // Shelves affect more spectrum so they get higher weight
    // Bells with wider Q affect more spectrum
    let totalWeight = 0;
    let weightedGainSum = 0;

    for (const band of activeBands) {
      let weight = 1;

      // Shelf filters affect more of the spectrum
      if (band.type === 'lowshelf' || band.type === 'highshelf') {
        weight = 2.0;
      } else if (band.type === 'tilt') {
        weight = 1.5;
      } else if (band.type === 'bell' || band.type === 'notch') {
        // Lower Q = wider band = more impact
        weight = Math.max(0.5, 2.0 / Math.max(0.5, band.q));
      } else if (band.type === 'highpass' || band.type === 'lowpass' || band.type === 'bandpass') {
        weight = 0.3; // Cuts don't add gain, less compensation needed
      }

      weightedGainSum += band.gain * weight;
      totalWeight += weight;
    }

    // Calculate compensation (inverted, smoothed)
    const avgWeightedGain = totalWeight > 0 ? weightedGainSum / totalWeight : 0;
    // Compensate for ~60% of the average weighted gain
    const compensation = -avgWeightedGain * 0.6;
    const newOutput = Math.max(-24, Math.min(24, Math.round(compensation * 10) / 10));

    // Only update if changed significantly (avoid micro-updates)
    if (Math.abs(outputGain - newOutput) > 0.05) {
      setOutputGain(newOutput);
      sendParam('outputGainDb', newOutput);
    }
  }, [autoGain, bands, outputGain, sendParam]);

  // Track container size for WebGL components
  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;

    const updateSize = () => {
      const rect = container.getBoundingClientRect();
      setContainerSize({ width: rect.width, height: rect.height });
    };

    updateSize();
    const observer = new ResizeObserver(updateSize);
    observer.observe(container);

    return () => observer.disconnect();
  }, []);

  // ============ Handlers ============

  const handleBandDrag = useCallback((bandId: number, e: React.MouseEvent) => {
    const container = containerRef.current;
    if (!container) return;

    e.preventDefault();
    setSelectedBand(bandId);
    onDragStart?.();

    // GSAP press animation
    const bandNode = (e.currentTarget as HTMLElement);
    gsap.to(bandNode, { scale: 0.9, duration: 0.08, ease: 'power2.in' });

    const rect = container.getBoundingClientRect();
    const bandIndex = bandId - 1;
    const startX = e.clientX;
    const startY = e.clientY;
    const band = bands.find(b => b.id === bandId);
    const startFreq = band?.freq ?? 1000;
    const startGain = band?.gain ?? 0;

    const currentDbRange = dbRange; // Capture for closure

    // Track whether we've moved enough to trigger changes
    // This prevents accidental resets when Shift+clicking without moving
    let hasMoved = false;
    const MOVE_THRESHOLD = 3; // pixels - must move at least this far to trigger changes

    const onMove = (moveEvent: MouseEvent) => {
      const rawDeltaX = moveEvent.clientX - startX;
      const rawDeltaY = moveEvent.clientY - startY;

      // Check if we've moved past the threshold
      if (!hasMoved) {
        const distance = Math.sqrt(rawDeltaX * rawDeltaX + rawDeltaY * rawDeltaY);
        if (distance < MOVE_THRESHOLD) {
          return; // Don't apply changes until we've moved enough
        }
        hasMoved = true;
      }

      // Fine tuning with Shift key
      if (moveEvent.shiftKey) {
        // Fine mode: relative movement from start position (10x more precise)
        const deltaX = rawDeltaX * 0.1;
        const deltaY = rawDeltaY * 0.1;

        const freqRange = Math.log10(CONFIG.freqMax) - Math.log10(CONFIG.freqMin);
        const freqDelta = (deltaX / rect.width) * freqRange;
        const newFreqLog = Math.log10(startFreq) + freqDelta;
        const newFreq = Math.max(CONFIG.freqMin, Math.min(CONFIG.freqMax, Math.pow(10, newFreqLog)));

        const gainDelta = (-deltaY / rect.height) * (currentDbRange * 2);
        const newGain = Math.max(-currentDbRange, Math.min(currentDbRange, startGain + gainDelta));

        // Use throttled send for smooth dragging (RAF-limited)
        sendBatchThrottled({
          [`band${bandIndex}_freqHz`]: newFreq,
          [`band${bandIndex}_gainDb`]: newGain,
          [`band${bandIndex}_enabled`]: 1,
        });
      } else {
        // Normal mode: absolute position
        const x = moveEvent.clientX - rect.left;
        const y = moveEvent.clientY - rect.top;

        const newFreq = Math.max(CONFIG.freqMin, Math.min(CONFIG.freqMax, xToFreq(x, rect.width)));
        const newGain = Math.max(-currentDbRange, Math.min(currentDbRange, yToGain(y, rect.height, currentDbRange)));

        // Use throttled send for smooth dragging (RAF-limited)
        sendBatchThrottled({
          [`band${bandIndex}_freqHz`]: newFreq,
          [`band${bandIndex}_gainDb`]: newGain,
          [`band${bandIndex}_enabled`]: 1,
        });
      }
    };

    const onUp = () => {
      document.removeEventListener('mousemove', onMove);
      document.removeEventListener('mouseup', onUp);
      // GSAP release animation with elastic bounce
      gsap.to(bandNode, { scale: 1, duration: 0.4, ease: 'elastic.out(1.2, 0.4)' });
      onDragEnd?.();
    };

    document.addEventListener('mousemove', onMove);
    document.addEventListener('mouseup', onUp);
  }, [bands, sendBatchThrottled, onDragStart, onDragEnd, dbRange]);

  const handleKnobDrag = useCallback((
    param: 'freq' | 'gain' | 'q',
    min: number,
    max: number,
    e: React.MouseEvent
  ) => {
    e.preventDefault();
    const startY = e.clientY;
    const startValue = activeBand[param];
    const bandIndex = selectedBand - 1;
    const knobContainer = (e.currentTarget as HTMLElement);

    // GSAP knob glow on drag start
    const knobInner = knobContainer.querySelector('.knob-inner') as HTMLElement;
    if (knobInner) {
      gsap.to(knobInner, {
        boxShadow: '0 0 25px rgba(0, 212, 255, 0.6), inset 0 -3px 10px rgba(0, 0, 0, 0.4)',
        duration: 0.15,
        ease: 'power2.out',
      });
    }

    onDragStart?.();

    const onMove = (moveEvent: MouseEvent) => {
      const deltaY = startY - moveEvent.clientY;
      const range = max - min;
      // Fine tuning with Shift key (10x more precise)
      // Freq knob is much slower (0.001 base) because of wide logarithmic range
      const baseSensitivity = param === 'freq' ? 0.001 : 0.005;
      const sensitivity = moveEvent.shiftKey ? baseSensitivity * 0.1 : baseSensitivity;
      let newValue = startValue + deltaY * range * sensitivity;
      newValue = Math.max(min, Math.min(max, newValue));

      // Map to param key
      const paramKey = param === 'freq' ? `band${bandIndex}_freqHz` :
                       param === 'gain' ? `band${bandIndex}_gainDb` :
                       `band${bandIndex}_q`;

      sendParam(paramKey, newValue);
    };

    const onUp = () => {
      document.removeEventListener('mousemove', onMove);
      document.removeEventListener('mouseup', onUp);
      // GSAP knob glow reset
      if (knobInner) {
        gsap.to(knobInner, {
          boxShadow: '0 0 12px rgba(0, 212, 255, 0.2), inset 0 -3px 10px rgba(0, 0, 0, 0.4)',
          duration: 0.3,
          ease: 'power2.out',
        });
      }
      onDragEnd?.();
    };

    document.addEventListener('mousemove', onMove);
    document.addEventListener('mouseup', onUp);
  }, [activeBand, selectedBand, sendParam, onDragStart, onDragEnd]);

  const handleFilterTypeChange = useCallback((type: FilterType) => {
    const bandIndex = selectedBand - 1;
    sendBatch({
      [`band${bandIndex}_type`]: FILTER_TO_TYPE_INDEX[type],
      [`band${bandIndex}_enabled`]: 1,
    });
  }, [selectedBand, sendBatch]);

  // Bypass toggle - audio bypassed but UI still interactive (FabFilter style)
  const handleBypassToggle = useCallback(() => {
    // Send bypass as a special batch with __bypass__ marker
    // This is handled by PluginWindowApp.handleVanEQBatch
    sendBatch({ '__bypass__': bypassed ? 0 : 1 });
  }, [bypassed, sendBatch]);

  // Off toggle (power button) - plugin completely disabled, UI non-interactive
  const handleOffToggle = useCallback(() => {
    const newOff = !isOff;
    setIsOff(newOff);
    // When turning off, also bypass the audio
    // When turning on, restore previous bypass state (we just un-bypass for now)
    sendBatch({ '__bypass__': newOff ? 1 : 0 });
  }, [isOff, sendBatch]);

  const handleOutputChange = useCallback((value: number) => {
    setOutputGain(value);
    sendParam('outputGainDb', value);
  }, [sendParam]);

  // Output slider drag - with fine tuning (Shift key)
  const handleOutputSliderDrag = useCallback((e: React.MouseEvent<HTMLDivElement>) => {
    e.preventDefault();
    onDragStart?.();
    const sliderEl = e.currentTarget;
    const rect = sliderEl.getBoundingClientRect();
    const startX = e.clientX;
    const startValue = outputGain;

    const updateValue = (clientX: number, shiftKey: boolean) => {
      if (shiftKey) {
        // Fine mode: relative movement from start position (10x more precise)
        const deltaX = clientX - startX;
        const deltaValue = (deltaX / rect.width) * 48 * 0.1; // 10% sensitivity
        const value = Math.max(-24, Math.min(24, startValue + deltaValue));
        handleOutputChange(Math.round(value * 10) / 10);
      } else {
        // Normal mode: absolute position
        const t = Math.max(0, Math.min(1, (clientX - rect.left) / rect.width));
        const value = -24 + t * 48; // -24 to +24
        handleOutputChange(Math.round(value * 10) / 10);
      }
    };

    updateValue(e.clientX, e.shiftKey);

    const onMove = (ev: MouseEvent) => updateValue(ev.clientX, ev.shiftKey);
    const onUp = () => {
      window.removeEventListener('mousemove', onMove);
      window.removeEventListener('mouseup', onUp);
      onDragEnd?.();
    };

    window.addEventListener('mousemove', onMove);
    window.addEventListener('mouseup', onUp);
  }, [handleOutputChange, outputGain, onDragStart, onDragEnd]);

  // Band enable/disable (double click)
  const handleBandToggle = useCallback((bandId: number) => {
    const band = bands.find(b => b.id === bandId);
    if (!band) return;
    const paramKey = `band${bandId - 1}_enabled`;
    sendParam(paramKey, band.active ? 0 : 1);
  }, [bands, sendParam]);

  // Scroll to change Q value on band node
  // Shift = fine tuning (0.01 step), normal = 0.1 step
  const handleBandScroll = useCallback((bandId: number, e: React.WheelEvent) => {
    e.preventDefault();
    const band = bands.find(b => b.id === bandId);
    if (!band) return;

    // Fine tuning with Shift key
    const step = e.shiftKey ? 0.01 : 0.1;
    // Scroll up = increase Q, scroll down = decrease Q
    const delta = e.deltaY < 0 ? step : -step;
    const newQ = Math.max(0.1, Math.min(10, band.q + delta));

    sendParam(`band${bandId - 1}_q`, newQ);
    // Also select this band so knob updates
    setSelectedBand(bandId);
  }, [bands, sendParam]);

  // Solo band toggle - filters audio to only hear the soloed band's frequency range
  // Uses a bandpass filter around the soloed band's frequency
  const handleSoloBand = useCallback((bandId?: number) => {
    const targetBand = bandId ?? selectedBand;
    if (soloedBand === targetBand) {
      // Unsolo - clear solo state and send to DSP
      setSoloedBand(null);
      sendBatch({ '__solo__': -1 }); // -1 = no solo
    } else {
      // Solo target band - set solo state and send to DSP
      setSoloedBand(targetBand);
      setSelectedBand(targetBand);
      sendBatch({ '__solo__': targetBand - 1 }); // 0-indexed band number
    }
  }, [selectedBand, soloedBand, sendBatch]);

  // Per-band channel mode toggle (FabFilter style)
  // Cycles: Stereo → Left → Right → Mid → Side → Stereo
  const handleBandChannelToggle = useCallback((bandId: number) => {
    const modes: ChannelMode[] = ['stereo', 'left', 'right', 'mid', 'side'];
    const currentMode = bandChannels[bandId - 1] || 'stereo';
    const idx = modes.indexOf(currentMode);
    const nextMode = modes[(idx + 1) % modes.length];

    setBandChannels(prev => {
      const updated = [...prev];
      updated[bandId - 1] = nextMode;
      return updated;
    });

    // Send to DSP (when parameter exists)
    // sendParam(`band${bandId - 1}_channel`, modes.indexOf(nextMode));
  }, [bandChannels]);

  // Get channel mode label for display
  const getChannelLabel = (mode: ChannelMode): string => {
    switch (mode) {
      case 'stereo': return 'ST';
      case 'left': return 'L';
      case 'right': return 'R';
      case 'mid': return 'M';
      case 'side': return 'S';
    }
  };

  // Default band values for reset
  const DEFAULT_BAND_FREQS = [50, 100, 300, 1000, 2500, 5000, 10000, 16000];

  // Reset single band to default (double-click on node)
  const handleResetBand = useCallback((bandId: number, e?: React.MouseEvent) => {
    const bandIndex = bandId - 1;

    // GSAP pulse animation on reset
    if (e?.currentTarget) {
      const node = e.currentTarget as HTMLElement;
      const core = node.querySelector('.band-node-core') as HTMLElement;
      if (core) {
        gsap.timeline()
          .to(core, { scale: 1.4, duration: 0.1, ease: 'power2.out' })
          .to(core, { scale: 1, duration: 0.5, ease: 'elastic.out(1, 0.3)' });
      }
    }

    sendBatch({
      [`band${bandIndex}_freqHz`]: DEFAULT_BAND_FREQS[bandIndex],
      [`band${bandIndex}_gainDb`]: 0,
      [`band${bandIndex}_q`]: 1,
      [`band${bandIndex}_type`]: 0, // bell
      [`band${bandIndex}_enabled`]: 1,
    });
  }, [sendBatch]);

  // Reset all bands to default - reset EVERYTHING (params, UI state, etc.)
  const handleResetAllBands = useCallback(() => {
    // GSAP stagger animation for all band nodes
    const bandNodes = document.querySelectorAll('.band-node');
    gsap.to(bandNodes, {
      scale: 0.5,
      opacity: 0.5,
      duration: 0.15,
      stagger: 0.03,
      ease: 'power2.in',
      onComplete: () => {
        gsap.to(bandNodes, {
          scale: 1,
          opacity: 1,
          duration: 0.4,
          stagger: 0.03,
          ease: 'elastic.out(1, 0.4)',
        });
      },
    });

    // Reset all band parameters
    const changes: Record<string, number> = {};
    for (let i = 0; i < 8; i++) {
      changes[`band${i}_freqHz`] = DEFAULT_BAND_FREQS[i];
      changes[`band${i}_gainDb`] = 0;
      changes[`band${i}_q`] = 1;
      changes[`band${i}_type`] = 0; // bell
      changes[`band${i}_enabled`] = 0; // Disable all bands on reset (OFF)
    }
    changes['outputGainDb'] = 0;
    changes['eqMode'] = 0; // minimum phase
    sendBatch(changes);

    // Reset all local UI state
    setOutputGain(0);
    setSelectedBand(1);
    setSoloedBand(null);
    setAutoGain(false);
    setDbZoom(12);
    setEqMode('minimum');
    setBandChannels(Array(8).fill('stereo'));
    setAbState('A');
    abStorageRef.current = { A: {}, B: {} };
  }, [sendBatch]);

  // EQ Mode change handler
  const handleEqModeChange = useCallback((mode: EQMode) => {
    setEqMode(mode);
    // Map mode to param value
    const modeMap: Record<EQMode, number> = {
      'minimum': 0,
      'linear': 1,
      'dynamic': 2,
      'match': 3,
    };
    sendParam('eqMode', modeMap[mode]);
  }, [sendParam]);

  // Auto gain toggle - saves/restores output volume when toggling
  // Real-time compensation is handled by useEffect above
  const handleAutoGainToggle = useCallback(() => {
    const newState = !autoGain;

    if (newState) {
      // Turning ON: save current output value before auto takes over
      preAutoGainOutputRef.current = outputGain;
    } else {
      // Turning OFF: restore previous output value
      handleOutputChange(preAutoGainOutputRef.current);
    }

    setAutoGain(newState);
  }, [autoGain, outputGain, handleOutputChange]);

  // A/B switch
  const handleAbSwitch = useCallback((state: 'A' | 'B') => {
    if (state === abState) return;

    // Save current state to current slot
    if (params) {
      abStorageRef.current[abState] = { ...params };
    }

    // Load state from target slot
    const stored = abStorageRef.current[state];
    if (Object.keys(stored).length > 0) {
      sendBatch(stored);
    }

    setAbState(state);
  }, [abState, params, sendBatch]);

  // A/B copy (copy current to other)
  const handleAbCopy = useCallback(() => {
    if (!params) return;
    const otherState = abState === 'A' ? 'B' : 'A';
    abStorageRef.current[otherState] = { ...params };
  }, [abState, params]);

  // A/B swap
  const handleAbSwap = useCallback(() => {
    if (!params) return;
    // Save current to temp
    const currentParams = { ...params };
    const otherState = abState === 'A' ? 'B' : 'A';
    const otherParams = { ...abStorageRef.current[otherState] };

    // Swap storage
    abStorageRef.current[abState] = otherParams;
    abStorageRef.current[otherState] = currentParams;

    // Load other state
    if (Object.keys(otherParams).length > 0) {
      sendBatch(otherParams);
    }
  }, [abState, params, sendBatch]);

  // Start editing knob value (double-click on knob readout)
  const handleKnobEditStart = useCallback((param: 'freq' | 'gain' | 'q') => {
    const band = bands.find(b => b.id === selectedBand);
    if (!band) return;

    setEditingKnob(param);
    // Format initial value based on param type
    if (param === 'freq') {
      setKnobInputValue(formatFreq(band.freq).replace(' Hz', '').replace(' kHz', 'k'));
    } else if (param === 'gain') {
      setKnobInputValue(band.gain.toFixed(1));
    } else {
      setKnobInputValue(band.q.toFixed(2));
    }

    // Focus input after render
    setTimeout(() => knobInputRef.current?.select(), 0);
  }, [bands, selectedBand]);

  // Confirm knob edit
  const handleKnobEditConfirm = useCallback(() => {
    if (editingKnob === null) return;

    const bandIndex = selectedBand - 1;

    if (editingKnob === 'freq') {
      const parsed = parseFreqInput(knobInputValue);
      if (parsed !== null) {
        const clamped = Math.max(CONFIG.freqMin, Math.min(CONFIG.freqMax, parsed));
        sendParam(`band${bandIndex}_freqHz`, clamped);
      }
    } else if (editingKnob === 'gain') {
      const parsed = parseFloat(knobInputValue);
      if (!isNaN(parsed)) {
        const clamped = Math.max(-24, Math.min(24, parsed));
        sendParam(`band${bandIndex}_gainDb`, clamped);
      }
    } else if (editingKnob === 'q') {
      const parsed = parseFloat(knobInputValue);
      if (!isNaN(parsed)) {
        const clamped = Math.max(0.1, Math.min(10, parsed));
        sendParam(`band${bandIndex}_q`, clamped);
      }
    }

    setEditingKnob(null);
    setKnobInputValue('');
  }, [editingKnob, knobInputValue, selectedBand, sendParam]);

  // Cancel knob edit
  const handleKnobEditCancel = useCallback(() => {
    setEditingKnob(null);
    setKnobInputValue('');
  }, []);

  // Handle knob input key press
  const handleKnobInputKeyDown = useCallback((e: React.KeyboardEvent) => {
    if (e.key === 'Enter') {
      handleKnobEditConfirm();
    } else if (e.key === 'Escape') {
      handleKnobEditCancel();
    }
  }, [handleKnobEditConfirm, handleKnobEditCancel]);

  // Reset output gain on double-click
  const handleOutputReset = useCallback(() => {
    handleOutputChange(0);
  }, [handleOutputChange]);

  // Window size change - resize window and save preference
  const handleWindowSizeChange = useCallback((size: WindowSize) => {
    setWindowSize(size);
    try {
      localStorage.setItem('vaneq_size', size);
    } catch { /* ignore */ }
    const { w, h } = WINDOW_SIZES[size];
    window.dispatchEvent(new CustomEvent('vaneq-programmatic-resize', { detail: { width: w, height: h } }));
    window.resizeTo(w, h);
    const left = Math.round((window.screen.width - w) / 2);
    const top = Math.round((window.screen.height - h) / 2);
    window.moveTo(left, top);
  }, []);

  // ============ Render ============

  return (
    <div className={`eq-plugin ${isOff ? 'off' : ''} ${bypassed ? 'bypassed' : ''}`}>
      {/* Top Bar */}
      <header className="top-bar">
        <div className="brand">
          <div className="logo">
            <svg viewBox="0 0 24 24"><path d="M12 2L2 7v10l10 5 10-5V7L12 2zm0 18.5L4 16V8.5l8 4v8zm1-9.5L5 7l7-3.5L19 7l-6 4z"/></svg>
          </div>
          <div className="brand-text">
            <div className="brand-name">VanEQ Pro</div>
            <div className="brand-subtitle">8-Band Parametric EQ</div>
          </div>
        </div>

        <div className="mode-tabs">
          {(['minimum', 'linear', 'dynamic', 'match'] as EQMode[]).map(mode => (
            <button
              key={mode}
              className={`mode-tab ${eqMode === mode ? 'active' : ''}`}
              onClick={() => handleEqModeChange(mode)}
            >
              {mode === 'minimum' ? 'Minimum Phase' :
               mode === 'linear' ? 'Linear Phase' :
               mode === 'dynamic' ? 'Dynamic' : 'Match EQ'}
            </button>
          ))}
        </div>

        <div className="header-controls">
          <div className="size-switch">
            {(['S', 'M', 'L'] as const).map(size => (
              <button
                key={size}
                className={`size-btn ${windowSize === size ? 'active' : ''}`}
                onClick={() => handleWindowSizeChange(size)}
                title={WINDOW_SIZES[size].label}
              >
                {size}
              </button>
            ))}
          </div>
          <div className="preset-nav">
            <button className="preset-arrow">◀</button>
            <div className="preset-name">Default</div>
            <button className="preset-arrow">▶</button>
          </div>
          <button
            className={`power-btn ${isPluginOn ? 'active' : ''}`}
            onClick={handleOffToggle}
            title="Power On/Off"
          >
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
              <path d="M12 3v9M18.4 6.6a9 9 0 1 1-12.8 0"/>
            </svg>
          </button>
        </div>
      </header>

      {/* Spectrum Section */}
      <section className="spectrum-section" ref={containerRef}>
        {/* WebGL Spectrum Analyzer */}
        {containerSize.width > 0 && analyzerOn && (
          <SpectrumWebGL
            fftData={spectrumData?.fftDb ?? null}
            sampleRate={spectrumData?.sampleRate ?? 48000}
            width={containerSize.width}
            height={containerSize.height}
            freqMin={CONFIG.freqMin}
            freqMax={CONFIG.freqMax}
            active={analyzerOn}
            marginLeft={MARGIN.left}
            marginRight={MARGIN.right}
            marginTop={MARGIN.top}
            marginBottom={MARGIN.bottom}
          />
        )}

        {/* WebGL EQ Curve */}
        {containerSize.width > 0 && (
          <EQCurveWebGL
            bands={bands}
            width={containerSize.width}
            height={containerSize.height}
            dbRange={dbRange}
            freqMin={CONFIG.freqMin}
            freqMax={CONFIG.freqMax}
            marginLeft={MARGIN.left}
            marginRight={MARGIN.right}
            marginTop={MARGIN.top}
            marginBottom={MARGIN.bottom}
          />
        )}

        <div className="db-scale">
          {/* Dynamic dB scale based on range */}
          {(() => {
            const step = dbRange <= 6 ? 2 : dbRange <= 12 ? 3 : 6;
            const ticks: number[] = [];
            for (let db = dbRange; db >= -dbRange; db -= step) {
              ticks.push(db);
            }
            return ticks.map(db => (
              <span key={db} className={`db-tick ${db === 0 ? 'zero' : ''}`}>
                {db > 0 ? '+' : ''}{db}
              </span>
            ));
          })()}
        </div>

        <div className="freq-scale">
          {['20', '30', '50', '100', '200', '500', '1k', '2k', '5k', '10k', '20k'].map(f => (
            <span key={f} className="freq-tick">{f}</span>
          ))}
        </div>

        <div className="band-nodes-container">
          {/* Band nodes positioned with absolute pixels matching WebGL exactly */}
          {containerSize.width > 0 && bands.map(band => {
            // Calculate working area (same as WebGL)
            const areaWidth = containerSize.width - MARGIN.left - MARGIN.right;
            const areaHeight = containerSize.height - MARGIN.top - MARGIN.bottom;

            // Calculate X position in pixels (logarithmic frequency scale) - same formula as EQCurveWebGL
            const logMin = Math.log10(CONFIG.freqMin);
            const logMax = Math.log10(CONFIG.freqMax);
            const xPx = MARGIN.left + ((Math.log10(band.freq) - logMin) / (logMax - logMin)) * areaWidth;

            // Calculate Y position in pixels (linear gain scale) - same formula as EQCurveWebGL
            const fullRange = dbRange * 2;
            const yPx = MARGIN.top + (1 - (band.gain + dbRange) / fullRange) * areaHeight;

            // Clamp Y for visibility
            const clampedYPx = Math.max(MARGIN.top - 20, Math.min(containerSize.height - MARGIN.bottom + 20, yPx));
            // Check if node is at edge
            const isAtEdge = yPx < MARGIN.top || yPx > containerSize.height - MARGIN.bottom;
            // Tooltip below when near top
            const tooltipBelow = yPx < MARGIN.top + areaHeight * 0.2;
            // Dimmed when another band is soloed (visual only, doesn't affect EQ curve)
            const isDimmedBySolo = soloedBand !== null && soloedBand !== band.id;
            const isSoloed = soloedBand === band.id;

            return (
              <div
                key={band.id}
                className={`band-node ${band.id === selectedBand ? 'selected' : ''} ${!band.active ? 'inactive' : ''} ${isAtEdge ? 'at-edge' : ''} ${tooltipBelow ? 'tooltip-below' : ''} ${isDimmedBySolo ? 'dimmed-solo' : ''} ${isSoloed ? 'soloed' : ''}`}
                data-band={band.id}
                style={{
                  left: `${xPx}px`,
                  top: `${clampedYPx}px`,
                  '--band-node-color': BAND_COLORS_HEX[band.id - 1],
                } as React.CSSProperties}
                onMouseDown={(e) => handleBandDrag(band.id, e)}
                onDoubleClick={(e) => handleResetBand(band.id, e)}
                onWheel={(e) => handleBandScroll(band.id, e)}
                title="Drag to adjust, scroll to change Q, double-click to reset"
              >
                <div className="band-node-ring" />
                <div className="band-node-core">{band.id}</div>
                <div className="band-tooltip">
                  <div className="tooltip-header">
                    <span className="tooltip-freq">{formatFreq(band.freq)}</span>
                    <button
                      className={`tooltip-solo-btn ${isSoloed ? 'active' : ''}`}
                      style={{
                        '--solo-btn-color': BAND_COLORS_HEX[band.id - 1],
                      } as React.CSSProperties}
                      onClick={(e) => {
                        e.stopPropagation();
                        e.preventDefault();
                        handleSoloBand(band.id);
                      }}
                      onMouseDown={(e) => {
                        e.stopPropagation();
                        e.preventDefault();
                      }}
                      onPointerDown={(e) => {
                        e.stopPropagation();
                        e.preventDefault();
                      }}
                      title={isSoloed ? 'Unsolo band' : 'Solo band'}
                    >
                      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                        <path d="M3 18v-6a9 9 0 0 1 18 0v6"/>
                        <path d="M21 19a2 2 0 0 1-2 2h-1a2 2 0 0 1-2-2v-3a2 2 0 0 1 2-2h3v5z"/>
                        <path d="M3 19a2 2 0 0 0 2 2h1a2 2 0 0 0 2-2v-3a2 2 0 0 0-2-2H3v5z"/>
                      </svg>
                    </button>
                  </div>
                  <div className="tooltip-info">
                    <span className="tooltip-gain">{formatDb(band.gain)} dB</span>
                    <span className="tooltip-sep">·</span>
                    <span className="tooltip-q">Q {band.q.toFixed(2)}</span>
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      </section>

      {/* Controls Section */}
      <section className="controls-section">
        <div className="band-pills">
          <div className="band-pills-row">
            {bands.slice(0, 4).map(band => (
              <div
                key={band.id}
                className={`band-pill ${band.id === selectedBand ? 'selected' : ''} ${!band.active ? 'inactive' : ''} ${soloedBand === band.id ? 'soloed' : ''}`}
                data-band={band.id}
                onClick={() => {
                  setSelectedBand(band.id);
                  handleBandToggle(band.id);
                }}
                onContextMenu={(e) => {
                  e.preventDefault();
                  handleBandChannelToggle(band.id);
                }}
                title="Click: focus + toggle on/off, Right-click: channel mode"
              >
                <div
                  className="indicator"
                  title="Band active indicator"
                />
                <div className="number">{band.id}</div>
                {bandChannels[band.id - 1] !== 'stereo' && (
                  <div
                    className="channel-badge"
                    style={{ '--badge-color': BAND_COLORS[band.id - 1] } as React.CSSProperties}
                  >
                    {getChannelLabel(bandChannels[band.id - 1])}
                  </div>
                )}
              </div>
            ))}
          </div>
          <div className="band-pills-row">
            {bands.slice(4, 8).map(band => (
              <div
                key={band.id}
                className={`band-pill ${band.id === selectedBand ? 'selected' : ''} ${!band.active ? 'inactive' : ''} ${soloedBand === band.id ? 'soloed' : ''}`}
                data-band={band.id}
                onClick={() => {
                  setSelectedBand(band.id);
                  handleBandToggle(band.id);
                }}
                onContextMenu={(e) => {
                  e.preventDefault();
                  handleBandChannelToggle(band.id);
                }}
                title="Click: focus + toggle on/off, Right-click: channel mode"
              >
                <div
                  className="indicator"
                  title="Band active indicator"
                />
                <div className="number">{band.id}</div>
                {bandChannels[band.id - 1] !== 'stereo' && (
                  <div
                    className="channel-badge"
                    style={{ '--badge-color': BAND_COLORS[band.id - 1] } as React.CSSProperties}
                  >
                    {getChannelLabel(bandChannels[band.id - 1])}
                  </div>
                )}
              </div>
            ))}
          </div>
        </div>

        <div className="params-panel">
          {/* Shape Selector */}
          <div className="shape-selector">
            <div className="shape-label">Shape</div>
            {FILTER_TYPES.map(ft => (
              <button
                key={ft.id}
                className={`shape-btn ${activeBand.type === ft.id ? 'active' : ''}`}
                onClick={() => handleFilterTypeChange(ft.id)}
              >
                <svg className="shape-icon" viewBox="0 0 24 14">
                  <path d={ft.path} />
                </svg>
                {ft.label}
              </button>
            ))}
          </div>

          {/* Frequency Knob */}
          <div className="knob-group">
            <div className="knob-label">Frequency</div>
            <div
              className="knob-container"
              onMouseDown={(e) => handleKnobDrag('freq', 20, 20000, e)}
              onDoubleClick={() => handleKnobEditStart('freq')}
            >
              <div className="knob-bg" />
              <div className="knob-track" />
              <div
                className="knob-value-arc"
                style={{ '--arc-deg': `${valueToArcDeg(Math.log10(activeBand.freq), Math.log10(20), Math.log10(20000))}deg` } as React.CSSProperties}
              />
              <div className="knob-inner" />
              <div
                className="knob-indicator"
                style={{ '--rotation': `${valueToRotation(Math.log10(activeBand.freq), Math.log10(20), Math.log10(20000))}deg` } as React.CSSProperties}
              />
            </div>
            <div
              className="knob-readout"
              onDoubleClick={() => handleKnobEditStart('freq')}
              title="Double-click to edit"
            >
              {editingKnob === 'freq' ? (
                <input
                  ref={knobInputRef}
                  type="text"
                  className="knob-input"
                  value={knobInputValue}
                  onChange={(e) => setKnobInputValue(e.target.value)}
                  onKeyDown={handleKnobInputKeyDown}
                  onBlur={handleKnobEditConfirm}
                  autoFocus
                />
              ) : (
                formatFreq(activeBand.freq)
              )}
            </div>
          </div>

          {/* Gain Knob */}
          <div className="knob-group">
            <div className="knob-label">Gain</div>
            <div
              className="knob-container"
              onMouseDown={(e) => handleKnobDrag('gain', -24, 24, e)}
              onDoubleClick={() => handleKnobEditStart('gain')}
            >
              <div className="knob-bg" />
              <div className="knob-track" />
              <div
                className="knob-value-arc"
                style={{ '--arc-deg': `${valueToArcDeg(activeBand.gain, -24, 24)}deg` } as React.CSSProperties}
              />
              <div className="knob-inner" />
              <div
                className="knob-indicator"
                style={{ '--rotation': `${valueToRotation(activeBand.gain, -24, 24)}deg` } as React.CSSProperties}
              />
            </div>
            <div
              className="knob-readout"
              onDoubleClick={() => handleKnobEditStart('gain')}
              title="Double-click to edit"
            >
              {editingKnob === 'gain' ? (
                <input
                  ref={knobInputRef}
                  type="text"
                  className="knob-input"
                  value={knobInputValue}
                  onChange={(e) => setKnobInputValue(e.target.value)}
                  onKeyDown={handleKnobInputKeyDown}
                  onBlur={handleKnobEditConfirm}
                  autoFocus
                />
              ) : (
                <>{formatDb(activeBand.gain)}<span className="unit">dB</span></>
              )}
            </div>
          </div>

          {/* Q Knob */}
          <div className="knob-group">
            <div className="knob-label">Q / Width</div>
            <div
              className="knob-container"
              onMouseDown={(e) => handleKnobDrag('q', 0.1, 10, e)}
              onDoubleClick={() => handleKnobEditStart('q')}
            >
              <div className="knob-bg" />
              <div className="knob-track" />
              <div
                className="knob-value-arc"
                style={{ '--arc-deg': `${valueToArcDeg(activeBand.q, 0.1, 10)}deg` } as React.CSSProperties}
              />
              <div className="knob-inner" />
              <div
                className="knob-indicator"
                style={{ '--rotation': `${valueToRotation(activeBand.q, 0.1, 10)}deg` } as React.CSSProperties}
              />
            </div>
            <div
              className="knob-readout"
              onDoubleClick={() => handleKnobEditStart('q')}
              title="Double-click to edit"
            >
              {editingKnob === 'q' ? (
                <input
                  ref={knobInputRef}
                  type="text"
                  className="knob-input"
                  value={knobInputValue}
                  onChange={(e) => setKnobInputValue(e.target.value)}
                  onKeyDown={handleKnobInputKeyDown}
                  onBlur={handleKnobEditConfirm}
                  autoFocus
                />
              ) : (
                activeBand.q.toFixed(2)
              )}
            </div>
          </div>

          {/* Channel Mode Selector - FabFilter style */}
          <div className="channel-selector" data-band={selectedBand}>
            <div className="channel-label">Channel</div>
            <div className="channel-buttons">
              {(['stereo', 'left', 'right', 'mid', 'side'] as const).map(mode => (
                <button
                  key={mode}
                  className={`channel-btn ${bandChannels[selectedBand - 1] === mode ? 'active' : ''}`}
                  onClick={() => {
                    setBandChannels(prev => {
                      const updated = [...prev];
                      updated[selectedBand - 1] = mode;
                      return updated;
                    });
                  }}
                  style={{
                    '--band-color': BAND_COLORS[selectedBand - 1]
                  } as React.CSSProperties}
                >
                  {mode === 'stereo' ? 'ST' : mode === 'left' ? 'L' : mode === 'right' ? 'R' : mode === 'mid' ? 'M' : 'S'}
                </button>
              ))}
            </div>
            <div className="channel-desc">
              {bandChannels[selectedBand - 1] === 'stereo' ? 'Stereo' :
               bandChannels[selectedBand - 1] === 'left' ? 'Left Only' :
               bandChannels[selectedBand - 1] === 'right' ? 'Right Only' :
               bandChannels[selectedBand - 1] === 'mid' ? 'Mid (Center)' : 'Side (Width)'}
            </div>
          </div>

          {/* Gain Display */}
          <div className="gain-display" data-band={selectedBand}>
            <div className="gain-value">
              {formatDb(activeBand.gain)}<span className="unit">dB</span>
            </div>
            <div className="gain-info">
              Band {selectedBand} · {FILTER_TYPES.find(f => f.id === activeBand.type)?.label || 'Bell'}
            </div>
            <div className="gain-band-color" style={{ background: BAND_COLORS[selectedBand - 1] }} />
          </div>
        </div>
      </section>

      {/* Bottom Toolbar */}
      <footer className="bottom-bar">
        <div className="toolbar-group">
          <button
            className={`tool-btn ${bypassed ? 'active' : ''}`}
            onClick={handleBypassToggle}
          >
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <circle cx="12" cy="12" r="10"/><path d="M12 6v6l4 2"/>
            </svg>
            Bypass
          </button>
          <button
            className={`tool-btn ${analyzerOn ? 'active' : ''}`}
            onClick={() => setAnalyzerOn(!analyzerOn)}
          >
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <path d="M3 3v18h18"/><path d="M18 9l-5 5-4-4-3 3"/>
            </svg>
            Analyzer
          </button>
          <div className="toolbar-divider" />
          <div className="db-range-switch">
            {([3, 6, 12] as const).map(zoom => (
              <button
                key={zoom}
                className={`db-range-btn ${dbZoom === zoom ? 'active' : ''}`}
                onClick={() => setDbZoom(zoom)}
                title={`±${zoom} dB zoom (shows ±${zoom * 2} dB)`}
              >
                ±{zoom}
              </button>
            ))}
          </div>
          <div className="toolbar-divider" />
          <button
            className="tool-btn reset-btn"
            onClick={handleResetAllBands}
            title="Reset all bands to default"
          >
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8"/>
              <path d="M3 3v5h5"/>
            </svg>
            Reset
          </button>
          <div className="toolbar-divider" />
          <button
            className={`tool-btn ${bandChannels[selectedBand - 1] !== 'stereo' ? 'active' : ''}`}
            onClick={() => handleBandChannelToggle(selectedBand)}
            title="Change channel mode for selected band (or right-click on band pill)"
          >
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <circle cx="12" cy="12" r="3"/><path d="M12 2v4m0 12v4M2 12h4m12 0h4"/>
            </svg>
            {getChannelLabel(bandChannels[selectedBand - 1])}
          </button>
          <button
            className={`tool-btn ${autoGain ? 'active' : ''}`}
            onClick={handleAutoGainToggle}
          >
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <path d="M12 3v18M3 12h18"/>
            </svg>
            Auto Gain
          </button>
        </div>

        <div className="toolbar-group">
          <div className="output-control">
            <span className="output-label">Output</span>
            <div
              className="slider-container"
              onMouseDown={handleOutputSliderDrag}
              onDoubleClick={handleOutputReset}
              title="Double-click to reset to 0 dB"
            >
              <div className="slider-fill" style={{ width: `${((outputGain + 24) / 48) * 100}%` }} />
              <div className="slider-thumb" style={{ left: `${((outputGain + 24) / 48) * 100}%` }} />
            </div>
            <span
              className="output-value"
              onDoubleClick={handleOutputReset}
              title="Double-click to reset to 0 dB"
            >
              {formatDb(outputGain)} dB
            </span>
          </div>
          <div className="toolbar-divider" />
          <div className="ab-switch">
            <button
              className={`ab-btn ${abState === 'A' ? 'active' : ''}`}
              onClick={() => handleAbSwitch('A')}
            >A</button>
            <button
              className="copy-swap"
              onClick={handleAbCopy}
              onDoubleClick={handleAbSwap}
              title="Click to copy, double-click to swap"
            >
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <path d="M7 16V4h12v12H7z"/><path d="M3 8v12h12"/>
              </svg>
            </button>
            <button
              className={`ab-btn ${abState === 'B' ? 'active' : ''}`}
              onClick={() => handleAbSwitch('B')}
            >B</button>
          </div>
        </div>
      </footer>
    </div>
  );
}
