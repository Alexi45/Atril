import Foundation

/// Trocea el guion respetando su estructura (encabezados y párrafos).
enum ScriptChunker {
    struct Section: Hashable {
        var heading: String
        var body: String
        /// Encabezado de nivel superior (parte, acto, capítulo) bajo el que cae.
        var part: String
        /// Es el «# Título» del documento.
        var isTitle = false

        var wordCount: Int { body.split(whereSeparator: \.isWhitespace).count }
    }

    struct Chunk: Hashable {
        var text: String
        var part: String
    }

    static func isHeading(_ line: String) -> Bool {
        let text = line.trimmed
        guard !text.isEmpty, text.count <= 90 else { return false }
        if text.hasPrefix("#") { return true }
        if text.range(of: #"^(\d{1,2}|[IVXLC]{1,6})[\.\)\-–:]\s+\p{Lu}"#, options: .regularExpression) != nil,
           !text.hasSuffix(".") { return true }
        let keyword = #"^(escena|cap[ií]tulo|parte|acto|localizaci[oó]n|encuentro|ap[eé]ndice|epílogo|ep[ií]logo|pr[oó]logo|introducci[oó]n|trasfondo|desenlace|conclusi[oó]n)\b"#
        if text.range(of: keyword, options: [.regularExpression, .caseInsensitive]) != nil, text.count < 70,
           !text.hasSuffix(".") { return true }
        let letters = text.filter(\.isLetter)
        return letters.count >= 4 && text.count < 60 && letters.allSatisfy(\.isUppercase) && !text.hasSuffix(".")
    }

    static func headingText(_ line: String) -> String {
        line.trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "#* ")).trimmed
    }

    /// Nivel de un encabezado: 1 para partes y actos, 2 para el resto.
    static func level(_ line: String) -> Int {
        let text = line.trimmed
        if text.hasPrefix("## ") || text.hasPrefix("### ") { return 2 }
        if text.hasPrefix("# ") { return 1 }
        if text.range(of: #"^(parte|acto|cap[ií]tulo)\b"#, options: [.regularExpression, .caseInsensitive]) != nil { return 1 }
        return 2
    }

    static func sections(_ script: String) -> [Section] {
        var sections: [Section] = []
        var heading = ""
        var part = ""
        var body: [String] = []
        var isFirstHeading = true
        var isTitle = false

        func flush() {
            let text = body.joined(separator: "\n").trimmed
            if !text.isEmpty || !heading.isEmpty {
                sections.append(Section(heading: heading, body: text, part: part, isTitle: isTitle))
            }
            body = []
        }

        for line in script.components(separatedBy: "\n") {
            if isHeading(line) {
                flush()
                let title = headingText(line)
                // El primer «# Título» suele ser el nombre de la aventura, no una parte.
                isTitle = isFirstHeading && line.trimmed.hasPrefix("# ")
                if level(line) == 1 && !isTitle {
                    part = title
                }
                heading = title
                isFirstHeading = false
            } else {
                body.append(line)
            }
        }
        flush()
        return sections
    }

    /// Agrupa secciones en trozos de como mucho `maxWords` palabras. Una sección demasiado
    /// larga se parte por párrafos.
    static func chunks(_ script: String, maxWords: Int) -> [Chunk] {
        var chunks: [Chunk] = []
        var current: [String] = []
        var currentWords = 0
        var currentPart = ""

        func flush() {
            let text = current.joined(separator: "\n\n").trimmed
            if !text.isEmpty { chunks.append(Chunk(text: text, part: currentPart)) }
            current = []
            currentWords = 0
        }

        for section in sections(script) {
            let header = section.heading.isEmpty ? "" : "\(section.isTitle ? "#" : "##") \(section.heading)\n"
            var pieces = [header + section.body]
            if section.wordCount > maxWords {
                pieces = []
                var piece = header
                var pieceWords = 0
                for paragraph in section.body.components(separatedBy: "\n\n") {
                    let words = paragraph.split(whereSeparator: \.isWhitespace).count
                    if pieceWords + words > maxWords, pieceWords > 0 {
                        pieces.append(piece)
                        piece = header.isEmpty ? "" : "## \(section.heading) (continuación)\n"
                        pieceWords = 0
                    }
                    piece += paragraph + "\n\n"
                    pieceWords += words
                }
                pieces.append(piece)
            }
            for piece in pieces {
                let words = piece.split(whereSeparator: \.isWhitespace).count
                if currentWords + words > maxWords || (section.part != currentPart && currentWords > 0) {
                    flush()
                }
                currentPart = section.part
                current.append(piece.trimmed)
                currentWords += words
            }
        }
        flush()
        return chunks
    }
}

