/**
 * ReelForge GPU Automation Curve Renderer
 *
 * WebGL-accelerated automation curve visualization:
 * - GPU-rendered curves with anti-aliasing
 * - Smooth bezier interpolation
 * - Point dragging with snap
 * - Zoom and pan support
 * - Real-time recording preview
 *
 * @module automation/AutomationCurveGPU
 */

import { useRef, useEffect, useCallback, useState, useMemo } from 'react';
import * as PIXI from 'pixi.js';
import type { AutomationPoint } from './AutomationLane';

// ============ Types ============

export interface AutomationCurveGPUProps {
  /** Width in pixels */
  width: number;
  /** Height in pixels */
  height: number;
  /** Automation points */
  points: AutomationPoint[];
  /** Min value */
  minValue: number;
  /** Max value */
  maxValue: number;
  /** Default value */
  defaultValue: number;
  /** Curve color */
  color: number;
  /** Fill opacity (0-1) */
  fillOpacity?: number;
  /** Pixels per second */
  pixelsPerSecond: number;
  /** Time offset (scroll) */
  timeOffset?: number;
  /** Show grid */
  showGrid?: boolean;
  /** Show value labels */
  showLabels?: boolean;
  /** Selected point IDs */
  selectedPoints?: Set<string>;
  /** Snap enabled */
  snapEnabled?: boolean;
  /** Snap resolution (seconds) */
  snapResolution?: number;
  /** On point add */
  onPointAdd?: (time: number, value: number) => void;
  /** On point move */
  onPointMove?: (id: string, time: number, value: number) => void;
  /** On point select */
  onPointSelect?: (id: string, multi: boolean) => void;
  /** On point delete */
  onPointDelete?: (id: string) => void;
  /** Recording mode */
  recording?: boolean;
  /** Playhead position (seconds) */
  playhead?: number;
  /** Custom class */
  className?: string;
}

// ============ Constants ============

const POINT_RADIUS = 5;
const POINT_HIT_RADIUS = 10;
const GRID_COLOR = 0x2a2a2a;
const DEFAULT_LINE_COLOR = 0x555555;

// ============ Bezier Helpers ============

function bezierPoint(
  t: number,
  p0: { x: number; y: number },
  p1: { x: number; y: number },
  p2: { x: number; y: number },
  p3: { x: number; y: number }
): { x: number; y: number } {
  const t2 = t * t;
  const t3 = t2 * t;
  const mt = 1 - t;
  const mt2 = mt * mt;
  const mt3 = mt2 * mt;

  return {
    x: mt3 * p0.x + 3 * mt2 * t * p1.x + 3 * mt * t2 * p2.x + t3 * p3.x,
    y: mt3 * p0.y + 3 * mt2 * t * p1.y + 3 * mt * t2 * p2.y + t3 * p3.y,
  };
}

// ============ Component ============

