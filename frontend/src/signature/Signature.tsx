/**
 * ReelForge Signature
 *
 * Signature pad component:
 * - Smooth drawing
 * - Touch support
 * - Export to image
 * - Clear/undo
 *
 * @module signature/Signature
 */

import { useRef, useState, useCallback, useEffect } from 'react';
import './Signature.css';

// ============ Types ============

export interface Point {
  x: number;
  y: number;
  pressure?: number;
  time: number;
}

export interface SignatureProps {
  /** Canvas width */
  width?: number;
  /** Canvas height */
  height?: number;
  /** Line color */
  penColor?: string;
  /** Line width */
  penWidth?: number;
  /** Background color */
  backgroundColor?: string;
  /** On change callback */
  onChange?: (isEmpty: boolean) => void;
  /** On end stroke callback */
  onEnd?: () => void;
  /** Disabled state */
  disabled?: boolean;
  /** Placeholder text */
  placeholder?: string;
  /** Custom class */
  className?: string;
}

export interface SignatureRef {
  /** Clear the signature */
  clear: () => void;
  /** Check if empty */
  isEmpty: () => boolean;
  /** Get data URL */
  toDataURL: (type?: string, quality?: number) => string;
  /** Get SVG string */
  toSVG: () => string;
  /** Undo last stroke */
  undo: () => void;
}

// ============ Signature Component ============

