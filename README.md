# dr-kit

[![CI](https://github.com/alleato-llc/dr-kit/actions/workflows/ci.yml/badge.svg)](https://github.com/alleato-llc/dr-kit/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/alleato-llc/dr-kit)](LICENSE)
[![Built with Claude](https://img.shields.io/badge/Built%20with-Claude-blueviolet)](https://claude.ai)

A Swift library implementing the Pleasurize Music Foundation / TT Dynamic Range measurement standard, with a reference TUI application.

## DRKit Library

### Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/alleato-llc/dr-kit.git", branch: "main"),
]
```

Then add `DRKit` as a dependency to your target:

```swift
.target(name: "MyApp", dependencies: [
    .product(name: "DRKit", package: "dr-kit"),
]),
```

### Usage

```swift
import DRKit

// Analyze a single file
let result = try DRAnalyzer.analyze(file: audioURL)
print("DR\(result.dr) — \(result.title)")

// Analyze an album directory
let album = try DRAnalyzer.analyze(directory: albumURL)
print("Album DR: DR\(album.overallDR)")

// Format output
print(DRFormatter.table(album))
print(DRFormatter.json(album))

// Analyze with progress
let result = try DRAnalyzer.analyze(file: url) { percent in
    print("Progress: \(Int(percent * 100))%")
}

// Low-level: compute DR from raw samples
let (dr, peakDB, rmsDB) = DRAnalyzer.computeDR(
    samples: floatSamples,
    channels: 2,
    sampleRate: 44100
)
```

### API

| Type | Purpose |
|------|---------|
| `DRAnalyzer` | Core analysis: file, directory, raw samples |
| `TrackResult` | Per-track DR, peak dB, RMS dB, duration, title |
| `AlbumResult` | Album-level result with track list and overall DR |
| `AnalysisEvent` | Progress events for async analysis |
| `DRFormatter` | Output formatting: table, JSON, CSV |
| `scanAudioFiles(in:)` | Directory scanner for audio files |

## Reference TUI Application

The `dr` executable demonstrates DRKit with an interactive terminal UI.

### Running

```bash
# Prerequisites
brew install ffmpeg

# Build and run
swift build
$(swift build --show-bin-path)/dr ~/Music/Album/ --tui
```

### CLI Options

| Flag | Description |
|------|-------------|
| `--json` | Output as JSON instead of table |
| `--tui` | Launch interactive TUI |
| `-j, --jobs <n>` | Number of parallel analysis jobs |

### TUI Keybindings

| Key | Action |
|-----|--------|
| `j` / `Down` | Select next track |
| `k` / `Up` | Select previous track |
| `e` | Open export dialog |
| `a` | Open about dialog |
| `q` | Quit |
| `Tab` | Cycle export format (in export dialog) |
| `Enter` | Save export (in export dialog) |
| `Esc` | Close dialog |

## Algorithm

DRKit implements the TT Dynamic Range measurement standard:

1. Decode audio to f32 samples via LibAVKit
2. Split into 3-second non-overlapping blocks
3. Per block, per channel: compute DR-RMS (`sqrt(2 * sum(x²) / N)`) and peak
4. Per channel: quadratic-mean the top 20% of block RMS values; take the 2nd-highest block peak
5. Per channel: `DR = 20 * log10(2nd_peak / top20%_rms)`
6. Final DR = mean of per-channel DR values, rounded

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full algorithm description.

## Testing

```bash
swift test
```

## Dependencies

| Package | Purpose |
|---------|---------|
| [LibAVKit](https://github.com/alleato-llc/libav-kit) | Audio decoding and metadata (FFmpeg wrapper) |
| [Tint](https://github.com/alleato-llc/tint) | Terminal UI framework (TUI example only) |
| [ArgumentParser](https://github.com/apple/swift-argument-parser) | CLI argument parsing (TUI example only) |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)
