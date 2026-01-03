/**
 * VanEQ Pro - Bottom Toolbar Component
 * VERSION: 2026-01-01-v1 - WOW Edition
 *
 * Features:
 * - Analyzer quality selector (LOW/MID/HIGH)
 * - Spectrum display options (Pre/Post, Freeze, Range)
 * - Output metering
 * - Additional controls
 */


export type AnalyzerQuality = 'low' | 'mid' | 'high';
export type AnalyzerPosition = 'pre' | 'post';
export type AnalyzerRange = 'full' | 'limited';

type Props = {
  // Analyzer settings
  analyzerQuality: AnalyzerQuality;
  onQualityChange: (quality: AnalyzerQuality) => void;

  analyzerPosition?: AnalyzerPosition;
  onPositionChange?: (position: AnalyzerPosition) => void;

  analyzerRange?: AnalyzerRange;
  onRangeChange?: (range: AnalyzerRange) => void;

  analyzerFrozen?: boolean;
  onToggleFreeze?: () => void;

  // Output level
  outputLevel?: number; // 0-1
  outputPeak?: number;  // 0-1

  // Auto gain
  autoGainEnabled?: boolean;
  onToggleAutoGain?: () => void;
  autoGainAmount?: number; // dB

  // Scale display
  scaleDb?: number;
};

/**
 * Quality selector buttons
 */
function QualitySelector({
  quality,
  onChange,
}: {
  quality: AnalyzerQuality;
  onChange: (q: AnalyzerQuality) => void;
}) {
  return (
    <div className="qualityGroup">
      <span className="qualityLabel">QUALITY</span>
      <div className="qualityButtons">
        {(['low', 'mid', 'high'] as AnalyzerQuality[]).map((q) => (
          <button
            key={q}
            className={`qualityBtn ${quality === q ? 'active' : ''}`}
            onClick={() => onChange(q)}
          >
            {q.toUpperCase()}
          </button>
        ))}
      </div>
    </div>
  );
}

/**
 * Position toggle (Pre/Post EQ)
 */
function PositionToggle({
  position,
  onChange,
}: {
  position: AnalyzerPosition;
  onChange: (p: AnalyzerPosition) => void;
}) {
  return (
    <div className="positionGroup">
      <button
        className={`positionBtn ${position === 'pre' ? 'active' : ''}`}
        onClick={() => onChange('pre')}
      >
        PRE
      </button>
      <button
        className={`positionBtn ${position === 'post' ? 'active' : ''}`}
        onClick={() => onChange('post')}
      >
        POST
      </button>
    </div>
  );
}

/**
 * Simple meter bar
 */
function MeterBar({
  level,
  peak,
}: {
  level: number;
  peak?: number;
}) {
  const levelPercent = Math.min(100, Math.max(0, level * 100));
  const peakPercent = peak !== undefined ? Math.min(100, Math.max(0, peak * 100)) : 0;

  return (
    <div className="meterBarContainer">
      <div className="meterBarTrack">
        <div
          className="meterBarFill"
          style={{ width: `${levelPercent}%` }}
        />
        {peak !== undefined && peak > 0.01 && (
          <div
            className="meterBarPeak"
            style={{ left: `${peakPercent}%` }}
          />
        )}
      </div>
    </div>
  );
}

export function BottomToolbar({
  analyzerQuality,
  onQualityChange,
  analyzerPosition = 'post',
  onPositionChange,
  analyzerRange: _analyzerRange = 'full',
  onRangeChange: _onRangeChange,
  analyzerFrozen = false,
  onToggleFreeze,
  outputLevel = 0,
  outputPeak = 0,
  autoGainEnabled = false,
  onToggleAutoGain,
  autoGainAmount = 0,
  scaleDb: _scaleDb,
}: Props) {
  // Suppress unused vars
  void _analyzerRange;
  void _onRangeChange;
  void _scaleDb;

  return (
    <div className="bottomToolbar">
      {/* Left: Analyzer controls */}
      <div className="bottomLeft">
        <QualitySelector quality={analyzerQuality} onChange={onQualityChange} />

        {onPositionChange && (
          <PositionToggle position={analyzerPosition} onChange={onPositionChange} />
        )}

        {onToggleFreeze && (
          <button
            className={`freezeBtn ${analyzerFrozen ? 'active' : ''}`}
            onClick={onToggleFreeze}
            title="Freeze spectrum"
          >
            <FreezeIcon />
            <span>FREEZE</span>
          </button>
        )}
      </div>

      {/* Center: Output meter */}
      <div className="bottomCenter">
        <div className="outputMeter">
          <span className="meterLabel">OUTPUT</span>
          <MeterBar level={outputLevel} peak={outputPeak} />
        </div>
      </div>

      {/* Right: Auto gain, etc */}
      <div className="bottomRight">
        {onToggleAutoGain && (
          <button
            className={`autoGainBtn ${autoGainEnabled ? 'active' : ''}`}
            onClick={onToggleAutoGain}
            title="Auto gain compensation"
          >
            <span>AUTO GAIN</span>
            {autoGainEnabled && autoGainAmount !== 0 && (
              <span className="autoGainValue">
                {autoGainAmount >= 0 ? '+' : ''}{autoGainAmount.toFixed(1)} dB
              </span>
            )}
          </button>
        )}
      </div>
    </div>
  );
}

/**
 * Freeze icon (snowflake)
 */
function FreezeIcon() {
  return (
    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
      <line x1="12" y1="2" x2="12" y2="22" />
      <line x1="2" y1="12" x2="22" y2="12" />
      <line x1="4.93" y1="4.93" x2="19.07" y2="19.07" />
      <line x1="19.07" y1="4.93" x2="4.93" y2="19.07" />
    </svg>
  );
}

export default BottomToolbar;
