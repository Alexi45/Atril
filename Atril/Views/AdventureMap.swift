import SwiftUI

/// Disposición del mapa: cada escena en la columna del camino más largo que lleva hasta ella
/// siguiendo el orden del guion, para que la línea principal se lea de izquierda a derecha.
/// Las vueltas atrás no cuentan para colocar; las escenas alternativas comparten columna.
struct MapLayout: Equatable {
    struct Position: Equatable {
        var column: Int
        var row: Int
    }

    var positions: [String: Position]
    var columnCount: Int
    var rowCount: Int

    init(_ guide: AdventureGuide) {
        var depth: [String: Int] = [:]
        var previous = -1
        for (index, scene) in guide.scenes.enumerated() {
            // Solo cuentan las salidas que vienen de escenas anteriores en el guion.
            let incoming = guide.scenes[..<index]
                .filter { $0.exits.contains { $0.sceneID == scene.id } }
                .compactMap { depth[$0.id] }
            // Sin escena anterior que lleve aquí: detrás de la anterior en el guion.
            depth[scene.id] = index == 0 ? 0 : (incoming.max().map { $0 + 1 } ?? previous + 1)
            previous = depth[scene.id]!
        }

        var rows: [Int: Int] = [:]
        var positions: [String: Position] = [:]
        for scene in guide.scenes {
            let column = depth[scene.id] ?? 0
            positions[scene.id] = Position(column: column, row: rows[column, default: 0])
            rows[column, default: 0] += 1
        }
        self.positions = positions
        columnCount = (depth.values.max() ?? -1) + 1
        rowCount = rows.values.max() ?? 0
    }
}

/// Mapa visual de la aventura. Con `controller`, colorea el progreso de la partida.
struct AdventureMap: View {
    let guide: AdventureGuide
    let tint: Color
    var controller: PlayController?
    /// Dentro de otra vista con desplazamiento vertical, solo se desplaza en horizontal.
    var axes: Axis.Set = [.horizontal, .vertical]
    let onSelect: (AdventureGuide.Scene) -> Void

    private let nodeSize = CGSize(width: 210, height: 96)
    private let gap = CGSize(width: 70, height: 28)
    private let margin: CGFloat = 24
    /// Espacio por encima de la primera fila para los arcos de los atajos.
    private let topRoom: CGFloat = 56
    @State private var position = ScrollPosition(edge: .leading)

    var body: some View {
        if axes.contains(.vertical) {
            // A pantalla completa: el diagrama se centra si sobra sitio.
            GeometryReader { geometry in scroller(minimum: geometry.size) }
        } else {
            scroller(minimum: .zero)
        }
    }

    private func scroller(minimum: CGSize) -> some View {
        let layout = MapLayout(guide)
        let size = CGSize(
            width: margin * 2 + CGFloat(layout.columnCount) * nodeSize.width + CGFloat(max(layout.columnCount - 1, 0)) * gap.width,
            height: margin * 2 + topRoom + CGFloat(layout.rowCount) * nodeSize.height + CGFloat(max(layout.rowCount - 1, 0)) * gap.height + 40
        )
        return ScrollView(axes) {
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in drawEdges(in: &context, layout: layout) }
                    .frame(width: size.width, height: size.height)
                ForEach(guide.scenes) { scene in
                    if let position = layout.positions[scene.id] {
                        let origin = origin(of: position)
                        Button { onSelect(scene) } label: { node(scene) }
                            .buttonStyle(.plain)
                            .frame(width: nodeSize.width, height: nodeSize.height)
                            .padding(.leading, origin.x)
                            .padding(.top, origin.y)
                            .help(scene.summary)
                    }
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .frame(minWidth: minimum.width, minHeight: minimum.height)
        }
        .scrollPosition($position)
        .onAppear {
            // En mesa, el mapa se abre con la escena actual en el centro.
            guard minimum.width > 0, let current = controller?.currentSceneID,
                  let column = layout.positions[current]?.column else { return }
            let center = margin + CGFloat(column) * (nodeSize.width + gap.width) + nodeSize.width / 2
            position.scrollTo(x: max(0, min(center - minimum.width / 2, size.width - minimum.width)))
        }
    }

    private func origin(of position: MapLayout.Position) -> CGPoint {
        CGPoint(x: margin + CGFloat(position.column) * (nodeSize.width + gap.width),
                y: margin + topRoom + CGFloat(position.row) * (nodeSize.height + gap.height))
    }

