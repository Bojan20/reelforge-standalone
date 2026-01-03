/**
 * Win Tier Editor
 *
 * Configure audio for different win tiers:
 * - Small Win (< 5x)
 * - Medium Win (5-15x)
 * - Big Win (15-50x)
 * - Mega Win (50-100x)
 * - Epic Win (> 100x)
 *
 * Each tier can have:
 * - Stinger sound
 * - Celebration loop
 * - Coin rain intensity
 * - Duration based on win amount
 *
 * @module layout/slot/WinTierEditor
 */

import { memo, useState, useCallback } from 'react';

// ============ Types ============

export type WinTier = 'small' | 'medium' | 'big' | 'mega' | 'epic' | 'jackpot';

export interface WinTierSound {
  id: string;
  name: string;
  type: 'stinger' | 'loop' | 'accent' | 'coins';
  volume?: number;
  fadeIn?: number;
  fadeOut?: number;
}

export interface WinTierConfig {
  tier: WinTier;
  minMultiplier: number;
  maxMultiplier: number;
  sounds: WinTierSound[];
  celebrationDuration: number; // ms
  coinRainIntensity: number; // 0-1
  screenShake: boolean;
  flashIntensity: number; // 0-1
}

export interface WinTierEditorProps {
  tiers: WinTierConfig[];
  activeTier?: WinTier | null;
  onTierChange?: (tiers: WinTierConfig[]) => void;
  onTierSelect?: (tier: WinTier) => void;
  onPreview?: (tier: WinTier) => void;
}

// ============ Constants ============

const TIER_COLORS: Record<WinTier, string> = {
  small: '#6b7280',
  medium: '#3b82f6',
  big: '#8b5cf6',
  mega: '#f59e0b',
  epic: '#ef4444',
  jackpot: '#fbbf24',
};

const TIER_LABELS: Record<WinTier, string> = {
  small: 'Small Win',
  medium: 'Medium Win',
  big: 'Big Win',
  mega: 'Mega Win',
  epic: 'Epic Win',
  jackpot: 'JACKPOT',
};

const TIER_ICONS: Record<WinTier, string> = {
  small: '🪙',
  medium: '💰',
  big: '💎',
  mega: '🔥',
  epic: '⚡',
  jackpot: '👑',
};

// ============ Win Tier Card ============

interface TierCardProps {
  config: WinTierConfig;
  isActive: boolean;
  isSelected: boolean;
  onClick: () => void;
  onPreview: () => void;
  onChange: (config: WinTierConfig) => void;
}

