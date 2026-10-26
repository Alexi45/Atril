import CryptoKit
import Foundation
import SwiftData

@Model
final class Adventure {
    var id = UUID()
    var title = ""
    var systemRaw = GameSystem.cthulhu.rawValue
    var script = ""
    var sourceFileName: String?
    var createdAt = Date()
    var updatedAt = Date()
    var guideData: Data?
    /// Huella del guion con el que se generó la guía, para avisar si el guion cambia.
    var analyzedScriptHash: String?
    /// Motor que preparó la guía: «basic», «onDevice», «cloud» o «claude».
    var guideEngine: String?
    /// Elementos de la lista «Antes de jugar» ya hechos.
    var prepDone: [String] = []
    /// Duración prevista de cada sesión, para el plan y los avisos de ritmo.
    var sessionHours: Double = 3
    @Relationship(deleteRule: .cascade, inverse: \PlaySession.adventure)
    var sessions: [PlaySession] = []

    init(title: String, system: GameSystem, script: String, sourceFileName: String? = nil) {
        self.title = title
        self.systemRaw = system.rawValue
        self.script = script
        self.sourceFileName = sourceFileName
    }

    var system: GameSystem {
        get { GameSystem(rawValue: systemRaw) ?? .other }
        set { systemRaw = newValue.rawValue }
    }

    var guide: AdventureGuide? {
        get { guideData.flatMap { try? JSONDecoder().decode(AdventureGuide.self, from: $0) } }
        set {
            guideData = newValue.flatMap { try? JSONEncoder().encode($0) }
            analyzedScriptHash = newValue == nil ? nil : Self.hash(script)
            updatedAt = .now
        }
    }

    var isGuideStale: Bool { guideData != nil && analyzedScriptHash != Self.hash(script) }

    /// La guía la hicieron las heurísticas, no una IA.
    var isBasicGuide: Bool { guideData != nil && (guideEngine ?? "basic") == "basic" }

    var guideEngineLabel: String {
        switch guideEngine {
        case "cloud": "IA de Apple (nube privada)"
        case "onDevice": "IA de Apple (en el dispositivo)"
        case "claude": "Claude"
        case "sample": "guía de ejemplo"
        default: "organización automática básica"
        }
    }

    var sortedSessions: [PlaySession] { sessions.sorted { $0.lastPlayedAt > $1.lastPlayedAt } }

    var wordCount: Int { script.split(whereSeparator: \.isWhitespace).count }

    static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}

@Model
final class PlaySession {
    var id = UUID()
    var number = 1
    var startedAt = Date()
    var lastPlayedAt = Date()
    var elapsed: TimeInterval = 0
    var currentSceneID: String?
    var visitedSceneIDs: [String] = []
    var foundClueIDs: [String] = []
    var notesData = Data()
    var playersData = Data()
    var chatData = Data()
    /// Resumen para los jugadores que se preparó al cerrar esta sesión.
    var playerSummary: String?
    /// «Previamente…»: resumen de la sesión anterior para leer al empezar esta.
    var recap: String?
    var recapDismissed = false
    /// Combate en curso, si lo hay.
    var combatData = Data()
    var adventure: Adventure?

    init(number: Int, adventure: Adventure) {
        self.number = number
        self.adventure = adventure
        self.currentSceneID = adventure.guide?.scenes.first?.id
    }

    var title: String { "Sesión \(number)" }

    var notes: [SessionNote] {
        get { Self.decode(notesData) }
        set { notesData = Self.encode(newValue) }
    }

    var players: [Player] {
        get { Self.decode(playersData) }
        set { playersData = Self.encode(newValue) }
    }

    var chat: [TutorMessage] {
        get { Self.decode(chatData) }
        set { chatData = Self.encode(newValue) }
    }

    private static func decode<T: Decodable>(_ data: Data) -> [T] {
        guard !data.isEmpty else { return [] }
        return (try? JSONDecoder().decode([T].self, from: data)) ?? []
    }

    private static func encode<T: Encodable>(_ value: [T]) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }
}
