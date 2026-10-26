import SwiftUI

/// Orden de turnos, asaltos y PV durante un combate.
struct CombatView: View {
    let controller: PlayController
    @State private var enemyName = ""
    @State private var enemyCount = 1
    @State private var enemyHP = 10
    @State private var enemyInitiative = 0
    @State private var editingInitiative: Combatant?

    private var combat: Combat { controller.combat }
    private var accent: Color { controller.system.accent }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if combat.isActive {
                    turnHeader
                    order
                } else {
                    Text("Combate").font(.title3.weight(.semibold))
                    Text(controller.system == .cthulhu
                         ? "Actúan por orden de DES (las armas de fuego preparadas, con DES + 50). Cada uno puede esquivar o contraatacar."
                         : "Cada turno: movimiento, una acción, una acción adicional si la tiene y una reacción por asalto.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                addSection
                if combat.isActive {
                    Button(role: .destructive) {
                        withAnimation(.snappy) { controller.endCombat() }
                    } label: {
                        Label("Terminar combate", systemImage: "flag.checkered").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(18)
        }
        .sheet(item: $editingInitiative) { combatant in
            InitiativeEditor(combatant: combatant) { value in controller.setInitiative(value, for: combatant.id) }
                .presentationDetents([.height(220)])
        }
    }

    // MARK: Turno

    private var turnHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ASALTO \(combat.round)")
                    .font(.caption.weight(.bold))
                    .tracking(0.6)
                    .foregroundStyle(accent)
                Text(combat.current.map { "Turno de \($0.name)" } ?? "—")
                    .font(.title2.weight(.bold))
                    .lineLimit(2)
            }
            Spacer()
            Button { withAnimation(.snappy) { controller.previousTurn() } } label: {
                Image(systemName: "backward.fill").frame(width: 24, height: 24)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Turno anterior")
            Button { withAnimation(.snappy) { controller.nextTurn() } } label: {
                Label("Siguiente", systemImage: "forward.fill").frame(minHeight: 24)
            }
            .buttonStyle(.borderedProminent)
        }
        .card(padding: 14)
    }

