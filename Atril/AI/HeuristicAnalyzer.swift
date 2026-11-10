import Foundation
import NaturalLanguage

/// Organiza un guion sin modelo de lenguaje: detecta secciones, texto para leer en voz alta,
/// tiradas, pérdidas de Cordura, pistas y personajes. Es instantáneo y funciona en cualquier
/// dispositivo; también es el respaldo cuando la IA no puede con un trozo.
enum HeuristicAnalyzer {
    enum Kind { case title, background, hook, scene, endings, appendix }

    /// Borradores antes de unirlos: la IA los parte de aquí para enriquecer escena a escena.
    struct Drafts {
        /// Un trozo por escena, en orden.
        var scenes: [DraftChunk]
        /// Texto original de cada escena (mismo orden que `scenes`).
        var bodies: [String]
        var characters: [DraftCharacter]
        var overview: DraftOverview

        var allChunks: [DraftChunk] { scenes + [DraftChunk(characters: characters)] }
    }

    static func analyze(script: String, system: GameSystem) -> AdventureGuide {
        let drafts = drafts(script: script, system: system)
        return GuideMerger.merge(chunks: drafts.allChunks, overview: drafts.overview, system: system)
    }

    private struct DraftsKey: Hashable {
        var script: String
        var system: GameSystem
    }

    /// El mismo guion se analiza al importarlo, al prepararlo la IA y al comprobar lo que hizo:
    /// los borradores se calculan una vez.
    private static let cachedDrafts = BoundedCache<DraftsKey, Drafts>(limit: 2)

    static func drafts(script: String, system: GameSystem) -> Drafts {
        cachedDrafts.value(for: DraftsKey(script: script, system: system)) { makeDrafts(script: script, system: system) }
    }

    private static func makeDrafts(script: String, system: GameSystem) -> Drafts {
        let sections = ScriptChunker.sections(script)
        var chunks: [DraftChunk] = []
        var bodies: [String] = []
        var overview = DraftOverview()
        var appendix = ""
        var introduction = ""

        for section in sections {
            switch kind(of: section) {
            case .title:
                introduction = Prose.sentences(plain(section.body)).prefix(2).joined(separator: " ")
            case .background:
                overview.truth = Prose.join(overview.truth, plain(section.body).truncated(words: 160))
            case .hook:
                overview.hook = Prose.join(overview.hook, plain(section.body).truncated(words: 120))
            case .endings:
                overview.endings += endings(in: section.body)
            case .appendix:
                appendix += section.body + "\n"
            case .scene:
                guard let scene = scene(from: section, system: system) else { continue }
                chunks.append(DraftChunk(summary: scene.summary, scenes: [scene], act: section.part))
                bodies.append(section.body)
            }
        }

        // Si el guion no tiene secciones reconocibles, al menos una escena con todo.
        if chunks.isEmpty, let first = sections.first {
            let whole = ScriptChunker.Section(heading: first.heading.isEmpty ? "Aventura" : first.heading,
                                              body: script, part: "")
            if let scene = scene(from: whole, system: system) {
                chunks.append(DraftChunk(scenes: [scene]))
                bodies.append(script)
            }
        }
        // Premisa: la presentación del guion y el arranque del gancho; si no hay, el comienzo del trasfondo.
        let hookStart = Prose.sentences(overview.hook).prefix(2).joined(separator: " ")
        overview.premise = Prose.join(introduction, hookStart)
        if overview.premise.isEmpty {
            overview.premise = Prose.sentences(overview.truth.isEmpty ? plain(script) : overview.truth).prefix(3).joined(separator: " ")
        }

        let characters = Self.characters(in: script, appendix: appendix)
        // Asocia a cada escena los personajes que se nombran en ella.
        let nameWords = characters.map { Prose.words($0.name).filter { $0.count > 3 } }
        for index in chunks.indices {
            guard var scene = chunks[index].scenes.first else { continue }
            let text = Prose.fold(scene.title + " " + scene.readAloud + " " + bodies[index])
            scene.characterNames = zip(characters, nameWords).filter { _, name in
                !name.isEmpty && name.contains { text.containsBytes($0) }
            }.map(\.0.name)
            chunks[index].scenes = [scene]
        }

        overview.prep = prep(system: system, characters: characters, hasStats: !appendix.isEmpty)
        return Drafts(scenes: chunks, bodies: bodies, characters: characters, overview: overview)
    }

