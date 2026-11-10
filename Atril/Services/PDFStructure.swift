import Foundation
import PDFKit

/// Recupera la estructura de un PDF maquetado: los módulos no tienen encabezados como tales,
/// sino líneas sueltas con otra fuente. Con el tamaño y el estilo de cada línea se distinguen
/// títulos, texto para leer (cursiva), cabeceras repetidas y párrafos partidos, y se devuelve
/// un texto con marcas (`#`, `##`, `>`) que el analizador sabe interpretar.
enum PDFStructure {
    struct Line: Equatable {
        var text: String
        var size: CGFloat
        var isBold = false
        var isItalic = false
        var page: Int
        /// Está entre las primeras o últimas líneas de la página: posible cabecera o pie.
        var isEdge = false
    }

    #if os(iOS)
    private typealias PlatformFont = UIFont
    #else
    private typealias PlatformFont = NSFont
    #endif

    static func text(of document: PDFDocument) -> String {
        markdown(lines(of: document), pageCount: document.pageCount)
    }

    /// Líneas de todas las páginas con su fuente. `onPage` avisa de la página que empieza (leer
    /// un módulo de cientos de páginas lleva unos segundos); se para si se cancela la tarea.
    static func lines(of document: PDFDocument, onPage: (Int) -> Void = { _ in }) -> [Line] {
        var result: [Line] = []
        for index in 0..<document.pageCount {
            if Task.isCancelled { break }
            onPage(index)
            guard let attributed = document.page(at: index)?.attributedString else { continue }
            var pageLines: [Line] = []
            let string = attributed.string as NSString
            string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: [.byLines, .substringNotRequired]) { _, range, _, _ in
                let text = string.substring(with: range).trimmed
                guard !text.isEmpty else { return }
                var sizes: [CGFloat: Int] = [:]
                var bold = 0, italic = 0, total = 0
                attributed.enumerateAttribute(.font, in: range) { value, run, _ in
                    guard let font = value as? PlatformFont else { return }
                    let name = font.fontName.lowercased()
                    sizes[(font.pointSize * 2).rounded() / 2, default: 0] += run.length
                    total += run.length
                    if ["bold", "black", "heavy", "demi", "semibold"].contains(where: name.contains) { bold += run.length }
                    if ["italic", "oblique", "cursiv"].contains(where: name.contains) { italic += run.length }
                }
                pageLines.append(Line(
                    text: text,
                    // A igualdad de caracteres, el tamaño mayor (que no dependa del orden del diccionario).
                    size: sizes.max { ($0.value, $0.key) < ($1.value, $1.key) }?.key ?? 0,
                    isBold: total > 0 && bold * 2 > total,
                    isItalic: total > 0 && italic * 10 >= total * 8,
                    page: index
                ))
            }
            for position in pageLines.indices {
                pageLines[position].isEdge = position < 2 || position >= pageLines.count - 2
            }
            result += pageLines
        }
        return result
    }

    /// Convierte las líneas en texto con marcas. `headingRatio` es cuánto mayor que el cuerpo
    /// tiene que ser una línea para contar como título (en OCR el tamaño es menos fiable).
    static func markdown(_ all: [Line], pageCount: Int, headingRatio: CGFloat = 1.12) -> String {
        let kept = removingFurniture(all, pageCount: pageCount)
        guard !kept.isEmpty else { return "" }
        let body = bodySize(of: kept)
        let lines = joiningWrappedHeadings(kept, minimumSize: body * headingRatio)
        let typicalLength = median(lines.filter { abs($0.size - body) < 0.6 }.map(\.text.count))

        func isHeadingShape(_ line: Line) -> Bool {
            let text = line.text
            guard text.count <= 90, let first = text.first, !first.isLowercase else { return false }
            if let last = text.last, ".,;:…".contains(last) { return false }
            let digits = text.filter(\.isNumber).count
            return digits * 3 < text.count
        }

        // Tamaños de título, de mayor a menor, con cuántas veces aparecen.
        var counts: [CGFloat: Int] = [:]
        for line in lines where line.size >= body * headingRatio && isHeadingShape(line) {
            counts[line.size, default: 0] += 1
        }
        var sizes = counts.keys.sorted(by: >)

        // El título del documento: el tamaño mayor si solo sale una vez, en la primera página.
        var titleLine: Line?
        if let largest = sizes.first, counts[largest] == 1, largest >= body * 1.4,
           let line = lines.first(where: { $0.size == largest && isHeadingShape($0) }), line.page == 0 {
            titleLine = line
            sizes.removeFirst()
        }
        // Si el siguiente tamaño es raro y debajo hay muchos, son partes o actos y debajo las
        // escenas; si no, ese tamaño ya son las escenas. Lo más pequeño son subapartados.
        var partSize: CGFloat?
        var sceneSize = sizes.first
        if sizes.count >= 2, let first = counts[sizes[0]], let second = counts[sizes[1]], first <= 3, second >= first * 2 {
            partSize = sizes[0]
            sceneSize = sizes[1]
        }
        // Sin títulos por tamaño: las líneas cortas en negrita hacen de títulos de escena.
        let boldAreScenes = sceneSize == nil

        func kind(of line: Line) -> Kind {
            if line == titleLine { return .title }
            guard isHeadingShape(line) else { return .text }
            if line.size == partSize { return .part }
            if line.size == sceneSize { return .scene }
            if line.size >= body * headingRatio { return .subsection }
            if line.isBold, line.text.split(separator: " ").count <= 9 { return boldAreScenes ? .scene : .subsection }
            return .text
        }

        var output: [String] = []
        var paragraph: [Line] = []

        func flush() {
            guard !paragraph.isEmpty else { return }
            var text = ""
            for line in paragraph {
                if text.hasSuffix("-"), line.text.first?.isLowercase == true {
                    text.removeLast()
                    text += line.text
                } else {
                    text += text.isEmpty ? line.text : " \(line.text)"
                }
            }
            let italic = paragraph.filter(\.isItalic).count * 10 >= paragraph.count * 8
            let isReadAloud = italic && text.split(separator: " ").count >= 10
            output.append(isReadAloud ? "> \(text)" : text)
            paragraph = []
        }

        func startsParagraph(_ line: Line, after previous: Line) -> Bool {
            if line.isItalic != previous.isItalic { return true }
            if let first = line.text.first, "•–—-*".contains(first) { return true }
            guard let last = previous.text.last else { return true }
            if last == ":" { return true }
            guard ".!?»…”)".contains(last) else { return false }
            // Línea acabada en punto y más corta que las demás: ahí termina el párrafo.
            if Double(previous.text.count) < Double(typicalLength) * 0.8 { return true }
            return line.page != previous.page && line.text.first?.isUppercase == true
        }

        for line in lines {
            let lineKind = kind(of: line)
            switch lineKind {
            case .title, .part, .scene:
                flush()
                output.append("\(lineKind == .scene ? "##" : "#") \(line.text)")
            case .subsection:
                // Un apartado dentro de la escena: se queda en su texto, no parte la escena.
                flush()
                output.append("\(line.text):")
            case .text:
                if let previous = paragraph.last, startsParagraph(line, after: previous) { flush() }
                paragraph.append(line)
            }
        }
        flush()
        return output.joined(separator: "\n\n")
    }

    private enum Kind { case title, part, scene, subsection, text }

    /// Un título largo ocupa varias líneas seguidas del mismo tamaño grande: es uno solo.
    private static func joiningWrappedHeadings(_ lines: [Line], minimumSize: CGFloat) -> [Line] {
        var result: [Line] = []
        for line in lines {
            if let last = result.last, line.size >= minimumSize, last.size == line.size, last.page == line.page,
               let end = last.text.last, !".:!?".contains(end) {
                result[result.count - 1].text += " \(line.text)"
            } else {
                result.append(line)
            }
        }
        return result
    }

    /// Quita números de página y las líneas que se repiten en los bordes de las páginas.
    private static func removingFurniture(_ lines: [Line], pageCount: Int) -> [Line] {
        let key: (Line) -> String = { line in
            Prose.fold(line.text).replacingOccurrences(of: #"\d+"#, with: "#", options: .regularExpression)
        }
        var pages: [String: Set<Int>] = [:]
        for line in lines where line.isEdge {
            pages[key(line), default: []].insert(line.page)
        }
        let threshold = max(2, Int((Double(pageCount) * 0.4).rounded(.up)))
        let body = bodySize(of: lines)
        return lines.filter { line in
            if line.isEdge, line.text.range(of: #"^[\W_]*\d{1,4}[\W_]*$"#, options: .regularExpression) != nil { return false }
            // Un título grande puede coincidir con la cabecera: solo se quita lo que no destaca.
            if pageCount >= 3, line.isEdge, line.text.count < 80, line.size <= body * 1.1,
               (pages[key(line)]?.count ?? 0) >= threshold { return false }
            return true
        }
    }

    /// El tamaño con más caracteres es el del cuerpo del texto (a igualdad, el menor).
    private static func bodySize(of lines: [Line]) -> CGFloat {
        var weights: [CGFloat: Int] = [:]
        for line in lines { weights[line.size, default: 0] += line.text.count }
        return weights.max { ($0.value, -$0.key) < ($1.value, -$1.key) }?.key ?? 0
    }

    private static func median(_ values: [Int]) -> Int {
        guard !values.isEmpty else { return 0 }
        return values.sorted()[values.count / 2]
    }
}