const TierCard = memo(function TierCard({
  config,
  isActive,
  isSelected,
  onClick,
  onPreview,
  onChange,
}: TierCardProps) {
  const [isExpanded, setIsExpanded] = useState(false);
  const color = TIER_COLORS[config.tier];

  return (
    <div
      className={`rf-win-tier-card ${isActive ? 'rf-win-tier-card--active' : ''} ${isSelected ? 'rf-win-tier-card--selected' : ''}`}
      style={{ '--tier-color': color } as React.CSSProperties}
      onClick={onClick}
    >
      {/* Header */}
      <div className="rf-win-tier-card__header">
        <span className="rf-win-tier-card__icon">{TIER_ICONS[config.tier]}</span>
        <span className="rf-win-tier-card__label">{TIER_LABELS[config.tier]}</span>
        <span className="rf-win-tier-card__range">
          {config.minMultiplier}x - {config.maxMultiplier === Infinity ? '∞' : `${config.maxMultiplier}x`}
        </span>
      </div>

      {/* Quick Stats */}
      <div className="rf-win-tier-card__stats">
        <div className="rf-win-tier-card__stat">
          <span>🔊</span>
          <span>{config.sounds.length} sounds</span>
        </div>
        <div className="rf-win-tier-card__stat">
          <span>⏱️</span>
          <span>{(config.celebrationDuration / 1000).toFixed(1)}s</span>
        </div>
        <div className="rf-win-tier-card__stat">
          <span>💫</span>
          <span>{Math.round(config.coinRainIntensity * 100)}%</span>
        </div>
      </div>

      {/* Preview Button */}
      <button
        className="rf-win-tier-card__preview"
        onClick={(e) => {
          e.stopPropagation();
          onPreview();
        }}
      >
        ▶ Preview
      </button>

      {/* Expand/Collapse */}
      <button
        className="rf-win-tier-card__expand"
        onClick={(e) => {
          e.stopPropagation();
          setIsExpanded(!isExpanded);
        }}
      >
        {isExpanded ? '▼' : '▶'}
      </button>

      {/* Expanded Details */}
      {isExpanded && (
        <div className="rf-win-tier-card__details" onClick={(e) => e.stopPropagation()}>
          {/* Sounds */}
          <div className="rf-win-tier-card__section">
            <h4>Sounds</h4>
            {config.sounds.map((sound) => (
              <div key={sound.id} className="rf-win-tier-card__sound">
                <span className={`rf-win-tier-card__sound-type rf-win-tier-card__sound-type--${sound.type}`}>
                  {sound.type}
                </span>
                <span>{sound.name}</span>
              </div>
            ))}
          </div>

          {/* Settings */}
          <div className="rf-win-tier-card__section">
            <h4>Settings</h4>
            <div className="rf-win-tier-card__setting">
              <label>Duration</label>
              <input
                type="range"
                min={500}
                max={10000}
                step={100}
                value={config.celebrationDuration}
                onChange={(e) =>
                  onChange({
                    ...config,
                    celebrationDuration: parseInt(e.target.value),
                  })
                }
              />
              <span>{(config.celebrationDuration / 1000).toFixed(1)}s</span>
            </div>
            <div className="rf-win-tier-card__setting">
              <label>Coin Rain</label>
              <input
                type="range"
                min={0}
                max={100}
                value={config.coinRainIntensity * 100}
                onChange={(e) =>
                  onChange({
                    ...config,
                    coinRainIntensity: parseInt(e.target.value) / 100,
                  })
                }
              />
              <span>{Math.round(config.coinRainIntensity * 100)}%</span>
            </div>
            <div className="rf-win-tier-card__setting">
              <label>Screen Shake</label>
              <input
                type="checkbox"
                checked={config.screenShake}
                onChange={(e) =>
                  onChange({
                    ...config,
                    screenShake: e.target.checked,
                  })
                }
              />
            </div>
          </div>
        </div>
      )}

      {/* Active indicator bar */}
      {isActive && <div className="rf-win-tier-card__active-bar" />}
    </div>
  );
});

// ============ Main Component ============

export const WinTierEditor = memo(function WinTierEditor({
  tiers,
  activeTier,
  onTierChange,
  onTierSelect,
  onPreview,
}: WinTierEditorProps) {
  const [selectedTier, setSelectedTier] = useState<WinTier | null>(null);

  const handleTierClick = useCallback(
    (tier: WinTier) => {
      setSelectedTier(tier);
      onTierSelect?.(tier);
    },
    [onTierSelect]
  );

  const handleTierChange = useCallback(
    (updatedConfig: WinTierConfig) => {
      const newTiers = tiers.map((t) =>
        t.tier === updatedConfig.tier ? updatedConfig : t
      );
      onTierChange?.(newTiers);
    },
    [tiers, onTierChange]
  );

  // Calculate tier distribution visualization
  const maxMultiplier = Math.max(...tiers.filter(t => t.maxMultiplier !== Infinity).map(t => t.maxMultiplier), 100);

  return (
    <div className="rf-win-tier-editor">
      {/* Header */}
      <div className="rf-win-tier-editor__header">
        <span className="rf-win-tier-editor__title">Win Tier Configuration</span>
        {activeTier && (
          <span className="rf-win-tier-editor__active">
            Active: {TIER_ICONS[activeTier]} {TIER_LABELS[activeTier]}
          </span>
        )}
      </div>

      {/* Tier Distribution Bar */}
      <div className="rf-win-tier-editor__distribution">
        {tiers.map((tier) => {
          const width = tier.maxMultiplier === Infinity
            ? 20
            : ((tier.maxMultiplier - tier.minMultiplier) / maxMultiplier) * 80;
          return (
            <div
              key={tier.tier}
              className={`rf-win-tier-editor__dist-bar ${activeTier === tier.tier ? 'active' : ''}`}
              style={{
                width: `${Math.max(width, 5)}%`,
                backgroundColor: TIER_COLORS[tier.tier],
              }}
              title={`${TIER_LABELS[tier.tier]}: ${tier.minMultiplier}x - ${tier.maxMultiplier === Infinity ? '∞' : tier.maxMultiplier + 'x'}`}
            />
          );
        })}
      </div>

      {/* Tier Cards */}
      <div className="rf-win-tier-editor__cards">
        {tiers.map((tier) => (
          <TierCard
            key={tier.tier}
            config={tier}
            isActive={activeTier === tier.tier}
            isSelected={selectedTier === tier.tier}
            onClick={() => handleTierClick(tier.tier)}
            onPreview={() => onPreview?.(tier.tier)}
            onChange={handleTierChange}
          />
        ))}
      </div>

      {/* Win Multiplier Test */}
      <div className="rf-win-tier-editor__test">
        <label>Test Win Multiplier:</label>
        <input
          type="number"
          min={0}
          step={0.5}
          placeholder="Enter multiplier..."
          onChange={(e) => {
            const mult = parseFloat(e.target.value);
            if (!isNaN(mult) && mult >= 0) {
              // Find tier that contains this multiplier (inclusive on both ends)
              const matchedTier = tiers.find(
                (t) => mult >= t.minMultiplier && mult <= t.maxMultiplier
              );
              if (matchedTier) {
                onTierSelect?.(matchedTier.tier);
              } else {
                // No match - could be above max tier, select highest
                const maxTier = tiers.reduce((max, t) =>
                  t.maxMultiplier > max.maxMultiplier ? t : max
                , tiers[0]);
                if (mult > maxTier.maxMultiplier) {
                  onTierSelect?.(maxTier.tier);
                }
              }
            }
          }}
        />
        <span>x bet</span>
      </div>
    </div>
  );
});

