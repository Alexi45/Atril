import SwiftUI

extension AdventureGuide {
    func blankScene() -> Scene {
        let next = (scenes.compactMap { Int($0.id.dropFirst()) }.max() ?? 0) + 1
        return Scene(id: "e\(next)", act: scenes.last?.act ?? "", title: "", place: "", summary: "", readAloud: "",
                     goals: [], clueIDs: [], npcIDs: [], checks: [], tips: [], danger: "", ifStuck: "", exits: [])
    }

    /// Añade la escena al final o sustituye la que tenga el mismo id.
    mutating func upsert(_ scene: Scene) {
        if let index = scenes.firstIndex(where: { $0.id == scene.id }) {
            scenes[index] = scene
        } else {
            if let last = scenes.indices.last, scenes[last].exits.isEmpty {
                scenes[last].exits = [Exit(sceneID: scene.id, condition: "Cuando terminen esta escena")]
            }
            scenes.append(scene)
        }
    }

    mutating func removeScene(_ id: String) {
        scenes.removeAll { $0.id == id }
        for index in scenes.indices { scenes[index].exits.removeAll { $0.sceneID == id } }
        for index in clues.indices where clues[index].sceneID == id { clues[index].sceneID = "" }
    }

    /// Sustituye las pistas de una escena por las editadas.
    mutating func setClues(_ edited: [Clue], forScene id: String) {
        guard let index = scenes.firstIndex(where: { $0.id == id }) else { return }
        let previous = Set(clues(in: scenes[index]).map(\.id))
        let kept = Set(edited.map(\.id))
        clues.removeAll { previous.contains($0.id) && !kept.contains($0.id) }
        for clue in edited {
            if let position = clues.firstIndex(where: { $0.id == clue.id }) {
                clues[position] = clue
            } else {
                clues.append(clue)
            }
        }
        scenes[index].clueIDs = edited.map(\.id)
    }

    func nextClueID(excluding others: [Clue] = []) -> String {
        let numbers = (clues + others).compactMap { Int($0.id.dropFirst()) }
        return "p\((numbers.max() ?? 0) + 1)"
    }

    func blankNPC() -> NPC {
        let next = (npcs.compactMap { Int($0.id.dropFirst()) }.max() ?? 0) + 1
        return NPC(id: "n\(next)", name: "", role: "", look: "", motivation: "", secret: "", voice: "", stats: "")
    }

    mutating func upsert(_ npc: NPC) {
        if let index = npcs.firstIndex(where: { $0.id == npc.id }) {
            npcs[index] = npc
        } else {
            npcs.append(npc)
        }
    }

    mutating func removeNPC(_ id: String) {
        npcs.removeAll { $0.id == id }
        for index in scenes.indices { scenes[index].npcIDs.removeAll { $0 == id } }
    }

    mutating func moveScene(_ id: String, by offset: Int) {
        guard let index = scenes.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard scenes.indices.contains(target) else { return }
        scenes.swapAt(index, target)
    }
}

extension Adventure {
    /// Edita la guía a mano sin perder de qué motor salió.
    func editGuide(_ change: (inout AdventureGuide) -> Void) {
        guard var value = guide else { return }
        let engine = guideEngine
        change(&value)
        guide = value
        guideEngine = engine
        guideEditedAt = .now
    }
}

struct SceneEditor: View {
    enum Result { case save(AdventureGuide.Scene, clues: [AdventureGuide.Clue]), delete }

    @State private var scene: AdventureGuide.Scene
    @State private var goals: String
    @State private var tips: String
    @State private var clues: [AdventureGuide.Clue]
    @State private var confirmDelete = false
    let guide: AdventureGuide?
    let isNew: Bool
    let onFinish: (Result) -> Void
    @Environment(\.dismiss) private var dismiss

