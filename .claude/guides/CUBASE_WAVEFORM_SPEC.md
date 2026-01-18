# Cubase-Class Waveform Rendering Specification

## HARD NON-NEGOTIABLES

1. **NEVER compute waveform from raw WAV on Flutter UI thread**
2. **NEVER rebuild peak cache on zoom/scroll** - cache built per asset once
3. **NEVER choose mip level coarser than pixel window** (`bucketFrames > framesPerPixel` loses transients)
4. **Zoom must feel instant** - show resampled tiles immediately, refine in background
5. **Peak-preserving at ALL zoom levels** - no transient ever disappears

---

## PART 1 — Waveform Correctness

### 1.1 Cache Data Per Bucket Per Channel

Store for each bucket:
```rust
struct WaveformBucket {
    min: f32,
    max: f32,
    rms: f32,           // sqrt(mean(x^2))
    peak_abs: f32,      // max(abs(min), abs(max))
    trans_score: f32,   // transient strength
}
```

**Mip Levels:**
- Level 0: 256 frames/bucket (or finer: 4, 8, 16, 32...)
- Each level doubles: 512, 1024, 2048...
- Stop when bucketFrames >= ~1 second

### 1.2 Pixel-Exact Aggregation (CRITICAL ALGORITHM)

```
For each pixel x in [0..pixelWidth):
    tl_f0 = floor(startFrameTL + x * framesPerPixel)
    tl_f1 = floor(startFrameTL + (x+1) * framesPerPixel)
    if tl_f1 == tl_f0: tl_f1 = tl_f0 + 1

    src_f0 = mapTLToSrc(tl_f0)  // Use SAME rounding as playback!
    src_f1 = mapTLToSrc(tl_f1)

    // Choose mip level: bucketFrames[L] <= framesPerPixel
    // NEVER pick coarser level!

    // Aggregate buckets in [src_f0, src_f1):
    pixelMin  = min(bucket.min)
    pixelMax  = max(bucket.max)
    pixelRMS  = sqrt(weightedSum(rms²×frames) / totalFrames)
```

### 1.3 Sample Mode (framesPerPixel <= 1.5)

- Fetch raw samples for visible window
- Draw polyline of actual samples
- Enable pencil/sample editing

### 1.4 Transient Hitpoints

**transScore calculation:**
```rust
trans_score = max(|s[n] - s[n-1]|)  // in bucket
```

**Hitpoint detection:**
- Local maximum in transScore above threshold
- Minimum distance 5-20ms between hitpoints
- Store in source frame domain

---

## PART 2 — Performance: Tile Cache + Progressive Refinement

### 2.1 Tile Architecture

- TILE_W = 256 px
- Tile key: `(assetId, clipId, zoomKey, tileX)`
- zoomKey = quantized, not raw float

### 2.2 Two-Stage Rendering

**On zoom:**

**STAGE 1 (instant):**
- Reuse cached tiles, resample/scale (GPU op)
- Immediate feedback, no hitch

**STAGE 2 (refine):**
- Background request exact peak data
- Replace placeholders when ready

### 2.3 LRU Caches

- Bitmap tile cache: 2000-5000 tiles
- Evict offscreen tiles first

### 2.4 Batch FFI Requests

```rust
query_waveform_tiles_batch(Vec<TileQuery>) -> Vec<TilePeakBlock>
```

Never 1 call per tile!

---

## PART 3 — Drawing Style (Cubase Look)

### 3.1 Body + Peaks

For each pixel column:
```dart
// RMS body (solid fill)
yTopBody = mid - rms * scale
yBotBody = mid + rms * scale
drawFilledRect(x, yTopBody, 1, yBotBody - yTopBody)

// Peak stroke (thin line for transients)
yTopPeak = mid - max * scale
yBotPeak = mid - min * scale
drawLine(x, yTopPeak, x, yBotPeak)
```

### 3.2 Subpixel Crispness

- Align strokes on half pixels: `y = floor(y) + 0.5`
- Batch using Path, not per-pixel drawLine

---

## PART 4 — Zoom Behavior

### 4.1 Zoom at Cursor

```dart
// Keep sample under cursor fixed
cursorTL = viewStart + cursorPx * framesPerPixel
newViewStart = cursorTL - cursorPx * newFramesPerPixel
```

### 4.2 Zoom Smoothing

- Short animation 80-160ms
- During animation: reuse resampled tiles
- Request refine after animation settles

---

## PART 5 — Acceptance Tests

### 5.1 Peak Preservation Test
```
displayedMax == trueMax (within epsilon)
displayedMin == trueMin
```

### 5.2 Drift Test
- Transient frame position stable across zoom changes

### 5.3 Performance Test
- 200 tracks: 60fps scroll/zoom
- Batch queries don't stall UI

---

## PART 6 — Rust↔Flutter API

```rust
// Waveform
ensure_wave_cache(assetPath) -> cacheId
query_tiles_batch(Vec<TileQuery>) -> Vec<TilePeakBlock>
query_samples_window(assetId, start, count) -> RawSamples

// Hitpoints
detect_hitpoints(assetId, options) -> Vec<Hitpoint>
query_hitpoints_in_range(assetId, start, end) -> Vec<Hitpoint>
```

---

## Implementation Priority

1. **Fix accuracy** - peak-preserving mip selection
2. **Fix transient visibility** - body+peaks style + hitpoints
3. **Fix zoom performance** - tiles + progressive refine + batching
