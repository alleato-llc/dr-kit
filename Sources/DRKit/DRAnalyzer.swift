import Accelerate
import Foundation
import LibAVKit

/// Streaming DR state — accumulates block-by-block statistics without buffering entire track.
///
/// LibAVKit delivers complete planar frames via `DecodedFrame.channelData`, so no residual
/// buffer is needed (unlike Rust's Symphonia which yields interleaved partial packets).
struct StreamingDrState {
    let channels: Int
    let sampleRate: Int
    let blockFrames: Int

    /// Per-channel sum-of-squares for current block.
    var chSumSq: [Double]
    /// Per-channel peak for current block.
    var chPeak: [Double]
    /// Completed block RMS values per channel.
    var blockRMS: [[Double]]
    /// Completed block peak values per channel.
    var blockPeaks: [[Double]]
    /// Absolute peak across entire track.
    var globalPeak: Double
    /// Number of frames accumulated in current block.
    var currentBlockFrames: Int

    init(channels: Int, sampleRate: Int) {
        self.channels = max(channels, 1)
        self.sampleRate = sampleRate
        self.blockFrames = 3 * sampleRate
        self.chSumSq = [Double](repeating: 0, count: self.channels)
        self.chPeak = [Double](repeating: 0, count: self.channels)
        self.blockRMS = Array(repeating: [], count: self.channels)
        self.blockPeaks = Array(repeating: [], count: self.channels)
        self.globalPeak = 0
        self.currentBlockFrames = 0
    }

    /// Feed a planar frame directly from LibAVKit's decoder callback.
    mutating func pushPlanarFrame(channelData: [UnsafePointer<Float>], frameCount: Int) {
        var offset = 0
        var remaining = frameCount

        while remaining > 0 {
            let spaceInBlock = blockFrames - currentBlockFrames
            let count = min(remaining, spaceInBlock)

            let n = vDSP_Length(count)
            for ch in 0..<channels {
                let ptr = channelData[ch].advanced(by: offset)

                // Sum of squares via dot product (SIMD-accelerated)
                var dotProd: Float = 0
                vDSP_dotpr(ptr, 1, ptr, 1, &dotProd, n)
                chSumSq[ch] += Double(dotProd)

                // Max magnitude (SIMD-accelerated)
                var maxMag: Float = 0
                vDSP_maxmgv(ptr, 1, &maxMag, n)
                let mag = Double(maxMag)
                if mag > chPeak[ch] { chPeak[ch] = mag }
                if mag > globalPeak { globalPeak = mag }
            }

            currentBlockFrames += count
            offset += count
            remaining -= count

            // Finalize complete block
            if currentBlockFrames == blockFrames {
                for ch in 0..<channels {
                    // DR-RMS: sqrt(2) factor calibrates sine peak = sine RMS
                    let rms = (2.0 * chSumSq[ch] / Double(blockFrames)).squareRoot()
                    blockRMS[ch].append(rms)
                    blockPeaks[ch].append(chPeak[ch])
                }
                for ch in 0..<channels {
                    chSumSq[ch] = 0
                    chPeak[ch] = 0
                }
                currentBlockFrames = 0
            }
        }
    }

    /// Compute final DR, peak dB, RMS dB, and duration from accumulated block stats.
    func finalize(totalFrames: Int) -> (dr: UInt, peakDB: Double, rmsDB: Double, durationSeconds: Double) {
        let durationSeconds = Double(totalFrames) / Double(max(sampleRate, 1))

        let numBlocks = blockRMS.first?.count ?? 0
        guard numBlocks > 0 else {
            return (0, DRAnalyzer.dbFS(globalPeak), -.infinity, durationSeconds)
        }

        var channelDRs: [Double] = []
        channelDRs.reserveCapacity(channels)
        var reportRMS = 0.0

        for ch in 0..<channels {
            var chRMS = blockRMS[ch]
            var chPk = blockPeaks[ch]

            // Sort RMS descending
            chRMS.sort(by: >)

            // Top 20% RMS — combine via quadratic mean
            let topCount = max(Int(ceil(Double(numBlocks) * 0.2)), 1)
            let sumSq = chRMS.prefix(topCount).reduce(0.0) { $0 + $1 * $1 }
            let combinedRMS = (sumSq / Double(topCount)).squareRoot()

            // Sort peaks descending, use 2nd-highest
            chPk.sort(by: >)
            let peak = chPk.count >= 2 ? chPk[1] : chPk[0]

            // Per-channel DR
            if peak > 0 && combinedRMS > 0 {
                channelDRs.append(20.0 * log10(peak / combinedRMS))
            } else {
                channelDRs.append(0.0)
            }

            if combinedRMS > reportRMS { reportRMS = combinedRMS }
        }

        let dr: UInt
        if channelDRs.isEmpty {
            dr = 0
        } else {
            let meanDR = channelDRs.reduce(0.0, +) / Double(channelDRs.count)
            dr = UInt(meanDR.rounded())
        }

        return (dr, DRAnalyzer.dbFS(globalPeak), DRAnalyzer.dbFS(reportRMS), durationSeconds)
    }
}

