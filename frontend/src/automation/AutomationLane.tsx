/**
 * ReelForge Automation Lane
 *
 * Visual editor for parameter automation:
 * - Point-based automation curves
 * - Multiple curve types (linear, bezier, step)
 * - Real-time preview
 * - Snap to grid
 *
 * @module automation/AutomationLane
 */

import { useState, useCallback, useRef, useMemo } from 'react';
import './AutomationLane.css';

// ============ Types ============

export type CurveType = 'linear' | 'bezier' | 'step' | 'smooth';

export interface AutomationPoint {
  id: string;
  time: number;
  value: number;
  curve: CurveType;
  // Bezier control points (relative offsets)
  controlIn?: { x: number; y: number };
  controlOut?: { x: number; y: number };
}

export interface AutomationLaneData {
  id: string;
  parameterId: string;
  parameterName: string;
  trackId: string;
  color: string;
  points: AutomationPoint[];
  minValue: number;
  maxValue: number;
  defaultValue: number;
  visible: boolean;
  armed: boolean;
}

export interface AutomationLaneProps {
  /** Lane data */
  lane: AutomationLaneData;
  /** Lane width in pixels */
  width: number;
  /** Lane height in pixels */
  height: number;
  /** Pixels per second */
  pixelsPerSecond: number;
  /** Scroll offset */
  scrollLeft: number;
  /** Snap enabled */
  snapEnabled?: boolean;
  /** Snap resolution in seconds */
  snapResolution?: number;
  /** Selected point IDs */
  selectedPoints?: string[];
  /** On point add */
  onPointAdd?: (time: number, value: number) => void;
  /** On point change */
  onPointChange?: (pointId: string, updates: Partial<AutomationPoint>) => void;
  /** On point delete */
  onPointDelete?: (pointId: string) => void;
  /** On selection change */
  onSelectionChange?: (pointIds: string[]) => void;
  /** On visibility toggle */
  onVisibilityToggle?: () => void;
  /** On arm toggle */
  onArmToggle?: () => void;
}

// ============ Helpers ============

