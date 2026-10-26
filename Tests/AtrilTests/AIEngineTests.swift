import Foundation
import Testing
@testable import Atril

struct ChunkerTests {
    @Test func detectsHeadings() {
        #expect(ScriptChunker.isHeading("## 3. La parroquia de San Telmo"))
        #expect(ScriptChunker.isHeading("4. El faro de Punta Negra"))
        #expect(ScriptChunker.isHeading("CAPÍTULO DOS"))
        #expect(ScriptChunker.isHeading("Escena 5: el sótano"))
        #expect(!ScriptChunker.isHeading("Los investigadores llegan al pueblo."))
        #expect(!ScriptChunker.isHeading("PV 10."))
    }

    @Test func splitsSampleIntoSections() {
        let sections = ScriptChunker.sections(SampleAdventure.script)
        let headings = sections.map(\.heading)
        #expect(headings.contains("1. Llegada a Portuxe"))
        #expect(headings.contains("6. La pleamar"))
        #expect(headings.contains("Estadísticas"))
    }

    @Test func chunksRespectWordLimit() {
        let chunks = ScriptChunker.chunks(SampleAdventure.script, maxWords: 250)
        #expect(chunks.count > 3)
        for chunk in chunks {
            // Una sección se puede pasar un poco, pero nunca el doble.
            #expect(chunk.text.split(whereSeparator: \.isWhitespace).count < 500)
        }
        let joined = chunks.map(\.text).joined(separator: " ")
        #expect(joined.contains("Xuacu") && joined.contains("Profundo"))
    }
}

struct IndexTests {
    @Test func findsRelevantPassage() {
        let index = ScriptIndex(script: SampleAdventure.script)
        let results = index.search("¿Qué pasa si tocan la piedra verdosa de la cueva?", limit: 2)
        #expect(results.first?.heading == "5. Las cuevas de la marea")
        #expect(index.search("registro parroquial 1824", limit: 1).first?.heading == "3. La parroquia de San Telmo")
    }

    @Test func stemmingJoinsPlurals() {
        #expect(ScriptIndex.stem("pistas") == ScriptIndex.stem("pista"))
        #expect(ScriptIndex.stem("faroles") == ScriptIndex.stem("farol"))
        #expect(ScriptIndex.stem("investigadores") == ScriptIndex.stem("investigadora"))
    }
}

struct HeuristicTests {
    @Test func organizesSampleWithoutModel() {
        let guide = HeuristicAnalyzer.analyze(script: SampleAdventure.script, system: .cthulhu)
        let titles = guide.scenes.map(\.title)
        #expect(titles.first == "Llegada a Portuxe")
        #expect(titles.contains("La pleamar"))
        // El trasfondo, el gancho, los desenlaces y las estadísticas no son escenas.
        #expect(!titles.contains { $0.contains("Trasfondo") || $0.contains("Estadísticas") || $0.contains("Desenlaces") })
        #expect(guide.truth.contains("1824"))
        #expect(guide.hook.contains("Elvira"))
        #expect(guide.endings.count == 3)

        let taberna = guide.scenes.first { $0.title.contains("taberna") }
        #expect(taberna?.readAloud.hasPrefix("Humo de pipa") == true)
        #expect(taberna?.checks.contains { $0.skill == "Persuasión" } == true)
        #expect(taberna?.checks.contains { $0.skill == "Cordura" && $0.difficulty == "0/1" } == true)

        let parroquia = guide.scenes.first { $0.title.contains("parroquia") }
        #expect(parroquia?.checks.contains { $0.skill == "Buscar libros" && $0.difficulty == "Difícil" } == true)
        // Las salidas apuntan a escenas que existen.
        let ids = Set(guide.scenes.map(\.id))
        #expect(guide.scenes.flatMap(\.exits).allSatisfy { ids.contains($0.sceneID) })
    }

    @Test func findsCharacters() {
        let guide = HeuristicAnalyzer.analyze(script: SampleAdventure.script, system: .cthulhu)
        let names = guide.npcs.map(\.name)
        #expect(names.contains { $0.contains("Marina") })
        #expect(names.contains { $0.contains("Xuacu") })
    }

    @Test func worksOnUnstructuredText() {
        let script = "Los aventureros llegan a la cripta. Una tirada de Percepción CD 15 revela una trampa. Al fondo, un esqueleto ataca."
        let guide = HeuristicAnalyzer.analyze(script: script, system: .dnd)
        #expect(guide.scenes.count == 1)
        #expect(guide.scenes[0].checks.first?.difficulty == "CD 15")
    }
}

