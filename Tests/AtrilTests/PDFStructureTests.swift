import CoreText
import Foundation
import PDFKit
import Testing
@testable import Atril

/// PDF con aspecto de módulo publicado: cabecera y número en cada página, títulos solo por
/// tamaño de letra, cuerpo con líneas cortadas y texto para leer en cursiva.
private func moduleText() -> NSAttributedString {
    func font(_ name: String, _ size: CGFloat) -> CTFont { CTFontCreateWithName(name as CFString, size, nil) }
    let body = font("Times New Roman", 10.5), italic = font("Times New Roman Italic", 10.5)
    let title = font("Helvetica Bold", 24), scene = font("Helvetica Bold", 15), sub = font("Helvetica Bold", 11.5)
    let text = NSMutableAttributedString()
    func add(_ value: String, _ font: CTFont) {
        text.append(NSAttributedString(string: value + "\n", attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
        ]))
    }
    add("El Sanatorio de Valdeluz", title)
    add("Una aventura para La llamada de Cthulhu. Galicia, invierno de 1926.", body)
    add("Trasfondo", scene)
    add("El doctor Aurelio Montenegro dirige el sanatorio de Valdeluz desde hace una década. Hace seis meses encontró en el pozo del claustro una tablilla que le susurra en sueños, y desde entonces experimenta con sus pacientes. La enfermera Sagrario Lema sospecha, pero teme por su vida.", body)
    for (name, read, detail) in [
        ("La llegada al sanatorio", "La niebla se traga el camino y solo el tañido de una campana os guía hasta los muros de piedra. Una figura con cofia os observa desde una ventana alta y desaparece.", "La enfermera Sagrario Lema recibe a los investigadores con nerviosismo. Si superan una tirada de Psicología notan que oculta algo y que mira constantemente hacia el pabellón."),
        ("El pabellón de los durmientes", "Decenas de camas de hierro se alinean bajo una luz mortecina. Los pacientes duermen con los ojos abiertos y sus labios se mueven a la vez, formando palabras.", "Una tirada de Medicina revela que no están enfermos, sino sedados con una sustancia desconocida. Verlos hablar a la vez cuesta 1/1D4 de Cordura."),
        ("El despacho del doctor", "Libros apilados, frascos con etiquetas borradas y un olor dulzón que se pega a la garganta. Sobre la mesa, un cuaderno abierto muestra dibujos de una puerta.", "Con una tirada de Cerrajería pueden abrir el cajón. Pista clave: el diario del doctor revela que la puerta se abrirá la noche de luna nueva."),
        ("El claustro y el pozo", "La lluvia repica en las losas del claustro. En el centro, el brocal del pozo está cubierto de musgo negro y de su interior sube un murmullo que pronuncia vuestros nombres.", "Descender al pozo requiere una tirada de Trepar. En el fondo hay un hueco con la tablilla, que al tocarla cuesta 1/1D6 de Cordura."),
    ] {
        add(name, scene)
        add("Cuando los investigadores lleguen, léeles lo siguiente:", body)
        add(read, italic)
        add(detail, body)
        add("Notas para el guardián", sub)
        add("Mantén la tensión con detalles pequeños: una puerta entornada, un susurro, una luz que se apaga. No reveles todo de golpe y deja que los jugadores saquen sus propias conclusiones.", body)
    }
    add("Desenlaces", scene)
    add("Si la puerta se cierra, el sanatorio queda en ruinas y los durmientes recuperan la memoria. Recompensa: +1D10 de Cordura. Si la puerta se abre, los investigadores huyen mientras la montaña se derrumba.", body)
    add("Estadísticas", scene)
    add("Doctor Aurelio Montenegro: FUE 45, CON 50, TAM 60, DES 55, POD 80, PV 11. Bisturí 40 % (1D4).", body)
    add("Sirviente de la Montaña: FUE 90, CON 80, TAM 90, DES 40, PV 17. Garras 50 % (1D8 + 1D6).", body)
    return text
}

private func writeModule() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("modulo-\(UUID().uuidString).pdf")
    let text = moduleText()
    var box = CGRect(x: 0, y: 0, width: 300, height: 420)
    let pdf = CGContext(url as CFURL, mediaBox: &box, nil)!
    let framesetter = CTFramesetterCreateWithAttributedString(text)
    let furniture = CTFontCreateWithName("Helvetica" as CFString, 8, nil)
    var position = 0, page = 1
    while position < text.length {
        pdf.beginPDFPage(nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: position, length: 0),
                                             CGPath(rect: CGRect(x: 30, y: 40, width: 240, height: 340), transform: nil), nil)
        CTFrameDraw(frame, pdf)
        position += CTFrameGetVisibleStringRange(frame).length
        for (value, y) in [("El Sanatorio de Valdeluz", CGFloat(395)), ("\(page)", CGFloat(20))] {
            pdf.textPosition = CGPoint(x: 30, y: y)
            CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): furniture,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
            ])), pdf)
        }
        pdf.endPDFPage()
        page += 1
    }
    pdf.closePDF()
    return url
}

