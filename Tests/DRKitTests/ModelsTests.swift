import Foundation
import Testing
@testable import DRKit

@Suite struct ModelsTests {

    @Test func trackResultCodable() throws {
        let track = TrackResult(
            dr: 14, peakDB: -0.10, rmsDB: -16.78,
            durationSeconds: 263.0, title: "Test", filename: "test.flac"
        )
        let data = try JSONEncoder().encode(track)
        let decoded = try JSONDecoder().decode(TrackResult.self, from: data)
        #expect(decoded.dr == 14)
        #expect(decoded.title == "Test")
        #expect(decoded.filename == "test.flac")
        #expect(abs(decoded.peakDB - (-0.10)) < 0.001)
    }

    @Test func albumResultCodable() throws {
        let album = AlbumResult(
            tracks: [
                TrackResult(
                    dr: 10, peakDB: -0.50, rmsDB: -12.0,
                    durationSeconds: 180.0, title: "A", filename: "a.flac"
                ),
            ],
            overallDR: 10,
            album: "My Album"
        )
        let data = try JSONEncoder().encode(album)
        let decoded = try JSONDecoder().decode(AlbumResult.self, from: data)
        #expect(decoded.overallDR == 10)
        #expect(decoded.album == "My Album")
        #expect(decoded.tracks.count == 1)
    }

    @Test func albumResultNilAlbum() throws {
        let album = AlbumResult(tracks: [], overallDR: 0, album: nil)
        let data = try JSONEncoder().encode(album)
        let decoded = try JSONDecoder().decode(AlbumResult.self, from: data)
        #expect(decoded.album == nil)
    }

    @Test func trackResultBackwardCompatible() throws {
        // JSON without fileBytes field should decode with default 0
        let json = """
        {"dr":12,"peakDB":-0.1,"rmsDB":-14.5,"durationSeconds":240.0,"title":"Test","filename":"test.flac"}
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(TrackResult.self, from: data)
        #expect(decoded.dr == 12)
        #expect(decoded.fileBytes == 0)
    }

    @Test func trackResultWithFileBytes() throws {
        let track = TrackResult(
            dr: 10, peakDB: -0.30, rmsDB: -12.0,
            durationSeconds: 180.0, title: "Test", filename: "test.flac",
            fileBytes: 45_000_000
        )
        let data = try JSONEncoder().encode(track)
        let decoded = try JSONDecoder().decode(TrackResult.self, from: data)
        #expect(decoded.fileBytes == 45_000_000)
        #expect(decoded.dr == 10)
    }
}
