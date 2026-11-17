import AppKit
import SwiftUI
import ZestCore

/// The popup's colors, made from a `ZestTheme`.
public struct Palette: Equatable, Sendable {
    public var background, border, selection, text, selectedText, match, dim: Color
    public var command, subcommand, option, argument: Color
    public var history: Color { dim }
    /// Light themes need the system controls (e.g. the spinner) in their light look.
    public var isDark: Bool

    public init(_ theme: ZestTheme) {
        func color(_ token: ZestTheme.Token) -> Color { Color(theme[token]) }
        background = color(.background)
        border = color(.border)
        selection = color(.selection)
        text = color(.text)
        selectedText = color(.selectedText)
        match = color(.match)
        dim = color(.description)
        command = color(.command)
        subcommand = color(.subcommand)
        option = color(.option)
        argument = color(.argument)
        isDark = theme.appearance == .dark
    }

    public static let `default` = Palette(.oneDarkProDarker)
}

/// The default palette, for places that don't follow the chosen theme (the README demo).
public enum Theme {
    public static var background: Color { Palette.default.background }
    public static var border: Color { Palette.default.border }
    public static var selection: Color { Palette.default.selection }
    public static var text: Color { Palette.default.text }
    public static var selectedText: Color { Palette.default.selectedText }
    public static var match: Color { Palette.default.match }
    public static var dim: Color { Palette.default.dim }
    public static var command: Color { Palette.default.command }
    public static var subcommand: Color { Palette.default.subcommand }
    public static var option: Color { Palette.default.option }
    public static var argument: Color { Palette.default.argument }
    public static var history: Color { Palette.default.history }
}

/// Monospaced fonts for the suggestions. `system` is SF Mono.
public enum PopupFont {
    public static let system = "System Monospaced"

    public static func font(_ name: String, size: CGFloat, bold: Bool = false) -> Font {
        if name == system || NSFont(name: name, size: size) == nil && NSFontManager.shared.availableMembers(ofFontFamily: name) == nil {
            return .system(size: size, weight: bold ? .bold : .regular, design: .monospaced)
        }
        let font = Font.custom(name, size: size)
        return bold ? font.bold() : font
    }

    /// Installed monospaced font families, with SF Mono first.
    public static func families() -> [String] {
        let manager = NSFontManager.shared
        let mono = manager.availableFontFamilies.filter { family in
            guard let first = manager.availableMembers(ofFontFamily: family)?.first,
                  let name = first.first as? String, let font = NSFont(name: name, size: 13) else { return false }
            return font.isFixedPitch && !family.hasPrefix(".")
        }
        return [system] + mono.sorted()
    }
}

extension Color {
    public init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }

    public init(_ rgba: RGBA) {
        self.init(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
    }
}
