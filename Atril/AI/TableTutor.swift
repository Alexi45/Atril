import Foundation

/// Qué motor responde al máster. La IA de Apple va integrada; Claude es opcional.
enum AIBackend: Equatable {
    case apple(AppleAI.Tier)
    case basic
    case claude

    var label: String {
        switch self {
        case .apple(.cloud): "IA de Apple · nube privada"
        case .apple(.onDevice): "IA de Apple · en el dispositivo"
        case .basic: "Tutor básico · sin conexión"
        case .claude: "Claude"
        }
    }

    var symbol: String {
        switch self {
        case .apple(.cloud): "cloud"
        case .apple(.onDevice): "cpu"
        case .basic: "book.closed"
        case .claude: "sparkles"
        }
    }

    static let useClaudeKey = "useClaude"

    /// El mejor motor disponible ahora mismo.
    static var current: AIBackend {
        if UserDefaults.standard.bool(forKey: useClaudeKey), KeychainStore.hasKey { return .claude }
        if let tier = AppleAI.status.best { return .apple(tier) }
        return .basic
    }
}

/// Lo que el tutor sabe de la mesa en el momento de la pregunta.
struct TableSnapshot {
    var title: String
    var system: GameSystem
    var guide: AdventureGuide?
    var state: TutorPrompts.TableState
    var index: ScriptIndex
    var recent: [TutorMessage]

    var scene: AdventureGuide.Scene? { guide?.scene(state.currentSceneID) }
}

// MARK: - Contexto compacto para la IA de Apple

enum TutorContext {
    /// Prompt autocontenido para modelos de contexto corto: la escena actual, el estado de la
    /// mesa y los pasajes del guion más relacionados con la pregunta.
    static func prompt(question: String, table: TableSnapshot, passages: Int, generous: Bool) -> String {
        var parts: [String] = []
        if let guide = table.guide {
            parts.append("## Aventura: \(table.title)\n\(guide.premise.truncated(words: generous ? 120 : 60))\nLa verdad oculta: \(guide.truth.truncated(words: generous ? 120 : 60))")
            if let scene = table.scene {
                var card = ["## Escena actual: \(scene.title)\(scene.place.isEmpty ? "" : " (\(scene.place))")", scene.summary.truncated(words: 70)]
                if !scene.goals.isEmpty { card.append("Objetivos: \(scene.goals.joined(separator: "; "))") }
                let clues = guide.clues(in: scene).map { "\($0.title)\($0.isCore ? " [clave]" : "")\(table.state.foundClueIDs.contains($0.id) ? " (ya descubierta)" : ""): \($0.detail.truncated(words: 20))" }
                if !clues.isEmpty { card.append("Pistas aquí: \(clues.joined(separator: " | "))") }
                let npcs = scene.npcIDs.compactMap(guide.npc).map { "\($0.name), \($0.role); quiere: \($0.motivation.truncated(words: 12))" }
                if !npcs.isEmpty { card.append("PNJ presentes: \(npcs.joined(separator: " | "))") }
                if !scene.checks.isEmpty { card.append("Tiradas: \(scene.checks.map { "\($0.skill) \($0.difficulty)".trimmed }.joined(separator: ", "))") }
                if !scene.ifStuck.isEmpty { card.append("Si se atascan: \(scene.ifStuck.truncated(words: 30))") }
                let exits = scene.exits.compactMap { exit in guide.scene(exit.sceneID).map { "\($0.title) (\(exit.condition.truncated(words: 10)))" } }
                if !exits.isEmpty { card.append("Siguientes escenas: \(exits.joined(separator: "; "))") }
                parts.append(card.joined(separator: "\n"))
            }
        }
        parts.append(TutorPrompts.stateBlock(table.state, ids: false))

        let query = [question, table.scene?.title ?? "", table.scene?.place ?? ""].joined(separator: " ")
        let found = table.index.search(query, limit: passages)
        if !found.isEmpty {
            let wordLimit = generous ? 160 : 90
            parts.append("## Fragmentos del guion relacionados\n" + found.enumerated()
                .map { "[\($0.offset + 1)] \($0.element.heading.isEmpty ? "" : "\($0.element.heading): ")\($0.element.text.truncated(words: wordLimit))" }
                .joined(separator: "\n"))
        }

        let history = table.recent.suffix(generous ? 6 : 2)
        if !history.isEmpty {
            parts.append("## Conversación reciente\n" + history.map {
                "\($0.role == .user ? "Máster" : "Tutor"): \($0.display.truncated(words: generous ? 80 : 40))"
            }.joined(separator: "\n"))
        }
        parts.append("## Pregunta del máster\n\(question)")
        return parts.joined(separator: "\n\n")
    }
}

