import SwiftUI

/// Búsqueda en toda la aventura: escenas, PNJ, pistas y el texto del guion.
enum GuideSearch {
    struct Results {
        var scenes: [AdventureGuide.Scene] = []
        var npcs: [AdventureGuide.NPC] = []
        var clues: [AdventureGuide.Clue] = []
        var passages: [ScriptIndex.Passage] = []

        var isEmpty: Bool { scenes.isEmpty && npcs.isEmpty && clues.isEmpty && passages.isEmpty }
    }

    /// Coinciden los elementos que contienen todas las palabras de la búsqueda, sin tener en
    /// cuenta tildes ni mayúsculas. El guion se busca por relevancia.
    static func search(_ query: String, guide: AdventureGuide?, index: ScriptIndex) -> Results {
        Catalog(guide: guide).search(query, index: index)
    }

    /// El texto de cada escena, PNJ y pista ya plegado, preparado una vez al abrir la búsqueda:
    /// así cada tecla solo compara textos.
    struct Catalog {
        let guide: AdventureGuide?
        private let scenes: [String]
        private let npcs: [String]
        private let clues: [String]

        init(guide: AdventureGuide?) {
            self.guide = guide
            func text(_ fields: [String]) -> String { Prose.fold(fields.joined(separator: " ")) }
            scenes = guide?.scenes.map {
                text([$0.title, $0.place, $0.summary, $0.readAloud, $0.danger, $0.ifStuck] + $0.goals + $0.tips + $0.checks.map(\.skill))
            } ?? []
            npcs = guide?.npcs.map { text([$0.name, $0.role, $0.look, $0.motivation, $0.secret, $0.voice]) } ?? []
            clues = guide?.clues.map { text([$0.title, $0.detail, $0.leadsTo]) } ?? []
        }

        func search(_ query: String, index: ScriptIndex) -> Results {
            let words = Prose.words(query).filter { $0.count > 1 }
            guard !words.isEmpty else { return Results() }
            func matching<Item>(_ items: [Item], _ texts: [String]) -> [Item] {
                zip(items, texts).filter { _, text in words.allSatisfy { text.containsBytes($0) } }.map(\.0)
            }
            var results = Results()
            if let guide {
                results.scenes = matching(guide.scenes, scenes)
                results.npcs = matching(guide.npcs, npcs)
                results.clues = matching(guide.clues, clues)
            }
            results.passages = index.search(query, limit: 6)
            return results
        }
    }
}

struct GuideSearchView: View {
    let guide: AdventureGuide?
    let index: ScriptIndex
    let tint: Color
    let onScene: (AdventureGuide.Scene) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    /// Se prepara al aparecer (no en `init`, que se repite con cada repintado de quien la abre).
    @State private var catalog: GuideSearch.Catalog?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            let results = (catalog ?? GuideSearch.Catalog(guide: guide)).search(query, index: index)
            List {
                if query.trimmed.isEmpty {
                    Text("Busca un nombre, un lugar, una pista o cualquier palabra del guion.")
                        .foregroundStyle(.secondary)
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
                if !results.scenes.isEmpty, let guide {
                    Section("Escenas") {
                        ForEach(results.scenes) { scene in
                            Button {
                                onScene(scene)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\((guide.scenes.firstIndex { $0.id == scene.id } ?? 0) + 1). \(scene.title)").font(.headline)
                                    Text(scene.summary).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if !results.npcs.isEmpty {
                    Section("PNJ") {
                        ForEach(results.npcs) { npc in
                            DisclosureGroup {
                                NPCCard(npc: npc, framed: false).padding(.vertical, 6)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(npc.name).font(.headline)
                                    Text(npc.role).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                        }
                    }
                }
                if !results.clues.isEmpty, let guide {
                    Section("Pistas") {
                        ForEach(results.clues) { clue in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(clue.title).font(.headline)
                                    if clue.isCore { Image(systemName: "star.fill").font(.caption).foregroundStyle(.orange) }
                                }
                                Text(clue.detail).font(.callout).foregroundStyle(.secondary)
                                if let scene = guide.scene(clue.sceneID) {
                                    Label(scene.title, systemImage: "mappin.and.ellipse").font(.caption).foregroundStyle(tint)
                                }
                            }
                        }
                    }
                }
                if !results.passages.isEmpty {
                    Section("En el guion") {
                        ForEach(results.passages) { passage in
                            DisclosureGroup {
                                Text(passage.text)
                                    .font(.system(.callout, design: .serif))
                                    .textSelection(.enabled)
                                    .padding(.vertical, 4)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    if !passage.heading.isEmpty {
                                        Text(passage.heading).font(.caption.weight(.semibold)).foregroundStyle(tint)
                                    }
                                    Text(passage.text).font(.callout).lineLimit(2)
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .toolbar, prompt: "Buscar en la aventura")
            .searchFocused($focused)
            .navigationTitle("Buscar")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } }
            }
            .onAppear {
                if catalog == nil { catalog = GuideSearch.Catalog(guide: guide) }
                focused = true
                #if DEBUG
                // Capturas: `-searchQuery "texto"` entra ya buscando.
                if let text = UserDefaults.standard.string(forKey: "searchQuery") { query = text }
                #endif
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 600)
        #endif
    }
}
