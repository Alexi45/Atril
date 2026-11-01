import CoreTransferable
import Foundation
import SwiftData
import UniformTypeIdentifiers

extension UTType {
    /// Archivo de aventura de Atril: guion, guía, sesiones y retratos en un solo JSON.
    static let atrilAdventure = UTType(exportedAs: "com.alejandroriscart.atril.adventure", conformingTo: .json)
}

/// Copia completa de una aventura para pasarla a otro dispositivo (AirDrop, Archivos) o
/// guardarla. Es JSON legible para que siga sirviendo aunque cambie la app.
struct AdventureArchive: Codable {
    static let currentVersion = 1

    var version = currentVersion
    var exportedAt = Date()
    var title: String
    var system: GameSystem
    var script: String
    var sourceFileName: String?
    var guide: AdventureGuide?
    var guideEngine: String?
    var prepDone: [String]
    var sessionHours: Double
    var sessions: [Session]
    var portraits: [String: Data]

    struct Session: Codable {
        var number: Int
        var startedAt: Date
        var lastPlayedAt: Date
        var elapsed: TimeInterval
        var currentSceneID: String?
        var visitedSceneIDs: [String]
        var foundClueIDs: [String]
        var notes: [SessionNote]
        var players: [Player]
        var chat: [TutorMessage]
        var playerSummary: String?
        var recap: String?
        var combat: Combat?
    }

    enum Failure: LocalizedError {
        case unreadable
        case newerVersion

        var errorDescription: String? {
            switch self {
            case .unreadable: "El archivo no es una aventura de Atril válida."
            case .newerVersion: "La aventura se exportó con una versión más reciente de Atril. Actualiza la app para abrirla."
            }
        }
    }

    init(_ adventure: Adventure) {
        title = adventure.title
        system = adventure.system
        script = adventure.script
        sourceFileName = adventure.sourceFileName
        guide = adventure.guide
        guideEngine = adventure.guideEngine
        prepDone = adventure.prepDone
        sessionHours = adventure.sessionHours
        sessions = adventure.sessions.sorted { $0.number < $1.number }.map { session in
            Session(
                number: session.number, startedAt: session.startedAt, lastPlayedAt: session.lastPlayedAt,
                elapsed: session.elapsed, currentSceneID: session.currentSceneID,
                visitedSceneIDs: session.visitedSceneIDs, foundClueIDs: session.foundClueIDs,
                notes: session.notes, players: session.players, chat: session.chat,
                playerSummary: session.playerSummary, recap: session.recap,
                combat: try? JSONDecoder().decode(Combat.self, from: session.combatData)
            )
        }
        portraits = Dictionary(adventure.portraits.map { ($0.npcName, $0.imageData) }, uniquingKeysWith: { first, _ in first })
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> AdventureArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // Primero solo la versión: un archivo de una versión futura puede no encajar en el esquema.
        struct Header: Decodable { var version: Int }
        guard let header = try? decoder.decode(Header.self, from: data) else { throw Failure.unreadable }
        guard header.version <= currentVersion else { throw Failure.newerVersion }
        do {
            return try decoder.decode(AdventureArchive.self, from: data)
        } catch {
            throw Failure.unreadable
        }
    }

    /// Crea la aventura en la base de datos. Si ya hay una con el mismo título, se añade
    /// «(importada)» para no confundirlas.
    @discardableResult
    func restore(into context: ModelContext, existingTitles: Set<String>) -> Adventure {
        let name = existingTitles.contains(title) ? "\(title) (importada)" : title
        let adventure = Adventure(title: name, system: system, script: script, sourceFileName: sourceFileName)
        context.insert(adventure)
        adventure.guide = guide
        adventure.guideEngine = guideEngine
        adventure.prepDone = prepDone
        adventure.sessionHours = sessionHours
        for item in sessions {
            let session = PlaySession(number: item.number, adventure: adventure)
            context.insert(session)
            session.startedAt = item.startedAt
            session.lastPlayedAt = item.lastPlayedAt
            session.elapsed = item.elapsed
            session.currentSceneID = item.currentSceneID
            session.visitedSceneIDs = item.visitedSceneIDs
            session.foundClueIDs = item.foundClueIDs
            session.notes = item.notes
            session.players = item.players
            session.chat = item.chat
            session.playerSummary = item.playerSummary
            session.recap = item.recap
            session.combatData = item.combat.flatMap { try? JSONEncoder().encode($0) } ?? Data()
        }
        for (name, data) in portraits {
            adventure.setPortrait(data, for: name)
        }
        return adventure
    }

    static func fileName(for title: String) -> String {
        let safe = title.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: "-")
        return safe.isEmpty ? "Aventura" : safe
    }
}

/// Para compartir con AirDrop, Mensajes o Archivos desde un `ShareLink`.
struct AdventureFile: Transferable {
    let archive: Data
    let title: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .atrilAdventure) { $0.archive }
            .suggestedFileName { "\(AdventureArchive.fileName(for: $0.title)).atril" }
    }
}
