/**
 * ReelForge DatePicker
 *
 * Date selection components:
 * - Calendar view
 * - Month/year navigation
 * - Date range selection
 * - Disabled dates
 *
 * @module date-picker/DatePicker
 */

import { useState, useCallback, useMemo } from 'react';
import './DatePicker.css';

// ============ Types ============

export interface DatePickerProps {
  /** Selected date */
  value?: Date | null;
  /** On date change */
  onChange?: (date: Date | null) => void;
  /** Minimum selectable date */
  minDate?: Date;
  /** Maximum selectable date */
  maxDate?: Date;
  /** Disabled specific dates */
  disabledDates?: Date[];
  /** Disabled days of week (0=Sunday, 6=Saturday) */
  disabledDaysOfWeek?: number[];
  /** First day of week (0=Sunday, 1=Monday) */
  firstDayOfWeek?: 0 | 1;
  /** Show week numbers */
  showWeekNumbers?: boolean;
  /** Locale for formatting */
  locale?: string;
  /** Custom day renderer */
  renderDay?: (date: Date, isSelected: boolean, isDisabled: boolean) => React.ReactNode;
  /** Custom class */
  className?: string;
}

export interface CalendarProps extends Omit<DatePickerProps, 'className'> {
  /** Initial view month/year */
  initialDate?: Date;
  /** Custom class */
  className?: string;
}

export interface DateRangePickerProps {
  /** Start date */
  startDate?: Date | null;
  /** End date */
  endDate?: Date | null;
  /** On range change */
  onChange?: (range: { start: Date | null; end: Date | null }) => void;
  /** Minimum selectable date */
  minDate?: Date;
  /** Maximum selectable date */
  maxDate?: Date;
  /** First day of week */
  firstDayOfWeek?: 0 | 1;
  /** Show two calendars */
  showTwoCalendars?: boolean;
  /** Custom class */
  className?: string;
}

// ============ Date Utilities ============

const DAYS_IN_WEEK = 7;

function getDaysInMonth(year: number, month: number): number {
  return new Date(year, month + 1, 0).getDate();
}

function getFirstDayOfMonth(year: number, month: number): number {
  return new Date(year, month, 1).getDay();
}

function isSameDay(a: Date, b: Date): boolean {
  return (
    a.getFullYear() === b.getFullYear() &&
    a.getMonth() === b.getMonth() &&
    a.getDate() === b.getDate()
  );
}

function isDateInRange(date: Date, start: Date | null, end: Date | null): boolean {
  if (!start || !end) return false;
  const time = date.getTime();
  return time >= start.getTime() && time <= end.getTime();
}

function isDateDisabled(
  date: Date,
  minDate?: Date,
  maxDate?: Date,
  disabledDates?: Date[],
  disabledDaysOfWeek?: number[]
): boolean {
  if (minDate && date < minDate) return true;
  if (maxDate && date > maxDate) return true;
  if (disabledDaysOfWeek?.includes(date.getDay())) return true;
  if (disabledDates?.some((d) => isSameDay(d, date))) return true;
  return false;
}

function getWeekNumber(date: Date): number {
  const d = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()));
  const dayNum = d.getUTCDay() || 7;
  d.setUTCDate(d.getUTCDate() + 4 - dayNum);
  const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
  return Math.ceil(((d.getTime() - yearStart.getTime()) / 86400000 + 1) / 7);
}

// ============ Calendar Component ============

