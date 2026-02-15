import Foundation

/// Output formatting for DR results.
public enum DRFormatter {

    /// Format a duration in seconds as "M:SS".
    public static func formatDuration(_ secs: Double) -> String {
        let totalSecs = Int(secs.rounded())
        let minutes = totalSecs / 60
        let seconds = totalSecs % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }

    /// Right-pad a string to the given width.
    private static func padLeft(_ s: String, width: Int) -> String {
        if s.count >= width { return s }
        return String(repeating: " ", count: width - s.count) + s
    }

    /// Left-pad a number string to the given width.
    private static func padRight(_ s: String, width: Int) -> String {
        if s.count >= width { return s }
        return s + String(repeating: " ", count: width - s.count)
    }

    /// Format a single track result as a DR Database-style table.
    public static func table(_ result: TrackResult) -> String {
        let separator = String(repeating: "\u{2500}", count: 58)
        let drStr = padRight("DR\(result.dr)", width: 10)
        let peakStr = String(format: "%7.2f", result.peakDB)
        let rmsStr = String(format: "%7.2f", result.rmsDB)
        let durStr = padLeft(formatDuration(result.durationSeconds), width: 10)
        return """
            DR              Peak        RMS   Duration  Track
            \(separator)
            \(drStr) \(peakStr) dB \(rmsStr) dB \(durStr)  \(result.title)
            \(separator)
            Official DR value: DR\(result.dr)
            """
    }

    /// Format an album result as a DR Database-style table.
    public static func table(_ result: AlbumResult) -> String {
        let separator = String(repeating: "\u{2500}", count: 58)
        var lines: [String] = []

        lines.append("DR              Peak        RMS   Duration  Track")
        lines.append(separator)

        for track in result.tracks {
            let drStr = padRight("DR\(track.dr)", width: 10)
            let peakStr = String(format: "%7.2f", track.peakDB)
            let rmsStr = String(format: "%7.2f", track.rmsDB)
            let durStr = padLeft(formatDuration(track.durationSeconds), width: 10)
            lines.append("\(drStr) \(peakStr) dB \(rmsStr) dB \(durStr)  \(track.title)")
        }

        lines.append(separator)
        lines.append("Number of tracks:  \(result.tracks.count)")
        lines.append("Official DR value: DR\(result.overallDR)")

        return lines.joined(separator: "\n")
    }

    /// Format a single track result as pretty-printed JSON.
    public static func json(_ result: TrackResult) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(result),
              let string = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return string
    }

    /// Format an album result as pretty-printed JSON.
    public static func json(_ result: AlbumResult) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(result),
              let string = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return string
    }

    /// Format an album result as CSV.
    public static func csv(_ result: AlbumResult) -> String {
        var lines: [String] = ["DR,Peak dB,RMS dB,Duration,Track"]
        for track in result.tracks {
            lines.append(
                "\(track.dr),\(String(format: "%.2f", track.peakDB)),\(String(format: "%.2f", track.rmsDB)),\(formatDuration(track.durationSeconds)),\(track.title)"
            )
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
