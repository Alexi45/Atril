import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(AnalysisCenter.self) private var analysis
    @Query(sort: \Adventure.updatedAt, order: .reverse) private var adventures: [Adventure]

    @State private var selection: Adventure?
    @State private var activeSession: PlaySession?
    @State private var showImport = false
    @State private var showSettings = false
    @State private var pendingDelete: Adventure?

    var body: some View {
        Group {
            if let activeSession {
                PlayView(session: activeSession) {
                    withAnimation(.snappy) { self.activeSession = nil }
                }
                .transition(.opacity)
            } else {
                library
            }
        }
        .sheet(isPresented: $showImport) {
            ImportView { adventure in
                selection = adventure
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsView() }
        }
        .task { seedForScreenshotsIfNeeded() }
    }

    private var library: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(adventures) { adventure in
                    NavigationLink(value: adventure) {
                        AdventureRow(adventure: adventure)
                    }
                    .contextMenu {
                        Button("Eliminar…", systemImage: "trash", role: .destructive) { pendingDelete = adventure }
                    }
                }
                .onDelete { offsets in pendingDelete = offsets.first.map { adventures[$0] } }
            }
            .navigationTitle("Atril")
            .navigationSplitViewColumnWidth(min: 260, ideal: 300)
            .overlay {
                if adventures.isEmpty {
                    ContentUnavailableView("Sin aventuras", systemImage: "books.vertical",
                                           description: Text("Importa el guion de una aventura para empezar."))
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Importar guion", systemImage: "plus") { showImport = true }
                        .keyboardShortcut("n", modifiers: .command)
                }
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) {
                    Button("Ajustes", systemImage: "gearshape") { showSettings = true }
                }
                #endif
            }
        } detail: {
            if let selection {
                AdventureDetailView(adventure: selection) { session in
                    withAnimation(.snappy) { activeSession = session }
                }
                .id(selection.id)
            } else {
                WelcomeView(
                    onImport: { showImport = true },
                    onSample: insertSample,
                    onSettings: { showSettings = true }
                )
            }
        }
        .confirmationDialog(
            "¿Eliminar «\(pendingDelete?.title ?? "")»?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Eliminar aventura y sesiones", role: .destructive) {
                if let pendingDelete {
                    if selection == pendingDelete { selection = nil }
                    context.delete(pendingDelete)
                }
                pendingDelete = nil
            }
        } message: {
            Text("Se borrarán el guion, la guía y todas sus sesiones.")
        }
    }

    private func insertSample() {
        let adventure = SampleAdventure.make(in: context, withSession: false)
        selection = adventure
    }

    /// Argumentos de arranque para capturas: `-seedDemo` crea la aventura de ejemplo con una
    /// sesión en curso y `-openPlay` abre directamente la mesa.
    private func seedForScreenshotsIfNeeded() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-seedImport") {
            // Simula importar el guion de ejemplo: guía básica al momento y después la IA.
            let adventure = Adventure(title: "Punta Negra (importada)", system: .cthulhu, script: SampleAdventure.script)
            context.insert(adventure)
            analysis.start(adventure)
            selection = adventure
            return
        }
        guard arguments.contains("-seedDemo") else { return }
        let adventure = adventures.first { $0.title == SampleAdventure.title }
            ?? SampleAdventure.make(in: context, withSession: true)
        selection = adventure
        if arguments.contains("-openPlay"), let session = adventure.sortedSessions.first {
            activeSession = session
        }
        #endif
    }
}

private struct AdventureRow: View {
    let adventure: Adventure
    @Environment(AnalysisCenter.self) private var analysis

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: adventure.system.symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(adventure.system.accent)
                .frame(width: 34, height: 34)
                .background(adventure.system.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(adventure.title).font(.body.weight(.medium)).lineLimit(2)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        if analysis.isRunning(adventure) { return "La IA está preparando la guía…" }
        guard let guide = adventure.guide else { return "\(adventure.system.shortName) · Sin analizar" }
        var parts = [adventure.system.shortName, "\(guide.scenes.count) escenas"]
        if let last = adventure.sortedSessions.first {
            parts.append("\(last.title) · \(last.lastPlayedAt.formatted(.relative(presentation: .named)))")
        }
        return parts.joined(separator: " · ")
    }
}

private struct WelcomeView: View {
    let onImport: () -> Void
    let onSample: () -> Void
    let onSettings: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 10) {
                Image(systemName: "book.pages")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(.tint)
                Text("Tu tutor de máster").font(.largeTitle.weight(.bold))
                Text("Dale el guion de tu aventura de Cthulhu o D&D. Atril lo convierte en escenas, PNJ y pistas, y te aconseja qué hacer en cada momento de la partida.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 560)
            }

            HStack(alignment: .top, spacing: 16) {
                StepCard(number: 1, title: "Importa el guion", detail: "PDF, texto o Markdown. También puedes pegarlo.")
                StepCard(number: 2, title: "Revisa la guía", detail: "Escenas, PNJ, pistas clave y desenlaces, listos para consultar.")
                StepCard(number: 3, title: "Dirige con ayuda", detail: "En mesa, pregunta al tutor o usa sus atajos de una pulsación.")
            }
            .frame(maxWidth: 760)

            HStack(spacing: 12) {
                Button(action: onImport) {
                    Label("Importar guion", systemImage: "square.and.arrow.down")
                        .frame(minWidth: 170)
                }
                .buttonStyle(.borderedProminent)
                Button(action: onSample) {
                    Label("Probar con un ejemplo", systemImage: "sparkles")
                        .frame(minWidth: 170)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)

            Button(action: onSettings) {
                Label("Tutor: \(AIBackend.current.label) · sin cuentas ni pagos", systemImage: AIBackend.current.symbol)
                    .font(.callout)
            }
            .buttonStyle(.borderless)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.canvas)
    }
}

private struct StepCard: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(number)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.tint))
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }
}
