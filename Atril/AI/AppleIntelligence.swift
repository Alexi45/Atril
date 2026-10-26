import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Qué IA integrada hay en este dispositivo. No necesita cuentas ni claves.
enum AppleAI {
    enum Tier: String {
        /// Modelo grande de Apple en su nube privada (iOS/macOS 27): más contexto y calidad.
        case cloud
        /// Modelo de Apple Intelligence en el propio dispositivo.
        case onDevice
    }

    struct Status: Equatable {
        var tiers: [Tier]
        /// Por qué no hay IA en el dispositivo, si no la hay.
        var unavailableReason: String?

        var best: Tier? { tiers.first }
    }

    static let allowCloudKey = "allowAppleCloud"

    /// La nube privada exige el permiso `com.apple.developer.private-cloud-compute`; sin él,
    /// FoundationModels cierra la app en iPadOS. Se activa compilando con `PCC_ENTITLED`
    /// una vez añadida la capacidad «Private Cloud Compute» con el equipo de desarrollo.
    static var cloudEntitled: Bool {
        #if PCC_ENTITLED
        true
        #else
        false
        #endif
    }

    static var allowsCloud: Bool {
        UserDefaults.standard.object(forKey: allowCloudKey) as? Bool ?? true
    }

    static var status: Status {
        var tiers: [Tier] = []
        var reason: String?
        #if canImport(FoundationModels)
        if cloudEntitled, #available(iOS 27.0, macOS 27.0, *), allowsCloud, PrivateCloudComputeLanguageModel().isAvailable {
            tiers.append(.cloud)
        }
        if #available(iOS 26.0, macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                tiers.append(.onDevice)
            case .unavailable(.appleIntelligenceNotEnabled):
                reason = "Activa Apple Intelligence en Ajustes del sistema para tener el tutor con IA."
            case .unavailable(.modelNotReady):
                reason = "El modelo de Apple Intelligence se está descargando. Vuelve a intentarlo en un rato."
            case .unavailable(.deviceNotEligible):
                reason = "Este dispositivo no es compatible con Apple Intelligence."
            case .unavailable:
                reason = "Apple Intelligence no está disponible ahora mismo."
            }
        } else {
            reason = "La IA integrada necesita iPadOS 26 o macOS 26."
        }
        #else
        reason = "La IA integrada necesita iPadOS 26 o macOS 26."
        #endif
        return Status(tiers: tiers, unavailableReason: tiers.isEmpty ? reason : nil)
    }

    /// Palabras por trozo para el análisis: el contexto del modelo local es de ~8.000 tokens
    /// (≈1,5 tokens por palabra en español) y hay que dejar sitio al esquema y a la respuesta.
    static func chunkWords(for tier: Tier) -> Int {
        tier == .cloud ? 7000 : 650
    }

    /// Pasajes del guion que acompañan cada pregunta al tutor.
    static func passageCount(for tier: Tier) -> Int {
        tier == .cloud ? 10 : 4
    }

    enum Failure: LocalizedError {
        case unavailable
        case contextTooLarge
        case guardrail
        case quota
        case other(String)

        var errorDescription: String? {
            switch self {
            case .unavailable: "La IA de Apple no está disponible en este dispositivo."
            case .contextTooLarge: "El texto es demasiado largo para la IA del dispositivo."
            case .guardrail: "La IA de Apple ha preferido no responder a este contenido."
            case .quota: "Se ha agotado la cuota de la nube privada de Apple por hoy. Se usará la IA del dispositivo."
            case .other(let message): message
            }
        }

        /// Clasifica los errores de FoundationModels sin depender de la versión del SDK
        /// (en iOS 27 cambiaron de tipo).
        static func classify(_ error: Error) -> Failure {
            if let failure = error as? Failure { return failure }
            let description = String(describing: error)
            let lowered = description.lowercased()
            if lowered.contains("contextwindow") || lowered.contains("contextsize") || lowered.contains("context size")
                || lowered.contains("context window") { return .contextTooLarge }
            if lowered.contains("guardrail") || lowered.contains("refusal") || lowered.contains("unsafe") { return .guardrail }
            if lowered.contains("quota") { return .quota }
            if lowered.contains("assetsunavailable") || lowered.contains("unavailable") { return .unavailable }
            return .other(error.localizedDescription)
        }
    }
}

#if canImport(FoundationModels)

