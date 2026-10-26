import SwiftData
import SwiftUI

/// Modo mesa: lo que el máster tiene delante mientras dirige.
struct PlayView: View {
    let onExit: () -> Void
    @State private var controller: PlayController
    @State private var showTutor = true
    @State private var showDice = false
    @State private var showParty = false
    @State private var showReference = false
    @State private var showEnd = false
    @State private var showCombat = false
    @State private var showMap = false
    @State private var debugHandout: Handout?
    @Environment(\.horizontalSizeClass) private var sizeClass

    init(session: PlaySession, onExit: @escaping () -> Void) {
        self.onExit = onExit
        _controller = State(initialValue: PlayController(session: session))
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                if sizeClass != .compact {
                    ReferenceRail(controller: controller)
                        .frame(width: 260)
                    Divider()
                }
                SceneColumn(controller: controller) { showCombat = true }
            }
            .background(Color.canvas)
            .inspector(isPresented: $showTutor) {
                TutorPanel(controller: controller)
                    .inspectorColumnWidth(min: 320, ideal: 380, max: 520)
            }
            .navigationTitle(controller.adventure.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbar }
            .sheet(isPresented: $showMap) {
                if let guide = controller.guide {
                    NavigationStack {
                        AdventureMap(guide: guide, tint: controller.system.accent, controller: controller) { scene in
                            withAnimation(.snappy) { controller.go(to: scene.id) }
                            showMap = false
                        }
                        .background(Color.canvas)
                        .navigationTitle("Mapa de la aventura")
                        #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) { Button("Listo") { showMap = false } }
                        }
                    }
                    .presentationSizing(.page)
                    #if os(macOS)
                    .frame(minWidth: 900, minHeight: 600)
                    #endif
                }
            }
            .sheet(isPresented: $showEnd) {
                SessionEndSheet(controller: controller) {
                    controller.pauseClock()
                    onExit()
                }
            }
            .sheet(isPresented: $showReference) {
                NavigationStack {
                    ReferenceRail(controller: controller) { showReference = false }
                        .navigationTitle("Referencia")
                        #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) { Button("Listo") { showReference = false } }
                        }
                }
            }
        }
        .tint(controller.system.accent)
        .onChange(of: controller.adventure.guideData) { controller.reloadGuide() }
        .onAppear {
            controller.begin()
            #if DEBUG
            // Capturas: `-openPanel dice|party` abre ese panel al entrar. Se espera a que la
            // barra esté en pantalla: un popover sin vista de origen hace abortar a UIKit.
            let panel = UserDefaults.standard.string(forKey: "openPanel")
            // `-ask "pregunta"` la envía al tutor al entrar.
            let question = UserDefaults.standard.string(forKey: "ask")
            Task {
                try? await Task.sleep(for: .seconds(1))
                showDice = panel == "dice"
                showParty = panel == "party"
                showEnd = panel == "end"
                if panel == "combat" || panel == "combatstrip" {
                    if !controller.combat.isActive {
                        controller.addPartyToCombat()
                        controller.addEnemies(name: "Profundo", count: 3, stats: StatBlock(hp: 13, dexterity: 50))
                    }
                    showCombat = panel == "combat"
                }
                if panel == "handout", let scene = controller.currentScene {
                    debugHandout = Handout(title: scene.place, body: scene.readAloud, style: .narration)
                }
                if panel == "document", let clue = controller.guide?.clues.first {
                    debugHandout = Handout(title: clue.title, body: clue.detail, style: .document)
                }
                showMap = panel == "map"
                if let question { controller.send(question) }
            }
            #endif
        }
        .onDisappear { controller.pauseClock() }
        .handoutPresenter($debugHandout)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                // Si ha habido partida, primero el resumen; si solo se ha echado un vistazo, se sale.
                if controller.elapsed() > 300 || !Recap.ownNotes(controller.notes).isEmpty {
                    showEnd = true
                } else {
                    controller.pauseClock()
                    onExit()
                }
            } label: {
                // Vista propia: en la barra del iPad un Label se queda solo en icono.
                HStack(spacing: 4) {
                    Image(systemName: "chevron.backward")
                    Text("Salir")
                }
                .padding(.horizontal, 4)
            }
            .accessibilityLabel("Salir de la mesa")
            .keyboardShortcut(.escape, modifiers: .command)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            ClockButton(controller: controller)

            if controller.guide != nil {
                Button("Mapa", systemImage: "point.3.connected.trianglepath.dotted") { showMap = true }
                    .keyboardShortcut("m", modifiers: .command)
            }

            if sizeClass == .compact {
                Button("Referencia", systemImage: "list.bullet.rectangle") { showReference = true }
            }

            Button("Dados", systemImage: "dice") { showDice.toggle() }
                .keyboardShortcut("d", modifiers: .command)
                .popover(isPresented: $showDice) {
                    DiceView(system: controller.system) { note in controller.addNote(note) }
                        .frame(idealWidth: 380, idealHeight: 560)
                        .presentationCompactAdaptation(.sheet)
                }

            Button {
                showCombat.toggle()
            } label: {
                Label(controller.combat.isActive ? "Combate · asalto \(controller.combat.round)" : "Combate",
                      systemImage: controller.combat.isActive ? "figure.fencing.circle.fill" : "figure.fencing")
            }
            .keyboardShortcut("k", modifiers: .command)
            .popover(isPresented: $showCombat) {
                CombatView(controller: controller)
                    .frame(idealWidth: 420, idealHeight: 620)
                    .presentationCompactAdaptation(.sheet)
            }

            Button(controller.system.characterNoun, systemImage: "person.3") { showParty.toggle() }
                .keyboardShortcut("j", modifiers: .command)
                .popover(isPresented: $showParty) {
                    PartyView(controller: controller)
                        .frame(idealWidth: 420, idealHeight: 560)
                        .presentationCompactAdaptation(.sheet)
                }

            Button(showTutor ? "Ocultar tutor" : "Mostrar tutor", systemImage: "sidebar.right") {
                withAnimation(.snappy) { showTutor.toggle() }
            }
            .keyboardShortcut("t", modifiers: .command)
        }
    }
}

