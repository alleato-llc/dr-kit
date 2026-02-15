import Foundation
import Testing
@testable import DRKit

@Suite struct ScannerTests {

    @Test func isAudioFileRecognizesFormats() {
        #expect(isAudioFile(URL(fileURLWithPath: "track.flac")))
        #expect(isAudioFile(URL(fileURLWithPath: "track.mp3")))
        #expect(isAudioFile(URL(fileURLWithPath: "track.wav")))
        #expect(isAudioFile(URL(fileURLWithPath: "track.ogg")))
        #expect(isAudioFile(URL(fileURLWithPath: "track.m4a")))
        #expect(isAudioFile(URL(fileURLWithPath: "track.opus")))
        #expect(isAudioFile(URL(fileURLWithPath: "track.wv")))
        #expect(isAudioFile(URL(fileURLWithPath: "track.aif")))
        #expect(isAudioFile(URL(fileURLWithPath: "track.aiff")))
    }

    @Test func isAudioFileRejectsNonAudio() {
        #expect(!isAudioFile(URL(fileURLWithPath: "readme.txt")))
        #expect(!isAudioFile(URL(fileURLWithPath: "image.png")))
        #expect(!isAudioFile(URL(fileURLWithPath: "data.json")))
    }

    @Test func isAudioFileCaseInsensitive() {
        #expect(isAudioFile(URL(fileURLWithPath: "track.FLAC")))
        #expect(isAudioFile(URL(fileURLWithPath: "track.Mp3")))
    }

    @Test func scanAudioFilesSortsAndFilters() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Create test files
        try Data("fake".utf8).write(to: tmpDir.appendingPathComponent("b_track.flac"))
        try Data("fake".utf8).write(to: tmpDir.appendingPathComponent("a_track.mp3"))
        try Data("fake".utf8).write(to: tmpDir.appendingPathComponent("cover.jpg"))
        try Data("fake".utf8).write(to: tmpDir.appendingPathComponent("notes.txt"))

        let files = scanAudioFiles(in: tmpDir)
        #expect(files.count == 2)
        #expect(files[0].lastPathComponent == "a_track.mp3")
        #expect(files[1].lastPathComponent == "b_track.flac")
    }

    @Test func scanAudioFilesEmptyDirectory() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let files = scanAudioFiles(in: tmpDir)
        #expect(files.isEmpty)
    }
}
