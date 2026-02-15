import DRKit
import Tint

enum DRRenderer {
    static func render(state: DRAppState, area: Rect, theme: DRTheme, buffer: inout Buffer) {
        let sections = Layout(
            direction: .vertical,
            constraints: [.fixed(3), .fill, .fixed(3), .fixed(1)]
        ).split(area)

        renderHeader(state: state, area: sections[0], theme: theme, buffer: &buffer)
        renderTrackTable(state: state, area: sections[1], theme: theme, buffer: &buffer)
        renderSummary(state: state, area: sections[2], theme: theme, buffer: &buffer)
        renderFooter(state: state, area: sections[3], theme: theme, buffer: &buffer)

        switch state.view {
        case .about:
            renderAboutOverlay(area: area, theme: theme, buffer: &buffer)
        case .export:
            renderExportOverlay(state: state, area: area, theme: theme, buffer: &buffer)
        case .info:
            renderInfoOverlay(state: state, area: area, theme: theme, buffer: &buffer)
        case .regenerateConfirm:
            renderRegenerateOverlay(area: area, theme: theme, buffer: &buffer)
        case .main:
            break
        }
    }

    // MARK: - Header

    private static func renderHeader(
        state: DRAppState, area: Rect, theme: DRTheme, buffer: inout Buffer
    ) {
        let titleText = state.loadedFromCache ? " DR Meter (cached) " : " DR Meter "
        Block(
            title: titleText,
            titleStyle: theme.accent,
            borderStyle: .plain,
            style: theme.border
        ).render(area: area, buffer: &buffer)

        let inner = area.inset(top: 1, right: 1, bottom: 1, left: 1)
        let albumText = state.albumTitle ?? "Unknown Album"
        let pathText = state.path.path

        buffer.write("Album: ", x: inner.x, y: inner.y, style: theme.muted)
        buffer.write(albumText, x: inner.x + 7, y: inner.y, style: Style(fg: .white, bold: true))

        let pathStart = inner.x + 7 + albumText.count + 2
        if pathStart + 6 + pathText.count <= inner.x + inner.width {
            buffer.write("Path: ", x: pathStart, y: inner.y, style: theme.muted)
            buffer.write(pathText, x: pathStart + 6, y: inner.y, style: theme.muted)
        }
    }

    // MARK: - Track Table

    private static func renderTrackTable(
        state: DRAppState, area: Rect, theme: DRTheme, buffer: inout Buffer
    ) {
        let innerHeight = max(area.height - 3, 0) // 2 borders + 1 header
        state.visibleRows = innerHeight

        // Scroll indicator
        let total = state.tracks.count
        var scrollInfo = ""
        if total > innerHeight {
            let hasAbove = state.scrollOffset > 0
            let hasBelow = state.scrollOffset + innerHeight < total
            let first = state.scrollOffset + 1
            let last = min(state.scrollOffset + innerHeight, total)
            switch (hasAbove, hasBelow) {
            case (true, true): scrollInfo = " [\(first)-\(last)/\(total)] \u{2191}\u{2193} "
            case (true, false): scrollInfo = " [\(first)-\(last)/\(total)] \u{2191} "
            case (false, true): scrollInfo = " [1-\(min(innerHeight, total))/\(total)] \u{2193} "
            case (false, false): break
            }
        }

        Block(
            title: scrollInfo,
            titleStyle: theme.muted,
            borderStyle: .plain,
            style: theme.border
        ).render(area: area, buffer: &buffer)

        let inner = area.inset(top: 1, right: 1, bottom: 1, left: 1)
        guard inner.height > 0, inner.width > 0 else { return }

        // Header row
        let cols = columnLayout(width: inner.width)
        buffer.write("#", x: inner.x + cols.num, y: inner.y, style: theme.muted)
        buffer.write("Track", x: inner.x + cols.track, y: inner.y, style: theme.muted)
        buffer.write("DR", x: inner.x + cols.dr, y: inner.y, style: theme.muted)
        buffer.write("Peak", x: inner.x + cols.peak, y: inner.y, style: theme.muted)
        buffer.write("RMS", x: inner.x + cols.rms, y: inner.y, style: theme.muted)
        buffer.write("Duration", x: inner.x + cols.duration, y: inner.y, style: theme.muted)

        // Track rows
        let endIndex = min(state.scrollOffset + innerHeight, state.tracks.count)
        for vi in 0..<(endIndex - state.scrollOffset) {
            let actualIndex = state.scrollOffset + vi
            let y = inner.y + 1 + vi
            guard y < inner.y + inner.height else { break }

            let (name, status) = state.tracks[actualIndex]
            let isSelected = actualIndex == state.selected
            let rowStyle = isSelected ? Style(bg: .brightBlack) : Style()

            if isSelected {
                for x in inner.x..<(inner.x + inner.width) {
                    buffer[x, y] = Cell(character: " ", style: rowStyle)
                }
            }

            let num = "\(actualIndex + 1)"
            buffer.write(num, x: inner.x + cols.num, y: y, style: rowStyle)

            switch status {
            case .pending:
                buffer.write(name, x: inner.x + cols.track, y: y, style: rowStyle)
                buffer.write("\u{00b7}", x: inner.x + cols.dr, y: y, style: theme.muted)

            case .analyzing(let pct):
                buffer.write(name, x: inner.x + cols.track, y: y, style: rowStyle)
                let barWidth = 12
                let filled = Int(pct * Float(barWidth))
                let empty = barWidth - filled
                let bar =
                    String(repeating: "\u{2588}", count: filled)
                    + String(repeating: "\u{2591}", count: empty)
                    + " \(Int(pct * 100))%"
                buffer.write(bar, x: inner.x + cols.dr, y: y, style: theme.progress)

            case .complete(let result):
                let trackWidth = cols.dr - cols.track - 1
                let displayTitle =
                    result.title.count > trackWidth
                    ? String(result.title.prefix(trackWidth)) : result.title
                buffer.write(displayTitle, x: inner.x + cols.track, y: y, style: rowStyle)
                buffer.write(
                    "DR\(result.dr)", x: inner.x + cols.dr, y: y,
                    style: theme.drColor(result.dr))
                buffer.write(
                    String(format: "%.2fdB", result.peakDB), x: inner.x + cols.peak, y: y,
                    style: rowStyle)
                buffer.write(
                    String(format: "%.2fdB", result.rmsDB), x: inner.x + cols.rms, y: y,
                    style: rowStyle)
                buffer.write(
                    DRFormatter.formatDuration(result.durationSeconds),
                    x: inner.x + cols.duration, y: y, style: rowStyle)
                buffer.write(
                    "\u{2713}", x: inner.x + inner.width - 1, y: y, style: theme.complete)

            case .error(let msg):
                buffer.write(name, x: inner.x + cols.track, y: y, style: rowStyle)
                buffer.write("ERR", x: inner.x + cols.dr, y: y, style: theme.error)
                buffer.write(msg, x: inner.x + cols.peak, y: y, style: theme.error)
                buffer.write(
                    "\u{2717}", x: inner.x + inner.width - 1, y: y, style: theme.error)
            }
        }
    }

