import Foundation

enum TutorPrompts {
    // MARK: Análisis del guion

    static func analysisSystem(_ system: GameSystem) -> String {
        """
        Eres un director de juego veterano que prepara aventuras para otros másteres. Vas a leer el \
        guion completo de una aventura y a convertirlo en una guía de dirección que el máster \
        consultará en mesa, con prisas y mientras habla con los jugadores.

        \(system.rulesPrimer)

        Cómo hacerlo:
        - Escribe en español, en frases cortas y concretas. Nada de relleno.
        - Sé fiel al guion: no inventes tramas, PNJ ni pistas que no estén. Solo puedes redactar \
        tú el texto para leer en voz alta cuando el guion no lo traiga, y los consejos de dirección.
        - Ordena las escenas en el orden en que es más probable jugarlas. Si la aventura es abierta \
        (una investigación, un sandbox), crea una escena por localización o encuentro importante y \
        usa las salidas para reflejar los caminos posibles.
        - Usa ids cortos y estables (e1, e2… para escenas; n1… para PNJ; p1… para pistas) y \
        haz que todas las referencias cruzadas apunten a ids que existan.
        - Marca como clave las pistas sin las que no se puede avanzar, y en «Si se atascan» da \
        siempre una salida que no dependa de una tirada.
        - Los consejos deben ser los que darías a alguien que dirige esta aventura por primera vez: \
        qué suele salir mal, cómo dosificar la información, cómo crear tensión.
        """
    }

    static func analysisRequest(title: String, script: String) -> String {
        """
        Aventura: \(title)

        <guion>
        \(script)
        </guion>

        Prepara la guía de dirección completa de esta aventura.
        """
    }

    // MARK: Tutor en partida

    static func tutorSystem(_ system: GameSystem) -> String {
        """
        Eres el tutor de un máster de rol que está dirigiendo una partida ahora mismo, en mesa, con \
        los jugadores delante. Conoces el guion completo de la aventura (abajo) y en cada mensaje \
        recibirás el estado actual de la partida.

        \(system.rulesPrimer)

        Tu trabajo es decirle qué hacer a continuación, como haría un mentor sentado a su lado:
        - Responde en español, directo y accionable. El máster lee de un vistazo: frases cortas, \
        listas breves, lo más importante primero. Unas 120 palabras salvo que pida más detalle.
        - Usa estos encabezados en negrita solo cuando aporten: **Ahora**, **Lee en voz alta**, \
        **Tirada**, **Si…**, **Ojo**.
        - Ancla tus consejos al guion y al estado de la partida: cita la escena, el PNJ o la pista \
        concreta. Si los jugadores se han salido del guion, improvisa algo coherente con la verdad \
        de la aventura y explica cómo reconducirlos sin forzarlos.
        - Puedes revelar al máster todos los secretos; él decide qué cuenta a los jugadores.
        - Si una regla no está clara, da la interpretación más común y sigue adelante: en mesa \
        importa más el ritmo que la exactitud.
        """
    }

    /// Bloque estable con el guion y el índice de la guía. Va al final del prompt de sistema
    /// para cachearse: es la parte grande y no cambia durante la partida.
    static func scriptContext(title: String, script: String, guide: AdventureGuide?) -> String {
        var index = ""
        if let guide {
            index = guide.scenes.map { "- \($0.id): \($0.title) (\($0.place))" }.joined(separator: "\n")
            index += "\n" + guide.npcs.map { "- \($0.id): \($0.name), \($0.role)" }.joined(separator: "\n")
            index += "\n" + guide.clues.map { "- \($0.id): \($0.title)\($0.isCore ? " [clave]" : "")" }.joined(separator: "\n")
        }
        return """
        Aventura: \(title)

        <guion>
        \(script)
        </guion>

        <indice>
        \(index)
        </indice>
        """
    }

    struct TableState {
        var system: GameSystem
        var guide: AdventureGuide?
        var playTime: TimeInterval
        var currentSceneID: String?
        var visitedSceneIDs: [String]
        var foundClueIDs: Set<String>
        var players: [Player]
        var notes: [SessionNote]
    }

