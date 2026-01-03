/**
 * ReelForge Steps
 *
 * Stepper/wizard component:
 * - Horizontal and vertical
 * - Numbered and icon steps
 * - Clickable navigation
 * - Status indicators
 *
 * @module steps/Steps
 */

import './Steps.css';

// ============ Types ============

export type StepStatus = 'pending' | 'current' | 'completed' | 'error';

export interface StepItem {
  /** Step title */
  title: string;
  /** Step description */
  description?: string;
  /** Custom icon */
  icon?: React.ReactNode;
  /** Disabled */
  disabled?: boolean;
}

export interface StepsProps {
  /** Steps data */
  items: StepItem[];
  /** Current step (0-indexed) */
  current: number;
  /** On step change */
  onChange?: (step: number) => void;
  /** Orientation */
  orientation?: 'horizontal' | 'vertical';
  /** Size */
  size?: 'small' | 'medium';
  /** Allow clicking on steps */
  clickable?: boolean;
  /** Custom class */
  className?: string;
}

// ============ Step Component ============

interface StepProps {
  item: StepItem;
  index: number;
  status: StepStatus;
  isLast: boolean;
  size: 'small' | 'medium';
  orientation: 'horizontal' | 'vertical';
  clickable: boolean;
  onClick?: () => void;
}

function Step({
  item,
  index,
  status,
  isLast,
  size,
  orientation,
  clickable,
  onClick,
}: StepProps) {
  const canClick = clickable && !item.disabled && status !== 'current';

  return (
    <div
      className={`step step--${status} step--${size} ${item.disabled ? 'step--disabled' : ''} ${
        canClick ? 'step--clickable' : ''
      }`}
      onClick={canClick ? onClick : undefined}
      role={canClick ? 'button' : undefined}
      tabIndex={canClick ? 0 : undefined}
      onKeyDown={
        canClick
          ? (e) => {
              if (e.key === 'Enter' || e.key === ' ') {
                e.preventDefault();
                onClick?.();
              }
            }
          : undefined
      }
    >
      {/* Indicator */}
      <div className="step__indicator">
        {item.icon ? (
          <span className="step__icon">{item.icon}</span>
        ) : status === 'completed' ? (
          <span className="step__check">✓</span>
        ) : status === 'error' ? (
          <span className="step__error">!</span>
        ) : (
          <span className="step__number">{index + 1}</span>
        )}
      </div>

      {/* Content */}
      <div className="step__content">
        <div className="step__title">{item.title}</div>
        {item.description && (
          <div className="step__description">{item.description}</div>
        )}
      </div>

      {/* Connector */}
      {!isLast && (
        <div
          className={`step__connector step__connector--${orientation} ${
            status === 'completed' ? 'step__connector--completed' : ''
          }`}
        />
      )}
    </div>
  );
}

// ============ Main Component ============

export function Steps({
  items,
  current,
  onChange,
  orientation = 'horizontal',
  size = 'medium',
  clickable = false,
  className = '',
}: StepsProps) {
  const getStatus = (index: number): StepStatus => {
    if (index < current) return 'completed';
    if (index === current) return 'current';
    return 'pending';
  };

  return (
    <div
      className={`steps steps--${orientation} steps--${size} ${className}`}
      role="navigation"
      aria-label="Progress"
    >
      {items.map((item, index) => (
        <Step
          key={index}
          item={item}
          index={index}
          status={getStatus(index)}
          isLast={index === items.length - 1}
          size={size}
          orientation={orientation}
          clickable={clickable}
          onClick={() => onChange?.(index)}
        />
      ))}
    </div>
  );
}

// ============ Step Content Container ============

export interface StepContentProps {
  /** Current step index */
  current: number;
  /** Children (should be step panels) */
  children: React.ReactNode[];
  /** Custom class */
  className?: string;
}

export function StepContent({ current, children, className = '' }: StepContentProps) {
  return (
    <div className={`step-content ${className}`}>
      {children[current]}
    </div>
  );
}

export default Steps;
