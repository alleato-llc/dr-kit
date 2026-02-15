# Architecture

## Module Structure

```
Sources/
├── DRKit/                     Library — public API
│   ├── DRAnalyzer.swift       Core computation + file/directory analysis
│   ├── DRFormatter.swift      Output formatters (table, JSON, CSV)
│   ├── Models.swift           TrackResult, AlbumResult, AnalysisEvent
│   └── Scanner.swift          Directory scanner for audio files
└── dr/                        Executable — reference TUI app
    ├── DR.swift               CLI entry point (ArgumentParser)
    └── TUI/
        ├── TUIMode.swift      Terminal setup, event loop
        ├── DRAppState.swift   Application state
        ├── DRTheme.swift      Tint theme
        ├── DRKeyHandler.swift Key dispatch
        └── DRRenderer.swift   Widget rendering
```

## Library vs Application

**DRKit** is the library target. It has a single dependency (LibAVKit for audio decoding) and exposes the full DR analysis API. Consumers import only `DRKit`.

**dr** is the executable target. It depends on DRKit plus Tint (TUI) and ArgumentParser (CLI). It serves as both a useful tool and a reference for how to integrate DRKit.

## Algorithm: TT Dynamic Range Standard

### 1. Decode to f32

Audio is decoded to interleaved Float32 samples using LibAVKit's `Decoder`. The decoder is configured for `float32` planar output; frames are interleaved during accumulation.

### 2. Split into 3-second blocks

The sample stream is divided into non-overlapping 3-second blocks. The final partial block (less than 3 seconds) is discarded.

### 3. Per block, per channel: DR-RMS and peak

For each block and each channel independently:

- **DR-RMS** = `sqrt(2 * sum(x²) / N)` where N is the number of frames
- **Peak** = maximum absolute sample value

### 4. Per channel: top 20% RMS and 2nd-highest peak

For each channel across all blocks:

- Sort block RMS values descending, take the top 20% (ceiling), combine via **quadratic mean** (RMS of RMS values)
- Sort block peaks descending, use the **2nd-highest** block peak (falls back to highest if fewer than 2 blocks)

### 5. Per channel DR

```
DR_channel = 20 * log10(2nd_peak / top20%_rms)
```

### 6. Final DR

The final DR value is the **mean of per-channel DR values**, rounded to the nearest integer.

### The sqrt(2) Calibration Factor

Standard RMS of a full-scale sine wave is `1/sqrt(2)` ≈ 0.707, giving -3.01 dBFS. The DR standard multiplies sum-of-squares by 2 before the square root, calibrating a full-scale sine to exactly 0 dB RMS. This means DR-RMS equals peak for a pure sine, cancelling its crest factor and yielding DR0.

### Peak Reporting

- **For DR computation**: 2nd-highest block peak per channel (reduces sensitivity to isolated transients)
- **For display (peakDB)**: absolute peak across the entire track

### Album DR

Album DR is the **mean of all track DR values**, rounded to the nearest integer.

## References

- "Measuring Dynamic Range — DR standard v3" (Pleasurize Music Foundation)
- [dr14_t.meter](https://github.com/simon-r/dr14_t.meter) — Python reference implementation
- [adiblol/dr_meter](https://github.com/adiblol/dr_meter) — C++ implementation
- [Robhub/TTDR](https://github.com/Robhub/TTDR) — JavaScript implementation
- [alleato-llc/dr](https://github.com/alleato-llc/dr) — Rust implementation (sibling project)

## TUI Architecture

### Data Flow

```
┌─────────────────┐  AnalysisEvent  ┌────────────────┐   render   ┌──────────┐
│  Worker Threads  │───────────────▶│  DRAppState    │──────────▶│ Terminal │
│  (DRAnalyzer)    │                │  (state)       │           │  (Tint)  │
└─────────────────┘                └────────────────┘           └──────────┘
                                          ▲
                                          │ Key events
                                   ┌──────┴─────┐
                                   │ DRKeyHandler│
                                   └────────────┘
```

1. **Worker threads** run `DRAnalyzer.analyze(directory:onEvent:)`, sending `AnalysisEvent` callbacks
2. **DRAppState** receives events and updates track statuses
3. **Tint event loop** calls `DRRenderer.render` every 100ms to draw the current state
4. **Key events** are dispatched through `DRKeyHandler` which mutates `DRAppState`

### Rendering

The UI is composed of four layout sections:

| Section | Content |
|---------|---------|
| Header (3 rows) | Album title + path |
| Track table (fill) | Per-track DR, peak, RMS, duration with scroll |
| Summary (3 rows) | Overall DR + completion count |
| Footer (1 row) | Keybinding hints |

Overlays (About, Export) render centered over the main layout.

DR values are color-coded: green (DR12+), yellow (DR8–11), red (DR0–7).

## Audio Decoding

Audio decoding uses [LibAVKit](https://github.com/alleato-llc/libav-kit), a Swift wrapper around FFmpeg. The `Decoder` class provides frame-by-frame decoding to Float32 planar PCM. Metadata (title, album) is read via `MetadataReader`.

Supported formats: FLAC, MP3, WAV, OGG/Vorbis, AAC/M4A, Opus, WavPack, AIFF.
