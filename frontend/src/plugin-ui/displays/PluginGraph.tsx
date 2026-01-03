/**
 * Plugin Graph Component
 *
 * Simple graph display for frequency response, transfer curves, etc.
 *
 * @module plugin-ui/displays/PluginGraph
 */

import { useRef, useEffect, memo } from 'react';
import { usePluginTheme } from '../usePluginTheme';
import './PluginGraph.css';

export interface PluginGraphProps {
  /** Width in pixels */
  width: number;
  /** Height in pixels */
  height: number;
  /** Data points (normalized 0-1) */
  data?: number[];
  /** X axis range */
  xRange?: [number, number];
  /** Y axis range */
  yRange?: [number, number];
  /** Show grid */
  showGrid?: boolean;
  /** Grid divisions X */
  gridX?: number;
  /** Grid divisions Y */
  gridY?: number;
  /** Line color override */
  lineColor?: string;
  /** Fill below line */
  fill?: boolean;
  /** Line width */
  lineWidth?: number;
  /** Custom draw function */
  onDraw?: (ctx: CanvasRenderingContext2D, width: number, height: number) => void;
  /** Custom class */
  className?: string;
}

function PluginGraphInner({
  width,
  height,
  data,
  xRange: _xRange = [0, 1],
  yRange: _yRange = [0, 1],
  showGrid = true,
  gridX = 10,
  gridY = 5,
  lineColor,
  fill = true,
  lineWidth = 2,
  onDraw,
  className,
}: PluginGraphProps) {
  const theme = usePluginTheme();
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const dpr = window.devicePixelRatio || 1;
    canvas.width = width * dpr;
    canvas.height = height * dpr;
    ctx.scale(dpr, dpr);

    // Clear
    ctx.fillStyle = theme.graphBg;
    ctx.fillRect(0, 0, width, height);

    // Grid
    if (showGrid) {
      ctx.strokeStyle = theme.graphGrid;
      ctx.lineWidth = 1;

      // Vertical lines
      for (let i = 0; i <= gridX; i++) {
        const x = (i / gridX) * width;
        ctx.beginPath();
        ctx.moveTo(x, 0);
        ctx.lineTo(x, height);
        ctx.stroke();
      }

      // Horizontal lines
      for (let i = 0; i <= gridY; i++) {
        const y = (i / gridY) * height;
        ctx.beginPath();
        ctx.moveTo(0, y);
        ctx.lineTo(width, y);
        ctx.stroke();
      }
    }

    // Custom draw
    if (onDraw) {
      onDraw(ctx, width, height);
      return;
    }

    // Draw data
    if (data && data.length > 0) {
      const color = lineColor || theme.graphLine;
      const fillColor = theme.graphFill;

      ctx.beginPath();
      ctx.moveTo(0, height);

      for (let i = 0; i < data.length; i++) {
        const x = (i / (data.length - 1)) * width;
        const y = height - data[i] * height;
        ctx.lineTo(x, y);
      }

      if (fill) {
        ctx.lineTo(width, height);
        ctx.closePath();
        ctx.fillStyle = fillColor;
        ctx.fill();
      }

      // Stroke line
      ctx.beginPath();
      for (let i = 0; i < data.length; i++) {
        const x = (i / (data.length - 1)) * width;
        const y = height - data[i] * height;
        if (i === 0) {
          ctx.moveTo(x, y);
        } else {
          ctx.lineTo(x, y);
        }
      }

      ctx.strokeStyle = color;
      ctx.lineWidth = lineWidth;
      ctx.stroke();
    }
  }, [width, height, data, showGrid, gridX, gridY, lineColor, fill, lineWidth, theme, onDraw]);

  return (
    <canvas
      ref={canvasRef}
      className={`plugin-graph ${className ?? ''}`}
      style={{ width, height }}
    />
  );
}

export const PluginGraph = memo(PluginGraphInner);
export default PluginGraph;
