import Foundation

/// Borradores que produce cualquier motor (IA de Apple o heurístico) al leer un trozo del guion.
/// `GuideMerger` los une en una `AdventureGuide` con ids y referencias cruzadas coherentes.
struct DraftChunk: Hashable {
    var summary = ""
    var scenes: [DraftScene] = []
    var characters: [DraftCharacter] = []
    /// Encabezado de parte o acto bajo el que cae el trozo, si lo hay.
    var act = ""
}

struct DraftScene: Hashable {
    var title: String
    var place = ""
    var summary = ""
    var readAloud = ""
    var goals: [String] = []
    var checks: [AdventureGuide.Check] = []
    var clues: [DraftClue] = []
    var danger = ""
    var tips: [String] = []
    var ifStuck = ""
    var characterNames: [String] = []
    var act = ""
}

struct DraftClue: Hashable {
    var title: String
    var detail = ""
    var leadsTo = ""
    var isCore = false
}

struct DraftCharacter: Hashable {
    var name: String
    var role = ""
    var look = ""
    var motivation = ""
    var secret = ""
    var voice = ""
    var stats = ""
}

struct DraftOverview: Hashable {
    var premise = ""
    var truth = ""
    var hook = ""
    var tone = ""
    var prep: [String] = []
    var endings: [AdventureGuide.Ending] = []
    /// Títulos de las pistas imprescindibles.
    var coreClues: [String] = []
}

struct DraftLink: Hashable {
    var from: String
    var to: String
    var condition: String
}

enum GuideMerger {
    static func merge(
        chunks: [DraftChunk],
        overview: DraftOverview,
        links: [DraftLink] = [],
        system: GameSystem
    ) -> AdventureGuide {
        // 1. Escenas en orden, uniendo las que se parten entre dos trozos.
        var scenes: [DraftScene] = []
        for chunk in chunks {
            for var scene in chunk.scenes where !scene.title.trimmed.isEmpty {
                if scene.act.isEmpty { scene.act = chunk.act }
                if let last = scenes.last, Prose.matches(last.title, scene.title) {
                    scenes[scenes.count - 1] = combine(last, scene)
                } else {
                    scenes.append(scene)
                }
            }
        }

        // 2. PNJ sin duplicados (mismo nombre con o sin tratamiento: «don Ramiro» = «Ramiro»).
        var characters: [DraftCharacter] = []
        for character in chunks.flatMap(\.characters) where !character.name.trimmed.isEmpty {
            if let index = characters.firstIndex(where: { Prose.sameName($0.name, character.name) }) {
                characters[index] = combine(characters[index], character)
            } else {
                characters.append(character)
            }
        }
        // PNJ citados en escenas pero no descritos en ningún trozo.
        for name in scenes.flatMap(\.characterNames) where !name.trimmed.isEmpty {
            if !characters.contains(where: { Prose.sameName($0.name, name) }) {
                characters.append(DraftCharacter(name: name.trimmed))
            }
        }
        let npcs = characters.enumerated().map { index, draft in
            AdventureGuide.NPC(
                id: "n\(index + 1)", name: draft.name.trimmed, role: draft.role.trimmed, look: draft.look.trimmed,
                motivation: draft.motivation.trimmed, secret: draft.secret.trimmed, voice: draft.voice.trimmed,
                stats: draft.stats.trimmed
            )
        }

        // 3. Pistas, con la escena donde aparecen.
        var clues: [AdventureGuide.Clue] = []
        var sceneClueIDs: [[String]] = Array(repeating: [], count: scenes.count)
        for (sceneIndex, scene) in scenes.enumerated() {
            for draft in scene.clues where !draft.title.trimmed.isEmpty {
                if let existing = clues.first(where: { Prose.matches($0.title, draft.title) }) {
                    if !sceneClueIDs[sceneIndex].contains(existing.id) { sceneClueIDs[sceneIndex].append(existing.id) }
                    continue
                }
                let id = "p\(clues.count + 1)"
                let isCore = draft.isCore || overview.coreClues.contains { Prose.matches(Prose.cleanLabel($0), draft.title) }
                clues.append(AdventureGuide.Clue(
                    id: id, title: Prose.cleanLabel(draft.title), detail: draft.detail.trimmed, sceneID: "e\(sceneIndex + 1)",
                    leadsTo: draft.leadsTo.trimmed, isCore: isCore
                ))
                sceneClueIDs[sceneIndex].append(id)
            }
        }

        // 4. Conexiones: las que proponga el motor o, si no hay, el orden del guion.
        func sceneIndex(_ title: String) -> Int? { scenes.firstIndex { Prose.matches($0.title, title) } }
        var exits: [[AdventureGuide.Exit]] = Array(repeating: [], count: scenes.count)
        for link in links {
            guard let from = sceneIndex(link.from), let to = sceneIndex(link.to), from != to else { continue }
            let id = "e\(to + 1)"
            if !exits[from].contains(where: { $0.sceneID == id }) {
                exits[from].append(AdventureGuide.Exit(sceneID: id, condition: link.condition.trimmed))
            }
        }
        for index in scenes.indices where exits[index].isEmpty && index < scenes.count - 1 {
            exits[index] = [AdventureGuide.Exit(sceneID: "e\(index + 2)", condition: "Cuando terminen esta escena")]
        }

        let guideScenes = scenes.enumerated().map { index, draft in
            AdventureGuide.Scene(
                id: "e\(index + 1)", act: draft.act.trimmed, title: draft.title.trimmed, place: draft.place.trimmed,
                summary: draft.summary.trimmed, readAloud: draft.readAloud.trimmed,
                goals: draft.goals.cleaned, clueIDs: sceneClueIDs[index],
                npcIDs: draft.characterNames.compactMap { name in npcs.first { Prose.sameName($0.name, name) }?.id }.uniqued,
                checks: draft.checks.filter { !$0.skill.trimmed.isEmpty },
                tips: draft.tips.cleaned, danger: draft.danger.trimmed, ifStuck: draft.ifStuck.trimmed,
                exits: exits[index]
            )
        }

        return AdventureGuide(
            premise: overview.premise.trimmed,
            truth: overview.truth.trimmed,
            hook: overview.hook.trimmed,
            tone: overview.tone.trimmed.isEmpty ? Self.defaultTone(system) : overview.tone.trimmed,
            prep: overview.prep.cleaned,
            scenes: guideScenes,
            npcs: npcs,
            clues: clues,
            endings: overview.endings.filter { !$0.title.trimmed.isEmpty }
        )
    }

