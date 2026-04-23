# Agent 13: DAWTools — Memory

## Accumulated Knowledge
- 15 razor actions: delete, split, cut, copy, paste, mute, join, fadeBoth, healSeparation, insertSilence, stripSilence, reverse, stretch, duplicate, move
- Smart Tool 13 zones with cursor wiring
- RazorEditProvider.executeAction() dispatches all razor ops to FFI
- Custom ln() replaced with dart:math log() (BUG #51)
- PitchShift debounced 50-100ms (BUG #77)

## Gotchas
- Project versions date needs padLeft(2, '0')
- Schema migration cascades version → schema_version → default 1
- Logical editor: range operators show "value1-value2"