// MARK: - Esquemas de generación guiada

@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "Lo que contiene un fragmento del guion de una aventura de rol")
struct ChunkExtraction {
    @Guide(description: "Resumen del fragmento en 2 o 3 frases, para el director de juego")
    var summary: String
    @Guide(description: "Escenas jugables que describe el fragmento, en orden. Vacío si el fragmento es solo trasfondo, reglas o estadísticas", .maximumCount(4))
    var scenes: [SceneExtraction]
    @Guide(description: "Personajes no jugadores que aparecen o se describen en el fragmento", .maximumCount(6))
    var characters: [CharacterExtraction]
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct SceneExtraction {
    @Guide(description: "Título breve de la escena")
    var title: String
    @Guide(description: "Lugar donde ocurre")
    var place: String
    @Guide(description: "Qué ocurre, explicado al director de juego en una o dos frases")
    var summary: String
    @Guide(description: "Texto para leer en voz alta a los jugadores, copiado del guion si existe (como mucho 80 palabras); si no, vacío")
    var readAloud: String
    @Guide(description: "Qué deben descubrir o conseguir los jugadores, en pocas palabras", .maximumCount(3))
    var goals: [String]
    @Guide(description: "Tiradas que pide el guion", .maximumCount(4))
    var checks: [CheckExtraction]
    @Guide(description: "Pistas o información que pueden descubrir los jugadores", .maximumCount(4))
    var clues: [ClueExtraction]
    @Guide(description: "Peligros, combates o pérdidas de Cordura o Puntos de Vida, en una frase. Vacío si no hay")
    var danger: String
    @Guide(description: "Consejos concretos y breves para dirigir bien esta escena", .maximumCount(2))
    var tips: [String]
    @Guide(description: "Qué hacer si los jugadores se atascan, sin depender de una tirada, en una frase")
    var ifStuck: String
    @Guide(description: "Nombres de los personajes no jugadores presentes", .maximumCount(6))
    var characterNames: [String]
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct CheckExtraction {
    @Guide(description: "Habilidad o característica")
    var skill: String
    @Guide(description: "Dificultad tal como la da el guion; vacío si no la da")
    var difficulty: String
    @Guide(description: "Qué se consigue con éxito o qué pasa si falla, en una frase")
    var purpose: String
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct ClueExtraction {
    @Guide(description: "Nombre corto de la pista")
    var title: String
    @Guide(description: "Qué revela, en una frase")
    var detail: String
    @Guide(description: "A qué lugar, personaje o conclusión lleva")
    var leadsTo: String
    @Guide(description: "true si sin ella no se puede avanzar")
    var isCore: Bool
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct CharacterExtraction {
    @Guide(description: "Nombre")
    var name: String
    @Guide(description: "Papel en la historia, en una línea")
    var role: String
    @Guide(description: "Aspecto y primera impresión, en pocas palabras")
    var look: String
    @Guide(description: "Qué quiere, en pocas palabras")
    var motivation: String
    @Guide(description: "Lo que oculta; vacío si nada")
    var secret: String
    @Guide(description: "Cómo interpretarlo en mesa: voz, gestos, forma de hablar, en una frase")
    var voice: String
    @Guide(description: "Estadísticas si el guion las da, abreviadas; vacío si no")
    var stats: String
}

@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "Ficha de dirección de una escena")
struct SceneEnrichment {
    @Guide(description: "Qué ocurre en la escena, explicado al director de juego en una o dos frases")
    var summary: String
    @Guide(description: "Lugar donde ocurre, en pocas palabras")
    var place: String
    @Guide(description: "Qué deben descubrir o conseguir los jugadores, en pocas palabras", .maximumCount(3))
    var goals: [String]
    @Guide(description: "Información concreta que los jugadores pueden descubrir aquí: un testimonio, un documento o un objeto. Solo las que dice el guion", .maximumCount(3))
    var clues: [SceneClue]
    @Guide(description: "Consejos prácticos para dirigir esta escena; cada uno empieza con un verbo y dice cómo y por qué", .maximumCount(2))
    var tips: [String]
    @Guide(description: "Qué hacer si los jugadores se atascan, sin depender de una tirada, en una frase")
    var ifStuck: String
}

private struct SceneClueDraft { var title: String; var detail: String }

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct SceneClue {
    @Guide(description: "Nombre corto y concreto de la pista, por ejemplo «Diario del farero» o «Relato de Xuacu»")
    var title: String
    @Guide(description: "Qué revela, en una frase")
    var detail: String
}

@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "Fichas de personajes no jugadores")
struct CastExtraction {
    @Guide(description: "Una ficha por cada personaje de la lista, con el mismo nombre", .maximumCount(3))
    var characters: [CharacterExtraction]
}

@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "Visión de conjunto de la aventura para el director de juego")
struct OverviewExtraction {
    @Guide(description: "De qué va la aventura, en 3 o 4 frases")
    var premise: String
    @Guide(description: "La verdad oculta: qué está pasando realmente y quién está detrás")
    var truth: String
    @Guide(description: "Cómo arrancar la partida y enganchar a los jugadores")
    var hook: String
    @Guide(description: "Tono y ambientación, y cómo conseguirlos en mesa")
    var tone: String
    @Guide(description: "Cosas que preparar antes de jugar", .maximumCount(5))
    var prep: [String]
    @Guide(description: "Desenlaces posibles", .maximumCount(4))
    var endings: [EndingExtraction]
    @Guide(description: "Las pistas sin las que no se puede terminar la aventura, copiadas de la lista. Como mucho cuatro", .maximumCount(4))
    var coreClues: [String]
    @Guide(description: "Conexiones entre escenas: a qué escena se puede pasar desde cada una", .maximumCount(16))
    var links: [LinkExtraction]
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct EndingExtraction {
    @Guide(description: "Nombre del desenlace")
    var title: String
    @Guide(description: "Cuándo ocurre")
    var condition: String
    @Guide(description: "Qué pasa y consecuencias")
    var outcome: String
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct LinkExtraction {
    @Guide(description: "Título de la escena de origen, copiado de la lista")
    var from: String
    @Guide(description: "Título de la escena de destino, copiado de la lista")
    var to: String
    @Guide(description: "Qué tiene que pasar para ir de una a otra")
    var condition: String
}

@available(iOS 26.0, macOS 26.0, *)
extension ChunkExtraction {
    func draft(act: String) -> DraftChunk {
        DraftChunk(
            summary: summary,
            scenes: scenes.map { scene in
                DraftScene(
                    title: Prose.isSchemaJunk(scene.title) ? (scene.place.isEmpty ? "Escena" : scene.place) : scene.title,
                    place: scene.place, summary: scene.summary, readAloud: scene.readAloud,
                    goals: scene.goals,
                    checks: scene.checks.map { .init(skill: $0.skill, difficulty: $0.difficulty, purpose: $0.purpose) },
                    clues: scene.clues.filter { !Prose.isSchemaJunk($0.title) }
                        .map { .init(title: $0.title, detail: $0.detail, leadsTo: $0.leadsTo, isCore: $0.isCore) },
                    danger: scene.danger, tips: scene.tips, ifStuck: scene.ifStuck, characterNames: scene.characterNames
                )
            },
            characters: characters.filter { !HeuristicAnalyzer.excludedNames.contains(Prose.fold($0.name)) }.map {
                DraftCharacter(name: $0.name, role: $0.role, look: $0.look, motivation: $0.motivation,
                               secret: $0.secret, voice: $0.voice, stats: $0.stats)
            },
            act: act
        )
    }
}

// MARK: - Sesiones

@available(iOS 26.0, macOS 26.0, *)
enum AppleSessions {
    static func make(_ tier: AppleAI.Tier, instructions: String) -> LanguageModelSession {
        if tier == .cloud, #available(iOS 27.0, macOS 27.0, *) {
            return LanguageModelSession(model: PrivateCloudComputeLanguageModel(), instructions: instructions)
        }
        return LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
    }

    static func prewarm(_ tier: AppleAI.Tier) {
        make(tier, instructions: AppleTutor.instructions(.cthulhu)).prewarm()
    }
}

// MARK: - Análisis por trozos

@available(iOS 26.0, macOS 26.0, *)
enum AppleAnalyzer {
    struct Progress: Sendable {
        var done: Int
        var total: Int
        var phase: String
    }

