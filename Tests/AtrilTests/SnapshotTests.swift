import CoreGraphics
import CoreText
import Foundation
import PDFKit
import Testing
@testable import Atril

/// Instantánea de lo que producen el analizador, el buscador y el lector de PDF, para comprobar
/// que una optimización no cambia ningún resultado: se genera con la versión anterior y con la
/// nueva y se comparan los archivos. Solo corre con `TEST_RUNNER_ATRIL_SNAPSHOT=nombre.json` (se
/// escribe en la carpeta temporal de la app, que está en sandbox).
@Suite(.enabled(if: ProcessInfo.processInfo.environment["ATRIL_SNAPSHOT"] != nil))
struct SnapshotTests {
    static func campaign(copies: Int) -> String {
        let body = SampleAdventure.script.components(separatedBy: "\n").dropFirst().joined(separator: "\n")
        var parts = ["# Campaña de prueba"]
        for copy in 1...copies {
            parts.append("# Parte \(copy)")
            parts.append(body
                .replacingOccurrences(of: "## ", with: "## \(copy)·")
                .replacingOccurrences(of: "Marina", with: "Marina\(copy)"))
        }
        return parts.joined(separator: "\n\n")
    }

    static let dnd = """
    # La cripta del rey goblin

    Aventura para personajes de nivel 2. El señor Aldric, alcalde de Brumavalle, pide ayuda: los goblins roban el grano.

    ## 1. El camino del bosque

    Cuando los aventureros entren en el bosque, leedles lo siguiente:

    Los árboles se cierran sobre el camino y el aire huele a humo. Entre las ramas cuelgan huesos atados con cuerda.

    Una prueba de Percepción CD 13 revela huellas pequeñas. Con Supervivencia CD 12 siguen el rastro hasta la cripta. Los goblins atacan si hacen ruido.

    Goblin
    Clase de Armadura 15, Puntos de golpe 7 (2d6), DES 14 (+2)

    ## 2. La cripta

    > Una escalera de piedra baja hacia la oscuridad. Al fondo, un trono de huesos y una corona oxidada.

    El rey goblin, Grak el Tuerto, dice que solo quería comida. Con Perspicacia CD 14 notan que miente. Pista clave: el mapa del alcalde muestra que él vendió el grano a los goblins.

    Rey goblin: CA 17, PG 21, DES 12. Una tirada de salvación de Sabiduría CD 13 evita el miedo.

    ## Desenlaces

    - Victoria: el alcalde confiesa y el pueblo recupera el grano.
    - Derrota: los goblins se quedan con Brumavalle.
    """

    static let unicode = """
    ## Æsir y Þórr en la «Taberna» — ¡Señor Øster!

    El Sr. Müller, el capitán Ñúñez y la Dra. Ålund dicen: «¿Qué pasó?» Tirada de Psicología (Difícil) y 1/1D6 de Cordura.
    Straße ½ ² ³ µ ª º ´ ¨ e\u{301} — fin… 0/1D4 COR. Ŀlibre l·l ﬁn 😀 €20 °C ×2 ÷3
    """

