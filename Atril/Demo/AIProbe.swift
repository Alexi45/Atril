#if DEBUG
import Foundation

/// Diagnóstico de la IA integrada: `Atril -probeAI` analiza la aventura de ejemplo con cada
/// modelo disponible, hace una pregunta al tutor e imprime tiempos y resultados.
enum AIProbe {
    @MainActor
    static func run() async {
        setvbuf(stdout, nil, _IOLBF, 0)
        let status = AppleAI.status
        print("== Estado: \(status.tiers.map(\.rawValue)) · \(status.unavailableReason ?? "ok")")
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let requested = ProcessInfo.processInfo.environment["PROBE_TIERS"]?.split(separator: ",").compactMap { AppleAI.Tier(rawValue: String($0)) }
        for tier in requested ?? status.tiers {
            let start = Date()
            do {
                let guide = try await AppleAnalyzer.analyze(
                    title: SampleAdventure.title, script: SampleAdventure.script, system: .cthulhu, tier: tier
                ) { progress in print("   [\(tier.rawValue)] \(progress.phase)") }
                print("== \(tier.rawValue): guía en \(Int(Date().timeIntervalSince(start))) s")
                print("   premisa: \(guide.premise.truncated(words: 40))")
                print("   verdad: \(guide.truth.truncated(words: 40))")
                for scene in guide.scenes {
                    print("   · \(scene.id) \(scene.title) | PNJ \(scene.npcIDs.compactMap { guide.npc($0)?.name }) | tiradas \(scene.checks.map(\.skill))")
                    print("       resumen: \(scene.summary)")
                    print("       pistas: \(guide.clues(in: scene).map(\.title))")
                    for tip in scene.tips { print("       consejo: \(tip)") }
                    print("       si se atascan: \(scene.ifStuck)")
                }
                for npc in guide.npcs {
                    print("   PNJ \(npc.name): \(npc.role) | quiere: \(npc.motivation) | oculta: \(npc.secret) | voz: \(npc.voice)")
                }
                print("   pistas clave: \(guide.clues.filter(\.isCore).map(\.title))")

                let state = TutorPrompts.TableState(
                    system: .cthulhu, guide: guide, playTime: 3000, currentSceneID: guide.scenes.dropFirst(3).first?.id,
                    visitedSceneIDs: guide.scenes.prefix(3).map(\.id), foundClueIDs: [], players: [], notes: [
                        SessionNote(playTime: 2800, text: "No han pasado por la parroquia; van directos al faro."),
                    ]
                )
                let table = TableSnapshot(title: SampleAdventure.title, system: .cthulhu, guide: guide, state: state,
                                          index: ScriptIndex(script: SampleAdventure.script), recent: [])
                let question = "Están atascados delante de la lente y no saben qué significa el signo. ¿Qué hago?"
                let prompt = TutorContext.prompt(question: question, table: table, passages: AppleAI.passageCount(for: tier), generous: tier == .cloud)
                let askStart = Date()
                var answer = ""
                for try await text in AppleTutor.answer(prompt: prompt, system: .cthulhu, tier: tier) { answer = text }
                print("== \(tier.rawValue): tutor en \(Int(Date().timeIntervalSince(askStart))) s\n\(answer)\n")
            } catch {
                print("== \(tier.rawValue): ERROR \(error)")
            }
        }
        #endif
    }
}
#endif