export function AutomationCurveGPU({
  width,
  height,
  points,
  minValue,
  maxValue,
  defaultValue,
  color,
  fillOpacity = 0.15,
  pixelsPerSecond,
  timeOffset = 0,
  showGrid = true,
  showLabels: _showLabels = false,
  selectedPoints = new Set(),
  snapEnabled = true,
  snapResolution = 0.125,
  onPointAdd,
  onPointMove,
  onPointSelect,
  onPointDelete,
  recording = false,
  playhead,
  className,
}: AutomationCurveGPUProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const appRef = useRef<PIXI.Application | null>(null);
  const graphicsRef = useRef<{
    grid: PIXI.Graphics;
    curve: PIXI.Graphics;
    fill: PIXI.Graphics;
    points: PIXI.Container;
    playhead: PIXI.Graphics;
  } | null>(null);

  const [isDragging, setIsDragging] = useState(false);
  const [dragPointId, setDragPointId] = useState<string | null>(null);

  // Sort points by time
  const sortedPoints = useMemo(() => {
    return [...points].sort((a, b) => a.time - b.time);
  }, [points]);

  // Convert time to X
  const timeToX = useCallback(
    (time: number): number => {
      return (time - timeOffset) * pixelsPerSecond;
    },
    [timeOffset, pixelsPerSecond]
  );

  // Convert X to time
  const xToTime = useCallback(
    (x: number): number => {
      const time = x / pixelsPerSecond + timeOffset;
      if (snapEnabled) {
        return Math.round(time / snapResolution) * snapResolution;
      }
      return Math.max(0, time);
    },
    [pixelsPerSecond, timeOffset, snapEnabled, snapResolution]
  );

  // Convert value to Y
  const valueToY = useCallback(
    (value: number): number => {
      const range = maxValue - minValue;
      const normalized = (value - minValue) / range;
      return height - normalized * height;
    },
    [height, minValue, maxValue]
  );

  // Convert Y to value
  const yToValue = useCallback(
    (y: number): number => {
      const normalized = 1 - y / height;
      const range = maxValue - minValue;
      return Math.max(minValue, Math.min(maxValue, minValue + normalized * range));
    },
    [height, minValue, maxValue]
  );

  // Initialize PixiJS
  useEffect(() => {
    if (!containerRef.current || appRef.current) return;

    const app = new PIXI.Application();

    (async () => {
      await app.init({
        width,
        height,
        backgroundColor: 0x1a1a1a,
        antialias: true,
        resolution: window.devicePixelRatio || 1,
        autoDensity: true,
      });

      if (containerRef.current) {
        containerRef.current.appendChild(app.canvas as HTMLCanvasElement);
      }

      const grid = new PIXI.Graphics();
      const fill = new PIXI.Graphics();
      const curve = new PIXI.Graphics();
      const pointsContainer = new PIXI.Container();
      const playheadGraphics = new PIXI.Graphics();

      app.stage.addChild(grid);
      app.stage.addChild(fill);
      app.stage.addChild(curve);
      app.stage.addChild(pointsContainer);
      app.stage.addChild(playheadGraphics);

      appRef.current = app;
      graphicsRef.current = {
        grid,
        curve,
        fill,
        points: pointsContainer,
        playhead: playheadGraphics,
      };
    })();

    return () => {
      if (appRef.current) {
        appRef.current.destroy(true, { children: true });
        appRef.current = null;
      }
    };
  }, []);

  // Resize
  useEffect(() => {
    if (appRef.current) {
      appRef.current.renderer.resize(width, height);
    }
  }, [width, height]);

  // Draw everything
  const draw = useCallback(() => {
    const g = graphicsRef.current;
    if (!g) return;

    // Clear all
    g.grid.clear();
    g.curve.clear();
    g.fill.clear();
    g.playhead.clear();
    g.points.removeChildren();

    // Draw grid
    if (showGrid) {
      g.grid.setStrokeStyle({ width: 1, color: GRID_COLOR });

      // Horizontal lines (value divisions)
      for (let i = 0; i <= 4; i++) {
        const y = (i / 4) * height;
        g.grid.moveTo(0, y);
        g.grid.lineTo(width, y);
      }

      // Vertical lines (time divisions)
      const startTime = timeOffset;
      const endTime = timeOffset + width / pixelsPerSecond;
      const gridStep = 1; // 1 second

      for (let t = Math.ceil(startTime / gridStep) * gridStep; t <= endTime; t += gridStep) {
        const x = timeToX(t);
        g.grid.moveTo(x, 0);
        g.grid.lineTo(x, height);
      }
      g.grid.stroke();
    }

    // Draw default value line
    const defaultY = valueToY(defaultValue);
    g.grid.setStrokeStyle({ width: 1, color: DEFAULT_LINE_COLOR });
    g.grid.moveTo(0, defaultY);
    g.grid.lineTo(width, defaultY);
    g.grid.stroke();

    // Draw curve
    if (sortedPoints.length === 0) {
      // Just default line
      g.curve.setStrokeStyle({ width: 2, color });
      g.curve.moveTo(0, defaultY);
      g.curve.lineTo(width, defaultY);
      g.curve.stroke();
    } else {
      // Build path
      const pathPoints: { x: number; y: number }[] = [];

      // Start from left edge
      const firstX = timeToX(sortedPoints[0].time);
      const firstY = valueToY(sortedPoints[0].value);

      if (firstX > 0) {
        pathPoints.push({ x: 0, y: firstY });
      }
      pathPoints.push({ x: firstX, y: firstY });

      // Generate curve points
      for (let i = 0; i < sortedPoints.length - 1; i++) {
        const p1 = sortedPoints[i];
        const p2 = sortedPoints[i + 1];
        const x1 = timeToX(p1.time);
        const y1 = valueToY(p1.value);
        const x2 = timeToX(p2.time);
        const y2 = valueToY(p2.value);

        switch (p1.curve) {
          case 'step':
            pathPoints.push({ x: x2, y: y1 });
            pathPoints.push({ x: x2, y: y2 });
            break;
          case 'bezier':
            if (p1.controlOut && p2.controlIn) {
              const cp1 = {
                x: x1 + p1.controlOut.x * (x2 - x1),
                y: y1 + p1.controlOut.y * (y2 - y1),
              };
              const cp2 = {
                x: x2 + p2.controlIn.x * (x2 - x1),
                y: y2 + p2.controlIn.y * (y2 - y1),
              };
              // Sample bezier
              for (let t = 0.1; t <= 1; t += 0.1) {
                const pt = bezierPoint(t, { x: x1, y: y1 }, cp1, cp2, { x: x2, y: y2 });
                pathPoints.push(pt);
              }
            } else {
              pathPoints.push({ x: x2, y: y2 });
            }
            break;
          case 'smooth':
            // Smooth curve
            const midX = (x1 + x2) / 2;
            const midY = (y1 + y2) / 2;
            pathPoints.push({ x: midX, y: y1 });
            pathPoints.push({ x: midX, y: midY });
            pathPoints.push({ x: midX, y: y2 });
            pathPoints.push({ x: x2, y: y2 });
            break;
          case 'linear':
          default:
            pathPoints.push({ x: x2, y: y2 });
            break;
        }
      }

      // Extend to right edge
      const lastY = valueToY(sortedPoints[sortedPoints.length - 1].value);
      if (pathPoints[pathPoints.length - 1].x < width) {
        pathPoints.push({ x: width, y: lastY });
      }

      // Draw fill
      g.fill.beginFill(color, fillOpacity);
      g.fill.moveTo(pathPoints[0].x, height);
      for (const pt of pathPoints) {
        g.fill.lineTo(pt.x, pt.y);
      }
      g.fill.lineTo(pathPoints[pathPoints.length - 1].x, height);
      g.fill.closePath();
      g.fill.endFill();

      // Draw curve line
      g.curve.setStrokeStyle({ width: 2, color });
      g.curve.moveTo(pathPoints[0].x, pathPoints[0].y);
      for (let i = 1; i < pathPoints.length; i++) {
        g.curve.lineTo(pathPoints[i].x, pathPoints[i].y);
      }
      g.curve.stroke();

      // Draw points
      for (const point of sortedPoints) {
        const x = timeToX(point.time);
        const y = valueToY(point.value);
        const isSelected = selectedPoints.has(point.id);

        const pointGfx = new PIXI.Graphics();

        // Selection ring
        if (isSelected) {
          pointGfx.setStrokeStyle({ width: 2, color: 0xffffff });
          pointGfx.circle(x, y, POINT_RADIUS + 3);
          pointGfx.stroke();
        }

        // Point fill
        pointGfx.beginFill(color);
        pointGfx.circle(x, y, POINT_RADIUS);
        pointGfx.endFill();

        // Point stroke
        pointGfx.setStrokeStyle({ width: 1, color: 0xffffff });
        pointGfx.circle(x, y, POINT_RADIUS);
        pointGfx.stroke();

        g.points.addChild(pointGfx);
      }
    }

    // Draw playhead
    if (playhead !== undefined) {
      const playheadX = timeToX(playhead);
      if (playheadX >= 0 && playheadX <= width) {
        g.playhead.setStrokeStyle({ width: 1, color: recording ? 0xff4444 : 0xffffff });
        g.playhead.moveTo(playheadX, 0);
        g.playhead.lineTo(playheadX, height);
        g.playhead.stroke();
      }
    }
  }, [
    width, height, sortedPoints, color, fillOpacity, pixelsPerSecond, timeOffset,
    showGrid, defaultValue, selectedPoints, playhead, recording,
    timeToX, valueToY,
  ]);

  // Animation loop
  useEffect(() => {
    let animationId: number;

    const animate = () => {
      draw();
      animationId = requestAnimationFrame(animate);
    };

    animate();

    return () => {
      cancelAnimationFrame(animationId);
    };
  }, [draw]);

  // Mouse handlers
  const handleMouseDown = useCallback(
    (e: React.MouseEvent) => {
      if (!containerRef.current) return;
      const rect = containerRef.current.getBoundingClientRect();
      const x = e.clientX - rect.left;
      const y = e.clientY - rect.top;

      // Check if clicking on a point
      for (const point of sortedPoints) {
        const px = timeToX(point.time);
        const py = valueToY(point.value);
        const distance = Math.sqrt((x - px) ** 2 + (y - py) ** 2);

        if (distance < POINT_HIT_RADIUS) {
          setIsDragging(true);
          setDragPointId(point.id);
          onPointSelect?.(point.id, e.ctrlKey || e.metaKey);
          return;
        }
      }

      // Double-click to add point
      if (e.detail === 2) {
        const time = xToTime(x);
        const value = yToValue(y);
        onPointAdd?.(time, value);
      }
    },
    [sortedPoints, timeToX, valueToY, xToTime, yToValue, onPointAdd, onPointSelect]
  );

  const handleMouseMove = useCallback(
    (e: React.MouseEvent) => {
      if (!isDragging || !dragPointId || !containerRef.current) return;

      const rect = containerRef.current.getBoundingClientRect();
      const x = e.clientX - rect.left;
      const y = e.clientY - rect.top;

      const time = xToTime(x);
      const value = yToValue(y);
      onPointMove?.(dragPointId, time, value);
    },
    [isDragging, dragPointId, xToTime, yToValue, onPointMove]
  );

  const handleMouseUp = useCallback(() => {
    setIsDragging(false);
    setDragPointId(null);
  }, []);

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if ((e.key === 'Delete' || e.key === 'Backspace') && selectedPoints.size > 0) {
        selectedPoints.forEach((id) => onPointDelete?.(id));
      }
    },
    [selectedPoints, onPointDelete]
  );

  return (
    <div
      ref={containerRef}
      className={`automation-curve-gpu ${recording ? 'recording' : ''} ${className ?? ''}`}
      style={{ width, height, cursor: isDragging ? 'grabbing' : 'crosshair' }}
      onMouseDown={handleMouseDown}
      onMouseMove={handleMouseMove}
      onMouseUp={handleMouseUp}
      onMouseLeave={handleMouseUp}
      onKeyDown={handleKeyDown}
      tabIndex={0}
    />
  );
}

export default AutomationCurveGPU;
