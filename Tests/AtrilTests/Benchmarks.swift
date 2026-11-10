import CoreGraphics
import CoreText
import Foundation
import ImageIO
import NaturalLanguage
import PDFKit
import SwiftData
import Testing
import UniformTypeIdentifiers
@testable import Atril

/// Banco de medidas con una campaña grande. No corre en la batería normal:
/// `TEST_RUNNER_ATRIL_BENCH=1 xcodebuild test … -only-testing:AtrilTests/Benchmarks`.
/// Imprime una línea «BENCH nombre: mediana ms» por medida.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["ATRIL_BENCH"] != nil))
struct Benchmarks {
    // MARK: Datos de prueba

    /// La aventura de ejemplo repetida `copies` veces como partes de una campaña, con escenas
    /// de títulos distintos (1.110 palabras por copia).
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

    /// La guía de ejemplo repetida: escenas, PNJ y pistas con identificadores propios.
    static func bigGuide(copies: Int) -> AdventureGuide {
        let base = SampleAdventure.guide
        var guide = base
        guide.scenes = []
        guide.npcs = []
        guide.clues = []
        for copy in 1...copies {
            func id(_ value: String) -> String { "\(value)-\(copy)" }
            guide.scenes += base.scenes.map { scene in
                var scene = scene
                scene.id = id(scene.id)
                scene.title += " \(copy)"
                scene.clueIDs = scene.clueIDs.map(id)
                scene.npcIDs = scene.npcIDs.map(id)
                scene.exits = scene.exits.map { .init(sceneID: id($0.sceneID), condition: $0.condition) }
                return scene
            }
            guide.npcs += base.npcs.map { npc in
                var npc = npc
                npc.id = id(npc.id)
                npc.name += " \(copy)"
                return npc
            }
            guide.clues += base.clues.map { clue in
                var clue = clue
                clue.id = id(clue.id)
                clue.sceneID = id(clue.sceneID)
                return clue
            }
        }
        return guide
    }

    static func table(guide: AdventureGuide, index: ScriptIndex) -> TableSnapshot {
        let state = TutorPrompts.TableState(
            system: .cthulhu, guide: guide, playTime: 3600, currentSceneID: guide.scenes[guide.scenes.count / 2].id,
            visitedSceneIDs: guide.scenes.prefix(guide.scenes.count / 2).map(\.id), foundClueIDs: Set(guide.clues.prefix(10).map(\.id)),
            players: (1...4).map { Player(name: "Jugador \($0)", character: "Investigador \($0)") },
            notes: (1...40).map { SessionNote(playTime: Double($0) * 60, sceneID: nil, text: "Nota número \($0) sobre lo que han hecho en el faro.") }
        )
        return TableSnapshot(title: "Campaña", system: .cthulhu, guide: guide, state: state, index: index, recent: [])
    }

    static let questions = [
        "¿Qué hago ahora?", "Están atascados en el faro", "¿Qué sabe Marina del signo?", "Se han ido a la iglesia",
        "Describe la cueva", "¿Qué tirada pido para el engranaje?", "regla de cordura", "¿Dónde están las piezas?",
    ]

    // MARK: Medición

    @discardableResult
    static func time(_ name: String, runs: Int = 5, _ work: () throws -> Void) rethrows -> Double {
        var samples: [Double] = []
        for _ in 0..<runs {
            let start = ContinuousClock.now
            try work()
            samples.append(milliseconds(ContinuousClock.now - start))
        }
        return report(name, samples)
    }

    @discardableResult
    static func time(_ name: String, runs: Int = 3, _ work: () async throws -> Void) async rethrows -> Double {
        var samples: [Double] = []
        for _ in 0..<runs {
            let start = ContinuousClock.now
            try await work()
            samples.append(milliseconds(ContinuousClock.now - start))
        }
        return report(name, samples)
    }

