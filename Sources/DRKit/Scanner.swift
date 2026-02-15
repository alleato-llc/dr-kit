import Foundation

/// Audio file extensions recognized by DRKit.
public let audioExtensions: Set<String> = [
    "flac", "mp3", "wav", "ogg", "m4a", "opus", "wv", "aif", "aiff",
]

/// Check if a URL has a recognized audio file extension.
public func isAudioFile(_ url: URL) -> Bool {
    audioExtensions.contains(url.pathExtension.lowercased())
}

/// Scan a directory for audio files, sorted by filename.
public func scanAudioFiles(in directory: URL) -> [URL] {
    guard let contents = try? FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else {
        return []
    }

    return contents
        .filter { url in
            let isFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            return isFile && isAudioFile(url)
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
}
