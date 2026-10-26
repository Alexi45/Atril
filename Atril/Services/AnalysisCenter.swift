import Foundation
import Observation

/// Lleva los análisis en curso para que sobrevivan a la navegación entre aventuras.
///
/// Al importar, la guía básica (heurística) aparece al instante; si hay IA disponible, se
/// sustituye después por la que prepara la IA, sin que el máster tenga que esperar.
@MainActor
@Observable
final class AnalysisCenter {
    struct Job {
        var startedAt = Date()
        var backend: AIBackend
        var phase = "Preparando…"
        var done = 0
        var total = 0
        /// Para Claude: escenas detectadas mientras llega la respuesta.
        var scenesFound = 0

        var fraction: Double? { total > 0 ? Double(done) / Double(total) : nil }
    }

    private(set) var jobs: [UUID: Job] = [:]
    private(set) var errors: [UUID: String] = [:]
    private var tasks: [UUID: Task<Void, Never>] = [:]

    func isRunning(_ adventure: Adventure) -> Bool { jobs[adventure.id] != nil }
    func job(for adventure: Adventure) -> Job? { jobs[adventure.id] }
    func error(for adventure: Adventure) -> String? { errors[adventure.id] }

    /// Guía básica inmediata, sin modelo.
    func organizeBasic(_ adventure: Adventure) {
        let guide = HeuristicAnalyzer.analyze(script: adventure.script, system: adventure.system)
        apply(guide, engine: "basic", to: adventure)
    }

    /// Prepara la guía con el mejor motor disponible (o el indicado).
    func start(_ adventure: Adventure, backend: AIBackend = .current) {
        let id = adventure.id
        guard jobs[id] == nil else { return }
        errors[id] = nil
        if adventure.guideData == nil { organizeBasic(adventure) }
        guard backend != .basic else {
            organizeBasic(adventure)
            return
        }
        jobs[id] = Job(backend: backend)
        let title = adventure.title
        let script = adventure.script
        let system = adventure.system

        tasks[id] = Task { [weak self] in
            do {
                switch backend {
                case .claude:
                    let guide = try await TutorService.analyze(title: title, script: script, system: system) { count in
                        self?.jobs[id]?.scenesFound = count
                        self?.jobs[id]?.phase = count == 0 ? "Claude está leyendo el guion…" : "\(count) escenas preparadas"
                    }
                    self?.apply(guide, engine: "claude", to: adventure)
                case .apple(let tier):
                    try await self?.runApple(adventure, title: title, script: script, system: system, tier: tier)
                case .basic:
                    break
                }
            } catch is CancellationError {
            } catch {
                self?.errors[id] = error.localizedDescription
            }
            self?.jobs[id] = nil
            self?.tasks[id] = nil
        }
    }

    private func runApple(_ adventure: Adventure, title: String, script: String, system: GameSystem, tier: AppleAI.Tier) async throws {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, macOS 26.0, *) else { throw AppleAI.Failure.unavailable }
        let id = adventure.id
        do {
            var guide = try await AppleAnalyzer.analyze(title: title, script: script, system: system, tier: tier) { [weak self] progress in
                self?.jobs[id]?.phase = progress.phase
                self?.jobs[id]?.done = progress.done
                self?.jobs[id]?.total = progress.total
            }
            // Si la IA se ha saltado buena parte de las escenas, se quedan las de la guía básica
            // y de la IA solo se aprovecha la visión de conjunto.
            let basic = HeuristicAnalyzer.analyze(script: script, system: system)
            if Double(guide.scenes.count) < Double(basic.scenes.count) * 0.75 {
                var hybrid = basic
                hybrid.premise = guide.premise.isEmpty ? basic.premise : guide.premise
                hybrid.truth = guide.truth.isEmpty ? basic.truth : guide.truth
                hybrid.hook = guide.hook.isEmpty ? basic.hook : guide.hook
                hybrid.tone = guide.tone
                hybrid.prep = guide.prep.isEmpty ? basic.prep : guide.prep
                hybrid.endings = guide.endings.isEmpty ? basic.endings : guide.endings
                guide = hybrid
            }
            apply(guide, engine: tier.rawValue, to: adventure)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // La nube privada no siempre responde: se repite en el dispositivo.
            guard tier == .cloud, AppleAI.status.tiers.contains(.onDevice) else { throw error }
            jobs[id]?.backend = .apple(.onDevice)
            try await runApple(adventure, title: title, script: script, system: system, tier: .onDevice)
        }
        #else
        throw AppleAI.Failure.unavailable
        #endif
    }

    func cancel(_ adventure: Adventure) {
        tasks[adventure.id]?.cancel()
    }

    /// Sustituye la guía y recoloca las sesiones en las escenas equivalentes de la nueva.
    private func apply(_ guide: AdventureGuide, engine: String, to adventure: Adventure) {
        let old = adventure.guide
        adventure.guide = guide
        adventure.guideEngine = engine
        func remap(_ id: String?) -> String? {
            guard let id, let title = old?.scene(id)?.title else { return nil }
            return guide.scenes.first { Prose.matches($0.title, title) }?.id
        }
        func remapClue(_ id: String) -> String? {
            guard let title = old?.clue(id)?.title else { return nil }
            return guide.clues.first { Prose.matches($0.title, title) }?.id
        }
        for session in adventure.sessions {
            session.currentSceneID = remap(session.currentSceneID) ?? guide.scenes.first?.id
            session.visitedSceneIDs = session.visitedSceneIDs.compactMap(remap)
            session.foundClueIDs = session.foundClueIDs.compactMap(remapClue)
        }
    }
}
