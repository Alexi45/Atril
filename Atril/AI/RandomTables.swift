import Foundation

/// Tablas para improvisar en mesa, con una pulsación y sin conexión.
struct RandomTable: Identifiable, Hashable {
    var id: String { title }
    var title: String
    var symbol: String
    var entries: [String]

    func roll(_ random: (Int) -> Int = { Int.random(in: 0..<$0) }) -> String {
        entries[random(entries.count)]
    }
}

enum RandomTables {
    static func tables(for system: GameSystem) -> [RandomTable] {
        switch system {
        case .cthulhu: cthulhu + common
        case .dnd: dnd + common
        case .other:
            common + [RandomTable(title: "Nombre", symbol: "person.text.rectangle", entries: dndNames.entries + cthulhuNames.entries)]
        }
    }

    // MARK: Comunes

    static let common: [RandomTable] = [
        RandomTable(title: "Giro de la trama", symbol: "arrow.triangle.branch", entries: [
            "Un aliado resulta tener su propio plan.",
            "Alguien ha llegado antes y se ha llevado lo que buscaban.",
            "La persona a la que protegen no quiere ser protegida.",
            "Lo que parecía una amenaza es una víctima.",
            "Aparece un testigo que cuenta otra versión de los hechos.",
            "El objeto que buscan no es lo que creen.",
            "Un rival les ofrece un trato difícil de rechazar.",
            "Se acaba el tiempo antes de lo previsto.",
            "Un PNJ querido desaparece sin dejar rastro.",
            "Alguien del grupo es reconocido por quien no debería.",
            "La salida por la que entraron ya no existe.",
            "Una pista falsa ha sido colocada a propósito.",
        ]),
        RandomTable(title: "Tiempo y ambiente", symbol: "cloud.sun", entries: [
            "Niebla espesa que se traga los sonidos.",
            "Viento frío que apaga las luces.",
            "Lluvia fina y constante que lo empapa todo.",
            "Calor pegajoso, sin una brizna de aire.",
            "Silencio absoluto: ni un pájaro, ni un perro.",
            "Tormenta lejana que se va acercando.",
            "Luna llena, tan clara que casi no hacen falta lámparas.",
            "Primeras nieves: cada paso deja huella.",
        ]),
    ]

    // MARK: La llamada de Cthulhu

    static let cthulhuNames = RandomTable(title: "Nombre", symbol: "person.text.rectangle", entries: [
        "Amparo Lafuente", "Benito Sanjurjo", "Consuelo Riera", "Faustino Arce", "Herminia Galán", "Teodoro Villa",
        "Remedios Castro", "Eusebio Paredes", "Virtudes Montes", "Anselmo Quiroga", "Pilar Ordóñez", "Ramiro Salcedo",
        "Edith Calloway", "Silas Whitmore", "Agnes Thorne", "Walter Pike", "Mabel Hargrave", "Josiah Crane",
    ])

