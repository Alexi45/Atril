import CoreGraphics
import CoreText
import Foundation
import PDFKit
import Testing
@testable import Atril

struct ImporterTests {
    /// PDF de una página que solo contiene una imagen con texto, como un módulo escaneado.
    private func scannedPDF(lines: [String]) throws -> URL {
        let width = 1240, height = 1754
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font = CTFontCreateWithName("Times New Roman" as CFString, 44, nil)
        for (index, line) in lines.enumerated() {
            let attributed = NSAttributedString(string: line, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            ])
            context.textPosition = CGPoint(x: 100, y: height - 200 - index * 80)
            CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
        }
        let image = context.makeImage()!

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("escaneado-\(UUID().uuidString).pdf")
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        let pdf = CGContext(url as CFURL, mediaBox: &box, nil)!
        pdf.beginPDFPage(nil)
        pdf.draw(image, in: box)
        pdf.endPDFPage()
        pdf.closePDF()
        return url
    }

    @Test func readsScannedPDFWithOCR() async throws {
        let url = try scannedPDF(lines: [
            "La taberna de la Remedios",
            "Humo de pipa y redes colgadas de las vigas.",
            "Xuacu pide una tirada de Persuasion.",
        ])
        defer { try? FileManager.default.removeItem(at: url) }
        #expect((PDFDocument(url: url)?.string ?? "").isEmpty)

        var messages: [String] = []
        let text = try await ScriptImporter.load(url) { messages.append($0) }
        #expect(text.localizedCaseInsensitiveContains("taberna"))
        #expect(text.localizedCaseInsensitiveContains("Xuacu"))
        #expect(messages.contains { $0.contains("texto escaneado") })
    }

    @Test func cleansHyphenationAndBlankLines() {
        let cleaned = ScriptImporter.clean("Los investi-\ngadores llegan.   \n\n\n\nFin")
        #expect(cleaned == "Los investigadores llegan.\n\nFin")
    }
}
