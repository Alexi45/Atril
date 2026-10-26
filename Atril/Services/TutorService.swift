import Foundation
import SwiftUI

/// Profundidad de razonamiento del tutor. En mesa suele importar más la rapidez.
enum TutorDepth: String, CaseIterable, Identifiable {
    case fast = "low"
    case balanced = "medium"
    case deep = "high"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fast: "Rápido"
        case .balanced: "Equilibrado"
        case .deep: "A fondo"
        }
    }

    var detail: String {
        switch self {
        case .fast: "Respuestas en pocos segundos. Ideal en mesa."
        case .balanced: "Piensa un poco más antes de responder."
        case .deep: "Para preparar sesiones o dudas complicadas."
        }
    }

    static let storageKey = "tutorDepth"
    static var current: TutorDepth {
        TutorDepth(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .fast
    }
}

enum TutorService {
    /// Convierte el guion en una guía estructurada. Llama a `progress` con el número
    /// de escenas detectadas mientras llega la respuesta.
    static func analyze(
        title: String,
        script: String,
        system: GameSystem,
        progress: @escaping @MainActor (Int) -> Void
    ) async throws -> AdventureGuide {
        let body: JSONValue = [
            "model": .string(ClaudeClient.model),
            "max_tokens": 64000,
            "thinking": ["type": "adaptive"],
            "output_config": [
                "effort": "high",
                "format": ["type": "json_schema", "schema": AdventureGuide.jsonSchema],
            ],
            "fallbacks": "default",
            "system": .string(TutorPrompts.analysisSystem(system)),
            "messages": [
                ["role": "user", "content": .string(TutorPrompts.analysisRequest(title: title, script: script))],
            ],
        ]

        let client = ClaudeClient(apiKey: KeychainStore.apiKey)
        var json = ""
        var lastCount = 0
        for try await event in client.stream(body) {
            switch event {
            case .textDelta(let delta):
                json += delta
                let count = json.components(separatedBy: "\"readAloud\"").count - 1
                if count != lastCount {
                    lastCount = count
                    await progress(count)
                }
            case .thinking:
                break
            case .finished(let response):
                if response.stopReason == "max_tokens" { throw ClaudeClient.Failure.truncated }
                json = response.text
            }
        }
        guard let data = json.data(using: .utf8) else { throw ClaudeClient.Failure.badRequest("Respuesta vacía") }
        do {
            return try JSONDecoder().decode(AdventureGuide.self, from: data)
        } catch {
            throw ClaudeClient.Failure.badRequest("La guía recibida no tiene el formato esperado.")
        }
    }

    /// Construye la petición del tutor. El prompt de sistema (instrucciones + guion) es fijo
    /// para toda la partida y lleva un punto de caché de 1 h; la conversación usa la caché
    /// automática. El historial solo crece por el final.
    static func chatBody(adventure: Adventure, history: [TutorMessage], depth: TutorDepth) -> JSONValue {
        [
            "model": .string(ClaudeClient.model),
            "max_tokens": 16000,
            "thinking": ["type": "adaptive"],
            "output_config": ["effort": .string(depth.rawValue)],
            "fallbacks": "default",
            "cache_control": ["type": "ephemeral"],
            "system": [
                ["type": "text", "text": .string(TutorPrompts.tutorSystem(adventure.system))],
                [
                    "type": "text",
                    "text": .string(TutorPrompts.scriptContext(title: adventure.title, script: adventure.script, guide: adventure.guide)),
                    "cache_control": ["type": "ephemeral", "ttl": "1h"],
                ],
            ],
            "messages": .array(history.map(\.apiMessage)),
        ]
    }

    /// Quita los bloques de razonamiento de las respuestas anteriores. Solo se usa como
    /// recuperación puntual cuando el contexto ha cambiado (p. ej. se editó el guion).
    static func strippingThinking(_ history: [TutorMessage]) -> [TutorMessage] {
        history.map { message in
            guard message.role == .assistant, case .array(let blocks) = message.content else { return message }
            var copy = message
            copy.content = .array(blocks.filter {
                let type = $0["type"]?.stringValue
                return type != "thinking" && type != "redacted_thinking"
            })
            return copy
        }
    }

    /// Petición mínima para comprobar que la clave funciona.
    static func testConnection(apiKey: String) async throws {
        let body: JSONValue = [
            "model": .string(ClaudeClient.model),
            "max_tokens": 1024,
            "output_config": ["effort": "low"],
            "messages": [["role": "user", "content": "Responde solo: OK"]],
        ]
        for try await _ in ClaudeClient(apiKey: apiKey).stream(body, betas: []) {}
    }
}
