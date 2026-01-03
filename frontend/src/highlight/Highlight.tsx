/**
 * ReelForge Highlight
 *
 * Text highlighting:
 * - Search term highlighting
 * - Multiple colors
 * - Case sensitivity
 *
 * @module highlight/Highlight
 */

import './Highlight.css';

// ============ Types ============

export type HighlightColor = 'yellow' | 'green' | 'blue' | 'red' | 'purple' | 'orange';

export interface HighlightProps {
  /** Text to highlight */
  children: string;
  /** Search term(s) */
  query: string | string[];
  /** Highlight color */
  color?: HighlightColor;
  /** Case sensitive search */
  caseSensitive?: boolean;
  /** Custom class for highlights */
  className?: string;
}

export interface MarkProps {
  /** Content to mark */
  children: React.ReactNode;
  /** Color */
  color?: HighlightColor;
  /** Custom class */
  className?: string;
}

// ============ Mark Component ============

export function Mark({ children, color = 'yellow', className = '' }: MarkProps) {
  return (
    <mark className={`mark mark--${color} ${className}`}>
      {children}
    </mark>
  );
}

// ============ Highlight Component ============

export function Highlight({
  children,
  query,
  color = 'yellow',
  caseSensitive = false,
  className = '',
}: HighlightProps) {
  if (!query || (Array.isArray(query) && query.length === 0)) {
    return <>{children}</>;
  }

  const queries = Array.isArray(query) ? query : [query];
  const filteredQueries = queries.filter((q) => q.length > 0);

  if (filteredQueries.length === 0) {
    return <>{children}</>;
  }

  // Escape special regex characters
  const escapeRegex = (str: string) =>
    str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

  const pattern = filteredQueries.map(escapeRegex).join('|');
  const flags = caseSensitive ? 'g' : 'gi';
  const regex = new RegExp(`(${pattern})`, flags);

  const parts = children.split(regex);

  return (
    <>
      {parts.map((part, index) => {
        const isMatch = filteredQueries.some((q) =>
          caseSensitive ? part === q : part.toLowerCase() === q.toLowerCase()
        );

        if (isMatch) {
          return (
            <Mark key={index} color={color} className={className}>
              {part}
            </Mark>
          );
        }

        return part;
      })}
    </>
  );
}

// ============ Multi-color Highlight ============

export interface MultiHighlightItem {
  query: string;
  color: HighlightColor;
}

export interface MultiHighlightProps {
  /** Text to highlight */
  children: string;
  /** Highlight items */
  items: MultiHighlightItem[];
  /** Case sensitive */
  caseSensitive?: boolean;
}

export function MultiHighlight({
  children,
  items,
  caseSensitive = false,
}: MultiHighlightProps) {
  if (items.length === 0) {
    return <>{children}</>;
  }

  const filteredItems = items.filter((item) => item.query.length > 0);

  if (filteredItems.length === 0) {
    return <>{children}</>;
  }

  // Build regex for all queries
  const escapeRegex = (str: string) =>
    str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

  const pattern = filteredItems.map((item) => escapeRegex(item.query)).join('|');
  const flags = caseSensitive ? 'g' : 'gi';
  const regex = new RegExp(`(${pattern})`, flags);

  const parts = children.split(regex);

  return (
    <>
      {parts.map((part, index) => {
        const matchedItem = filteredItems.find((item) =>
          caseSensitive
            ? part === item.query
            : part.toLowerCase() === item.query.toLowerCase()
        );

        if (matchedItem) {
          return (
            <Mark key={index} color={matchedItem.color}>
              {part}
            </Mark>
          );
        }

        return part;
      })}
    </>
  );
}

export default Highlight;
