import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Atril

struct EnemyCandidateTests {
    @Test func findsCthulhuStatLines() {
        let candidates = StatBlock.candidates(in: SampleAdventure.script)
        let deepOne = candidates.first { $0.name == "Profundo" }
        #expect(deepOne?.stats.hp == 13)
        #expect(deepOne?.stats.dexterity == 50)
        #expect(candidates.contains { $0.name == "Marina Rivas" && $0.stats.hp == 10 })
    }

    @Test func findsDnDBlocksWithNameOnItsOwnLine() {
        let script = """
        ## Encuentro en el puente

        Goblin
        Clase de Armadura 15, Puntos de golpe 7 (2d6), DES 14 (+2)

        Los goblins atacan en cuanto ven a los aventureros, que deben tener 3 puntos de vida o más.
        """
        let goblin = StatBlock.candidates(in: script).first
        #expect(goblin?.name == "Goblin")
        #expect(goblin?.stats.hp == 7)
        #expect(goblin?.stats.armorClass == 15)
        #expect(goblin?.stats.initiativeBonus == 2)
    }

    @Test func proseWithPointsIsNotAnEnemyName() {
        let names = StatBlock.candidates(in: "Si el investigador cae a 0 PV 3 horas después, muere.").map(\.name)
        #expect(names.isEmpty)
    }
}

struct RandomTableTests {
    @Test(arguments: GameSystem.allCases)
    func everySystemHasUsefulTables(_ system: GameSystem) {
        let tables = RandomTables.tables(for: system)
        #expect(tables.count >= 3)
        #expect(tables.allSatisfy { $0.entries.count >= 5 })
        #expect(Set(tables.map(\.title)).count == tables.count)
    }

    @Test func tablesMatchTheGame() {
        #expect(RandomTables.tables(for: .cthulhu).contains { $0.title == "Ataque de locura" })
        #expect(RandomTables.tables(for: .dnd).contains { $0.title == "Botín menor" })
        #expect(!RandomTables.tables(for: .dnd).contains { $0.title == "Ataque de locura" })
    }

    @Test func rollsFromTheEntries() {
        let table = RandomTables.common[0]
        #expect(table.roll { _ in 0 } == table.entries[0])
        #expect(table.entries.contains(table.roll()))
    }
}

struct GuideEditingTests {
    @Test func editingCluesAddsChangesAndRemoves() {
        var guide = SampleAdventure.guide
        let scene = guide.scene("e4")!
        var clues = guide.clues(in: scene)
        #expect(clues.map(\.id) == ["p4", "p5"])
        clues[0].title = "La lente rota"
        clues.remove(at: 1)
        let id = guide.nextClueID(excluding: clues)
        #expect(id == "p7")
        clues.append(AdventureGuide.Clue(id: id, title: "Huellas mojadas", detail: "Suben del sótano.", sceneID: "e4", leadsTo: "", isCore: true))
        guide.setClues(clues, forScene: "e4")

        #expect(guide.clue("p4")?.title == "La lente rota")
        #expect(guide.clue("p5") == nil)
        #expect(guide.clue("p7")?.isCore == true)
        #expect(guide.scene("e4")?.clueIDs == ["p4", "p7"])
        #expect(guide.clues(in: guide.scene("e4")!).map(\.id) == ["p4", "p7"])
    }

    @Test func removingAnNPCLeavesNoDanglingReferences() {
        var guide = SampleAdventure.guide
        guide.removeNPC("n5")
        #expect(guide.npc("n5") == nil)
        #expect(!guide.scenes.contains { $0.npcIDs.contains("n5") })
        var npc = guide.blankNPC()
        #expect(npc.id == "n7")
        npc.name = "Teodoro"
        guide.upsert(npc)
        #expect(guide.npc("n7")?.name == "Teodoro")
    }
}