    @Test func writeSnapshot() throws {
        let path = try #require(ProcessInfo.processInfo.environment["ATRIL_SNAPSHOT"])
        var snapshot: [String: String] = [:]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        func json<T: Encodable>(_ value: T) -> String { String(decoding: try! encoder.encode(value), as: UTF8.self) }

        let module = Self.moduleScript()
        let scripts: [(String, String, GameSystem)] = [
            ("muestra", SampleAdventure.script, .cthulhu),
            ("campaña", Self.campaign(copies: 6), .cthulhu),
            ("modulo", module, .cthulhu),
            ("dnd", Self.dnd, .dnd),
            ("otro", Self.dnd + "\n\n" + SampleAdventure.script, .other),
            ("unicode", Self.unicode, .cthulhu),
        ]
        for (name, script, system) in scripts {
            snapshot["guia.\(name)"] = json(HeuristicAnalyzer.analyze(script: script, system: system))
            snapshot["enemigos.\(name)"] = StatBlock.candidates(in: script)
                .map { "\($0.name)|\($0.stats.hp ?? -1)|\($0.stats.dexterity ?? -1)|\($0.stats.armorClass ?? -1)|\($0.stats.initiativeBonus ?? -99)" }
                .joined(separator: "\n")
            let index = ScriptIndex(script: script)
            let guide = HeuristicAnalyzer.analyze(script: script, system: system)
            for query in ["faro", "Marina signo", "¿Qué hago ahora?", "cueva piezas engranaje", "goblin rey", "tirada Psicología"] {
                snapshot["indice.\(name).\(query)"] = index.search(query, limit: 6).map { "\($0.id)" }.joined(separator: ",")
                let results = GuideSearch.search(query, guide: guide, index: index)
                snapshot["busqueda.\(name).\(query)"] = [
                    results.scenes.map(\.id).joined(separator: ","), results.npcs.map(\.id).joined(separator: ","),
                    results.clues.map(\.id).joined(separator: ","), results.passages.map { "\($0.id)" }.joined(separator: ","),
                ].joined(separator: " | ")
            }
            let lines = script.components(separatedBy: "\n")
            snapshot["pliegue.\(name)"] = lines.map(Prose.fold).joined(separator: "\n")
            snapshot["palabras.\(name)"] = lines.map { Prose.words($0).joined(separator: "/") }.joined(separator: "\n")
            snapshot["secciones.\(name)"] = ScriptChunker.sections(script).map { "\($0.heading)|\($0.part)|\($0.isTitle)|\($0.wordCount)" }.joined(separator: "\n")
        }
        snapshot["pliegue.raros"] = (0x20...0x2FF).compactMap(UnicodeScalar.init).map { Prose.fold("a\($0)b \($0)") }.joined(separator: "\n")

        // La app está en sandbox: se escribe en su carpeta temporal y se indica dónde.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(URL(fileURLWithPath: path).lastPathComponent)
        try json(snapshot).write(to: url, atomically: true, encoding: .utf8)
        print("SNAPSHOT-PATH \(url.path)")
    }

    /// Texto de un módulo maquetado leído con `PDFStructure`.
    static func moduleScript() -> String {
        func font(_ name: String, _ size: CGFloat) -> CTFont { CTFontCreateWithName(name as CFString, size, nil) }
        let body = font("Times New Roman", 10.5), italic = font("Times New Roman Italic", 10.5)
        let title = font("Helvetica Bold", 24), scene = font("Helvetica Bold", 15)
        let text = NSMutableAttributedString()
        func add(_ value: String, _ font: CTFont) {
            text.append(NSAttributedString(string: value + "\n", attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
            ]))
        }
        add("El Sanatorio de Valdeluz", title)
        for name in ["La llegada", "El pabellón", "El despacho", "El claustro"] {
            add(name, scene)
            add("Cuando los investigadores lleguen, léeles lo siguiente:", body)
            add("La niebla se traga el camino y solo el tañido de una campana os guía hasta los muros de piedra. Una figura con cofia os observa.", italic)
            add("La enfermera Sagrario Lema recibe a los investigadores con nerviosismo. Si superan una tirada de Psicología notan que oculta algo. El doctor Aurelio Montenegro, director del sanatorio, dice que todo va bien. Verlo cuesta 1/1D4 de Cordura.", body)
        }
        add("Estadísticas", scene)
        add("Doctor Aurelio Montenegro: FUE 45, CON 50, TAM 60, DES 55, POD 80, PV 11.", body)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("snapshot-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        var box = CGRect(x: 0, y: 0, width: 300, height: 420)
        let pdf = CGContext(url as CFURL, mediaBox: &box, nil)!
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        var position = 0
        while position < text.length {
            pdf.beginPDFPage(nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: position, length: 0),
                                                 CGPath(rect: CGRect(x: 30, y: 40, width: 240, height: 340), transform: nil), nil)
            CTFrameDraw(frame, pdf)
            position += CTFrameGetVisibleStringRange(frame).length
            pdf.endPDFPage()
        }
        pdf.closePDF()
        return PDFStructure.text(of: PDFDocument(url: url)!)
    }
}