export function Calendar({
  value,
  onChange,
  minDate,
  maxDate,
  disabledDates,
  disabledDaysOfWeek,
  firstDayOfWeek = 1,
  showWeekNumbers = false,
  locale = 'en-US',
  renderDay,
  initialDate,
  className = '',
}: CalendarProps) {
  const [viewDate, setViewDate] = useState(() => initialDate || value || new Date());

  const year = viewDate.getFullYear();
  const month = viewDate.getMonth();

  // Month/year navigation
  const goToPrevMonth = () => {
    setViewDate(new Date(year, month - 1, 1));
  };

  const goToNextMonth = () => {
    setViewDate(new Date(year, month + 1, 1));
  };

  const goToPrevYear = () => {
    setViewDate(new Date(year - 1, month, 1));
  };

  const goToNextYear = () => {
    setViewDate(new Date(year + 1, month, 1));
  };

  // Day names
  const dayNames = useMemo(() => {
    const formatter = new Intl.DateTimeFormat(locale, { weekday: 'short' });
    const days: string[] = [];
    const baseDate = new Date(2024, 0, firstDayOfWeek === 0 ? 7 : 1);

    for (let i = 0; i < DAYS_IN_WEEK; i++) {
      days.push(formatter.format(new Date(baseDate.getTime() + i * 86400000)));
    }

    return days;
  }, [locale, firstDayOfWeek]);

  // Month name
  const monthName = new Intl.DateTimeFormat(locale, { month: 'long' }).format(viewDate);

  // Calendar days grid
  const calendarDays = useMemo(() => {
    const daysInMonth = getDaysInMonth(year, month);
    let firstDay = getFirstDayOfMonth(year, month);

    // Adjust for first day of week
    firstDay = (firstDay - firstDayOfWeek + 7) % 7;

    const days: Array<{ date: Date; isCurrentMonth: boolean } | null> = [];

    // Previous month days
    const prevMonthDays = getDaysInMonth(year, month - 1);
    for (let i = firstDay - 1; i >= 0; i--) {
      days.push({
        date: new Date(year, month - 1, prevMonthDays - i),
        isCurrentMonth: false,
      });
    }

    // Current month days
    for (let i = 1; i <= daysInMonth; i++) {
      days.push({
        date: new Date(year, month, i),
        isCurrentMonth: true,
      });
    }

    // Next month days
    const remainingDays = 42 - days.length; // 6 rows × 7 days
    for (let i = 1; i <= remainingDays; i++) {
      days.push({
        date: new Date(year, month + 1, i),
        isCurrentMonth: false,
      });
    }

    return days;
  }, [year, month, firstDayOfWeek]);

  // Handle day click
  const handleDayClick = useCallback(
    (date: Date) => {
      if (isDateDisabled(date, minDate, maxDate, disabledDates, disabledDaysOfWeek)) {
        return;
      }
      onChange?.(date);
    },
    [onChange, minDate, maxDate, disabledDates, disabledDaysOfWeek]
  );

  const today = new Date();

  return (
    <div className={`calendar ${className}`}>
      {/* Header */}
      <div className="calendar__header">
        <button
          type="button"
          className="calendar__nav-btn"
          onClick={goToPrevYear}
          aria-label="Previous year"
        >
          ««
        </button>
        <button
          type="button"
          className="calendar__nav-btn"
          onClick={goToPrevMonth}
          aria-label="Previous month"
        >
          «
        </button>

        <span className="calendar__title">
          {monthName} {year}
        </span>

        <button
          type="button"
          className="calendar__nav-btn"
          onClick={goToNextMonth}
          aria-label="Next month"
        >
          »
        </button>
        <button
          type="button"
          className="calendar__nav-btn"
          onClick={goToNextYear}
          aria-label="Next year"
        >
          »»
        </button>
      </div>

      {/* Day names */}
      <div
        className="calendar__weekdays"
        style={{ gridTemplateColumns: showWeekNumbers ? 'auto repeat(7, 1fr)' : undefined }}
      >
        {showWeekNumbers && <span className="calendar__weekday calendar__weekday--week">#</span>}
        {dayNames.map((name) => (
          <span key={name} className="calendar__weekday">
            {name}
          </span>
        ))}
      </div>

      {/* Days grid */}
      <div
        className="calendar__days"
        style={{ gridTemplateColumns: showWeekNumbers ? 'auto repeat(7, 1fr)' : undefined }}
      >
        {calendarDays.map((day, index) => {
          if (!day) return <span key={index} />;

          const { date, isCurrentMonth } = day;
          const isSelected = value ? isSameDay(date, value) : false;
          const isToday = isSameDay(date, today);
          const isDisabled = isDateDisabled(
            date,
            minDate,
            maxDate,
            disabledDates,
            disabledDaysOfWeek
          );

          // Week number at start of each row
          const showWeekNum = showWeekNumbers && index % 7 === 0;

          return (
            <>
              {showWeekNum && (
                <span key={`week-${index}`} className="calendar__week-number">
                  {getWeekNumber(date)}
                </span>
              )}
              <button
                key={date.toISOString()}
                type="button"
                className={`calendar__day ${!isCurrentMonth ? 'calendar__day--other' : ''} ${
                  isSelected ? 'calendar__day--selected' : ''
                } ${isToday ? 'calendar__day--today' : ''} ${
                  isDisabled ? 'calendar__day--disabled' : ''
                }`}
                onClick={() => handleDayClick(date)}
                disabled={isDisabled}
                aria-label={date.toLocaleDateString(locale)}
                aria-pressed={isSelected}
              >
                {renderDay ? renderDay(date, isSelected, isDisabled) : date.getDate()}
              </button>
            </>
          );
        })}
      </div>
    </div>
  );
}

// ============ DatePicker Component (with input) ============

export function DatePicker({
  value,
  onChange,
  minDate,
  maxDate,
  disabledDates,
  disabledDaysOfWeek,
  firstDayOfWeek = 1,
  showWeekNumbers = false,
  locale = 'en-US',
  className = '',
}: DatePickerProps) {
  const [isOpen, setIsOpen] = useState(false);

  const formattedValue = value
    ? new Intl.DateTimeFormat(locale, {
        year: 'numeric',
        month: 'short',
        day: 'numeric',
      }).format(value)
    : '';

  const handleSelect = (date: Date | null) => {
    onChange?.(date);
    setIsOpen(false);
  };

  const handleClear = () => {
    onChange?.(null);
  };

  return (
    <div className={`date-picker ${isOpen ? 'date-picker--open' : ''} ${className}`}>
      <div className="date-picker__input" onClick={() => setIsOpen(!isOpen)}>
        <span className="date-picker__value">{formattedValue || 'Select date...'}</span>
        <span className="date-picker__icon">📅</span>
      </div>

      {value && (
        <button
          type="button"
          className="date-picker__clear"
          onClick={handleClear}
          aria-label="Clear date"
        >
          ×
        </button>
      )}

      {isOpen && (
        <div className="date-picker__dropdown">
          <Calendar
            value={value}
            onChange={handleSelect}
            minDate={minDate}
            maxDate={maxDate}
            disabledDates={disabledDates}
            disabledDaysOfWeek={disabledDaysOfWeek}
            firstDayOfWeek={firstDayOfWeek}
            showWeekNumbers={showWeekNumbers}
            locale={locale}
          />
        </div>
      )}
    </div>
  );
}

// ============ DateRangePicker Component ============

export function DateRangePicker({
  startDate,
  endDate,
  onChange,
  minDate,
  maxDate,
  firstDayOfWeek = 1,
  showTwoCalendars = true,
  className = '',
}: DateRangePickerProps) {
  const [selecting, setSelecting] = useState<'start' | 'end'>('start');
  const [hoverDate, setHoverDate] = useState<Date | null>(null);

  const handleSelect = (date: Date) => {
    if (selecting === 'start') {
      onChange?.({ start: date, end: null });
      setSelecting('end');
    } else {
      if (startDate && date < startDate) {
        onChange?.({ start: date, end: startDate });
      } else {
        onChange?.({ start: startDate!, end: date });
      }
      setSelecting('start');
    }
  };

  const renderDay = (date: Date, _isSelected: boolean, _isDisabled: boolean) => {
    const isStart = startDate && isSameDay(date, startDate);
    const isEnd = endDate && isSameDay(date, endDate);
    const inRange = isDateInRange(date, startDate ?? null, endDate ?? null);
    const inHoverRange =
      selecting === 'end' && startDate && hoverDate && isDateInRange(date, startDate, hoverDate);

    return (
      <span
        className={`date-range__day ${isStart ? 'date-range__day--start' : ''} ${
          isEnd ? 'date-range__day--end' : ''
        } ${inRange || inHoverRange ? 'date-range__day--in-range' : ''}`}
        onMouseEnter={() => setHoverDate(date)}
        onMouseLeave={() => setHoverDate(null)}
      >
        {date.getDate()}
      </span>
    );
  };

  const today = new Date();
  const nextMonth = new Date(today.getFullYear(), today.getMonth() + 1, 1);

  return (
    <div className={`date-range-picker ${className}`}>
      <Calendar
        value={startDate}
        onChange={(date) => date && handleSelect(date)}
        minDate={minDate}
        maxDate={maxDate}
        firstDayOfWeek={firstDayOfWeek}
        renderDay={renderDay}
        initialDate={today}
      />
      {showTwoCalendars && (
        <Calendar
          value={endDate}
          onChange={(date) => date && handleSelect(date)}
          minDate={minDate}
          maxDate={maxDate}
          firstDayOfWeek={firstDayOfWeek}
          renderDay={renderDay}
          initialDate={nextMonth}
        />
      )}
    </div>
  );
}

export default DatePicker;
