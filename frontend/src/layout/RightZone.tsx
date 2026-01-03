/**
 * ReelForge Right Zone (Inspector)
 *
 * Property inspector with collapsible sections:
 * - General (name, category, priority)
 * - Playback (volume, pitch, filters)
 * - Routing (bus, sends)
 * - RTPC (game parameters)
 * - States (state groups)
 * - Advanced (scope, 3D settings)
 *
 * @module layout/RightZone
 */

import { memo, useState, useCallback, type ReactNode } from 'react';

// ============ Types ============

export type InspectedObjectType = 'event' | 'command' | 'sound' | 'bus' | 'none';

export interface InspectorSection {
  id: string;
  title: string;
  defaultExpanded?: boolean;
  content: ReactNode;
}

export interface RightZoneProps {
  /** Whether zone is collapsed */
  collapsed?: boolean;
  /** Type of inspected object */
  objectType: InspectedObjectType;
  /** Object name/title */
  objectName?: string;
  /** Inspector sections */
  sections: InspectorSection[];
  /** On collapse toggle */
  onToggleCollapse?: () => void;
}

// ============ Section Component ============

interface SectionProps {
  id: string;
  title: string;
  expanded: boolean;
  onToggle: () => void;
  children: ReactNode;
}

const Section = memo(function Section({
  title,
  expanded,
  onToggle,
  children,
}: SectionProps) {
  return (
    <div className={`rf-inspector-section ${expanded ? 'expanded' : ''}`}>
      <div className="rf-inspector-section__header" onClick={onToggle}>
        <span className="rf-inspector-section__expand">▶</span>
        <span className="rf-inspector-section__title">{title}</span>
      </div>
      <div className="rf-inspector-section__content">{children}</div>
    </div>
  );
});

// ============ Field Components ============

export interface TextFieldProps {
  label: string;
  value: string;
  onChange?: (value: string) => void;
  placeholder?: string;
  disabled?: boolean;
}

export const TextField = memo(function TextField({
  label,
  value,
  onChange,
  placeholder,
  disabled,
}: TextFieldProps) {
  return (
    <div className="rf-field">
      <label className="rf-field__label">{label}</label>
      <input
        type="text"
        className="rf-field__input"
        value={value}
        onChange={(e) => onChange?.(e.target.value)}
        placeholder={placeholder}
        disabled={disabled}
      />
    </div>
  );
});

export interface SelectFieldProps {
  label: string;
  value: string;
  options: { value: string; label: string }[];
  onChange?: (value: string) => void;
  disabled?: boolean;
}

export const SelectField = memo(function SelectField({
  label,
  value,
  options,
  onChange,
  disabled,
}: SelectFieldProps) {
  return (
    <div className="rf-field">
      <label className="rf-field__label">{label}</label>
      <select
        className="rf-field__input"
        value={value}
        onChange={(e) => onChange?.(e.target.value)}
        disabled={disabled}
      >
        {options.map((opt) => (
          <option key={opt.value} value={opt.value}>
            {opt.label}
          </option>
        ))}
      </select>
    </div>
  );
});

export interface SliderFieldProps {
  label: string;
  value: number;
  min: number;
  max: number;
  step?: number;
  unit?: string;
  onChange?: (value: number) => void;
  formatValue?: (value: number) => string;
  disabled?: boolean;
  /** Default value for double-click reset. If not provided, uses min for bipolar (min < 0), or min for unipolar */
  defaultValue?: number;
}

