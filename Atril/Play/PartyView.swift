import SwiftUI

/// Personajes de la mesa con sus contadores de PV y Cordura.
struct PartyView: View {
    @Bindable var controller: PlayController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(controller.system.characterNoun).font(.title3.weight(.semibold))
                    Spacer()
                    Button("Añadir", systemImage: "plus") {
                        withAnimation(.snappy) { controller.players.append(newPlayer()) }
                    }
                    .buttonStyle(.bordered)
                }
                if controller.players.isEmpty {
                    Text("Añade a los personajes para llevar sus PV\(controller.system.tracksSanity ? " y su Cordura" : "") y que el tutor los tenga en cuenta.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach($controller.players) { $player in
                    PlayerCard(player: $player, system: controller.system) {
                        withAnimation(.snappy) { controller.players.removeAll { $0.id == player.id } }
                    }
                }
            }
            .padding(18)
        }
    }

    private func newPlayer() -> Player {
        controller.system == .cthulhu
            ? Player(hp: 11, hpMax: 11, sanity: 55, sanityMax: 99)
            : Player(hp: 10, hpMax: 10, armorClass: 12)
    }
}

private struct PlayerCard: View {
    @Binding var player: Player
    let system: GameSystem
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Personaje", text: $player.character).font(.headline)
                    TextField("Jugador", text: $player.name).font(.subheadline).foregroundStyle(.secondary)
                }
                .textFieldStyle(.plain)
                Menu {
                    Button("Quitar", systemImage: "trash", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis").frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            Counter(title: "PV", value: $player.hp, max: $player.hpMax, tint: .red)
            if system.tracksSanity {
                Counter(title: "COR", value: $player.sanity, max: $player.sanityMax, tint: .purple, showsMax: false)
            }
            if system == .dnd {
                HStack {
                    Text("CA").font(.callout.weight(.semibold)).frame(width: 40, alignment: .leading)
                    Stepper("\(player.armorClass)", value: $player.armorClass, in: 1...30)
                        .font(.callout.monospacedDigit())
                }
            }
            TextField("Estado (herido, aterrado, sin munición…)", text: $player.notes)
                .font(.callout)
                .textFieldStyle(.roundedBorder)
        }
        .card(padding: 14)
    }
}

private struct Counter: View {
    let title: String
    @Binding var value: Int
    @Binding var max: Int
    let tint: Color
    var showsMax = true

    var body: some View {
        HStack(spacing: 10) {
            Text(title).font(.callout.weight(.semibold)).frame(width: 40, alignment: .leading)
            Button { value -= 1 } label: { Image(systemName: "minus").frame(width: 28, height: 28) }
                .buttonStyle(.bordered)
            Text(showsMax ? "\(value)/\(max)" : "\(value)")
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(value <= 0 ? .red : .primary)
                .frame(minWidth: 64)
                .contentTransition(.numericText())
            Button { value += 1 } label: { Image(systemName: "plus").frame(width: 28, height: 28) }
                .buttonStyle(.bordered)
            if showsMax {
                ProgressView(value: Double(Swift.max(value, 0)), total: Double(Swift.max(max, 1)))
                    .tint(tint)
            } else {
                Spacer()
            }
        }
        .contextMenu {
            if showsMax {
                Button("Restaurar al máximo") { value = max }
                Button("Subir máximo") { max += 1 }
                Button("Bajar máximo") { max = Swift.max(1, max - 1) }
            }
        }
    }
}
