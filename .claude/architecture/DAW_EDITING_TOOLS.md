# DAW Editing Tools — Implementation Reference

Reference document based on Logic Pro X and Cubase behavior.
Target: FluxForge Studio DAW timeline tool implementation.

---

## Table of Contents

1. [Tool Switching & Toolbar](#tool-switching--toolbar)
2. [Selection / Pointer Tool](#1-selection--pointer-tool)
3. [Cut / Scissors Tool](#2-cut--scissors-tool)
4. [Crossfade Tool](#3-crossfade-tool)
5. [Fade Tool](#4-fade-tool)
6. [Glue / Join Tool](#5-glue--join-tool)
7. [Zoom Tool](#6-zoom-tool)
8. [Mute Tool](#7-mute-tool)
9. [Eraser / Delete Tool](#8-eraser--delete-tool)
10. [Slip / Trim Tool](#9-slip--trim-tool)
11. [Range / Marquee Selection](#10-range--marquee-selection)
12. [Clip Gain / Volume Handle](#clip-gain--volume-handle)
13. [Snap & Grid System](#snap--grid-system)
14. [Undo Behavior](#undo-behavior)

---

## Tool Switching & Toolbar

### Logic Pro X

- **T key** opens Tool Menu popup at cursor — then press letter to select tool
- **Dual toolbox**: Left slot = left-click tool, Right slot = Cmd-click tool
- **Third slot** (optional): Right-click tool (enable in Preferences > Editing > Right Mouse Button > "Is Assignable to a Tool")
- **Tool letter shortcuts** (press T first, then letter):
  - Pointer: T (default, pressing T alone reverts to Pointer)
  - Pencil: P
  - Eraser: E
  - Scissors: I
  - Glue/Join: J
  - Solo: S
  - Mute: M
  - Zoom: Y
  - Fade: A
  - Marquee: R
  - Flex: X
  - Automation Select: U
  - Automation Curve: W
- **Click Zones** (Smart Tool concept): When enabled in Preferences > General > Editing:
  - **Fade Tool Click Zones**: Pointer over upper-left/upper-right edges of region = Fade pointer activates automatically
  - **Marquee Click Zones**: Pointer over lower half of region (excluding corners) = Marquee pointer activates automatically
  - **Loop Click Zones**: Hold Option in fade click zone area = Loop pointer
  - **Resize zones**: Lower-left/lower-right edges = Resize pointer

### Cubase

- **Number keys 1-9** select tools directly (no prefix key needed):
  - 1: Object Selection (Pointer)
  - 2: Range Selection
  - 3: Split (Scissors)
  - 4: Glue
  - 5: Erase
  - 6: Zoom
  - 7: Mute
  - 8: Draw (Pencil)
  - 9: Play
  - 0: Drumstick (for drum editor)
- **Right-click toolbox**: Enable "Pop-up Toolbox on Right-Click" in Preferences > Editing > Tools. Shows toolbox at cursor position. Hold any modifier + right-click = context menu instead.
- **Combine Selection Tools Mode**: Activatable on toolbar — divides track height into two zones:
  - **Upper zone**: Range Selection tool activates automatically
  - **Lower zone**: Object Selection tool activates automatically
  - Track height must be at least 2 rows for this to work
  - Cursor changes automatically based on vertical position within the track
- **Tool Modifiers**: Fully configurable in Preferences > Editing > Tool Modifiers. Each tool has configurable modifier key behaviors.

---

## 1. Selection / Pointer Tool

### Primary Click Behavior

| Action | Logic Pro X | Cubase |
|--------|------------|--------|
| Click on clip | Selects clip, deselects others | Selects event, deselects others |
| Click on empty area | Deselects all, moves playhead | Deselects all, moves cursor (if "Locate When Clicked in Empty Space" is on) |
| Click on selected clip | Keeps selection (prepare for drag) | Keeps selection (prepare for drag) |

### Drag Behavior

| Action | Logic Pro X | Cubase |
|--------|------------|--------|
| Drag selected clip | Moves clip (snaps to grid) | Moves event (snaps to grid) |
| Drag from empty area | Rubber-band / lasso selection | Rubber-band selection |
| Drag clip edge (lower-left/right) | Resizes clip (trims start/end) | Resizes event (Normal Sizing mode by default) |

### Modifier Keys

| Modifier | Logic Pro X | Cubase |
|----------|------------|--------|
| **Shift + click** | Add to / remove from selection (toggle) | Add to / remove from selection (toggle) |
| **Option/Alt + drag** | Duplicate clip (copy-drag) | Duplicate event (copy-drag) |
| **Shift + drag** | Constrain movement to vertical axis only (lock horizontal position) | Constrain movement (configurable) |
| **Cmd + click** | Activates Command-click tool (secondary tool) | Depends on tool modifier settings |
| **Ctrl + drag** | Bypass snap, move in fine increments (division steps) | Bypass snap temporarily |
| **Ctrl + Shift + drag** | Move in tick/sample increments | — |
| **Option + Shift + click** | Add clicked track's regions to selection | — |
| **Cmd + Alt + drag** | — | Resize with fade adaptation |

### Cursor Appearance

| Zone | Logic Pro X | Cubase |
|------|------------|--------|
| Center of clip | Arrow pointer | Arrow pointer |
| Lower-left/right edge | Resize pointer (bracket with arrows) | Resize pointer (when near edge) |
| Upper-left/right edge | Fade pointer (if click zones enabled) | — (fades via handles) |
| Lower half of clip | Marquee crosshair (if click zones enabled) | Range tool (if Combine Selection Tools active) |

### Cubase Object Selection — Sizing Sub-Modes

Cubase's Object Selection tool has three sizing sub-modes (selected via dropdown on the tool):

1. **Normal Sizing**: Dragging clip edge reveals/hides content. Audio stays in place, boundary moves. Standard trim behavior.
2. **Sizing Moves Contents**: Dragging clip edge moves the audio with the boundary. The content slides as you resize. (Equivalent to slip + trim in one operation.)
3. **Sizing Applies Time Stretch**: Dragging clip edge time-stretches the audio to fit the new length. MIDI notes get repositioned; audio gets processed.

---

## 2. Cut / Scissors Tool

### Primary Click Behavior

| Action | Logic Pro X | Cubase |
|--------|------------|--------|
| Click on clip | Splits clip at click position (respects snap/grid) | Splits event at click position (respects snap/grid) |
| Click on empty area | No effect | No effect |

### Modifier Keys

| Modifier | Logic Pro X | Cubase |
|----------|------------|--------|
| **Option/Alt + click** | **Multiple equal cuts**: Splits clip into equal segments. Cut position defines first segment length; rest of clip is divided into segments of that same length. Example: clicking at bar 3 of a 16-bar region creates eight 2-bar segments. Plus sign (+) appears next to scissors cursor. | **Split at cursor**: Alt is the split modifier when using the Object Selection tool (configurable) |
| **Ctrl + drag** | **Scrub with precision**: Bypass snap grid, scrub at tick level when zoomed in close enough | Bypass snap temporarily |
| **Cmd + click** | — | Split behavior depends on tool modifier settings (may not snap to grid with Cmd) |

### Snap/Grid Interaction

- **Both DAWs**: Cut position snaps to current grid value by default
- **Logic**: Grid resolution follows the Snap popup menu (Smart, Bar, Beat, Division, Ticks, QF, Samples)
- **Cubase**: Grid resolution follows the Snap Type and Grid Type settings
- **Override**: Hold Ctrl (Logic) or the configured modifier (Cubase) to bypass snap

### Crossfade Boundary Behavior

- Cutting at a crossfade boundary: The crossfade is removed/split. Each resulting clip retains its individual fade settings.
- Logic: If the cut falls within a crossfade, the crossfade is removed and new region edges are created.
- Cubase: Crossfade is removed on cut. You can re-create crossfades afterward.

### Cursor Appearance

- Logic: Scissors icon. With Option held: scissors + plus sign (+).
- Cubase: Scissors icon.

---

## 3. Crossfade Tool

### Logic Pro X — Crossfade Creation

Logic Pro does NOT have a dedicated crossfade tool. Crossfades are created via:

1. **Fade Tool**: Drag across the boundary between two adjacent/overlapping regions
2. **Menu**: Select both regions > Edit > Fade > Create Crossfade
3. **Key command**: Assignable via Key Commands
4. **Automatic**: Enable in Preferences > General > Editing > "Auto-crossfade on region overlap"

### Cubase — Crossfade Creation

1. **Selection + shortcut**: Select two adjacent events, press X to create default crossfade
2. **Drag overlap**: Move one event to overlap another — crossfade is auto-applied if Auto Crossfade is enabled
3. **Range Selection tool**: Select a range spanning the boundary, then apply crossfade
4. **Double-click** the crossfade area to open the Crossfade Editor

### Crossfade Types

| Type | Logic Pro X | Cubase |
|------|------------|--------|
| **Linear (X)** | Straight-line gain change. Fade-out and fade-in are linear. Can cause slight volume dip at midpoint. | **Equal Gain**: Linear crossfade where summed amplitudes are constant. Adjustable curve points. |
| **Equal Power (EqP)** | Compensates for the volume dip of linear crossfade. Maintains consistent perceived loudness. Curves are concave/convex. | **Equal Power**: Maintains constant power through the crossfade. Single editable curve point only — shape is locked. |
| **S-Curve (X S)** | S-shaped crossfade curve. Slow start, fast middle, slow end. Smooth transitions. | Available via custom curve editing in the Crossfade Editor. |
| **Speed Up / Slow Down** | Additional parameters in Region Inspector — accelerate/decelerate the crossfade rate | — (achieved via custom curve points) |

### Crossfade Editing

**Logic Pro X:**
- Drag crossfade edges to resize
- Hover middle of crossfade with Fade tool = curve adjustment cursor appears
- Cmd + drag curve = bend/reshape the fade curve
- Region Inspector shows: Fade Time, Curve value (negative/positive/zero = concave/convex/linear), Type dropdown (Out, X, EqP, X S)

**Cubase — Crossfade Editor** (double-click crossfade to open):
- Separate fade-in and fade-out curves displayed
- Curve interpolation modes: Spline, Damped Spline, Linear
- Click on curve to add control points
- Drag points to reshape
- Drag point outside display to remove it
- Presets: Save/Load/Set as Default
- Equal Power mode: only one curve point, shape is locked
- Equal Gain mode: fully editable curve points
- Preview (Play) button to audition crossfade
- Length field to set crossfade duration numerically

### Visual Representation

- **Logic**: Shaded overlay area at region boundary. Curve line visible within the shaded zone.
- **Cubase**: X-shaped crossfade icon between events. Shaded area shows crossfade zone. Waveform display within crossfade editor shows both fade-in and fade-out waveforms overlaid.

---

## 4. Fade Tool

### Logic Pro X — Fade Tool (key: A)

**Fade-In** (drag from left edge rightward):
- Hover pointer over upper-left corner of region = fade pointer appears (if click zones enabled, or when Fade tool is active)
- Click and drag rightward into the region
- Shaded triangular area appears showing fade duration
- Release to set fade length

**Fade-Out** (drag from right edge leftward):
- Same as above but from upper-right corner, dragging leftward

**Curve Adjustment**:
- After creating a fade, hover over the middle of the fade curve
- Cursor changes to curve-adjustment variant of the Fade tool
- Click and drag up/down to change curve shape (convex/concave)
- Cmd + click + drag the curve line = fine-grained curve bending

### Cubase — Fade Handles (no dedicated Fade tool)

Cubase uses **event handles** rather than a dedicated tool:
- **Fade-in handle**: Triangular handle at upper-left corner of event. Drag rightward to create fade-in.
- **Fade-out handle**: Triangular handle at upper-right corner of event. Drag leftward to create fade-out.
- **Volume handle**: Square handle at top-center of event. Drag up/down to set clip gain.
- Handles are always visible (or configure in Preferences > Event Display > Audio > "Show Event Volume Curves Always")
- Double-click a fade area to open the **Fade Dialog**

### Fade Curve Types

| Curve | Logic Pro X | Cubase |
|-------|------------|--------|
| **Linear** | Straight line from start to end level | Linear interpolation |
| **Exponential** | Fast initial change, slowing toward end | Available via curve point editing |
| **Logarithmic** | Slow initial change, accelerating toward end | Available via curve point editing |
| **S-Curve** | Slow-fast-slow transition | Available via Spline/Damped Spline interpolation |
| **Custom** | Cmd + drag to bend curve freely | Click curve to add points, drag to shape |

### Fade Curve Dialog (Cubase)

- **Spline Interpolation**: Smooth curves through control points
- **Damped Spline Interpolation**: Smoother, less overshoot than regular spline
- **Linear Interpolation**: Straight-line segments between points
- **Preset curves**: Quick-access buttons for common shapes
- Add points by clicking on curve
- Remove points by dragging outside display
- Save as preset / Set as default

### Interaction with Volume Automation

- **Logic**: Fades are region-based (pre-fader). Volume automation is track-based (post-fader). Both are independent. Fades apply first, then automation.
- **Cubase**: Event fades are event-based (pre-fader). Track automation applies after. The event volume handle is also pre-fader but independent of fade curves.

### Visual Representation

- **Logic**: Shaded area with curve line. Color matches region tint. Duration shown on hover.
- **Cubase**: Fade curve drawn on event. Waveform updates to reflect faded appearance. Handle triangles visible at corners.

---

## 5. Glue / Join Tool

### Logic Pro X — Join Tool (key: J)

**Primary click behavior:**
- Click a clip with the Join tool: no effect on single clip
- Select multiple clips first (with Shift or rubber-band), then click any of them with Join tool: joins them into one

**Drag behavior:**
- Drag across multiple clips with Join tool to select and join them
- Shift + click additional clips with Join tool to add to selection, then click to join

**What happens internally:**
- If all selected clips come from the **same original audio file** AND are in their **original relative positions**: No new file is created — a single extended region is created (non-destructive)
- If clips are from **different source files** or have been moved: A **mixdown occurs** — Logic creates a new audio file on disk, adds it to the Project Audio Browser
- **Overlapping clips**: You are prompted to create a new audio file. Clips are mixed down together with no volume changes. Takes the name of the first region.
- MIDI regions: Always joined non-destructively into a single container region

### Cubase — Glue Tool (key: 4)

**Primary click behavior:**
- Click an event with the Glue tool: glues it to the next adjacent event on the same track
- If events were originally **split from the same event**: An event is recreated (non-destructive, no new file)
- If events are from **different sources**: A **Part** container is created (not a new audio file — it's a container holding references to the events)

**Drag behavior:**
- Not a standard drag operation — you click on events sequentially

**Known behavior:**
- Gluing events with crossfades between them: **crossfades are removed** (except possibly the first one). This is a known limitation.
- To merge into a new audio file: Use **Audio > Bounce Selection** instead of Glue
- Bounce Selection: Creates a new audio file, replaces selected events with single event referencing new file

### Modifier Keys

| Modifier | Logic Pro X | Cubase |
|----------|------------|--------|
| Shift + click | Add to join selection | — |
| Alt + click | — | Glue all following events on track into one |

---

## 6. Zoom Tool

### Logic Pro X (key: Y)

**Primary click behavior:**
- Click: Zoom in one step centered on click position
- Option + click: Zoom out one step

**Drag behavior:**
- Drag a rectangle: Zoom to fit that rectangle in the visible area (both horizontal and vertical)
- The selected area fills the window

**Key commands:**
- Cmd + Arrow keys for horizontal/vertical zoom
- Z: Zoom to fit all (Toggle Zoom to Fit / Undo Zoom)
- Ctrl + Option + drag: Zoom horizontally by dragging left/right

### Cubase (key: 6)

**Primary click behavior:**
- Click: Zoom in one step centered on click position
- Cmd/Ctrl + click: Zoom out one step

**Drag behavior:**
- Drag a rectangle: Zoom to fit that rectangle
- Horizontal and vertical zoom simultaneously when holding Cmd/Ctrl while dragging with Zoom tool

**Additional zoom features:**
- G / H: Zoom in / Zoom out horizontally
- Shift + G / Shift + H: Zoom in / Zoom out vertically
- Zoom to Selection: Alt + S (or Edit > Zoom > Zoom to Selection)
- Zoom presets: Store/recall zoom states

### Snap/Grid Interaction
- Zoom tool ignores snap settings — it operates on visual coordinates, not musical time

---

## 7. Mute Tool

### Logic Pro X (key: M)

**Primary click behavior:**
- Click an unmuted clip: Mutes it (dims visual appearance, stops playback of that clip)
- Click a muted clip: Unmutes it (toggle behavior)
- If multiple clips are selected: The clicked clip's resulting mute state is applied to ALL selected clips

**Visual feedback:**
- Muted clips appear dimmed/grayed out with a dot indicator
- Waveform is still visible but with reduced opacity

### Cubase (key: 7)

**Primary click behavior:**
- Click an event: Toggles mute state
- Drag across events: All events touched by the drag are muted (mute-as-you-highlight)

**Modifier keys:**
- Shift + M: Mute selected events (without needing the Mute tool active)
- Shift + U: Unmute selected events

**Visual feedback:**
- Muted events appear with an X overlay or grayed out appearance
- Event is still visible in the timeline but greyed

### Both DAWs
- Mute is per-clip, not per-track (track mute is separate)
- Muted clips are skipped during playback but remain in the arrangement
- Fully undoable — single undo step per mute/unmute action

---

## 8. Eraser / Delete Tool

### Logic Pro X (key: E)

**Primary click behavior:**
- Click any clip: Deletes it immediately (whether selected or not)
- If multiple clips are selected AND you click one of them: ALL selected clips are deleted
- If you click an unselected clip: Only that clip is deleted (regardless of current selection)

**No drag behavior** — click-only operation

### Cubase (key: 5)

**Primary click behavior:**
- Click an event: Deletes it immediately
- Drag across events: All events touched are deleted

**Modifier keys:**
- Delete/Backspace key: Deletes selected events (without needing Eraser tool)

### Both DAWs
- Deletion is undoable (Cmd + Z)
- Deleting a clip does NOT delete the source audio file from disk
- Only removes the clip/event reference from the arrangement

---

## 9. Slip / Trim Tool

### Slip Editing (moving audio within fixed clip boundaries)

**Logic Pro X:**
- No dedicated slip tool — use key commands:
  - **Ctrl + Option + Left Arrow**: Slip content left by nudge value
  - **Ctrl + Option + Right Arrow**: Slip content right by nudge value
- The clip boundaries stay fixed. The audio inside slides left or right.
- Also accessible via Edit > Move > Slip Left / Slip Right
- Nudge value determines slip amount (configurable)

**Cubase — "Sizing Moves Contents" mode:**
- Select Object Selection tool > choose "Sizing Moves Contents" from dropdown
- Drag either edge of the event: boundary moves AND content moves with it
- This is the closest equivalent to slip editing — by resizing one edge, the content shifts
- Alternative: Alt + drag content within a part to reposition it

### Trim Editing (changing clip boundaries to reveal/hide audio)

**Logic Pro X:**
- Pointer tool: Drag lower-left or lower-right edge of region
- Cursor changes to resize/trim pointer (bracket shape)
- Dragging reveals or hides underlying audio
- Content position stays fixed — only the boundary moves
- Snaps to grid by default; hold Ctrl to bypass snap

**Cubase — "Normal Sizing" mode:**
- Default mode for Object Selection tool
- Drag lower-left or lower-right corner of event
- Reveals or hides audio content
- Audio position stays fixed — only the boundary moves
- Snaps to grid; hold Ctrl/Cmd to bypass

### Key Difference: Slip vs. Trim

| Operation | Boundaries | Content Position |
|-----------|-----------|-----------------|
| **Trim** | Move | Fixed |
| **Slip** | Fixed | Move |
| **Cubase "Sizing Moves Contents"** | Move | Moves with boundary |

---

## 10. Range / Marquee Selection

### Logic Pro X — Marquee Tool (key: R)

**Primary click behavior:**
- Click: Sets a point selection (very narrow range)

**Drag behavior:**
- Drag across timeline: Creates a time range selection (crosshair cursor)
- Selection spans time (horizontal) and tracks (vertical)
- Can select across multiple tracks simultaneously
- Can select WITHIN a region — only the selected portion is affected by operations

**Operations on Marquee selection:**
- **Delete**: Removes the selected portion from clips, creating a gap (or closing the gap depending on drag mode)
- **Cut (Cmd + X)**: Cuts selection to clipboard
- **Copy (Cmd + C)**: Copies selection to clipboard
- **Option + drag**: Copy-drag the selected range to a new position
- **Bounce (Selection-Based Processing)**: Functions > Selection-Based Processing to apply effects to just the selected range
- **Split at Marquee edges**: Clicking with the Pointer tool within a Marquee selection splits at both edges automatically
- **Play**: Pressing Space plays only the Marquee-selected range (if preference is set)

**Modifier keys:**
- Shift + drag: Extend existing Marquee selection
- Option + drag selection: Copy the selection to new position

### Cubase — Range Selection Tool (key: 2)

**Primary click behavior:**
- Click: Sets position for range start

**Drag behavior:**
- Drag across timeline: Creates a time range selection
- Selection spans tracks vertically
- Can cross event boundaries — range is independent of events

**Operations on Range selection:**
- **Delete**: Removes content within range
- **Cut Time (Shift + Ctrl/Cmd + X)**: Cuts range and closes gap — all events on all tracks shift left
- **Paste Time (Shift + Ctrl/Cmd + V)**: Inserts clipboard content at cursor, pushing existing content right
- **Insert Silence (Ctrl/Cmd + Shift + E)**: Inserts empty space at range, pushing content right
- **Bounce Selection**: Creates new audio file from range content
- **Split at range boundaries**: Automatic when performing cut/copy on a range

**Modifier keys:**
- Shift + drag: Extend/modify range selection
- Ctrl/Cmd + Shift + drag: Select range across ALL tracks (not just visible/clicked tracks)
- Alt + Shift + drag: Range with snap override
- Double-click an event: Selects the event's full time range

### Key Differences

| Feature | Logic Marquee | Cubase Range |
|---------|--------------|--------------|
| Dedicated tool | Yes (or via click zones) | Yes (key 2) |
| Can select within clips | Yes | Yes |
| Cut Time (close gap) | Via Cmd+X + preference | Shift+Ctrl+X |
| Insert silence | — (use other methods) | Ctrl+Shift+E |
| Selection-based processing | Yes (Functions menu) | Via Bounce or Direct Offline Processing |

---

## Clip Gain / Volume Handle

### Logic Pro X — Region Gain

- **Access**: Region Inspector panel (press I with region selected) > Gain parameter
- **Gain tool**: Dedicated tool — hover over region shows gain value in dB as yellow line across region
- **Drag behavior**: Click and drag up/down to increase/decrease gain
- **Range**: -30 dB to +30 dB (60 dB total range)
- **Visual**: Yellow horizontal line across region at current gain level. Waveform redraws to reflect gain change.
- **Signal path**: Clip gain is PRE-fader, PRE-automation. First gain stage in the signal chain.
- **Display**: Numerical dB value shown at cursor during adjustment

### Cubase — Event Volume Handle

- **Handle location**: Square handle at top-center of event
- **Drag behavior**: Drag up/down to change event volume
- **Fade handles**: Triangular handles at upper-left (fade-in) and upper-right (fade-out) corners
- **Visual**: Horizontal line across event at current volume level. Waveform display updates.
- **Volume curve**: Can draw volume automation directly on events using the Draw tool
- **Preferences**: "Show Event Volume Curves Always" in Preferences > Event Display > Audio (otherwise only visible on hover)
- **Signal path**: Event volume is PRE-fader. Applied before channel fader and automation.

### Implementation Notes

- Clip gain/volume handle operates independently of track automation
- Both are non-destructive — original audio file is unmodified
- The gain line should snap to 0 dB as a magnetic point (user expects easy return to unity)
- Fine adjustment: hold modifier key for finer dB increments
- Display should show both the gain value (dB) and the resulting peak level

---

## Snap & Grid System

### Logic Pro X — Snap Modes

| Mode | Behavior |
|------|----------|
| **Smart** (default) | Auto-selects grid resolution based on zoom level. Zoomed out = bars. Zoomed in = beats/divisions/ticks. |
| **Bar** | Snaps to bar boundaries |
| **Beat** | Snaps to beat boundaries |
| **Division** | Snaps to division (sub-beat) boundaries |
| **Ticks** | Snaps to MIDI tick boundaries |
| **QF** | Quarter frames (SMPTE) |
| **Samples** | Sample-accurate snap |

**Absolute vs. Relative:**
- **Absolute** (default): Items snap exactly to grid positions. A clip dragged near beat 2 will land exactly on beat 2.
- **Relative**: Items maintain their offset from the grid while moving in grid-sized increments. A clip starting at beat 2.3 moved by one beat lands at beat 3.3.

**Override modifiers:**
- Ctrl + drag: Move in steps of one division
- Ctrl + Shift + drag: Move in tick/sample steps
- No modifier: Follows current Snap mode

### Cubase — Snap Types

| Snap Type | Behavior |
|-----------|----------|
| **Grid** | Snaps to grid positions (absolute — events jump to grid lines) |
| **Grid Relative** | Maintains relative offset while moving in grid steps |
| **Events** | Snaps to start/end of other events (magnetic) |
| **Shuffle** | Events push adjacent events when moved |
| **Magnetic Cursor** | Snaps to project cursor position |
| **Grid + Cursor** | Combination of Grid and Magnetic Cursor |
| **Events + Cursor** | Combination of Events and Magnetic Cursor |
| **Grid + Events** | Combination of Grid and Events |
| **Grid + Events + Cursor** | All three combined |

**Grid Type dropdown:** Bar, Beat, Use Quantize (follows quantize value)

**Override:** Ctrl/Cmd + drag to temporarily disable snap

### Tool-Snap Interaction

- **All move/resize/split operations** respect snap by default
- **Zoom tool**: Ignores snap entirely (works on pixel coordinates)
- **Mute/Eraser tools**: Ignore snap (operate on whole clips)
- **Scissors**: Respects snap for cut position
- **Fade/Crossfade**: Respects snap for fade length
- **Marquee/Range**: Respects snap for range boundaries

---

## Undo Behavior

### Logic Pro X

- **Cmd + Z**: Undo last action
- **Cmd + Shift + Z**: Redo
- **Undo History**: Edit > Undo History — shows complete list of undoable actions
- **Max steps**: Configurable up to 200 (Settings > General > Editing)
- **Granularity**: Each tool action = one undo step (move, resize, split, delete, mute, fade change, etc.)
- **Separate undo stacks**:
  - Arrangement undo (main)
  - Mixer undo (separate — mixer changes don't pollute arrangement undo)
  - Plugin undo (each plugin has its own stack — undo/redo buttons in plugin window)
- **Selective undo**: Cmd + click an entry in Undo History to undo only that specific action (preserving later edits)
- All three stacks can be viewed together in integrated Undo History window

### Cubase

- **Ctrl/Cmd + Z**: Undo
- **Ctrl/Cmd + Shift + Z**: Redo
- **Edit History**: Edit > History — sequential undo/redo list
- **Max steps**: Configurable in Preferences > General (default varies by version)
- **MixConsole History**: Separate undo for mixer parameter changes
- **Limitation**: Cannot selectively undo a single action from the middle of the history — must undo sequentially

### Implementation Recommendations

- Each tool action should produce exactly ONE undo entry
- Drag operations: Record state at mouse-down, commit at mouse-up = one undo entry for the entire drag
- Group related operations: e.g., "Split and Delete" from Marquee = one undo entry
- Undo entry should store: affected clip ID, property changed, old value, new value
- Consider separate undo stacks for arrangement vs. mixer vs. plugin parameters

---

## Summary — Tool Comparison Matrix

| Tool | Logic Key | Cubase Key | Primary Action | Modifier Actions |
|------|-----------|------------|---------------|------------------|
| Pointer/Select | T (default) | 1 | Click=select, Drag=move | Opt=copy, Shift=constrain, Ctrl=fine |
| Scissors/Split | I | 3 | Click=split at point | Opt=multiple equal cuts (Logic), Alt=split from Select tool (Cubase) |
| Fade | A | — (handles) | Drag from edge=create fade | Cmd+drag=adjust curve |
| Crossfade | (via Fade tool) | X key | Drag across boundary | — |
| Glue/Join | J | 4 | Click=join with next | Shift=multi-select (Logic), Alt=glue all following (Cubase) |
| Zoom | Y | 6 | Click=zoom in, Drag=zoom rect | Opt/Cmd=zoom out |
| Mute | M | 7 | Click=toggle mute | Drag=mute all touched (Cubase) |
| Eraser | E | 5 | Click=delete | Drag=delete all touched (Cubase) |
| Marquee/Range | R | 2 | Drag=select time range | Shift=extend, Opt=copy range |
| Trim | (via Pointer) | (via Pointer) | Drag edge=resize clip | Ctrl=bypass snap |
| Slip | Ctrl+Opt+Arrows | Sizing Moves Contents | Nudge content within clip | — |
| Gain | (Inspector/Tool) | (Volume handle) | Drag=adjust clip gain | — |
