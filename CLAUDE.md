# CLAUDE.md — dr-kit

## What This Is

A Swift library (DRKit) implementing the Pleasurize Music Foundation / TT Dynamic Range measurement standard, plus a reference TUI application built on Tint.

## Build & Test

```bash
# Prerequisites
brew install ffmpeg

# Build
swift build

# Run TUI
$(swift build --show-bin-path)/dr ~/Music --tui

# Run CLI
$(swift build --show-bin-path)/dr ~/Music/Album/

# Test
swift test
```

## Project Structure

```
Sources/
├── DRKit/                     Library target — all analysis logic
│   ├── DRAnalyzer.swift       Core DR computation + file/directory analysis
│   ├── DRFormatter.swift      Output formatters (table, JSON, CSV)
│   ├── Models.swift           TrackResult, AlbumResult, AnalysisEvent
│   └── Scanner.swift          Directory scanning for audio files
└── dr/                        Executable target — CLI + TUI example
    ├── DR.swift               @main entry point (ArgumentParser)
    └── TUI/
        ├── TUIMode.swift      Terminal setup + event loop
        ├── DRAppState.swift   App state (TrackStatus, View, ExportFormat)
        ├── DRTheme.swift      Tint Theme conformance (cyan palette)
        ├── DRKeyHandler.swift Key → state mutation dispatch
        └── DRRenderer.swift   Layout + widget rendering

Tests/DRKitTests/
├── DRComputationTests.swift   Block stats, DR calc, dBFS
├── DRFormatterTests.swift     Table, JSON, CSV output
├── ScannerTests.swift         Audio file detection + directory scanning
└── ModelsTests.swift          Codable round-trip tests
```

## Key Conventions

- **Swift 6.2+, macOS 14.4+**
- **Always use Swift Testing** (`import Testing`, `#expect`, `@Suite`, `@Test`) — never XCTest
- **DRKit is the library target** — all analysis logic lives here, no TUI dependencies
- **The `dr` executable is a reference app** — demonstrates the DRKit API with a Tint TUI
- **Dependencies**: LibAVKit (decoding + metadata), Tint (TUI framework), ArgumentParser (CLI)
- **`DRAnalyzer.computeDR` is the core algorithm** — pure function, no I/O, fully testable
- **`LockedValue` is the only cross-thread type** — NSLock-guarded for thread-safe state sharing

## Architecture

- **Data flow (CLI)**: File path → DRAnalyzer.analyze → TrackResult/AlbumResult → DRFormatter → stdout
- **Data flow (TUI)**: Worker threads → AnalysisEvent → DRAppState mutation → DRRenderer reads state
- **Rendering**: DRRenderer coordinates layout, draws header, track table, summary, footer, and overlays
- **Algorithm**: TT DR standard with sqrt(2) RMS calibration — see docs/ARCHITECTURE.md