struct PDFStructureTests {
    private func imported() async throws -> String {
        let url = writeModule()
        defer { try? FileManager.default.removeItem(at: url) }
        return try await ScriptImporter.load(url)
    }

    @Test func recoversStructureFromLayout() async throws {
        let text = try await imported()
        #expect(text.hasPrefix("# El Sanatorio de Valdeluz"))
        #expect(text.contains("## La llegada al sanatorio"))
        #expect(text.contains("> La niebla se traga el camino"))
        // Las líneas partidas se recomponen en párrafos.
        #expect(text.contains("mira constantemente hacia el pabellón."))
        #expect(!text.contains("constantemente\nhacia"))
        // Ni cabeceras ni números de página: el título solo aparece una vez.
        #expect(text.components(separatedBy: "El Sanatorio de Valdeluz").count == 2)
        #expect(text.range(of: #"(?m)^\d+$"#, options: .regularExpression) == nil)
    }

    @Test func realLookingModuleBecomesAGuide() async throws {
        let guide = HeuristicAnalyzer.analyze(script: try await imported(), system: .cthulhu)
        #expect(guide.scenes.map(\.title) == ["La llegada al sanatorio", "El pabellón de los durmientes", "El despacho del doctor", "El claustro y el pozo"])
        let first = guide.scenes[0]
        #expect(first.readAloud.hasPrefix("La niebla se traga"))
        #expect(first.readAloud.hasSuffix("desaparece."))
        #expect(first.checks.contains { $0.skill == "Psicología" })
        #expect(guide.scenes[1].checks.contains { $0.skill == "Cordura" && $0.difficulty == "1/1D4" })
        #expect(guide.scenes[2].checks.contains { $0.skill == "Cerrajería" })
        #expect(guide.truth.hasPrefix("El doctor Aurelio Montenegro"))
        #expect(guide.endings.count == 2)
        #expect(guide.endings[0].title == "Si la puerta se cierra")
        #expect(guide.endings[0].outcome.contains("Recompensa"))
        // «Galicia» sale una vez y no es un personaje.
        #expect(!guide.npcs.contains { $0.name == "Galicia" })
        #expect(guide.npcs.contains { $0.name.contains("Montenegro") })
    }

    @Test func subsectionsDoNotSplitScenes() {
        let lines = [
            PDFStructure.Line(text: "Primera escena", size: 16, page: 0),
            PDFStructure.Line(text: "Texto de la primera escena que sigue en esta línea y acaba aquí.", size: 10, page: 0),
            PDFStructure.Line(text: "Apartado interno", size: 12, page: 0),
            PDFStructure.Line(text: "Más texto de la misma escena que continúa sin cambiar de sitio.", size: 10, page: 0),
            PDFStructure.Line(text: "Segunda escena", size: 16, page: 0),
            PDFStructure.Line(text: "Texto de la segunda.", size: 10, page: 0),
        ]
        let text = PDFStructure.markdown(lines, pageCount: 1)
        #expect(text.contains("## Primera escena"))
        #expect(text.contains("## Segunda escena"))
        #expect(text.contains("Apartado interno:"))
        #expect(!text.contains("## Apartado interno"))
    }

    @Test func partsSitAboveScenes() {
        var lines: [PDFStructure.Line] = [PDFStructure.Line(text: "Parte primera", size: 22, page: 0)]
        for index in 1...4 {
            lines.append(PDFStructure.Line(text: "Escena \(["uno", "dos", "tres", "cuatro"][index - 1])", size: 14, page: 0))
            lines.append(PDFStructure.Line(text: "Un párrafo largo de texto normal para que este tamaño sea el del cuerpo del documento.", size: 10, page: 0))
        }
        lines.append(PDFStructure.Line(text: "Parte segunda", size: 22, page: 1))
        lines.append(PDFStructure.Line(text: "Escena cinco", size: 14, page: 1))
        lines.append(PDFStructure.Line(text: "Otro párrafo largo de texto normal para que este tamaño sea el del cuerpo del documento.", size: 10, page: 1))
        let text = PDFStructure.markdown(lines, pageCount: 2)
        #expect(text.contains("# Parte segunda"))
        #expect(text.contains("## Escena cinco"))
    }

    @Test func standaloneLinesActAsHeadingsInPlainText() {
        let script = "La casa del farero\n\nLos investigadores llegan al faro y encuentran la puerta abierta de par en par.\n\nEl sótano inundado\n\nEl agua llega por las rodillas y algo se mueve bajo la superficie oscura.\n\nLa torre\n\nArriba está la lente rota."
        let sections = ScriptChunker.sections(script)
        #expect(sections.map(\.heading) == ["La casa del farero", "El sótano inundado", "La torre"])
    }

    @Test func recognizesReadAloudCues() {
        #expect(HeuristicAnalyzer.isReadAloudCue("Cuando lleguen, léeles lo siguiente:"))
        #expect(HeuristicAnalyzer.isReadAloudCue("Lee o parafrasea el siguiente texto:"))
        #expect(!HeuristicAnalyzer.isReadAloudCue("El libro que se lee en la biblioteca es antiguo."))
    }
}