// ============ Demo Data ============

export function generateDemoWinTiers(): WinTierConfig[] {
  return [
    {
      tier: 'small',
      minMultiplier: 0,
      maxMultiplier: 5,
      sounds: [
        { id: 'small-sting', name: 'win_sting_small', type: 'stinger' },
        { id: 'small-coins', name: 'coins_light', type: 'coins', volume: 0.5 },
      ],
      celebrationDuration: 1000,
      coinRainIntensity: 0.2,
      screenShake: false,
      flashIntensity: 0.1,
    },
    {
      tier: 'medium',
      minMultiplier: 5,
      maxMultiplier: 15,
      sounds: [
        { id: 'med-sting', name: 'win_sting_medium', type: 'stinger' },
        { id: 'med-loop', name: 'win_loop_medium', type: 'loop', fadeIn: 100 },
        { id: 'med-coins', name: 'coins_medium', type: 'coins' },
      ],
      celebrationDuration: 2000,
      coinRainIntensity: 0.4,
      screenShake: false,
      flashIntensity: 0.2,
    },
    {
      tier: 'big',
      minMultiplier: 15,
      maxMultiplier: 50,
      sounds: [
        { id: 'big-sting', name: 'win_sting_big', type: 'stinger' },
        { id: 'big-fanfare', name: 'big_win_fanfare', type: 'stinger', fadeIn: 0 },
        { id: 'big-loop', name: 'win_loop_big', type: 'loop', fadeIn: 200 },
        { id: 'big-coins', name: 'coins_heavy', type: 'coins' },
      ],
      celebrationDuration: 4000,
      coinRainIntensity: 0.7,
      screenShake: true,
      flashIntensity: 0.4,
    },
    {
      tier: 'mega',
      minMultiplier: 50,
      maxMultiplier: 100,
      sounds: [
        { id: 'mega-impact', name: 'mega_win_impact', type: 'stinger' },
        { id: 'mega-fanfare', name: 'mega_win_fanfare', type: 'stinger', fadeIn: 0 },
        { id: 'mega-loop', name: 'win_loop_mega', type: 'loop', fadeIn: 300 },
        { id: 'mega-coins', name: 'coins_cascade', type: 'coins' },
        { id: 'mega-accent', name: 'crowd_cheer', type: 'accent' },
      ],
      celebrationDuration: 6000,
      coinRainIntensity: 0.9,
      screenShake: true,
      flashIntensity: 0.6,
    },
    {
      tier: 'epic',
      minMultiplier: 100,
      maxMultiplier: Infinity,
      sounds: [
        { id: 'epic-boom', name: 'epic_win_boom', type: 'stinger' },
        { id: 'epic-fanfare', name: 'epic_win_fanfare', type: 'stinger' },
        { id: 'epic-loop', name: 'win_loop_epic', type: 'loop', fadeIn: 500 },
        { id: 'epic-coins', name: 'coins_explosion', type: 'coins' },
        { id: 'epic-crowd', name: 'crowd_roar', type: 'accent' },
        { id: 'epic-music', name: 'victory_music', type: 'loop', fadeIn: 1000 },
      ],
      celebrationDuration: 10000,
      coinRainIntensity: 1.0,
      screenShake: true,
      flashIntensity: 0.8,
    },
  ];
}

export default WinTierEditor;