    static func enrichmentInstructions(_ system: GameSystem) -> String {
        instructions(system) + """
         Cada consejo debe ser propio de esta escena: nombra algo que aparezca en ella (un personaje, un \
        objeto, un lugar o una tirada), di qué hacer y para qué sirve. Evita consejos que valdrían para \
        cualquier escena.
        """
    }

    static func instructions(_ system: GameSystem) -> String {
        """
        Ayudas a directores de juego (el «máster») de juegos de rol de mesa como \(system.name). En estos \
        juegos los jugadores interpretan personajes y el máster narra la aventura siguiendo un guion. \
        Lees fragmentos de ese guion y extraes su estructura para que el máster la consulte en mesa. \
        Escribe siempre en español, con frases cortas. Sé fiel al texto: no inventes personajes, pistas \
        ni escenas. Solo puedes redactar tú los consejos y qué hacer si se atascan.
        """
    }

    /// Analiza el guion entero. Si tiene estructura (encabezados por escena), las escenas, el
    /// texto para leer y las tiradas salen de las heurísticas y la IA enriquece escena a escena,
    /// con respuestas cortas. Si no, la IA extrae la estructura trozo a trozo.
    static func analyze(
        title: String,
        script: String,
        system: GameSystem,
        tier: AppleAI.Tier,
        progress: @escaping @MainActor (Progress) -> Void
    ) async throws -> AdventureGuide {
        let basic = HeuristicAnalyzer.drafts(script: script, system: system)
        let longest = basic.bodies.map { $0.split(whereSeparator: \.isWhitespace).count }.max() ?? 0
        if basic.scenes.count >= 3 && longest <= 1500 {
            return try await enrich(basic, script: script, title: title, system: system, tier: tier, progress: progress)
        }
        return try await extractAll(title: title, script: script, system: system, tier: tier, progress: progress)
    }

