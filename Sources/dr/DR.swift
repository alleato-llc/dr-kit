import ArgumentParser
import DRKit
import Foundation

@main
struct DR: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dr",
        abstract: "Dynamic range meter for audio files"
    )

    @Argument(help: "Audio file or directory")
    var path: String?

    @Flag(name: .long, help: "Output as JSON instead of table")
    var json = false

    @Flag(name: .long, help: "Launch interactive TUI")
    var tui = false

    @Option(name: .shortAndLong, help: "Number of parallel analysis jobs (default: CPU cores)")
    var jobs: Int?

    @Flag(name: .long, help: "Scan subdirectories as separate albums")
    var bulk = false

    @Flag(name: .long, help: "Write dr_report.txt alongside JSON")
    var txt = false

    @Flag(name: .long, help: "Re-analyze even if cached report exists")
    var regenerate = false

    func validate() throws {
        if bulk && tui {
            throw ValidationError("--bulk and --tui cannot be used together")
        }
        if bulk && !json && !txt {
            throw ValidationError("--bulk requires --json and/or --txt")
        }
    }

    func run() throws {
        let pathStr = path ?? "."
        let url = URL(fileURLWithPath: pathStr)

        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)

        guard exists else {
            throw ValidationError("Path '\(pathStr)' does not exist")
        }

        if bulk {
            try runBulk(base: url)
            return
        }

        if isDir.boolValue {
            if tui {
                TUIMode.run(directory: url, jobs: jobs, regenerate: regenerate)
                return
            }

            // Check cache for non-TUI single-directory mode
            if !regenerate, let cached = DRCache.loadCachedReport(in: url) {
                if json {
                    print(DRFormatter.json(cached))
                } else {
                    print(DRFormatter.table(cached))
                }
                if txt {
                    try DRCache.saveTextReport(DRFormatter.table(cached), in: url)
                }
                return
            }

            let result = try DRAnalyzer.analyze(directory: url, jobs: jobs)

            // Auto-save JSON cache
            try? DRCache.saveReport(result, in: url)

            if json {
                print(DRFormatter.json(result))
            } else {
                print(DRFormatter.table(result))
            }

            if txt {
                try DRCache.saveTextReport(DRFormatter.table(result), in: url)
            }
        } else {
            let result = try DRAnalyzer.analyze(file: url)
            if json {
                print(DRFormatter.json(result))
            } else {
                print(DRFormatter.table(result))
            }
        }
    }

    private func runBulk(base: URL) throws {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: base,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw ValidationError("Cannot read directory '\(base.path)'")
        }

        let subdirs = contents.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard !subdirs.isEmpty else {
            print("No subdirectories found in \(base.path)")
            return
        }

        var analyzed = 0
        var skipped = 0
        var failed = 0

        for dir in subdirs {
            let name = dir.lastPathComponent

            // Skip if reports already exist (unless --regenerate)
            if !regenerate && DRCache.reportsExist(in: dir, json: json, txt: txt) {
                print("  skip  \(name) (cached)")
                skipped += 1
                continue
            }

            // Check for audio files
            let audioFiles = scanAudioFiles(in: dir)
            guard !audioFiles.isEmpty else {
                continue
            }

            print("  scan  \(name)...")
            do {
                let result = try DRAnalyzer.analyze(directory: dir, jobs: jobs)

                if json {
                    try DRCache.saveReport(result, in: dir)
                }
                if txt {
                    try DRCache.saveTextReport(DRFormatter.table(result), in: dir)
                }

                print("  done  \(name) — DR\(result.overallDR) (\(result.tracks.count) tracks)")
                analyzed += 1
            } catch {
                print("  FAIL  \(name) — \(error.localizedDescription)")
                failed += 1
            }
        }

        print("\nBulk complete: \(analyzed) analyzed, \(skipped) skipped, \(failed) failed")
    }
}