struct MergerTests {
    @Test func mergesDuplicatedCharactersAndScenes() {
        let chunks = [
            DraftChunk(scenes: [DraftScene(title: "El faro", summary: "Llegan.", characterNames: ["Marina"])],
                       characters: [DraftCharacter(name: "Marina", role: "Hija del farero")]),
            DraftChunk(scenes: [DraftScene(title: "El faro", summary: "Suben a la linterna.",
                                           clues: [DraftClue(title: "La lente sellada")])],
                       characters: [DraftCharacter(name: "Marina Rivas", secret: "Oye el canto"), DraftCharacter(name: "Don Ramiro")]),
            DraftChunk(scenes: [DraftScene(title: "La cueva", characterNames: ["Ramiro"])]),
        ]
        let guide = GuideMerger.merge(
            chunks: chunks,
            overview: DraftOverview(premise: "P", coreClues: ["la lente sellada"]),
            links: [DraftLink(from: "La cueva", to: "El faro", condition: "Si suben")],
            system: .cthulhu
        )
        #expect(guide.scenes.count == 2)
        #expect(guide.scenes[0].summary == "Llegan. Suben a la linterna.")
        #expect(guide.npcs.count == 2)
        #expect(guide.npcs[0].name == "Marina Rivas")
        #expect(guide.npcs[0].secret == "Oye el canto")
        #expect(guide.scenes[1].npcIDs == [guide.npcs[1].id])
        #expect(guide.clues.first?.isCore == true)
        #expect(guide.clues.first?.sceneID == "e1")
        #expect(guide.scenes[0].exits.first?.sceneID == "e2")
        #expect(guide.scenes[1].exits.first?.condition == "Si suben")
    }

    @Test func namesMatchIgnoringHonorifics() {
        #expect(Prose.sameName("Don Ramiro", "Ramiro"))
        #expect(Prose.sameName("la doctora Elvira Cueto", "Elvira Cueto"))
        #expect(!Prose.sameName("Marina Rivas", "Anselmo Rivas"))
    }
}

struct PlannerTests {
    @Test func splitsAdventureIntoSessions() {
        let guide = SampleAdventure.guide
        let total = SessionPlanner.totalMinutes(guide)
        #expect(total > 90 && total < 300)
        let long = SessionPlanner.plan(guide, hours: 6)
        #expect(long.count == 1)
        let short = SessionPlanner.plan(guide, hours: 1.5)
        #expect(short.count > 1)
        #expect(short.flatMap(\.sceneIDs) == guide.scenes.map(\.id))
    }

    @Test func combatScenesTakeLonger() {
        let guide = SampleAdventure.guide
        let finale = SessionPlanner.minutes(for: guide.scene("e6")!)
        let arrival = SessionPlanner.minutes(for: guide.scene("e1")!)
        #expect(finale > arrival)
    }
}

struct CoachTests {
    private func state(_ change: (inout Coach.State) -> Void = { _ in }) -> Coach.State {
        var value = Coach.State(
            system: .cthulhu, guide: SampleAdventure.guide, sceneID: "e4", timeInScene: 300, sessionElapsed: 3600,
            sessionHours: 3, players: [], sanityAtSceneStart: [:], minutesSinceLastNote: 5, leftBehind: []
        )
        change(&value)
        return value
    }

    @Test func warnsAboutForgottenCoreClue() {
        let clue = SampleAdventure.guide.clue("p3")!
        let hints = Coach.hints(state { $0.leftBehind = [clue] })
        #expect(hints.first?.title == "Se dejaron una pista clave")
        #expect(hints.first?.message.contains("Registro de 1824") == true)
    }

    @Test func warnsWhenSceneDragsOn() {
        #expect(Coach.hints(state { $0.timeInScene = 90 * 60 }).contains { $0.title == "Esta escena se alarga" })
        #expect(!Coach.hints(state()).contains { $0.title == "Esta escena se alarga" })
    }

    @Test func remindsSanityRules() {
        let player = Player(name: "Ana", character: "Lucía", hp: 10, hpMax: 11, sanity: 40)
        let hints = Coach.hints(state {
            $0.players = [player]
            $0.sanityAtSceneStart = [player.id: 47]
        })
        #expect(hints.contains { $0.title == "Lucía ha perdido 7 de Cordura" })
    }