    static func enrich(
        _ basic: HeuristicAnalyzer.Drafts,
        script: String,
        title: String,
        system: GameSystem,
        tier: AppleAI.Tier,
        progress: @escaping @MainActor (Progress) -> Void
    ) async throws -> AdventureGuide {
        // De uno en uno: con varios a la vez el modelo local mezcla sus datos.
        let castBatches = basic.characters.map { [$0] }
        let total = basic.scenes.count + castBatches.count + 1
        let names = basic.characters.map(\.name).joined(separator: ", ")
        var scenes = basic.scenes
        let wordLimit = tier == .cloud ? 3000 : 550
        // Lo que de verdad pasa en la aventura, para que los consejos apunten en la buena dirección.
        let background = basic.overview.truth.truncated(words: tier == .cloud ? 400 : 90)

        for index in scenes.indices {
            try Task.checkCancellation()
            guard var scene = scenes[index].scenes.first else { continue }
            await progress(Progress(done: index, total: total, phase: "Preparando «\(scene.title)» · escena \(index + 1) de \(scenes.count)"))
            let prompt = """
            Trasfondo de la aventura (solo para el máster): \(background.isEmpty ? "no se indica" : background)

            Escena «\(scene.title)» del guion:

            \(basic.bodies[index].truncated(words: wordLimit))

            Personajes de la aventura: \(names.isEmpty ? "no se conocen" : names).

            Prepara la ficha de dirección de esta escena.
            """
            do {
                let session = AppleSessions.make(tier, instructions: enrichmentInstructions(system))
                // Tope de respuesta: si el modelo entra en bucle, falla en segundos y no en minutos.
                let value = try await session.respond(to: prompt, generating: SceneEnrichment.self,
                                                      options: GenerationOptions(temperature: 0.2, maximumResponseTokens: 900)).content
                apply(value, to: &scene)
                scenes[index].scenes = [scene]
                scenes[index].summary = scene.summary
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                #if DEBUG
                print("   [\(tier.rawValue)] escena «\(scene.title)» falló: \(error)")
                #endif
                // La escena se queda con la versión básica.
            }
        }

        // El modelo pequeño repite a veces el mismo consejo en varias escenas: se queda en la primera.
        var seenTips = Set<String>()
        for index in scenes.indices {
            guard var scene = scenes[index].scenes.first else { continue }
            let unique = scene.tips.filter { seenTips.insert(Prose.fold($0)).inserted }
            scene.tips = unique.isEmpty ? Array(basic.scenes[index].scenes.first?.tips.prefix(1) ?? []) : unique
            scenes[index].scenes = [scene]
        }

        var characters = basic.characters
        for (batchIndex, batch) in castBatches.enumerated() {
            try Task.checkCancellation()
            await progress(Progress(done: scenes.count + batchIndex, total: total, phase: "Preparando las fichas de los PNJ"))
            for draft in try await cast(batch, script: script, system: system, tier: tier) {
                guard let position = characters.firstIndex(where: { Prose.sameName($0.name, draft.name) })
                    ?? (batch.count == 1 ? characters.firstIndex(of: batch[0]) : nil) else { continue }
                var character = characters[position]
                // El papel sacado de una aposición del guion («Xuacu, el único superviviente…») es más
                // fiable que el del modelo; solo se sustituye si es una frase larga de relleno.
                let roleIsWeak = character.role.split(separator: " ").count > 10 || character.role.isEmpty
                if roleIsWeak, !Prose.useful(draft.role).isEmpty { character.role = draft.role }
                character.look = character.look.longer(Prose.useful(draft.look))
                character.motivation = character.motivation.longer(Prose.useful(draft.motivation))
                character.secret = character.secret.longer(Prose.useful(draft.secret))
                character.voice = character.voice.longer(Prose.useful(draft.voice))
                characters[position] = character
            }
        }

        try Task.checkCancellation()
        await progress(Progress(done: total - 1, total: total, phase: "Preparando el resumen y los desenlaces"))
        let drafts = scenes + [DraftChunk(characters: characters)]
        let preliminary = GuideMerger.merge(chunks: drafts, overview: basic.overview, system: system)
        var (overview, links) = await self.overview(title: title, drafts: drafts, guide: preliminary, system: system,
                                                    tier: tier, background: background)
        // El texto del propio guion es más fiable que su paráfrasis: la IA solo rellena lo que falte.
        let original = basic.overview
        if !original.truth.trimmed.isEmpty { overview.truth = original.truth }
        if !original.hook.trimmed.isEmpty { overview.hook = original.hook }
        if !original.premise.trimmed.isEmpty { overview.premise = original.premise }
        if !original.endings.isEmpty { overview.endings = original.endings }
        overview.prep = Array((overview.prep + original.prep).cleaned.prefix(6))
        await progress(Progress(done: total, total: total, phase: "Guía lista"))
        return GuideMerger.merge(chunks: drafts, overview: overview, links: links, system: system)
    }

