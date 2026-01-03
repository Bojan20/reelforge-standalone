/**
 * ReelForge AspectRatio
 *
 * Aspect ratio container:
 * - Common presets
 * - Custom ratios
 * - Responsive scaling
 *
 * @module aspect-ratio/AspectRatio
 */

import './AspectRatio.css';

// ============ Types ============

export type AspectRatioPreset = '1:1' | '4:3' | '16:9' | '21:9' | '3:2' | '2:3' | '9:16';

export interface AspectRatioProps {
  /** Aspect ratio as preset or number (width/height) */
  ratio: AspectRatioPreset | number;
  /** Children content */
  children: React.ReactNode;
  /** Custom class */
  className?: string;
}

// ============ Preset Ratios ============

const RATIO_VALUES: Record<AspectRatioPreset, number> = {
  '1:1': 1,
  '4:3': 4 / 3,
  '16:9': 16 / 9,
  '21:9': 21 / 9,
  '3:2': 3 / 2,
  '2:3': 2 / 3,
  '9:16': 9 / 16,
};

// ============ Component ============

export function AspectRatio({ ratio, children, className = '' }: AspectRatioProps) {
  const ratioValue = typeof ratio === 'number' ? ratio : RATIO_VALUES[ratio];
  const paddingBottom = `${(1 / ratioValue) * 100}%`;

  return (
    <div className={`aspect-ratio ${className}`} style={{ paddingBottom }}>
      <div className="aspect-ratio__content">{children}</div>
    </div>
  );
}

export default AspectRatio;
