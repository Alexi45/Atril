import SwiftUI

enum GameSystem: String, Codable, CaseIterable, Identifiable {
    case cthulhu
    case dnd
    case other

    var id: String { rawValue }

    var name: String {
        switch self {
        case .cthulhu: "La llamada de Cthulhu"
        case .dnd: "Dungeons & Dragons"
        case .other: "Otro sistema"
        }
    }

    var edition: String {
        switch self {
        case .cthulhu: "7.ª edición"
        case .dnd: "5.ª edición"
        case .other: "Genérico"
        }
    }

    var shortName: String {
        switch self {
        case .cthulhu: "Cthulhu"
        case .dnd: "D&D"
        case .other: "Rol"
        }
    }

    var symbol: String {
        switch self {
        case .cthulhu: "eye"
        case .dnd: "shield.lefthalf.filled"
        case .other: "dice"
        }
    }

    var accent: Color {
        switch self {
        case .cthulhu: Color(red: 0.16, green: 0.50, blue: 0.45)
        case .dnd: Color(red: 0.70, green: 0.20, blue: 0.20)
        case .other: Color(red: 0.33, green: 0.36, blue: 0.70)
        }
    }

    /// Cómo se llama a los personajes de los jugadores en cada juego.
    var characterNoun: String {
        switch self {
        case .cthulhu: "Investigadores"
        case .dnd: "Aventureros"
        case .other: "Personajes"
        }
    }

    var tracksSanity: Bool { self == .cthulhu }

    /// Contexto de reglas que el tutor debe tener presente.
    var rulesPrimer: String {
        switch self {
        case .cthulhu:
            """
            Sistema: La llamada de Cthulhu, 7.ª edición (Chaosium). Tiradas de porcentaje con d100 contra \
            habilidad; niveles de éxito Normal, Difícil (mitad) y Extremo (quinta parte); 01 es crítico; \
            pifia con 100 (o 96-100 si la habilidad es menor de 50). Dados de bonificación y penalización. \
            Forzar tiradas con consecuencias. Cordura (COR) con pérdidas del tipo 1/1D6, locura temporal \
            e indefinida. Puntos de Vida, Suerte y gasto de Suerte. El tono es horror investigativo: las \
            pistas clave nunca deben depender de una sola tirada fallida.
            """
        case .dnd:
            """
            Sistema: Dungeons & Dragons, 5.ª edición. d20 + modificador contra Clase de Dificultad (CD) \
            o Clase de Armadura (CA); ventaja y desventaja; salvaciones; iniciativa; acciones, acciones \
            adicionales y reacciones; descansos cortos y largos; inspiración. Equilibra combate, \
            exploración e interacción social.
            """
        case .other:
            "Sistema genérico: adapta los consejos a las reglas que indique el guion."
        }
    }
}
