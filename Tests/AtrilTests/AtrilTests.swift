import Foundation
import Testing
@testable import Atril

/// Generador de dados con resultados fijos, en orden.
private func fixed(_ values: [Int]) -> Dice {
    var queue = values
    return Dice(roll: { _ in queue.removeFirst() })
}

struct DiceTests {
    @Test func cthulhuGrades() {
        #expect(Dice.grade(1, skill: 50) == .critical)
        #expect(Dice.grade(10, skill: 50) == .extreme)
        #expect(Dice.grade(25, skill: 50) == .hard)
        #expect(Dice.grade(50, skill: 50) == .regular)
        #expect(Dice.grade(51, skill: 50) == .failure)
        #expect(Dice.grade(99, skill: 50) == .failure)
        #expect(Dice.grade(100, skill: 50) == .fumble)
        // Con habilidad menor de 50, la pifia empieza en 96.
        #expect(Dice.grade(96, skill: 40) == .fumble)
        #expect(Dice.grade(95, skill: 40) == .failure)
    }

    @Test func percentileUsesBestTensWithBonus() {
        // unidades 5 (d10=6), decenas 70 y 20 → con bonificación se queda con 25
        let result = fixed([6, 8, 3]).percentile(skill: 30, bonus: 1)
        #expect(result.value == 25)
        #expect(result.result == .regular)
    }

    @Test func percentileUsesWorstTensWithPenalty() {
        let result = fixed([6, 8, 3]).percentile(skill: 30, bonus: -1)
        #expect(result.value == 75)
        #expect(result.result == .failure)
    }

    @Test func doubleZeroIsHundred() {
        // unidades 0 y decenas 00 → 100
        #expect(fixed([1, 1]).percentile(skill: 60).value == 100)
    }

    @Test func d20Advantage() {
        #expect(fixed([4, 17]).d20(modifier: 3, advantage: .advantage).total == 20)
        #expect(fixed([4, 17]).d20(modifier: 3, advantage: .disadvantage).total == 7)
        #expect(fixed([12]).d20(modifier: -1, advantage: .normal).natural == 12)
    }

    @Test func pool() {
        let result = fixed([2, 5, 6]).roll(Dice.Pool(count: 3, sides: 6, modifier: 1))
        #expect(result.total == 14)
        #expect(Dice.Pool(count: 1, sides: 100, modifier: -2).label == "1d100-2")
    }
}

struct StreamTests {
    private func event(_ json: String) throws -> JSONValue {
        try JSONValue.decode(Data(json.utf8))
    }

    @Test func rebuildsThinkingAndTextBlocks() throws {
        var accumulator = MessageAccumulator()
        let events = [
            #"{"type":"message_start","message":{"usage":{"input_tokens":12,"cache_read_input_tokens":3000}}}"#,
            #"{"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"abc"}}"#,
            #"{"type":"content_block_stop","index":0}"#,
            #"{"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}"#,
            #"{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Hola, "}}"#,
            #"{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"máster"}}"#,
            #"{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":40}}"#,
        ]
        var deltas: [MessageAccumulator.Delta] = []
        for raw in events {
            if let delta = try accumulator.apply(try event(raw)) { deltas.append(delta) }
        }
        let response = accumulator.response
        #expect(response.text == "Hola, máster")
        #expect(response.stopReason == "end_turn")
        #expect(response.cacheReadTokens == 3000)
        #expect(response.content[0]["signature"]?.stringValue == "abc")
        #expect(response.content[0]["type"]?.stringValue == "thinking")
        #expect(deltas.contains(.text("máster")))
    }