    static func defaultTone(_ system: GameSystem) -> String {
        switch system {
        case .cthulhu: "Horror investigativo: dosifica la información, describe con los cinco sentidos y deja que el miedo venga de lo que no se ve."
        case .dnd: "Aventura heroica: alterna combate, exploración e interacción, y premia las ideas creativas de los jugadores."
        case .other: "Adapta el tono a lo que pida el guion y a lo que disfrute tu mesa."
        }
    }

    private static func combine(_ a: DraftScene, _ b: DraftScene) -> DraftScene {
        var merged = a
        merged.place = a.place.longer(b.place)
        merged.summary = Prose.join(a.summary, b.summary)
        merged.readAloud = a.readAloud.longer(b.readAloud)
        merged.goals = (a.goals + b.goals).uniqued
        merged.checks = (a.checks + b.checks).uniqued
        merged.clues = a.clues + b.clues.filter { clue in !a.clues.contains { Prose.matches($0.title, clue.title) } }
        merged.danger = Prose.join(a.danger, b.danger)
        merged.tips = (a.tips + b.tips).uniqued
        merged.ifStuck = a.ifStuck.longer(b.ifStuck)
        merged.characterNames = (a.characterNames + b.characterNames).uniqued
        return merged
    }

    private static func combine(_ a: DraftCharacter, _ b: DraftCharacter) -> DraftCharacter {
        DraftCharacter(
            name: a.name.longer(b.name), role: a.role.longer(b.role), look: a.look.longer(b.look),
            motivation: a.motivation.longer(b.motivation), secret: Prose.join(a.secret, b.secret),
            voice: a.voice.longer(b.voice), stats: a.stats.longer(b.stats)
        )
    }
}

// MARK: - Utilidades de texto

enum Prose {
    private static let honorifics: Set<String> = [
        "don", "dona", "el", "la", "los", "las", "senor", "senora", "senorita", "sr", "sra", "srta",
        "padre", "madre", "hermano", "hermana", "doctor", "doctora", "dr", "dra", "profesor", "profesora",
        "capitan", "sargento", "inspector", "inspectora", "lord", "lady", "sir", "fray", "sor", "tio", "tia",
    ]

