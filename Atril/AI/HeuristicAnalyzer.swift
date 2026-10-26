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

    static func drafts(script: String, system: GameSystem) -> Drafts {
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
        for index in chunks.indices {
            guard var scene = chunks[index].scenes.first else { continue }
            let text = Prose.fold(scene.title + " " + scene.readAloud + " " + bodies[index])
            scene.characterNames = characters.filter { character in
                let name = Prose.words(character.name).filter { $0.count > 3 }
                return !name.isEmpty && name.contains { text.contains($0) }
            }.map(\.name)
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
            } else if readNext, !text.isEmpty {
                readAloud.append(text)
                readNext = false
            } else {
                let folded = Prose.fold(text)
                if folded.hasPrefix("lee en voz alta") || folded.hasPrefix("leed en voz alta") || folded.hasPrefix("para leer") {
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
        let sentences = Prose.sentences(prose)
        scene.summary = sentences.prefix(3).joined(separator: " ")
        scene.place = place(in: scene.readAloud + " " + prose) ?? ""
        scene.checks = checks(in: body, system: system)
        scene.clues = clues(in: body)
        scene.danger = danger(in: body, system: system)
        scene.goals = scene.clues.prefix(3).map { "Descubrir: \($0.title.lowercased())" }
        scene.tips = tips(for: scene, system: system)
        scene.ifStuck = ifStuck(for: scene)
        return scene
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

    static func place(in text: String) -> String? {
        let pattern = #"\b(en|hacia|desde)\s+(el|la|los|las)\s+((?:[\p{Lu}][\p{L}]+\s?){1,3})"#
        guard let match = text.range(of: pattern, options: .regularExpression) else { return nil }
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

    static func checks(in text: String, system: GameSystem) -> [AdventureGuide.Check] {
        let skills = system == .dnd ? dndSkills : (system == .cthulhu ? cthulhuSkills : cthulhuSkills + dndSkills)
        var result: [AdventureGuide.Check] = []
        for sentence in Prose.sentences(plain(text)) {
            let folded = Prose.fold(sentence)
            let mentionsRoll = folded.contains("tirada") || folded.contains("prueba") || folded.contains("salvacion")
                || folded.contains("dificil") || folded.contains("extrem") || sentence.range(of: #"\bCD\s*\d+"#, options: .regularExpression) != nil
            guard mentionsRoll else { continue }
            for skill in skills {
                let key = Prose.fold(skill)
                let isAbbreviation = skill.count <= 3
                let found = isAbbreviation
                    ? sentence.range(of: "\\b\(skill)\\b", options: .regularExpression) != nil
                    : folded.range(of: "\\b\(key)\\b", options: .regularExpression) != nil
                guard found, !result.contains(where: { $0.skill == skill }) else { continue }
                result.append(AdventureGuide.Check(skill: skill, difficulty: difficulty(in: sentence), purpose: sentence.truncated(words: 30)))
            }
        }
        // Pérdidas de Cordura: «cuesta 1/1D4 de Cordura», «0/1D6 COR».
        let sanity = #"(\d+D?\d*/\d+D\d+(\s*\+\s*\d+)?|\d+/\d+)\s*(puntos\s*)?(de\s*)?(Cordura|COR)"#
        for sentence in Prose.sentences(plain(text)) {
            guard let range = sentence.range(of: sanity, options: [.regularExpression, .caseInsensitive]) else { continue }
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
        var result: [DraftClue] = []
        for sentence in Prose.sentences(plain(text)) {
            let folded = Prose.fold(sentence)
            let isClue = folded.hasPrefix("pista") || folded.contains(" pista") || folded.contains("encuentran")
                || folded.contains("descubren") || folded.contains("revela") || folded.contains("averiguan")
                || folded.contains("registro") || folded.contains("diario") || folded.contains("carta")
            guard isClue, sentence.count > 25 else { continue }
            let detail = sentence.replacingOccurrences(of: #"^Pista\s*(clave)?\s*:\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
            result.append(DraftClue(
                title: clueTitle(detail),
                detail: detail.truncated(words: 40),
                isCore: folded.contains("clave") || folded.contains("imprescindible") || folded.contains("esencial")
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

    static func danger(in text: String, system: GameSystem) -> String {
        let keys = ["ataca", "combate", "pierde", "daño", "muere", "muerte", "herid", "PV", "veneno", "trampa", "cordura"]
        let sentences = Prose.sentences(plain(text)).filter { sentence in
            let folded = Prose.fold(sentence)
            return keys.contains { folded.contains(Prose.fold($0)) }
        }
        return sentences.prefix(2).joined(separator: " ")
    }

    /// Personajes: el reconocedor de nombres de Apple acierta poco en guiones largos en español
    /// (toma «Marina Rivas» por un lugar), así que se combina con señales del propio texto.
    static func characters(in script: String, appendix: String) -> [DraftCharacter] {
        let text = plain(script)
        var personal: [String: Int] = [:]
        var nonPersonal: Set<String> = []
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        tagger.setLanguage(.spanish, range: text.startIndex..<text.endIndex)
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType,
                             options: [.omitWhitespace, .omitPunctuation, .joinNames]) { tag, range in
            let name = Prose.fold(String(text[range]))
            if tag == .personalName { personal[name, default: 0] += 1 }
            if tag == .placeName || tag == .organizationName { nonPersonal.insert(name) }
            return true
        }

        struct Candidate { var name: String; var count = 0; var score = 0; var firstSentence = ""; var apposition = "" }
        var candidates: [String: Candidate] = [:]
        let pattern = #"(?:\b(?:don|doña|padre|madre|doctora?|señora?|señorita|fray|sor|capitán|inspectora?|profesora?|tío|tía)\s+)?\p{Lu}\p{Ll}+(?:\s+(?:de\s+)?\p{Lu}\p{Ll}+){0,2}"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let nsText = text as NSString
        let speech = ["dice", "dicen", "cuenta", "explica", "grita", "habla", "responde", "sabe", "quiere", "esta",
                      "intenta", "mira", "recibe", "oculta", "miente", "teme", "busca", "pide", "niega", "confiesa"]
        regex?.enumerateMatches(in: text, range: NSRange(location: 0, length: nsText.length)) { match, _, _ in
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
            let after = nsText.substring(from: range.location + range.length).prefix(110)
            if after.range(of: #"^\s*,\s*(el|la|un|una|su)?\s*\p{Ll}+"#, options: .regularExpression) != nil { score += 2 }
            let nextWord = Prose.words(String(after)).first ?? ""
            if speech.contains(nextWord) { score += 2 }
            let before = Prose.words(nsText.substring(to: range.location).suffix(14).description).last ?? ""
            if ["en", "hacia", "desde", "bajo", "frente", "sobre"].contains(before) { score -= 2 }
            if before == "de" || before == "del" { score -= 1 }

            var candidate = candidates[key] ?? Candidate(name: hasHonorific ? raw : core)
            candidate.count += 1
            candidate.score += score
            if hasHonorific { candidate.name = raw.capitalizedFirst }
            // «Xuacu, el único superviviente del naufragio, …» → papel del personaje.
            if candidate.apposition.isEmpty,
               let role = after.range(of: #"^\s*,\s*(el|la|un|una|su)?\s*[^,.;:()]{3,90}(?=[,.;:])"#, options: .regularExpression) {
                let value = after[role].trimmingCharacters(in: CharacterSet(charactersIn: ", ")).trimmed
                let first = Prose.words(value).first ?? ""
                if !["en", "a", "al", "de", "del", "con", "por", "para", "sin", "sobre", "tras", "que", "y", "o"].contains(first) {
                    candidate.apposition = value
                }
            }
            if candidate.firstSentence.isEmpty {
                candidate.firstSentence = Prose.sentences(nsText.substring(with: NSRange(location: max(0, range.location - 120), length: min(260, nsText.length - max(0, range.location - 120)))))
                    .first { Prose.fold($0).contains(key) } ?? ""
            }
            candidates[key] = candidate
        }

        var characters: [DraftCharacter] = []
        let ranked = candidates.values.sorted { $0.score + $0.count > $1.score + $1.count }
        for candidate in ranked {
            let key = Prose.fold(candidate.name)
            let words = Prose.words(candidate.name)
            var score = candidate.score
            if words.contains(where: { (personal[$0] ?? 0) > 0 }) || (personal[key] ?? 0) > 0 { score += 2 }
            if nonPersonal.contains(key) { score -= 2 }
            guard candidate.count >= 2 || score >= 3, score >= 3 else { continue }
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
    ]

    /// Términos de juego que van en mayúscula y no son personajes.
    static var excludedNames: Set<String> {
        Set((cthulhuSkills + dndSkills).map(Prose.fold)).union([
            "cordura", "pv", "cor", "pm", "profundo", "profundos", "primigenios", "mitos", "guardian", "master",
            "director de juego", "investigadores", "jugadores", "llamada de cthulhu", "cthulhu", "dungeons",
        ])
    }

    static func statsLine(for name: String, in appendix: String) -> String? {
        let key = Prose.words(name).last ?? ""
        return appendix.components(separatedBy: "\n").first { line in
            Prose.fold(line).contains(key) && line.range(of: #"\d"#, options: .regularExpression) != nil
        }?.trimmed
    }

    static func endings(in text: String) -> [AdventureGuide.Ending] {
        let items = text.components(separatedBy: "\n").map(\.trimmed).filter { $0.hasPrefix("-") || $0.hasPrefix("•") || $0.hasPrefix("*") }
        let source = items.isEmpty ? Prose.sentences(plain(text)) : items
        return source.prefix(5).map { item in
            let clean = item.trimmingCharacters(in: CharacterSet(charactersIn: "-•* ")).trimmed
            let parts = clean.split(separator: ":", maxSplits: 1).map { String($0).trimmed }
            return AdventureGuide.Ending(
                title: parts.count == 2 ? parts[0].capitalizedFirst : clean.truncated(words: 5),
                condition: "",
                outcome: parts.count == 2 ? parts[1] : clean
            )
        }
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
