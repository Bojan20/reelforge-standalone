/**
 * ReelForge Calendar
 *
 * Full calendar component:
 * - Month/Year/Decade views
 * - Date selection
 * - Range selection
 * - Events display
 * - Localization
 *
 * @module calendar/Calendar
 */

import { useState, useCallback, useMemo } from 'react';
import './Calendar.css';

// ============ Types ============

export type CalendarMode = 'month' | 'year' | 'decade';

export interface CalendarEvent {
  id: string;
  date: Date;
  title: string;
  color?: string;
}

export interface CalendarProps {
  /** Selected date */
  value?: Date | null;
  /** Default date */
  defaultValue?: Date;
  /** On date select */
  onChange?: (date: Date) => void;
  /** Calendar mode */
  mode?: CalendarMode;
  /** On mode change */
  onModeChange?: (mode: CalendarMode) => void;
  /** Events to display */
  events?: CalendarEvent[];
  /** On event click */
  onEventClick?: (event: CalendarEvent) => void;
  /** Disable specific dates */
  disabledDate?: (date: Date) => boolean;
  /** Min selectable date */
  minDate?: Date;
  /** Max selectable date */
  maxDate?: Date;
  /** Week starts on (0=Sun, 1=Mon) */
  weekStartsOn?: 0 | 1;
  /** Show week numbers */
  showWeekNumbers?: boolean;
  /** Locale */
  locale?: string;
  /** Custom class */
  className?: string;
}

export interface CalendarRangeProps {
  /** Selected range */
  value?: [Date | null, Date | null];
  /** On range change */
  onChange?: (range: [Date, Date]) => void;
  /** Other props */
  disabledDate?: (date: Date) => boolean;
  minDate?: Date;
  maxDate?: Date;
  weekStartsOn?: 0 | 1;
  locale?: string;
  className?: string;
}

// ============ Helpers ============

const DAYS_SHORT = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];
const MONTHS = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

function getDaysInMonth(year: number, month: number): number {
  return new Date(year, month + 1, 0).getDate();
}

function getFirstDayOfMonth(year: number, month: number): number {
  return new Date(year, month, 1).getDay();
}

function isSameDay(d1: Date, d2: Date): boolean {
  return (
    d1.getFullYear() === d2.getFullYear() &&
    d1.getMonth() === d2.getMonth() &&
    d1.getDate() === d2.getDate()
  );
}

function _isSameMonth(d1: Date, d2: Date): boolean {
  return d1.getFullYear() === d2.getFullYear() && d1.getMonth() === d2.getMonth();
}
void _isSameMonth; // Reserved for future use

