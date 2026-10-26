import Foundation

/// Guía estructurada que el tutor extrae del guion: lo que el máster consulta en mesa.
struct AdventureGuide: Codable, Hashable {
    var premise: String
    var truth: String
    var hook: String
    var tone: String
    var prep: [String]
    var scenes: [Scene]
    var npcs: [NPC]
    var clues: [Clue]
    var endings: [Ending]

    struct Scene: Codable, Hashable, Identifiable {
        var id: String
        var act: String
        var title: String
        var place: String
        var summary: String
        var readAloud: String
        var goals: [String]
        var clueIDs: [String]
        var npcIDs: [String]
        var checks: [Check]
        var tips: [String]
        var danger: String
        var ifStuck: String
        var exits: [Exit]
    }

    struct Check: Codable, Hashable {
        var skill: String
        var difficulty: String
        var purpose: String
    }

    struct Exit: Codable, Hashable {
        var sceneID: String
        var condition: String
    }

    struct NPC: Codable, Hashable, Identifiable {
        var id: String
        var name: String
        var role: String
        var look: String
        var motivation: String
        var secret: String
        var voice: String
        var stats: String
    }

    struct Clue: Codable, Hashable, Identifiable {
        var id: String
        var title: String
        var detail: String
        var sceneID: String
        var leadsTo: String
        var isCore: Bool
    }

    struct Ending: Codable, Hashable {
        var title: String
        var condition: String
        var outcome: String
    }

    func scene(_ id: String?) -> Scene? { scenes.first { $0.id == id } }
    func npc(_ id: String) -> NPC? { npcs.first { $0.id == id } }
    func clue(_ id: String) -> Clue? { clues.first { $0.id == id } }

    /// Pistas de una escena: las que la escena enumera y las que dicen encontrarse en ella.
    func clues(in scene: Scene) -> [Clue] {
        let listed = scene.clueIDs.compactMap(clue)
        let placed = clues.filter { $0.sceneID == scene.id && !scene.clueIDs.contains($0.id) }
        return listed + placed
    }
}

// MARK: - Esquema JSON para las salidas estructuradas

extension AdventureGuide {
    /// Esquema que se envía en `output_config.format`. Todas las propiedades son obligatorias
    /// y ningún objeto admite claves extra, como exige la API.
    static var jsonSchema: JSONValue {
        func object(_ properties: [(String, JSONValue)]) -> JSONValue {
            .object([
                "type": "object",
                "properties": .object(Dictionary(uniqueKeysWithValues: properties)),
                "required": .array(properties.map { .string($0.0) }),
                "additionalProperties": false,
            ])
        }
        func string(_ description: String) -> JSONValue { ["type": "string", "description": .string(description)] }
        func strings(_ description: String) -> JSONValue {
            ["type": "array", "items": ["type": "string"], "description": .string(description)]
        }
        func array(_ items: JSONValue, _ description: String) -> JSONValue {
            ["type": "array", "items": items, "description": .string(description)]
        }

        let check = object([
            ("skill", string("Habilidad o característica que se tira")),
            ("difficulty", string("Dificultad: Normal/Difícil/Extrema en Cthulhu, CD numérica en D&D")),
            ("purpose", string("Qué se consigue si sale bien y qué pasa si sale mal")),
        ])
        let exit = object([
            ("sceneID", string("id de la escena a la que se puede pasar")),
            ("condition", string("Qué tiene que pasar para ir allí")),
        ])
        let scene = object([
            ("id", string("Identificador corto y estable: e1, e2, e3…")),
            ("act", string("Acto o parte de la aventura (p. ej. «Acto 1 · La llegada»); vacío si no aplica")),
            ("title", string("Título breve de la escena")),
            ("place", string("Lugar donde ocurre")),
            ("summary", string("Qué ocurre en la escena, explicado al máster en 2-4 frases")),
            ("readAloud", string("Texto para leer en voz alta a los jugadores. Si el guion trae texto de caja, cópialo; si no, escribe 2-4 frases evocadoras")),
            ("goals", strings("Qué deben descubrir o conseguir los jugadores aquí")),
            ("clueIDs", strings("ids de las pistas que se pueden obtener en esta escena")),
            ("npcIDs", strings("ids de los PNJ presentes")),
            ("checks", array(check, "Tiradas probables en esta escena")),
            ("tips", strings("Consejos de dirección concretos para el máster en esta escena (ritmo, ambientación, trampas habituales)")),
            ("danger", string("Peligros, combates o pérdidas de Cordura/PV posibles; vacío si no hay")),
            ("ifStuck", string("Qué hacer si los jugadores se atascan: una forma natural de reconducirlos")),
            ("exits", array(exit, "Escenas a las que se puede pasar desde aquí")),
        ])
        let npc = object([
            ("id", string("Identificador corto: n1, n2…")),
            ("name", string("Nombre")),
            ("role", string("Papel en la historia, en una línea")),
            ("look", string("Aspecto y primera impresión")),
            ("motivation", string("Qué quiere")),
            ("secret", string("Lo que oculta; vacío si nada")),
            ("voice", string("Cómo interpretarlo en mesa: voz, gestos, muletillas")),
            ("stats", string("Estadísticas relevantes resumidas si el guion las trae; vacío si no")),
        ])
        let clue = object([
            ("id", string("Identificador corto: p1, p2…")),
            ("title", string("Nombre corto de la pista")),
            ("detail", string("Qué revela exactamente")),
            ("sceneID", string("id de la escena donde se encuentra")),
            ("leadsTo", string("A qué escena, PNJ o conclusión lleva")),
            ("isCore", ["type": "boolean", "description": "true si es imprescindible para avanzar"]),
        ])
        let ending = object([
            ("title", string("Nombre del desenlace")),
            ("condition", string("Cuándo ocurre")),
            ("outcome", string("Qué pasa y consecuencias (Cordura, recompensas…)")),
        ])
        return object([
            ("premise", string("Resumen de la aventura para el máster en 3-5 frases")),
            ("truth", string("La verdad oculta: qué está pasando realmente y quién está detrás")),
            ("hook", string("Cómo arrancar la partida y enganchar a los jugadores")),
            ("tone", string("Tono y ambientación: cómo debe sentirse la partida y recursos para lograrlo")),
            ("prep", strings("Lista de cosas que el máster debe preparar antes de jugar")),
            ("scenes", array(scene, "Escenas en el orden más probable de juego")),
            ("npcs", array(npc, "Personajes no jugadores importantes")),
            ("clues", array(clue, "Pistas e información que pueden descubrir los jugadores")),
            ("endings", array(ending, "Desenlaces posibles")),
        ])
    }
}
