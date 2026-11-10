import CoreGraphics
import Foundation
import PDFKit
import UniformTypeIdentifiers
import Vision

/// Extrae el texto de un guion en PDF, TXT, Markdown o RTF.
enum ScriptImporter {
    static let allowedTypes: [UTType] = [.pdf, .plainText, .utf8PlainText, .rtf, UTType(filenameExtension: "md") ?? .plainText]

    enum Failure: LocalizedError {
        case unreadable
        case empty

        var errorDescription: String? {
            switch self {
            case .unreadable: "No se ha podido leer el archivo."
            case .empty: "No se ha encontrado texto en el archivo, ni siquiera leyendo las páginas como imagen."
            }
        }
    }

    /// Lee el guion. Los PDF escaneados (sin capa de texto) se leen con reconocimiento de
    /// texto en el propio dispositivo; `progress` informa de la página en curso.
    static func load(_ url: URL, progress: @escaping @MainActor (String) -> Void = { _ in }) async throws -> String {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let text: String
        switch UTType(filenameExtension: url.pathExtension) {
        case .some(let type) where type.conforms(to: .pdf):
            guard let document = PDFDocument(url: url) else { throw Failure.unreadable }
            // Una sola pasada por las páginas: las líneas con su fuente sirven para saber si hay
            // capa de texto y, si la hay, para recuperar la maquetación.
            let pageCount = document.pageCount
            let lines = PDFStructure.lines(of: document) { index in
                guard pageCount > 20, index.isMultiple(of: 10) else { return }
                Task { @MainActor in progress("Leyendo la página \(index + 1) de \(pageCount)") }
            }
            try Task.checkCancellation()
            let words = lines.reduce(0) { $0 + WordCounter.count($1.text) }
            if words < document.pageCount * 30 {
                text = try await recognize(document, progress: progress)
            } else {
                // La maquetación dice qué es título y qué es texto para leer.
                let structured = PDFStructure.markdown(lines, pageCount: document.pageCount)
                text = structured.isEmpty
                    ? (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n\n")
                    : structured
            }
        case .some(let type) where type.conforms(to: .rtf):
            let data = try Data(contentsOf: url)
            let attributed = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
            text = attributed.string
        default:
            let data = try Data(contentsOf: url)
            text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        }

        let cleaned = clean(text)
        guard !cleaned.isEmpty else { throw Failure.empty }
        return cleaned
    }

    /// Reconocimiento de texto (OCR) en español e inglés. Las páginas se dibujan de una en una y
    /// se reconocen varias a la vez, que es lo lento; el texto se une después en su orden.
    static func recognize(_ document: PDFDocument, progress: @escaping @MainActor (String) -> Void) async throws -> String {
        let pageCount = document.pageCount
        let width = max(1, min(3, ProcessInfo.processInfo.activeProcessorCount / 2))
        var found = [[(text: String, height: CGFloat)]](repeating: [], count: pageCount)
        var heights = [CGFloat](repeating: 0, count: pageCount)
        try await withThrowingTaskGroup(of: (Int, [(text: String, height: CGFloat)]).self) { group in
            var running = 0
            var done = 0
            func collect(_ result: (Int, [(text: String, height: CGFloat)])) async {
                found[result.0] = result.1
                running -= 1
                done += 1
                await progress("Leyendo el texto escaneado · \(done) de \(pageCount) páginas")
            }
            await progress("Leyendo el texto escaneado · 0 de \(pageCount) páginas")
            for index in 0..<pageCount {
                try Task.checkCancellation()
                // La página siguiente se dibuja mientras se reconocen las anteriores.
                guard let page = document.page(at: index), let image = render(page) else { continue }
                heights[index] = page.bounds(for: .mediaBox).height
                if running == width, let result = try await group.next() { await collect(result) }
                group.addTask(priority: .userInitiated) { (index, try recognizeLines(in: image)) }
                running += 1
            }
            while let result = try await group.next() { await collect(result) }
        }

        var lines: [PDFStructure.Line] = []
        for (index, page) in found.enumerated() {
            for (position, line) in page.enumerated() {
                lines.append(PDFStructure.Line(
                    text: line.text,
                    // La altura de la línea hace de tamaño de letra: distingue los títulos.
                    size: (line.height * heights[index]).rounded(),
                    page: index,
                    isEdge: position < 2 || position >= page.count - 2
                ))
            }
        }
        return PDFStructure.markdown(lines, pageCount: pageCount, headingRatio: 1.3)
    }

    /// Dibuja la página a unos 200 ppp, suficiente para el reconocimiento de texto.
    static func render(_ page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 200 / 72
        let width = Int(bounds.width * scale), height = Int(bounds.height * scale)
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)
        return context.makeImage()
    }

    /// Líneas reconocidas con su altura relativa a la página.
    static func recognizeLines(in image: CGImage) throws -> [(text: String, height: CGFloat)] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["es-ES", "en-US"]
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { observation in
            observation.topCandidates(1).first.map { ($0.string, observation.boundingBox.height) }
        }
    }

    /// Normaliza saltos de línea y espacios típicos de los PDF maquetados.
    static func clean(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\u{00AD}", with: "")
            .replacingOccurrences(of: "-\n", with: "")
            .replacingOccurrences(of: "[ \t]+\n", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func suggestedTitle(for url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }
}
