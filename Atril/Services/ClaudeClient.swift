import Foundation

/// Cliente mínimo de la API de Mensajes de Anthropic (HTTP + SSE).
/// Swift no tiene SDK oficial, así que se habla con `/v1/messages` directamente.
struct ClaudeClient: Sendable {
    static let model = "claude-opus-5-5"
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    /// Si los clasificadores de seguridad rechazan una petición, la API la repite
    /// en el modelo de respaldo recomendado en lugar de devolver el rechazo.
    static let fallbackBeta = "server-side-fallback-2026-07-01"

    let apiKey: String
    var session: URLSession = .shared

    enum Event: Sendable {
        case textDelta(String)
        case thinking
        case finished(Response)
    }

    struct Response: Sendable {
        /// Bloques de contenido completos, tal como hay que reenviarlos en el historial.
        var content: [JSONValue]
        var stopReason: String?
        var inputTokens = 0
        var outputTokens = 0
        var cacheReadTokens = 0
        var cacheWriteTokens = 0

        var text: String {
            content.compactMap { block in
                block["type"]?.stringValue == "text" ? block["text"]?.stringValue : nil
            }.joined()
        }
    }

    enum Failure: LocalizedError, Equatable {
        case missingKey
        case invalidKey
        case rateLimited
        case overloaded
        case refused
        case truncated
        case interrupted
        case badRequest(String)
        case server(Int, String)
        case network(String)

        var errorDescription: String? {
            switch self {
            case .missingKey: "Añade tu clave de Anthropic en Ajustes para usar el tutor."
            case .invalidKey: "La clave de Anthropic no es válida. Revísala en Ajustes."
            case .rateLimited: "Has alcanzado el límite de peticiones. Espera unos segundos y repite."
            case .overloaded: "El servicio está saturado ahora mismo. Vuelve a intentarlo en un momento."
            case .refused: "El tutor no puede responder a esa petición. Prueba a formularla de otra manera."
            case .truncated: "La respuesta se ha cortado por longitud. Prueba con un guion más corto o pide menos detalle."
            case .interrupted: "La respuesta se ha interrumpido a medias. Vuelve a intentarlo."
            case .badRequest(let message): "Petición rechazada: \(message)"
            case .server(let code, let message): "Error del servidor (\(code)): \(message)"
            case .network(let message): "Sin conexión con el tutor: \(message)"
            }
        }

        var isRetryable: Bool {
            switch self {
            case .rateLimited, .overloaded, .server, .network: true
            default: false
            }
        }
    }

    /// Envía una petición en streaming. `body` no debe incluir `stream`; se añade aquí.
    func stream(_ body: JSONValue, betas: [String] = [fallbackBeta]) -> AsyncThrowingStream<Event, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var attempt = 0
                    while true {
                        do {
                            try await run(body, betas: betas, continuation: continuation)
                            break
                        } catch let failure as Failure where failure.isRetryable && attempt < 2 {
                            // `run` convierte en `.interrupted` (no reintentable) cualquier fallo
                            // que llegue después de haber emitido texto, para no duplicarlo.
                            attempt += 1
                            try await Task.sleep(for: .seconds(Double(attempt) * 2))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(
        _ body: JSONValue,
        betas: [String],
        continuation: AsyncThrowingStream<Event, Error>.Continuation
    ) async throws {
        guard !apiKey.isEmpty else { throw Failure.missingKey }

        var payload = body
        payload["stream"] = true
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if !betas.isEmpty {
            request.setValue(betas.joined(separator: ","), forHTTPHeaderField: "anthropic-beta")
        }
        request.httpBody = try payload.encoded()

        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Failure.network(error.localizedDescription)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            var data = Data()
            for try await byte in bytes { data.append(byte) }
            throw Self.failure(status: status, body: data)
        }

        var accumulator = MessageAccumulator()
        var emittedText = false
        do {
            for try await line in bytes.lines {
                guard line.hasPrefix("data:") else { continue }
                let json = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                guard let data = json.data(using: .utf8), let event = try? JSONValue.decode(data) else { continue }
                switch try accumulator.apply(event) {
                case .text(let delta):
                    emittedText = true
                    continuation.yield(.textDelta(delta))
                case .thinking: continuation.yield(.thinking)
                case .none: break
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as Failure {
            throw emittedText ? Failure.interrupted : failure
        } catch {
            throw emittedText ? Failure.interrupted : Failure.network(error.localizedDescription)
        }

        let result = accumulator.response
        if result.stopReason == "refusal" { throw Failure.refused }
        if result.stopReason == "max_tokens" && result.text.isEmpty { throw Failure.truncated }
        continuation.yield(.finished(result))
    }

    static func failure(status: Int, body: Data) -> Failure {
        let json = try? JSONValue.decode(body)
        let message = json?["error"]?["message"]?.stringValue ?? String(decoding: body, as: UTF8.self)
        switch status {
        case 401, 403: return .invalidKey
        case 429: return .rateLimited
        case 529: return .overloaded
        case 400, 404, 413, 422: return .badRequest(message)
        default: return .server(status, message)
        }
    }
}

/// Reconstruye los bloques de contenido a partir de los eventos SSE.
struct MessageAccumulator {
    enum Delta: Equatable { case text(String), thinking }

    private(set) var response = ClaudeClient.Response(content: [])

    mutating func apply(_ event: JSONValue) throws -> Delta? {
        switch event["type"]?.stringValue {
        case "message_start":
            let usage = event["message"]?["usage"]
            response.inputTokens = usage?["input_tokens"]?.intValue ?? 0
            response.cacheReadTokens = usage?["cache_read_input_tokens"]?.intValue ?? 0
            response.cacheWriteTokens = usage?["cache_creation_input_tokens"]?.intValue ?? 0
            return nil

        case "content_block_start":
            guard let index = event["index"]?.intValue, let block = event["content_block"] else { return nil }
            while response.content.count <= index { response.content.append(.object([:])) }
            response.content[index] = block
            return block["type"]?.stringValue == "thinking" ? .thinking : nil

        case "content_block_delta":
            guard let index = event["index"]?.intValue, index < response.content.count,
                  let delta = event["delta"] else { return nil }
            var block = response.content[index]
            defer { response.content[index] = block }
            switch delta["type"]?.stringValue {
            case "text_delta":
                let text = delta["text"]?.stringValue ?? ""
                block["text"] = .string((block["text"]?.stringValue ?? "") + text)
                return .text(text)
            case "thinking_delta":
                block["thinking"] = .string((block["thinking"]?.stringValue ?? "") + (delta["thinking"]?.stringValue ?? ""))
                return .thinking
            case "signature_delta":
                block["signature"] = delta["signature"]
                return nil
            case "citations_delta":
                if let citation = delta["citation"] {
                    block["citations"] = .array((block["citations"]?.arrayValue ?? []) + [citation])
                }
                return nil
            default:
                return nil
            }

        case "message_delta":
            if let reason = event["delta"]?["stop_reason"]?.stringValue { response.stopReason = reason }
            if let output = event["usage"]?["output_tokens"]?.intValue { response.outputTokens = output }
            return nil

        case "error":
            let type = event["error"]?["type"]?.stringValue ?? ""
            let message = event["error"]?["message"]?.stringValue ?? "Error desconocido"
            switch type {
            case "overloaded_error": throw ClaudeClient.Failure.overloaded
            case "rate_limit_error": throw ClaudeClient.Failure.rateLimited
            default: throw ClaudeClient.Failure.server(0, message)
            }

        default:
            return nil
        }
    }
}
