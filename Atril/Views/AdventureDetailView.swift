import SwiftData
import SwiftUI

struct AdventureDetailView: View {
    @Bindable var adventure: Adventure
    let onPlay: (PlaySession) -> Void

    @Environment(\.modelContext) private var context
    @Environment(AnalysisCenter.self) private var analysis
    @State private var tab: Tab = .overview
    @State private var expandedScenes: Set<String> = []
    @State private var editingScript = false
    @State private var showSettings = false
    @State private var editingScene: AdventureGuide.Scene?

    enum Tab: String, CaseIterable, Identifiable {
        case overview = "Resumen"
        case plan = "Plan"
        case map = "Mapa"
        case scenes = "Escenas"
        case npcs = "PNJ"
        case clues = "Pistas"
        case script = "Guion"
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                analysisStatus
                if adventure.guide != nil || tab == .script {
                    Picker("Sección", selection: $tab) {
                        ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                content
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 940)
            .frame(maxWidth: .infinity)
        }
        .background(Color.canvas)
        #if DEBUG
        .onAppear {
            // Capturas: `-openTab plan|scenes|npcs|clues|script`.
            if let name = UserDefaults.standard.string(forKey: "openTab"),
               let match = Tab.allCases.first(where: { "\($0)" == name }) { tab = match }
        }
        #endif
        .navigationTitle(adventure.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $showSettings) { NavigationStack { SettingsView() } }
        .sheet(item: $editingScene) { scene in
            SceneEditor(scene: scene, guide: adventure.guide, isNew: adventure.guide?.scene(scene.id) == nil) { result in
                switch result {
                case .save(let edited, let coreClueIDs):
                    adventure.editGuide { guide in
                        guide.upsert(edited)
                        let inScene = Set(guide.clues(in: edited).map(\.id))
                        for index in guide.clues.indices where inScene.contains(guide.clues[index].id) {
                            guide.clues[index].isCore = coreClueIDs.contains(guide.clues[index].id)
                        }
                    }
                case .delete: adventure.editGuide { $0.removeScene(scene.id) }
                }
            }
        }
    }

