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
            let layer = (0..<document.pageCount)
                .compactMap { document.page(at: $0)?.string }
                .joined(separator: "\n\n")
            let words = layer.split(whereSeparator: \.isWhitespace).count
            if words < document.pageCount * 30 {
                text = try await recognize(document, progress: progress)
            } else {
                text = layer
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

    /// Reconocimiento de texto (OCR) página a página, en español e inglés.
    static func recognize(_ document: PDFDocument, progress: @escaping @MainActor (String) -> Void) async throws -> String {
        var pages: [String] = []
        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            await progress("Leyendo página \(index + 1) de \(document.pageCount) (texto escaneado)")
            guard let page = document.page(at: index), let image = render(page) else { continue }
            let text = try await Task.detached(priority: .userInitiated) { try recognizeText(in: image) }.value
            pages.append(text)
        }
        return pages.joined(separator: "\n\n")
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

    static func recognizeText(in image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["es-ES", "en-US"]
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
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
