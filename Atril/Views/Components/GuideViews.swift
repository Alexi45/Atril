import SwiftUI

/// Contenido completo de una escena. Con `controller`, las pistas se marcan y las salidas navegan.
struct SceneContent: View {
    let scene: AdventureGuide.Scene
    let guide: AdventureGuide
    let system: GameSystem
    var controller: PlayController?
    var adventure: Adventure?
    @State private var shownNPC: AdventureGuide.NPC?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !scene.readAloud.isEmpty {
                ReadAloudBox(text: scene.readAloud, tint: system.accent, title: scene.place.isEmpty ? scene.title : scene.place)
            }

            block("Qué pasa", symbol: "text.alignleft") {
                Text(scene.summary).fixedSize(horizontal: false, vertical: true)
            }

            if !scene.goals.isEmpty {
                block("Qué deben conseguir", symbol: "scope") {
                    ForEach(scene.goals, id: \.self) { BulletRow(text: $0) }
                }
            }

            let clues = guide.clues(in: scene)
            if !clues.isEmpty {
                block("Pistas aquí", symbol: "magnifyingglass") {
                    ForEach(clues) { clue in ClueRow(clue: clue, guide: guide, controller: controller) }
                }
            }

            let npcs = scene.npcIDs.compactMap(guide.npc)
            if !npcs.isEmpty {
                block("PNJ en escena", symbol: "person.2") {
                    FlowLayout(spacing: 8) {
                        ForEach(npcs) { npc in
                            Button {
                                shownNPC = npc
                            } label: {
                                HStack(spacing: 6) {
                                    PortraitAvatar(name: npc.name, data: portraitOwner?.portrait(for: npc.name), size: 24, tint: system.accent)
                                    Text(npc.name)
                                }
                                .font(.callout.weight(.medium))
                                .padding(.leading, 5)
                                .padding(.trailing, 12)
                                .padding(.vertical, 5)
                                .background(Color.primary.opacity(0.06), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .popover(isPresented: Binding(get: { shownNPC == npc }, set: { if !$0 { shownNPC = nil } })) {
                                ScrollView { NPCCard(npc: npc, framed: false, adventure: portraitOwner).padding(20) }
                                    .frame(idealWidth: 380, maxHeight: 520)
                                    .presentationCompactAdaptation(.sheet)
                            }
                        }
                    }
                }
            }

            if !scene.checks.isEmpty {
                block("Tiradas probables", symbol: "dice") {
                    ForEach(scene.checks, id: \.self) { check in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(check.skill).font(.callout.weight(.semibold))
                                if !check.difficulty.isEmpty {
                                    Text(check.difficulty)
                                        .font(.caption.weight(.medium))
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(system.accent.opacity(0.12), in: Capsule())
                                        .foregroundStyle(system.accent)
                                }
                            }
                            Text(check.purpose).font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if !scene.danger.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        SectionLabel(title: "Peligro", tint: .orange)
                        Text(scene.danger).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if !scene.tips.isEmpty {
                block("Consejos del tutor", symbol: "lightbulb", tint: .amber) {
                    ForEach(scene.tips, id: \.self) { BulletRow(text: $0, symbol: "lightbulb.fill", tint: .amber) }
                }
            }

            if !scene.ifStuck.isEmpty {
                block("Si se atascan", symbol: "lifepreserver") {
                    Text(scene.ifStuck).fixedSize(horizontal: false, vertical: true)
                }
            }

            if !scene.exits.isEmpty {
                block("Desde aquí", symbol: "arrow.triangle.turn.up.right.diamond") {
                    ForEach(scene.exits, id: \.self) { exit in
                        ExitRow(exit: exit, guide: guide, tint: system.accent, controller: controller)
                    }
                }
            }
        }
    }

    private var portraitOwner: Adventure? { adventure ?? controller?.adventure }

    @ViewBuilder
    private func block<Content: View>(_ title: String, symbol: String, tint: Color = .secondary, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title: title, symbol: symbol, tint: tint == .secondary ? .secondary : tint)
            content()
        }
    }
}

struct ClueRow: View {
    let clue: AdventureGuide.Clue
    let guide: AdventureGuide
    var controller: PlayController?
    @State private var presented: Handout?

    var body: some View {
        let found = controller?.isFound(clue.id) ?? false
        HStack(alignment: .top, spacing: 10) {
            if let controller {
                Button {
                    controller.toggleClue(clue.id)
                } label: {
                    Image(systemName: found ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(found ? Color.green : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(found ? "Marcar como no descubierta" : "Marcar como descubierta")
            } else {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).frame(width: 22)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(clue.title).font(.callout.weight(.semibold))
                        .strikethrough(found, color: .secondary)
                    if clue.isCore {
                        Label("Clave", systemImage: "star.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.orange)
                    }
                }
                Text(clue.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if !clue.leadsTo.isEmpty {
                    Label(clue.leadsTo, systemImage: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
            Button {
                presented = Handout(title: clue.title, body: clue.detail, style: .document)
            } label: {
                Image(systemName: "doc.richtext")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Enseñar la pista a los jugadores como documento")
            .accessibilityLabel("Enseñar a los jugadores")
        }
        .opacity(found ? 0.7 : 1)
        .handoutPresenter($presented)
    }
}

private struct ExitRow: View {
    let exit: AdventureGuide.Exit
    let guide: AdventureGuide
    let tint: Color
    var controller: PlayController?

    var body: some View {
        let target = guide.scene(exit.sceneID)
        let content = HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.right.circle.fill").foregroundStyle(tint).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(target?.title ?? exit.sceneID).font(.callout.weight(.semibold))
                Text(exit.condition).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())

        if let controller, target != nil {
            Button { withAnimation(.snappy) { controller.go(to: exit.sceneID) } } label: { content }
                .buttonStyle(.plain)
                .padding(10)
                .background(tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            content
        }
    }
}

struct NPCCard: View {
    let npc: AdventureGuide.NPC
    var framed = true
    /// Con la aventura, la ficha muestra el retrato y permite crearlo o cambiarlo.
    var adventure: Adventure?

    var body: some View {
        let content = VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                if let adventure {
                    PortraitControl(npc: npc, adventure: adventure, size: 56)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(npc.name).font(.headline)
                    Text(npc.role).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            if !npc.look.isEmpty { field("Aspecto", npc.look, symbol: "eye") }
            if !npc.motivation.isEmpty { field("Quiere", npc.motivation, symbol: "target") }
            if !npc.voice.isEmpty { field("Cómo interpretarlo", npc.voice, symbol: "theatermasks") }
            if !npc.secret.isEmpty { field("Secreto", npc.secret, symbol: "eye.slash", tint: .purple) }
            if !npc.stats.isEmpty {
                Text(npc.stats)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        if framed { content.card() } else { content }
    }

    private func field(_ title: String, _ value: String, symbol: String, tint: Color = .secondary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            SectionLabel(title: title, symbol: symbol, tint: tint)
            Text(value).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Distribuye etiquetas en líneas que se ajustan al ancho disponible.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal: proposal, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(proposal: ProposedViewSize(width: bounds.width, height: nil), subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty && rows[rows.count - 1].width + spacing + size.width > maxWidth {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