    /// Minúsculas, sin acentos ni signos.
    static func fold(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es"))
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func words(_ value: String) -> [String] { fold(value).split(separator: " ").map(String.init) }

    static func matches(_ a: String, _ b: String) -> Bool {
        let x = fold(a), y = fold(b)
        guard !x.isEmpty, !y.isEmpty else { return false }
        if x == y { return true }
        let shorter = x.count < y.count ? x : y
        let longer = x.count < y.count ? y : x
        return shorter.count >= 8 && longer.contains(shorter)
    }

    /// Mismo personaje: igual nombre sin tratamientos, o uno contiene al otro como palabras completas.
    static func sameName(_ a: String, _ b: String) -> Bool {
        let x = words(a).filter { !honorifics.contains($0) }
        let y = words(b).filter { !honorifics.contains($0) }
        guard !x.isEmpty, !y.isEmpty else { return false }
        if x == y { return true }
        let (shorter, longer) = x.count <= y.count ? (x, y) : (y, x)
        return shorter.allSatisfy(longer.contains) && shorter.joined().count >= 4
    }

    /// Quita adornos de Markdown y comillas que el modelo pone a veces en títulos y nombres.
    static func cleanLabel(_ value: String) -> String {
        value.trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "#*-•\"'«»“”[]").union(.whitespaces)).trimmed
    }

    /// Frases del texto que nombran a alguien, para darle al modelo solo lo que le concierne.
    static func sentences(mentioning name: String, in text: String, limit: Int) -> [String] {
        let keys = words(name).filter { $0.count > 3 }
        guard !keys.isEmpty else { return [] }
        return Array(sentences(text).filter { sentence in
            let folded = fold(sentence)
            return keys.contains { folded.contains($0) }
        }.prefix(limit))
    }

    /// Valores de relleno: el modelo pequeño a veces devuelve la descripción del campo
    /// («Qué quiere, en pocas palabras») o un «vacío» literal en lugar de dejarlo en blanco.
    static func isPlaceholder(_ value: String) -> Bool {
        let text = fold(value)
        if ["", "vacio", "nada", "ninguno", "ninguna", "no", "no aplica", "n a", "no oculta nada", "no hay",
            "no se indica", "desconocido", "sin datos", "nada oculto", "no se revela", "no se menciona", "no se menciona nada"].contains(text) { return true }
        let echoes = ["en pocas palabras", "vacio si", "en una frase", "que quiere", "lo que oculta",
                      "como interpretarlo", "aspecto y primera impresion", "papel en la historia", "abreviadas"]
        return echoes.contains { text.contains($0) } || isSchemaJunk(value)
    }

    /// Texto del modelo si es útil; si no, cadena vacía.
    static func useful(_ value: String) -> String { isPlaceholder(value) ? "" : value.trimmed }

    /// El modelo local a veces devuelve fragmentos del esquema en lugar de texto.
    static func isSchemaJunk(_ value: String) -> Bool {
        let text = value.trimmed
        return text.isEmpty || text.contains("$defs") || text.hasPrefix("#/") || text.hasSuffix("Extraction")
            || text.range(of: #"^[A-Z][a-z]+[A-Z][A-Za-z]+$"#, options: .regularExpression) != nil
    }

    static func join(_ a: String, _ b: String) -> String {
        let x = a.trimmed, y = b.trimmed
        if x.isEmpty { return y }
        if y.isEmpty || x.contains(y) { return x }
        if y.contains(x) { return y }
        return "\(x) \(y)"
    }

    static func sentences(_ value: String) -> [String] {
        var result: [String] = []
        value.enumerateSubstrings(in: value.startIndex..., options: [.bySentences, .localized]) { sentence, _, _, _ in
            if let sentence = sentence?.trimmed, !sentence.isEmpty { result.append(sentence) }
        }
        return result
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    func longer(_ other: String) -> String { other.trimmed.count > trimmed.count ? other : self }

    func truncated(words limit: Int) -> String {
        let parts = split(whereSeparator: \.isWhitespace)
        guard parts.count > limit else { return self }
        return parts.prefix(limit).joined(separator: " ") + "…"
    }
}

extension Array where Element: Hashable {
    var uniqued: [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

extension Array where Element == String {
    var cleaned: [String] { map(\.trimmed).filter { !$0.isEmpty }.uniqued }
}