// MARK: - Tutor sin modelo

/// Responde a partir de la guía, el estado de la mesa, una referencia de reglas y tablas de
/// improvisación. Funciona en cualquier dispositivo y sin conexión.
enum BasicTutor {
    static func answer(_ question: String, table: TableSnapshot, seed: UInt64 = UInt64(Date().timeIntervalSince1970)) -> String {
        var random = SeededRandom(seed: seed)
        switch intent(of: question) {
        case .next: return next(table)
        case .stuck: return stuck(table)
        case .offScript: return offScript(question, table)
        case .describe: return describe(table)
        case .npc: return improviseNPC(table, random: &random)
        case .roll: return roll(table)
        case .tension: return tension(table, random: &random)
        case .rule: return rule(question, system: table.system)
        case .search: return search(question, table)
        }
    }

    enum Intent { case next, stuck, offScript, describe, npc, roll, tension, rule, search }

    static func intent(of question: String) -> Intent {
        let text = Prose.fold(question)
        func has(_ keys: [String]) -> Bool { keys.contains { text.contains($0) } }
        if has(["salido del guion", "se han desviado", "no siguen", "otro sitio", "se van a"]) { return .offScript }
        if has(["atascad", "no saben que hacer", "perdidos", "bloquead", "dales una pista"]) { return .stuck }
        if has(["improvis", "pnj", "personaje nuevo", "nombre para"]) { return .npc }
        if has(["que tirada", "tirada pido", "que tiro", "que tiren"]) { return .roll }
        if has(["describ", "voz alta", "ambiente"]) { return .describe }
        if has(["tension", "ritmo", "aburr", "decae", "animar"]) { return .tension }
        if has(["regla", "duda de", "como funciona", "cordura", "locura", "forzar", "herida", "combate", "ventaja",
                "salvacion", "muerte", "descanso", "iniciativa", "suerte", "persecucion", "concentracion", "oportunidad"]) { return .rule }
        if has(["que hago", "ahora", "siguiente", "como sigo", "continuar"]) { return .next }
        return .search
    }

    private static func next(_ table: TableSnapshot) -> String {
        guard let guide = table.guide, let scene = table.scene else {
            return "**Ahora**\n- Recuérdales dónde están y qué saben.\n- Pregunta a cada jugador qué hace su personaje.\n- Apunta en la bitácora lo que decidan."
        }
        var lines = ["**Ahora · \(scene.title)**"]
        let pending = guide.clues(in: scene).filter { !table.state.foundClueIDs.contains($0.id) }
        if let goal = scene.goals.first { lines.append("- Objetivo de la escena: \(goal.lowercasedFirst).") }
        if let clue = pending.first(where: \.isCore) ?? pending.first {
            lines.append("- Aún no tienen «\(clue.title)»\(clue.isCore ? " (clave)" : ""): \(clue.detail.truncated(words: 22))")
        } else if !guide.clues(in: scene).isEmpty {
            lines.append("- Ya tienen las pistas de esta escena: es buen momento para avanzar.")
        }
        if let check = scene.checks.first(where: { $0.skill != "Cordura" }) {
            lines.append("- Tirada útil: **\(check.skill)**\(check.difficulty.isEmpty ? "" : " (\(check.difficulty))").")
        }
        if let exit = scene.exits.first, let target = guide.scene(exit.sceneID) {
            lines.append("\n**Si…**\n- \(exit.condition.capitalizedFirst) → pasa a «\(target.title)».")
        }
        if let tip = scene.tips.first { lines.append("\n**Ojo**\n- \(tip)") }
        return lines.joined(separator: "\n")
    }

    private static func stuck(_ table: TableSnapshot) -> String {
        guard let guide = table.guide, let scene = table.scene else {
            return "**Si se atascan**\n- Resume en voz alta lo que saben.\n- Haz que pase algo: alguien llega, algo suena, el tiempo apremia."
        }
        var lines = ["**Si se atascan**"]
        if !scene.ifStuck.isEmpty { lines.append("- \(scene.ifStuck)") }
        let pendingCore = guide.clues.filter { $0.isCore && !table.state.foundClueIDs.contains($0.id) }
        if let clue = pendingCore.first {
            let npc = scene.npcIDs.compactMap(guide.npc).first
            lines.append("- Haz que \(npc.map { "\($0.name)" } ?? "un detalle del entorno") les ponga sobre la pista de «\(clue.title)» sin tirada.")
        }
        lines.append("- Resume lo que saben y pregunta: «¿Qué es lo que más os inquieta?». Suele reactivar la mesa.")
        return lines.joined(separator: "\n")
    }