/// Dynamic range analyzer implementing the TT DR standard.
public enum DRAnalyzer {

    // MARK: - Public API

    /// Analyze a single audio file.
    public static func analyze(file url: URL) throws -> TrackResult {
        try analyze(file: url, onProgress: { _ in })
    }

    /// Analyze a single audio file with progress callback.
    ///
    /// Uses streaming block-by-block DR computation (~2MB vs ~230MB for a typical album track).
    public static func analyze(
        file url: URL,
        onProgress: @Sendable (Float) -> Void
    ) throws -> TrackResult {
        let decoder = Decoder()
        try decoder.open(url: url)

        let sampleRate = decoder.sampleRate
        let channels = max(decoder.channels, 1)
        let duration = decoder.duration

        // Configure output to match source format (no resampling)
        try decoder.reconfigure(outputFormat: AudioOutputFormat(
            sampleRate: Double(sampleRate),
            channelCount: channels,
            sampleFormat: .float32,
            isInterleaved: false
        ))

        let metadata = (try? MetadataReader().read(url: url)) ?? .empty
        let title = metadata.title ?? url.deletingPathExtension().lastPathComponent
        let filename = url.lastPathComponent

        // Get file size
        let fileBytes: UInt64
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? UInt64 {
            fileBytes = size
        } else {
            fileBytes = 0
        }

        var state = StreamingDrState(channels: channels, sampleRate: sampleRate)
        var totalFrames = 0
        let totalDuration = duration > 0 ? duration : 1.0

        // Throttle progress to ~100ms of audio to avoid per-frame float divisions
        let progressInterval = sampleRate / 10
        var framesSinceProgress = 0

        // Bulk decode — returns on EOF, no per-frame throw/catch overhead
        do {
            try decoder.decodeAllFrames { frame in
                let frameCount = frame.frameCount
                state.pushPlanarFrame(channelData: frame.channelData, frameCount: frameCount)
                totalFrames += frameCount
                framesSinceProgress += frameCount

                if framesSinceProgress >= progressInterval {
                    framesSinceProgress = 0
                    let progress = Float(min(Double(totalFrames) / Double(sampleRate) / totalDuration, 1.0))
                    onProgress(progress)
                }
            }
        } catch {
            // Decode error mid-file: return partial results
        }

        onProgress(1.0)
        decoder.close()

        let (dr, peakDB, rmsDB, durationSeconds) = state.finalize(totalFrames: totalFrames)

        return TrackResult(
            dr: dr,
            peakDB: peakDB,
            rmsDB: rmsDB,
            durationSeconds: durationSeconds,
            title: title,
            filename: filename,
            fileBytes: fileBytes
        )
    }

    /// Analyze all audio files in a directory.
    public static func analyze(
        directory url: URL,
        jobs: Int? = nil
    ) throws -> AlbumResult {
        let files = scanAudioFiles(in: url)
        guard !files.isEmpty else {
            throw DRError.noAudioFiles(url.path)
        }

        let jobCount = max(jobs ?? ProcessInfo.processInfo.activeProcessorCount, 1)
        let results = analyzeFilesInParallel(files: files, jobs: jobCount)

        var tracks: [TrackResult] = []
        for result in results {
            switch result {
            case .success(let track):
                tracks.append(track)
            case .failure(let error):
                throw error
            }
        }

        let albumName = extractAlbumName(from: files.first!)

        let overallDR: UInt
        if tracks.isEmpty {
            overallDR = 0
        } else {
            let sum = tracks.reduce(0.0) { $0 + Double($1.dr) }
            overallDR = UInt((sum / Double(tracks.count)).rounded())
        }

        return AlbumResult(tracks: tracks, overallDR: overallDR, album: albumName)
    }