private struct ClockButton: View {
    let controller: PlayController

    var body: some View {
        Button {
            controller.toggleClock()
        } label: {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: 6) {
                    Image(systemName: controller.isClockRunning ? "timer" : "pause.circle.fill")
                    Text(Format.clock(controller.elapsed(at: context.date)))
                        .monospacedDigit()
                }
                .padding(.horizontal, 4)
                .foregroundStyle(controller.isClockRunning ? Color.primary : Color.orange)
            }
        }
        .help(controller.isClockRunning ? "Pausar el reloj de juego" : "Reanudar el reloj de juego")
    }
}

// MARK: - Columna central

private struct SceneColumn: View {
    let controller: PlayController
    var onOpenCombat: () -> Void = {}
    @State private var note = ""
    @FocusState private var noteFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Color.clear.frame(height: 0).id("top")
                    if let recap = controller.session.recap, !controller.session.recapDismissed {
                        PreviouslyCard(text: recap, title: controller.adventure.title, tint: controller.system.accent) {
                            withAnimation(.snappy) { controller.dismissRecap() }
                        }
                    }
                    if controller.combat.isActive {
                        CombatStrip(controller: controller, onOpen: onOpenCombat)
                    }
                    HintsBanner(controller: controller)
                    if let guide = controller.guide, let scene = controller.currentScene {
                        sceneHeader(scene, guide: guide)
                        SceneContent(scene: scene, guide: guide, system: controller.system, controller: controller)
                    } else {
                        noGuide
                    }
                    logbook
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 22)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: controller.currentSceneID) {
                withAnimation(.snappy) { proxy.scrollTo("top", anchor: .top) }
            }
        }
    }

    private func sceneHeader(_ scene: AdventureGuide.Scene, guide: AdventureGuide) -> some View {
        let index = (guide.scenes.firstIndex { $0.id == scene.id } ?? 0)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                (Text("ESCENA \(index + 1) DE \(guide.scenes.count)")
                    .foregroundStyle(controller.system.accent)
                    + Text(scene.act.isEmpty ? "" : "  ·  \(scene.act.uppercased())")
                    .foregroundStyle(.secondary))
                    .font(.caption.weight(.bold))
                    .tracking(0.6)
                    .lineLimit(1)
                Spacer()
                HStack(spacing: 4) {
                    Button { step(-1, guide) } label: { Image(systemName: "chevron.left") }
                        .disabled(index == 0)
                        .keyboardShortcut(.leftArrow, modifiers: .command)
                    Button { step(1, guide) } label: { Image(systemName: "chevron.right") }
                        .disabled(index >= guide.scenes.count - 1)
                        .keyboardShortcut(.rightArrow, modifiers: .command)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Text(scene.title).font(.title.weight(.bold)).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 14) {
                if !scene.place.isEmpty {
                    Label(scene.place, systemImage: "mappin.and.ellipse")
                }
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    let spent = Int((controller.elapsed(at: context.date) - controller.sceneEnteredAt) / 60)
                    Label("\(spent) de ~\(SessionPlanner.minutes(for: scene)) min", systemImage: "clock")
                        .monospacedDigit()
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    private func step(_ offset: Int, _ guide: AdventureGuide) {
        guard let index = guide.scenes.firstIndex(where: { $0.id == controller.currentSceneID }) else { return }
        let target = index + offset
        guard guide.scenes.indices.contains(target) else { return }
        withAnimation(.snappy) { controller.go(to: guide.scenes[target].id) }
    }

    private var noGuide: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Partida sin guía", systemImage: "book.closed").font(.headline)
            Text("Esta aventura aún no se ha analizado, así que no hay escenas que seguir. El tutor conoce el guion completo: pregúntale lo que necesites y apunta abajo lo que va pasando.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }

    private var logbook: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "Bitácora de la sesión", symbol: "pencil.and.list.clipboard")
            HStack(spacing: 8) {
                TextField("¿Qué ha pasado? Ej.: «Han convencido al farero»", text: $note)
                    .textFieldStyle(.roundedBorder)
                    .focused($noteFocused)
                    .onSubmit(save)
                Button("Anotar", action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(note.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text("El tutor lee estas notas para saber qué han hecho los jugadores.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(controller.notes.reversed()) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(Format.clock(entry.playTime))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 58, alignment: .leading)
                    Text(entry.text).font(.callout).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .contextMenu {
                    Button("Borrar nota", systemImage: "trash", role: .destructive) { controller.deleteNote(entry) }
                }
            }
        }
        .card()
    }

    private func save() {
        controller.addNote(note)
        note = ""
        noteFocused = true
    }
}

// MARK: - Combate en curso

/// Recordatorio del combate en la columna central: de quién es el turno y pasar al siguiente.
private struct CombatStrip: View {
    let controller: PlayController
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onOpen) {
                HStack(spacing: 10) {
                    Image(systemName: "figure.fencing").foregroundStyle(.red)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Combate · asalto \(controller.combat.round)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(controller.combat.current.map { "Turno de \($0.name)" } ?? "")
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                withAnimation(.snappy) { controller.nextTurn() }
            } label: {
                Image(systemName: "forward.fill")
                    .font(.callout.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Color.red, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Siguiente turno")
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.red.opacity(0.25)))
    }
}

// MARK: - Consejo del momento

/// Avisos del tutor proactivo: aparecen solos según el ritmo, las pistas y el estado de los personajes.
private struct HintsBanner: View {
    let controller: PlayController

    var body: some View {
        TimelineView(.periodic(from: .now, by: 20)) { context in
            let hints = controller.hints(at: context.date)
            if !hints.isEmpty {
                VStack(spacing: 8) {
                    ForEach(hints.prefix(2)) { hint in
                        HintRow(hint: hint) {
                            withAnimation(.snappy) { controller.dismiss(hint) }
                        }
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
}

private struct HintRow: View {
    let hint: CoachHint
    let onDismiss: () -> Void

    var body: some View {
        let tint: Color = hint.tone == .warning ? .orange : .accentColor
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: hint.symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(hint.title).font(.callout.weight(.semibold))
                Text(hint.message).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Descartar consejo")
        }
        .padding(12)
        .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tint.opacity(0.25)))
    }
}

// MARK: - Columna de referencia

/// Escenas, PNJ y pistas a un toque. En pantallas estrechas se abre como hoja.
struct ReferenceRail: View {
    let controller: PlayController
    var onNavigate: (() -> Void)?
    @State private var section: Section = .scenes
    @State private var shownNPC: AdventureGuide.NPC?

    enum Section: String, CaseIterable, Identifiable {
        case scenes = "Escenas", npcs = "PNJ", clues = "Pistas"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Referencia", selection: $section) {
                ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)

            if let guide = controller.guide {
                List {
                    switch section {
                    case .scenes: scenes(guide)
                    case .npcs: npcs(guide)
                    case .clues: clues(guide)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            } else {
                ContentUnavailableView("Sin guía", systemImage: "book.closed", description: Text("Analiza el guion para ver escenas, PNJ y pistas."))
            }
        }
        .sheet(item: $shownNPC) { npc in
            NavigationStack {
                ScrollView { NPCCard(npc: npc, framed: false).padding(24) }
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { shownNPC = nil } } }
            }
            .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private func scenes(_ guide: AdventureGuide) -> some View {
        ForEach(guide.scenes) { scene in
            let status = controller.status(of: scene)
            Button {
                withAnimation(.snappy) { controller.go(to: scene.id) }
                onNavigate?()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: icon(for: status))
                        .foregroundStyle(status == .pending ? Color.secondary : controller.system.accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(scene.title)
                            .font(.callout.weight(status == .current ? .semibold : .regular))
                            .foregroundStyle(status == .visited ? .secondary : .primary)
                            .lineLimit(2)
                        if !scene.place.isEmpty {
                            Text(scene.place).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(status == .current ? controller.system.accent.opacity(0.12) : Color.clear)
        }
        let progress = controller.coreProgress
        if progress.total > 0 {
            Label("Pistas clave: \(progress.found) de \(progress.total)", systemImage: "star.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.orange)
                .listRowBackground(Color.clear)
        }
    }

    private func icon(for status: PlayController.SceneStatus) -> String {
        switch status {
        case .current: "largecircle.fill.circle"
        case .visited: "checkmark.circle.fill"
        case .pending: "circle"
        }
    }

    @ViewBuilder
    private func npcs(_ guide: AdventureGuide) -> some View {
        let here = Set(controller.currentScene?.npcIDs ?? [])
        ForEach(guide.npcs.sorted { here.contains($0.id) && !here.contains($1.id) }) { npc in
            Button { shownNPC = npc } label: {
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.fill")
                        .foregroundStyle(here.contains(npc.id) ? controller.system.accent : .secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(npc.name).font(.callout.weight(.medium))
                        Text(npc.role).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    if here.contains(npc.id) {
                        Text("En escena").font(.caption2.weight(.semibold)).foregroundStyle(controller.system.accent)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func clues(_ guide: AdventureGuide) -> some View {
        ForEach(guide.clues) { clue in
            let found = controller.isFound(clue.id)
            Button { controller.toggleClue(clue.id) } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: found ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(found ? Color.green : Color.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(clue.title).font(.callout.weight(.medium)).strikethrough(found, color: .secondary)
                            if clue.isCore { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.orange) }
                        }
                        Text(guide.scene(clue.sceneID)?.title ?? "").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
