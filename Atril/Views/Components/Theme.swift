import SwiftUI

extension Color {
    /// Un tono para el modo claro y otro para el oscuro, en componentes sRGB.
    init(light: (red: Double, green: Double, blue: Double), dark: (red: Double, green: Double, blue: Double)) {
        #if os(iOS)
        self.init(uiColor: UIColor { traits in
            let tone = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: tone.red, green: tone.green, blue: tone.blue, alpha: 1)
        })
        #else
        self.init(nsColor: NSColor(name: nil) { appearance in
            let tone = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: tone.red, green: tone.green, blue: tone.blue, alpha: 1)
        })
        #endif
    }

    /// Fondo general de las pantallas.
    static var canvas: Color {
        #if os(iOS)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    /// Fondo de tarjetas sobre `canvas`.
    static var card: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }

    static var hairline: Color { Color.primary.opacity(0.08) }

    /// Ámbar legible sobre fondo claro y oscuro (el amarillo del sistema se pierde en blanco).
    static let amber = Color(red: 0.78, green: 0.52, blue: 0.05)
}

struct CardModifier: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.hairline))
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardModifier(padding: padding)) }
}

/// Encabezado de sección con icono, en mayúsculas pequeñas.
struct SectionLabel: View {
    let title: String
    var symbol: String?
    var tint: Color = .secondary

    var body: some View {
        Label {
            Text(title.uppercased())
        } icon: {
            if let symbol { Image(systemName: symbol) }
        }
        .font(.caption.weight(.semibold))
        .tracking(0.6)
        .foregroundStyle(tint)
    }
}

/// Distintivo del sistema de juego.
struct SystemBadge: View {
    let system: GameSystem
    var compact = false

    var body: some View {
        Label(compact ? system.shortName : system.name, systemImage: system.symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(system.accent)
            .background(system.accent.opacity(0.12), in: Capsule())
    }
}

/// Texto para leer en voz alta: tipografía con serifa y filete lateral, como el texto de caja de los módulos.
struct ReadAloudBox: View {
    let text: String
    let tint: Color
    /// Título para la pantalla de los jugadores; con él aparecen los botones de narrar y enseñar.
    var title: String?
    @State private var presented: Handout?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2).fill(tint).frame(width: 3)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    SectionLabel(title: "Lee en voz alta", symbol: "quote.opening", tint: tint)
                    Spacer()
                    if let title {
                        HandoutButtons(handout: Handout(title: title, body: text, style: .narration), presented: $presented, tint: tint)
                    }
                }
                Text(text)
                    .font(.system(.body, design: .serif))
                    .lineSpacing(3)
                    .textSelection(.enabled)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .handoutPresenter($presented)
    }
}

/// Fila con viñeta para listas cortas.
struct BulletRow: View {
    let text: String
    var symbol = "circle.fill"
    var tint: Color = .secondary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: symbol == "circle.fill" ? 5 : 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 14)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Renderizado ligero del Markdown que devuelve el tutor: párrafos, viñetas y negritas.
struct MarkdownText: View {
    let text: String
    /// Texto que aún está llegando: cambia con cada palabra y no merece guardarse.
    var isLive = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array((isLive ? Self.parse(Self.closingOpenBold(text)) : Self.blocks(text)).enumerated()), id: \.offset) { _, block in
                switch block.kind {
                case .heading:
                    Text(block.text).font(.subheadline.weight(.semibold)).padding(.top, 4)
                case .bullet:
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(.secondary)
                        Text(block.text).fixedSize(horizontal: false, vertical: true)
                    }
                case .paragraph:
                    Text(block.text).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .textSelection(.enabled)
    }

    struct Block {
        enum Kind { case heading, bullet, paragraph }
        let kind: Kind
        let text: AttributedString
    }

    /// Interpretar el Markdown es lo más caro de pintar una respuesta: se hace una vez por texto.
    private static let parsed = BoundedCache<String, [Block]>(limit: 256)

    static func blocks(_ text: String) -> [Block] {
        parsed.value(for: text) { parse(text) }
    }

    static func parse(_ text: String) -> [Block] {
        text.components(separatedBy: "\n").compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { return nil }
            if line.hasPrefix("#") { return Block(kind: .heading, text: inline(line.trimmingCharacters(in: CharacterSet(charactersIn: "# ")))) }
            for marker in ["- ", "* ", "• "] where line.hasPrefix(marker) {
                return Block(kind: .bullet, text: inline(String(line.dropFirst(marker.count))))
            }
            return Block(kind: .paragraph, text: inline(line))
        }
    }

    /// Mientras llega la respuesta, una negrita a medio escribir («**Mantén a…») se vería con
    /// sus asteriscos: se cierra provisionalmente al final del texto.
    static func closingOpenBold(_ text: String) -> String {
        let lastLine = text.split(separator: "\n", omittingEmptySubsequences: false).last ?? ""
        return lastLine.components(separatedBy: "**").count.isMultiple(of: 2) ? text + "**" : text
    }

    private static func inline(_ value: String) -> AttributedString {
        (try? AttributedString(markdown: value, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(value)
    }
}