    static let cthulhu: [RandomTable] = [
        RandomTable(title: "Ataque de locura", symbol: "brain.head.profile", entries: [
            "Se queda paralizado, con la mirada fija en un punto.",
            "Huye a ciegas, sin mirar atrás ni atender a nadie.",
            "Ríe a carcajadas sin poder parar.",
            "Recita algo que no recuerda haber aprendido.",
            "Ataca lo que tiene más cerca, sin distinguir amigo de enemigo.",
            "Se acurruca en un rincón y llora.",
            "Se convence de que uno de sus compañeros es el culpable de todo.",
            "Repite la última frase que ha oído, una y otra vez.",
            "Se desmaya.",
            "Se tapa los oídos y grita para no oír algo que solo oye él.",
            "Intenta escribir o dibujar lo que ha visto, con lo que tenga a mano.",
            "Cree estar a salvo en otro lugar y actúa como si estuviera allí.",
        ]),
        RandomTable(title: "Fobia", symbol: "exclamationmark.bubble", entries: [
            "Al agua profunda.", "A los espejos.", "A la oscuridad.", "A los espacios cerrados.", "A los insectos.",
            "A los hospitales y las agujas.", "A los muñecos y maniquíes.", "A las multitudes.", "Al fuego.",
            "A las alturas.", "A los perros.", "Al sonido de las campanas.", "A los libros antiguos.",
            "A los reptiles.", "A la lluvia.", "A su propio reflejo.",
        ]),
        RandomTable(title: "Manía", symbol: "repeat", entries: [
            "Cuenta todo lo que ve.", "Se lava las manos sin parar.", "Lo apunta todo en un cuaderno.",
            "Enciende todas las luces que encuentra.", "Comprueba las cerraduras una y otra vez.",
            "Colecciona objetos que cree importantes.", "Habla con alguien que no está.",
            "Lleva siempre encima un amuleto improvisado.", "No da la espalda a ninguna puerta.",
            "Repite un gesto antes de cualquier acción.", "Desconfía de la comida que no ha preparado.",
            "Solo puede dormir con los ojos tapados.",
        ]),
        RandomTable(title: "Detalle inquietante", symbol: "eye", entries: [
            "Las huellas terminan en mitad del pasillo.",
            "Un reloj se ha parado a la hora exacta en que entraron.",
            "Alguien ha escrito sus nombres en el polvo.",
            "Un perro mira fijamente una pared y gruñe.",
            "Todas las fotografías de la casa miran al mismo punto.",
            "Huele a mar, aunque están lejos de la costa.",
            "Un niño canta una canción que nadie le ha enseñado.",
            "La puerta que cerraron está abierta.",
            "Hay un plato aún caliente en una casa abandonada.",
            "Una sombra tarda un instante de más en seguir a su dueño.",
            "Se oye respirar al otro lado de la pared.",
            "Los pájaros están todos mirando en la misma dirección.",
            "En el espejo, la habitación tiene una puerta más.",
            "La radio susurra entre interferencias algo parecido a un nombre.",
            "Alguien ha dado la vuelta a todos los cuadros.",
            "El agua del vaso tiembla, aunque nada se mueve.",
        ]),
        RandomTable(title: "Rumor del lugar", symbol: "bubble.left.and.bubble.right", entries: [
            "Dicen que el último que preguntó por eso se marchó sin su equipaje.",
            "Por las noches se ven luces donde no vive nadie.",
            "El médico firma demasiados certificados de defunción últimamente.",
            "Hay familias que ya no vienen a misa, y nadie pregunta por qué.",
            "Un forastero compró la casa vieja y paga en monedas antiguas.",
            "Los animales no quieren acercarse a cierto camino.",
            "Alguien ha estado preguntando por los personajes antes de que llegaran.",
            "Lo que encontraron los obreros está guardado bajo llave.",
            "Hace años pasó lo mismo, y todos prefieren no recordarlo.",
            "Hay una carta que nunca llegó a su destino, y alguien la busca.",
        ]),
        cthulhuNames,
    ]

    // MARK: Dungeons & Dragons

    static let dndNames = RandomTable(title: "Nombre", symbol: "person.text.rectangle", entries: [
        "Brenna Calderón", "Ostrik el Pardo", "Mirela Vane", "Tobías Piedrahueca", "Ysolda", "Garrick Tres Dedos",
        "Elowen Sauce", "Durgan Martillo", "Kaelith", "Fenn Ligero", "Morwen la Gris", "Bartolo Barril",
        "Sira Nocheclara", "Hodrik", "Lyra Espino", "Tamsin Cobre",
    ])