    /// Para guiones sin estructura: un paso por trozo y un paso final de conjunto.
    static func extractAll(
        title: String,
        script: String,
        system: GameSystem,
        tier: AppleAI.Tier,
        progress: @escaping @MainActor (Progress) -> Void
    ) async throws -> AdventureGuide {
        let pieces = ScriptChunker.chunks(script, maxWords: AppleAI.chunkWords(for: tier))
        let total = pieces.count + 1
        var drafts: [DraftChunk] = []

        for (index, piece) in pieces.enumerated() {
            try Task.checkCancellation()
            await progress(Progress(done: index, total: total, phase: "Leyendo el guion · parte \(index + 1) de \(pieces.count)"))
            drafts += try await extract(piece, system: system, tier: tier)
        }

        try Task.checkCancellation()
        await progress(Progress(done: pieces.count, total: total, phase: "Uniendo escenas, PNJ y pistas"))
        let preliminary = GuideMerger.merge(chunks: drafts, overview: DraftOverview(), system: system)
        let (overview, links) = await self.overview(title: title, drafts: drafts, guide: preliminary, system: system, tier: tier)
        await progress(Progress(done: total, total: total, phase: "Guía lista"))
        return GuideMerger.merge(chunks: drafts, overview: overview, links: links, system: system)
    }

    /// Mezcla la ficha de la IA con la escena básica. Los PNJ presentes los decide el texto
    /// (el modelo tiende a repetir la lista completa) y la marca de «clave» la visión de conjunto.
    static func apply(_ value: SceneEnrichment, to scene: inout DraftScene) {
        if !Prose.useful(value.summary).isEmpty { scene.summary = value.summary }
        // Un lugar que repite el título de la escena no aporta nada.
        if !Prose.useful(value.place).isEmpty, !Prose.matches(value.place, scene.title),
           Prose.fold(value.place) != Prose.fold(scene.title) { scene.place = value.place }
        let goals = value.goals.map(Prose.useful).cleaned
        if !goals.isEmpty { scene.goals = goals }
        let clues = value.clues
            .map { SceneClueDraft(title: Prose.cleanLabel($0.title), detail: $0.detail.trimmed) }
            .filter { !Prose.isSchemaJunk($0.title) && $0.title.count > 3 && $0.detail.split(separator: " ").count >= 4 }
            .map { DraftClue(title: $0.title, detail: $0.detail) }
        let explicit = scene.clues.filter(\.isCore)
        if !clues.isEmpty { scene.clues = explicit + clues.filter { clue in !explicit.contains { Prose.matches($0.title, clue.title) } } }
        // Un consejo de dos o tres palabras («Observar el canto») no ayuda en mesa.
        let tips = value.tips.map(Prose.useful).filter { $0.split(separator: " ").count >= 5 }
        scene.tips = (tips + scene.tips.suffix(1)).cleaned
        if !Prose.useful(value.ifStuck).isEmpty { scene.ifStuck = value.ifStuck }
    }