    init(scene: AdventureGuide.Scene, guide: AdventureGuide?, isNew: Bool, onFinish: @escaping (Result) -> Void) {
        _scene = State(initialValue: scene)
        _goals = State(initialValue: scene.goals.joined(separator: "\n"))
        _tips = State(initialValue: scene.tips.joined(separator: "\n"))
        _clues = State(initialValue: guide.map { $0.clues(in: scene) } ?? [])
        self.guide = guide
        self.isNew = isNew
        self.onFinish = onFinish
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Escena") {
                    TextField("Título", text: $scene.title)
                    TextField("Lugar", text: $scene.place)
                    TextField("Acto o parte (opcional)", text: $scene.act)
                }
                Section("Qué pasa") {
                    editor($scene.summary, placeholder: "Lo que ocurre, explicado para ti")
                }
                Section("Lee en voz alta") {
                    editor($scene.readAloud, placeholder: "Texto para leer a los jugadores")
                }
                Section {
                    editor($goals, placeholder: "Un objetivo por línea")
                } header: {
                    Text("Qué deben conseguir")
                }
                Section {
                    editor($tips, placeholder: "Un consejo por línea")
                } header: {
                    Text("Consejos para dirigirla")
                }
                Section("Si se atascan") {
                    editor($scene.ifStuck, placeholder: "Cómo reconducirlos sin tirada")
                }
                Section("Peligro") {
                    editor($scene.danger, placeholder: "Combates, pérdidas de Cordura o PV")
                }
                Section {
                    ForEach($clues) { $clue in
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Nombre de la pista", text: $clue.title).font(.body.weight(.medium))
                            TextField("Qué revela", text: $clue.detail, axis: .vertical).font(.callout).lineLimit(1...5)
                            HStack {
                                Toggle("Clave", isOn: $clue.isCore).fixedSize()
                                Spacer()
                                Button("Quitar", role: .destructive) {
                                    let id = clue.id
                                    clues.removeAll { $0.id == id }
                                }
                                .buttonStyle(.borderless)
                            }
                            .font(.callout)
                        }
                        .padding(.vertical, 2)
                    }
                    Button("Añadir pista", systemImage: "plus") {
                        let id = guide?.nextClueID(excluding: clues) ?? "p\(clues.count + 1)"
                        clues.append(AdventureGuide.Clue(id: id, title: "", detail: "", sceneID: scene.id, leadsTo: "", isCore: false))
                    }
                } header: {
                    Text("Pistas")
                } footer: {
                    Text("Las clave son las imprescindibles para terminar la aventura: el tutor te avisa si se quedan atrás.")
                }
                if let guide, !guide.npcs.isEmpty {
                    Section("PNJ en escena") {
                        ForEach(guide.npcs) { npc in
                            Toggle(npc.name, isOn: Binding(
                                get: { scene.npcIDs.contains(npc.id) },
                                set: { on in
                                    if on { scene.npcIDs.append(npc.id) } else { scene.npcIDs.removeAll { $0 == npc.id } }
                                }
                            ))
                        }
                    }
                }
                if !isNew {
                    Section {
                        Button("Eliminar escena", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isNew ? "Nueva escena" : "Editar escena")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        scene.goals = goals.components(separatedBy: "\n").cleaned
                        scene.tips = tips.components(separatedBy: "\n").cleaned
                        onFinish(.save(scene, clues: clues.filter { !$0.title.trimmed.isEmpty }))
                        dismiss()
                    }
                    .disabled(scene.title.trimmed.isEmpty)
                }
            }
            .confirmationDialog("¿Eliminar «\(scene.title)»?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Eliminar escena", role: .destructive) {
                    onFinish(.delete)
                    dismiss()
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 640)
        #endif
    }

    private func editor(_ text: Binding<String>, placeholder: String) -> some View {
        TextField(placeholder, text: text, axis: .vertical)
            .lineLimit(2...10)
    }
}

/// Reparto de la aventura en sesiones según la duración prevista de cada escena.
struct PlanView: View {
    @Bindable var adventure: Adventure
    let guide: AdventureGuide
    @State private var showPrepSheet = false

