import AppKit
import SwiftUI

struct Design {
    let dark: Bool
    var ink: Color { color(0x202536, 0xE9EDF9) }
    var muted: Color { color(0x515C70, 0xAFB9C9) }
    var field: Color { color(0xF4F5FA, 0x22283A) }
    var surface: Color { color(0xFFFFFF, 0x202733) }
    var canvas: Color { color(0xFFFFFF, 0x151925) }
    var accent: Color { color(0x0042D0, 0xA6B5FF) }
    var tint: Color { color(0xDFE9FF, 0x292F54) }
    var statusInk: Color { color(0x344BC3, 0xA6B5FF) }
    var positive: Color { color(0x277653, 0x95D5B5) }
    var line: Color { color(0xE6E8EF, 0x30384C) }
    var primary: Color { Color(hex: 0x344BC3) }

    private func color(_ light: UInt32, _ night: UInt32) -> Color { Color(hex: dark ? night : light) }

    func heading(_ size: CGFloat, bold: Bool = true) -> Font {
        Font.installed(bold ? "Geologica-SemiBold" : "Geologica-Regular", size: size, weight: bold ? .semibold : .regular)
    }

    func body(_ size: CGFloat = 15, bold: Bool = false) -> Font {
        Font.installed(bold ? "GolosText-SemiBold" : "GolosText-Regular", size: size, weight: bold ? .semibold : .regular)
    }

    func ui(_ size: CGFloat = 13, bold: Bool = true) -> Font {
        Font.installed(bold ? "GolosText-SemiBold" : "GolosText-Regular", size: size, weight: bold ? .semibold : .regular)
    }
}

enum Space {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 6
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

extension Color {
    fileprivate init(hex: UInt32) {
        self.init(red: Double(hex >> 16) / 255, green: Double(hex >> 8 & 255) / 255, blue: Double(hex & 255) / 255)
    }
}

extension Font {
    fileprivate static func installed(_ name: String, size: CGFloat, weight: Font.Weight) -> Font {
        if let bundled = PrototypeFonts.font(name, size: size) { return bundled }
        return NSFont(name: name, size: size) == nil ? .system(size: size, weight: weight) : .custom(name, fixedSize: size)
    }
}
private enum DesignKey: EnvironmentKey {
    static let defaultValue = Design(dark: false)
}

extension EnvironmentValues {
    var design: Design {
        get { self[DesignKey.self] }
        set { self[DesignKey.self] = newValue }
    }
}

enum ChipStyle { case plain, selected, primary }

struct Chip: View {
    @Environment(\.design) private var design
    let title: String
    var style: ChipStyle = .plain
    var compact = false
    var icon: String? = nil
    var disclosure = false

    var body: some View {
        HStack(spacing: Space.xs) {
            if let icon { Image(systemName: icon).accessibilityHidden(true) }
            Text(title)
            if disclosure {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .accessibilityHidden(true)
            }
        }
            .font(design.ui(compact ? 12 : 13))
            .foregroundStyle(style == .primary ? .white : (style == .selected ? design.accent : design.muted))
            .padding(.horizontal, compact ? Space.sm : Space.md)
            .frame(minHeight: compact ? 28 : 42)
            .background(style == .primary ? design.primary : (style == .selected ? design.tint : design.field), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ChipButton: View {
    let title: String
    var style: ChipStyle = .plain
    var compact = false
    var icon: String? = nil
    var disclosure = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Chip(title: title, style: style, compact: compact, icon: icon, disclosure: disclosure)
        }
            .buttonStyle(PressStyle())
    }
}

struct PressStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .hoverFeedback()
            .opacity(enabled ? (configuration.isPressed ? 0.72 : 1) : 0.45)
    }
}

private struct HoverFeedback: ViewModifier {
    @Environment(\.design) private var design
    @Environment(\.isEnabled) private var enabled
    @ViewState private var hovered = false
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(design.ink.opacity(enabled && hovered ? 0.08 : 0))
                    .allowsHitTesting(false)
            }
            .onHover { hovered = $0 }
    }
}

extension View {
    func hoverFeedback(cornerRadius: CGFloat = 8) -> some View {
        modifier(HoverFeedback(cornerRadius: cornerRadius))
    }
}
