import DRKit
import Foundation

enum TrackStatus {
    case pending
    case analyzing(Float)
    case complete(TrackResult)
    case error(String)
}

enum AppView {
    case main
    case about
    case export
    case info
    case regenerateConfirm
}

enum ExportFormat {
    case text
    case json
    case csv

    var label: String {
        switch self {
        case .text: "Text (DR Database table)"
        case .json: "JSON"
        case .csv: "CSV"
        }
    }

    var ext: String {
        switch self {
        case .text: "txt"
        case .json: "json"
        case .csv: "csv"
        }
    }

    func next() -> ExportFormat {
        switch self {
        case .text: .json
        case .json: .csv
        case .csv: .text
        }
    }
}

struct TrackTiming {
    let elapsed: Duration
    let fileBytes: UInt64
}

struct BenchmarkStats {
    let totalElapsed: Duration
    let trackTimings: [TrackTiming]

    var totalMB: Double {
        let bytes = trackTimings.reduce(UInt64(0)) { $0 + $1.fileBytes }
        return Double(bytes) / (1024.0 * 1024.0)
    }

    var avgPerTrack: Duration {
        guard !trackTimings.isEmpty else { return .zero }
        return totalElapsed / trackTimings.count
    }

    var mbPerSec: Double {
        let secs = totalElapsed.seconds
        guard secs > 0 else { return 0 }
        return totalMB / secs
    }
}

extension Duration {
    var seconds: Double {
        let (secs, attos) = components
        return Double(secs) + Double(attos) * 1e-18
    }
}

final class DRAppState: @unchecked Sendable {
    private let lock = NSLock()

    private var _tracks: [(String, TrackStatus)]
    private var _albumResult: AlbumResult?
    private var _albumTitle: String?

    var view: AppView = .main
    var selected: Int = 0
    var scrollOffset: Int = 0
    var shouldQuit = false
    let path: URL
    var exportFormat: ExportFormat = .text
    var exportMessage: String?
    var visibleRows: Int = 20
    let jobs: Int

    // Info/benchmark state
    var loadedFromCache = false
    var benchmark: BenchmarkStats?
    var analysisStart: ContinuousClock.Instant?
    private var _trackStartTimes: [ContinuousClock.Instant?]
    private var _trackElapsed: [TrackTiming?]

    init(filenames: [String], path: URL, jobs: Int? = nil) {
        self._tracks = filenames.map { ($0, .pending) }
        self.path = path
        self.jobs = max(jobs ?? ProcessInfo.processInfo.activeProcessorCount, 1)
        self._trackStartTimes = Array(repeating: nil, count: filenames.count)
        self._trackElapsed = Array(repeating: nil, count: filenames.count)
    }

    // MARK: - Thread-safe accessors for shared state

    var tracks: [(String, TrackStatus)] {
        lock.lock()
        defer { lock.unlock() }
        return _tracks
    }

    var albumResult: AlbumResult? {
        lock.lock()
        defer { lock.unlock() }
        return _albumResult
    }

    var albumTitle: String? {
        lock.lock()
        defer { lock.unlock() }
        return _albumTitle
    }

    var completedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _tracks.filter { if case .complete = $0.1 { true } else { false } }.count
    }

    // MARK: - Main thread actions

    func selectNext() {
        lock.lock()
        let count = _tracks.count
        lock.unlock()
        guard count > 0 else { return }
        selected = min(selected + 1, count - 1)
        ensureVisible()
    }

    func selectPrev() {
        selected = max(selected - 1, 0)
        ensureVisible()
    }

    func cycleExportFormat() {
        exportFormat = exportFormat.next()
    }

    /// Populate tracks from a cached album result.
    func loadFromCache(_ result: AlbumResult) {
        lock.lock()
        defer { lock.unlock() }
        _albumTitle = result.album
        _albumResult = result
        loadedFromCache = true
        for (i, track) in result.tracks.enumerated() {
            if i < _tracks.count {
                _tracks[i].1 = .complete(track)
            }
        }
    }

    /// Reset state for re-analysis.
    func resetForRegeneration(filenames: [String]) {
        lock.lock()
        defer { lock.unlock() }
        _tracks = filenames.map { ($0, .pending) }
        _albumResult = nil
        _albumTitle = nil
        loadedFromCache = false
        benchmark = nil
        selected = 0
        scrollOffset = 0
        _trackStartTimes = Array(repeating: nil, count: filenames.count)
        _trackElapsed = Array(repeating: nil, count: filenames.count)
        analysisStart = .now
    }

    // MARK: - Called from analysis thread

    func handleEvent(_ event: AnalysisEvent) {
        lock.lock()
        defer { lock.unlock() }
        switch event {
        case .trackStarted(let index):
            if index < _tracks.count {
                _tracks[index].1 = .analyzing(0)
                if index < _trackStartTimes.count {
                    _trackStartTimes[index] = .now
                }
            }
        case .trackProgress(let index, let percent):
            if index < _tracks.count {
                _tracks[index].1 = .analyzing(percent)
            }
        case .trackCompleted(let index, let result):
            if index < _tracks.count {
                _tracks[index].1 = .complete(result)
                if index < _trackStartTimes.count, let start = _trackStartTimes[index] {
                    _trackElapsed[index] = TrackTiming(
                        elapsed: .now - start,
                        fileBytes: result.fileBytes
                    )
                }
            }
        case .albumCompleted(let result):
            _albumTitle = result.album
            _albumResult = result
            if let start = analysisStart {
                let totalElapsed: Duration = .now - start
                let timings = _trackElapsed.compactMap { $0 }
                benchmark = BenchmarkStats(totalElapsed: totalElapsed, trackTimings: timings)
            }
        case .error(let index, let message):
            if index < _tracks.count {
                _tracks[index].1 = .error(message)
            }
        }
    }

    private func ensureVisible() {
        guard visibleRows > 0 else { return }
        if selected < scrollOffset {
            scrollOffset = selected
        } else if selected >= scrollOffset + visibleRows {
            scrollOffset = selected - visibleRows + 1
        }
    }
}
