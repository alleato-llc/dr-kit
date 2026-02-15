import DRKit
import Tint

enum DRKeyHandler {
    static func handle(key: Key, state: DRAppState, app: Application) {
        switch state.view {
        case .main:
            handleMain(key: key, state: state, app: app)
        case .about:
            handleAbout(key: key, state: state)
        case .export:
            handleExport(key: key, state: state)
        case .info:
            handleInfo(key: key, state: state)
        case .regenerateConfirm:
            handleRegenerateConfirm(key: key, state: state)
        }
    }

    private static func handleMain(key: Key, state: DRAppState, app: Application) {
        switch key {
        case .char("q"), .ctrlC:
            app.quit()
        case .char("e"):
            if state.albumResult != nil {
                state.view = .export
                state.exportMessage = nil
            }
        case .char("a"):
            state.view = .about
        case .char("i"):
            if state.albumResult != nil || state.loadedFromCache {
                state.view = .info
            }
        case .char("r"):
            if state.albumResult != nil || state.loadedFromCache {
                state.view = .regenerateConfirm
            }
        case .char("j"), .down, .scrollDown:
            state.selectNext()
        case .char("k"), .up, .scrollUp:
            state.selectPrev()
        default:
            break
        }
    }

    private static func handleAbout(key: Key, state: DRAppState) {
        switch key {
        case .escape, .char("q"):
            state.view = .main
        default:
            break
        }
    }

    private static func handleExport(key: Key, state: DRAppState) {
        switch key {
        case .escape:
            state.view = .main
        case .tab:
            state.cycleExportFormat()
            state.exportMessage = nil
        case .enter:
            guard let result = state.albumResult else { return }
            let content: String
            switch state.exportFormat {
            case .text: content = DRFormatter.table(result)
            case .json: content = DRFormatter.json(result)
            case .csv: content = DRFormatter.csv(result)
            }
            let outputPath = state.path.appendingPathComponent("dr_report.\(state.exportFormat.ext)")
            do {
                try content.write(to: outputPath, atomically: true, encoding: .utf8)
                state.exportMessage = "Saved to \(outputPath.path)"
            } catch {
                state.exportMessage = "Error: \(error.localizedDescription)"
            }
        default:
            break
        }
    }

    private static func handleInfo(key: Key, state: DRAppState) {
        switch key {
        case .escape, .char("q"):
            state.view = .main
        default:
            break
        }
    }

    private static func handleRegenerateConfirm(key: Key, state: DRAppState) {
        switch key {
        case .char("y"), .enter:
            state.view = .main
            let files = scanAudioFiles(in: state.path)
            let filenames = files.map { $0.lastPathComponent }
            state.resetForRegeneration(filenames: filenames)
            TUIMode.spawnAnalysis(directory: state.path, state: state)
        case .char("n"), .escape:
            state.view = .main
        default:
            break
        }
    }
}