    @Test func errorEventThrows() throws {
        var accumulator = MessageAccumulator()
        #expect(throws: ClaudeClient.Failure.overloaded) {
            try accumulator.apply(try event(#"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#))
        }
    }

    @Test func httpErrorsMapToFriendlyFailures() {
        let body = Data(#"{"type":"error","error":{"type":"invalid_request_error","message":"bad"}}"#.utf8)
        #expect(ClaudeClient.failure(status: 401, body: body) == .invalidKey)
        #expect(ClaudeClient.failure(status: 400, body: body) == .badRequest("bad"))
        #expect(ClaudeClient.failure(status: 529, body: body).isRetryable)
    }
}

struct PromptTests {
    @Test func sampleGuideIsConsistent() throws {
        let guide = SampleAdventure.guide
        let sceneIDs = Set(guide.scenes.map(\.id))
        let npcIDs = Set(guide.npcs.map(\.id))
        let clueIDs = Set(guide.clues.map(\.id))
        for scene in guide.scenes {
            #expect(scene.npcIDs.allSatisfy(npcIDs.contains), "PNJ inexistente en \(scene.id)")
            #expect(scene.clueIDs.allSatisfy(clueIDs.contains), "Pista inexistente en \(scene.id)")
            #expect(scene.exits.allSatisfy { sceneIDs.contains($0.sceneID) }, "Salida rota en \(scene.id)")
        }
        // Ida y vuelta por JSON, como se guarda en SwiftData.
        let data = try JSONEncoder().encode(guide)
        #expect(try JSONDecoder().decode(AdventureGuide.self, from: data) == guide)
    }

    @Test func schemaRequiresEveryProperty() {
        func check(_ schema: JSONValue) {
            if schema["type"]?.stringValue == "object", case .object(let properties)? = schema["properties"] {
                let required = Set(schema["required"]?.arrayValue?.compactMap(\.stringValue) ?? [])
                #expect(required == Set(properties.keys))
                #expect(schema["additionalProperties"] == .bool(false))
                properties.values.forEach(check)
            }
            if let items = schema["items"] { check(items) }
        }
        check(AdventureGuide.jsonSchema)
    }

    @Test func stateBlockSummarisesTheTable() {
        let guide = SampleAdventure.guide
        let state = TutorPrompts.TableState(
            system: .cthulhu, guide: guide, playTime: 3900, currentSceneID: "e4",
            visitedSceneIDs: ["e1", "e2", "e4"], foundClueIDs: ["p1"],
            players: [Player(name: "Ana", character: "Lucía", hp: 9, hpMax: 11, sanity: 50)],
            notes: [SessionNote(playTime: 120, text: "Llegan al pueblo")]
        )
        let block = TutorPrompts.stateBlock(state)
        #expect(block.contains("Escena actual: e4 · El faro de Punta Negra"))
        #expect(block.contains("Escenas ya jugadas: e1, e2"))
        #expect(block.contains("Pistas clave pendientes: p3"))
        #expect(block.contains("Lucía (Ana) PV 9/11, COR 50"))
        #expect(block.contains("[2 min] Llegan al pueblo"))
        #expect(block.contains("1 h 05 min"))
    }

    @Test func chatBodyCachesTheScript() throws {
        let adventure = Adventure(title: "Prueba", system: .dnd, script: "Guion de prueba")
        let history = [TutorMessage(role: .user, display: "Hola", content: "Hola")]
        let body = TutorService.chatBody(adventure: adventure, history: history, depth: .fast)
        let system = try #require(body["system"]?.arrayValue)
        #expect(system.count == 2)
        #expect(system[1]["cache_control"]?["ttl"]?.stringValue == "1h")
        #expect(system[1]["text"]?.stringValue?.contains("Guion de prueba") == true)
        #expect(body["fallbacks"]?.stringValue == "default")
        #expect(body["output_config"]?["effort"]?.stringValue == "low")
        #expect(body["messages"]?.arrayValue?.count == 1)
        // Peticiones idénticas producen bytes idénticos (caché de prompts).
        #expect(try body.encoded() == TutorService.chatBody(adventure: adventure, history: history, depth: .fast).encoded())
    }

    @Test func strippingThinkingKeepsText() {
        let answer = TutorMessage(role: .assistant, display: "ok", content: [
            ["type": "thinking", "thinking": "", "signature": "x"],
            ["type": "text", "text": "ok"],
        ])
        let stripped = TutorService.strippingThinking([answer])
        #expect(stripped[0].content.arrayValue?.count == 1)
        #expect(stripped[0].content.arrayValue?.first?["type"]?.stringValue == "text")
    }
}