    private var order: some View {
        VStack(spacing: 6) {
            ForEach(Array(combat.combatants.enumerated()), id: \.element.id) { index, combatant in
                let isCurrent = index == combat.turn
                let down = controller.isDown(combatant)
                HStack(spacing: 10) {
                    Button { editingInitiative = combatant } label: {
                        Text("\(combatant.initiative)")
                            .font(.callout.weight(.bold).monospacedDigit())
                            .frame(minWidth: 34, minHeight: 28)
                            .background((isCurrent ? accent : Color.primary).opacity(isCurrent ? 0.2 : 0.06), in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .help("Cambiar la iniciativa")

                    Image(systemName: down ? "xmark.octagon.fill" : (combatant.isPlayer ? "person.fill" : "flame.fill"))
                        .foregroundStyle(down ? Color.red : (combatant.isPlayer ? accent : .orange))
                        .frame(width: 18)
                    Text(combatant.name)
                        .font(.callout.weight(isCurrent ? .bold : .regular))
                        .strikethrough(down, color: .secondary)
                        .foregroundStyle(down ? .secondary : .primary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let hp = controller.hp(of: combatant) {
                        HStack(spacing: 4) {
                            Button { controller.changeHP(of: combatant, by: -1) } label: { Image(systemName: "minus") }
                            Text("\(hp.current)/\(hp.max)")
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(hp.current <= 0 ? .red : (hp.current * 2 <= hp.max ? .orange : .primary))
                                .frame(minWidth: 40)
                                .contentTransition(.numericText())
                            Button { controller.changeHP(of: combatant, by: 1) } label: { Image(systemName: "plus") }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isCurrent ? accent.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contextMenu {
                    Button("Quitar del combate", systemImage: "trash", role: .destructive) { controller.removeFromCombat(combatant.id) }
                }
            }
        }
    }

    // MARK: Añadir

    private var addSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: combat.isActive ? "Añadir al combate" : "Preparar el combate", symbol: "plus.circle")
            if !controller.players.isEmpty, controller.players.contains(where: { player in !combat.combatants.contains { $0.playerID == player.id } }) {
                Button {
                    withAnimation(.snappy) { controller.addPartyToCombat() }
                } label: {
                    Label("Añadir a \(controller.system.characterNoun.lowercased())", systemImage: "person.3.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Text(controller.system == .cthulhu ? "Empiezan con DES 50: toca el número para poner la de cada uno." : "Se tira un d20 por cada uno: toca el número para sumar su modificador.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            let suggested = suggestedEnemies
            if !suggested.isEmpty {
                Text("Del guion").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(suggested, id: \.name) { npc in
                    let stats = StatBlock(parsing: npc.stats)
                    Button {
                        withAnimation(.snappy) { controller.addEnemies(name: npc.name, count: 1, stats: stats) }
                    } label: {
                        HStack {
                            Image(systemName: "flame")
                            Text(npc.name).lineLimit(1)
                            Spacer()
                            Text([stats.hp.map { "PV \($0)" }, stats.dexterity.map { "DES \($0)" }].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }

            Text("Otro enemigo").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            TextField("Nombre (p. ej. «Profundo»)", text: $enemyName)
                .textFieldStyle(.roundedBorder)
            HStack {
                Stepper("× \(enemyCount)", value: $enemyCount, in: 1...12).fixedSize()
                Spacer()
                Stepper("PV \(enemyHP)", value: $enemyHP, in: 1...300).fixedSize()
            }
            .font(.callout.monospacedDigit())
            Stepper(controller.system == .cthulhu ? "DES \(enemyInitiative == 0 ? 50 : enemyInitiative)" : "Modificador de iniciativa \(enemyInitiative >= 0 ? "+" : "")\(enemyInitiative)",
                    value: $enemyInitiative, in: controller.system == .cthulhu ? 0...150 : -5...10, step: controller.system == .cthulhu ? 5 : 1)
                .font(.callout.monospacedDigit())
            Button {
                let stats = controller.system == .cthulhu
                    ? StatBlock(hp: enemyHP, dexterity: enemyInitiative == 0 ? 50 : enemyInitiative)
                    : StatBlock(hp: enemyHP, initiativeBonus: enemyInitiative)
                withAnimation(.snappy) { controller.addEnemies(name: enemyName, count: enemyCount, stats: stats) }
                enemyName = ""
                enemyCount = 1
            } label: {
                Label("Añadir", systemImage: "plus").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .card()
    }

    /// PNJ con estadísticas: primero los de la escena actual.
    private var suggestedEnemies: [AdventureGuide.NPC] {
        guard let guide = controller.guide else { return [] }
        let here = Set(controller.currentScene?.npcIDs ?? [])
        return guide.npcs
            .filter { StatBlock(parsing: $0.stats).hp != nil }
            .sorted { here.contains($0.id) && !here.contains($1.id) }
            .prefix(4)
            .map { $0 }
    }
}

private struct InitiativeEditor: View {
    let combatant: Combatant
    let onSave: (Int) -> Void
    @State private var value: Int
    @Environment(\.dismiss) private var dismiss

    init(combatant: Combatant, onSave: @escaping (Int) -> Void) {
        self.combatant = combatant
        self.onSave = onSave
        _value = State(initialValue: combatant.initiative)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Iniciativa de \(combatant.name)").font(.headline)
            Stepper(value: $value, in: -10...200) {
                Text("\(value)").font(.largeTitle.weight(.bold).monospacedDigit())
            }
            .frame(maxWidth: 280)
            HStack {
                Button("Cancelar") { dismiss() }.buttonStyle(.bordered)
                Button("Guardar") {
                    onSave(value)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
    }
}
