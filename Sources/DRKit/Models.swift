import Foundation

/// Result of analyzing a single audio track.
public struct TrackResult: Codable, Sendable {
    public let dr: UInt
    public let peakDB: Double
    public let rmsDB: Double
    public let durationSeconds: Double
    public let title: String
    public let filename: String
    public let fileBytes: UInt64

    public init(
        dr: UInt,
        peakDB: Double,
        rmsDB: Double,
        durationSeconds: Double,
        title: String,
        filename: String,
        fileBytes: UInt64 = 0
    ) {
        self.dr = dr
        self.peakDB = peakDB
        self.rmsDB = rmsDB
        self.durationSeconds = durationSeconds
        self.title = title
        self.filename = filename
        self.fileBytes = fileBytes
    }

    public init(from decoder: any Swift.Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dr = try container.decode(UInt.self, forKey: .dr)
        peakDB = try container.decode(Double.self, forKey: .peakDB)
        rmsDB = try container.decode(Double.self, forKey: .rmsDB)
        durationSeconds = try container.decode(Double.self, forKey: .durationSeconds)
        title = try container.decode(String.self, forKey: .title)
        filename = try container.decode(String.self, forKey: .filename)
        fileBytes = try container.decodeIfPresent(UInt64.self, forKey: .fileBytes) ?? 0
    }
}

/// Result of analyzing an album (directory of tracks).
public struct AlbumResult: Codable, Sendable {
    public let tracks: [TrackResult]
    public let overallDR: UInt
    public let album: String?

    public init(tracks: [TrackResult], overallDR: UInt, album: String?) {
        self.tracks = tracks
        self.overallDR = overallDR
        self.album = album
    }
}

/// Events emitted during directory analysis.
public enum AnalysisEvent: Sendable {
    case trackStarted(index: Int)
    case trackProgress(index: Int, percent: Float)
    case trackCompleted(index: Int, result: TrackResult)
    case albumCompleted(result: AlbumResult)
    case error(index: Int, message: String)
}