@MainActor
struct EditProtectionTests {
    private func adventure() throws -> (Adventure, ModelContainer) {
        let container = try ModelContainer(for: Adventure.self, PlaySession.self, Portrait.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return (SampleAdventure.make(in: container.mainContext, withSession: false), container)
    }

    @Test func manualEditsAreRecorded() throws {
        let (adventure, container) = try adventure()
        _ = container
        #expect(adventure.guideEditedAt == nil)
        adventure.editGuide { $0.scenes[0].title = "Nueva llegada" }
        #expect(adventure.guideEditedAt != nil)
        #expect(adventure.guide?.scenes[0].title == "Nueva llegada")
        #expect(adventure.guideEngine == "sample")
    }

    @Test func pendingGuideWaitsForADecision() throws {
        let (adventure, container) = try adventure()
        _ = container
        var ai = SampleAdventure.guide
        ai.scenes[0].title = "Título de la IA"
        adventure.editGuide { $0.scenes[0].title = "Título mío" }
        adventure.pendingGuideData = try JSONEncoder().encode(ai)
        adventure.pendingGuideEngine = "onDevice"

        let center = AnalysisCenter()
        center.discardPendingGuide(of: adventure)
        #expect(adventure.pendingGuideData == nil)
        #expect(adventure.guide?.scenes[0].title == "Título mío")

        adventure.pendingGuideData = try JSONEncoder().encode(ai)
        adventure.pendingGuideEngine = "onDevice"
        center.acceptPendingGuide(of: adventure)
        #expect(adventure.guide?.scenes[0].title == "Título de la IA")
        #expect(adventure.guideEngine == "onDevice")
        #expect(adventure.guideEditedAt == nil)
        #expect(adventure.pendingGuideData == nil)
    }

    @Test func renamingAnNPCKeepsItsPortrait() throws {
        let (adventure, container) = try adventure()
        _ = container
        adventure.setPortrait(Data([9]), for: "Marina Rivas")
        adventure.renamePortrait(from: "Marina Rivas", to: "Marina del Faro")
        #expect(adventure.portrait(for: "Marina del Faro") == Data([9]))
        #expect(adventure.portrait(for: "Anselmo Rivas") == nil)
    }
}

struct AppleBusyTests {
    @Test func recognizesTransientErrors() {
        for message in ["Rate limited, try later", "Too many concurrent requests", "App is in the background"] {
            let error = NSError(domain: "x", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
            guard case .busy = AppleAI.Failure.classify(error) else {
                Issue.record("No se reconoció como pasajero: \(message)")
                continue
            }
        }
    }
}

@MainActor
struct EnemyNumberingTests {
    @Test func addingTheSameEnemyAgainNumbersIt() throws {
        let container = try ModelContainer(for: Adventure.self, PlaySession.self, Portrait.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let adventure = SampleAdventure.make(in: container.mainContext, withSession: true)
        let controller = PlayController(session: adventure.sessions[0])
        #expect(controller.enemyCandidates.contains { $0.name == "Profundo" })
        let stats = StatBlock(hp: 13, dexterity: 50)
        controller.addEnemies(name: "Profundo", count: 1, stats: stats)
        controller.addEnemies(name: "Profundo", count: 1, stats: stats)
        controller.addEnemies(name: "Goblin", count: 2, stats: stats)
        let names = Set(controller.combat.combatants.map(\.name))
        #expect(names == ["Profundo", "Profundo 2", "Goblin 1", "Goblin 2"])
    }
}

@MainActor
struct DarkModeContrastTests {
    private func luminance(_ color: Color, in scheme: ColorScheme) -> Double {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        let resolved = color.resolve(in: environment)
        return 0.2126 * Double(resolved.linearRed) + 0.7152 * Double(resolved.linearGreen) + 0.0722 * Double(resolved.linearBlue)
    }

    private func contrast(_ first: Double, _ second: Double) -> Double {
        (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    @Test func accentsReadOnDarkCardsAndUnderWhiteText() {
        let card = luminance(.card, in: .dark)
        for system in GameSystem.allCases {
            let accent = luminance(system.accent, in: .dark)
            #expect(accent > luminance(system.accent, in: .light), "\(system.name) debe aclararse en oscuro")
            #expect(contrast(accent, card) >= 4.5, "\(system.name) sobre tarjeta")
            #expect(contrast(accent, 1) >= 3, "Texto blanco sobre \(system.name)")
        }
    }

    @Test func engineNamesFitInASentence() {
        #expect(AIBackend.apple(.onDevice).inSentence == "la IA de Apple")
        #expect(AIBackend.apple(.cloud).atSentenceStart == "La IA de Apple")
        #expect(AIBackend.claude.atSentenceStart == "Claude")
    }
}
