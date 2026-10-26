import Foundation

/// Organiza la aventura en sesiones según el tiempo que suele llevar cada escena.
enum SessionPlanner {
    struct PlannedSession: Hashable, Identifiable {
        var number: Int
        var sceneIDs: [String]
        var minutes: Int
        var id: Int { number }
    }

    /// Minutos aproximados que lleva jugar una escena.
    static func minutes(for scene: AdventureGuide.Scene) -> Int {
        var total = 12
        total += scene.checks.filter { $0.skill != "Cordura" }.count * 4
        total += scene.clueIDs.count * 3
        total += min(scene.npcIDs.count, 4) * 3
        if !scene.readAloud.isEmpty { total += 3 }
        let danger = Prose.fold(scene.danger)
        if ["combate", "ataca", "lucha", "pelea", "pv", "garras", "dano"].contains(where: danger.contains) {
            total += 15
        } else if !danger.isEmpty {
            total += 5
        }
        return min(max(Int((Double(total) / 5).rounded()) * 5, 10), 60)
    }

    static func totalMinutes(_ guide: AdventureGuide) -> Int {
        guide.scenes.map(minutes(for:)).reduce(0, +)
    }

    /// Reparte las escenas en sesiones de `hours` horas sin partir ninguna escena.
    /// Se reserva un 15 % del tiempo para charla, descansos y recapitular.
    static func plan(_ guide: AdventureGuide, hours: Double) -> [PlannedSession] {
        let budget = Int(hours * 60 * 0.85)
        var sessions: [PlannedSession] = []
        var current = PlannedSession(number: 1, sceneIDs: [], minutes: 0)
        for scene in guide.scenes {
            let cost = minutes(for: scene)
            if !current.sceneIDs.isEmpty && current.minutes + cost > budget {
                sessions.append(current)
                current = PlannedSession(number: current.number + 1, sceneIDs: [], minutes: 0)
            }
            current.sceneIDs.append(scene.id)
            current.minutes += cost
        }
        if !current.sceneIDs.isEmpty { sessions.append(current) }
        return sessions
    }
}

/// Consejos que el tutor da por su cuenta, sin que se los pidan, a partir del estado de la mesa.
struct CoachHint: Identifiable, Hashable {
    enum Tone { case info, warning }

    var id: String
    var symbol: String
    var title: String
    var message: String
    var tone: Tone = .info
}

enum Coach {
    struct State {
        var system: GameSystem
        var guide: AdventureGuide?
        var sceneID: String?
        var timeInScene: TimeInterval
        var sessionElapsed: TimeInterval
        var sessionHours: Double
        var players: [Player]
        /// Cordura de cada personaje al entrar en la escena.
        var sanityAtSceneStart: [UUID: Int]
        var minutesSinceLastNote: Double?
        /// Pistas clave de la escena anterior que se quedaron sin descubrir.
        var leftBehind: [AdventureGuide.Clue]
    }

    static func hints(_ state: State) -> [CoachHint] {
        var hints: [CoachHint] = []
        let scene = state.guide?.scene(state.sceneID)

        if !state.leftBehind.isEmpty {
            let titles = state.leftBehind.map { "«\($0.title)»" }.joined(separator: ", ")
            hints.append(CoachHint(
                id: "left-\(state.sceneID ?? "")", symbol: "star.slash", title: "Se dejaron una pista clave",
                message: "No descubrieron \(titles). Haz que aparezca aquí: en un objeto, en boca de un PNJ o como recuerdo de un personaje.",
                tone: .warning
            ))
        }

        if let scene, state.timeInScene < 90, !scene.readAloud.isEmpty {
            hints.append(CoachHint(
                id: "open-\(scene.id)", symbol: "quote.opening", title: "Abre la escena",
                message: "Empieza leyendo el texto en voz alta y termina con «¿Qué hacéis?»."
            ))
        }

        if let scene {
            let expected = Double(SessionPlanner.minutes(for: scene))
            let spent = state.timeInScene / 60
            if spent > expected * 1.6 && spent > 15 {
                hints.append(CoachHint(
                    id: "slow-\(scene.id)", symbol: "hourglass", title: "Esta escena se alarga",
                    message: "Lleváis \(Int(spent)) min (suele durar unos \(Int(expected))). \(scene.ifStuck.isEmpty ? "Si la mesa decae, haz que pase algo que les empuje a la siguiente escena." : scene.ifStuck)",
                    tone: .warning
                ))
            }
        }

        let target = state.sessionHours * 3600
        let remaining = target - state.sessionElapsed
        if target > 0, remaining < 20 * 60, remaining > -30 * 60, state.sessionElapsed > 30 * 60 {
            hints.append(CoachHint(
                id: "ending-\(Int(target))", symbol: "flag.checkered", title: remaining > 0 ? "Quedan unos \(max(Int(remaining / 60), 1)) min" : "Habéis pasado del tiempo previsto",
                message: "Busca un buen punto para cerrar la sesión: una revelación o un peligro inminente dejan ganas de volver."
            ))
        }

        for player in state.players {
            let name = player.character.isEmpty ? player.name : player.character
            guard !name.isEmpty else { continue }
            if player.hp <= 0 {
                hints.append(CoachHint(
                    id: "down-\(player.id)", symbol: "cross.case", title: "\(name) está fuera de combate",
                    message: state.system == .dnd
                        ? "A 0 PV: salvaciones contra muerte cada turno (10 o más es éxito; tres de cada deciden)."
                        : "A 0 PV: inconsciente; si además sufrió una herida grave, está moribundo y necesita Primeros auxilios ya.",
                    tone: .warning
                ))
            } else if player.hpMax > 0, Double(player.hp) <= Double(player.hpMax) / 2 {
                hints.append(CoachHint(
                    id: "hurt-\(player.id)-\(player.hp)", symbol: "bandage", title: "\(name) va muy tocado",
                    message: state.system == .dnd
                        ? "Recuérdales que pueden descansar o usar pociones. Un enemigo listo iría a por el más débil."
                        : "Si perdió la mitad de sus PV de un golpe es una herida grave: tirada de CON para no desmayarse."
                ))
            }
            if state.system.tracksSanity, let start = state.sanityAtSceneStart[player.id], start - player.sanity >= 5 {
                hints.append(CoachHint(
                    id: "insane-\(player.id)-\(player.sanity)", symbol: "brain.head.profile", title: "\(name) ha perdido \(start - player.sanity) de Cordura",
                    message: "Cinco o más de golpe: tirada de INT. Si la supera, comprende lo que ha visto y sufre locura temporal (1D10 horas).",
                    tone: .warning
                ))
            }
        }

        if let minutes = state.minutesSinceLastNote, minutes > 25, state.sessionElapsed > 20 * 60 {
            hints.append(CoachHint(
                id: "notes-\(Int(minutes / 25))", symbol: "pencil.and.list.clipboard", title: "Apunta lo último que ha pasado",
                message: "Una línea en la bitácora basta: así el tutor sabe qué han hecho y te aconseja mejor."
            ))
        }
        return hints
    }
}