function isToday(date: Date): boolean {
  return isSameDay(date, new Date());
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
  defaultValue,
  onChange,
  mode: controlledMode,
  onModeChange,
  events = [],
  onEventClick,
  disabledDate,
  minDate,
  maxDate,
  weekStartsOn = 0,
  showWeekNumbers = false,
  className = '',
}: CalendarProps) {
  const [viewDate, setViewDate] = useState(() => value || defaultValue || new Date());
  const [internalMode, setInternalMode] = useState<CalendarMode>('month');

  const mode = controlledMode ?? internalMode;
  const setMode = (m: CalendarMode) => {
    setInternalMode(m);
    onModeChange?.(m);
  };

  const year = viewDate.getFullYear();
  const month = viewDate.getMonth();

  // Check if date is disabled
  const isDisabled = useCallback(
    (date: Date): boolean => {
      if (disabledDate?.(date)) return true;
      if (minDate && date < minDate) return true;
      if (maxDate && date > maxDate) return true;
      return false;
    },
    [disabledDate, minDate, maxDate]
  );

  // Get events for a specific date
  const getEventsForDate = useCallback(
    (date: Date) => events.filter((e) => isSameDay(e.date, date)),
    [events]
  );

  // Navigation
  const goToPrevMonth = () => setViewDate(new Date(year, month - 1, 1));
  const goToNextMonth = () => setViewDate(new Date(year, month + 1, 1));
  const goToPrevYear = () => setViewDate(new Date(year - 1, month, 1));
  const goToNextYear = () => setViewDate(new Date(year + 1, month, 1));
  const goToPrevDecade = () => setViewDate(new Date(year - 10, month, 1));
  const goToNextDecade = () => setViewDate(new Date(year + 10, month, 1));

  // Build calendar grid
  const calendarDays = useMemo(() => {
    const days: Array<{ date: Date; isCurrentMonth: boolean }> = [];
    const daysInMonth = getDaysInMonth(year, month);
    const firstDay = getFirstDayOfMonth(year, month);

    // Adjust for week start
    const startOffset = (firstDay - weekStartsOn + 7) % 7;

    // Previous month days
    const prevMonthDays = getDaysInMonth(year, month - 1);
    for (let i = startOffset - 1; i >= 0; i--) {
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
    const remaining = 42 - days.length;
    for (let i = 1; i <= remaining; i++) {
      days.push({
        date: new Date(year, month + 1, i),
        isCurrentMonth: false,
      });
    }

    return days;
  }, [year, month, weekStartsOn]);

  // Day headers
  const dayHeaders = useMemo(() => {
    const headers = [...DAYS_SHORT];
    if (weekStartsOn === 1) {
      headers.push(headers.shift()!);
    }
    return headers;
  }, [weekStartsOn]);

  // Handle date click
  const handleDateClick = (date: Date) => {
    if (isDisabled(date)) return;
    onChange?.(date);
  };

  // Handle month click (in year view)
  const handleMonthClick = (m: number) => {
    setViewDate(new Date(year, m, 1));
    setMode('month');
  };

  // Handle year click (in decade view)
  const handleYearClick = (y: number) => {
    setViewDate(new Date(y, month, 1));
    setMode('year');
  };

  // Render month view
  const renderMonthView = () => (
    <>
      <div className="calendar__header">
        <button type="button" className="calendar__nav" onClick={goToPrevMonth}>
          ‹
        </button>
        <button
          type="button"
          className="calendar__title"
          onClick={() => setMode('year')}
        >
          {MONTHS[month]} {year}
        </button>
        <button type="button" className="calendar__nav" onClick={goToNextMonth}>
          ›
        </button>
      </div>

      <div className="calendar__weekdays">
        {showWeekNumbers && <div className="calendar__weekday calendar__weekday--number">#</div>}
        {dayHeaders.map((day) => (
          <div key={day} className="calendar__weekday">
            {day}
          </div>
        ))}
      </div>

      <div className="calendar__days">
        {calendarDays.map(({ date, isCurrentMonth }, i) => {
          const dayEvents = getEventsForDate(date);
          const isSelected = value && isSameDay(date, value);
          const showWeekNum = showWeekNumbers && i % 7 === 0;

          return (
            <>
              {showWeekNum && (
                <div key={`week-${i}`} className="calendar__week-number">
                  {getWeekNumber(date)}
                </div>
              )}
              <button
                key={date.toISOString()}
                type="button"
                className={`calendar__day ${
                  !isCurrentMonth ? 'calendar__day--outside' : ''
                } ${isToday(date) ? 'calendar__day--today' : ''} ${
                  isSelected ? 'calendar__day--selected' : ''
                } ${isDisabled(date) ? 'calendar__day--disabled' : ''}`}
                onClick={() => handleDateClick(date)}
                disabled={isDisabled(date)}
              >
                <span className="calendar__day-number">{date.getDate()}</span>
                {dayEvents.length > 0 && (
                  <div className="calendar__day-events">
                    {dayEvents.slice(0, 3).map((event) => (
                      <span
                        key={event.id}
                        className="calendar__day-event"
                        style={{ backgroundColor: event.color }}
                        onClick={(e) => {
                          e.stopPropagation();
                          onEventClick?.(event);
                        }}
                        title={event.title}
                      />
                    ))}
                  </div>
                )}
              </button>
            </>
          );
        })}
      </div>
    </>
  );

  // Render year view (months)
  const renderYearView = () => (
    <>
      <div className="calendar__header">
        <button type="button" className="calendar__nav" onClick={goToPrevYear}>
          ‹
        </button>
        <button
          type="button"
          className="calendar__title"
          onClick={() => setMode('decade')}
        >
          {year}
        </button>
        <button type="button" className="calendar__nav" onClick={goToNextYear}>
          ›
        </button>
      </div>

      <div className="calendar__months">
        {MONTHS.map((monthName, i) => {
          const isCurrentMonth = i === new Date().getMonth() && year === new Date().getFullYear();
          const isSelected = value && value.getMonth() === i && value.getFullYear() === year;

          return (
            <button
              key={monthName}
              type="button"
              className={`calendar__month ${
                isCurrentMonth ? 'calendar__month--current' : ''
              } ${isSelected ? 'calendar__month--selected' : ''}`}
              onClick={() => handleMonthClick(i)}
            >
              {monthName.slice(0, 3)}
            </button>
          );
        })}
      </div>
    </>
  );

  // Render decade view (years)
  const renderDecadeView = () => {
    const decadeStart = Math.floor(year / 10) * 10;
    const years = Array.from({ length: 12 }, (_, i) => decadeStart - 1 + i);

    return (
      <>
        <div className="calendar__header">
          <button type="button" className="calendar__nav" onClick={goToPrevDecade}>
            ‹
          </button>
          <span className="calendar__title">
            {decadeStart} - {decadeStart + 9}
          </span>
          <button type="button" className="calendar__nav" onClick={goToNextDecade}>
            ›
          </button>
        </div>

        <div className="calendar__years">
          {years.map((y) => {
            const isCurrentYear = y === new Date().getFullYear();
            const isSelected = value && value.getFullYear() === y;
            const isOutside = y < decadeStart || y > decadeStart + 9;

            return (
              <button
                key={y}
                type="button"
                className={`calendar__year ${
                  isCurrentYear ? 'calendar__year--current' : ''
                } ${isSelected ? 'calendar__year--selected' : ''} ${
                  isOutside ? 'calendar__year--outside' : ''
                }`}
                onClick={() => handleYearClick(y)}
              >
                {y}
              </button>
            );
          })}
        </div>
      </>
    );
  };

  return (
    <div className={`calendar calendar--${mode} ${className}`}>
      {mode === 'month' && renderMonthView()}
      {mode === 'year' && renderYearView()}
      {mode === 'decade' && renderDecadeView()}
    </div>
  );
}

// ============ CalendarRange Component ============

export function CalendarRange({
  value,
  onChange,
  disabledDate,
  minDate,
  maxDate,
  weekStartsOn = 0,
  className = '',
}: CalendarRangeProps) {
  const [hoverDate, setHoverDate] = useState<Date | null>(null);
  const [selecting, setSelecting] = useState<'start' | 'end'>('start');
  const [viewDate, setViewDate] = useState(() => value?.[0] || new Date());

  const [startDate, endDate] = value || [null, null];
  const year = viewDate.getFullYear();
  const month = viewDate.getMonth();

  const isDisabled = useCallback(
    (date: Date): boolean => {
      if (disabledDate?.(date)) return true;
      if (minDate && date < minDate) return true;
      if (maxDate && date > maxDate) return true;
      return false;
    },
    [disabledDate, minDate, maxDate]
  );

  const isInRange = useCallback(
    (date: Date): boolean => {
      if (!startDate) return false;
      const end = endDate || hoverDate;
      if (!end) return false;

      const start = startDate < end ? startDate : end;
      const finish = startDate < end ? end : startDate;

      return date >= start && date <= finish;
    },
    [startDate, endDate, hoverDate]
  );

  const calendarDays = useMemo(() => {
    const days: Array<{ date: Date; isCurrentMonth: boolean }> = [];
    const daysInMonth = getDaysInMonth(year, month);
    const firstDay = getFirstDayOfMonth(year, month);
    const startOffset = (firstDay - weekStartsOn + 7) % 7;
    const prevMonthDays = getDaysInMonth(year, month - 1);

    for (let i = startOffset - 1; i >= 0; i--) {
      days.push({ date: new Date(year, month - 1, prevMonthDays - i), isCurrentMonth: false });
    }
    for (let i = 1; i <= daysInMonth; i++) {
      days.push({ date: new Date(year, month, i), isCurrentMonth: true });
    }
    const remaining = 42 - days.length;
    for (let i = 1; i <= remaining; i++) {
      days.push({ date: new Date(year, month + 1, i), isCurrentMonth: false });
    }

    return days;
  }, [year, month, weekStartsOn]);

  const dayHeaders = useMemo(() => {
    const headers = [...DAYS_SHORT];
    if (weekStartsOn === 1) headers.push(headers.shift()!);
    return headers;
  }, [weekStartsOn]);

  const handleDateClick = (date: Date) => {
    if (isDisabled(date)) return;

    if (selecting === 'start') {
      onChange?.([date, date]);
      setSelecting('end');
    } else {
      if (startDate && date < startDate) {
        onChange?.([date, startDate]);
      } else if (startDate) {
        onChange?.([startDate, date]);
      }
      setSelecting('start');
    }
  };

  return (
    <div className={`calendar calendar--range ${className}`}>
      <div className="calendar__header">
        <button
          type="button"
          className="calendar__nav"
          onClick={() => setViewDate(new Date(year, month - 1, 1))}
        >
          ‹
        </button>
        <span className="calendar__title">
          {MONTHS[month]} {year}
        </span>
        <button
          type="button"
          className="calendar__nav"
          onClick={() => setViewDate(new Date(year, month + 1, 1))}
        >
          ›
        </button>
      </div>

      <div className="calendar__weekdays">
        {dayHeaders.map((day) => (
          <div key={day} className="calendar__weekday">
            {day}
          </div>
        ))}
      </div>

      <div className="calendar__days">
        {calendarDays.map(({ date, isCurrentMonth }) => {
          const isSelected =
            (startDate && isSameDay(date, startDate)) ||
            (endDate && isSameDay(date, endDate));
          const inRange = isInRange(date);

          return (
            <button
              key={date.toISOString()}
              type="button"
              className={`calendar__day ${
                !isCurrentMonth ? 'calendar__day--outside' : ''
              } ${isToday(date) ? 'calendar__day--today' : ''} ${
                isSelected ? 'calendar__day--selected' : ''
              } ${inRange ? 'calendar__day--in-range' : ''} ${
                isDisabled(date) ? 'calendar__day--disabled' : ''
              }`}
              onClick={() => handleDateClick(date)}
              onMouseEnter={() => setHoverDate(date)}
              onMouseLeave={() => setHoverDate(null)}
              disabled={isDisabled(date)}
            >
              <span className="calendar__day-number">{date.getDate()}</span>
            </button>
          );
        })}
      </div>
    </div>
  );
}

// ============ MiniCalendar Component ============

export interface MiniCalendarProps {
  value?: Date | null;
  onChange?: (date: Date) => void;
  className?: string;
}

export function MiniCalendar({ value, onChange, className = '' }: MiniCalendarProps) {
  return (
    <Calendar
      value={value}
      onChange={onChange}
      className={`calendar--mini ${className}`}
    />
  );
}

export default Calendar;