    /// Analyze a directory with per-track events for TUI use.
    public static func analyze(
        directory url: URL,
        jobs: Int? = nil,
        onEvent: @escaping @Sendable (AnalysisEvent) -> Void
    ) throws {
        let files = scanAudioFiles(in: url)
        guard !files.isEmpty else {
            throw DRError.noAudioFiles(url.path)
        }

        let jobCount = max(jobs ?? ProcessInfo.processInfo.activeProcessorCount, 1)
        let indexedFiles = Array(files.enumerated())
        let nextIndex = LockedValue(0)

        let threadCount = min(jobCount, files.count)
        var threads: [Thread] = []
        let allTracks = LockedValue<[(Int, TrackResult)]>([])

        for _ in 0..<threadCount {
            let thread = Thread {
                while true {
                    let index = nextIndex.withLock { value in
                        let current = value
                        value += 1
                        return current
                    }
                    guard index < indexedFiles.count else { break }

                    let (idx, fileURL) = indexedFiles[index]
                    onEvent(.trackStarted(index: idx))

                    do {
                        let result = try analyze(file: fileURL) { percent in
                            onEvent(.trackProgress(index: idx, percent: percent))
                        }
                        onEvent(.trackCompleted(index: idx, result: result))
                        allTracks.withLock { $0.append((idx, result)) }
                    } catch {
                        onEvent(.error(index: idx, message: error.localizedDescription))
                    }
                }
            }
            thread.start()
            threads.append(thread)
        }

        // Wait for all threads
        for thread in threads {
            while !thread.isFinished {
                Thread.sleep(forTimeInterval: 0.01)
            }
        }

        let tracks = allTracks.withLock { value in
            value.sorted { $0.0 < $1.0 }.map(\.1)
        }

        let albumName = extractAlbumName(from: files.first!)

        let overallDR: UInt
        if tracks.isEmpty {
            overallDR = 0
        } else {
            let sum = tracks.reduce(0.0) { $0 + Double($1.dr) }
            overallDR = UInt((sum / Double(tracks.count)).rounded())
        }

        onEvent(.albumCompleted(result: AlbumResult(
            tracks: tracks,
            overallDR: overallDR,
            album: albumName
        )))
    }

    // MARK: - Core Algorithm

    /// Compute DR, peak dB, and RMS dB from interleaved f32 samples.
    ///
    /// Implements the TT Dynamic Range standard:
    /// 1. Split into 3-second blocks, discard final partial block
    /// 2. Per block per channel: compute DR-RMS (with sqrt(2)) and peak
    /// 3. Per channel: sort RMS descending, quadratic-mean the top 20%
    /// 4. Per channel: sort peaks descending, use the 2nd-highest
    /// 5. Per channel: DR_ch = 20 * log10(2nd_peak / top20%_rms)
    /// 6. Final DR = mean of per-channel DR values, rounded
    public static func computeDR(
        samples: [Float],
        channels: Int,
        sampleRate: Int
    ) -> (dr: UInt, peakDB: Double, rmsDB: Double) {
        let blockFrames = 3 * sampleRate
        let blockSize = blockFrames * channels

        guard samples.count >= blockSize, channels > 0 else {
            var peakF: Float = 0
            if !samples.isEmpty {
                samples.withUnsafeBufferPointer { buf in
                    vDSP_maxmgv(buf.baseAddress!, 1, &peakF, vDSP_Length(buf.count))
                }
            }
            return (0, dbFS(Double(peakF)), -.infinity)
        }

        // Gather per-block stats — pointer-based, no per-block copy
        let numBlocks = samples.count / blockSize
        var blocks: [BlockStats] = []
        blocks.reserveCapacity(numBlocks)

        samples.withUnsafeBufferPointer { buffer in
            let base = buffer.baseAddress!
            for b in 0..<numBlocks {
                blocks.append(computeBlockStats(base.advanced(by: b * blockSize), count: blockSize, channels: channels))
            }
        }

        var channelDRs: [Double] = []
        channelDRs.reserveCapacity(channels)
        var reportPeak = 0.0
        var reportRMS = 0.0

        for ch in 0..<channels {
            var chRMS = blocks.map { $0.rms[ch] }
            var chPeaks = blocks.map { $0.peak[ch] }

            // Sort RMS descending
            chRMS.sort(by: >)

            // Top 20% RMS — combine via quadratic mean
            let topCount = max(Int(ceil(Double(numBlocks) * 0.2)), 1)
            let sumSq = chRMS.prefix(topCount).reduce(0.0) { $0 + $1 * $1 }
            let combinedRMS = (sumSq / Double(topCount)).squareRoot()

            // Sort peaks descending, use 2nd-highest
            chPeaks.sort(by: >)
            let peak = chPeaks.count >= 2 ? chPeaks[1] : chPeaks[0]

            // Per-channel DR
            if peak > 0 && combinedRMS > 0 {
                channelDRs.append(20.0 * log10(peak / combinedRMS))
            } else {
                channelDRs.append(0.0)
            }

            if peak > reportPeak { reportPeak = peak }
            if combinedRMS > reportRMS { reportRMS = combinedRMS }
        }

        // Final DR = mean of per-channel DR values, rounded
        let dr: UInt
        if channelDRs.isEmpty {
            dr = 0
        } else {
            let meanDR = channelDRs.reduce(0.0, +) / Double(channelDRs.count)
            dr = UInt(meanDR.rounded())
        }

        // Absolute peak for display (SIMD-accelerated)
        var absolutePeakF: Float = 0
        samples.withUnsafeBufferPointer { buf in
            vDSP_maxmgv(buf.baseAddress!, 1, &absolutePeakF, vDSP_Length(buf.count))
        }
        let absolutePeak = Double(absolutePeakF)

        return (dr, dbFS(absolutePeak), dbFS(reportRMS))
    }

