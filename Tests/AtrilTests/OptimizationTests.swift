import CoreGraphics
import CoreText
import Foundation
import ImageIO
import PDFKit
import SwiftData
import Testing
import UniformTypeIdentifiers
@testable import Atril

/// Las versiones rápidas tienen que dar exactamente lo mismo que las de siempre.
struct FastPathTests {
    static let texts: [String] = [
        SampleAdventure.script,
        "¿Qué pasó? «Él» dijo: ¡Ñandú! Ünïcódé — Àlvaro y Çésar… 50 % de 1D6.",
        "  Espacios\u{00A0}duros\tytabs\n\nsaltos  ",
        "L'Hôpital, Café-Bar y 3ª edición; 2º piso; µ; ½; Straße; Æsir; Øster; Þórr.",
        "Combinadas: e\u{301} y n\u{303}; emoji 😀; símbolos €20, °C, ×2, ÷3, ±1, ©, ®.",
        "Sr. Rivas, Dra. Cueto y D. Ramiro: «¿Dónde está la lente?»",
        "", "   ", "ABC_def-ghi.jkl",
    ]

    @Test func latinFoldMatchesFoundation() {
        for text in Self.texts {
            for line in text.components(separatedBy: "\n") + [text] {
                #expect(Prose.fold(line) == Prose.foundationFold(line), "\(line)")
            }
        }
        // Todo carácter de Latin-1 y del principio de Unicode, solo y entre letras.
        for value in 0x20...0x2FF {
            guard let scalar = UnicodeScalar(value) else { continue }
            let text = "Ab\(Character(scalar))cD \(Character(scalar))"
            #expect(Prose.fold(text) == Prose.foundationFold(text), "U+\(String(value, radix: 16))")
        }
    }

    @Test func latinFoldCoversSpanishText() {
        // El guion de ejemplo entero va por la vía rápida.
        #expect(Prose.latinFold(SampleAdventure.script) != nil)
        #expect(Prose.latinFold("Ægir") == nil)
    }

    @Test func wordCountMatchesSplit() {
        for text in Self.texts + ["uno\u{2003}dos\u{3000}tres\u{200B}cuatro", "\r\nhola\r\nadiós\r\n"] {
            #expect(WordCounter.count(text) == text.split(whereSeparator: \.isWhitespace).count, "\(text)")
        }
    }

    @Test func piecesKeepTheWholeTextAndCutBetweenSentences() {
        let text = String(repeating: "El Sr. Rivas mira el faro. La Dra. Cueto llega tarde a la cita. ", count: 400)
        let pieces = HeuristicAnalyzer.sentencePieces(of: text, count: 5)
        #expect(pieces.count == 5)
        #expect(pieces.joined() == text)
        for piece in pieces.dropLast() {
            #expect(piece.hasSuffix(". "))
            #expect(!piece.hasSuffix("Sr. ") && !piece.hasSuffix("Dra. "))
        }
    }

    @Test func parallelNameTagsMatchASingleTagger() {
        let text = HeuristicAnalyzer.plain(SampleAdventure.script)
        let whole = HeuristicAnalyzer.nameTags(in: text, pieces: 1)
        let split = HeuristicAnalyzer.nameTags(in: text, pieces: 4)
        #expect(whole.personal == split.personal)
        #expect(whole.other == split.other)
    }
}

struct CacheTests {
    @Test func decodedGuidesFollowTheirData() throws {
        var guide = SampleAdventure.guide
        let data = try #require(guide.encoded())
        #expect(AdventureGuide.decode(data) == guide)
        guide.scenes[0].title = "Otra llegada"
        let changed = try JSONEncoder().encode(guide)
        #expect(AdventureGuide.decode(changed)?.scenes[0].title == "Otra llegada")
        #expect(AdventureGuide.decode(data)?.scenes[0].title == SampleAdventure.guide.scenes[0].title)
        #expect(AdventureGuide.decode(Data("no es json".utf8)) == nil)
    }

    @Test func scriptFactsFollowEdits() {
        let adventure = Adventure(title: "Prueba", system: .cthulhu, script: "Uno dos tres.\n\nCuatro.")
        adventure.guide = SampleAdventure.guide
        #expect(adventure.wordCount == 4)
        #expect(adventure.scriptParagraphs.count == 2)
        #expect(!adventure.isGuideStale)
        adventure.script += " Cinco seis."
        #expect(adventure.wordCount == 6)
        #expect(adventure.isGuideStale)
        #expect(adventure.scriptHash == Adventure.hash(adventure.script))
    }

