import Foundation
import Testing
@testable import DRKit

@Suite struct DRFormatterTests {

    // MARK: - Duration Formatting

    @Test func formatDurationZero() {
        #expect(DRFormatter.formatDuration(0.0) == "0:00")
    }

    @Test func formatDurationOneMinute() {
        #expect(DRFormatter.formatDuration(61.0) == "1:01")
    }

    @Test func formatDurationLong() {
        #expect(DRFormatter.formatDuration(3661.0) == "61:01")
    }

    // MARK: - Table Formatting

    @Test func tableAlbumContainsExpectedFields() {
        let result = AlbumResult(
            tracks: [
                TrackResult(
                    dr: 14, peakDB: -0.10, rmsDB: -16.78,
                    durationSeconds: 263.0, title: "Test Track", filename: "test.flac"
                ),
            ],
            overallDR: 14,
            album: "Test Album"
        )
        let table = DRFormatter.table(result)
        #expect(table.contains("DR14"))
        #expect(table.contains("-0.10 dB"))
        #expect(table.contains("-16.78 dB"))
        #expect(table.contains("4:23"))
        #expect(table.contains("Test Track"))
        #expect(table.contains("Official DR value: DR14"))
        #expect(table.contains("Number of tracks:  1"))
    }

    // MARK: - JSON Formatting

    @Test func jsonRoundtrip() throws {
        let track = TrackResult(
            dr: 12, peakDB: -0.30, rmsDB: -14.56,
            durationSeconds: 225.0, title: "My Track", filename: "track.flac"
        )
        let json = DRFormatter.json(track)
        let data = json.data(using: .utf8)!
        let parsed = try JSONDecoder().decode(TrackResult.self, from: data)
        #expect(parsed.dr == 12)
        #expect(parsed.title == "My Track")
    }

    // MARK: - CSV Formatting

    @Test func csvFormat() {
        let result = AlbumResult(
            tracks: [
                TrackResult(
                    dr: 14, peakDB: -0.10, rmsDB: -16.78,
                    durationSeconds: 263.0, title: "Track One", filename: "01.flac"
                ),
                TrackResult(
                    dr: 12, peakDB: -0.30, rmsDB: -14.56,
                    durationSeconds: 225.0, title: "Track Two", filename: "02.flac"
                ),
            ],
            overallDR: 13,
            album: nil
        )
        let csv = DRFormatter.csv(result)
        let lines = csv.split(separator: "\n")
        #expect(lines[0] == "DR,Peak dB,RMS dB,Duration,Track")
        #expect(lines[1].hasPrefix("14,"))
        #expect(lines[2].hasPrefix("12,"))
    }
}
