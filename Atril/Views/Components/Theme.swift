import SwiftUI

extension Color {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let value):
                    Text(inline(value)).font(.subheadline.weight(.semibold)).padding(.top, 4)
                case .bullet(let value):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(.secondary)
                        Text(inline(value)).fixedSize(horizontal: false, vertical: true)
                    }
                case .paragraph(let value):
                    Text(inline(value)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .textSelection(.enabled)
    }

    private enum Block { case heading(String), bullet(String), paragraph(String) }

    private var blocks: [Block] {
        text.components(separatedBy: "\n").compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { return nil }
            if line.hasPrefix("#") { return .heading(line.trimmingCharacters(in: CharacterSet(charactersIn: "# "))) }
            for marker in ["- ", "* ", "• "] where line.hasPrefix(marker) {
                return .bullet(String(line.dropFirst(marker.count)))
            }
            return .paragraph(line)
        }
    }

    private func inline(_ value: String) -> AttributedString {
        (try? AttributedString(markdown: value, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(value)
    }
}