export function Signature({
  width = 400,
  height = 200,
  penColor = '#000000',
  penWidth = 2,
  backgroundColor = '#ffffff',
  onChange,
  onEnd,
  disabled = false,
  placeholder = 'Sign here',
  className = '',
}: SignatureProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [isDrawing, setIsDrawing] = useState(false);
  const [isEmpty, setIsEmpty] = useState(true);
  const [strokes, setStrokes] = useState<Point[][]>([]);
  const currentStroke = useRef<Point[]>([]);
  const lastPoint = useRef<Point | null>(null);

  // Initialize canvas
  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    // Set canvas size
    canvas.width = width;
    canvas.height = height;

    // Fill background
    ctx.fillStyle = backgroundColor;
    ctx.fillRect(0, 0, width, height);
  }, [width, height, backgroundColor]);

  // Redraw all strokes
  const redraw = useCallback(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    // Clear and fill background
    ctx.fillStyle = backgroundColor;
    ctx.fillRect(0, 0, width, height);

    // Redraw all strokes
    ctx.strokeStyle = penColor;
    ctx.lineWidth = penWidth;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';

    strokes.forEach((stroke) => {
      if (stroke.length < 2) return;

      ctx.beginPath();
      ctx.moveTo(stroke[0].x, stroke[0].y);

      for (let i = 1; i < stroke.length; i++) {
        const p0 = stroke[i - 1];
        const p1 = stroke[i];

        // Smooth curve
        const midX = (p0.x + p1.x) / 2;
        const midY = (p0.y + p1.y) / 2;
        ctx.quadraticCurveTo(p0.x, p0.y, midX, midY);
      }

      ctx.stroke();
    });

    setIsEmpty(strokes.length === 0);
    onChange?.(strokes.length === 0);
  }, [strokes, width, height, backgroundColor, penColor, penWidth, onChange]);

  useEffect(() => {
    redraw();
  }, [redraw]);

  // Get point from event
  const getPoint = useCallback(
    (e: React.MouseEvent | React.TouchEvent): Point => {
      const canvas = canvasRef.current!;
      const rect = canvas.getBoundingClientRect();

      let clientX: number, clientY: number;
      let pressure = 0.5;

      if ('touches' in e) {
        const touch = e.touches[0] || e.changedTouches[0];
        clientX = touch.clientX;
        clientY = touch.clientY;
        if ('force' in touch) {
          pressure = (touch as any).force;
        }
      } else {
        clientX = e.clientX;
        clientY = e.clientY;
      }

      return {
        x: (clientX - rect.left) * (canvas.width / rect.width),
        y: (clientY - rect.top) * (canvas.height / rect.height),
        pressure,
        time: Date.now(),
      };
    },
    []
  );

  // Draw line between points
  const drawLine = useCallback(
    (p0: Point, p1: Point) => {
      const canvas = canvasRef.current;
      if (!canvas) return;

      const ctx = canvas.getContext('2d');
      if (!ctx) return;

      ctx.strokeStyle = penColor;
      ctx.lineWidth = penWidth;
      ctx.lineCap = 'round';
      ctx.lineJoin = 'round';

      ctx.beginPath();

      if (currentStroke.current.length < 3) {
        // Just draw a line for short strokes
        ctx.moveTo(p0.x, p0.y);
        ctx.lineTo(p1.x, p1.y);
      } else {
        // Smooth curve
        const midX = (p0.x + p1.x) / 2;
        const midY = (p0.y + p1.y) / 2;
        ctx.moveTo(p0.x, p0.y);
        ctx.quadraticCurveTo(p0.x, p0.y, midX, midY);
      }

      ctx.stroke();
    },
    [penColor, penWidth]
  );

  // Start drawing
  const handleStart = useCallback(
    (e: React.MouseEvent | React.TouchEvent) => {
      if (disabled) return;
      e.preventDefault();

      const point = getPoint(e);
      setIsDrawing(true);
      currentStroke.current = [point];
      lastPoint.current = point;

      // Draw initial dot
      const canvas = canvasRef.current;
      if (canvas) {
        const ctx = canvas.getContext('2d');
        if (ctx) {
          ctx.fillStyle = penColor;
          ctx.beginPath();
          ctx.arc(point.x, point.y, penWidth / 2, 0, Math.PI * 2);
          ctx.fill();
        }
      }
    },
    [disabled, getPoint, penColor, penWidth]
  );

  // Continue drawing
  const handleMove = useCallback(
    (e: React.MouseEvent | React.TouchEvent) => {
      if (!isDrawing || disabled) return;
      e.preventDefault();

      const point = getPoint(e);
      currentStroke.current.push(point);

      if (lastPoint.current) {
        drawLine(lastPoint.current, point);
      }

      lastPoint.current = point;
    },
    [isDrawing, disabled, getPoint, drawLine]
  );

  // End drawing
  const handleEnd = useCallback(
    (e: React.MouseEvent | React.TouchEvent) => {
      if (!isDrawing) return;
      e.preventDefault();

      if (currentStroke.current.length > 0) {
        setStrokes((prev) => [...prev, currentStroke.current]);
        setIsEmpty(false);
        onChange?.(false);
      }

      currentStroke.current = [];
      lastPoint.current = null;
      setIsDrawing(false);
      onEnd?.();
    },
    [isDrawing, onChange, onEnd]
  );

  // Clear signature
  const clear = useCallback(() => {
    setStrokes([]);
    currentStroke.current = [];
    setIsEmpty(true);
    onChange?.(true);
  }, [onChange]);

  // Undo last stroke
  const undo = useCallback(() => {
    setStrokes((prev) => {
      const newStrokes = prev.slice(0, -1);
      const newIsEmpty = newStrokes.length === 0;
      setIsEmpty(newIsEmpty);
      onChange?.(newIsEmpty);
      return newStrokes;
    });
  }, [onChange]);

  // Export to data URL (available via ref)
  const _toDataURL = useCallback(
    (type = 'image/png', quality = 1) => {
      return canvasRef.current?.toDataURL(type, quality) ?? '';
    },
    []
  );
  void _toDataURL;

  // Export to SVG (available via ref)
  const _toSVG = useCallback(() => {
    const paths = strokes
      .map((stroke) => {
        if (stroke.length < 2) return '';
        const d = stroke
          .map((p, i) => `${i === 0 ? 'M' : 'L'}${p.x},${p.y}`)
          .join(' ');
        return `<path d="${d}" stroke="${penColor}" stroke-width="${penWidth}" fill="none" stroke-linecap="round" stroke-linejoin="round"/>`;
      })
      .join('\n');

    return `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">
  <rect width="${width}" height="${height}" fill="${backgroundColor}"/>
  ${paths}
</svg>`;
  }, [strokes, width, height, penColor, penWidth, backgroundColor]);
  void _toSVG;

  return (
    <div className={`signature ${disabled ? 'signature--disabled' : ''} ${className}`}>
      <canvas
        ref={canvasRef}
        className="signature__canvas"
        onMouseDown={handleStart}
        onMouseMove={handleMove}
        onMouseUp={handleEnd}
        onMouseLeave={handleEnd}
        onTouchStart={handleStart}
        onTouchMove={handleMove}
        onTouchEnd={handleEnd}
      />

      {isEmpty && (
        <div className="signature__placeholder">{placeholder}</div>
      )}

      <div className="signature__controls">
        <button
          type="button"
          className="signature__btn"
          onClick={undo}
          disabled={isEmpty || disabled}
        >
          Undo
        </button>
        <button
          type="button"
          className="signature__btn signature__btn--clear"
          onClick={clear}
          disabled={isEmpty || disabled}
        >
          Clear
        </button>
      </div>
    </div>
  );
}

// ============ useSignature Hook ============

export function useSignature() {
  const [dataUrl, setDataUrl] = useState<string | null>(null);
  const [isEmpty, setIsEmpty] = useState(true);
  const canvasRef = useRef<HTMLCanvasElement | null>(null);

  const clear = useCallback(() => {
    setDataUrl(null);
    setIsEmpty(true);
  }, []);

  const save = useCallback(() => {
    if (canvasRef.current) {
      setDataUrl(canvasRef.current.toDataURL());
    }
  }, []);

  return {
    dataUrl,
    isEmpty,
    setIsEmpty,
    clear,
    save,
    canvasRef,
  };
}

export default Signature;