    private static func offScript(_ question: String, _ table: TableSnapshot) -> String {
        var lines = ["**Se han salido del guion**",
                     "- No los fuerces a volver: mueve el contenido hacia ellos. Lo que iba a pasar en un sitio puede pasar donde estén."]
        if let guide = table.guide {
            let pending = guide.clues.filter { $0.isCore && !table.state.foundClueIDs.contains($0.id) }
            if !pending.isEmpty {
                lines.append("- Pistas clave que aún necesitan: \(pending.prefix(3).map { "«\($0.title)»" }.joined(separator: ", ")). Colócalas en el nuevo lugar o en boca de alguien que encuentren.")
            }
            if let npc = guide.npcs.first(where: { !$0.motivation.isEmpty }) {
                lines.append("- Usa a \(npc.name): quiere \(npc.motivation.lowercasedFirst.truncated(words: 14)) y puede buscarlos él.")
            }
        }
        let related = table.index.search(question, limit: 1)
        if let passage = related.first {
            lines.append("\n**Lo más parecido en el guion**\n- \(passage.heading.isEmpty ? "" : "\(passage.heading): ")\(passage.text.truncated(words: 40))")
        }
        return lines.joined(separator: "\n")
    }

    private static func describe(_ table: TableSnapshot) -> String {
        guard let scene = table.scene else { return "**Lee en voz alta**\nDescribe tres cosas: lo que ven, lo que oyen y algo que no encaja." }
        if !scene.readAloud.isEmpty { return "**Lee en voz alta**\n\(scene.readAloud)" }
        return "**Lee en voz alta**\n\(scene.summary)\n\n**Ojo**\n- Añade un sonido y un olor: hacen el lugar real."
    }

    private static func roll(_ table: TableSnapshot) -> String {
        var lines = ["**Tirada**"]
        if let checks = table.scene?.checks, !checks.isEmpty {
            lines += checks.prefix(3).map { "- **\($0.skill)**\($0.difficulty.isEmpty ? "" : " (\($0.difficulty))"): \($0.purpose.truncated(words: 20))" }
        } else {
            lines.append(table.system == .dnd
                ? "- Pide una prueba de la característica más lógica con CD 10 (fácil), 15 (media) o 20 (difícil)."
                : "- Pide la habilidad más lógica. Usa Difícil solo si la situación lo justifica.")
        }
        lines.append(table.system == .cthulhu
            ? "\n**Si fallan**\n- Ofrece forzar la tirada a cambio de un riesgo claro."
            : "\n**Si fallan**\n- Que el fallo complique la situación en vez de pararla.")
        return lines.joined(separator: "\n")
    }

    private static func tension(_ table: TableSnapshot, random: inout SeededRandom) -> String {
        let ideas: [String] = table.system == .dnd ? [
            "Un rival llega antes que ellos al objetivo.",
            "El suelo cede o una puerta se cierra: separa al grupo un momento.",
            "Un aliado les pide ayuda urgente y les obliga a elegir.",
            "Ponles un reloj: «Tenéis tres asaltos antes de que…».",
        ] : [
            "Un ruido arriba, justo cuando nadie mira.",
            "Una luz se apaga y alguien ya no está donde estaba.",
            "Un PNJ aterrado aparece con una frase incompleta.",
            "Encuentran algo que ya no debería estar ahí: huellas mojadas, una puerta abierta.",
            "Ponles un reloj: la marea, la noche, el tren que sale.",
        ]
        var lines = ["**Sube la tensión**"]
        var pool = ideas
        for _ in 0..<2 where !pool.isEmpty {
            lines.append("- \(pool.remove(at: random.next(pool.count)))")
        }
        if let danger = table.scene?.danger, !danger.isEmpty { lines.append("- Adelanta el peligro de la escena: \(danger.truncated(words: 22))") }
        lines.append("\n**Ojo**\n- Frases cortas y pregunta directa a un jugador: «¿Qué haces?».")
        return lines.joined(separator: "\n")
    }