    private func drawEdges(in context: inout GraphicsContext, layout: MapLayout) {
        for scene in guide.scenes {
            guard let from = layout.positions[scene.id] else { continue }
            for exit in scene.exits {
                guard let to = layout.positions[exit.sceneID] else { continue }
                let a = origin(of: from), b = origin(of: to)
                var path = Path()
                let end: CGPoint
                let direction: CGFloat
                if to.column > from.column + 1 && to.row == from.row {
                    // Atajo que se salta escenas: en arco por encima, para no cruzar las tarjetas.
                    let start = CGPoint(x: a.x + nodeSize.width / 2, y: a.y)
                    end = CGPoint(x: b.x + nodeSize.width / 2, y: b.y - 4)
                    let rise = min(start.y, end.y) - 30 - CGFloat(to.column - from.column) * 4
                    path.move(to: start)
                    path.addCurve(to: end, control1: CGPoint(x: start.x, y: rise), control2: CGPoint(x: end.x, y: rise))
                    direction = .pi / 2
                } else if to.column > from.column {
                    // Hacia delante: del borde derecho al izquierdo.
                    let start = CGPoint(x: a.x + nodeSize.width, y: a.y + nodeSize.height / 2)
                    end = CGPoint(x: b.x - 4, y: b.y + nodeSize.height / 2)
                    path.move(to: start)
                    path.addCurve(to: end, control1: CGPoint(x: start.x + gap.width * 0.6, y: start.y),
                                  control2: CGPoint(x: end.x - gap.width * 0.6, y: end.y))
                    direction = 0
                } else {
                    // Vuelta atrás o misma columna: por debajo, para no tapar las tarjetas.
                    let start = CGPoint(x: a.x + nodeSize.width / 2, y: a.y + nodeSize.height)
                    end = CGPoint(x: b.x + nodeSize.width / 2, y: b.y + nodeSize.height + 4)
                    let dip = max(start.y, end.y) + 34
                    path.move(to: start)
                    path.addCurve(to: end, control1: CGPoint(x: start.x, y: dip), control2: CGPoint(x: end.x, y: dip))
                    direction = -.pi / 2
                }
                let visited = controller.map { $0.status(of: scene) != .pending && $0.status(of: guide.scene(exit.sceneID)!) != .pending } ?? false
                let color = visited ? tint : Color.secondary.opacity(0.55)
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: visited ? 2.5 : 1.5, lineCap: .round,
                                                                              dash: to.column > from.column ? [] : [5, 4]))
                // Punta de flecha.
                var arrow = Path()
                let length: CGFloat = 9, spread: CGFloat = 0.45
                arrow.move(to: end)
                arrow.addLine(to: CGPoint(x: end.x - length * cos(direction - spread), y: end.y - length * sin(direction - spread)))
                arrow.move(to: end)
                arrow.addLine(to: CGPoint(x: end.x - length * cos(direction + spread), y: end.y - length * sin(direction + spread)))
                context.stroke(arrow, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
    }

    private func node(_ scene: AdventureGuide.Scene) -> some View {
        let status = controller?.status(of: scene)
        let index = (guide.scenes.firstIndex { $0.id == scene.id } ?? 0) + 1
        let clues = guide.clues(in: scene)
        let pendingCore = clues.filter { $0.isCore && !(controller?.isFound($0.id) ?? false) }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(status == .current ? tint : tint.opacity(0.14))
                    if status == .visited {
                        Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(tint)
                    } else {
                        Text("\(index)").font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(status == .current ? Color.white : tint)
                    }
                }
                .frame(width: 24, height: 24)
                Text(scene.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            if !scene.place.isEmpty {
                Text(scene.place).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                if !clues.isEmpty { badge("magnifyingglass", "\(clues.count)") }
                if !pendingCore.isEmpty { badge("star.fill", "\(pendingCore.count)", color: .orange) }
                if !scene.npcIDs.isEmpty { badge("person.2", "\(scene.npcIDs.count)") }
                if !scene.danger.isEmpty { badge("exclamationmark.triangle.fill", nil, color: .red) }
                Spacer(minLength: 0)
                Text("~\(SessionPlanner.minutes(for: scene))′").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .frame(width: nodeSize.width, height: nodeSize.height, alignment: .topLeading)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(status == .current ? tint : Color.hairline, lineWidth: status == .current ? 2.5 : 1)
        )
        .opacity(status == .visited ? 0.75 : 1)
        .shadow(color: .black.opacity(status == .current ? 0.15 : 0.05), radius: status == .current ? 10 : 3, y: 2)
    }

    private func badge(_ symbol: String, _ value: String?, color: Color = .secondary) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
            if let value { Text(value).monospacedDigit() }
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(color)
    }
}
