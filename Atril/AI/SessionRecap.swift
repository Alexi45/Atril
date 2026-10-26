import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Resumen de una sesión: un texto para los jugadores (solo lo que ellos saben) y una lista
/// de pendientes para el máster.
struct SessionRecap: Hashable {
    var forPlayers: String
    var forGM: [String]
}

enum Recap {
    struct Facts {
        var title: String
        var system: GameSystem
        var guide: AdventureGuide?
        var notes: [SessionNote]
        var visitedSceneIDs: [String]
        var foundClueIDs: Set<String>
        var currentSceneID: String?
        var players: [Player]
    }

    /// Notas escritas por el máster (sin las que la app añade sola).
    static func ownNotes(_ notes: [SessionNote]) -> [SessionNote] {
        notes.filter { !$0.text.hasPrefix("Descubren la pista:") && !$0.text.hasPrefix("Tirada ") }
    }

    /// Resumen sin modelo, a partir de las escenas, las pistas y la bitácora.
    static func basic(_ facts: Facts) -> SessionRecap {
        let guide = facts.guide
        var sentences: [String] = []
        let scenes = facts.visitedSceneIDs.compactMap { guide?.scene($0) }
        if !scenes.isEmpty {
            sentences.append("La última vez en «\(facts.title)» pasasteis por \(list(scenes.map { "«\($0.title)»" })).")
        } else {
            sentences.append("La última vez en «\(facts.title)» empezó la aventura.")
        }
        let clues = guide?.clues.filter { facts.foundClueIDs.contains($0.id) } ?? []
        if !clues.isEmpty {
            sentences.append("Descubristeis \(list(clues.map { "«\($0.title)»" })).")
        }
        let notes = ownNotes(facts.notes).suffix(3).map { $0.text.trimmingCharacters(in: CharacterSet(charactersIn: ". ")) }
        if !notes.isEmpty {
            sentences.append("Además: \(notes.joined(separator: "; ")).")
        }
        if let scene = guide?.scene(facts.currentSceneID) {
            sentences.append("Os quedasteis en «\(scene.place.isEmpty ? scene.title : scene.place)».")
        }

        var gm: [String] = []
        if let guide, let scene = guide.scene(facts.currentSceneID) {
            let number = (guide.scenes.firstIndex { $0.id == scene.id } ?? 0) + 1
            gm.append("Retoma en «\(scene.title)» (escena \(number) de \(guide.scenes.count)).")
            if let exit = scene.exits.first, let next = guide.scene(exit.sceneID) {
                gm.append("Después, lo más probable: «\(next.title)» — \(exit.condition.lowercasedFirst).")
            }
            let pending = guide.clues.filter { $0.isCore && !facts.foundClueIDs.contains($0.id) }
            if !pending.isEmpty {
                gm.append("Pistas clave pendientes: \(pending.map { "«\($0.title)»" }.joined(separator: ", ")).")
            }
        }
        for player in facts.players where player.hpMax > 0 && player.hp * 2 <= player.hpMax {
            let name = player.character.isEmpty ? player.name : player.character
            gm.append("\(name) sigue herido: \(player.hp)/\(player.hpMax) PV.")
        }
        if facts.system.tracksSanity {
            for player in facts.players where player.sanity < 30 {
                let name = player.character.isEmpty ? player.name : player.character
                gm.append("\(name) anda baja de Cordura (\(player.sanity)): buen momento para un detalle inquietante.")
            }
        }
        return SessionRecap(forPlayers: sentences.joined(separator: " "), forGM: gm)
    }

    /// Une elementos con comas y una «y» final.
    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: ""
        case 1: items[0]
        default: items.dropLast().joined(separator: ", ") + " y " + items.last!
        }
    }

    /// Versión narrada con la IA de Apple. Solo recibe lo que los jugadores conocen, para que
    /// no se escapen secretos. Si falla, se usa el resumen básico.
    static func narrated(_ facts: Facts, basic: SessionRecap, tier: AppleAI.Tier) async -> String? {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, macOS 26.0, *) else { return nil }
        let guide = facts.guide
        let scenes = facts.visitedSceneIDs.compactMap { guide?.scene($0) }
            .map { "- \($0.title)\($0.place.isEmpty ? "" : " (\($0.place))")" }
        let clues = (guide?.clues.filter { facts.foundClueIDs.contains($0.id) } ?? [])
            .map { "- \($0.title): \($0.detail.truncated(words: 25))" }
        let notes = ownNotes(facts.notes).suffix(8).map { "- \($0.text.truncated(words: 30))" }
        let prompt = """
        Aventura: \(facts.title)

        Lugares por los que pasaron los personajes:
        \(scenes.isEmpty ? "- ninguno todavía" : scenes.joined(separator: "\n"))

        Lo que descubrieron:
        \(clues.isEmpty ? "- nada todavía" : clues.joined(separator: "\n"))

        Lo que hicieron según las notas del máster:
        \(notes.isEmpty ? "- sin notas" : notes.joined(separator: "\n"))

        Escribe el resumen de la sesión anterior para leerlo en voz alta a los jugadores al empezar la \
        siguiente: entre 3 y 5 frases, en segunda persona del plural («llegasteis», «descubristeis»), con tono \
        de narrador de \(facts.system.name). Cuenta solo lo que está en estas listas y termina con una frase \
        que deje intriga.
        """
        let instructions = """
        Ayudas a un director de juego de rol a preparar el «previamente» de su partida. Escribes en español \
        de España, con frases claras y evocadoras. Nunca inventas hechos ni revelas secretos.
        """
        do {
            let session = AppleSessions.make(tier, instructions: instructions)
            let response = try await session.respond(to: prompt, options: GenerationOptions(temperature: 0.7, maximumResponseTokens: 350))
            let text = response.content.trimmed
            return Prose.isPlaceholder(text) || text.split(separator: " ").count < 12 ? nil : text
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }
}