    /// Instantánea del estado de la mesa que acompaña a cada pregunta. Se guarda con el
    /// mensaje, así que el historial enviado nunca cambia a posteriori.
    /// `ids: false` para modelos pequeños, que tienden a repetir los identificadores internos.
    static func stateBlock(_ state: TableState, ids: Bool = true) -> String {
        var lines = ["Tiempo de juego: \(Format.duration(state.playTime))"]
        if let guide = state.guide {
            func clue(_ clue: AdventureGuide.Clue) -> String { ids ? "\(clue.id) \(clue.title)" : clue.title }
            if let scene = guide.scene(state.currentSceneID) {
                lines.append("Escena actual: \(ids ? "\(scene.id) · " : "")\(scene.title)")
            }
            let visited = state.visitedSceneIDs.filter { $0 != state.currentSceneID }
            if !visited.isEmpty {
                let names = ids ? visited : visited.compactMap { guide.scene($0)?.title }
                lines.append("Escenas ya jugadas: \(names.joined(separator: ", "))")
            }
            let found = guide.clues.filter { state.foundClueIDs.contains($0.id) }
            lines.append("Pistas descubiertas: \(found.isEmpty ? "ninguna" : found.map(clue).joined(separator: "; "))")
            let missingCore = guide.clues.filter { $0.isCore && !state.foundClueIDs.contains($0.id) }
            if !missingCore.isEmpty {
                let pending = missingCore.map { item in
                    ids ? clue(item) : "\(item.title)\(guide.scene(item.sceneID).map { " (en «\($0.title)»)" } ?? "")"
                }
                lines.append("Pistas clave pendientes: \(pending.joined(separator: "; "))")
            }
        }
        if !state.players.isEmpty {
            let party = state.players.map { player in
                var line = "\(player.character.isEmpty ? player.name : player.character)"
                if !player.name.isEmpty && !player.character.isEmpty { line += " (\(player.name))" }
                line += " PV \(player.hp)/\(player.hpMax)"
                if state.system.tracksSanity { line += ", COR \(player.sanity)" }
                if !player.notes.isEmpty { line += ", \(player.notes)" }
                return line
            }
            lines.append("\(state.system.characterNoun): \(party.joined(separator: "; "))")
        }
        let recent = state.notes.suffix(12)
        if !recent.isEmpty {
            lines.append("Notas de la mesa (de más antigua a más reciente):")
            lines += recent.map { "- [\(Format.duration($0.playTime))] \($0.text)" }
        }
        return "<estado_partida>\n\(lines.joined(separator: "\n"))\n</estado_partida>"
    }
}

/// Atajos de una pulsación para las dudas más habituales en mesa.
struct QuickAction: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
    let prompt: String
    /// Si necesita que el máster complete la frase antes de enviarla.
    var needsDetail = false

    static let all: [QuickAction] = [
        QuickAction(id: "next", title: "¿Qué hago ahora?", symbol: "arrow.forward.circle",
                    prompt: "¿Qué hago ahora? Dame el siguiente paso concreto para dirigir este momento."),
        QuickAction(id: "stuck", title: "Están atascados", symbol: "questionmark.bubble",
                    prompt: "Los jugadores están atascados y no saben qué hacer. Dame una forma natural de darles una pista sin regalarles la solución."),
        QuickAction(id: "offscript", title: "Se han salido del guion", symbol: "arrow.triangle.branch",
                    prompt: "Los jugadores se han salido del guion: ", needsDetail: true),
        QuickAction(id: "describe", title: "Descríbelo", symbol: "text.quote",
                    prompt: "Dame una descripción breve y evocadora del lugar o la situación actual para leer en voz alta."),
        QuickAction(id: "npc", title: "Improvisa un PNJ", symbol: "person.badge.plus",
                    prompt: "Necesito improvisar un PNJ coherente con la aventura para este momento: nombre, aspecto, cómo habla, qué sabe y qué quiere."),
        QuickAction(id: "roll", title: "¿Qué tirada pido?", symbol: "dice",
                    prompt: "¿Qué tirada debería pedir ahora, con qué dificultad y qué pasa si sale bien o mal?"),
        QuickAction(id: "tension", title: "Sube la tensión", symbol: "bolt.heart",
                    prompt: "La mesa está perdiendo ritmo. ¿Cómo subo la tensión ahora mismo sin romper la historia?"),
        QuickAction(id: "rule", title: "Duda de reglas", symbol: "book.closed",
                    prompt: "Duda de reglas: ", needsDetail: true),
    ]
}

enum Format {
    static func duration(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return hours > 0 ? String(format: "%d h %02d min", hours, minutes) : "\(minutes) min"
    }

    static func clock(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}
