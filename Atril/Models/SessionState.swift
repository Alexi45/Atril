import Foundation

/// Lo que el máster apunta durante la partida. Alimenta el contexto del tutor.
struct SessionNote: Codable, Hashable, Identifiable {
    var id = UUID()
    var date = Date()
    /// Tiempo de juego transcurrido cuando se anotó.
    var playTime: TimeInterval
    var sceneID: String?
    var text: String
}

struct Player: Codable, Hashable, Identifiable {
    var id = UUID()
    var name = ""
    var character = ""
    var hp = 10
    var hpMax = 10
    var sanity = 50
    var sanityMax = 99
    var armorClass = 10
    var notes = ""
}

struct TutorMessage: Codable, Hashable, Identifiable {
    enum Role: String, Codable { case user, assistant }

    var id = UUID()
    var date = Date()
    var role: Role
    /// Texto que se muestra en la interfaz.
    var display: String
    /// Contenido exacto enviado o recibido. Se reenvía sin cambios para no invalidar
    /// la caché ni los bloques de razonamiento de turnos anteriores.
    var content: JSONValue
    /// Huella del prompt de sistema con el que se generó la respuesta.
    var contextHash: String?

    /// Representación en la API: `{role, content}`.
    var apiMessage: JSONValue {
        ["role": .string(role.rawValue), "content": content]
    }
}