    /// Fichas de un lote de PNJ, con solo las frases del guion que los nombran.
    /// Si el lote desborda el contexto, se parte en dos.
    private static func cast(_ batch: [DraftCharacter], script: String, system: GameSystem, tier: AppleAI.Tier) async throws -> [CharacterExtraction] {
        let text = HeuristicAnalyzer.plain(script)
        let context = batch.map { character in
            let sentences = Prose.sentences(mentioning: character.name, in: text, limit: tier == .cloud ? 12 : 6)
            return "- \(character.name): \(sentences.joined(separator: " ").truncated(words: tier == .cloud ? 300 : 110))"
        }.joined(separator: "\n")
        let prompt = """
        Lo que dice el guion de \(batch.count == 1 ? "este personaje no jugador" : "estos personajes no jugadores"):

        \(context)

        Prepara la ficha de \(batch.count == 1 ? "\(batch[0].name)" : "cada uno, con su mismo nombre"): papel, aspecto, \
        qué quiere, qué oculta y cómo interpretarlo en mesa. Usa solo lo que dicen estas frases sobre \
        \(batch.count == 1 ? "él o ella" : "cada uno").
        """
        do {
            let session = AppleSessions.make(tier, instructions: instructions(system))
            return try await session.respond(to: prompt, generating: CastExtraction.self,
                                             options: GenerationOptions(temperature: 0.3, maximumResponseTokens: 220 * batch.count + 200)).content.characters
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            #if DEBUG
            print("   [\(tier.rawValue)] fichas de \(batch.map(\.name)) fallaron: \(error)")
            #endif
            guard case .contextTooLarge = AppleAI.Failure.classify(error), batch.count > 1 else { return [] }
            let half = batch.count / 2
            return try await cast(Array(batch[..<half]), script: script, system: system, tier: tier)
                + cast(Array(batch[half...]), script: script, system: system, tier: tier)
        }
    }

    private static func extract(_ chunk: ScriptChunker.Chunk, system: GameSystem, tier: AppleAI.Tier) async throws -> [DraftChunk] {
        let session = AppleSessions.make(tier, instructions: instructions(system))
        let prompt = """
        Fragmento del guion:

        \(chunk.text)

        Extrae las escenas jugables y los personajes de este fragmento.
        """
        do {
            let response = try await session.respond(
                to: prompt, generating: ChunkExtraction.self,
                options: GenerationOptions(temperature: 0.2)
            )
            return [response.content.draft(act: chunk.part)]
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            #if DEBUG
            print("   [\(tier.rawValue)] trozo de \(chunk.text.split(whereSeparator: \.isWhitespace).count) palabras falló: \(error)")
            #endif
            switch AppleAI.Failure.classify(error) {
            case .contextTooLarge where chunk.text.split(whereSeparator: \.isWhitespace).count > 300:
                // Se parte por la mitad y se vuelve a intentar.
                let halves = ScriptChunker.chunks(chunk.text, maxWords: chunk.text.split(whereSeparator: \.isWhitespace).count / 2 + 1)
                var result: [DraftChunk] = []
                for half in halves {
                    result += try await extract(ScriptChunker.Chunk(text: half.text, part: chunk.part), system: system, tier: tier)
                }
                return result
            case .quota where tier == .cloud:
                return try await extract(chunk, system: system, tier: .onDevice)
            default:
                return [fallback(chunk, system: system)]
            }
        }
    }

