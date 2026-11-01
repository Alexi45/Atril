import PDFKit
import SwiftUI

extension SessionPlanner {
    /// Escenas de la próxima sesión: desde donde se quedó la mesa, hasta llenar el tiempo previsto.
    static func upcoming(_ guide: AdventureGuide, from sceneID: String?, hours: Double) -> [String] {
        let start = guide.scenes.firstIndex { $0.id == sceneID } ?? 0
        let budget = Int(hours * 60 * 0.85)
        var minutes = 0
        var ids: [String] = []
        for scene in guide.scenes[start...] {
            let cost = SessionPlanner.minutes(for: scene)
            if !ids.isEmpty && minutes + cost > budget { break }
            ids.append(scene.id)
            minutes += cost
        }
        return ids
    }
}

/// Hoja de preparación imprimible (A4) para dirigir una sesión sin pantalla.
enum PrepSheet {
    struct Content {
        var title: String
        var subtitle: String
        var system: GameSystem
        var guide: AdventureGuide
        var sceneIDs: [String]
        var recap: String?
        var includeOpening: Bool
        var portraits: [String: Data]
    }

    static let page = CGSize(width: 595, height: 842)
    static let margin: CGFloat = 36
    static var contentWidth: CGFloat { page.width - margin * 2 }
    static let footerHeight: CGFloat = 22

    /// Maqueta los bloques en páginas sin partir ninguno y escribe el PDF.
    @MainActor
    static func render(_ content: Content, to url: URL) throws {
        let blocks = blocks(for: content)
        let heights = blocks.map(measure)
        let available = page.height - margin * 2 - footerHeight
        var pages: [[Int]] = [[]]
        var used: CGFloat = 0
        for (index, height) in heights.enumerated() {
            let spacing: CGFloat = pages[pages.count - 1].isEmpty ? 0 : 14
            if used + spacing + height > available && !pages[pages.count - 1].isEmpty {
                pages.append([index])
                used = height
            } else {
                pages[pages.count - 1].append(index)
                used += spacing + height
            }
        }

        var box = CGRect(origin: .zero, size: page)
        guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { throw CocoaError(.fileWriteUnknown) }
        for (number, indices) in pages.enumerated() {
            let view = PageView(blocks: indices.map { blocks[$0] }, title: content.title, number: number + 1, total: pages.count)
            let renderer = ImageRenderer(content: view)
            renderer.proposedSize = ProposedViewSize(page)
            pdf.beginPDFPage(nil)
            renderer.render { _, draw in draw(pdf) }
            pdf.endPDFPage()
        }
        pdf.closePDF()
    }

    @MainActor
    private static func measure(_ block: AnyView) -> CGFloat {
        let renderer = ImageRenderer(content: block.frame(width: contentWidth).environment(\.colorScheme, .light))
        renderer.proposedSize = ProposedViewSize(width: contentWidth, height: nil)
        var height: CGFloat = 0
        renderer.render { size, _ in height = size.height }
        return height
    }

    private static func blocks(for content: Content) -> [AnyView] {
        let guide = content.guide
        let scenes = content.sceneIDs.compactMap(guide.scene)
        var blocks: [AnyView] = [AnyView(Header(content: content, minutes: scenes.map(SessionPlanner.minutes(for:)).reduce(0, +)))]
        if let recap = content.recap, !recap.trimmed.isEmpty {
            blocks.append(AnyView(Box(title: "Previamente (para leer al empezar)", text: recap, serif: true)))
        }
        if content.includeOpening {
            if !guide.truth.isEmpty { blocks.append(AnyView(Box(title: "La verdad · solo para el máster", text: guide.truth.truncated(words: 140)))) }
            if !guide.hook.isEmpty { blocks.append(AnyView(Box(title: "Cómo empezar", text: guide.hook.truncated(words: 110)))) }
        }
        for scene in scenes {
            let number = (guide.scenes.firstIndex { $0.id == scene.id } ?? 0) + 1
            blocks.append(AnyView(SceneBlock(scene: scene, number: number, guide: guide)))
        }
        let npcIDs = scenes.flatMap(\.npcIDs).uniqued
        let npcs = npcIDs.compactMap(guide.npc)
        if !npcs.isEmpty {
            blocks.append(AnyView(SectionTitle(text: "Personajes no jugadores")))
            for npc in npcs {
                let portrait = content.portraits.first { Prose.sameName($0.key, npc.name) }?.value
                blocks.append(AnyView(NPCBlock(npc: npc, portrait: portrait)))
            }
        }
        return blocks
    }

    // MARK: Piezas de la hoja (colores fijos: es papel, no pantalla)

    static let ink = Color(red: 0.10, green: 0.10, blue: 0.12)
    static let muted = Color(red: 0.40, green: 0.40, blue: 0.44)
    static let rule = Color(red: 0.85, green: 0.85, blue: 0.87)

