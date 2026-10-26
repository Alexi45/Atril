import SwiftUI

struct DiceView: View {
    let system: GameSystem
    /// Anota la tirada en la bitácora.
    let onLog: (String) -> Void

    @State private var skill = 50
    @State private var bonus = 0
    @State private var modifier = 0
    @State private var difficulty = 12
    @State private var advantage: Dice.Advantage = .normal
    @State private var poolCount = 1
    @State private var history: [Roll] = []
    @State private var logged: Set<UUID> = []

    private let dice = Dice()

    struct Roll: Identifiable {
        let id = UUID()
        let title: String
        let value: String
        let detail: String
        var tone: Tone = .neutral
        enum Tone { case good, great, bad, awful, neutral }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                switch system {
                case .cthulhu: cthulhuCheck
                case .dnd: dndCheck
                case .other: EmptyView()
                }
                quickDice
                if !history.isEmpty { historyList }
            }
            .padding(18)
        }
    }

    // MARK: Cthulhu

    private var cthulhuCheck: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "Tirada de habilidad", symbol: "percent")
            HStack {
                Text("Habilidad")
                Spacer()
                Stepper(value: $skill, in: 1...99, step: 5) {
                    Text("\(skill) %").font(.title3.weight(.semibold).monospacedDigit())
                }
                .fixedSize()
            }
            Text("Difícil \(skill / 2) · Extremo \(skill / 5)").font(.caption).foregroundStyle(.secondary)
            Picker("Dados extra", selection: $bonus) {
                Text("−2").tag(-2)
                Text("−1").tag(-1)
                Text("Normal").tag(0)
                Text("+1").tag(1)
                Text("+2").tag(2)
            }
            .pickerStyle(.segmented)
            Text("Negativo: dados de penalización. Positivo: de bonificación.").font(.caption).foregroundStyle(.secondary)
            Button {
                let result = dice.percentile(skill: skill, bonus: bonus)
                let tone: Roll.Tone = switch result.result {
                case .critical, .extreme: .great
                case .hard, .regular: .good
                case .failure: .bad
                case .fumble: .awful
                }
                push(Roll(title: "Habilidad \(skill) %\(bonus == 0 ? "" : " (\(bonus > 0 ? "+" : "")\(bonus))")",
                          value: "\(result.value)", detail: result.result.rawValue, tone: tone))
            } label: {
                Label("Tirar d100", systemImage: "dice.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: [])
        }
        .card()
    }

    // MARK: D&D

    private var dndCheck: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "Prueba con d20", symbol: "die.face.5")
            HStack {
                Text("Modificador")
                Spacer()
                Stepper(value: $modifier, in: -5...15) {
                    Text(modifier >= 0 ? "+\(modifier)" : "\(modifier)").font(.title3.weight(.semibold).monospacedDigit())
                }
                .fixedSize()
            }
            HStack {
                Text("CD")
                Spacer()
                Stepper(value: $difficulty, in: 5...30) {
                    Text("\(difficulty)").font(.title3.weight(.semibold).monospacedDigit())
                }
                .fixedSize()
            }
            Picker("Ventaja", selection: $advantage) {
                ForEach(Dice.Advantage.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            Button {
                let result = dice.d20(modifier: modifier, advantage: advantage)
                let success = result.total >= difficulty
                let detail: String
                let tone: Roll.Tone
                if result.natural == 20 { detail = "¡20 natural!"; tone = .great }
                else if result.natural == 1 { detail = "1 natural"; tone = .awful }
                else { detail = success ? "Supera la CD \(difficulty)" : "No supera la CD \(difficulty)"; tone = success ? .good : .bad }
                let faces = result.faces.count > 1 ? " [\(result.faces.map(String.init).joined(separator: ", "))]" : ""
                push(Roll(title: "d20\(modifier >= 0 ? "+" : "")\(modifier)\(faces)", value: "\(result.total)", detail: detail, tone: tone))
            } label: {
                Label("Tirar d20", systemImage: "dice.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: [])
        }
        .card()
    }

    // MARK: Dados rápidos

    private var quickDice: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(title: "Dados rápidos", symbol: "dice")
                Spacer()
                Stepper("\(poolCount) ×", value: $poolCount, in: 1...10)
                    .font(.callout.monospacedDigit())
                    .fixedSize()
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach([3, 4, 6, 8, 10, 12, 20, 100], id: \.self) { sides in
                    Button {
                        let pool = Dice.Pool(count: poolCount, sides: sides, modifier: 0)
                        let result = dice.roll(pool)
                        push(Roll(title: pool.label, value: "\(result.total)",
                                  detail: result.faces.count > 1 ? result.faces.map(String.init).joined(separator: " + ") : ""))
                    } label: {
                        Text("d\(sides)")
                            .font(.callout.weight(.semibold).monospacedDigit())
                            .frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .card()
    }

    private var historyList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(title: "Últimas tiradas", symbol: "clock.arrow.circlepath")
                Spacer()
                Button("Borrar") { history.removeAll() }.font(.caption).buttonStyle(.borderless)
            }
            ForEach(Array(history.enumerated()), id: \.element.id) { index, roll in
                HStack(spacing: 12) {
                    Text(roll.value)
                        .font((index == 0 ? Font.largeTitle : .title3).weight(.bold).monospacedDigit())
                        .foregroundStyle(color(roll.tone))
                        .frame(minWidth: index == 0 ? 72 : 48, alignment: .leading)
                        .contentTransition(.numericText())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(roll.title).font(.callout.weight(.medium))
                        if !roll.detail.isEmpty {
                            Text(roll.detail).font(.caption).foregroundStyle(color(roll.tone))
                        }
                    }
                    Spacer()
                    Button {
                        onLog("Tirada \(roll.title): \(roll.value)\(roll.detail.isEmpty ? "" : " (\(roll.detail))")")
                        logged.insert(roll.id)
                    } label: {
                        Image(systemName: logged.contains(roll.id) ? "checkmark" : "square.and.pencil")
                    }
                    .buttonStyle(.borderless)
                    .disabled(logged.contains(roll.id))
                    .help("Anotar en la bitácora")
                }
            }
        }
        .card()
    }

    private func push(_ roll: Roll) {
        withAnimation(.snappy) {
            history.insert(roll, at: 0)
            if history.count > 8 { history.removeLast() }
        }
    }

    private func color(_ tone: Roll.Tone) -> Color {
        switch tone {
        case .great: .green
        case .good: .teal
        case .bad: .orange
        case .awful: .red
        case .neutral: .primary
        }
    }
}