function generatePointId(): string {
  return `ap-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
}

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

// ============ Component ============

export function AutomationLane({
  lane,
  width,
  height,
  pixelsPerSecond,
  scrollLeft,
  snapEnabled = true,
  snapResolution = 0.125,
  selectedPoints = [],
  onPointAdd,
  onPointChange,
  onPointDelete,
  onSelectionChange,
  onVisibilityToggle,
  onArmToggle,
}: AutomationLaneProps) {
  const [isDragging, setIsDragging] = useState(false);
  const [dragPointId, setDragPointId] = useState<string | null>(null);
  const [hoverPoint, setHoverPoint] = useState<{ x: number; y: number } | null>(null);

  const svgRef = useRef<SVGSVGElement>(null);

  // Convert time to X pixel
  const timeToX = useCallback(
    (time: number): number => {
      return time * pixelsPerSecond - scrollLeft;
    },
    [pixelsPerSecond, scrollLeft]
  );

  // Convert X pixel to time
  const xToTime = useCallback(
    (x: number): number => {
      const time = (x + scrollLeft) / pixelsPerSecond;
      if (snapEnabled) {
        return Math.round(time / snapResolution) * snapResolution;
      }
      return time;
    },
    [pixelsPerSecond, scrollLeft, snapEnabled, snapResolution]
  );

  // Convert value to Y pixel
  const valueToY = useCallback(
    (value: number): number => {
      const normalized = (value - lane.minValue) / (lane.maxValue - lane.minValue);
      return height - normalized * height;
    },
    [height, lane.minValue, lane.maxValue]
  );

  // Convert Y pixel to value
  const yToValue = useCallback(
    (y: number): number => {
      const normalized = 1 - y / height;
      return clamp(
        lane.minValue + normalized * (lane.maxValue - lane.minValue),
        lane.minValue,
        lane.maxValue
      );
    },
    [height, lane.minValue, lane.maxValue]
  );

  // Sort points by time
  const sortedPoints = useMemo(() => {
    return [...lane.points].sort((a, b) => a.time - b.time);
  }, [lane.points]);

  // Generate SVG path for automation curve
  const curvePath = useMemo(() => {
    if (sortedPoints.length === 0) {
      // Default value line
      const y = valueToY(lane.defaultValue);
      return `M 0 ${y} L ${width} ${y}`;
    }

    const pathParts: string[] = [];

    // Start from left edge at first point's value
    const firstX = timeToX(sortedPoints[0].time);
    const firstY = valueToY(sortedPoints[0].value);

    if (firstX > 0) {
      pathParts.push(`M 0 ${firstY} L ${firstX} ${firstY}`);
    } else {
      pathParts.push(`M ${firstX} ${firstY}`);
    }

    // Draw curves between points
    for (let i = 0; i < sortedPoints.length - 1; i++) {
      const p1 = sortedPoints[i];
      const p2 = sortedPoints[i + 1];
      const x1 = timeToX(p1.time);
      const y1 = valueToY(p1.value);
      const x2 = timeToX(p2.time);
      const y2 = valueToY(p2.value);

      switch (p1.curve) {
        case 'step':
          pathParts.push(`L ${x2} ${y1} L ${x2} ${y2}`);
          break;
        case 'bezier':
          if (p1.controlOut && p2.controlIn) {
            const cx1 = x1 + p1.controlOut.x * (x2 - x1);
            const cy1 = y1 + p1.controlOut.y * (y2 - y1);
            const cx2 = x2 + p2.controlIn.x * (x2 - x1);
            const cy2 = y2 + p2.controlIn.y * (y2 - y1);
            pathParts.push(`C ${cx1} ${cy1} ${cx2} ${cy2} ${x2} ${y2}`);
          } else {
            pathParts.push(`L ${x2} ${y2}`);
          }
          break;
        case 'smooth':
          // Smooth curve using quadratic bezier
          const midX = (x1 + x2) / 2;
          pathParts.push(`Q ${midX} ${y1} ${midX} ${(y1 + y2) / 2} Q ${midX} ${y2} ${x2} ${y2}`);
          break;
        case 'linear':
        default:
          pathParts.push(`L ${x2} ${y2}`);
          break;
      }
    }

    // Extend to right edge
    const lastPoint = sortedPoints[sortedPoints.length - 1];
    const lastX = timeToX(lastPoint.time);
    const lastY = valueToY(lastPoint.value);

    if (lastX < width) {
      pathParts.push(`L ${width} ${lastY}`);
    }

    return pathParts.join(' ');
  }, [sortedPoints, timeToX, valueToY, width, lane.defaultValue]);

  // Handle mouse down on SVG
  const handleMouseDown = useCallback(
    (e: React.MouseEvent<SVGSVGElement>) => {
      if (!svgRef.current) return;
      const rect = svgRef.current.getBoundingClientRect();
      const x = e.clientX - rect.left;
      const y = e.clientY - rect.top;

      // Check if clicking on a point
      for (const point of sortedPoints) {
        const px = timeToX(point.time);
        const py = valueToY(point.value);
        const distance = Math.sqrt((x - px) ** 2 + (y - py) ** 2);

        if (distance < 8) {
          // Click on point
          setIsDragging(true);
          setDragPointId(point.id);

          if (e.ctrlKey || e.metaKey) {
            // Toggle selection
            const newSelection = selectedPoints.includes(point.id)
              ? selectedPoints.filter((id) => id !== point.id)
              : [...selectedPoints, point.id];
            onSelectionChange?.(newSelection);
          } else if (!selectedPoints.includes(point.id)) {
            // Single select
            onSelectionChange?.([point.id]);
          }
          return;
        }
      }

      // Double-click to add point
      if (e.detail === 2) {
        const time = xToTime(x);
        const value = yToValue(y);
        onPointAdd?.(time, value);
      } else {
        // Deselect
        onSelectionChange?.([]);
      }
    },
    [sortedPoints, timeToX, valueToY, xToTime, yToValue, selectedPoints, onPointAdd, onSelectionChange]
  );

  // Handle mouse move
  const handleMouseMove = useCallback(
    (e: React.MouseEvent<SVGSVGElement>) => {
      if (!svgRef.current) return;
      const rect = svgRef.current.getBoundingClientRect();
      const x = e.clientX - rect.left;
      const y = e.clientY - rect.top;

      if (isDragging && dragPointId) {
        const time = xToTime(x);
        const value = yToValue(y);
        onPointChange?.(dragPointId, { time, value });
      } else {
        setHoverPoint({ x, y });
      }
    },
    [isDragging, dragPointId, xToTime, yToValue, onPointChange]
  );

  // Handle mouse up
  const handleMouseUp = useCallback(() => {
    setIsDragging(false);
    setDragPointId(null);
  }, []);

  // Handle mouse leave
  const handleMouseLeave = useCallback(() => {
    setHoverPoint(null);
    setIsDragging(false);
    setDragPointId(null);
  }, []);

  // Handle key down for delete
  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if ((e.key === 'Delete' || e.key === 'Backspace') && selectedPoints.length > 0) {
        selectedPoints.forEach((id) => onPointDelete?.(id));
        onSelectionChange?.([]);
      }
    },
    [selectedPoints, onPointDelete, onSelectionChange]
  );

  if (!lane.visible) {
    return null;
  }

  return (
    <div
      className={`automation-lane ${lane.armed ? 'automation-lane--armed' : ''}`}
      tabIndex={0}
      onKeyDown={handleKeyDown}
    >
      {/* Header */}
      <div className="automation-lane__header">
        <button
          className="automation-lane__visibility"
          onClick={onVisibilityToggle}
          title="Toggle visibility"
        >
          👁
        </button>
        <span
          className="automation-lane__color"
          style={{ backgroundColor: lane.color }}
        />
        <span className="automation-lane__name">{lane.parameterName}</span>
        <button
          className={`automation-lane__arm ${lane.armed ? 'active' : ''}`}
          onClick={onArmToggle}
          title="Arm for recording"
        >
          R
        </button>
      </div>

      {/* Canvas */}
      <svg
        ref={svgRef}
        className="automation-lane__canvas"
        width={width}
        height={height}
        onMouseDown={handleMouseDown}
        onMouseMove={handleMouseMove}
        onMouseUp={handleMouseUp}
        onMouseLeave={handleMouseLeave}
      >
        {/* Grid lines */}
        <g className="automation-lane__grid">
          {[0.25, 0.5, 0.75].map((ratio) => (
            <line
              key={ratio}
              x1={0}
              y1={height * ratio}
              x2={width}
              y2={height * ratio}
              stroke="#333"
              strokeDasharray="4 4"
            />
          ))}
        </g>

        {/* Default value line */}
        <line
          className="automation-lane__default"
          x1={0}
          y1={valueToY(lane.defaultValue)}
          x2={width}
          y2={valueToY(lane.defaultValue)}
          stroke="#555"
          strokeDasharray="2 2"
        />

        {/* Automation curve */}
        <path
          className="automation-lane__curve"
          d={curvePath}
          fill="none"
          stroke={lane.color}
          strokeWidth={2}
        />

        {/* Fill under curve */}
        <path
          className="automation-lane__fill"
          d={`${curvePath} L ${width} ${height} L 0 ${height} Z`}
          fill={lane.color}
          fillOpacity={0.1}
        />

        {/* Points */}
        {sortedPoints.map((point) => {
          const x = timeToX(point.time);
          const y = valueToY(point.value);
          const isSelected = selectedPoints.includes(point.id);

          return (
            <g key={point.id} className="automation-lane__point">
              {/* Selection ring */}
              {isSelected && (
                <circle
                  cx={x}
                  cy={y}
                  r={8}
                  fill="none"
                  stroke="#fff"
                  strokeWidth={2}
                />
              )}
              {/* Point */}
              <circle
                cx={x}
                cy={y}
                r={5}
                fill={lane.color}
                stroke="#fff"
                strokeWidth={1}
                style={{ cursor: 'move' }}
              />
            </g>
          );
        })}

        {/* Hover preview */}
        {hoverPoint && !isDragging && (
          <circle
            cx={hoverPoint.x}
            cy={hoverPoint.y}
            r={4}
            fill={lane.color}
            fillOpacity={0.3}
            stroke={lane.color}
            strokeDasharray="2 2"
          />
        )}
      </svg>
    </div>
  );
}

// ============ Utility Exports ============

export { generatePointId };

export default AutomationLane;
