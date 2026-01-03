/**
 * ReelForge Carousel
 *
 * Image/content slider:
 * - Touch/swipe support
 * - Auto play
 * - Dots/arrows navigation
 * - Infinite loop
 * - Multiple slides visible
 *
 * @module carousel/Carousel
 */

import { useState, useRef, useCallback, useEffect } from 'react';
import './Carousel.css';

// ============ Types ============

export interface CarouselProps {
  /** Slides content */
  children: React.ReactNode[];
  /** Auto play */
  autoPlay?: boolean;
  /** Auto play interval (ms) */
  interval?: number;
  /** Show dots */
  showDots?: boolean;
  /** Show arrows */
  showArrows?: boolean;
  /** Infinite loop */
  infinite?: boolean;
  /** Slides to show */
  slidesToShow?: number;
  /** Slides to scroll */
  slidesToScroll?: number;
  /** Gap between slides */
  gap?: number;
  /** Animation duration (ms) */
  duration?: number;
  /** Pause on hover */
  pauseOnHover?: boolean;
  /** On slide change */
  onChange?: (index: number) => void;
  /** Custom class */
  className?: string;
}

export interface CarouselSlideProps {
  /** Slide content */
  children: React.ReactNode;
  /** Custom class */
  className?: string;
}

// ============ Carousel Component ============

export function Carousel({
  children,
  autoPlay = false,
  interval = 5000,
  showDots = true,
  showArrows = true,
  infinite = true,
  slidesToShow = 1,
  slidesToScroll = 1,
  gap = 0,
  duration = 300,
  pauseOnHover = true,
  onChange,
  className = '',
}: CarouselProps) {
  const [currentIndex, setCurrentIndex] = useState(0);
  const [isTransitioning, setIsTransitioning] = useState(false);
  const [isPaused, setIsPaused] = useState(false);
  const trackRef = useRef<HTMLDivElement>(null);
  const touchStartX = useRef(0);
  const touchEndX = useRef(0);

  const totalSlides = children.length;
  const maxIndex = infinite ? totalSlides - 1 : Math.max(0, totalSlides - slidesToShow);

  // Go to specific slide
  const goTo = useCallback(
    (index: number) => {
      if (isTransitioning) return;

      let newIndex = index;

      if (infinite) {
        if (index < 0) newIndex = totalSlides - 1;
        else if (index >= totalSlides) newIndex = 0;
      } else {
        newIndex = Math.max(0, Math.min(maxIndex, index));
      }

      setIsTransitioning(true);
      setCurrentIndex(newIndex);
      onChange?.(newIndex);

      setTimeout(() => setIsTransitioning(false), duration);
    },
    [isTransitioning, infinite, totalSlides, maxIndex, duration, onChange]
  );

  // Next/Prev
  const next = useCallback(() => {
    goTo(currentIndex + slidesToScroll);
  }, [currentIndex, slidesToScroll, goTo]);

  const prev = useCallback(() => {
    goTo(currentIndex - slidesToScroll);
  }, [currentIndex, slidesToScroll, goTo]);

  // Auto play
  useEffect(() => {
    if (!autoPlay || isPaused) return;

    const timer = setInterval(next, interval);
    return () => clearInterval(timer);
  }, [autoPlay, interval, isPaused, next]);

  // Touch handlers
  const handleTouchStart = (e: React.TouchEvent) => {
    touchStartX.current = e.touches[0].clientX;
  };

  const handleTouchMove = (e: React.TouchEvent) => {
    touchEndX.current = e.touches[0].clientX;
  };

  const handleTouchEnd = () => {
    const diff = touchStartX.current - touchEndX.current;
    const threshold = 50;

    if (Math.abs(diff) > threshold) {
      if (diff > 0) {
        next();
      } else {
        prev();
      }
    }
  };

  // Mouse drag handlers
  const handleMouseDown = (e: React.MouseEvent) => {
    touchStartX.current = e.clientX;
  };

  const handleMouseUp = (e: React.MouseEvent) => {
    const diff = touchStartX.current - e.clientX;
    const threshold = 50;

    if (Math.abs(diff) > threshold) {
      if (diff > 0) {
        next();
      } else {
        prev();
      }
    }
  };

  // Calculate transform
  const slideWidth = 100 / slidesToShow;
  const translateX = -(currentIndex * slideWidth);

  // Can navigate
  const canPrev = infinite || currentIndex > 0;
  const canNext = infinite || currentIndex < maxIndex;

  return (
    <div
      className={`carousel ${className}`}
      onMouseEnter={() => pauseOnHover && setIsPaused(true)}
      onMouseLeave={() => pauseOnHover && setIsPaused(false)}
    >
      {/* Track */}
      <div className="carousel__viewport">
        <div
          ref={trackRef}
          className="carousel__track"
          style={{
            transform: `translateX(${translateX}%)`,
            transition: isTransitioning ? `transform ${duration}ms ease` : 'none',
            gap,
          }}
          onTouchStart={handleTouchStart}
          onTouchMove={handleTouchMove}
          onTouchEnd={handleTouchEnd}
          onMouseDown={handleMouseDown}
          onMouseUp={handleMouseUp}
        >
          {children.map((child, index) => (
            <div
              key={index}
              className="carousel__slide"
              style={{ width: `${slideWidth}%`, flexShrink: 0 }}
            >
              {child}
            </div>
          ))}
        </div>
      </div>

      {/* Arrows */}
      {showArrows && (
        <>
          <button
            type="button"
            className="carousel__arrow carousel__arrow--prev"
            onClick={prev}
            disabled={!canPrev}
            aria-label="Previous slide"
          >
            ‹
          </button>
          <button
            type="button"
            className="carousel__arrow carousel__arrow--next"
            onClick={next}
            disabled={!canNext}
            aria-label="Next slide"
          >
            ›
          </button>
        </>
      )}

      {/* Dots */}
      {showDots && (
        <div className="carousel__dots">
          {Array.from({ length: totalSlides }).map((_, index) => (
            <button
              key={index}
              type="button"
              className={`carousel__dot ${index === currentIndex ? 'carousel__dot--active' : ''}`}
              onClick={() => goTo(index)}
              aria-label={`Go to slide ${index + 1}`}
              aria-current={index === currentIndex}
            />
          ))}
        </div>
      )}
    </div>
  );
}

