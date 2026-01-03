/**
 * ReelForge Descriptions
 *
 * Key-value display list:
 * - Multiple columns
 * - Bordered/borderless
 * - Custom label width
 * - Responsive layout
 *
 * @module descriptions/Descriptions
 */

import './Descriptions.css';

// ============ Types ============

export interface DescriptionItem {
  key?: string;
  label: React.ReactNode;
  children: React.ReactNode;
  span?: number;
}

export interface DescriptionsProps {
  /** Title */
  title?: React.ReactNode;
  /** Extra content */
  extra?: React.ReactNode;
  /** Items */
  items: DescriptionItem[];
  /** Number of columns */
  column?: number;
  /** Bordered style */
  bordered?: boolean;
  /** Size */
  size?: 'small' | 'default' | 'large';
  /** Layout direction */
  layout?: 'horizontal' | 'vertical';
  /** Label width */
  labelWidth?: number | string;
  /** Colon after label */
  colon?: boolean;
  /** Custom class */
  className?: string;
}

// ============ Descriptions Component ============

export function Descriptions({
  title,
  extra,
  items,
  column = 3,
  bordered = false,
  size = 'default',
  layout = 'horizontal',
  labelWidth,
  colon = true,
  className = '',
}: DescriptionsProps) {
  // Group items into rows
  const rows: DescriptionItem[][] = [];
  let currentRow: DescriptionItem[] = [];
  let currentSpan = 0;

  for (const item of items) {
    const span = item.span || 1;

    if (currentSpan + span > column) {
      if (currentRow.length > 0) {
        rows.push(currentRow);
      }
      currentRow = [item];
      currentSpan = span;
    } else {
      currentRow.push(item);
      currentSpan += span;
    }
  }

  if (currentRow.length > 0) {
    rows.push(currentRow);
  }

  const labelStyle = labelWidth
    ? { width: typeof labelWidth === 'number' ? `${labelWidth}px` : labelWidth }
    : undefined;

  return (
    <div
      className={`descriptions descriptions--${size} descriptions--${layout} ${
        bordered ? 'descriptions--bordered' : ''
      } ${className}`}
    >
      {(title || extra) && (
        <div className="descriptions__header">
          {title && <div className="descriptions__title">{title}</div>}
          {extra && <div className="descriptions__extra">{extra}</div>}
        </div>
      )}

      <div className="descriptions__body">
        {bordered ? (
          <table className="descriptions__table">
            <tbody>
              {rows.map((row, rowIndex) => (
                <tr key={rowIndex} className="descriptions__row">
                  {row.map((item, itemIndex) => (
                    layout === 'horizontal' ? (
                      <>
                        <th
                          key={`label-${item.key || itemIndex}`}
                          className="descriptions__cell descriptions__cell--label"
                          style={labelStyle}
                        >
                          {item.label}
                          {colon && ':'}
                        </th>
                        <td
                          key={`content-${item.key || itemIndex}`}
                          className="descriptions__cell descriptions__cell--content"
                          colSpan={(item.span || 1) * 2 - 1}
                        >
                          {item.children}
                        </td>
                      </>
                    ) : (
                      <td
                        key={item.key || itemIndex}
                        className="descriptions__cell descriptions__cell--vertical"
                        colSpan={item.span || 1}
                      >
                        <div className="descriptions__label" style={labelStyle}>
                          {item.label}
                          {colon && ':'}
                        </div>
                        <div className="descriptions__content">{item.children}</div>
                      </td>
                    )
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        ) : (
          <div
            className="descriptions__list"
            style={{ gridTemplateColumns: `repeat(${column}, 1fr)` }}
          >
            {items.map((item, index) => (
              <div
                key={item.key || index}
                className={`descriptions__item ${
                  layout === 'vertical' ? 'descriptions__item--vertical' : ''
                }`}
                style={{ gridColumn: item.span ? `span ${item.span}` : undefined }}
              >
                <div className="descriptions__label" style={labelStyle}>
                  {item.label}
                  {colon && ':'}
                </div>
                <div className="descriptions__content">{item.children}</div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

// ============ DescriptionsItem Component ============

export interface DescriptionsItemProps extends DescriptionItem {
  children: React.ReactNode;
}

export function DescriptionsItem({ children }: DescriptionsItemProps) {
  return <>{children}</>;
}

export default Descriptions;