    /// El trozo que la IA no pudo leer se organiza con heurísticas.
    private static func fallback(_ chunk: ScriptChunker.Chunk, system: GameSystem) -> DraftChunk {
        let guide = HeuristicAnalyzer.analyze(script: chunk.text, system: system)
        return DraftChunk(
            summary: guide.premise,
            scenes: guide.scenes.map { scene in
                DraftScene(
                    title: scene.title, place: scene.place, summary: scene.summary, readAloud: scene.readAloud,
                    goals: scene.goals, checks: scene.checks,
                    clues: guide.clues(in: scene).map { DraftClue(title: $0.title, detail: $0.detail, leadsTo: $0.leadsTo, isCore: $0.isCore) },
                    danger: scene.danger, tips: scene.tips, ifStuck: scene.ifStuck,
                    characterNames: scene.npcIDs.compactMap { guide.npc($0)?.name }
                )
            },
            characters: guide.npcs.map { DraftCharacter(name: $0.name, role: $0.role, stats: $0.stats) },
            act: chunk.part
        )
    }

    private static func overview(
        title: String, drafts: [DraftChunk], guide: AdventureGuide, system: GameSystem, tier: AppleAI.Tier,
        background: String = ""
    ) async -> (DraftOverview, [DraftLink]) {
        let budget = tier == .cloud ? 4000 : 900
        let summaries = drafts.map(\.summary).filter { !$0.isEmpty }.joined(separator: "\n").truncated(words: budget / 2)
        let scenes = guide.scenes.map { "- \($0.title): \($0.summary.truncated(words: tier == .cloud ? 40 : 18))" }
            .joined(separator: "\n").truncated(words: budget / 3)
        let clues = guide.clues.map { "- \($0.title)" }.joined(separator: "\n").truncated(words: budget / 8)
        let characters = guide.npcs.map { "- \($0.name): \($0.role)" }.joined(separator: "\n").truncated(words: budget / 8)
        let prompt = """
        Aventura: \(title)
        \(background.isEmpty ? "" : "\nTrasfondo (texto del guion): \(background)\n")
        Resumen por partes:
        \(summaries)

        Escenas:
        \(scenes)

        Pistas:
        \(clues)

        Personajes:
        \(characters)

        Prepara la visión de conjunto de la aventura para el máster.
        """
        let session = AppleSessions.make(tier, instructions: instructions(system))
        do {
            let response = try await session.respond(to: prompt, generating: OverviewExtraction.self,
                                                     options: GenerationOptions(temperature: 0.3))
            let value = response.content
            let overview = DraftOverview(
                premise: value.premise, truth: value.truth, hook: value.hook, tone: value.tone, prep: value.prep,
                endings: value.endings.map { .init(title: $0.title, condition: $0.condition, outcome: $0.outcome) },
                coreClues: value.coreClues
            )
            return (overview, value.links.map { DraftLink(from: $0.from, to: $0.to, condition: $0.condition) })
        } catch {
            #if DEBUG
            print("   [\(tier.rawValue)] visión de conjunto falló: \(error)")
            #endif
            let basic = HeuristicAnalyzer.analyze(script: summaries, system: system)
            return (DraftOverview(premise: basic.premise, prep: basic.prep), [])
        }
    }
}

// MARK: - Tutor en mesa

@available(iOS 26.0, macOS 26.0, *)
enum AppleTutor {
    static func instructions(_ system: GameSystem) -> String {
        """
        Eres el tutor de un director de juego (el «máster») que dirige ahora mismo una partida de rol de \
        mesa de \(system.name). Los jugadores interpretan a sus personajes; el máster narra y arbitra. \
        Aconsejas al máster qué hacer a continuación, apoyándote en el guion y en el estado de la partida. \
        Háblale de tú al máster, no a los jugadores. \
        Responde en español, en menos de 130 palabras, con viñetas breves y lo más importante primero. \
        Puedes revelar al máster los secretos del guion. Básate en los fragmentos del guion que se te dan; \
        si el guion no dice algo, improvisa algo coherente con la aventura y di que es improvisado. \
        No termines con preguntas: da directamente el consejo.
        """
    }

    /// Responde en streaming; cada elemento es el texto acumulado hasta el momento.
    static func answer(prompt: String, system: GameSystem, tier: AppleAI.Tier) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let session = AppleSessions.make(tier, instructions: instructions(system))
                    let stream = session.streamResponse(to: prompt, options: GenerationOptions(temperature: 0.6))
                    for try await snapshot in stream {
                        continuation.yield(snapshot.content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: AppleAI.Failure.classify(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

#endif
