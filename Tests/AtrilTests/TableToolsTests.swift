import Foundation
import Testing
@testable import Atril

struct CombatTests {
    private func combatant(_ name: String, _ initiative: Int, hp: Int? = 10, player: Bool = false) -> Combatant {
        Combatant(name: name, initiative: initiative, hp: hp, hpMax: hp, playerID: player ? UUID() : nil)
    }

    @Test func ordersByInitiativeWithPlayersFirstOnTies() {
        var combat = Combat()
        combat.add([combatant("Profundo", 50), combatant("Lucía", 70, player: true), combatant("Tomás", 50, player: true)])
        #expect(combat.combatants.map(\.name) == ["Lucía", "Tomás", "Profundo"])
        #expect(combat.current?.name == "Lucía")
    }

    @Test func turnsAdvanceAndRoundsWrap() {
        var combat = Combat()
        combat.add([combatant("A", 3), combatant("B", 2), combatant("C", 1)])
        combat.next()
        combat.next()
        #expect(combat.current?.name == "C")
        #expect(combat.round == 1)
        combat.next()
        #expect(combat.current?.name == "A")
        #expect(combat.round == 2)
        combat.previous()
        #expect(combat.current?.name == "C")
        #expect(combat.round == 1)
    }

    @Test func skipsCombatantsWhoAreDown() {
        var combat = Combat()
        combat.add([combatant("A", 3), combatant("B", 2, hp: 0), combatant("C", 1)])
        combat.next()
        #expect(combat.current?.name == "C")
    }

    @Test func addingMidCombatKeepsTheCurrentTurn() {
        var combat = Combat()
        combat.add([combatant("A", 10), combatant("B", 5)])
        combat.next()
        #expect(combat.current?.name == "B")
        combat.add([combatant("Rápido", 20)])
        #expect(combat.current?.name == "B")
        combat.setInitiative(1, for: combat.combatants.first { $0.name == "A" }!.id)
        #expect(combat.current?.name == "B")
        #expect(combat.combatants.last?.name == "A")
    }

    @Test func removingKeepsTurnInRange() {
        var combat = Combat()
        combat.add([combatant("A", 3), combatant("B", 2)])
        combat.next()
        combat.remove(combat.current!.id)
        #expect(combat.turn == 0)
        #expect(combat.current?.name == "A")
    }
}

struct StatBlockTests {
    @Test func parsesCthulhuStats() {
        let stats = StatBlock(parsing: "Profundo: FUE 70, CON 50, TAM 80, DES 50, PV 13. Garras 45 %")
        #expect(stats.hp == 13)
        #expect(stats.dexterity == 50)
        #expect(stats.initiative(system: .cthulhu) == 50)
    }

    @Test func parsesDnDStatsWithTypographicMinus() {
        let stats = StatBlock(parsing: "CA 15, PG 22 (puntos de golpe 22), FUE 12 (+1), DES 8 (−1)")
        #expect(stats.armorClass == 15)
        #expect(stats.hp == 22)
        #expect(stats.initiativeBonus == -1)
        #expect(stats.initiative(system: .dnd, roll: { _ in 10 }) == 9)
    }

    @Test func emptyStats() {
        #expect(StatBlock(parsing: "No lucha: huye hacia el agua.") == StatBlock())
    }
}

struct RecapTests {
    private var facts: Recap.Facts {
        Recap.Facts(
            title: SampleAdventure.title, system: .cthulhu, guide: SampleAdventure.guide,
            notes: [
                SessionNote(playTime: 60, text: "Han convencido a Xuacu con orujo"),
                SessionNote(playTime: 90, text: "Descubren la pista: Luces bajo el agua"),
            ],
            visitedSceneIDs: ["e1", "e2", "e4"], foundClueIDs: ["p1", "p2"], currentSceneID: "e4",
            players: [Player(name: "Ana", character: "Lucía", hp: 4, hpMax: 11, sanity: 25)]
        )
    }

    @Test func playersTextOnlyHasWhatTheyKnow() {
        let recap = Recap.basic(facts)
        #expect(recap.forPlayers.contains("«Llegada a Portuxe», «La taberna de la Remedios» y «El faro de Punta Negra»"))
        #expect(recap.forPlayers.contains("Descubristeis «Luces bajo el agua» y «Marina camina hacia el mar»."))
        #expect(recap.forPlayers.contains("Han convencido a Xuacu con orujo"))
        // Las notas automáticas no se repiten y no se revelan secretos.
        #expect(!recap.forPlayers.contains("Descubren la pista"))
        #expect(!recap.forPlayers.contains("Profundos"))
        #expect(!recap.forPlayers.contains("Registro de 1824"))
    }

    @Test func gmGetsPendingWork() {
        let recap = Recap.basic(facts)
        #expect(recap.forGM.first?.hasPrefix("Retoma en «El faro de Punta Negra»") == true)
        #expect(recap.forGM.contains { $0.contains("«Registro de 1824»") })
        #expect(recap.forGM.contains { $0 == "Lucía sigue herido: 4/11 PV." || $0.hasPrefix("Lucía sigue herid") })
        #expect(recap.forGM.contains { $0.contains("Cordura (25)") })
    }

    @Test func listJoinsWithY() {
        #expect(Recap.list(["a"]) == "a")
        #expect(Recap.list(["a", "b", "c"]) == "a, b y c")
    }
}

struct MapLayoutTests {
    @Test func linearAdventureIsOneRow() {
        let layout = MapLayout(SampleAdventure.guide)
        #expect(layout.columnCount == 6)
        #expect(layout.rowCount == 1)
        #expect(layout.positions["e4"] == MapLayout.Position(column: 3, row: 0))
    }

    @Test func shortcutsDoNotBreakTheMainLine() {
        // En el ejemplo se puede ir de la llegada directamente al faro, y del faro volver a la parroquia.
        let guide = SampleAdventure.guide
        #expect(guide.scene("e1")?.exits.contains { $0.sceneID == "e4" } == true)
        let layout = MapLayout(guide)
        #expect(layout.positions["e4"] == MapLayout.Position(column: 3, row: 0))
    }

    @Test func alternativesShareAColumn() {
        var guide = SampleAdventure.guide
        // Desde la taberna se va o a la parroquia o al faro, y las dos llevan a las cuevas.
        guide.scenes[0].exits = [.init(sceneID: "e2", condition: "")]
        guide.scenes[1].exits = [.init(sceneID: "e3", condition: ""), .init(sceneID: "e4", condition: "")]
        guide.scenes[2].exits = [.init(sceneID: "e5", condition: "")]
        guide.scenes[3].exits = [.init(sceneID: "e5", condition: "")]
        let layout = MapLayout(guide)
        #expect(layout.positions["e3"] == MapLayout.Position(column: 2, row: 0))
        #expect(layout.positions["e4"] == MapLayout.Position(column: 2, row: 1))
        #expect(layout.positions["e5"]?.column == 3)
        #expect(layout.rowCount == 2)
    }

    @Test func unreachableScenesFollowTheScript() {
        var guide = SampleAdventure.guide
        guide.scenes[0].exits = []
        let layout = MapLayout(guide)
        #expect(layout.positions["e2"]?.column == 1)
    }
}