    // MARK: Cabecera

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            SystemBadge(system: adventure.system)
            Text(adventure.title)
                .font(.largeTitle.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            Text(metadata).font(.subheadline).foregroundStyle(.secondary)
            if adventure.guide != nil && !adventure.isBasicGuide {
                Label(adventure.guideEngine == "sample" ? "Guía de ejemplo" : "Guía preparada con \(adventure.guideEngineLabel)",
                      systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                if let last = adventure.sortedSessions.first {
                    Button { onPlay(last) } label: {
                        Label("Continuar \(last.title)", systemImage: "play.fill").frame(minWidth: 180)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    Button { onPlay(newSession()) } label: {
                        Label("Nueva sesión", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button { onPlay(newSession()) } label: {
                        Label("Empezar a jugar", systemImage: "play.fill").frame(minWidth: 180)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                }
                Spacer()
                if !analysis.isRunning(adventure) {
                    Menu {
                        if AIBackend.current != .basic {
                            Button("Preparar la guía con \(AIBackend.current.label)", systemImage: "sparkles") { reanalyze() }
                        }
                        Button("Reorganizar sin IA", systemImage: "arrow.clockwise") { analysis.organizeBasic(adventure) }
                        if adventure.guide != nil {
                            Button("Añadir escena", systemImage: "plus") { editingScene = adventure.guide?.blankScene() }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.title3)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
            .controlSize(.large)
            .tint(adventure.system.accent)
        }
    }

    private var metadata: String {
        var parts = [adventure.system.edition, "\(adventure.wordCount.formatted()) palabras"]
        if let guide = adventure.guide {
            parts.append("\(guide.scenes.count) escenas · \(guide.npcs.count) PNJ · \(guide.clues.count) pistas")
        }
        if !adventure.sessions.isEmpty {
            parts.append(adventure.sessions.count == 1 ? "1 sesión" : "\(adventure.sessions.count) sesiones")
        }
        return parts.joined(separator: " · ")
    }

    private func newSession() -> PlaySession {
        let previous = adventure.sortedSessions.first
        let session = PlaySession(number: (adventure.sessions.map(\.number).max() ?? 0) + 1, adventure: adventure)
        // El grupo suele repetir: se copian los personajes de la sesión anterior.
        if let previous {
            session.players = previous.players
            session.currentSceneID = previous.currentSceneID ?? session.currentSceneID
            session.visitedSceneIDs = previous.visitedSceneIDs
            session.foundClueIDs = previous.foundClueIDs
            // «Previamente…» para empezar: el resumen que se preparó al cerrar, o uno básico.
            session.recap = previous.playerSummary ?? Recap.basic(Recap.Facts(
                title: adventure.title, system: adventure.system, guide: adventure.guide, notes: previous.notes,
                visitedSceneIDs: previous.visitedSceneIDs, foundClueIDs: Set(previous.foundClueIDs),
                currentSceneID: previous.currentSceneID, players: previous.players
            )).forPlayers
        }
        context.insert(session)
        return session
    }

    private func reanalyze() {
        analysis.start(adventure)
    }

    // MARK: Estado del análisis

    @ViewBuilder
    private var analysisStatus: some View {
        if let job = analysis.job(for: adventure) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: job.backend.symbol).foregroundStyle(adventure.system.accent)
                    Text("\(job.backend.label) está preparando la guía").font(.headline)
                    Spacer()
                    Button("Cancelar") { analysis.cancel(adventure) }.buttonStyle(.bordered).controlSize(.small)
                }
                if let fraction = job.fraction {
                    ProgressView(value: fraction).tint(adventure.system.accent)
                } else {
                    ProgressView().frame(maxWidth: .infinity, alignment: .leading)
                }
                TimelineView(.periodic(from: job.startedAt, by: 1)) { context in
                    Text("\(job.phase) · \(Format.clock(context.date.timeIntervalSince(job.startedAt)))")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text("Mientras tanto puedes usar la guía básica; se sustituirá sola cuando termine.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .card()
        } else if let error = analysis.error(for: adventure) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 8) {
                    Text("La IA no ha podido terminar la guía").font(.headline)
                    Text("\(error) Tienes la guía básica disponible.").font(.callout).foregroundStyle(.secondary)
                    Button("Reintentar") { reanalyze() }.buttonStyle(.bordered)
                }
            }
            .card()
        } else if adventure.guide == nil {
            VStack(alignment: .leading, spacing: 10) {
                Label("Este guion aún no está organizado", systemImage: "sparkles").font(.headline)
                Text("Atril lo convierte en escenas con texto para leer en voz alta, PNJ, pistas clave, tiradas y consejos de dirección.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Organizar guion", systemImage: "sparkles") { reanalyze() }
                    .buttonStyle(.borderedProminent)
                    .tint(adventure.system.accent)
            }
            .card()
        } else if adventure.isGuideStale {
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.orange)
                Text("Has editado el guion desde que se preparó la guía.").font(.callout)
                Spacer()
                Button("Actualizar guía") { reanalyze() }.buttonStyle(.bordered)
            }
            .card(padding: 12)
        } else if adventure.isBasicGuide {
            let backend = AIBackend.current
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "wand.and.stars").foregroundStyle(adventure.system.accent)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Guía organizada sin IA").font(.callout.weight(.semibold))
                    Text(backend == .basic
                         ? "Se ha hecho leyendo la estructura del guion. Revisa las escenas y edítalas si hace falta. \(AppleAI.status.unavailableReason ?? "")"
                         : "Se ha hecho leyendo la estructura del guion. La \(backend.label) puede leerlo entero y mejorarla.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if backend != .basic {
                    Button("Mejorar con IA", systemImage: "sparkles") { reanalyze() }
                        .buttonStyle(.borderedProminent)
                        .tint(adventure.system.accent)
                }
            }
            .card(padding: 14)
        }
    }

    // MARK: Contenido

    @ViewBuilder
    private var content: some View {
        if let guide = adventure.guide, tab != .script {
            switch tab {
            case .overview: overview(guide)
            case .plan: PlanView(adventure: adventure, guide: guide)
            case .map:
                VStack(alignment: .leading, spacing: 10) {
                    AdventureMap(guide: guide, tint: adventure.system.accent, axes: .horizontal) { scene in
                        expandedScenes.insert(scene.id)
                        tab = .scenes
                    }
                    .card(padding: 0)
                    Text("Toca una escena para ver su ficha. Las flechas discontinuas son vueltas atrás.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .scenes: scenes(guide)
            case .npcs: npcs(guide)
            case .clues: clues(guide)
            case .script: EmptyView()
            }
        } else {
            scriptView
        }
    }

    private func overview(_ guide: AdventureGuide) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            textCard("La premisa", guide.premise, symbol: "book")
            textCard("La verdad · solo para el máster", guide.truth, symbol: "eye.slash", tint: .purple)
            HStack(alignment: .top, spacing: 14) {
                textCard("Cómo empezar", guide.hook, symbol: "flag")
                textCard("Tono", guide.tone, symbol: "theatermasks")
            }
            if !guide.prep.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(title: "Antes de jugar", symbol: "checklist")
                    ForEach(guide.prep, id: \.self) { item in
                        let done = adventure.prepDone.contains(item)
                        Button {
                            if done { adventure.prepDone.removeAll { $0 == item } } else { adventure.prepDone.append(item) }
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Image(systemName: done ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(done ? adventure.system.accent : .secondary)
                                Text(item)
                                    .strikethrough(done, color: .secondary)
                                    .foregroundStyle(done ? .secondary : .primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .card()
            }
            if !guide.endings.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Desenlaces", symbol: "flag.checkered")
                    ForEach(guide.endings, id: \.self) { ending in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(ending.title).font(.callout.weight(.semibold))
                            Text(ending.condition).font(.callout).foregroundStyle(.secondary)
                            Text(ending.outcome).font(.callout)
                        }
                    }
                }
                .card()
            }
        }
    }

    private func textCard(_ title: String, _ text: String, symbol: String, tint: Color = .secondary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title: title, symbol: symbol, tint: tint)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }

    private func scenes(_ guide: AdventureGuide) -> some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            ForEach(Array(guide.scenes.enumerated()), id: \.element.id) { index, scene in
                if !scene.act.isEmpty, index == 0 || guide.scenes[index - 1].act != scene.act {
                    Text(scene.act).font(.title3.weight(.semibold)).padding(.top, index == 0 ? 0 : 12)
                }
                let expanded = expandedScenes.contains(scene.id)
                VStack(alignment: .leading, spacing: 14) {
                    Button {
                        withAnimation(.snappy) {
                            if expanded { expandedScenes.remove(scene.id) } else { expandedScenes.insert(scene.id) }
                        }
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.callout.weight(.bold).monospacedDigit())
                                .foregroundStyle(adventure.system.accent)
                                .frame(width: 28, height: 28)
                                .background(adventure.system.accent.opacity(0.12), in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(scene.title).font(.headline)
                                if !scene.place.isEmpty {
                                    Text(scene.place).font(.subheadline).foregroundStyle(.secondary)
                                }
                                if !expanded {
                                    Text(scene.summary).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.down")
                                .rotationEffect(.degrees(expanded ? 180 : 0))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if expanded {
                        SceneContent(scene: scene, guide: guide, system: adventure.system)
                            .padding(.leading, 40)
                        HStack(spacing: 8) {
                            Button("Editar", systemImage: "pencil") { editingScene = scene }
                            Button("Subir", systemImage: "arrow.up") { adventure.editGuide { $0.moveScene(scene.id, by: -1) } }
                                .disabled(index == 0)
                            Button("Bajar", systemImage: "arrow.down") { adventure.editGuide { $0.moveScene(scene.id, by: 1) } }
                                .disabled(index == guide.scenes.count - 1)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .padding(.leading, 40)
                    }
                }
                .card()
            }
            Button {
                editingScene = guide.blankScene()
            } label: {
                Label("Añadir escena", systemImage: "plus").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private func npcs(_ guide: AdventureGuide) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14, alignment: .top)], spacing: 14) {
            ForEach(guide.npcs) { NPCCard(npc: $0) }
        }
    }

    private func clues(_ guide: AdventureGuide) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(guide.scenes) { scene in
                let sceneClues = guide.clues.filter { $0.sceneID == scene.id }
                if !sceneClues.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(title: scene.title, symbol: "mappin.and.ellipse")
                        ForEach(sceneClues) { ClueRow(clue: $0, guide: guide) }
                    }
                    .card()
                }
            }
            let orphans = guide.clues.filter { guide.scene($0.sceneID) == nil }
            if !orphans.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Otras pistas", symbol: "magnifyingglass")
                    ForEach(orphans) { ClueRow(clue: $0, guide: guide) }
                }
                .card()
            }
        }
    }

    private var scriptView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(title: adventure.sourceFileName ?? "Guion", symbol: "doc.text")
                Spacer()
                Button(editingScript ? "Listo" : "Editar") {
                    if editingScript { adventure.updatedAt = .now }
                    editingScript.toggle()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            if editingScript {
                TextEditor(text: $adventure.script)
                    .font(.system(.body, design: .serif))
                    .frame(minHeight: 500)
                    .scrollContentBackground(.hidden)
            } else {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(adventure.script.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph)
                            .font(.system(.body, design: .serif))
                            .lineSpacing(3)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .card(padding: 20)
    }
}
