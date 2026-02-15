import Foundation

/// Cache utilities for persisting and loading DR analysis reports.
public enum DRCache {

    private static let jsonFilename = "dr_report.json"
    private static let txtFilename = "dr_report.txt"

    /// Load a cached album result from `dr_report.json` in the given directory.
    /// Returns `nil` if the file is missing or cannot be parsed.
    public static func loadCachedReport(in directory: URL) -> AlbumResult? {
        let path = directory.appendingPathComponent(jsonFilename)
        guard let data = try? Data(contentsOf: path) else { return nil }
        return try? JSONDecoder().decode(AlbumResult.self, from: data)
    }

    /// Save an album result as pretty-printed JSON to `dr_report.json`.
    public static func saveReport(_ result: AlbumResult, in directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(result)
        let path = directory.appendingPathComponent(jsonFilename)
        try data.write(to: path)
    }

    /// Check if all requested report files already exist.
    public static func reportsExist(in directory: URL, json: Bool, txt: Bool) -> Bool {
        let fm = FileManager.default
        if json && !fm.fileExists(atPath: directory.appendingPathComponent(jsonFilename).path) {
            return false
        }
        if txt && !fm.fileExists(atPath: directory.appendingPathComponent(txtFilename).path) {
            return false
        }
        return json || txt
    }

    /// Save a text report to `dr_report.txt` in the given directory.
    public static func saveTextReport(_ content: String, in directory: URL) throws {
        let path = directory.appendingPathComponent(txtFilename)
        try content.write(to: path, atomically: true, encoding: .utf8)
    }
}