    @Test func sharedIndexMatchesAFreshOne() {
        let cached = ScriptIndex.cached(for: SampleAdventure.script)
        let fresh = ScriptIndex(script: SampleAdventure.script)
        #expect(cached.search("faro lente", limit: 4) == fresh.search("faro lente", limit: 4))
        #expect(ScriptIndex.cached(for: SampleAdventure.script).passages == cached.passages)
    }

    @Test func liveAnswersCloseAnOpenBold() {
        #expect(MarkdownText.closingOpenBold("- **Mantén a Marina") == "- **Mantén a Marina**")
        #expect(MarkdownText.closingOpenBold("- **Hecho** y más") == "- **Hecho** y más")
        #expect(MarkdownText.closingOpenBold("**Ahora**\n- Sigue") == "**Ahora**\n- Sigue")
        #expect(String(MarkdownText.parse(MarkdownText.closingOpenBold("- **Mantén"))[0].text.characters) == "Mantén")
    }

    @Test func markdownIsParsedOnce() {
        let text = "**Ahora**\n- Que Marina *no* les deje subir.\n# Título"
        let blocks = MarkdownText.blocks(text)
        #expect(blocks.map(\.kind) == [.paragraph, .bullet, .heading])
        #expect(String(blocks[1].text.characters) == "Que Marina no les deje subir.")
        #expect(MarkdownText.blocks(text).map(\.text) == blocks.map(\.text))
    }

    @Test func portraitThumbnailsHaveTheRequestedSize() throws {
        let context = CGContext(data: nil, width: 800, height: 600, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 0.4, green: 0.2, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        let thumbnail = try #require(PortraitImage.thumbnail(data as Data, pixels: 120))
        #expect(max(thumbnail.width, thumbnail.height) == 120)
        #expect(PortraitImage.thumbnail(data as Data, pixels: 120) === thumbnail)
        #expect(PortraitImage.thumbnail(Data([1, 2, 3]), pixels: 120) == nil)
    }
}

struct BackgroundWorkTests {
    @Test @MainActor func basicGuideArrivesWithoutBlocking() async throws {
        let container = try ModelContainer(for: Adventure.self, PlaySession.self, Portrait.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let adventure = Adventure(title: "Punta Negra", system: .cthulhu, script: SampleAdventure.script)
        container.mainContext.insert(adventure)
        let center = AnalysisCenter()
        center.organizeBasic(adventure)
        #expect(center.isOrganizing(adventure))
        for _ in 0..<200 where center.isOrganizing(adventure) {
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(!center.isOrganizing(adventure))
        #expect(adventure.guide?.scenes.count == 6)
        #expect(adventure.guideEngine == "basic")
    }

    @Test @MainActor func audioEngineSleepsWhenSilent() async throws {
        let player = AmbiencePlayer.shared
        player.play(.rain)
        // Sin salida de audio (algunos entornos de prueba) no hay nada que comprobar.
        guard player.isEngineRunning else { return }
        player.stop(.rain)
        #expect(player.isEngineRunning, "Sigue sonando mientras dura el fundido")
        try await Task.sleep(for: .seconds(2.5))
        #expect(!player.isEngineRunning)
        player.play(.rain)
        #expect(player.isEngineRunning)
        player.stopAll()
    }

    @Test(.timeLimit(.minutes(1)))
    func scannedPagesKeepTheirOrder() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("orden-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        let pdf = try #require(CGContext(url as CFURL, mediaBox: &box, nil))
        let font = CTFontCreateWithName("Times New Roman" as CFString, 40, nil)
        for page in ["Primera", "Segunda", "Tercera", "Cuarta", "Quinta"] {
            let context = CGContext(data: nil, width: 1240, height: 1754, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 1240, height: 1754))
            for line in 0..<3 {
                let text = NSAttributedString(string: "\(page) página, línea \(line + 1) del faro.", attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): font,
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 0, green: 0, blue: 0, alpha: 1),
                ])
                context.textPosition = CGPoint(x: 100, y: 1500 - line * 90)
                CTLineDraw(CTLineCreateWithAttributedString(text), context)
            }
            pdf.beginPDFPage(nil)
            pdf.draw(context.makeImage()!, in: box)
            pdf.endPDFPage()
        }
        pdf.closePDF()

        let text = try await ScriptImporter.load(url)
        let positions = ["Primera", "Segunda", "Tercera", "Cuarta", "Quinta"].compactMap { text.range(of: $0)?.lowerBound }
        #expect(positions.count == 5)
        #expect(positions == positions.sorted())
    }
}