    @Test func announcesEndOfSession() {
        #expect(Coach.hints(state { $0.sessionElapsed = 2.8 * 3600 }).contains { $0.id.hasPrefix("ending") })
    }
}

struct BasicTutorTests {
    private var table: TableSnapshot {
        let state = TutorPrompts.TableState(
            system: .cthulhu, guide: SampleAdventure.guide, playTime: 3600, currentSceneID: "e4",
            visitedSceneIDs: ["e1", "e2", "e4"], foundClueIDs: ["p1", "p2"], players: [], notes: []
        )
        return TableSnapshot(title: SampleAdventure.title, system: .cthulhu, guide: SampleAdventure.guide,
                             state: state, index: ScriptIndex(script: SampleAdventure.script), recent: [])
    }

    @Test func quickActionsMapToIntents() {
        let intents = QuickAction.all.map { BasicTutor.intent(of: $0.prompt) }
        #expect(intents == [.next, .stuck, .offScript, .describe, .npc, .roll, .tension, .rule])
    }

    @Test func nextStepUsesTheScene() {
        let answer = BasicTutor.answer("¿Qué hago ahora?", table: table, seed: 1)
        #expect(answer.contains("El faro de Punta Negra"))
        #expect(answer.contains("La lente sellada"))
    }

    @Test func stuckOffersPendingCoreClue() {
        let answer = BasicTutor.answer("Están atascados", table: table, seed: 1)
        #expect(answer.contains("Registro de 1824") || answer.contains("La lente sellada"))
    }

    @Test func rulesReference() {
        #expect(BasicTutor.answer("Duda de reglas: ¿cómo funciona forzar una tirada?", table: table).contains("Forzar"))
        #expect(BasicTutor.rule("salvaciones contra muerte", system: .dnd).contains("Caer a 0 PV"))
    }

    @Test func freeQuestionSearchesTheScript() {
        let answer = BasicTutor.answer("¿Cuántos Profundos salen del agua?", table: table)
        #expect(answer.contains("Profundo"))
    }

    @Test func contextPromptStaysCompact() {
        let prompt = TutorContext.prompt(question: "¿Qué hago si suben a la linterna?", table: table, passages: 4, generous: false)
        let words = prompt.split(whereSeparator: \.isWhitespace).count
        #expect(words < 1500)
        #expect(prompt.contains("## Escena actual: El faro de Punta Negra"))
        #expect(prompt.contains("## Fragmentos del guion relacionados"))
        // Sin identificadores internos y con la escena de cada pista clave pendiente.
        #expect(!prompt.contains("Escena actual: e4"))
        #expect(prompt.contains("Registro de 1824 (en «La parroquia de San Telmo»)"))
    }
}

struct AppleErrorTests {
    @Test func recognizesContextOverflowMessage() {
        let error = NSError(domain: "FoundationModels.LanguageModelError", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "Content contains 8193 tokens, which exceeds the maximum allowed context size of 8192.",
        ])
        guard case .contextTooLarge = AppleAI.Failure.classify(error) else {
            Issue.record("No se reconoció el desbordamiento de contexto")
            return
        }
    }

    @Test func cloudStaysOffWithoutEntitlement() {
        #expect(!AppleAI.cloudEntitled)
        #expect(!AppleAI.status.tiers.contains(.cloud))
    }
}

struct SanitizerTests {
    @Test func detectsSchemaJunkTitles() {
        #expect(Prose.isSchemaJunk("#/$defs/SceneExtraction"))
        #expect(Prose.isSchemaJunk("SceneExtraction"))
        #expect(!Prose.isSchemaJunk("La taberna de la Remedios"))
        #expect(!Prose.isSchemaJunk("Llegada a Portuxe"))
    }

    @Test func detectsPlaceholderValues() {
        #expect(Prose.isPlaceholder("Qué quiere, en pocas palabras"))
        #expect(Prose.isPlaceholder("Lo que oculta; vacío si nada"))
        #expect(Prose.isPlaceholder("Vacío"))
        #expect(Prose.isPlaceholder("No oculta nada"))
        #expect(!Prose.isPlaceholder("Que la luz vuelva a girar"))
        #expect(Prose.useful("  Proteger a su hija ") == "Proteger a su hija")
    }
}