    static let dnd: [RandomTable] = [
        RandomTable(title: "Botín menor", symbol: "bag", entries: [
            "Una bolsa con monedas de varios reinos.",
            "Un anillo de plata con una inscripción gastada.",
            "Un mapa parcial, con una marca en tinta roja.",
            "Un frasco con una poción sin etiquetar.",
            "Una llave de hierro que no abre nada cercano.",
            "Una gema pequeña, tallada con torpeza.",
            "Una carta sellada dirigida a alguien importante.",
            "Un pergamino con un conjuro menor.",
            "Una daga fina con el emblema de una casa noble.",
            "Un cuaderno de viaje con la última página arrancada.",
            "Un amuleto que se calienta cerca de la magia.",
            "Un saquito de hierbas curativas.",
        ]),
        RandomTable(title: "Encuentro en el camino", symbol: "signpost.right", entries: [
            "Un mercader con la rueda rota que ofrece pagar por ayuda.",
            "Bandidos que cobran un «peaje» y prefieren no pelear.",
            "Un carro abandonado, con la comida aún caliente.",
            "Peregrinos que huyen de algo que no quieren nombrar.",
            "Un mensajero herido con una carta urgente.",
            "Un puente vigilado por alguien con mucho tiempo libre.",
            "Huellas enormes que cruzan el sendero.",
            "Una patrulla que busca a alguien que se parece a un personaje.",
            "Un bardo que conoce demasiado bien sus hazañas.",
            "Un animal herido con una flecha de factura extraña.",
            "Un altar en el camino con ofrendas recientes.",
            "Una niebla repentina que no aparece en ningún mapa.",
        ]),
        RandomTable(title: "Rumor de taberna", symbol: "bubble.left.and.bubble.right", entries: [
            "El señor de estas tierras lleva semanas sin dejarse ver.",
            "Han vuelto a abrir la mina cerrada, y paga el doble.",
            "Algo se ha llevado el ganado sin dejar sangre.",
            "Una compañía de aventureros entró en las ruinas y solo salió uno.",
            "El herrero forja de noche para un cliente que nadie conoce.",
            "Hay una recompensa por una cabeza que nadie quiere nombrar.",
            "Un dragón compró la deuda de la ciudad, o eso dicen.",
            "El templo cierra sus puertas al caer el sol, y no explica por qué.",
            "En el mercado venden mapas de un lugar que no existe.",
            "El río baja de otro color desde hace tres lunas.",
        ]),
        RandomTable(title: "Complicación", symbol: "exclamationmark.triangle", entries: [
            "Se oye un cuerno: vienen refuerzos.",
            "El suelo cede bajo uno de los personajes.",
            "Un civil queda atrapado en medio del peligro.",
            "Se apaga la única fuente de luz.",
            "El enemigo ofrece rendirse, pero no parece sincero.",
            "Alguien más quiere lo mismo y acaba de llegar.",
            "Empieza a salir humo: algo se ha prendido fuego.",
            "Un conjuro de protección se activa de repente.",
        ]),
        RandomTable(title: "Nombre de posada", symbol: "house", entries: [
            "El Ganso Tuerto", "La Última Vela", "El Barril Sin Fondo", "La Cabra Sabia", "El Descanso del Herrero",
            "Los Tres Cuervos", "La Rueda Rota", "El Grifo Dormido", "La Moneda Falsa", "El Farol del Puente",
        ]),
        RandomTable(title: "Rasgo de PNJ", symbol: "theatermasks", entries: [
            "Le falta un dedo y cuenta una historia distinta cada vez.",
            "Habla de sí en tercera persona.",
            "Colecciona botones y los ofrece como pago.",
            "Tutea a reyes y trata de usted a los perros.",
            "Siempre está comiendo algo.",
            "Silba cuando miente.",
            "Lleva un sombrero demasiado grande.",
            "Cita proverbios que se inventa sobre la marcha.",
            "Tiene miedo de los pájaros.",
            "Regatea hasta cuando le regalan algo.",
        ]),
        dndNames,
    ]
}

/// Enemigo que el guion describe con estadísticas («Profundo: FUE 70, … PV 13»).
struct EnemyCandidate: Hashable, Identifiable {
    var id: String { name }
    var name: String
    var stats: StatBlock
}

extension StatBlock {
    /// Busca en el guion las líneas con PV o puntos de golpe y saca de quién son.
    static func candidates(in script: String) -> [EnemyCandidate] {
        var found: [EnemyCandidate] = []
        let paragraphs = script.components(separatedBy: "\n").map(\.trimmed).filter { !$0.isEmpty }
        for (index, paragraph) in paragraphs.enumerated() where StatBlock.mentionsHitPoints(paragraph) {
            let text = paragraph.trimmingCharacters(in: CharacterSet(charactersIn: ">*-• "))
            let stats = StatBlock(parsing: text)
            guard stats.hp != nil else { continue }
            let name = enemyName(in: text) ?? (index > 0 ? previousName(paragraphs[index - 1]) : nil)
            guard let name, !found.contains(where: { Prose.fold($0.name) == Prose.fold(name) }) else { continue }
            found.append(EnemyCandidate(name: name, stats: stats))
        }
        return found
    }

    /// «Profundo: FUE 70…» → «Profundo»; también «Marina Rivas (PV 10)…».
    private static func enemyName(in text: String) -> String? {
        guard let end = text.firstIndex(where: { ":(,".contains($0) }) else { return nil }
        let name = String(text[..<end]).trimmed
        return isName(name) ? name : nil
    }

    /// En los bloques de D&D, el nombre va en su propia línea, antes de las estadísticas.
    private static func previousName(_ line: String) -> String? {
        let name = line.trimmingCharacters(in: CharacterSet(charactersIn: "#>*-• ")).trimmed
        return isName(name) ? name : nil
    }

    private static func isName(_ text: String) -> Bool {
        let words = text.split(separator: " ")
        guard (1...6).contains(words.count), text.first?.isUppercase == true else { return false }
        // Si empieza por una estadística, no es un nombre («FUE 70», «PV 13»).
        return text.filter(\.isNumber).isEmpty
    }
}