    // MARK: - Internal

    struct BlockStats {
        let rms: [Double]
        let peak: [Double]
    }

    /// Compute per-channel DR-RMS and peak for interleaved samples at a pointer.
    static func computeBlockStats(_ base: UnsafePointer<Float>, count: Int, channels: Int) -> BlockStats {
        let frames = count / channels
        var rms = [Double](repeating: 0, count: channels)
        var peak = [Double](repeating: 0, count: channels)
        let stride = vDSP_Stride(channels)
        let n = vDSP_Length(frames)

        for ch in 0..<channels {
            let chPtr = base.advanced(by: ch)

            var dotProd: Float = 0
            vDSP_dotpr(chPtr, stride, chPtr, stride, &dotProd, n)

            var maxMag: Float = 0
            vDSP_maxmgv(chPtr, stride, &maxMag, n)

            // DR-RMS: sqrt(2) factor calibrates sine peak = sine RMS
            rms[ch] = (2.0 * Double(dotProd) / Double(frames)).squareRoot()
            peak[ch] = Double(maxMag)
        }

        return BlockStats(rms: rms, peak: peak)
    }

    /// Compute per-channel DR-RMS and peak for a block of interleaved samples.
    static func computeBlockStats(_ samples: [Float], channels: Int) -> BlockStats {
        samples.withUnsafeBufferPointer { buffer in
            computeBlockStats(buffer.baseAddress!, count: buffer.count, channels: channels)
        }
    }

    /// Convert a linear amplitude to dBFS.
    static func dbFS(_ linear: Double) -> Double {
        if linear <= 0 {
            return -.infinity
        }
        return 20.0 * log10(linear)
    }

    /// Extract album name from the first file's metadata.
    static func extractAlbumName(from url: URL) -> String? {
        guard let metadata = try? MetadataReader().read(url: url) else { return nil }
        return metadata.album
    }

    /// Analyze files in parallel using a work-stealing pattern.
    private static func analyzeFilesInParallel(
        files: [URL],
        jobs: Int
    ) -> [Result<TrackResult, Error>] {
        let nextIndex = LockedValue(0)
        let results = LockedValue<[(Int, Result<TrackResult, Error>)]>([])

        let threadCount = min(jobs, files.count)
        var threads: [Thread] = []

        for _ in 0..<threadCount {
            let thread = Thread {
                while true {
                    let index = nextIndex.withLock { value in
                        let current = value
                        value += 1
                        return current
                    }
                    guard index < files.count else { break }

                    let result: Result<TrackResult, Error>
                    do {
                        result = .success(try analyze(file: files[index]))
                    } catch {
                        result = .failure(error)
                    }
                    results.withLock { $0.append((index, result)) }
                }
            }
            thread.start()
            threads.append(thread)
        }

        // Wait for all threads
        for thread in threads {
            while !thread.isFinished {
                Thread.sleep(forTimeInterval: 0.01)
            }
        }

        return results.withLock { value in
            value.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }
}

/// Errors from DRKit analysis.
public enum DRError: Error, LocalizedError {
    case noAudioFiles(String)

    public var errorDescription: String? {
        switch self {
        case .noAudioFiles(let path):
            return "No audio files found in \(path)"
        }
    }
}

/// Thread-safe locked value for cross-thread state sharing.
final class LockedValue<T>: @unchecked Sendable {
    private var value: T
    private let lock = NSLock()

    init(_ value: T) {
        self.value = value
    }

    func withLock<R>(_ body: (inout T) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