    static func kind(of section: ScriptChunker.Section) -> Kind {
        if section.isTitle { return .title }
        let heading = Prose.fold(section.heading)
        func has(_ words: [String]) -> Bool { words.contains { heading.contains($0) } }
        if has(["trasfondo", "introduccion", "para el guardian", "para el master", "para el dj", "resumen", "la verdad", "historia previa", "antecedentes", "sinopsis"]) { return .background }
        if has(["gancho", "como empezar", "comienzo", "implicar a los", "inicio de la aventura"]) { return .hook }
        if has(["desenlace", "conclusion", "final", "epilogo", "recompensa"]) { return .endings }
        if has(["estadistica", "apendice", "anexo", "personajes no jugadores", "dramatis", "ayudas de juego", "pnj"]) { return .appendix }
        if section.heading.isEmpty && section.wordCount < 120 { return .background }
        return .scene
    }

    // MARK: Escenas

    static func scene(from section: ScriptChunker.Section, system: GameSystem) -> DraftScene? {
        let lines = section.body.components(separatedBy: "\n")
        var readAloud: [String] = []
        var rest: [String] = []
        var readNext = false
        for line in lines {
            let text = line.trimmed
            if text.hasPrefix(">") {
                readAloud.append(text.trimmingCharacters(in: CharacterSet(charactersIn: "> ")))
                readNext = false
            } else if readNext, !text.isEmpty {
                readAloud.append(text)
                readNext = false
            } else {
                if isReadAloudCue(text) {
                    readNext = true
                } else {
                    rest.append(line)
                }
            }
        }
        let body = rest.joined(separator: "\n")
        let prose = plain(body)
        guard !section.heading.isEmpty || !prose.isEmpty else { return nil }

        var scene = DraftScene(title: cleanTitle(section.heading.isEmpty ? "Escena" : section.heading))
        scene.act = section.part
        scene.readAloud = readAloud.joined(separator: " ")
        // Las frases del cuerpo se trocean y se pliegan una vez para todas las búsquedas.
        let sentences = Sentences(Prose.sentences(prose))
        scene.summary = sentences.raw.prefix(3).joined(separator: " ")
        scene.place = place(in: scene.readAloud + " " + prose) ?? ""
        scene.checks = checks(in: sentences, system: system)
        scene.clues = clues(in: sentences)
        scene.danger = danger(in: sentences)
        scene.goals = scene.clues.prefix(3).map { "Descubrir: \($0.title.lowercased())" }
        scene.tips = tips(for: scene, system: system)
        scene.ifStuck = ifStuck(for: scene)
        return scene
    }

    /// Frase que anuncia el texto para leer: «Cuando lleguen, léeles lo siguiente:».
    static func isReadAloudCue(_ text: String) -> Bool {
        guard text.count < 140 else { return false }
        let folded = Prose.fold(text)
        let cues = ["lee en voz alta", "leed en voz alta", "leer en voz alta", "para leer", "leeles", "leedles",
                    "lee lo siguiente", "leed lo siguiente", "lee a los jugadores", "leed a los jugadores",
                    "leer a los jugadores", "lee o parafrasea", "leed o parafrasead", "lee este texto"]
        return cues.contains { folded.containsBytes($0) }
    }

