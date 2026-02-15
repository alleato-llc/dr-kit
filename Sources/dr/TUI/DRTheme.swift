import Tint

struct DRTheme: Theme {
    var primary: Style { Style(fg: .white) }
    var secondary: Style { Style(fg: .brightBlack) }
    var highlight: Style { Style(fg: .black, bg: .cyan, bold: true) }
    var accent: Style { Style(fg: .cyan, bold: true) }
    var muted: Style { Style(fg: .brightBlack) }
    var border: Style { Style(fg: .cyan) }
    var title: Style { Style(fg: .cyan, bold: true) }
    var error: Style { Style(fg: .red, bold: true) }
    var statusBar: Style { Style(fg: .white, bg: .brightBlack) }

    var complete: Style { Style(fg: .green) }
    var progress: Style { Style(fg: .yellow) }

    func drColor(_ dr: UInt) -> Style {
        switch dr {
        case 0...7: Style(fg: .red)
        case 8...11: Style(fg: .yellow)
        default: Style(fg: .green)
        }
    }
}
