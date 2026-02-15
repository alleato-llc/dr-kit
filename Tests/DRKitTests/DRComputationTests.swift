import Foundation
import Testing
@testable import DRKit

@Suite struct DRComputationTests {

    // MARK: - dbFS

    @Test func dbFSFullScale() {
        let result = DRAnalyzer.dbFS(1.0)
        #expect(abs(result - 0.0) < 0.001)
    }

    @Test func dbFSHalf() {
        let result = DRAnalyzer.dbFS(0.5)
        #expect(abs(result - (-6.0206)) < 0.01)
    }

    @Test func dbFSZero() {
        let result = DRAnalyzer.dbFS(0.0)
        #expect(result.isInfinite)
    }

    // MARK: - Block Stats

    @Test func blockStatsMonoSilence() {
        let samples = [Float](repeating: 0, count: 44100)
        let stats = DRAnalyzer.computeBlockStats(samples, channels: 1)
        #expect(stats.rms[0] == 0.0)
        #expect(stats.peak[0] == 0.0)
    }

    @Test func blockStatsMonoConstant() {
        // Mono constant value 0.5:
        // DR-RMS = sqrt(2 * sum(0.25) / N) = sqrt(2 * 0.25) = sqrt(0.5) ≈ 0.7071
        let samples = [Float](repeating: 0.5, count: 44100)
        let stats = DRAnalyzer.computeBlockStats(samples, channels: 1)
        let expectedRMS = (2.0 * 0.25).squareRoot() // sqrt(0.5) ≈ 0.7071
        #expect(abs(stats.rms[0] - expectedRMS) < 0.001)
        #expect(abs(stats.peak[0] - 0.5) < 0.001)
    }

    @Test func blockStatsStereo() {
        // Stereo: left=0.8 right=0.2
        var stereo: [Float] = []
        stereo.reserveCapacity(44100 * 2)
        for _ in 0..<44100 {
            stereo.append(0.8)
            stereo.append(0.2)
        }
        let stats = DRAnalyzer.computeBlockStats(stereo, channels: 2)

        let expectedLeft = (2.0 * 0.64).squareRoot()  // sqrt(1.28) ≈ 1.1314
        let expectedRight = (2.0 * 0.04).squareRoot()  // sqrt(0.08) ≈ 0.2828
        #expect(abs(stats.rms[0] - expectedLeft) < 0.001)
        #expect(abs(stats.rms[1] - expectedRight) < 0.001)
        #expect(abs(stats.peak[0] - 0.8) < 0.001)
        #expect(abs(stats.peak[1] - 0.2) < 0.001)
    }

    // MARK: - DR Computation

    @Test func computeDRSineWave() {
        // A full-scale sine wave: with the sqrt(2) calibration, DR-RMS equals peak
        // so DR should be ~0
        let sampleRate = 44100
        let duration = 12.0
        let numSamples = Int(Double(sampleRate) * duration)
        var samples: [Float] = []
        samples.reserveCapacity(numSamples)
        for i in 0..<numSamples {
            let t = Double(i) / Double(sampleRate)
            samples.append(Float(sin(2.0 * Double.pi * 440.0 * t)))
        }
        let (dr, peakDB, rmsDB) = DRAnalyzer.computeDR(
            samples: samples, channels: 1, sampleRate: sampleRate
        )
        #expect(dr <= 1, "Pure sine DR should be ~0, got DR\(dr)")
        #expect(peakDB > -0.1, "Peak should be near 0 dBFS, got \(peakDB)")
        #expect(rmsDB > -1.0, "DR-RMS of sine should be near 0 dBFS, got \(rmsDB)")
    }

    @Test func computeDRTooShort() {
        // Less than one 3-second block should return DR 0
        let samples = [Float](repeating: 0.5, count: 1000)
        let (dr, _, _) = DRAnalyzer.computeDR(samples: samples, channels: 1, sampleRate: 44100)
        #expect(dr == 0)
    }

    @Test func computeDREmptySamples() {
        let (dr, peakDB, rmsDB) = DRAnalyzer.computeDR(samples: [], channels: 1, sampleRate: 44100)
        #expect(dr == 0)
        #expect(peakDB == -.infinity)
        #expect(rmsDB == -.infinity)
    }
}
