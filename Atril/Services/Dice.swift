import Foundation

/// Motor de tiradas. Recibe el generador para poder probarlo con resultados fijos.
struct Dice {
    var roll: (Int) -> Int = { sides in Int.random(in: 1...sides) }

    // MARK: Tirada libre: NdX + mod

    struct Pool: Hashable {
        var count: Int
        var sides: Int
        var modifier: Int

        var label: String {
            let base = "\(count)d\(sides)"
            if modifier == 0 { return base }
            return modifier > 0 ? "\(base)+\(modifier)" : "\(base)\(modifier)"
        }
    }

    func roll(_ pool: Pool) -> (total: Int, faces: [Int]) {
        let faces = (0..<max(pool.count, 1)).map { _ in roll(pool.sides) }
        return (faces.reduce(0, +) + pool.modifier, faces)
    }

    // MARK: La llamada de Cthulhu (7.ª ed.)

    enum CthulhuResult: String {
        case critical = "Crítico"
        case extreme = "Éxito extremo"
        case hard = "Éxito difícil"
        case regular = "Éxito"
        case failure = "Fallo"
        case fumble = "Pifia"

        var isSuccess: Bool { [.critical, .extreme, .hard, .regular].contains(self) }
    }

    /// `bonus` > 0 son dados de bonificación; < 0, de penalización.
    func percentile(skill: Int, bonus: Int = 0) -> (value: Int, tens: [Int], result: CthulhuResult) {
        let units = roll(10) - 1
        let tensCount = 1 + abs(bonus)
        let tens = (0..<tensCount).map { _ in (roll(10) - 1) * 10 }
        let candidates = tens.map { ten -> Int in
            let value = ten + units
            return value == 0 ? 100 : value
        }
        let value = bonus >= 0 ? candidates.min()! : candidates.max()!
        return (value, tens, Self.grade(value, skill: skill))
    }

    static func grade(_ value: Int, skill: Int) -> CthulhuResult {
        if value == 1 { return .critical }
        let fumbleFloor = skill < 50 ? 96 : 100
        if value >= fumbleFloor { return .fumble }
        if value <= skill / 5 { return .extreme }
        if value <= skill / 2 { return .hard }
        if value <= skill { return .regular }
        return .failure
    }

    // MARK: Dungeons & Dragons (5.ª ed.)

    enum Advantage: Int, CaseIterable {
        case disadvantage = -1, normal = 0, advantage = 1

        var label: String {
            switch self {
            case .disadvantage: "Desventaja"
            case .normal: "Normal"
            case .advantage: "Ventaja"
            }
        }
    }

    func d20(modifier: Int, advantage: Advantage) -> (natural: Int, faces: [Int], total: Int) {
        let faces = advantage == .normal ? [roll(20)] : [roll(20), roll(20)]
        let natural = advantage == .disadvantage ? faces.min()! : faces.max()!
        return (natural, faces, natural + modifier)
    }
}