    private struct PageView: View {
        let blocks: [AnyView]
        let title: String
        let number: Int
        let total: Int

        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in block }
                Spacer(minLength: 0)
                HStack {
                    Text("Atril · \(title)")
                    Spacer()
                    Text("Página \(number) de \(total)")
                }
                .font(.system(size: 8))
                .foregroundStyle(PrepSheet.muted)
                .frame(height: PrepSheet.footerHeight, alignment: .bottom)
            }
            .padding(PrepSheet.margin)
            .frame(width: PrepSheet.page.width, height: PrepSheet.page.height, alignment: .topLeading)
            .background(Color.white)
            .environment(\.colorScheme, .light)
        }
    }

    private struct Header: View {
        let content: Content
        let minutes: Int

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(content.system.name.uppercased())
                    .font(.system(size: 8, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(content.system.accent)
                Text(content.title).font(.system(size: 22, weight: .bold, design: .serif)).foregroundStyle(PrepSheet.ink)
                Text("\(content.subtitle) · ~\(Format.duration(TimeInterval(minutes * 60)))")
                    .font(.system(size: 10))
                    .foregroundStyle(PrepSheet.muted)
                Rectangle().fill(PrepSheet.rule).frame(height: 1).padding(.top, 4)
            }
        }
    }

    private struct SectionTitle: View {
        let text: String
        var body: some View {
            Text(text.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(1)
                .foregroundStyle(PrepSheet.muted)
                .padding(.top, 6)
        }
    }

    private struct Box: View {
        let title: String
        let text: String
        var serif = false

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased()).font(.system(size: 8, weight: .bold)).tracking(0.8).foregroundStyle(PrepSheet.muted)
                Text(text)
                    .font(serif ? .system(size: 10, design: .serif) : .system(size: 9.5))
                    .foregroundStyle(PrepSheet.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0.96, green: 0.96, blue: 0.97), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private struct SceneBlock: View {
        let scene: AdventureGuide.Scene
        let number: Int
        let guide: AdventureGuide

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(number). \(scene.title)").font(.system(size: 13, weight: .bold)).foregroundStyle(PrepSheet.ink)
                    Spacer()
                    Text("~\(SessionPlanner.minutes(for: scene)) min").font(.system(size: 8)).foregroundStyle(PrepSheet.muted)
                }
                if !scene.place.isEmpty {
                    Text(scene.place).font(.system(size: 9)).foregroundStyle(PrepSheet.muted)
                }
                if !scene.readAloud.isEmpty {
                    Text(scene.readAloud.truncated(words: 90))
                        .font(.system(size: 9.5, design: .serif))
                        .italic()
                        .foregroundStyle(PrepSheet.ink)
                        .padding(.leading, 8)
                        .overlay(alignment: .leading) { Rectangle().fill(PrepSheet.rule).frame(width: 2) }
                        .fixedSize(horizontal: false, vertical: true)
                }
                line("Qué pasa", scene.summary)
                if !scene.goals.isEmpty { line("Objetivos", scene.goals.joined(separator: " · ")) }
                let clues = guide.clues(in: scene)
                if !clues.isEmpty {
                    line("Pistas", clues.map { "\($0.isCore ? "★ " : "")\($0.title): \($0.detail.truncated(words: 18))" }.joined(separator: "\n"))
                }
                let npcs = scene.npcIDs.compactMap(guide.npc)
                if !npcs.isEmpty { line("PNJ", npcs.map(\.name).joined(separator: ", ")) }
                if !scene.checks.isEmpty {
                    line("Tiradas", scene.checks.map { "\($0.skill)\($0.difficulty.isEmpty ? "" : " (\($0.difficulty))")" }.joined(separator: " · "))
                }
                if !scene.danger.isEmpty { line("Peligro", scene.danger) }
                if !scene.ifStuck.isEmpty { line("Si se atascan", scene.ifStuck) }
                if let tip = scene.tips.first { line("Consejo", tip) }
                Rectangle().fill(PrepSheet.rule).frame(height: 1).padding(.top, 4)
            }
        }

        private func line(_ label: String, _ value: String) -> some View {
            (Text("\(label): ").bold() + Text(value))
                .font(.system(size: 9))
                .foregroundStyle(PrepSheet.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private struct NPCBlock: View {
        let npc: AdventureGuide.NPC
        let portrait: Data?

        var body: some View {
            HStack(alignment: .top, spacing: 10) {
                if let portrait, let image = Image(portraitData: portrait) {
                    image.resizable().scaledToFill().frame(width: 46, height: 46).clipShape(RoundedRectangle(cornerRadius: 6))
                }
                VStack(alignment: .leading, spacing: 2) {
                    (Text(npc.name).bold() + Text(npc.role.isEmpty ? "" : " — \(npc.role)"))
                        .font(.system(size: 10))
                        .foregroundStyle(PrepSheet.ink)
                    let details = [
                        npc.voice.isEmpty ? nil : "Voz: \(npc.voice)",
                        npc.motivation.isEmpty ? nil : "Quiere: \(npc.motivation)",
                        npc.secret.isEmpty ? nil : "Oculta: \(npc.secret)",
                        npc.stats.isEmpty ? nil : npc.stats,
                    ].compactMap { $0 }
                    if !details.isEmpty {
                        Text(details.joined(separator: " · "))
                            .font(.system(size: 8.5))
                            .foregroundStyle(PrepSheet.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

/// Elegir qué sesión preparar, ver la hoja y compartirla o imprimirla.
struct PrepSheetView: View {
    let adventure: Adventure
    let guide: AdventureGuide
    @Environment(\.dismiss) private var dismiss
    @State private var choice: Choice = .next
    @State private var url: URL?
    @State private var error: String?

    enum Choice: Hashable {
        case next
        case planned(Int)
        case all
    }

    private var plan: [SessionPlanner.PlannedSession] { SessionPlanner.plan(guide, hours: adventure.sessionHours) }
    private var lastSession: PlaySession? { adventure.sortedSessions.first }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Qué preparar", selection: $choice) {
                    if lastSession != nil { Text("Próxima sesión").tag(Choice.next) }
                    ForEach(plan) { session in Text("Sesión \(session.number) del plan").tag(Choice.planned(session.number)) }
                    Text("Toda la aventura").tag(Choice.all)
                }
                .pickerStyle(.menu)
                .padding(12)
                Divider()
                if let url {
                    PDFPreview(url: url)
                } else if let error {
                    ContentUnavailableView("No se ha podido crear la hoja", systemImage: "exclamationmark.triangle", description: Text(error))
                } else {
                    ProgressView("Maquetando…").frame(maxHeight: .infinity)
                }
            }
            .navigationTitle("Hoja de preparación")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } }
                if let url {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: url) { Label("Compartir o imprimir", systemImage: "square.and.arrow.up") }
                    }
                    #if os(macOS)
                    ToolbarItem(placement: .primaryAction) {
                        Button("Imprimir…", systemImage: "printer") {
                            PDFDocument(url: url)?.printOperation(for: nil, scalingMode: .pageScaleToFit, autoRotate: true)?.runModal(for: NSApp.keyWindow ?? NSWindow(), delegate: nil, didRun: nil, contextInfo: nil)
                        }
                    }
                    #endif
                }
            }
            .task(id: choice) { build() }
            .onAppear { if lastSession == nil { choice = plan.isEmpty ? .all : .planned(1) } }
        }
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 760)
        #endif
    }

    private func build() {
        url = nil
        error = nil
        var sceneIDs: [String]
        var subtitle: String
        var recap: String?
        var opening = false
        switch choice {
        case .next:
            let number = (adventure.sessions.map(\.number).max() ?? 0) + 1
            sceneIDs = SessionPlanner.upcoming(guide, from: lastSession?.currentSceneID, hours: adventure.sessionHours)
            subtitle = "Sesión \(number)"
            recap = lastSession?.playerSummary
        case .planned(let number):
            sceneIDs = plan.first { $0.number == number }?.sceneIDs ?? []
            subtitle = "Sesión \(number) del plan"
            opening = number == 1
        case .all:
            sceneIDs = guide.scenes.map(\.id)
            subtitle = "Aventura completa"
            opening = true
        }
        if sceneIDs.isEmpty { sceneIDs = guide.scenes.map(\.id) }
        let content = PrepSheet.Content(
            title: adventure.title, subtitle: subtitle, system: adventure.system, guide: guide, sceneIDs: sceneIDs,
            recap: recap, includeOpening: opening,
            portraits: Dictionary(adventure.portraits.map { ($0.npcName, $0.imageData) }, uniquingKeysWith: { first, _ in first })
        )
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(AdventureArchive.fileName(for: adventure.title)) - \(subtitle).pdf")
        do {
            try PrepSheet.render(content, to: file)
            url = file
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Vista previa del PDF con PDFKit.
struct PDFPreview {
    let url: URL

    func makeView() -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.document = PDFDocument(url: url)
        return view
    }
}

#if os(iOS)
extension PDFPreview: UIViewRepresentable {
    func makeUIView(context: Context) -> PDFView { makeView() }
    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url { view.document = PDFDocument(url: url) }
    }
}
#else
extension PDFPreview: NSViewRepresentable {
    func makeNSView(context: Context) -> PDFView { makeView() }
    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url { view.document = PDFDocument(url: url) }
    }
}
#endif