export const SliderField = memo(function SliderField({
  label,
  value,
  min,
  max,
  step = 1,
  unit = '',
  onChange,
  formatValue,
  disabled,
  defaultValue,
}: SliderFieldProps) {
  const percentage = ((value - min) / (max - min)) * 100;
  const displayValue = formatValue ? formatValue(value) : value.toString();

  // Calculate default for reset: 0 for bipolar sliders, min for unipolar
  const resetValue = defaultValue ?? (min < 0 && max > 0 ? 0 : min);

  const handleDoubleClick = () => {
    if (!disabled && onChange) {
      onChange(resetValue);
    }
  };

  return (
    <div className="rf-field">
      <label className="rf-field__label">{label}</label>
      <div className="rf-slider" onDoubleClick={handleDoubleClick} title="Double-click to reset">
        <div className="rf-slider__track">
          <div className="rf-slider__fill" style={{ width: `${percentage}%` }} />
          <input
            type="range"
            min={min}
            max={max}
            step={step}
            value={value}
            onChange={(e) => onChange?.(parseFloat(e.target.value))}
            disabled={disabled}
            style={{
              position: 'absolute',
              top: 0,
              left: 0,
              width: '100%',
              height: '100%',
              opacity: 0,
              cursor: disabled ? 'default' : 'pointer',
            }}
          />
          <div
            className="rf-slider__thumb"
            style={{ left: `${percentage}%` }}
          />
        </div>
        <span className="rf-slider__value">
          {displayValue}{unit}
        </span>
      </div>
    </div>
  );
});

export interface CheckboxFieldProps {
  label: string;
  checked: boolean;
  onChange?: (checked: boolean) => void;
  disabled?: boolean;
}

export const CheckboxField = memo(function CheckboxField({
  label,
  checked,
  onChange,
  disabled,
}: CheckboxFieldProps) {
  return (
    <div className="rf-field" style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
      <input
        type="checkbox"
        checked={checked}
        onChange={(e) => onChange?.(e.target.checked)}
        disabled={disabled}
        style={{ width: 16, height: 16 }}
      />
      <label className="rf-field__label" style={{ marginBottom: 0 }}>
        {label}
      </label>
    </div>
  );
});

// ============ Object Type Icons ============

const TYPE_ICONS: Record<InspectedObjectType, string> = {
  event: '🎯',
  command: '▶',
  sound: '🔊',
  bus: '🔈',
  none: '',
};

// ============ Right Zone Component ============

export const RightZone = memo(function RightZone({
  collapsed = false,
  objectType,
  objectName,
  sections,
  onToggleCollapse,
}: RightZoneProps) {
  // Track which sections are expanded
  const [expandedSections, setExpandedSections] = useState<Set<string>>(() => {
    return new Set(
      sections.filter((s) => s.defaultExpanded !== false).map((s) => s.id)
    );
  });

  const toggleSection = useCallback((id: string) => {
    setExpandedSections((prev) => {
      const next = new Set(prev);
      if (next.has(id)) {
        next.delete(id);
      } else {
        next.add(id);
      }
      return next;
    });
  }, []);

  if (collapsed) {
    return null;
  }

  return (
    <div className="rf-right-zone rf-scrollbar">
      {/* Header */}
      <div className="rf-zone-header">
        <span className="rf-zone-header__title">Inspector</span>
        <div className="rf-zone-header__actions">
          {onToggleCollapse && (
            <button
              className="rf-zone-header__btn"
              onClick={onToggleCollapse}
              title="Collapse Zone"
            >
              ▶
            </button>
          )}
        </div>
      </div>

      {/* Inspector Content */}
      <div className="rf-inspector rf-scrollbar">
        {objectType === 'none' ? (
          <div className="rf-inspector__empty">
            <span className="rf-inspector__empty-icon">📋</span>
            <span>Select an object to inspect</span>
          </div>
        ) : (
          <>
            {/* Object Header */}
            {objectName && (
              <div
                style={{
                  padding: '12px',
                  borderBottom: '1px solid var(--rf-border)',
                  display: 'flex',
                  alignItems: 'center',
                  gap: 8,
                }}
              >
                <span style={{ fontSize: 18 }}>{TYPE_ICONS[objectType]}</span>
                <span
                  style={{
                    fontSize: 13,
                    fontWeight: 600,
                    color: 'var(--rf-text-primary)',
                  }}
                >
                  {objectName}
                </span>
              </div>
            )}

            {/* Sections */}
            {sections.map((section) => (
              <Section
                key={section.id}
                id={section.id}
                title={section.title}
                expanded={expandedSections.has(section.id)}
                onToggle={() => toggleSection(section.id)}
              >
                {section.content}
              </Section>
            ))}
          </>
        )}
      </div>
    </div>
  );
});

export default RightZone;