    static func cleanTitle(_ heading: String) -> String {
        heading.replacingOccurrences(of: #"^(\d{1,2}|[IVXLC]{1,6})[\.\)\-–:]\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^(escena|localizaci[oó]n)\s*\d*[\.:–-]?\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmed
    }

    /// Quita marcas de Markdown y viñetas.
    static func plain(_ text: String) -> String {
        text.components(separatedBy: "\n")
            .map { $0.trimmed.trimmingCharacters(in: CharacterSet(charactersIn: ">-*#• ")) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .replacingOccurrences(of: "**", with: "")
    }

    private static let placePattern = try! NSRegularExpression(pattern: #"\b(en|hacia|desde)\s+(el|la|los|las)\s+((?:[\p{Lu}][\p{L}]+\s?){1,3})"#)

    static func place(in text: String) -> String? {
        guard let found = placePattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let match = Range(found.range, in: text) else { return nil }
        let words = text[match].split(separator: " ").dropFirst()
        return words.joined(separator: " ").trimmed.capitalizedFirst
    }

    // MARK: Tiradas

    static let cthulhuSkills = [
        "Buscar libros", "Descubrir", "Psicología", "Persuasión", "Charlatanería", "Encanto", "Intimidar",
        "Mecánica", "Ocultismo", "Historia", "Antropología", "Arqueología", "Medicina", "Primeros auxilios",
        "Sigilo", "Escuchar", "Esquivar", "Trepar", "Saltar", "Nadar", "Lanzar", "Conducir", "Cerrajería",
        "Disfrazarse", "Psicoanálisis", "Mitos de Cthulhu", "Orientarse", "Rastrear", "Juego de manos",
        "Ciencia", "Derecho", "Tasación", "Contabilidad", "Electricidad", "Supervivencia", "Equitación",
        "Pilotar", "Suerte", "Atletismo", "Combatir", "Armas de fuego", "Idioma", "FUE", "CON", "DES", "POD",
        "INT", "TAM", "APA", "EDU",
    ]

    static let dndSkills = [
        "Percepción", "Investigación", "Perspicacia", "Atletismo", "Acrobacias", "Sigilo", "Persuasión",
        "Engaño", "Intimidación", "Arcanos", "Historia", "Religión", "Naturaleza", "Supervivencia",
        "Medicina", "Trato con animales", "Juego de manos", "Interpretación", "Fuerza", "Destreza",
        "Constitución", "Inteligencia", "Sabiduría", "Carisma",
    ]

    /// Frases de un texto con su versión plegada (sin tildes ni mayúsculas, con las palabras
    /// separadas por un espacio y espacios a los lados, para buscar palabras completas).
    struct Sentences {
        let raw: [String]
        let padded: [String]

        init(_ raw: [String]) {
            self.raw = raw
            padded = raw.map { " \(Prose.fold($0)) " }
        }

        init(of text: String) {
            self.init(Prose.sentences(plain(text)))
        }
    }

    /// Una habilidad con su forma de buscarla: las abreviaturas («FUE», «DES») en mayúsculas en
    /// el texto original; el resto como palabras completas en el texto plegado.
    private struct SkillKey {
        let name: String
        let padded: String
        let abbreviation: NSRegularExpression?

        init(_ name: String) {
            self.name = name
            padded = " \(Prose.fold(name)) "
            abbreviation = name.count <= 3 ? try? NSRegularExpression(pattern: "\\b\(name)\\b") : nil
        }

        func found(in sentence: String, padded folded: String) -> Bool {
            if let abbreviation {
                return sentence.containsBytes(name)
                    && abbreviation.firstMatch(in: sentence, range: NSRange(sentence.startIndex..., in: sentence)) != nil
            }
            return folded.containsBytes(padded)
        }
    }

    private static let cthulhuKeys = cthulhuSkills.map(SkillKey.init)
    private static let dndKeys = dndSkills.map(SkillKey.init)
    private static let otherKeys = cthulhuKeys + dndKeys
    private static let difficultyClass = try! NSRegularExpression(pattern: #"\bCD\s*\d+"#)
    private static let sanityLoss = try! NSRegularExpression(
        pattern: #"(\d+D?\d*/\d+D\d+(\s*\+\s*\d+)?|\d+/\d+)\s*(puntos\s*)?(de\s*)?(Cordura|COR)"#, options: .caseInsensitive)

    static func checks(in text: String, system: GameSystem) -> [AdventureGuide.Check] {
        checks(in: Sentences(of: text), system: system)
    }

    static func checks(in sentences: Sentences, system: GameSystem) -> [AdventureGuide.Check] {
        let skills = system == .dnd ? dndKeys : (system == .cthulhu ? cthulhuKeys : otherKeys)
        var result: [AdventureGuide.Check] = []
        for (sentence, folded) in zip(sentences.raw, sentences.padded) {
            let mentionsRoll = folded.containsBytes("tirada") || folded.containsBytes("prueba") || folded.containsBytes("salvacion")
                || folded.containsBytes("dificil") || folded.containsBytes("extrem")
                || difficultyClass.firstMatch(in: sentence, range: NSRange(sentence.startIndex..., in: sentence)) != nil
            guard mentionsRoll else { continue }
            for skill in skills where skill.found(in: sentence, padded: folded) {
                guard !result.contains(where: { $0.skill == skill.name }) else { continue }
                result.append(AdventureGuide.Check(skill: skill.name, difficulty: difficulty(in: sentence), purpose: sentence.truncated(words: 30)))
            }
        }
        // Pérdidas de Cordura: «cuesta 1/1D4 de Cordura», «0/1D6 COR».
        for sentence in sentences.raw {
            guard let match = sanityLoss.firstMatch(in: sentence, range: NSRange(sentence.startIndex..., in: sentence)),
                  let range = Range(match.range, in: sentence) else { continue }
            let value = sentence[range].split(separator: " ").first.map(String.init) ?? ""
            result.append(AdventureGuide.Check(skill: "Cordura", difficulty: value, purpose: sentence.truncated(words: 30)))
        }
        return result
    }

    static func difficulty(in sentence: String) -> String {
        if let range = sentence.range(of: #"\bCD\s*\d+"#, options: .regularExpression) { return String(sentence[range]) }
        let folded = Prose.fold(sentence)
        if folded.contains("extrem") { return "Extrema" }
        if folded.contains("dificil") { return "Difícil" }
        if folded.contains("dado de penalizacion") { return "Con penalización" }
        if folded.contains("dado de bonificacion") { return "Con bonificación" }
        return ""
    }

    // MARK: Pistas, peligros y personajes

    static func clues(in text: String) -> [DraftClue] {
        clues(in: Sentences(of: text))
    }

    static func clues(in sentences: Sentences) -> [DraftClue] {
        var result: [DraftClue] = []
        for (sentence, folded) in zip(sentences.raw, sentences.padded) where result.count < 4 {
            // « pista» en el texto con espacios a los lados: empieza por «pista» o la nombra después.
            let isClue = folded.containsBytes(" pista") || folded.containsBytes("encuentran")
                || folded.containsBytes("descubren") || folded.containsBytes("revela") || folded.containsBytes("averiguan")
                || folded.containsBytes("registro") || folded.containsBytes("diario") || folded.containsBytes("carta")
            guard isClue, sentence.count > 25 else { continue }
            let detail = sentence.replacingOccurrences(of: #"^Pista\s*(clave)?\s*:\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
            result.append(DraftClue(
                title: clueTitle(detail),
                detail: detail.truncated(words: 40),
                isCore: folded.containsBytes("clave") || folded.containsBytes("imprescindible") || folded.containsBytes("esencial")
            ))
        }
        return Array(result.prefix(4))
    }

    /// Título corto de una pista: el objeto que se encuentra, o las primeras palabras.
    static func clueTitle(_ sentence: String) -> String {
        let pattern = #"\b(el|la|un|una)\s+(registro|diario|carta|nota|libro|mapa|fotograf[ií]a|llave|objeto|cuaderno|relato|piedra|lente|signo|s[ií]mbolo|cad[aá]ver|huella|documento)(\s+de(l)?\s+[\p{L}\d]+(\s+[\p{L}\d]+)?)?"#
        if let range = sentence.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
            return String(sentence[range]).capitalizedFirst
        }
        return sentence.truncated(words: 6).replacingOccurrences(of: "…", with: "").trimmed.capitalizedFirst
    }

    private static let dangerKeys = ["ataca", "combate", "pierde", "daño", "muere", "muerte", "herid", "PV", "veneno", "trampa", "cordura"]
        .map(Prose.fold)

    static func danger(in text: String, system: GameSystem) -> String {
        danger(in: Sentences(of: text))
    }

    static func danger(in sentences: Sentences) -> String {
        var found: [String] = []
        for (sentence, folded) in zip(sentences.raw, sentences.padded) where found.count < 2 {
            if dangerKeys.contains(where: { folded.containsBytes($0) }) { found.append(sentence) }
        }
        return found.joined(separator: " ")
    }

    /// Personajes: el reconocedor de nombres de Apple acierta poco en guiones largos en español
    /// (toma «Marina Rivas» por un lugar), así que se combina con señales del propio texto.
    private static let namePattern = try! NSRegularExpression(
        pattern: #"(?:\b(?:don|doña|padre|madre|doctora?|señora?|señorita|fray|sor|capitán|inspectora?|profesora?|tío|tía)\s+)?\p{Lu}\p{Ll}+(?:\s+(?:de\s+)?\p{Lu}\p{Ll}+){0,2}"#)
    /// «Xuacu, el …»: una aposición detrás del nombre.
    private static let appositionStart = try! NSRegularExpression(pattern: #"^\s*,\s*(el|la|un|una|su)?\s*\p{Ll}+"#)
    private static let appositionRole = try! NSRegularExpression(pattern: #"^\s*,\s*(el|la|un|una|su)?\s*[^,.;:()]{3,90}(?=[,.;:])"#)
    private static let speechVerbs: Set<String> = ["dice", "dicen", "cuenta", "explica", "grita", "habla", "responde", "sabe", "quiere", "esta",
                                                   "intenta", "mira", "recibe", "oculta", "miente", "teme", "busca", "pide", "niega", "confiesa"]

    static func characters(in script: String, appendix: String) -> [DraftCharacter] {
        let text = plain(script)
        let (personal, nonPersonal) = nameTags(in: text)

        struct Candidate {
            var name: String
            /// Orden de aparición en el guion: desempata la clasificación para que salga siempre igual.
            var order: Int
            var count = 0
            var score = 0
            var firstSentence = ""
            var apposition = ""
            var hasHonorific = false
        }
        var candidates: [String: Candidate] = [:]
        let nsText = text as NSString
        let length = nsText.length
        namePattern.enumerateMatches(in: text, range: NSRange(location: 0, length: length)) { match, _, _ in
            guard let range = match?.range else { return }
            let raw = nsText.substring(with: range)
            let words = raw.split(separator: " ").map(String.init)
            let hasHonorific = words.count > 1 && words[0].first?.isLowercase == true
            let core = words.drop { $0.first?.isLowercase == true }.joined(separator: " ")
            let key = Prose.fold(core)
            guard !key.isEmpty, !commonCapitalized.contains(Prose.words(core).first ?? ""),
                  !excludedNames.contains(key) else { return }

            var score = 0
            if hasHonorific { score += 3 }
            // Solo el trozo de texto de alrededor, sin copiar el resto del guion en cada nombre.
            let end = range.location + range.length
            let after = String(nsText.substring(with: NSRange(location: end, length: min(440, length - end))).prefix(110))
            let afterRange = NSRange(location: 0, length: (after as NSString).length)
            if appositionStart.firstMatch(in: after, options: .anchored, range: afterRange) != nil { score += 2 }
            let nextWord = Prose.words(after).first ?? ""
            if speechVerbs.contains(nextWord) { score += 2 }
            let start = max(0, range.location - 56)
            let before = Prose.words(String(nsText.substring(with: NSRange(location: start, length: range.location - start)).suffix(14))).last ?? ""
            if ["en", "hacia", "desde", "bajo", "frente", "sobre"].contains(before) { score -= 2 }
            if before == "de" || before == "del" { score -= 1 }

            var candidate = candidates[key] ?? Candidate(name: hasHonorific ? raw : core, order: candidates.count)
            candidate.count += 1
            candidate.score += score
            if hasHonorific {
                candidate.name = raw.capitalizedFirst
                candidate.hasHonorific = true
            }
            // «Xuacu, el único superviviente del naufragio, …» → papel del personaje.
            if candidate.apposition.isEmpty,
               let match = appositionRole.firstMatch(in: after, options: .anchored, range: afterRange),
               let role = Range(match.range, in: after) {
                let value = after[role].trimmingCharacters(in: CharacterSet(charactersIn: ", ")).trimmed
                let first = Prose.words(value).first ?? ""
                if !["en", "a", "al", "de", "del", "con", "por", "para", "sin", "sobre", "tras", "que", "y", "o"].contains(first) {
                    candidate.apposition = value
                }
            }
            if candidate.firstSentence.isEmpty {
                candidate.firstSentence = Prose.sentences(nsText.substring(with: NSRange(location: max(0, range.location - 120), length: min(260, length - max(0, range.location - 120)))))
                    .first { Prose.fold($0).contains(key) } ?? ""
            }
            candidates[key] = candidate
        }

        var characters: [DraftCharacter] = []
        let ranked = candidates.values.sorted {
            ($0.score + $0.count, -$0.order) > ($1.score + $1.count, -$1.order)
        }
        for candidate in ranked {
            let key = Prose.fold(candidate.name)
            let words = Prose.words(candidate.name)
            var score = candidate.score
            if words.contains(where: { (personal[$0] ?? 0) > 0 }) || (personal[key] ?? 0) > 0 { score += 2 }
            if nonPersonal.contains(key) { score -= 2 }
            // Una sola mención sin tratamiento no basta: suele ser un lugar («Galicia, invierno de 1926»).
            guard candidate.count >= 2 || candidate.hasHonorific, score >= 3 else { continue }
            if let index = characters.firstIndex(where: { Prose.sameName($0.name, candidate.name) }) {
                characters[index].name = characters[index].name.longer(candidate.name)
                continue
            }
            var character = DraftCharacter(name: candidate.name)
            character.role = candidate.apposition.isEmpty
                ? candidate.firstSentence.truncated(words: 22)
                : candidate.apposition.capitalizedFirst
            if let stats = statsLine(for: candidate.name, in: appendix) { character.stats = stats }
            characters.append(character)
        }
        return Array(characters.prefix(14))
    }

    /// Palabras que van en mayúscula al empezar frase y no son nombres.
    static let commonCapitalized: Set<String> = [
        "la", "el", "los", "las", "un", "una", "si", "con", "en", "al", "a", "de", "del", "cada", "desde", "tras",
        "para", "cuando", "solo", "hace", "antes", "despues", "durante", "mientras", "pero", "y", "o", "no", "su",
        "sus", "este", "esta", "estos", "estas", "ese", "esa", "aqui", "alli", "entonces", "luego", "tambien",
        "todo", "todos", "nadie", "alguien", "algo", "hay", "ver", "verlos", "leer", "tocar", "con", "sin", "por",
        "que", "quien", "como", "donde", "pista", "escena", "acto", "parte", "duracion", "aventura", "gancho",
        "trasfondo", "desenlaces", "estadisticas", "recompensa", "fracaso", "lee", "leed", "nota", "ojo", "tirada",
        "mas", "menos", "muy", "ademas", "asi", "ya", "otro", "otra", "dos", "tres", "cien", "hasta",
        "les", "le", "lo", "nos", "os", "me", "te", "se", "ella", "ellas", "ellos", "usted", "ustedes",
    ]

    /// Términos de juego que van en mayúscula y no son personajes.
    static let excludedNames: Set<String> = Set((cthulhuSkills + dndSkills).map(Prose.fold)).union([
        "cordura", "pv", "cor", "pm", "profundo", "profundos", "primigenios", "mitos", "guardian", "master",
        "director de juego", "investigadores", "jugadores", "llamada de cthulhu", "cthulhu", "dungeons",
    ])

    /// Nombres que el reconocedor de Apple etiqueta como personas, y como lugares u organizaciones.
    /// Es lo más lento del análisis, así que el texto se reparte entre los núcleos en trozos que
    /// terminan en un final de frase (el reconocedor trabaja frase a frase).
    static func nameTags(in text: String, pieces count: Int? = nil) -> (personal: [String: Int], other: Set<String>) {
        let count = count ?? max(1, min(ProcessInfo.processInfo.activeProcessorCount, text.utf16.count / 12_000))
        let pieces = sentencePieces(of: text, count: count)
        var results = [(personal: [String: Int], other: Set<String>)](repeating: ([:], []), count: pieces.count)
        results.withUnsafeMutableBufferPointer { buffer in
            DispatchQueue.concurrentPerform(iterations: pieces.count) { index in
                let piece = pieces[index]
                var personal: [String: Int] = [:]
                var other: Set<String> = []
                let tagger = NLTagger(tagSchemes: [.nameType])
                tagger.string = piece
                tagger.setLanguage(.spanish, range: piece.startIndex..<piece.endIndex)
                tagger.enumerateTags(in: piece.startIndex..<piece.endIndex, unit: .word, scheme: .nameType,
                                     options: [.omitWhitespace, .omitPunctuation, .joinNames]) { tag, range in
                    let name = Prose.fold(String(piece[range]))
                    if tag == .personalName { personal[name, default: 0] += 1 }
                    if tag == .placeName || tag == .organizationName { other.insert(name) }
                    return true
                }
                buffer[index] = (personal, other)
            }
        }
        return results.reduce(into: ([:], [])) { total, part in
            total.personal.merge(part.personal, uniquingKeysWith: +)
            total.other.formUnion(part.other)
        }
    }

    /// Parte el texto en `count` trozos parecidos, cortando siempre en un final de frase: un
    /// espacio detrás de «.», «!», «?» o «…» que cierra una palabra de cuatro letras o más (así
    /// no se corta en «Sr. Rivas» ni en «Dra. Cueto»).
    static func sentencePieces(of text: String, count: Int) -> [String] {
        guard count > 1 else { return [text] }
        let target = text.utf8.count / count
        var pieces: [String] = []
        var start = text.startIndex
        var utf8Offset = 0
        var index = text.startIndex
        var previous: Character?
        var letters = 0
        var lettersBeforeMark = 0
        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            utf8Offset += character.utf8.count
            if character.isLetter {
                letters += 1
            } else {
                if let mark = character.unicodeScalars.first, ".!?…".unicodeScalars.contains(mark) { lettersBeforeMark = letters }
                letters = 0
            }
            if pieces.count < count - 1, utf8Offset >= target * (pieces.count + 1), character.isWhitespace,
               let previous, ".!?…".contains(previous), lettersBeforeMark >= 4 {
                pieces.append(String(text[start..<next]))
                start = next
            }
            previous = character
            index = next
        }
        pieces.append(String(text[start...]))
        return pieces
    }

    static func statsLine(for name: String, in appendix: String) -> String? {
        let key = Prose.words(name).last ?? ""
        return appendix.components(separatedBy: "\n").first { line in
            Prose.fold(line).contains(key) && line.range(of: #"\d"#, options: .regularExpression) != nil
        }?.trimmed
    }

    static func endings(in text: String) -> [AdventureGuide.Ending] {
        let items = text.components(separatedBy: "\n").map(\.trimmed).filter { $0.hasPrefix("-") || $0.hasPrefix("•") || $0.hasPrefix("*") }
        if items.isEmpty { return proseEndings(text) }
        return items.prefix(5).map { item in
            let clean = item.trimmingCharacters(in: CharacterSet(charactersIn: "-•* ")).trimmed
            let parts = clean.split(separator: ":", maxSplits: 1).map { String($0).trimmed }
            return AdventureGuide.Ending(
                title: parts.count == 2 ? parts[0].capitalizedFirst : clean.truncated(words: 5),
                condition: "",
                outcome: parts.count == 2 ? parts[1] : clean
            )
        }
    }

    /// Desenlaces en prosa: cada «Si…» empieza uno; lo que le sigue es su resultado.
    static func proseEndings(_ text: String) -> [AdventureGuide.Ending] {
        var endings: [AdventureGuide.Ending] = []
        for sentence in Prose.sentences(plain(text)) {
            let folded = Prose.fold(sentence)
            if folded.hasPrefix("si ") || folded.hasPrefix("cuando ") || folded.hasPrefix("en caso ") || endings.isEmpty {
                let parts = sentence.split(separator: ",", maxSplits: 1).map { String($0).trimmed }
                endings.append(AdventureGuide.Ending(
                    title: parts[0].truncated(words: 8).trimmingCharacters(in: CharacterSet(charactersIn: ".")),
                    condition: parts.count == 2 ? parts[0] : "",
                    outcome: parts.count == 2 ? parts[1].capitalizedFirst : sentence
                ))
            } else {
                endings[endings.count - 1].outcome = Prose.join(endings[endings.count - 1].outcome, sentence)
            }
        }
        return Array(endings.prefix(5))
    }

    // MARK: Consejos genéricos de dirección

    static func tips(for scene: DraftScene, system: GameSystem) -> [String] {
        var tips: [String] = []
        if !scene.readAloud.isEmpty {
            tips.append("Lee el texto despacio y termina con «¿Qué hacéis?»: deja que sean ellos quienes muevan la escena.")
        }
        if scene.clues.contains(where: \.isCore) {
            tips.append(system == .cthulhu
                ? "La pista clave nunca debe depender de una sola tirada: si fallan, dásela con un coste (tiempo, ruido, Cordura)."
                : "Si la información es imprescindible, que una tirada fallida cambie cómo la obtienen, no si la obtienen.")
        }
        if scene.checks.contains(where: { $0.skill == "Cordura" }) {
            tips.append("Describe lo que ven antes de pedir la tirada de Cordura; si pierden 5 o más de golpe, tirada de INT para la locura temporal.")
        }
        if !scene.danger.isEmpty {
            tips.append(system == .dnd
                ? "Antes del combate, describe el terreno: coberturas y alturas hacen la pelea más interesante."
                : "Avisa del peligro con señales antes de que golpee: el miedo funciona mejor anticipado.")
        }
        if tips.count < 2 {
            tips.append("Pregunta a cada jugador qué hace su personaje para que nadie se quede fuera de la escena.")
        }
        return tips
    }

    static func ifStuck(for scene: DraftScene) -> String {
        if let clue = scene.clues.first(where: \.isCore) ?? scene.clues.first {
            return "Haz que un PNJ o un detalle del entorno les lleve a «\(clue.title)»: no hace falta tirada si la información es necesaria."
        }
        return "Introduce un acontecimiento que les obligue a moverse: alguien llega, algo suena, el tiempo apremia."
    }

    static func prep(system: GameSystem, characters: [DraftCharacter], hasStats: Bool) -> [String] {
        var items = ["Lee el guion completo una vez y marca las pistas imprescindibles."]
        if !characters.isEmpty {
            items.append("Piensa una voz o un gesto para \(characters.prefix(3).map(\.name).joined(separator: ", ")).")
        }
        if hasStats { items.append("Ten a mano las estadísticas del apéndice para los encuentros.") }
        items.append(system == .cthulhu
            ? "Revisa las reglas de Cordura y de forzar tiradas."
            : "Revisa las fichas de los monstruos y la iniciativa.")
        return items
    }
}

extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
