import Foundation

struct Combatant: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var initiative: Int
    var hp: Int?
    var hpMax: Int?
    /// Personaje de la mesa al que corresponde (sus PV se sincronizan con la lista de personajes).
    var playerID: UUID?
    var conditions: [String] = []

    var isDown: Bool { (hp ?? 1) <= 0 }
    var isPlayer: Bool { playerID != nil }
}

/// Combate por turnos. Los participantes se guardan ya ordenados por iniciativa.
struct Combat: Codable, Hashable {
    var combatants: [Combatant] = []
    var round = 1
    var turn = 0

    var isActive: Bool { !combatants.isEmpty }
    var current: Combatant? { combatants.indices.contains(turn) ? combatants[turn] : nil }

    /// Mayor iniciativa primero; a igualdad, los personajes antes que los enemigos.
    static func ordered(_ list: [Combatant]) -> [Combatant] {
        list.sorted { a, b in
            if a.initiative != b.initiative { return a.initiative > b.initiative }
            if a.isPlayer != b.isPlayer { return a.isPlayer }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    /// Añade y reordena sin cambiar de quién es el turno.
    mutating func add(_ new: [Combatant]) {
        let currentID = current?.id
        combatants = Self.ordered(combatants + new)
        if let currentID, let index = combatants.firstIndex(where: { $0.id == currentID }) { turn = index }
    }

    mutating func setInitiative(_ value: Int, for id: UUID) {
        guard let index = combatants.firstIndex(where: { $0.id == id }) else { return }
        let currentID = current?.id
        combatants[index].initiative = value
        combatants = Self.ordered(combatants)
        if let currentID, let index = combatants.firstIndex(where: { $0.id == currentID }) { turn = index }
    }

    mutating func remove(_ id: UUID) {
        guard let index = combatants.firstIndex(where: { $0.id == id }) else { return }
        combatants.remove(at: index)
        if index < turn { turn -= 1 }
        if turn >= combatants.count { turn = 0 }
    }

    /// Pasa al siguiente que siga en pie; al dar la vuelta empieza un asalto nuevo.
    mutating func next() {
        guard !combatants.isEmpty, combatants.contains(where: { !$0.isDown }) else { return }
        repeat {
            turn += 1
            if turn >= combatants.count {
                turn = 0
                round += 1
            }
        } while combatants[turn].isDown
    }

    mutating func previous() {
        guard !combatants.isEmpty, combatants.contains(where: { !$0.isDown }) else { return }
        repeat {
            turn -= 1
            if turn < 0 {
                turn = combatants.count - 1
                round = max(1, round - 1)
            }
        } while combatants[turn].isDown
    }

    mutating func changeHP(_ id: UUID, by amount: Int) {
        guard let index = combatants.firstIndex(where: { $0.id == id }), let hp = combatants[index].hp else { return }
        combatants[index].hp = hp + amount
    }
}

/// Lee lo útil para el combate de unas estadísticas en texto («PV 13», «DES 50», «CA 15»).
struct StatBlock: Equatable {
    var hp: Int?
    var dexterity: Int?
    var initiativeBonus: Int?
    var armorClass: Int?

    init(hp: Int? = nil, dexterity: Int? = nil, initiativeBonus: Int? = nil, armorClass: Int? = nil) {
        self.hp = hp
        self.dexterity = dexterity
        self.initiativeBonus = initiativeBonus
        self.armorClass = armorClass
    }

    init(parsing original: String) {
        // Los manuales suelen escribir el menos tipográfico: «DES 8 (−1)».
        let text = original.replacingOccurrences(of: "−", with: "-")
        func number(_ pattern: String) -> Int? {
            guard let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
            let digits = text[range].split(whereSeparator: { !$0.isNumber && $0 != "-" && $0 != "+" }).last.map(String.init)
            return digits.flatMap { Int($0.replacingOccurrences(of: "+", with: "")) }
        }
        hp = number(#"\b(PV|HP|puntos de (vida|golpe))\s*:?\s*\d+"#)
        dexterity = number(#"\b(DES|DEX|destreza)\s*:?\s*\d+"#)
        initiativeBonus = number(#"\b(iniciativa|init)\s*:?\s*[+-]?\d+"#) ?? number(#"\b(DES|DEX)\s*\d+\s*\(\s*[+-]\d+\s*\)"#)
        armorClass = number(#"\b(CA|AC)\s*:?\s*\d+"#)
    }

    /// Iniciativa de un enemigo: en Cthulhu manda la DES; en D&D, d20 + modificador.
    func initiative(system: GameSystem, roll: (Int) -> Int = { Int.random(in: 1...$0) }) -> Int {
        switch system {
        case .cthulhu:
            return dexterity ?? 50
        case .dnd, .other:
            let bonus = initiativeBonus ?? dexterity.map { $0 > 30 ? 0 : ($0 - 10) / 2 } ?? 0
            return roll(20) + bonus
        }
    }
}
