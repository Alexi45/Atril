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
    }
}

struct SceneEditor: View {
    enum Result { case save(AdventureGuide.Scene, coreClueIDs: Set<String>), delete }

    @State private var scene: AdventureGuide.Scene
    @State private var goals: String
    @State private var tips: String
    @State private var coreClueIDs: Set<String>
    @State private var confirmDelete = false
    let guide: AdventureGuide?
    let isNew: Bool
    let onFinish: (Result) -> Void
    @Environment(\.dismiss) private var dismiss

    init(scene: AdventureGuide.Scene, guide: AdventureGuide?, isNew: Bool, onFinish: @escaping (Result) -> Void) {
        _scene = State(initialValue: scene)
        _goals = State(initialValue: scene.goals.joined(separator: "\n"))
        _tips = State(initialValue: scene.tips.joined(separator: "\n"))
        _coreClueIDs = State(initialValue: Set((guide.map { $0.clues(in: scene) } ?? []).filter(\.isCore).map(\.id)))
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
                if let guide, !guide.clues(in: scene).isEmpty {
                    Section {
                        ForEach(guide.clues(in: scene)) { clue in
                            Toggle(isOn: Binding(
                                get: { coreClueIDs.contains(clue.id) },
                                set: { on in if on { coreClueIDs.insert(clue.id) } else { coreClueIDs.remove(clue.id) } }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(clue.title)
                                    Text(clue.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                        }
                    } header: {
                        Text("Pistas · marca las clave")
                    } footer: {
                        Text("Las pistas clave son las imprescindibles para terminar la aventura: el tutor te avisa si se quedan atrás.")
                    }
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
                        onFinish(.save(scene, coreClueIDs: coreClueIDs))
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
            }
            .card()

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
