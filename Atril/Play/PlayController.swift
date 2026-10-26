import Foundation
import Observation
import SwiftData

/// Estado vivo de una partida. Trabaja en memoria y vuelca cada cambio a la sesión guardada.
@MainActor
@Observable
final class PlayController {
    let adventure: Adventure
    let session: PlaySession
    private(set) var guide: AdventureGuide?
    /// Buscador sobre el guion para que el tutor cite los pasajes relevantes.
    private(set) var index: ScriptIndex

    var currentSceneID: String? { didSet { sceneChanged(from: oldValue) } }
    private(set) var visitedSceneIDs: [String]
    private(set) var foundClueIDs: Set<String>
    private(set) var notes: [SessionNote]
    var players: [Player] {
        didSet {
            session.players = players
            syncCombatHP()
        }
    }
    private(set) var combat: Combat { didSet { session.combatData = (try? JSONEncoder().encode(combat)) ?? Data() } }
    private(set) var messages: [TutorMessage]

    // Tutor
    var draft = ""
    private(set) var streamingText = ""
    private(set) var isWaiting = false
    private(set) var isThinking = false
    var tutorError: String?
    private(set) var backend: AIBackend
    private var tutorTask: Task<Void, Never>?

    // Tutor proactivo
    private(set) var sceneEnteredAt: TimeInterval
    private var sanityAtSceneStart: [UUID: Int] = [:]
    private(set) var leftBehind: [AdventureGuide.Clue] = []
    private(set) var dismissedHints: Set<String> = []

    // Cronómetro de juego
    private(set) var isClockRunning = false
    private var storedElapsed: TimeInterval
    private var resumedAt: Date?

    init(session: PlaySession) {
        self.session = session
        self.adventure = session.adventure!
        self.guide = session.adventure?.guide
        self.index = ScriptIndex(script: session.adventure?.script ?? "")
        self.currentSceneID = session.currentSceneID ?? session.adventure?.guide?.scenes.first?.id
        self.visitedSceneIDs = session.visitedSceneIDs
        self.foundClueIDs = Set(session.foundClueIDs)
        self.notes = session.notes
        self.players = session.players
        self.combat = (try? JSONDecoder().decode(Combat.self, from: session.combatData)) ?? Combat()
        self.messages = session.chat
        self.storedElapsed = session.elapsed
        self.sceneEnteredAt = session.elapsed
        self.backend = .current
        self.sanityAtSceneStart = Dictionary(uniqueKeysWithValues: session.players.map { ($0.id, $0.sanity) })
    }

    var system: GameSystem { adventure.system }
    var currentScene: AdventureGuide.Scene? { guide?.scene(currentSceneID) }

