import DRKit
import Foundation
import Tint

enum TUIMode {
    static func run(directory: URL, jobs: Int?, regenerate: Bool = false) {
        let files = scanAudioFiles(in: directory)
        guard !files.isEmpty else {
            print("No audio files found in \(directory.path)")
            return
        }

        let filenames = files.map { $0.lastPathComponent }
        let state = DRAppState(filenames: filenames, path: directory, jobs: jobs)
        let theme = DRTheme()
        let app = Application(theme: theme)

        // Try loading cached report
        if !regenerate, let cached = DRCache.loadCachedReport(in: directory) {
            state.loadFromCache(cached)
        } else {
            spawnAnalysis(directory: directory, state: state)
        }

        app.run(
            render: { area, buffer in
                DRRenderer.render(state: state, area: area, theme: theme, buffer: &buffer)
            },
            onKey: { key in
                DRKeyHandler.handle(key: key, state: state, app: app)
            }
        )
    }

    static func spawnAnalysis(directory: URL, state: DRAppState) {
        state.analysisStart = .now
        let jobCount = state.jobs
        Thread.detachNewThread {
            try? DRAnalyzer.analyze(directory: directory, jobs: jobCount) { event in
                state.handleEvent(event)
            }
            // Auto-save JSON cache on completion
            if let result = state.albumResult {
                try? DRCache.saveReport(result, in: directory)
            }
        }
    }
}
