import Foundation
import Testing
@testable import DRKit

@Suite struct CacheTests {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dr-cache-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    private func sampleAlbum() -> AlbumResult {
        AlbumResult(
            tracks: [
                TrackResult(
                    dr: 12, peakDB: -0.10, rmsDB: -14.5,
                    durationSeconds: 240.0, title: "Track 1", filename: "01.flac",
                    fileBytes: 50_000_000
                ),
                TrackResult(
                    dr: 10, peakDB: -0.30, rmsDB: -12.0,
                    durationSeconds: 180.0, title: "Track 2", filename: "02.flac",
                    fileBytes: 40_000_000
                ),
            ],
            overallDR: 11,
            album: "Test Album"
        )
    }

    @Test func reportsExistNoFiles() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        #expect(!DRCache.reportsExist(in: dir, json: true, txt: false))
        #expect(!DRCache.reportsExist(in: dir, json: false, txt: true))
        #expect(!DRCache.reportsExist(in: dir, json: true, txt: true))
    }

    @Test func reportsExistJSONOnly() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        try DRCache.saveReport(sampleAlbum(), in: dir)
        #expect(DRCache.reportsExist(in: dir, json: true, txt: false))
        #expect(!DRCache.reportsExist(in: dir, json: true, txt: true))
    }

    @Test func reportsExistTxtOnly() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        try DRCache.saveTextReport("test content", in: dir)
        #expect(DRCache.reportsExist(in: dir, json: false, txt: true))
        #expect(!DRCache.reportsExist(in: dir, json: true, txt: true))
    }

    @Test func reportsExistBoth() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        try DRCache.saveReport(sampleAlbum(), in: dir)
        try DRCache.saveTextReport("test content", in: dir)
        #expect(DRCache.reportsExist(in: dir, json: true, txt: true))
    }

    @Test func saveTextReport() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let content = "DR Report\nDR12 test"
        try DRCache.saveTextReport(content, in: dir)
        let path = dir.appendingPathComponent("dr_report.txt")
        let read = try String(contentsOf: path, encoding: .utf8)
        #expect(read == content)
    }

    @Test func saveAndLoadReport() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let album = sampleAlbum()
        try DRCache.saveReport(album, in: dir)
        let loaded = DRCache.loadCachedReport(in: dir)
        #expect(loaded != nil)
        #expect(loaded?.overallDR == 11)
        #expect(loaded?.album == "Test Album")
        #expect(loaded?.tracks.count == 2)
        #expect(loaded?.tracks[0].fileBytes == 50_000_000)
    }

    @Test func loadMissingReport() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let loaded = DRCache.loadCachedReport(in: dir)
        #expect(loaded == nil)
    }
}