    var body: some View {
        let plan = SessionPlanner.plan(guide, hours: adventure.sessionHours)
        let total = SessionPlanner.totalMinutes(guide)
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Duración estimada: \(Format.duration(TimeInterval(total * 60)))").font(.headline)
                        Text(plan.count == 1 ? "Cabe en una sesión" : "\(plan.count) sesiones")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Stepper(value: $adventure.sessionHours, in: 1.5...6, step: 0.5) {
                        Text("\(adventure.sessionHours.formatted(.number.precision(.fractionLength(0...1)))) h por sesión")
                            .font(.callout.monospacedDigit())
                    }
                    .fixedSize()
                }
                Text("Cada escena se estima por sus tiradas, pistas, PNJ y peligros. En mesa, el tutor te avisa si una escena se alarga o si se acerca el final de la sesión.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    showPrepSheet = true
                } label: {
                    Label("Hoja de preparación para imprimir", systemImage: "doc.richtext")
                }
                .buttonStyle(.bordered)
                .tint(adventure.system.accent)
            }
            .card()
            .sheet(isPresented: $showPrepSheet) { PrepSheetView(adventure: adventure, guide: guide) }

            ForEach(plan) { session in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        SectionLabel(title: "Sesión \(session.number)", symbol: "calendar", tint: adventure.system.accent)
                        Spacer()
                        Text("~\(Format.duration(TimeInterval(session.minutes * 60)))")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    ForEach(session.sceneIDs, id: \.self) { id in
                        if let scene = guide.scene(id) {
                            HStack(spacing: 10) {
                                Text("\((guide.scenes.firstIndex { $0.id == id } ?? 0) + 1)")
                                    .font(.caption.weight(.bold).monospacedDigit())
                                    .foregroundStyle(adventure.system.accent)
                                    .frame(width: 22, height: 22)
                                    .background(adventure.system.accent.opacity(0.12), in: Circle())
                                Text(scene.title).font(.callout)
                                Spacer()
                                Text("\(SessionPlanner.minutes(for: scene)) min")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let last = session.sceneIDs.last.flatMap(guide.scene), session.number < plan.count {
                        Label {
                            Text("Termina la sesión al acabar «\(last.title)»\(last.exits.first.map { ": \($0.condition.lowercasedFirst)" } ?? ""). Deja una pregunta abierta para la siguiente.")
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "flag.checkered")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                    }
                }
                .card()
            }
        }
    }
}

/// Corregir o crear un PNJ: la IA acierta mucho, pero no siempre.
struct NPCEditor: View {
    enum Result { case save(AdventureGuide.NPC), delete }

    @State private var npc: AdventureGuide.NPC
    @State private var confirmDelete = false
    let isNew: Bool
    let onFinish: (Result) -> Void
    @Environment(\.dismiss) private var dismiss

    init(npc: AdventureGuide.NPC, isNew: Bool, onFinish: @escaping (Result) -> Void) {
        _npc = State(initialValue: npc)
        self.isNew = isNew
        self.onFinish = onFinish
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Personaje") {
                    TextField("Nombre", text: $npc.name)
                    TextField("Papel en la historia", text: $npc.role, axis: .vertical).lineLimit(1...3)
                }
                Section("Para interpretarlo") {
                    TextField("Aspecto", text: $npc.look, axis: .vertical).lineLimit(1...4)
                    TextField("Qué quiere", text: $npc.motivation, axis: .vertical).lineLimit(1...4)
                    TextField("Voz, gestos, forma de hablar", text: $npc.voice, axis: .vertical).lineLimit(1...4)
                }
                Section {
                    TextField("Qué oculta", text: $npc.secret, axis: .vertical).lineLimit(1...4)
                } header: {
                    Text("Solo para el máster")
                }
                Section {
                    TextField("FUE 50, DES 60, PV 12…", text: $npc.stats, axis: .vertical).lineLimit(1...4)
                } header: {
                    Text("Estadísticas")
                } footer: {
                    Text("Si incluyes los PV (y la DES o CA), podrás añadirlo al combate de un toque.")
                }
                if !isNew {
                    Section {
                        Button("Eliminar PNJ", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isNew ? "Nuevo PNJ" : "Editar PNJ")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        onFinish(.save(npc))
                        dismiss()
                    }
                    .disabled(npc.name.trimmed.isEmpty)
                }
            }
            .confirmationDialog("¿Eliminar a «\(npc.name)»?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Eliminar PNJ", role: .destructive) {
                    onFinish(.delete)
                    dismiss()
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 560)
        #endif
    }
}
