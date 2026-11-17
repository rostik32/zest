import AppKit
import SwiftUI
import ZestCore

/// What the popup view shows.
@MainActor
public final class PopupModel: ObservableObject {
    public init() {}

    @Published public var items: [Completion] = []
    @Published public var selected = 0
    @Published public var isLoading = false
    @Published public var fontSize: CGFloat = 13
    @Published public var visibleRows = 8
    @Published public var showDescriptions = true
    @Published public var palette = Palette.default
    @Published public var fontName = "Menlo"
    /// The row under the mouse pointer.
    @Published public var hovered: Int?
    /// Called with the row that was clicked.
    public var onSelect: ((Int) -> Void)?

    func font(bold: Bool = false) -> Font { PopupFont.font(fontName, size: fontSize, bold: bold) }

    public var rowHeight: CGFloat { (fontSize + 9).rounded() }
    public var footerHeight: CGFloat { showDescriptions ? rowHeight + 2 : 0 }
    public var iconSize: CGFloat { (fontSize + 3).rounded() }

    public func height(itemCount: Int) -> CGFloat {
        CGFloat(min(itemCount, visibleRows)) * rowHeight + footerHeight + 8
    }
}

// MARK: - View

public struct PopupView: View {
    @ObservedObject var model: PopupModel
    let icons: IconResolver

    public init(model: PopupModel, icons: IconResolver) {
        self.model = model
        self.icons = icons
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(model.items.enumerated()), id: \.offset) { index, item in
                            Row(item: item, selected: index == model.selected, hovered: index == model.hovered,
                                model: model, icons: icons)
                                .id(index)
                                .contentShape(Rectangle())
                                .onHover { inside in
                                    if inside { model.hovered = index } else if model.hovered == index { model.hovered = nil }
                                }
                                .onTapGesture { model.onSelect?(index) }
                        }
                    }
                }
                .onChange(of: model.selected) { _, new in proxy.scrollTo(new) }
                .onChange(of: model.items) { _, _ in proxy.scrollTo(model.selected) }
            }
            if model.showDescriptions {
                Rectangle().fill(model.palette.border).frame(height: 1)
                Footer(model: model)
            }
        }
        .padding(.vertical, 4)
        .background(model.palette.background)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(model.palette.border, lineWidth: 1))
        .environment(\.colorScheme, model.palette.isDark ? .dark : .light)
    }
}

private struct Row: View {
    let item: Completion
    let selected: Bool
    var hovered = false
    @ObservedObject var model: PopupModel
    let icons: IconResolver

    var body: some View {
        HStack(spacing: 8) {
            IconView(icon: icons.icon(for: item), size: model.iconSize, palette: model.palette)
            Text(highlighted)
                .font(model.font())
                .lineLimit(1)
                .strikethrough(item.deprecated, color: model.palette.dim)
            Spacer(minLength: 12)
            if model.showDescriptions, let description = item.description, !selected {
                Text(description)
                    .font(.system(size: model.fontSize - 2))
                    .foregroundStyle(model.palette.dim)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 180, alignment: .trailing)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: model.rowHeight)
        .background(selected ? model.palette.selection : hovered ? model.palette.selection.opacity(0.5) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .padding(.horizontal, 4)
    }

    private var highlighted: AttributedString {
        var text = AttributedString(item.name)
        text.foregroundColor = selected ? model.palette.selectedText : model.palette.text
        let characters = Array(item.name)
        for index in item.matchedIndices where index < characters.count {
            let start = text.index(text.startIndex, offsetByCharacters: index)
            let end = text.index(start, offsetByCharacters: 1)
            text[start..<end].foregroundColor = model.palette.match
            text[start..<end].font = model.font(bold: true)
        }
        return text
    }
}

private struct Footer: View {
    @ObservedObject var model: PopupModel

    var body: some View {
        HStack(spacing: 6) {
            let item = model.items.indices.contains(model.selected) ? model.items[model.selected] : nil
            Text(item?.description ?? item?.name ?? "")
                .font(.system(size: model.fontSize - 1).italic())
                .foregroundStyle(model.palette.subcommand)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if model.isLoading {
                ProgressView().controlSize(.mini).tint(model.palette.dim)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: model.rowHeight)
    }
}

public struct IconView: View {
    let icon: IconResolver.Icon
    let size: CGFloat
    let palette: Palette

    public init(icon: IconResolver.Icon, size: CGFloat, palette: Palette = .default) {
        self.icon = icon
        self.size = size
        self.palette = palette
    }

    public var body: some View {
        Group {
            switch icon {
            case .material(let name):
                if let image = IconCache.shared.material(name) {
                    Image(nsImage: image).resizable().interpolation(.high)
                } else {
                    Codicon(name: "symbol-variable", color: palette.dim, size: size)
                }
            case .codicon(let name, let role):
                Codicon(name: name, color: Self.color(role, palette), size: size)
            case .emoji(let emoji):
                Text(emoji).font(.system(size: size - 3))
            }
        }
        .frame(width: size, height: size)
    }

    public static func color(_ role: IconResolver.Role, _ palette: Palette = .default) -> Color {
        switch role {
        case .command: return palette.command
        case .subcommand: return palette.subcommand
        case .option: return palette.option
        case .argument: return palette.argument
        case .history: return palette.history
        }
    }
}

private struct Codicon: View {
    let name: String
    let color: Color
    let size: CGFloat

    var body: some View {
        Text(IconCache.shared.codicon(name))
            .font(.custom("codicon", size: size - 1))
            .foregroundStyle(color)
    }
}

/// Loads icons on first use and keeps them.
@MainActor
public final class IconCache {
    public static let shared = IconCache()
    public var materialDirectory: URL?
    private var images: [String: NSImage] = [:]
    private var codepoints: [String: String] = [:]

    public func configure(icons: URL?) {
        guard let icons else { return }
        materialDirectory = icons.appendingPathComponent("material")
        let font = icons.appendingPathComponent("codicon.ttf")
        CTFontManagerRegisterFontsForURL(font as CFURL, .process, nil)
        if let data = try? Data(contentsOf: icons.appendingPathComponent("codicons.json")),
           let map = try? JSONDecoder().decode([String: String].self, from: data) {
            for (name, hex) in map {
                if let value = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(value) {
                    codepoints[name] = String(Character(scalar))
                }
            }
        }
    }

    func material(_ name: String) -> NSImage? {
        if let image = images[name] { return image }
        guard let url = materialDirectory?.appendingPathComponent(name + ".svg"),
              let image = NSImage(contentsOf: url) else { return nil }
        images[name] = image
        return image
    }

    func codicon(_ name: String) -> String {
        codepoints[name] ?? "•"
    }
}