// ============ CarouselSlide ============

export function CarouselSlide({ children, className = '' }: CarouselSlideProps) {
  return <div className={`carousel-slide ${className}`}>{children}</div>;
}

// ============ useCarousel Hook ============

export interface UseCarouselOptions {
  /** Total slides */
  totalSlides: number;
  /** Initial index */
  initialIndex?: number;
  /** Infinite loop */
  infinite?: boolean;
  /** On change callback */
  onChange?: (index: number) => void;
}

export function useCarousel({
  totalSlides,
  initialIndex = 0,
  infinite = true,
  onChange,
}: UseCarouselOptions) {
  const [currentIndex, setCurrentIndex] = useState(initialIndex);

  const goTo = useCallback(
    (index: number) => {
      let newIndex = index;

      if (infinite) {
        if (index < 0) newIndex = totalSlides - 1;
        else if (index >= totalSlides) newIndex = 0;
      } else {
        newIndex = Math.max(0, Math.min(totalSlides - 1, index));
      }

      setCurrentIndex(newIndex);
      onChange?.(newIndex);
    },
    [totalSlides, infinite, onChange]
  );

  const next = useCallback(() => goTo(currentIndex + 1), [currentIndex, goTo]);
  const prev = useCallback(() => goTo(currentIndex - 1), [currentIndex, goTo]);

  return {
    currentIndex,
    goTo,
    next,
    prev,
    isFirst: currentIndex === 0,
    isLast: currentIndex === totalSlides - 1,
  };
}

export default Carousel;