    private static func improviseNPC(_ table: TableSnapshot, random: inout SeededRandom) -> String {
        let names = table.system == .dnd
            ? ["Brenna Calderón", "Ostrik el Pardo", "Mirela Vane", "Tobías Piedrahueca", "Ysolda", "Garrick Tres Dedos"]
            : ["Amparo Lafuente", "Benito Sanjurjo", "Consuelo Riera", "Faustino Arce", "Herminia Galán", "Teodoro Villa"]
        let looks = ["manos manchadas de tinta", "una cicatriz que esconde con el pelo", "ropa demasiado buena para el lugar",
                     "mira siempre a la puerta", "huele a tabaco de pipa", "sonrisa amable que no llega a los ojos"]
        let voices = ["habla muy bajo y obliga a acercarse", "repite la última palabra de los demás", "tutea a todo el mundo",
                      "se ríe en mal momento", "contesta con preguntas", "habla rápido cuando miente"]
        let wants = ["que los forasteros se vayan cuanto antes", "dinero para salir del pueblo", "proteger a un familiar",
                     "que alguien le crea", "vengarse de quien le engañó", "saber qué buscan los personajes"]
        var lines = ["**PNJ improvisado: \(names[random.next(names.count)])**",
                     "- Aspecto: \(looks[random.next(looks.count)]).",
                     "- Voz: \(voices[random.next(voices.count)]).",
                     "- Quiere: \(wants[random.next(wants.count)])."]
        if let guide = table.guide, let clue = guide.clues.first(where: { $0.isCore && !table.state.foundClueIDs.contains($0.id) }) {
            lines.append("- Sabe algo útil: puede llevarles a «\(clue.title)».")
        } else {
            lines.append("- Sabe un rumor que puede llevarles a la siguiente escena.")
        }
        return lines.joined(separator: "\n")
    }

    private static func search(_ question: String, _ table: TableSnapshot) -> String {
        let passages = table.index.search(question, limit: 2)
        guard !passages.isEmpty else {
            return "No encuentro nada en el guion sobre eso.\n\n**Ahora**\n- Improvisa algo coherente con la verdad de la aventura y anótalo en la bitácora para mantenerlo luego."
        }
        var lines = ["**Lo que dice el guion**"]
        lines += passages.map { "- \($0.heading.isEmpty ? "" : "**\($0.heading)**: ")\($0.text.truncated(words: 55))" }
        return lines.joined(separator: "\n")
    }

    // MARK: Reglas

    struct RuleEntry {
        var keys: [String]
        var title: String
        var text: String
    }

    static func rule(_ question: String, system: GameSystem) -> String {
        let entries = system == .dnd ? dndRules : cthulhuRules
        let text = Prose.fold(question)
        let matches = entries.filter { entry in entry.keys.contains { text.contains($0) } }
        guard !matches.isEmpty else {
            let topics = entries.map(\.title).joined(separator: ", ")
            return "No tengo esa regla a mano. Temas que conozco: \(topics).\n\n**Ojo**\n- En mesa, decide algo razonable y sigue: revisa la regla al terminar la sesión."
        }
        return matches.prefix(2).map { "**\($0.title)**\n\($0.text)" }.joined(separator: "\n\n")
    }