/// Buscador BM25 sobre pasajes del guion. Permite al tutor citar el guion sin meterlo
/// entero en el contexto del modelo.
struct ScriptIndex {
    struct Passage: Hashable, Identifiable {
        var id: Int
        var heading: String
        var text: String
    }

    let passages: [Passage]
    private let termFrequencies: [[String: Int]]
    private let documentFrequency: [String: Int]
    private let lengths: [Int]
    private let averageLength: Double

    init(script: String, passageWords: Int = 110) {
        var passages: [Passage] = []
        for section in ScriptChunker.sections(script) {
            var buffer: [String] = []
            var words = 0
            func flush() {
                let text = buffer.joined(separator: "\n").trimmed
                if !text.isEmpty { passages.append(Passage(id: passages.count, heading: section.heading, text: text)) }
                buffer = []
                words = 0
            }
            for paragraph in section.body.components(separatedBy: "\n") where !paragraph.trimmed.isEmpty {
                let count = paragraph.split(whereSeparator: \.isWhitespace).count
                if words + count > passageWords && words > 0 { flush() }
                buffer.append(paragraph)
                words += count
            }
            flush()
        }
        self.passages = passages
        termFrequencies = passages.map { passage in
            Self.terms(passage.heading + " " + passage.text).reduce(into: [:]) { $0[$1, default: 0] += 1 }
        }
        var frequency: [String: Int] = [:]
        for terms in termFrequencies { for term in terms.keys { frequency[term, default: 0] += 1 } }
        documentFrequency = frequency
        lengths = termFrequencies.map { $0.values.reduce(0, +) }
        averageLength = Double(lengths.reduce(0, +)) / Double(max(lengths.count, 1))
    }

    func search(_ query: String, limit: Int) -> [Passage] {
        let queryTerms = Set(Self.terms(query))
        guard !queryTerms.isEmpty else { return [] }
        let count = Double(passages.count)
        let k1 = 1.2, b = 0.75
        let scored = passages.indices.compactMap { index -> (Int, Double)? in
            var score = 0.0
            for term in queryTerms {
                guard let tf = termFrequencies[index][term] else { continue }
                let df = Double(documentFrequency[term] ?? 0)
                let idf = log(1 + (count - df + 0.5) / (df + 0.5))
                let norm = Double(tf) * (k1 + 1) / (Double(tf) + k1 * (1 - b + b * Double(lengths[index]) / averageLength))
                score += idf * norm
            }
            return score > 0 ? (index, score) : nil
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(limit).map { passages[$0.0] }
    }

    private static let stopwords: Set<String> = [
        "que", "los", "las", "del", "una", "uno", "unos", "unas", "por", "con", "para", "como", "pero", "sus",
        "son", "esta", "este", "estos", "estas", "ese", "esa", "eso", "hay", "han", "has", "hace", "muy", "mas",
        "sin", "sobre", "entre", "cuando", "donde", "quien", "todo", "toda", "todos", "todas", "tiene", "tienen",
        "ser", "era", "fue", "sea", "les", "nos", "ahora", "aqui", "alli", "hacer", "hago", "puede", "pueden",
        "que", "porque", "tambien", "solo", "ante", "desde", "hasta", "durante", "the", "and", "esto", "algo",
        "otro", "otra", "otros", "cada", "mismo", "misma", "dame", "dime", "debo", "deberia", "jugadores",
    ]

    static func terms(_ text: String) -> [String] {
        Prose.words(text).compactMap { word in
            guard word.count >= 3, !stopwords.contains(word) else { return nil }
            return stem(word)
        }
    }

    /// Lematizador muy ligero para el español: une singular y plural y algunos géneros.
    static func stem(_ word: String) -> String {
        var value = word
        for suffix in ["iones", "ces", "es", "s"] where value.count > suffix.count + 3 && value.hasSuffix(suffix) {
            value = String(value.dropLast(suffix.count))
            if suffix == "iones" { value += "ion" }
            if suffix == "ces" { value += "z" }
            break
        }
        if value.count > 5, let last = value.last, "ao".contains(last) { value.removeLast() }
        return value
    }
}
