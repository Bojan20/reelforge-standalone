/**
 * ReelForge Tour
 *
 * Feature tour/walkthrough component:
 * - Step-by-step guide
 * - Target element highlighting
 * - Keyboard navigation
 * - Progress indicator
 *
 * @module tour/Tour
 */

import { useState, useEffect, useCallback, useRef } from 'react';
import { createPortal } from 'react-dom';
import './Tour.css';

// ============ Types ============

export interface TourStep {
  /** Target element selector or ref */
  target: string | React.RefObject<HTMLElement>;
  /** Step title */
  title: string;
  /** Step content */
  content: React.ReactNode;
  /** Placement relative to target */
  placement?: 'top' | 'bottom' | 'left' | 'right';
  /** Highlight padding */
  highlightPadding?: number;
  /** Before step callback */
  onBefore?: () => void | Promise<void>;
  /** After step callback */
  onAfter?: () => void | Promise<void>;
}

export interface TourProps {
  /** Tour steps */
  steps: TourStep[];
  /** Is tour open */
  open: boolean;
  /** On close/finish */
  onClose: () => void;
  /** Initial step index */
  initialStep?: number;
  /** Show step numbers */
  showStepNumbers?: boolean;
  /** Show progress bar */
  showProgress?: boolean;
  /** Close on overlay click */
  closeOnOverlayClick?: boolean;
  /** Close on escape */
  closeOnEscape?: boolean;
  /** Next button text */
  nextText?: string;
  /** Previous button text */
  prevText?: string;
  /** Finish button text */
  finishText?: string;
  /** Skip button text */
  skipText?: string;
  /** Custom class */
  className?: string;
}

// ============ Tour Component ============