    static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }

    static func report(_ name: String, _ samples: [Double]) -> Double {
        let median = samples.sorted()[samples.count / 2]
        print("BENCH \(name): \(String(format: "%.3f", median)) ms")
        return median
    }

    // MARK: Guion y guía

    @Test func scriptProcessing() {
        let medium = Self.campaign(copies: 10)
        let large = Self.campaign(copies: 40)
        let huge = Self.campaign(copies: 120)
        print("BENCH-INFO palabras: \(medium.split(whereSeparator: \.isWhitespace).count) / \(large.split(whereSeparator: \.isWhitespace).count) / \(huge.split(whereSeparator: \.isWhitespace).count)")

        Self.time("heuristica 11k palabras", runs: 3) { _ = HeuristicAnalyzer.analyze(script: medium, system: .cthulhu) }
        Self.time("heuristica 44k palabras", runs: 1) { _ = HeuristicAnalyzer.analyze(script: large, system: .cthulhu) }
        Self.time("indice 44k palabras") { _ = ScriptIndex(script: large) }
        Self.time("indice 133k palabras", runs: 3) { _ = ScriptIndex(script: huge) }
        let index = ScriptIndex(script: huge)
        Self.time("busqueda indice 133k ×8", runs: 5) { for question in Self.questions { _ = index.search(question, limit: 6) } }
        Self.time("enemigos del guion 44k") { _ = StatBlock.candidates(in: large) }
        Self.time("secciones 44k") { _ = ScriptChunker.sections(large) }
        Self.time("trozos IA 44k") { _ = ScriptChunker.chunks(large, maxWords: 650) }

        let adventure = Adventure(title: "Campaña", system: .cthulhu, script: huge)
        Self.time("contar palabras 133k") { _ = adventure.wordCount }
        Self.time("huella del guion 133k") { _ = Adventure.hash(huge) }
        Self.time("¿guía desfasada? 133k") { _ = adventure.isGuideStale }
        Self.time("parrafos del guion 133k") { _ = huge.components(separatedBy: "\n\n") }
    }

    @Test func heuristicBreakdown() {
        let large = Self.campaign(copies: 40)
        let sections = ScriptChunker.sections(large)
        Self.time("h: personajes 44k", runs: 1) { _ = HeuristicAnalyzer.characters(in: large, appendix: "") }
        Self.time("h: escenas 44k", runs: 1) { for section in sections { _ = HeuristicAnalyzer.scene(from: section, system: .cthulhu) } }
        let drafts = HeuristicAnalyzer.drafts(script: large, system: .cthulhu)
        Self.time("h: unir borradores 44k", runs: 1) { _ = GuideMerger.merge(chunks: drafts.allChunks, overview: drafts.overview, system: .cthulhu) }
        let plain = HeuristicAnalyzer.plain(large)
        Self.time("h: texto plano 44k", runs: 1) { _ = HeuristicAnalyzer.plain(large) }
        Self.time("h: frases 44k", runs: 1) { _ = Prose.sentences(plain) }
        Self.time("h: NLTagger 44k", runs: 1) {
            let tagger = NLTagger(tagSchemes: [.nameType])
            tagger.string = plain
            tagger.setLanguage(.spanish, range: plain.startIndex..<plain.endIndex)
            var count = 0
            tagger.enumerateTags(in: plain.startIndex..<plain.endIndex, unit: .word, scheme: .nameType,
                                 options: [.omitWhitespace, .omitPunctuation, .joinNames]) { _, _ in count += 1; return true }
        }
        let sentences = Prose.sentences(plain)
        Self.time("fold de \(sentences.count) frases", runs: 3) { for sentence in sentences { _ = Prose.fold(sentence) } }
        Self.time("excludedNames ×100", runs: 3) { for _ in 0..<100 { _ = HeuristicAnalyzer.excludedNames } }
        Self.time("estado de la IA de Apple ×100", runs: 3) { for _ in 0..<100 { _ = AppleAI.status } }
        Self.time("motor actual ×100", runs: 3) { for _ in 0..<100 { _ = AIBackend.current } }
    }

    @Test func sceneBreakdown() {
        let large = Self.campaign(copies: 40)
        let sections = ScriptChunker.sections(large)
        let bodies = sections.map(\.body)
        let plains = bodies.map(HeuristicAnalyzer.plain)
        print("BENCH-INFO secciones: \(sections.count)")
        Self.time("e: texto plano", runs: 3) { for body in bodies { _ = HeuristicAnalyzer.plain(body) } }
        Self.time("e: frases", runs: 3) { for plain in plains { _ = Prose.sentences(plain) } }
        let sentences = plains.map { HeuristicAnalyzer.Sentences(Prose.sentences($0)) }
        Self.time("e: frases plegadas", runs: 3) { for plain in plains { _ = HeuristicAnalyzer.Sentences(Prose.sentences(plain)) } }
        Self.time("e: tiradas", runs: 3) { for item in sentences { _ = HeuristicAnalyzer.checks(in: item, system: .cthulhu) } }
        Self.time("e: pistas", runs: 3) { for item in sentences { _ = HeuristicAnalyzer.clues(in: item) } }
        Self.time("e: peligros", runs: 3) { for item in sentences { _ = HeuristicAnalyzer.danger(in: item) } }
        Self.time("e: lugar", runs: 3) { for plain in plains { _ = HeuristicAnalyzer.place(in: plain) } }
        Self.time("e: títulos", runs: 3) { for section in sections { _ = HeuristicAnalyzer.cleanTitle(section.heading) } }
        Self.time("e: avisos de lectura", runs: 3) {
            for body in bodies { for line in body.components(separatedBy: "\n") { _ = HeuristicAnalyzer.isReadAloudCue(line.trimmed) } }
        }
        Self.time("e: escenas completas", runs: 3) { for section in sections { _ = HeuristicAnalyzer.scene(from: section, system: .cthulhu) } }

        let guide = Self.bigGuide(copies: 8)
        let catalog = GuideSearch.Catalog(guide: guide)
        let index = ScriptIndex(script: large)
        Self.time("catálogo de búsqueda", runs: 5) { _ = GuideSearch.Catalog(guide: guide) }
        Self.time("búsqueda con catálogo ×8", runs: 5) { for question in Self.questions { _ = catalog.search(question, index: index) } }
    }

    @Test func pdfBreakdown() throws {
        let url = Self.writeModule(copies: 16)
        defer { try? FileManager.default.removeItem(at: url) }
        Self.time("p: abrir el documento", runs: 3) { _ = PDFDocument(url: url) }
        Self.time("p: líneas con fuente (documento nuevo)", runs: 3) { _ = PDFStructure.lines(of: PDFDocument(url: url)!) }
        Self.time("p: capa de texto (documento nuevo)", runs: 3) {
            let document = PDFDocument(url: url)!
            _ = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }
        }
        let document = try #require(PDFDocument(url: url))
        let lines = PDFStructure.lines(of: document)
        Self.time("p: marcas", runs: 3) { _ = PDFStructure.markdown(lines, pageCount: document.pageCount) }
        let text = PDFStructure.markdown(lines, pageCount: document.pageCount)
        Self.time("p: limpiar", runs: 3) { _ = ScriptImporter.clean(text) }
    }

    @Test func alternatives() throws {
        let large = Self.campaign(copies: 40)
        let plains = ScriptChunker.sections(large).map { HeuristicAnalyzer.plain($0.body) }
        // Frases: la de siempre frente a un tokenizador reutilizado.
        Self.time("alt: frases enumerateSubstrings", runs: 3) { for plain in plains { _ = Prose.sentences(plain) } }
        let tokenizer = CFStringTokenizerCreate(nil, "" as CFString, CFRange(location: 0, length: 0), kCFStringTokenizerUnitSentence, CFLocaleCopyCurrent())!
        func cfSentences(_ text: String) -> [String] {
            let ns = text as NSString
            CFStringTokenizerSetString(tokenizer, ns, CFRange(location: 0, length: ns.length))
            var result: [String] = []
            while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
                let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
                let sentence = ns.substring(with: NSRange(location: range.location, length: range.length)).trimmed
                if !sentence.isEmpty { result.append(sentence) }
            }
            return result
        }
        Self.time("alt: frases CFStringTokenizer", runs: 3) { for plain in plains { _ = cfSentences(plain) } }
        var differences = 0
        for plain in plains where cfSentences(plain) != Prose.sentences(plain) { differences += 1 }
        print("BENCH-INFO frases distintas: \(differences) de \(plains.count)")

        // Buscar texto: contains de Foundation frente a memmem.
        let folded = plains.map(Prose.fold)
        let keys = ["tirada", "prueba", "salvacion", "dificil", "extrem", "pista", "encuentran", "revela", "cordura", "zzz"]
        Self.time("alt: contains", runs: 3) { for text in folded { for key in keys { _ = text.contains(key) } } }
        Self.time("alt: memmem", runs: 3) { for text in folded { for key in keys { _ = text.containsBytes(key) } } }
        var mismatches = 0
        for text in folded { for key in keys where text.contains(key) != text.containsBytes(key) { mismatches += 1 } }
        print("BENCH-INFO contains distintos: \(mismatches)")

        // PDF: cuánto es crear el texto con atributos y cuánto lo nuestro.
        let url = Self.writeModule(copies: 16)
        defer { try? FileManager.default.removeItem(at: url) }
        Self.time("alt: attributedString (documento nuevo)", runs: 3) {
            let document = PDFDocument(url: url)!
            _ = (0..<document.pageCount).compactMap { document.page(at: $0)?.attributedString }
        }
        let pages = PDFDocument(url: url)!.pageCount
        for workers in [2, 4, 8] {
            Self.time("alt: attributedString en \(workers) hilos", runs: 3) {
                DispatchQueue.concurrentPerform(iterations: workers) { worker in
                    let document = PDFDocument(url: url)!
                    for index in stride(from: worker, to: pages, by: workers) { _ = document.page(at: index)?.attributedString }
                }
            }
        }
        let big = Self.writeModule(copies: 100)
        defer { try? FileManager.default.removeItem(at: big) }
        print("BENCH-INFO PDF grande: \(PDFDocument(url: big)!.pageCount) páginas")
        Self.time("alt: PDF grande, líneas", runs: 1) { _ = PDFStructure.lines(of: PDFDocument(url: big)!) }
        Self.time("alt: PDF grande, attributedString en 4 hilos", runs: 1) {
            let count = PDFDocument(url: big)!.pageCount
            DispatchQueue.concurrentPerform(iterations: 4) { worker in
                let document = PDFDocument(url: big)!
                for index in stride(from: worker, to: count, by: 4) { _ = document.page(at: index)?.attributedString }
            }
        }
    }

    @Test func guideAccess() throws {
        let guide = Self.bigGuide(copies: 8)
        let data = try JSONEncoder().encode(guide)
        print("BENCH-INFO guía: \(guide.scenes.count) escenas, \(guide.npcs.count) PNJ, \(guide.clues.count) pistas, \(data.count / 1024) KB")
        let adventure = Adventure(title: "Campaña", system: .cthulhu, script: Self.campaign(copies: 8))
        adventure.guide = guide

        Self.time("leer adventure.guide ×1", runs: 9) { _ = adventure.guide }
        // Lo que lee la ficha de una aventura en cada repintado (cabecera, estado, contenido…).
        Self.time("leer adventure.guide ×8", runs: 9) { for _ in 0..<8 { _ = adventure.guide } }
        Self.time("guardar adventure.guide", runs: 9) { adventure.guide = guide }

        let index = ScriptIndex(script: adventure.script)
        let table = Self.table(guide: guide, index: index)
        Self.time("prompt del tutor ×8") {
            for question in Self.questions { _ = TutorContext.prompt(question: question, table: table, passages: 4, generous: false) }
        }
        Self.time("tutor básico ×8") { for question in Self.questions { _ = BasicTutor.answer(question, table: table, seed: 1) } }
        Self.time("búsqueda en la guía ×8") {
            for question in Self.questions { _ = GuideSearch.search(question, guide: guide, index: index) }
        }
        Self.time("plan de sesiones") { _ = SessionPlanner.plan(guide, hours: 3) }
        Self.time("mapa") { _ = MapLayout(guide) }
    }

    @Test @MainActor func archiveRoundTrip() throws {
        let container = try ModelContainer(for: Adventure.self, PlaySession.self, Portrait.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let adventure = Adventure(title: "Campaña", system: .cthulhu, script: Self.campaign(copies: 40))
        container.mainContext.insert(adventure)
        adventure.guide = Self.bigGuide(copies: 8)
        for number in 1...5 {
            let session = PlaySession(number: number, adventure: adventure)
            container.mainContext.insert(session)
            session.chat = (1...60).map { TutorMessage(role: $0.isMultiple(of: 2) ? .assistant : .user, display: "Mensaje \($0) con algo de texto de relleno para que pese como una respuesta real del tutor.", content: .string("x")) }
            session.notes = (1...80).map { SessionNote(playTime: Double($0) * 30, sceneID: nil, text: "Nota \($0)") }
        }
        var encoded = Data()
        try Self.time("exportar .atril") { encoded = try AdventureArchive(adventure).encoded() }
        print("BENCH-INFO .atril: \(encoded.count / 1024) KB")
        try Self.time("leer .atril") { _ = try AdventureArchive.decode(encoded) }
        let session = adventure.sessions[0]
        Self.time("leer chat de una sesión (60)") { _ = session.chat }
        Self.time("abrir la mesa (PlayController)", runs: 3) { _ = PlayController(session: session) }
    }

    @Test @MainActor func prepSheet() throws {
        let guide = Self.bigGuide(copies: 8)
        let content = PrepSheet.Content(
            title: "Campaña", subtitle: "Aventura completa", system: .cthulhu, guide: guide,
            sceneIDs: guide.scenes.map(\.id), recap: "La última vez…", includeOpening: true, portraits: [:]
        )
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bench-hoja-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try Self.time("hoja de preparación, 48 escenas", runs: 3) { try PrepSheet.render(content, to: url) }
        print("BENCH-INFO hoja: \(PDFDocument(url: url)?.pageCount ?? 0) páginas")
    }

    // MARK: Retratos

    @Test func portraitDecoding() throws {
        // Un retrato como los que guarda la app: JPEG de 768 px.
        let size = 1024
        let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        for step in 0..<64 {
            context.setFillColor(CGColor(red: Double(step % 8) / 8, green: Double(step / 8) / 8, blue: 0.5, alpha: 1))
            context.fill(CGRect(x: (step % 8) * 128, y: (step / 8) * 128, width: 128, height: 128))
        }
        let png = NSMutableData()
        let destination = CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        let portrait = try #require(PortraitImage.prepared(png as Data))
        print("BENCH-INFO retrato: \(portrait.count / 1024) KB")

        func drawn(_ image: CGImage, side: Int) {
            let target = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                   space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            target.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        Self.time("decodificar retrato completo ×30", runs: 3) {
            for _ in 0..<30 {
                let source = CGImageSourceCreateWithData(portrait as CFData, nil)!
                drawn(CGImageSourceCreateImageAtIndex(source, 0, nil)!, side: 90)
            }
        }
        Self.time("miniatura de retrato 90 px ×30", runs: 3) {
            for _ in 0..<30 {
                let source = CGImageSourceCreateWithData(portrait as CFData, nil)!
                let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 90]
                drawn(CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)!, side: 90)
            }
        }
    }

    // MARK: Audio

    @Test func ambienceCPU() {
        let seconds = 10
        for kind in Ambience.allCases {
            let synth = AmbienceSynth(kind: kind, sampleRate: 48_000)
            synth.targetGain = 1
            var left = [Float](repeating: 0, count: 512)
            var right = [Float](repeating: 0, count: 512)
            let blocks = 48_000 * seconds / 512
            let total = Self.time("ambiente \(kind.rawValue) \(seconds) s", runs: 3) {
                left.withUnsafeMutableBufferPointer { l in
                    right.withUnsafeMutableBufferPointer { r in
                        for _ in 0..<blocks { synth.render(left: l.baseAddress!, right: r.baseAddress!, frames: 512) }
                    }
                }
            }
            print("BENCH-INFO ambiente \(kind.rawValue): \(String(format: "%.2f", total / Double(seconds) / 10)) % de un núcleo")
        }
    }

    // MARK: Importación

    @Test func pdfImport() async throws {
        let url = Self.writeModule(copies: 16)
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try #require(PDFDocument(url: url))
        print("BENCH-INFO PDF: \(document.pageCount) páginas")
        Self.time("capa de texto del PDF", runs: 3) {
            _ = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n\n")
        }
        Self.time("estructura del PDF", runs: 3) { _ = PDFStructure.text(of: document) }
        try await Self.time("importar PDF completo", runs: 3) { _ = try await ScriptImporter.load(url) }
    }

    @Test func ocrImport() async throws {
        let url = try Self.scannedPDF(pages: 4)
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try #require(PDFDocument(url: url))
        try await Self.time("OCR 4 páginas", runs: 1) { _ = try await ScriptImporter.recognize(document) { _ in } }
    }

    /// PDF maquetado como un módulo publicado, con el contenido repetido `copies` veces.
    static func writeModule(copies: Int) -> URL {
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
        for copy in 1...copies {
            for name in ["La llegada", "El pabellón", "El despacho", "El claustro", "El pozo", "La huida"] {
                add("\(name) \(copy)", scene)
                add("Cuando los investigadores lleguen, léeles lo siguiente:", body)
                add("La niebla se traga el camino y solo el tañido de una campana os guía hasta los muros de piedra. Una figura con cofia os observa desde una ventana alta y desaparece.", italic)
                add("La enfermera Sagrario Lema recibe a los investigadores con nerviosismo. Si superan una tirada de Psicología notan que oculta algo y que mira constantemente hacia el pabellón. Con una tirada de Cerrajería pueden abrir el cajón del despacho, donde el diario del doctor revela que la puerta se abrirá la noche de luna nueva. Verlo cuesta 1/1D4 de Cordura.", body)
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bench-\(UUID().uuidString).pdf")
        var box = CGRect(x: 0, y: 0, width: 420, height: 595)
        let pdf = CGContext(url as CFURL, mediaBox: &box, nil)!
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        let furniture = CTFontCreateWithName("Helvetica" as CFString, 8, nil)
        var position = 0, page = 1
        while position < text.length {
            pdf.beginPDFPage(nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: position, length: 0),
                                                 CGPath(rect: CGRect(x: 36, y: 48, width: 348, height: 500), transform: nil), nil)
            CTFrameDraw(frame, pdf)
            position += CTFrameGetVisibleStringRange(frame).length
            for (value, y) in [("El Sanatorio de Valdeluz", CGFloat(570)), ("\(page)", CGFloat(24))] {
                pdf.textPosition = CGPoint(x: 36, y: y)
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

    /// PDF escaneado: páginas que solo son una imagen con texto.
    static func scannedPDF(pages: Int) throws -> URL {
        let width = 1240, height = 1754
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bench-ocr-\(UUID().uuidString).pdf")
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        let pdf = CGContext(url as CFURL, mediaBox: &box, nil)!
        let font = CTFontCreateWithName("Times New Roman" as CFString, 36, nil)
        for page in 1...pages {
            let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            for line in 0..<24 {
                let attributed = NSAttributedString(string: "Página \(page), línea \(line): la niebla se traga el camino del faro.", attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): font,
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 0, green: 0, blue: 0, alpha: 1),
                ])
                context.textPosition = CGPoint(x: 90, y: height - 160 - line * 62)
                CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
            }
            pdf.beginPDFPage(nil)
            pdf.draw(context.makeImage()!, in: box)
            pdf.endPDFPage()
        }
        pdf.closePDF()
        return url
    }
}