    /// Al abrir la mesa: arranca el reloj y marca la escena actual como jugada.
    func begin() {
        markVisited()
        startClock()
        refreshBackend()
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *), case .apple(let tier) = backend { AppleSessions.prewarm(tier) }
        #endif
    }

    /// La IA terminó de preparar la guía mientras se jugaba.
    func reloadGuide() {
        guide = adventure.guide
        index = ScriptIndex(script: adventure.script)
        currentSceneID = session.currentSceneID ?? guide?.scenes.first?.id
        visitedSceneIDs = session.visitedSceneIDs
        foundClueIDs = Set(session.foundClueIDs)
    }

    func refreshBackend() {
        backend = .current
    }

    // MARK: Escenas y pistas

    func go(to sceneID: String) {
        guard sceneID != currentSceneID else { return }
        currentSceneID = sceneID
    }

    func status(of scene: AdventureGuide.Scene) -> SceneStatus {
        if scene.id == currentSceneID { return .current }
        return visitedSceneIDs.contains(scene.id) ? .visited : .pending
    }

    enum SceneStatus { case current, visited, pending }

    func toggleClue(_ id: String) {
        if foundClueIDs.contains(id) {
            foundClueIDs.remove(id)
        } else {
            foundClueIDs.insert(id)
            leftBehind.removeAll { $0.id == id }
            if let clue = guide?.clue(id) { addNote("Descubren la pista: \(clue.title)") }
        }
        session.foundClueIDs = Array(foundClueIDs).sorted()
        touch()
    }

    func isFound(_ id: String) -> Bool { foundClueIDs.contains(id) }

    var coreProgress: (found: Int, total: Int) {
        let core = guide?.clues.filter(\.isCore) ?? []
        return (core.filter { foundClueIDs.contains($0.id) }.count, core.count)
    }

    private func sceneChanged(from previous: String?) {
        markVisited()
        // Pistas clave de la escena que dejan atrás sin haberlas encontrado.
        if let guide, let previous = guide.scene(previous) {
            leftBehind = guide.clues(in: previous).filter { $0.isCore && !foundClueIDs.contains($0.id) }
        } else {
            leftBehind = []
        }
        sceneEnteredAt = elapsed()
        sanityAtSceneStart = Dictionary(uniqueKeysWithValues: players.map { ($0.id, $0.sanity) })
    }

    private func markVisited() {
        if let id = currentSceneID, !visitedSceneIDs.contains(id) {
            visitedSceneIDs.append(id)
            session.visitedSceneIDs = visitedSceneIDs
        }
        session.currentSceneID = currentSceneID
        touch()
    }

    // MARK: Tutor proactivo

    func hints(at date: Date = .now) -> [CoachHint] {
        let now = elapsed(at: date)
        let lastNote = notes.last?.playTime
        let state = Coach.State(
            system: system, guide: guide, sceneID: currentSceneID,
            timeInScene: now - sceneEnteredAt, sessionElapsed: now, sessionHours: adventure.sessionHours,
            players: players, sanityAtSceneStart: sanityAtSceneStart,
            minutesSinceLastNote: lastNote.map { (now - $0) / 60 } ?? (now > 20 * 60 ? now / 60 : nil),
            leftBehind: leftBehind
        )
        return Coach.hints(state).filter { !dismissedHints.contains($0.id) }
    }

    func dismiss(_ hint: CoachHint) {
        dismissedHints.insert(hint.id)
    }

    // MARK: Notas

    func addNote(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        notes.append(SessionNote(playTime: elapsed(), sceneID: currentSceneID, text: trimmed))
        session.notes = notes
        touch()
    }

    func deleteNote(_ note: SessionNote) {
        notes.removeAll { $0.id == note.id }
        session.notes = notes
    }

    // MARK: Cronómetro

    func elapsed(at date: Date = .now) -> TimeInterval {
        storedElapsed + (resumedAt.map { date.timeIntervalSince($0) } ?? 0)
    }

    func startClock() {
        guard !isClockRunning else { return }
        resumedAt = .now
        isClockRunning = true
    }

    func pauseClock() {
        guard isClockRunning else { return }
        storedElapsed = elapsed()
        resumedAt = nil
        isClockRunning = false
        session.elapsed = storedElapsed
        touch()
    }

    func toggleClock() { isClockRunning ? pauseClock() : startClock() }

    private func touch() { session.lastPlayedAt = .now }

    // MARK: Combate

    /// Añade a la mesa entera. En Cthulhu la iniciativa es la DES (por defecto 50, editable);
    /// en D&D se tira un d20 que el máster puede corregir con el modificador.
    func addPartyToCombat(dice: Dice = Dice()) {
        let present = Set(combat.combatants.compactMap(\.playerID))
        let new = players.filter { !present.contains($0.id) }.map { player in
            Combatant(
                name: player.character.isEmpty ? (player.name.isEmpty ? "Personaje" : player.name) : player.character,
                initiative: system == .cthulhu ? 50 : dice.roll(20), hp: player.hp, hpMax: player.hpMax, playerID: player.id
            )
        }
        combat.add(new)
    }

    /// Añade `count` enemigos iguales («Profundo 1», «Profundo 2»…) con sus estadísticas.
    func addEnemies(name: String, count: Int, stats: StatBlock, dice: Dice = Dice()) {
        let base = name.trimmed.isEmpty ? "Enemigo" : name.trimmed
        let new = (1...max(count, 1)).map { index in
            Combatant(
                name: count > 1 ? "\(base) \(index)" : base,
                initiative: stats.initiative(system: system, roll: dice.roll),
                hp: stats.hp, hpMax: stats.hp
            )
        }
        combat.add(new)
    }

    func nextTurn() { combat.next() }
    func previousTurn() { combat.previous() }
    func setInitiative(_ value: Int, for id: UUID) { combat.setInitiative(value, for: id) }
    func removeFromCombat(_ id: UUID) { combat.remove(id) }

    /// PV de un participante: los de los personajes viven en su ficha.
    func hp(of combatant: Combatant) -> (current: Int, max: Int)? {
        if let playerID = combatant.playerID, let player = players.first(where: { $0.id == playerID }) {
            return (player.hp, player.hpMax)
        }
        guard let hp = combatant.hp else { return nil }
        return (hp, combatant.hpMax ?? hp)
    }

    func isDown(_ combatant: Combatant) -> Bool { (hp(of: combatant)?.current ?? 1) <= 0 }

    func changeHP(of combatant: Combatant, by amount: Int) {
        if let playerID = combatant.playerID, let index = players.firstIndex(where: { $0.id == playerID }) {
            players[index].hp += amount
        } else {
            combat.changeHP(combatant.id, by: amount)
        }
    }

    /// Los PV de los personajes se pueden tocar desde su ficha: el combate se pone al día
    /// para saber quién ha caído y saltar su turno.
    private func syncCombatHP() {
        guard combat.isActive else { return }
        var updated = combat
        for index in updated.combatants.indices {
            guard let playerID = updated.combatants[index].playerID,
                  let player = players.first(where: { $0.id == playerID }) else { continue }
            updated.combatants[index].hp = player.hp
            updated.combatants[index].hpMax = player.hpMax
        }
        if updated != combat { combat = updated }
    }

    func endCombat() {
        guard combat.isActive else { return }
        addNote("Combate terminado tras \(combat.round) \(combat.round == 1 ? "asalto" : "asaltos").")
        combat = Combat()
    }

    // MARK: Resumen de sesión

    var recapFacts: Recap.Facts {
        Recap.Facts(title: adventure.title, system: system, guide: guide, notes: notes, visitedSceneIDs: visitedSceneIDs,
                    foundClueIDs: foundClueIDs, currentSceneID: currentSceneID, players: players)
    }

    func savePlayerSummary(_ text: String) {
        session.playerSummary = text
        touch()
    }

    func dismissRecap() {
        session.recapDismissed = true
    }

    // MARK: Tutor

    var tableState: TutorPrompts.TableState {
        TutorPrompts.TableState(
            system: system, guide: guide, playTime: elapsed(), currentSceneID: currentSceneID,
            visitedSceneIDs: visitedSceneIDs, foundClueIDs: foundClueIDs, players: players, notes: notes
        )
    }

    var snapshot: TableSnapshot {
        TableSnapshot(title: adventure.title, system: system, guide: guide, state: tableState, index: index, recent: messages)
    }

    func send(_ question: String) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isWaiting else { return }
        tutorError = nil
        draft = ""
        refreshBackend()

        isWaiting = true
        isThinking = false
        streamingText = ""

        switch backend {
        case .claude:
            let text = "\(TutorPrompts.stateBlock(tableState))\n\n\(trimmed)"
            messages.append(TutorMessage(role: .user, display: trimmed, content: .string(text)))
            tutorTask = Task { await runClaude(retryingWithoutThinking: false, question: trimmed) }
        case .apple(let tier):
            let table = snapshot
            messages.append(TutorMessage(role: .user, display: trimmed, content: .string(trimmed)))
            tutorTask = Task { await runApple(question: trimmed, table: table, tier: tier) }
        case .basic:
            let table = snapshot
            messages.append(TutorMessage(role: .user, display: trimmed, content: .string(trimmed)))
            finish(with: BasicTutor.answer(trimmed, table: table))
        }
    }

    func cancelTutor() {
        tutorTask?.cancel()
    }

    private func finish(with answer: String) {
        messages.append(TutorMessage(role: .assistant, display: answer, content: .string(answer)))
        session.chat = messages
        touch()
        streamingText = ""
        isWaiting = false
        isThinking = false
    }

    private func fail(_ error: Error, question: String) {
        // La pregunta no obtuvo respuesta: se retira del historial y vuelve al campo de texto.
        if messages.last?.role == .user { messages.removeLast() }
        if !(error is CancellationError) {
            tutorError = error.localizedDescription
            draft = question
        }
        streamingText = ""
        isWaiting = false
        isThinking = false
    }

    private func runApple(question: String, table: TableSnapshot, tier: AppleAI.Tier) async {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, macOS 26.0, *) else { return finish(with: BasicTutor.answer(question, table: table)) }
        isThinking = true
        var passages = AppleAI.passageCount(for: tier)
        var currentTier = tier
        while true {
            let prompt = TutorContext.prompt(question: question, table: table, passages: passages, generous: currentTier == .cloud)
            do {
                var answer = ""
                for try await text in AppleTutor.answer(prompt: prompt, system: system, tier: currentTier) {
                    isThinking = false
                    answer = text
                    streamingText = text
                }
                return finish(with: answer)
            } catch is CancellationError {
                return fail(CancellationError(), question: question)
            } catch {
                switch AppleAI.Failure.classify(error) {
                case .contextTooLarge where passages > 1:
                    passages /= 2
                case .quota where currentTier == .cloud, .other where currentTier == .cloud, .unavailable where currentTier == .cloud:
                    currentTier = .onDevice
                    passages = AppleAI.passageCount(for: .onDevice)
                case .guardrail:
                    // Al horror de los guiones a veces le saltan los filtros: se responde con la guía.
                    return finish(with: BasicTutor.answer(question, table: table)
                        + "\n\n_La IA de Apple no ha querido responder a esto; te dejo lo que dice la guía._")
                default:
                    return finish(with: BasicTutor.answer(question, table: table))
                }
            }
        }
        #else
        finish(with: BasicTutor.answer(question, table: table))
        #endif
    }

    private var contextHash: String {
        Adventure.hash(TutorPrompts.tutorSystem(system) + TutorPrompts.scriptContext(title: adventure.title, script: adventure.script, guide: guide))
    }

    private func runClaude(retryingWithoutThinking: Bool, question: String) async {
        let hash = contextHash
        var history = messages
        // Si el guion cambió desde respuestas anteriores, sus bloques de razonamiento ya no
        // son válidos para este contexto: se quitan una vez y la conversación sigue.
        let contextChanged = history.contains { $0.role == .assistant && $0.contextHash != nil && $0.contextHash != hash }
        if contextChanged || retryingWithoutThinking {
            history = TutorService.strippingThinking(history)
        }

        let body = TutorService.chatBody(adventure: adventure, history: history, depth: .current)
        let client = ClaudeClient(apiKey: KeychainStore.apiKey)
        do {
            for try await event in client.stream(body) {
                switch event {
                case .thinking:
                    isThinking = true
                case .textDelta(let delta):
                    isThinking = false
                    streamingText += delta
                case .finished(let response):
                    if contextChanged || retryingWithoutThinking {
                        messages = history
                    }
                    messages.append(TutorMessage(
                        role: .assistant, display: response.text,
                        content: .array(response.content), contextHash: hash
                    ))
                    session.chat = messages
                    touch()
                }
            }
        } catch ClaudeClient.Failure.badRequest(let message) where !retryingWithoutThinking && message.localizedCaseInsensitiveContains("thinking") {
            await runClaude(retryingWithoutThinking: true, question: question)
            return
        } catch {
            return fail(error, question: question)
        }
        streamingText = ""
        isWaiting = false
        isThinking = false
    }

    func clearChat() {
        guard !isWaiting else { return }
        messages = []
        session.chat = []
    }
}