    // MARK: - Summary

    private static func renderSummary(
        state: DRAppState, area: Rect, theme: DRTheme, buffer: inout Buffer
    ) {
        Block(borderStyle: .plain, style: theme.border).render(area: area, buffer: &buffer)

        let inner = area.inset(top: 1, right: 1, bottom: 1, left: 1)
        let completed = state.completedCount
        let total = state.tracks.count

        let drText: String
        if let album = state.albumResult {
            drText = "Overall DR: DR\(album.overallDR)"
        } else if completed > 0 {
            let sum: UInt = state.tracks.compactMap {
                if case .complete(let r) = $0.1 { r.dr } else { nil }
            }.reduce(0, +)
            drText = "Overall DR: ~DR\(sum / UInt(completed))"
        } else {
            drText = "Overall DR: --"
        }

        let text = "\(drText) (\(completed)/\(total) complete)"
        let x = inner.x + max((inner.width - text.count) / 2, 0)
        buffer.write(text, x: x, y: inner.y, style: theme.primary)
    }

    // MARK: - Footer

    private static func renderFooter(
        state: DRAppState, area: Rect, theme: DRTheme, buffer: inout Buffer
    ) {
        let keys: String
        switch state.view {
        case .main:
            if state.albumResult != nil || state.loadedFromCache {
                keys = "[e]xport  [i]nfo  [r]egenerate  [a]bout  [q]uit"
            } else {
                keys = "[a]bout  [q]uit"
            }
        case .about, .export, .info, .regenerateConfirm:
            keys = "[Esc] close"
        }
        let x = area.x + max((area.width - keys.count) / 2, 0)
        buffer.write(keys, x: x, y: area.y, style: theme.muted)
    }

    // MARK: - Overlays

    private static func renderAboutOverlay(area: Rect, theme: DRTheme, buffer: inout Buffer) {
        let overlay = centeredRect(width: 40, height: 10, in: area)
        clearArea(overlay, buffer: &buffer)

        Block(
            title: " About ",
            titleStyle: theme.accent,
            borderStyle: .plain,
            style: theme.border
        ).render(area: overlay, buffer: &buffer)

        let inner = overlay.inset(top: 1, right: 1, bottom: 1, left: 1)
        let lines = [
            ("DR Meter", theme.accent),
            ("", theme.primary),
            ("Dynamic range analyzer for audio files.", theme.primary),
            ("Uses the Pleasurize Music / DR Database algorithm.", theme.primary),
            ("", theme.primary),
            ("[Esc] close", theme.muted),
        ]

        for (i, (text, style)) in lines.enumerated() {
            let y = inner.y + i
            guard y < inner.y + inner.height else { break }
            let x = inner.x + max((inner.width - text.count) / 2, 0)
            buffer.write(text, x: x, y: y, style: style)
        }
    }

