/**
 * ReelForge Mentions
 *
 * @mentions input component:
 * - Trigger on @ character
 * - Search suggestions
 * - Custom triggers
 * - Keyboard navigation
 *
 * @module mentions/Mentions
 */

import { useState, useRef, useCallback, useEffect, useMemo } from 'react';
import './Mentions.css';

// ============ Types ============

export interface MentionOption {
  id: string;
  label: string;
  avatar?: string;
  description?: string;
}

export interface MentionData {
  id: string;
  label: string;
  trigger: string;
  startIndex: number;
  endIndex: number;
}

export interface MentionsProps {
  /** Current value */
  value: string;
  /** On value change */
  onChange: (value: string) => void;
  /** Mention options */
  options: MentionOption[];
  /** Trigger character */
  trigger?: string;
  /** On mention select */
  onMention?: (mention: MentionData) => void;
  /** Placeholder */
  placeholder?: string;
  /** Disabled state */
  disabled?: boolean;
  /** Rows for textarea */
  rows?: number;
  /** Max suggestions to show */
  maxSuggestions?: number;
  /** Custom option render */
  renderOption?: (option: MentionOption) => React.ReactNode;
  /** Custom class */
  className?: string;
}

// ============ Mentions Component ============

export function Mentions({
  value,
  onChange,
  options,
  trigger = '@',
  onMention,
  placeholder = '',
  disabled = false,
  rows = 3,
  maxSuggestions = 10,
  renderOption,
  className = '',
}: MentionsProps) {
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const suggestionsRef = useRef<HTMLDivElement>(null);

  const [isOpen, setIsOpen] = useState(false);
  const [search, setSearch] = useState('');
  const [triggerIndex, setTriggerIndex] = useState(-1);
  const [highlightedIndex, setHighlightedIndex] = useState(0);
  const [position, setPosition] = useState({ top: 0, left: 0 });

  // Filter options by search
  const filteredOptions = useMemo(() => {
    if (!search) return options.slice(0, maxSuggestions);
    const lowerSearch = search.toLowerCase();
    return options
      .filter((opt) => opt.label.toLowerCase().includes(lowerSearch))
      .slice(0, maxSuggestions);
  }, [options, search, maxSuggestions]);

  // Get caret position
  const getCaretCoordinates = useCallback(() => {
    const textarea = textareaRef.current;
    if (!textarea) return { top: 0, left: 0 };

    // Create a hidden div to measure
    const div = document.createElement('div');
    const style = getComputedStyle(textarea);

    div.style.cssText = `
      position: absolute;
      visibility: hidden;
      white-space: pre-wrap;
      word-wrap: break-word;
      font: ${style.font};
      padding: ${style.padding};
      width: ${textarea.offsetWidth}px;
    `;

    const textBeforeCaret = value.substring(0, textarea.selectionStart);
    div.textContent = textBeforeCaret;

    const span = document.createElement('span');
    span.textContent = '|';
    div.appendChild(span);

    document.body.appendChild(div);

    const rect = textarea.getBoundingClientRect();
    const spanRect = span.getBoundingClientRect();
    const divRect = div.getBoundingClientRect();

    document.body.removeChild(div);

    return {
      top: spanRect.top - divRect.top + textarea.scrollTop + rect.top + 20,
      left: spanRect.left - divRect.left + rect.left,
    };
  }, [value]);

  // Handle input change
  const handleChange = useCallback(
    (e: React.ChangeEvent<HTMLTextAreaElement>) => {
      const newValue = e.target.value;
      const cursorPos = e.target.selectionStart;

      onChange(newValue);

      // Check for trigger character
      const textBeforeCursor = newValue.substring(0, cursorPos);
      const lastTriggerIndex = textBeforeCursor.lastIndexOf(trigger);

      if (lastTriggerIndex >= 0) {
        // Check if there's a space before trigger (or it's at start)
        const charBefore = textBeforeCursor[lastTriggerIndex - 1];
        if (lastTriggerIndex === 0 || charBefore === ' ' || charBefore === '\n') {
          const searchText = textBeforeCursor.substring(lastTriggerIndex + 1);

          // Check if search contains space (end of mention)
          if (!searchText.includes(' ') && !searchText.includes('\n')) {
            setSearch(searchText);
            setTriggerIndex(lastTriggerIndex);
            setIsOpen(true);
            setHighlightedIndex(0);
            setPosition(getCaretCoordinates());
            return;
          }
        }
      }

      setIsOpen(false);
    },
    [onChange, trigger, getCaretCoordinates]
  );

  // Select mention
  const selectMention = useCallback(
    (option: MentionOption) => {
      const textarea = textareaRef.current;
      if (!textarea || triggerIndex < 0) return;

      const beforeTrigger = value.substring(0, triggerIndex);
      const afterCursor = value.substring(textarea.selectionStart);
      const mentionText = `${trigger}${option.label} `;

      const newValue = beforeTrigger + mentionText + afterCursor;
      onChange(newValue);

      // Notify about mention
      onMention?.({
        id: option.id,
        label: option.label,
        trigger,
        startIndex: triggerIndex,
        endIndex: triggerIndex + mentionText.length - 1,
      });

      setIsOpen(false);
      setSearch('');
      setTriggerIndex(-1);

      // Set cursor position
      setTimeout(() => {
        const newCursorPos = triggerIndex + mentionText.length;
        textarea.setSelectionRange(newCursorPos, newCursorPos);
        textarea.focus();
      }, 0);
    },
    [value, onChange, trigger, triggerIndex, onMention]
  );

  // Keyboard navigation
  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if (!isOpen) return;

      switch (e.key) {
        case 'ArrowDown':
          e.preventDefault();
          setHighlightedIndex((prev) =>
            prev < filteredOptions.length - 1 ? prev + 1 : 0
          );
          break;
        case 'ArrowUp':
          e.preventDefault();
          setHighlightedIndex((prev) =>
            prev > 0 ? prev - 1 : filteredOptions.length - 1
          );
          break;
        case 'Enter':
        case 'Tab':
          e.preventDefault();
          if (filteredOptions[highlightedIndex]) {
            selectMention(filteredOptions[highlightedIndex]);
          }
          break;
        case 'Escape':
          e.preventDefault();
          setIsOpen(false);
          break;
      }
    },
    [isOpen, filteredOptions, highlightedIndex, selectMention]
  );

  // Close on outside click
  useEffect(() => {
    if (!isOpen) return;

    const handleClick = (e: MouseEvent) => {
      if (
        !textareaRef.current?.contains(e.target as Node) &&
        !suggestionsRef.current?.contains(e.target as Node)
      ) {
        setIsOpen(false);
      }
    };

    document.addEventListener('mousedown', handleClick);
    return () => document.removeEventListener('mousedown', handleClick);
  }, [isOpen]);

  // Scroll highlighted into view
  useEffect(() => {
    if (!isOpen || !suggestionsRef.current) return;

    const item = suggestionsRef.current.children[highlightedIndex] as HTMLElement;
    if (item) {
      item.scrollIntoView({ block: 'nearest' });
    }
  }, [highlightedIndex, isOpen]);

  return (
    <div className={`mentions ${className}`}>
      <textarea
        ref={textareaRef}
        value={value}
        onChange={handleChange}
        onKeyDown={handleKeyDown}
        placeholder={placeholder}
        disabled={disabled}
        rows={rows}
        className="mentions__input"
      />

      {isOpen && filteredOptions.length > 0 && (
        <div
          ref={suggestionsRef}
          className="mentions__suggestions"
          style={{ top: position.top, left: position.left }}
        >
          {filteredOptions.map((option, index) => (
            <div
              key={option.id}
              className={`mentions__option ${
                index === highlightedIndex ? 'mentions__option--highlighted' : ''
              }`}
              onClick={() => selectMention(option)}
              onMouseEnter={() => setHighlightedIndex(index)}
            >
              {renderOption ? (
                renderOption(option)
              ) : (
                <>
                  {option.avatar && (
                    <img
                      src={option.avatar}
                      alt=""
                      className="mentions__option-avatar"
                    />
                  )}
                  <div className="mentions__option-content">
                    <span className="mentions__option-label">{option.label}</span>
                    {option.description && (
                      <span className="mentions__option-desc">{option.description}</span>
                    )}
                  </div>
                </>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

// ============ useMentions Hook ============

export interface UseMentionsOptions {
  trigger?: string;
  options: MentionOption[];
}

export function useMentions({ trigger = '@', options }: UseMentionsOptions) {
  const [value, setValue] = useState('');
  const [mentions, setMentions] = useState<MentionData[]>([]);

  const handleMention = useCallback((mention: MentionData) => {
    setMentions((prev) => [...prev, mention]);
  }, []);

  const getMentions = useCallback(() => mentions, [mentions]);

  const clearMentions = useCallback(() => setMentions([]), []);

  return {
    value,
    setValue,
    mentions,
    handleMention,
    getMentions,
    clearMentions,
    mentionsProps: {
      value,
      onChange: setValue,
      options,
      trigger,
      onMention: handleMention,
    },
  };
}

export default Mentions;
