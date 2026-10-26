import SwiftUI

/// Al cerrar la mesa: lo que ha dado de sí la sesión, un resumen para compartir con los
/// jugadores y los pendientes para la próxima.
struct SessionEndSheet: View {
    let controller: PlayController
    let onClose: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var recap: SessionRecap?
    @State private var narrated: String?
    @State private var isNarrating = false
    @State private var presented: Handout?

    private var text: String { narrated ?? recap?.forPlayers ?? "" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    stats
                    playersCard
                    if let recap, !recap.forGM.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionLabel(title: "Para ti, la próxima vez", symbol: "list.bullet.clipboard")
                            ForEach(recap.forGM, id: \.self) { BulletRow(text: $0) }
                        }
                        .card()
                    }
                }
                .padding(20)
            }
            .background(Color.canvas)
            .navigationTitle("Fin de la \(controller.session.title.lowercased())")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Seguir jugando") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cerrar la mesa") {
                        controller.savePlayerSummary(text)
                        dismiss()
                        onClose()
                    }
                }
            }
            .task { await prepare() }
            .handoutPresenter($presented)
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 620)
        #endif
    }

    private var stats: some View {
        let facts = controller.recapFacts
        let notes = Recap.ownNotes(facts.notes).count
        return HStack(spacing: 10) {
            stat(Format.duration(controller.elapsed()), "de juego", "timer")
            stat("\(facts.visitedSceneIDs.count)", facts.visitedSceneIDs.count == 1 ? "escena" : "escenas", "rectangle.stack")
            stat("\(facts.foundClueIDs.count)", facts.foundClueIDs.count == 1 ? "pista" : "pistas", "magnifyingglass")
            stat("\(notes)", notes == 1 ? "nota" : "notas", "pencil")
        }
    }

    private func stat(_ value: String, _ label: String, _ symbol: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).foregroundStyle(controller.system.accent)
            Text(value).font(.title3.weight(.semibold).monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .card(padding: 12)
    }

    private var playersCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(title: "Para los jugadores", symbol: "person.3", tint: controller.system.accent)
                Spacer()
                if isNarrating {
                    ProgressView().controlSize(.small)
                    Text("Redactando…").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(text.isEmpty ? "Preparando el resumen…" : text)
                .font(.system(.body, design: .serif))
                .lineSpacing(3)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                ShareLink(item: text, subject: Text(controller.adventure.title)) {
                    Label("Compartir", systemImage: "square.and.arrow.up")
                }
                Button {
                    Narrator.shared.toggle(text, id: "recap-end")
                } label: {
                    Label(Narrator.shared.isSpeaking("recap-end") ? "Parar" : "Narrar",
                          systemImage: Narrator.shared.isSpeaking("recap-end") ? "stop.fill" : "speaker.wave.2")
                }
                Button {
                    presented = Handout(title: "Previamente", body: text, style: .narration)
                } label: {
                    Label("Enseñar", systemImage: "rectangle.on.rectangle.angled")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(text.isEmpty)
            Text("Se guardará para leerlo al empezar la próxima sesión.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .card()
    }

    private func prepare() async {
        let facts = controller.recapFacts
        let basic = Recap.basic(facts)
        recap = basic
        if case .apple(let tier) = AIBackend.current {
            isNarrating = true
            narrated = await Recap.narrated(facts, basic: basic, tier: tier)
            isNarrating = false
        }
    }
}

/// «Previamente…»: el resumen de la sesión anterior, listo para leer al empezar.
struct PreviouslyCard: View {
    let text: String
    let title: String
    let tint: Color
    let onDismiss: () -> Void
    @State private var presented: Handout?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(title: "Previamente en «\(title)»", symbol: "clock.arrow.circlepath", tint: tint)
                Spacer()
                HandoutButtons(handout: Handout(title: "Previamente", body: text, style: .narration), presented: $presented, tint: tint)
                Button(action: onDismiss) {
                    Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Ocultar el resumen")
            }
            Text(text)
                .font(.system(.body, design: .serif))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Text("Léelo para empezar: recuerda a todos dónde lo dejasteis.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tint.opacity(0.25)))
        .handoutPresenter($presented)
    }
}