    private static func renderExportOverlay(
        state: DRAppState, area: Rect, theme: DRTheme, buffer: inout Buffer
    ) {
        let overlay = centeredRect(width: 50, height: 12, in: area)
        clearArea(overlay, buffer: &buffer)

        Block(
            title: " Export ",
            titleStyle: theme.accent,
            borderStyle: .plain,
            style: theme.border
        ).render(area: overlay, buffer: &buffer)

        let inner = overlay.inset(top: 1, right: 1, bottom: 1, left: 1)
        let outputPath = state.path.appendingPathComponent("dr_report.\(state.exportFormat.ext)")

        var lines: [(String, Style)] = [
            ("Export Report", theme.accent),
            ("", theme.primary),
            ("Format: \(state.exportFormat.label)", theme.primary),
            ("Output: \(outputPath.path)", theme.primary),
            ("", theme.primary),
            ("[Tab] cycle format  [Enter] save  [Esc] cancel", theme.muted),
        ]

        if let msg = state.exportMessage {
            lines.append(("", theme.primary))
            lines.append((msg, theme.complete))
        }

        for (i, (text, style)) in lines.enumerated() {
            let y = inner.y + i
            guard y < inner.y + inner.height else { break }
            let x = inner.x + max((inner.width - text.count) / 2, 0)
            buffer.write(text, x: x, y: y, style: style)
        }
    }

    private static func renderInfoOverlay(
        state: DRAppState, area: Rect, theme: DRTheme, buffer: inout Buffer
    ) {
        let overlay = centeredRect(width: 50, height: 14, in: area)
        clearArea(overlay, buffer: &buffer)

        Block(
            title: " Info ",
            titleStyle: theme.accent,
            borderStyle: .plain,
            style: theme.border
        ).render(area: overlay, buffer: &buffer)

        let inner = overlay.inset(top: 1, right: 1, bottom: 1, left: 1)
        var lines: [(String, Style)] = []

        if state.loadedFromCache, state.benchmark == nil {
            lines.append(("Loaded from cached report", theme.accent))
            lines.append(("", theme.primary))
            lines.append(("Tracks: \(state.tracks.count)", theme.primary))
            lines.append(("", theme.primary))
            lines.append(("Press [r] to re-analyze", theme.muted))
        } else if let bench = state.benchmark {
            lines.append(("Analysis Complete", theme.accent))
            lines.append(("", theme.primary))
            lines.append(("Tracks: \(bench.trackTimings.count)", theme.primary))
            let totalSecs = bench.totalElapsed.seconds
            lines.append(("Total time: \(String(format: "%.1fs", totalSecs))", theme.primary))
            let avgSecs = bench.avgPerTrack.seconds
            lines.append(("Avg/track: \(String(format: "%.1fs", avgSecs))", theme.primary))
            lines.append(("Total size: \(String(format: "%.1f MB", bench.totalMB))", theme.primary))
            lines.append(("Throughput: \(String(format: "%.1f MB/s", bench.mbPerSec))", theme.primary))
        } else {
            lines.append(("Analysis in progress...", theme.muted))
        }

        lines.append(("", theme.primary))
        lines.append(("[Esc] close", theme.muted))

        for (i, (text, style)) in lines.enumerated() {
            let y = inner.y + i
            guard y < inner.y + inner.height else { break }
            let x = inner.x + max((inner.width - text.count) / 2, 0)
            buffer.write(text, x: x, y: y, style: style)
        }
    }

    private static func renderRegenerateOverlay(
        area: Rect, theme: DRTheme, buffer: inout Buffer
    ) {
        let overlay = centeredRect(width: 50, height: 10, in: area)
        clearArea(overlay, buffer: &buffer)

        Block(
            title: " Regenerate ",
            titleStyle: theme.accent,
            borderStyle: .plain,
            style: theme.border
        ).render(area: overlay, buffer: &buffer)

        let inner = overlay.inset(top: 1, right: 1, bottom: 1, left: 1)
        let lines: [(String, Style)] = [
            ("Re-analyze all tracks?", theme.accent),
            ("", theme.primary),
            ("This will overwrite the cached report.", theme.primary),
            ("", theme.primary),
            ("[y]es  [n]o", theme.muted),
        ]

        for (i, (text, style)) in lines.enumerated() {
            let y = inner.y + i
            guard y < inner.y + inner.height else { break }
            let x = inner.x + max((inner.width - text.count) / 2, 0)
            buffer.write(text, x: x, y: y, style: style)
        }
    }

    // MARK: - Helpers

    private struct ColumnLayout {
        let num: Int
        let track: Int
        let dr: Int
        let peak: Int
        let rms: Int
        let duration: Int
    }

    private static func columnLayout(width: Int) -> ColumnLayout {
        ColumnLayout(
            num: 0,
            track: 4,
            dr: max(width - 42, 24),
            peak: max(width - 30, 36),
            rms: max(width - 20, 46),
            duration: max(width - 10, 56)
        )
    }

    private static func centeredRect(width: Int, height: Int, in area: Rect) -> Rect {
        let x = area.x + max((area.width - width) / 2, 0)
        let y = area.y + max((area.height - height) / 2, 0)
        return Rect(
            x: x, y: y,
            width: min(width, area.width),
            height: min(height, area.height)
        )
    }

    private static func clearArea(_ area: Rect, buffer: inout Buffer) {
        buffer.fill(area, cell: Cell(character: " ", style: Style()))
    }
}
