/**
 * VanEQ Pro - Top Bar Component
 * VERSION: 2026-01-01-v1 - WOW Edition with mode tabs
 *
 * Features:
 * - A/B preset switching with copy/swap
 * - Mode tabs (Minimum Phase, Linear Phase, Dynamic, Match EQ)
 * - S/M/L window size selection (FabFilter-style fixed presets)
 * - Theme toggle (sun/moon icons)
 * - Analyzer toggle
 * - ON/OFF power button
 */

export type SizeMode = 'S' | 'M' | 'L';
export type EQMode = 'minimum' | 'linear' | 'dynamic' | 'match';

type Props = {
  // A/B state
  abState: 'A' | 'B';
  onAbToggle: (state: 'A' | 'B') => void;
  onAbCopy?: () => void;
  onAbSwap?: () => void;

  // EQ processing mode
  eqMode?: EQMode;
  onEqModeChange?: (mode: EQMode) => void;

  // Size mode (S/M/L fixed presets)
  uiSize: SizeMode;
  onUiSizeChange: (mode: SizeMode) => void;

  // Theme
  isLightTheme: boolean;
  onToggleTheme: () => void;

  // Analyzer
  analyzerEnabled: boolean;
  onToggleAnalyzer: () => void;

  // Plugin power
  pluginEnabled: boolean;
  onTogglePluginEnabled: () => void;

  // Optional preset menu
  onPresetMenu?: () => void;
  presetName?: string;
};

/**
 * SVG icons for theme toggle
 */
function SunIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
      <circle cx="12" cy="12" r="5" />
      <line x1="12" y1="1" x2="12" y2="3" />
      <line x1="12" y1="21" x2="12" y2="23" />
      <line x1="4.22" y1="4.22" x2="5.64" y2="5.64" />
      <line x1="18.36" y1="18.36" x2="19.78" y2="19.78" />
      <line x1="1" y1="12" x2="3" y2="12" />
      <line x1="21" y1="12" x2="23" y2="12" />
      <line x1="4.22" y1="19.78" x2="5.64" y2="18.36" />
      <line x1="18.36" y1="5.64" x2="19.78" y2="4.22" />
    </svg>
  );
}

function MoonIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
      <path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z" />
    </svg>
  );
}

/**
 * Analyzer icon (spectrum bars)
 */
function AnalyzerIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
      <rect x="4" y="14" width="3" height="8" rx="1" />
      <rect x="10" y="8" width="3" height="14" rx="1" />
      <rect x="16" y="4" width="3" height="18" rx="1" />
    </svg>
  );
}

/**
 * Copy icon
 */
function CopyIcon() {
  return (
    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
      <rect x="9" y="9" width="13" height="13" rx="2" />
      <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1" />
    </svg>
  );
}

/**
 * Swap icon
 */
function SwapIcon() {
  return (
    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
      <path d="M7 16l-4-4 4-4" />
      <path d="M17 8l4 4-4 4" />
      <path d="M3 12h18" />
    </svg>
  );
}

/**
 * Chevron icon for preset dropdown
 */
function ChevronIcon() {
  return (
    <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
      <polyline points="6 9 12 15 18 9" />
    </svg>
  );
}

const MODE_LABELS: Record<EQMode, string> = {
  minimum: 'Minimum Phase',
  linear: 'Linear Phase',
  dynamic: 'Dynamic',
  match: 'Match EQ',
};

export function TopBar({
  abState,
  onAbToggle,
  onAbCopy,
  onAbSwap,
  eqMode = 'minimum',
  onEqModeChange,
  uiSize,
  onUiSizeChange,
  isLightTheme,
  onToggleTheme,
  analyzerEnabled,
  onToggleAnalyzer,
  pluginEnabled,
  onTogglePluginEnabled,
  onPresetMenu,
  presetName = 'Default',
}: Props) {
  return (
    <div className="topBar">
      {/* Left section: A/B + Copy/Swap + Preset */}
      <div className="topLeft">
        <div className="abGroup">
          <button
            className={`abBtn ${abState === 'A' ? 'active' : ''}`}
            onClick={() => onAbToggle('A')}
            title="Switch to A"
          >
            A
          </button>
          <button
            className={`abBtn ${abState === 'B' ? 'active' : ''}`}
            onClick={() => onAbToggle('B')}
            title="Switch to B"
          >
            B
          </button>
        </div>

        {/* Copy/Swap buttons */}
        {(onAbCopy || onAbSwap) && (
          <div className="abActions">
            {onAbCopy && (
              <button className="iconBtn small" onClick={onAbCopy} title={`Copy ${abState} to ${abState === 'A' ? 'B' : 'A'}`}>
                <CopyIcon />
              </button>
            )}
            {onAbSwap && (
              <button className="iconBtn small" onClick={onAbSwap} title="Swap A and B">
                <SwapIcon />
              </button>
            )}
          </div>
        )}

        {/* Preset dropdown */}
        <button className="presetBtn" onClick={onPresetMenu}>
          <span className="presetName">{presetName}</span>
          <ChevronIcon />
        </button>
      </div>

      {/* Center: Mode tabs */}
      <div className="topMid">
        {onEqModeChange ? (
          <div className="modeTabGroup">
            {(['minimum', 'linear', 'dynamic', 'match'] as EQMode[]).map((mode) => (
              <button
                key={mode}
                className={`modeTab ${eqMode === mode ? 'active' : ''}`}
                onClick={() => onEqModeChange(mode)}
              >
                {MODE_LABELS[mode]}
              </button>
            ))}
          </div>
        ) : (
          <span className="topTitle">VANEQ PRO</span>
        )}
      </div>

      {/* Right section: S/M/L, Theme, Analyzer, Power */}
      <div className="topRight">
        {/* Size buttons S/M/L (FabFilter-style fixed presets) */}
        <div className="sizeGroup">
          {(['S', 'M', 'L'] as SizeMode[]).map((mode) => (
            <button
              key={mode}
              className={`sizeBtn ${uiSize === mode ? 'active' : ''}`}
              onClick={() => onUiSizeChange(mode)}
              title={`Window size ${mode}`}
            >
              {mode}
            </button>
          ))}
        </div>

        {/* Theme toggle (sun/moon) */}
        <button
          className="iconBtn"
          title={isLightTheme ? 'Switch to dark theme' : 'Switch to light theme'}
          onClick={onToggleTheme}
        >
          {isLightTheme ? <SunIcon /> : <MoonIcon />}
        </button>

        {/* Analyzer toggle */}
        <button
          className={`iconBtn ${analyzerEnabled ? 'active' : ''}`}
          title={analyzerEnabled ? 'Disable analyzer' : 'Enable analyzer'}
          onClick={onToggleAnalyzer}
        >
          <AnalyzerIcon />
        </button>

        {/* Power ON/OFF button */}
        <button
          className={`onBtn ${!pluginEnabled ? 'off' : ''}`}
          onClick={onTogglePluginEnabled}
        >
          {pluginEnabled ? 'ON' : 'OFF'}
        </button>
      </div>
    </div>
  );
}
