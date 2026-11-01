import SwiftUI

/// Lo que se enseña a los jugadores: un texto narrado o un documento del juego.
struct Handout: Codable, Hashable, Identifiable {
    enum Style: String, Codable { case narration, document, portrait }

    var id = UUID()
    var title: String
    var body: String
    var style: Style
    var imageData: Data?
}

/// Pantalla para girar el iPad hacia la mesa (o llevar a otra pantalla en el Mac):
/// solo el texto, grande y legible, sin nada de la información del máster.
struct PlayerScreenView: View {
    let handout: Handout
    @Environment(\.dismiss) private var dismiss
    @State private var showControls = true
    private var narrator: Narrator { .shared }

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            GeometryReader { geometry in
                ScrollView {
                    content
                        .padding(.horizontal, 48)
                        .padding(.vertical, 80)
                        .frame(maxWidth: 980)
                        .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }
            }
            .scrollIndicators(.hidden)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() } }

            if showControls { controls.transition(.opacity) }
        }
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 480)
        .navigationTitle(handout.title)
        #endif
        .onDisappear { if narrator.isSpeaking(handout.id.uuidString) { narrator.stop() } }
    }

    @ViewBuilder
    private var background: some View {
        switch handout.style {
        case .narration, .portrait:
            RadialGradient(colors: [Color(red: 0.10, green: 0.12, blue: 0.13), .black], center: .center, startRadius: 40, endRadius: 900)
        case .document:
            LinearGradient(colors: [Color(red: 0.16, green: 0.12, blue: 0.09), Color(red: 0.07, green: 0.05, blue: 0.04)],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch handout.style {
        case .narration:
            VStack(spacing: 28) {
                if !handout.title.isEmpty {
                    Text(handout.title.uppercased())
                        .font(.system(.title3, design: .serif).weight(.semibold))
                        .tracking(3)
                        .foregroundStyle(Color(red: 0.85, green: 0.72, blue: 0.48))
                }
                Text(handout.body)
                    .font(.system(size: 34, weight: .regular, design: .serif))
                    .lineSpacing(10)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color(red: 0.95, green: 0.92, blue: 0.86))
            }
        case .portrait:
            VStack(spacing: 24) {
                if let data = handout.imageData, let image = Image(portraitData: data) {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 560, maxHeight: 560)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color(red: 0.85, green: 0.72, blue: 0.48).opacity(0.6), lineWidth: 2))
                        .shadow(color: .black.opacity(0.6), radius: 30, y: 10)
                }
                Text(handout.title)
                    .font(.system(size: 34, weight: .semibold, design: .serif))
                    .foregroundStyle(Color(red: 0.95, green: 0.92, blue: 0.86))
            }
        case .document:
            VStack(alignment: .leading, spacing: 18) {
                Text(handout.title)
                    .font(.system(size: 30, weight: .bold, design: .serif))
                    .foregroundStyle(Color(red: 0.25, green: 0.16, blue: 0.08))
                Rectangle().fill(Color(red: 0.45, green: 0.32, blue: 0.18).opacity(0.4)).frame(height: 1)
                Text(handout.body)
                    .font(.system(size: 26, design: .serif))
                    .italic()
                    .lineSpacing(8)
                    .foregroundStyle(Color(red: 0.22, green: 0.15, blue: 0.08))
            }
            .padding(44)
            .frame(maxWidth: 760, alignment: .leading)
            .background(
                LinearGradient(colors: [Color(red: 0.96, green: 0.92, blue: 0.82), Color(red: 0.90, green: 0.84, blue: 0.70)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 6)
            )
            .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
            .rotationEffect(.degrees(-0.6))
        }
    }

    private var controls: some View {
        VStack {
            HStack(spacing: 12) {
                Button {
                    narrator.toggle(handout.title.isEmpty ? handout.body : "\(handout.title). \(handout.body)", id: handout.id.uuidString)
                } label: {
                    Label(narrator.isSpeaking(handout.id.uuidString) ? "Parar" : "Narrar",
                          systemImage: narrator.isSpeaking(handout.id.uuidString) ? "stop.fill" : "speaker.wave.2.fill")
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Label("Cerrar", systemImage: "xmark")
                }
                .keyboardShortcut(.cancelAction)
            }
            .buttonStyle(.bordered)
            .tint(.white)
            .controlSize(.large)
            .padding(20)
            Spacer()
            Text("Toca la pantalla para ocultar los controles")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.35))
                .padding(.bottom, 16)
        }
    }
}

/// Presenta un `Handout`: a pantalla completa en el iPad y en una ventana aparte en el Mac,
/// para poder llevarla a otro monitor o a la tele.
struct HandoutPresenter: ViewModifier {
    @Binding var handout: Handout?
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    func body(content: Content) -> some View {
        #if os(iOS)
        content.fullScreenCover(item: $handout) { PlayerScreenView(handout: $0) }
        #else
        content.onChange(of: handout) {
            guard let handout else { return }
            openWindow(id: "handout", value: handout)
            self.handout = nil
        }
        #endif
    }
}

extension View {
    func handoutPresenter(_ handout: Binding<Handout?>) -> some View {
        modifier(HandoutPresenter(handout: handout))
    }
}

/// Botones de narrar y enseñar, para el texto en voz alta y las pistas.
struct HandoutButtons: View {
    let handout: Handout
    @Binding var presented: Handout?
    var tint: Color = .accentColor
    private var narrator: Narrator { .shared }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                narrator.toggle(handout.body, id: handout.body)
            } label: {
                Image(systemName: narrator.isSpeaking(handout.body) ? "stop.circle.fill" : "speaker.wave.2")
            }
            .help(narrator.isSpeaking(handout.body) ? "Parar la narración" : "Narrar en voz alta")
            .accessibilityLabel(narrator.isSpeaking(handout.body) ? "Parar la narración" : "Narrar en voz alta")
            Button {
                presented = handout
            } label: {
                Image(systemName: "rectangle.on.rectangle.angled")
            }
            .help("Enseñar a los jugadores")
            .accessibilityLabel("Enseñar a los jugadores")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(tint)
        .font(.callout.weight(.semibold))
    }
}
