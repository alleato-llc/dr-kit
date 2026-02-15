import Foundation
import Testing
@testable import DRKit

@Suite struct StreamingAnalyzerTests {

    /// Verify streaming DR computation matches legacy `computeDR()` for a mono 440Hz sine wave.
    @Test func streamingMatchesLegacy() {
        let sampleRate = 44100
        let channels = 1
        let duration = 12.0
        let numFrames = Int(Double(sampleRate) * duration)

        // Generate mono sine wave
        var samples: [Float] = []
        samples.reserveCapacity(numFrames)
        for i in 0..<numFrames {
            let t = Double(i) / Double(sampleRate)
            samples.append(Float(sin(2.0 * Double.pi * 440.0 * t)))
        }

        // Legacy computation (interleaved, mono = same as planar)
        let (legacyDR, legacyPeak, legacyRMS) = DRAnalyzer.computeDR(
            samples: samples, channels: channels, sampleRate: sampleRate
        )

        // Streaming computation — feed in chunks simulating decoder frames
        var state = StreamingDrState(channels: channels, sampleRate: sampleRate)
        let chunkSize = 4096
        var offset = 0
        while offset < numFrames {
            let count = min(chunkSize, numFrames - offset)
            // For mono, create a single-channel planar pointer
            samples.withUnsafeBufferPointer { buf in
                let ptr = buf.baseAddress! + offset
                state.pushPlanarFrame(channelData: [ptr], frameCount: count)
            }
            offset += count
        }
        let (streamDR, streamPeak, streamRMS, _) = state.finalize(totalFrames: numFrames)

        #expect(streamDR == legacyDR, "DR mismatch: streaming=\(streamDR) legacy=\(legacyDR)")
        #expect(abs(streamPeak - legacyPeak) < 0.01, "Peak mismatch: streaming=\(streamPeak) legacy=\(legacyPeak)")
        #expect(abs(streamRMS - legacyRMS) < 0.01, "RMS mismatch: streaming=\(streamRMS) legacy=\(legacyRMS)")
    }

    /// Verify streaming matches legacy for stereo (0.9x440Hz left + 0.5x880Hz right).
    @Test func streamingStereoMatchesLegacy() {
        let sampleRate = 44100
        let channels = 2
        let duration = 12.0
        let numFrames = Int(Double(sampleRate) * duration)

        // Generate planar stereo data
        var left: [Float] = []
        var right: [Float] = []
        left.reserveCapacity(numFrames)
        right.reserveCapacity(numFrames)

        // Also build interleaved for legacy
        var interleaved: [Float] = []
        interleaved.reserveCapacity(numFrames * 2)

        for i in 0..<numFrames {
            let t = Double(i) / Double(sampleRate)
            let l = Float(0.9 * sin(2.0 * Double.pi * 440.0 * t))
            let r = Float(0.5 * sin(2.0 * Double.pi * 880.0 * t))
            left.append(l)
            right.append(r)
            interleaved.append(l)
            interleaved.append(r)
        }

        // Legacy
        let (legacyDR, legacyPeak, legacyRMS) = DRAnalyzer.computeDR(
            samples: interleaved, channels: channels, sampleRate: sampleRate
        )

        // Streaming
        var state = StreamingDrState(channels: channels, sampleRate: sampleRate)
        let chunkSize = 4096
        var offset = 0
        while offset < numFrames {
            let count = min(chunkSize, numFrames - offset)
            left.withUnsafeBufferPointer { lBuf in
                right.withUnsafeBufferPointer { rBuf in
                    let lPtr = lBuf.baseAddress! + offset
                    let rPtr = rBuf.baseAddress! + offset
                    state.pushPlanarFrame(channelData: [lPtr, rPtr], frameCount: count)
                }
            }
            offset += count
        }
        let (streamDR, streamPeak, streamRMS, _) = state.finalize(totalFrames: numFrames)

        #expect(streamDR == legacyDR, "DR mismatch: streaming=\(streamDR) legacy=\(legacyDR)")
        #expect(abs(streamPeak - legacyPeak) < 0.01, "Peak mismatch: streaming=\(streamPeak) legacy=\(legacyPeak)")
        #expect(abs(streamRMS - legacyRMS) < 0.01, "RMS mismatch: streaming=\(streamRMS) legacy=\(legacyRMS)")
    }
}