    static let cthulhuRules: [RuleEntry] = [
        RuleEntry(keys: ["forzar"], title: "Forzar una tirada",
                  text: "- Solo si el jugador explica cómo lo intenta de nuevo.\n- Antes de tirar, avisa de qué pasará si falla: el segundo fallo trae una consecuencia seria.\n- No se fuerzan las tiradas de Cordura, Suerte ni combate."),
        RuleEntry(keys: ["cordura", "locura", "cor "], title: "Cordura y locura",
                  text: "- Tirada de Cordura: éxito pierde lo de antes de la barra; fallo, lo de después.\n- Perder 5 o más de una vez: tirada de INT; si la supera, locura temporal (1D10 horas).\n- Perder una quinta parte de la COR en un día: locura indefinida.\n- Durante la locura, ataque de locura y delirios."),
        RuleEntry(keys: ["herida", "pv", "dano", "inconsciente", "muerte", "morir"], title: "Heridas",
                  text: "- Herida grave: perder la mitad o más de los PV máximos de un golpe. Tirada de CON para no caer inconsciente.\n- A 0 PV con herida grave: moribundo; necesita primeros auxilios o muere.\n- A 0 PV sin herida grave: inconsciente."),
        RuleEntry(keys: ["combate", "atac", "esquivar", "contraatac", "ronda"], title: "Combate",
                  text: "- Orden por DES (las armas de fuego preparadas van antes).\n- El defensor elige: esquivar o contraatacar. Gana el mejor nivel de éxito.\n- Superados en número: el atacante gana un dado de bonificación."),
        RuleEntry(keys: ["suerte"], title: "Suerte",
                  text: "- Tirada de Suerte para lo que depende del azar del grupo.\n- Opcional: gastar Suerte para subir una tirada fallida punto por punto (no Cordura ni Suerte)."),
        RuleEntry(keys: ["bonificacion", "penalizacion", "dados extra", "ventaja"], title: "Dados de bonificación y penalización",
                  text: "- Se tira un dado de decenas extra por cada uno.\n- Bonificación: te quedas con el resultado más bajo. Penalización: con el más alto.\n- Uno de cada se anulan entre sí."),
        RuleEntry(keys: ["persecucion", "huir", "perseguir"], title: "Persecuciones",
                  text: "- Tirada de velocidad (CON o Conducir) para fijar MOV.\n- Cada asalto, acciones de movimiento; los obstáculos piden una tirada para no perder tiempo.\n- Si no quieres reglas: tres tiradas, dos éxitos para escapar."),
        RuleEntry(keys: ["dificultad", "dificil", "extrem"], title: "Dificultad",
                  text: "- Normal: el valor de la habilidad. Difícil: la mitad. Extrema: la quinta parte.\n- Contra un PNJ, la dificultad la marca su habilidad: 50 o más, Difícil; 90 o más, Extrema."),
    ]

    static let dndRules: [RuleEntry] = [
        RuleEntry(keys: ["ventaja", "desventaja"], title: "Ventaja y desventaja",
                  text: "- Tira dos d20: con ventaja te quedas el mayor; con desventaja, el menor.\n- No se acumulan: varias fuentes de ventaja cuentan como una, y una ventaja y una desventaja se anulan."),
        RuleEntry(keys: ["muerte", "morir", "0 pv", "inconsciente"], title: "Caer a 0 PV",
                  text: "- Inconsciente y haciendo salvaciones contra muerte: d20 sin modificador, 10 o más es éxito.\n- Tres éxitos: estable. Tres fallos: muere. Un 20 natural: recupera 1 PV; un 1 cuenta como dos fallos.\n- Recibir daño a 0 PV: un fallo (dos si es crítico)."),
        RuleEntry(keys: ["descanso"], title: "Descansos",
                  text: "- Corto: 1 hora; se gastan dados de golpe para curarse.\n- Largo: 8 horas; recupera todos los PV y la mitad de los dados de golpe. Uno cada 24 horas."),
        RuleEntry(keys: ["iniciativa", "combate", "turno"], title: "Combate",
                  text: "- Iniciativa: prueba de Destreza.\n- En tu turno: movimiento, una acción y, si la tienes, una acción adicional; una reacción por asalto."),
        RuleEntry(keys: ["oportunidad"], title: "Ataque de oportunidad",
                  text: "- Cuando un enemigo sale de tu alcance, puedes usar tu reacción para un ataque cuerpo a cuerpo.\n- La acción de Retirarse lo evita."),
        RuleEntry(keys: ["concentracion", "conjuro", "hechizo"], title: "Concentración",
                  text: "- Solo un conjuro de concentración a la vez.\n- Al recibir daño: salvación de Constitución CD 10 o la mitad del daño (lo que sea mayor)."),
        RuleEntry(keys: ["salvacion", "cd", "dificultad"], title: "Clases de dificultad",
                  text: "- Muy fácil 5 · Fácil 10 · Media 15 · Difícil 20 · Muy difícil 25 · Casi imposible 30."),
        RuleEntry(keys: ["cobertura"], title: "Cobertura",
                  text: "- Media: +2 a CA y salvaciones de Destreza. Tres cuartos: +5. Total: no se le puede atacar directamente."),
    ]
}

/// Generador reproducible para las tablas de improvisación.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next(_ upperBound: Int) -> Int {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Int((state >> 33) % UInt64(max(upperBound, 1)))
    }
}

extension String {
    var lowercasedFirst: String {
        guard let first else { return self }
        return first.lowercased() + dropFirst()
    }
}