export function Tour({
  steps,
  open,
  onClose,
  initialStep = 0,
  showStepNumbers = true,
  showProgress = true,
  closeOnOverlayClick = true,
  closeOnEscape = true,
  nextText = 'Next',
  prevText = 'Previous',
  finishText = 'Finish',
  skipText = 'Skip',
  className = '',
}: TourProps) {
  const [currentStep, setCurrentStep] = useState(initialStep);
  const [targetRect, setTargetRect] = useState<DOMRect | null>(null);
  const tooltipRef = useRef<HTMLDivElement>(null);

  const step = steps[currentStep];
  const isFirst = currentStep === 0;
  const isLast = currentStep === steps.length - 1;

  // Get target element
  const getTargetElement = useCallback((): HTMLElement | null => {
    if (!step) return null;

    if (typeof step.target === 'string') {
      return document.querySelector(step.target);
    }

    return step.target.current;
  }, [step]);

  // Update target rect
  const updateTargetRect = useCallback(() => {
    const target = getTargetElement();
    if (target) {
      setTargetRect(target.getBoundingClientRect());
    } else {
      setTargetRect(null);
    }
  }, [getTargetElement]);

  // Scroll target into view
  const scrollToTarget = useCallback(() => {
    const target = getTargetElement();
    if (target) {
      target.scrollIntoView({ behavior: 'smooth', block: 'center' });
      // Update rect after scroll
      setTimeout(updateTargetRect, 300);
    }
  }, [getTargetElement, updateTargetRect]);

  // Handle step change
  useEffect(() => {
    if (!open) return;

    const runBeforeHook = async () => {
      if (step?.onBefore) {
        await step.onBefore();
      }
      scrollToTarget();
    };

    runBeforeHook();
  }, [open, currentStep, step, scrollToTarget]);

  // Update on resize/scroll
  useEffect(() => {
    if (!open) return;

    updateTargetRect();

    window.addEventListener('resize', updateTargetRect);
    window.addEventListener('scroll', updateTargetRect, true);

    return () => {
      window.removeEventListener('resize', updateTargetRect);
      window.removeEventListener('scroll', updateTargetRect, true);
    };
  }, [open, updateTargetRect]);

  // Handle escape key
  useEffect(() => {
    if (!open || !closeOnEscape) return;

    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        onClose();
      } else if (e.key === 'ArrowRight' && !isLast) {
        handleNext();
      } else if (e.key === 'ArrowLeft' && !isFirst) {
        handlePrev();
      }
    };

    document.addEventListener('keydown', handleKeyDown);
    return () => document.removeEventListener('keydown', handleKeyDown);
  }, [open, closeOnEscape, isFirst, isLast, onClose]);

  // Navigation handlers
  const handleNext = useCallback(async () => {
    if (step?.onAfter) {
      await step.onAfter();
    }

    if (isLast) {
      onClose();
    } else {
      setCurrentStep((prev) => prev + 1);
    }
  }, [step, isLast, onClose]);

  const handlePrev = useCallback(() => {
    if (!isFirst) {
      setCurrentStep((prev) => prev - 1);
    }
  }, [isFirst]);

  const handleSkip = useCallback(() => {
    onClose();
  }, [onClose]);

  const handleOverlayClick = useCallback(() => {
    if (closeOnOverlayClick) {
      onClose();
    }
  }, [closeOnOverlayClick, onClose]);

  // Calculate tooltip position
  const getTooltipStyle = (): React.CSSProperties => {
    if (!targetRect) {
      // Center in viewport if no target
      return {
        top: '50%',
        left: '50%',
        transform: 'translate(-50%, -50%)',
      };
    }

    const padding = step?.highlightPadding ?? 8;
    const placement = step?.placement ?? 'bottom';
    const gap = 12;

    const style: React.CSSProperties = {};

    switch (placement) {
      case 'top':
        style.bottom = window.innerHeight - targetRect.top + gap + padding;
        style.left = targetRect.left + targetRect.width / 2;
        style.transform = 'translateX(-50%)';
        break;
      case 'bottom':
        style.top = targetRect.bottom + gap + padding;
        style.left = targetRect.left + targetRect.width / 2;
        style.transform = 'translateX(-50%)';
        break;
      case 'left':
        style.right = window.innerWidth - targetRect.left + gap + padding;
        style.top = targetRect.top + targetRect.height / 2;
        style.transform = 'translateY(-50%)';
        break;
      case 'right':
        style.left = targetRect.right + gap + padding;
        style.top = targetRect.top + targetRect.height / 2;
        style.transform = 'translateY(-50%)';
        break;
    }

    return style;
  };

  // Highlight mask
  const getMaskStyle = (): React.CSSProperties => {
    if (!targetRect) return {};

    const padding = step?.highlightPadding ?? 8;

    return {
      top: targetRect.top - padding,
      left: targetRect.left - padding,
      width: targetRect.width + padding * 2,
      height: targetRect.height + padding * 2,
    };
  };

  if (!open || !step) return null;

  return createPortal(
    <div className={`tour ${className}`}>
      {/* Overlay */}
      <div className="tour__overlay" onClick={handleOverlayClick}>
        {/* Highlight cutout */}
        {targetRect && (
          <div className="tour__highlight" style={getMaskStyle()} />
        )}
      </div>

      {/* Tooltip */}
      <div
        ref={tooltipRef}
        className={`tour__tooltip tour__tooltip--${step.placement ?? 'bottom'}`}
        style={getTooltipStyle()}
      >
        {/* Header */}
        <div className="tour__header">
          {showStepNumbers && (
            <span className="tour__step-number">
              {currentStep + 1} / {steps.length}
            </span>
          )}
          <h3 className="tour__title">{step.title}</h3>
          <button
            type="button"
            className="tour__close"
            onClick={onClose}
            aria-label="Close tour"
          >
            ×
          </button>
        </div>

        {/* Content */}
        <div className="tour__content">{step.content}</div>

        {/* Progress */}
        {showProgress && (
          <div className="tour__progress">
            <div
              className="tour__progress-bar"
              style={{ width: `${((currentStep + 1) / steps.length) * 100}%` }}
            />
          </div>
        )}

        {/* Footer */}
        <div className="tour__footer">
          <button
            type="button"
            className="tour__btn tour__btn--skip"
            onClick={handleSkip}
          >
            {skipText}
          </button>

          <div className="tour__nav">
            {!isFirst && (
              <button
                type="button"
                className="tour__btn tour__btn--prev"
                onClick={handlePrev}
              >
                {prevText}
              </button>
            )}
            <button
              type="button"
              className="tour__btn tour__btn--next"
              onClick={handleNext}
            >
              {isLast ? finishText : nextText}
            </button>
          </div>
        </div>
      </div>
    </div>,
    document.body
  );
}

// ============ useTour Hook ============

export function useTour(steps: TourStep[]) {
  const [isOpen, setIsOpen] = useState(false);
  const [hasCompleted, setHasCompleted] = useState(false);

  const start = useCallback(() => {
    setIsOpen(true);
  }, []);

  const stop = useCallback(() => {
    setIsOpen(false);
    setHasCompleted(true);
  }, []);

  const reset = useCallback(() => {
    setHasCompleted(false);
  }, []);

  return {
    isOpen,
    hasCompleted,
    start,
    stop,
    reset,
    tourProps: {
      steps,
      open: isOpen,
      onClose: stop,
    },
  };
}

export default Tour;
