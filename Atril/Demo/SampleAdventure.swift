import Foundation
import SwiftData

/// Aventura corta original para probar la app sin clave: guion, guía ya preparada y,
/// opcionalmente, una sesión a medias.
enum SampleAdventure {
    static let title = "La luz de Punta Negra"

    @discardableResult
    static func make(in context: ModelContext, withSession: Bool) -> Adventure {
        let adventure = Adventure(title: title, system: .cthulhu, script: script, sourceFileName: "punta-negra.md")
        adventure.guide = guide
        adventure.guideEngine = "sample"
        context.insert(adventure)

        if withSession {
            let session = PlaySession(number: 1, adventure: adventure)
            session.currentSceneID = "e4"
            session.visitedSceneIDs = ["e1", "e2", "e4"]
            session.foundClueIDs = ["p1", "p2"]
            session.elapsed = 63 * 60
            session.players = [
                Player(name: "Ana", character: "Lucía Ferrer", hp: 10, hpMax: 11, sanity: 52, sanityMax: 99, notes: "periodista"),
                Player(name: "Dani", character: "Tomás Llano", hp: 9, hpMax: 9, sanity: 61, sanityMax: 99, notes: "profesor de antropología"),
                Player(name: "Rober", character: "Casimiro Vega", hp: 13, hpMax: 13, sanity: 44, sanityMax: 99, notes: "expolicía"),
            ]
            session.notes = [
                SessionNote(playTime: 4 * 60, sceneID: "e1", text: "Llegan en el coche de línea de Oviedo. Elvira les espera en la plaza."),
                SessionNote(playTime: 22 * 60, sceneID: "e2", text: "Xuacu les cuenta lo de las luces bajo el agua. Lucía le ha invitado a orujo."),
                SessionNote(playTime: 31 * 60, sceneID: "e2", text: "Descubren la pista: Marina camina hacia el mar"),
                SessionNote(playTime: 48 * 60, sceneID: "e4", text: "No pasan por la parroquia: van directos al faro. Marina les abre, muy fría."),
            ]
            let question = "No han pasado por la parroquia y ya están en el faro con Marina. ¿Qué hago ahora?"
            let answer = """
            **Ahora**
            - Que Marina no les deje subir: «Padre está enfermo, no recibe a nadie». Es amable pero no se aparta de la escalera.
            - Si insisten, se oye un golpe arriba y una voz ronca que grita «¡La luz!». Eso los engancha sin necesidad de forzar nada.

            **Tirada**
            - Psicología (Normal) para notar que Marina no parpadea y tiene la piel húmeda aunque no llueve.

            **Ojo**
            - Sin el registro de 1824 no sabrán qué significa el signo del cristal. Cuando lo vean, deja que Tomás haga Antropología o Historia: con éxito recuerda «algo parecido en la iglesia del pueblo». Así vuelven a la parroquia por iniciativa propia.
            """
            session.chat = [
                TutorMessage(role: .user, display: question, content: .string(question)),
                TutorMessage(role: .assistant, display: answer, content: [["type": "text", "text": .string(answer)]]),
            ]
            context.insert(session)
        }
        return adventure
    }

    static let script = """
    # La luz de Punta Negra

    Aventura corta para La llamada de Cthulhu (7.ª edición) para 2-4 investigadores. Asturias, octubre de 1924. Duración estimada: una sesión de 3-4 horas.

    ## Trasfondo para el guardián

    En 1824, tras un invierno de naufragios, el farero Bernardo Rivas encontró en las cuevas bajo Punta Negra una piedra verdosa tallada con un signo que no era de este mundo. Cada pleamar viva, la piedra cantaba, y algo respondía desde el fondo. El párroco de entonces, don Baltasar, descubrió que la luz del faro los mantenía lejos y mandó grabar el mismo signo, invertido, en la lente. Desde entonces la luz no solo guía a los barcos: aleja a los que esperan bajo la marea.

    Cien años después, Marina Rivas, bisnieta de Bernardo, ha empezado a oír el canto. En su sangre hay algo de ellos. Hace tres noches desmontó el engranaje de la lente y encerró a su padre, Anselmo, en la cámara de la linterna. La próxima pleamar viva es dentro de dos noches. Si la luz no vuelve a girar, los Profundos subirán a Portuxe y se llevarán a Marina con ellos… y a quien encuentren por el camino.

    ## Gancho

    La doctora Elvira Cueto, médica de Portuxe y antigua compañera de uno de los investigadores, les escribe pidiendo ayuda: un pesquero ha naufragado frente a Punta Negra, el faro lleva tres noches apagado y nadie del pueblo se atreve a subir. «Aquí todos tienen miedo de algo que no saben nombrar.»

    ## 1. Llegada a Portuxe

    > El coche de línea os deja en una plaza que huele a salitre y a leña mojada. Las casas, de piedra oscura, se aprietan unas contra otras como si temieran al mar. Al fondo, sobre el acantilado, el faro de Punta Negra se recorta apagado contra un cielo de color pizarra.

    Elvira los recibe y los lleva a su consulta. Les cuenta que Xuacu, el único superviviente del naufragio, delira sobre «luces debajo del agua». Les ofrece alojamiento en la fonda de la taberna.

    Pista: el relato de Elvira sobre el naufragio y las luces bajo el agua (lleva a hablar con Xuacu en la taberna).

    ## 2. La taberna de la Remedios

    > Humo de pipa, redes colgadas de las vigas y una docena de hombres que dejan de hablar cuando entráis. Detrás de la barra, una mujer enorme seca vasos sin quitaros la vista de encima.

    Remedios, la tabernera, es desconfiada pero se ablanda con una buena propina o con Encanto. Xuacu está en un rincón, temblando. Si le invitan a beber y superan una tirada de Persuasión, cuenta que antes de hundirse vio «faroles verdes que subían del fondo» y una cara pálida en el agua. Ver a Xuacu revivir el naufragio cuesta 0/1 de Cordura.

    Remedios, con una tirada de Charlatanería o Encanto, cuenta que Marina, la hija del farero, ha bajado a la playa tres noches seguidas y se ha metido en el mar vestida, «como si la llamaran».

    ## 3. La parroquia de San Telmo

    > La iglesia es pequeña y fría. Un exvoto con forma de barco cuelga sobre el altar, y a su lado alguien ha pintado, hace mucho tiempo, un signo extraño en la piedra.

    Don Ramiro, el párroco, es un hombre mayor y asustado. Si los investigadores mencionan el signo o el faro, les deja ver el archivo. Con una tirada de Buscar libros (Difícil) encuentran el registro de don Baltasar de 1824: «La luz los mantiene lejos. Mientras el signo gire en el cristal, el mar no subirá a por nosotros». Leer el registro completo cuesta 1/1D4 de Cordura y permite reconocer el signo de la lente.

    ## 4. El faro de Punta Negra

    > El camino del acantilado termina en una casa encalada pegada a la torre. El viento silba entre las rocas. La puerta se abre antes de que llaméis: una joven pálida, de ojos muy grandes, os mira sin parpadear.

    Marina dice que su padre está enfermo y no puede recibir a nadie. Con Psicología se nota que miente y que tiene la piel húmeda aunque no llueve. Si los investigadores fuerzan la situación o suben, encuentran a Anselmo encerrado en la cámara de la linterna, deshidratado y medio loco, repitiendo «la luz, la luz».

    En la cámara de la linterna ven el engranaje desmontado y la lente con un signo grabado, el mismo de la iglesia. Una tirada de Mecánica (Difícil) basta para volver a montarlo, pero faltan dos piezas que Marina ha escondido en la cueva. El diario de Anselmo, en la mesa de la cocina, describe los cambios de Marina y las «canciones» que se oyen bajo el faro en pleamar.

    ## 5. Las cuevas de la marea

    > Una escalera tallada en la roca baja desde el sótano del faro hasta una gruta donde el mar respira. En el centro, sobre una losa cubierta de algas, una piedra verdosa late con una luz enferma.

    Solo se puede bajar con marea baja. En la cueva están las piezas del engranaje, envueltas en algas, junto a la piedra. Tocar la piedra cuesta 1/1D6 de Cordura y provoca visiones del fondo del mar. La piedra puede romperse con un golpe fuerte (FUE Difícil) o arrojarse al fuego del faro.

    Si Marina sigue libre, baja tras ellos y trata de impedirlo: no quiere hacer daño, pero se lanzará al agua con la piedra si puede.

    ## 6. La pleamar

    > La marea sube con un rugido. Bajo la superficie, decenas de luces verdes se acercan a la playa, y en el acantilado se escucha un canto que no sale de ninguna garganta humana.

    Si la luz vuelve a girar antes de medianoche, las figuras se detienen en la orilla y se hunden de nuevo. Si no, salen del agua: tres Profundos suben hacia el pueblo buscando a Marina. Verlos cuesta 0/1D6 de Cordura. Los investigadores pueden intentar encender la luz durante el ataque (Mecánica con un dado de penalización).

    ## Desenlaces

    - La luz vuelve a girar: los Profundos se retiran. Marina, al ver a su padre libre, elige entre quedarse o entrar en el mar. Recompensa: +1D6 de Cordura.
    - La piedra destruida: el canto cesa para siempre, pero Marina enferma y no recuerda nada. Recompensa: +1D4 de Cordura.
    - Fracaso: los Profundos se llevan a Marina y a varios vecinos. Portuxe no vuelve a ser el mismo. Pérdida de 1D6 de Cordura.

    ## Estadísticas

    Profundo: FUE 70, CON 50, TAM 80, DES 50, PV 13. Garras 45 % (1D6 + 1D4). Armadura 1 punto (escamas).
    Marina Rivas: PV 10, Esquivar 40 %. No lucha; huye hacia el agua.
    """

    static let guide = AdventureGuide(
        premise: "El faro de Punta Negra lleva tres noches apagado y un pesquero ha naufragado. Los investigadores acuden a Portuxe llamados por la doctora del pueblo y descubren que la hija del farero ha saboteado la luz para que, en la próxima pleamar viva, las criaturas del fondo vengan a buscarla.",
        truth: "La luz del faro, con un signo grabado en la lente en 1824, mantiene alejados a los Profundos que acuden a una piedra tallada de las cuevas. Marina Rivas, descendiente del farero que encontró la piedra, ha empezado a transformarse: desmontó el engranaje, escondió dos piezas en la cueva y encerró a su padre. Si la luz no gira en dos noches, los Profundos subirán a por ella.",
        hook: "Lee la carta de Elvira Cueto a un investigador que la conozca y empieza directamente en la plaza de Portuxe, con el faro apagado al fondo. Plantea desde el principio la cuenta atrás: la pleamar viva es dentro de dos noches.",
        tone: "Horror rural y costero: niebla, salitre, vecinos que callan. Ve de lo cotidiano a lo inquietante poco a poco. Usa sonidos (el mar, el viento, el canto) más que monstruos; los Profundos solo deberían verse al final.",
        prep: [
            "Imprime o ten a mano el registro de 1824 de la parroquia para dárselo a los jugadores.",
            "Decide qué investigador conoce a Elvira Cueto y escribe su carta en primera persona.",
            "Ten preparadas las estadísticas de tres Profundos para la escena final.",
            "Lleva la cuenta de la marea: la cueva solo es accesible con marea baja.",
        ],
        scenes: [
            .init(
                id: "e1", act: "Acto 1 · Portuxe", title: "Llegada a Portuxe", place: "Plaza y consulta de la doctora",
                summary: "Los investigadores llegan al pueblo y Elvira Cueto les cuenta el naufragio y el apagón del faro. Es la escena para presentar la amenaza y la cuenta atrás.",
                readAloud: "El coche de línea os deja en una plaza que huele a salitre y a leña mojada. Las casas, de piedra oscura, se aprietan unas contra otras como si temieran al mar. Al fondo, sobre el acantilado, el faro de Punta Negra se recorta apagado contra un cielo de color pizarra.",
                goals: ["Conocer a Elvira y su versión del naufragio", "Saber que Xuacu, el superviviente, está en la taberna"],
                clueIDs: ["p1"], npcIDs: ["n1"], checks: [],
                tips: ["Que Elvira hable bajo y mire al faro mientras habla: el miedo del pueblo se transmite en los gestos.", "No alargues esta escena: en 10-15 minutos deberían ir a la taberna."],
                danger: "",
                ifStuck: "Elvira se ofrece a acompañarlos a la taberna: «Xuacu no habla con forasteros, pero a mí me debe una».",
                exits: [.init(sceneID: "e2", condition: "Van a hablar con Xuacu o a alojarse en la fonda"), .init(sceneID: "e4", condition: "Deciden subir directamente al faro")]
            ),
            .init(
                id: "e2", act: "Acto 1 · Portuxe", title: "La taberna de la Remedios", place: "Taberna y fonda del puerto",
                summary: "Ambiente hostil hacia los forasteros. Xuacu, el superviviente, puede contar lo que vio, y Remedios sabe que Marina se mete en el mar de noche.",
                readAloud: "Humo de pipa, redes colgadas de las vigas y una docena de hombres que dejan de hablar cuando entráis. Detrás de la barra, una mujer enorme seca vasos sin quitaros la vista de encima.",
                goals: ["Escuchar el relato de Xuacu", "Ganarse a Remedios para que hable de Marina"],
                clueIDs: ["p1", "p2"], npcIDs: ["n2", "n3"],
                checks: [
                    .init(skill: "Persuasión", difficulty: "Normal", purpose: "Xuacu cuenta lo de los faroles verdes y la cara pálida. Si falla, solo balbucea «luces» y hay que invitarle a otra ronda."),
                    .init(skill: "Charlatanería o Encanto", difficulty: "Normal", purpose: "Remedios cuenta que Marina se mete en el mar vestida. Una buena propina da un dado de bonificación."),
                    .init(skill: "Cordura", difficulty: "0/1", purpose: "Ver a Xuacu revivir el naufragio."),
                ],
                tips: ["Interpreta a la clientela como un muro: silencios, miradas, alguien que escupe al suelo. Que el cambio cuando Remedios se ablanda se note.", "Si los jugadores son groseros, que Remedios los eche, pero que Xuacu les siga fuera."],
                danger: "Pérdida de Cordura 0/1 al escuchar a Xuacu.",
                ifStuck: "Xuacu, borracho, los sigue a la calle y señala el faro: «Ella baja al agua. La hija. Yo la vi».",
                exits: [.init(sceneID: "e3", condition: "Preguntan por la historia del pueblo o alguien menciona a don Ramiro"), .init(sceneID: "e4", condition: "Quieren ver el faro o a Marina")]
            ),
            .init(
                id: "e3", act: "Acto 2 · La investigación", title: "La parroquia de San Telmo", place: "Iglesia y archivo parroquial",
                summary: "Don Ramiro guarda el registro de 1824 que explica el signo y el papel de la luz. Es la pista que da sentido a todo lo demás.",
                readAloud: "La iglesia es pequeña y fría. Un exvoto con forma de barco cuelga sobre el altar, y a su lado alguien ha pintado, hace mucho tiempo, un signo extraño en la piedra.",
                goals: ["Encontrar el registro de 1824", "Entender que la luz con el signo mantiene lejos a las criaturas"],
                clueIDs: ["p3"], npcIDs: ["n4"],
                checks: [
                    .init(skill: "Buscar libros", difficulty: "Difícil", purpose: "Encuentran el registro de don Baltasar. Si falla, don Ramiro lo encuentra tras una hora, a costa de tiempo."),
                    .init(skill: "Cordura", difficulty: "1/1D4", purpose: "Leer el registro completo."),
                ],
                tips: ["Esta pista es clave: nunca la hagas depender de una sola tirada. Si fallan, cambia el coste (tiempo, que anochezca) en lugar de negarla.", "Don Ramiro sabe más de lo que dice; si le presionan, confiesa que su predecesor le pidió que nunca dejara apagarse el faro."],
                danger: "Pérdida de Cordura 1/1D4 al leer el registro.",
                ifStuck: "Don Ramiro, nervioso, saca él mismo el libro: «Mi predecesor me hizo jurar que si el faro se apagaba, alguien leería esto».",
                exits: [.init(sceneID: "e4", condition: "Con el registro, van al faro a comprobar la lente")]
            ),
            .init(
                id: "e4", act: "Acto 2 · La investigación", title: "El faro de Punta Negra", place: "Casa del farero y cámara de la linterna",
                summary: "Marina intenta impedir que suban. Arriba está Anselmo encerrado, el engranaje desmontado y la lente con el signo. Faltan dos piezas, escondidas en la cueva.",
                readAloud: "El camino del acantilado termina en una casa encalada pegada a la torre. El viento silba entre las rocas. La puerta se abre antes de que llaméis: una joven pálida, de ojos muy grandes, os mira sin parpadear.",
                goals: ["Liberar a Anselmo", "Descubrir el sabotaje y el signo de la lente", "Leer el diario de Anselmo"],
                clueIDs: ["p4", "p5"], npcIDs: ["n5", "n6"],
                checks: [
                    .init(skill: "Psicología", difficulty: "Normal", purpose: "Notan que Marina miente y que tiene la piel húmeda aunque no llueve."),
                    .init(skill: "Mecánica", difficulty: "Difícil", purpose: "Saben montar el engranaje y que faltan dos piezas."),
                    .init(skill: "Descubrir", difficulty: "Normal", purpose: "Encuentran el diario de Anselmo en la cocina."),
                ],
                tips: ["Marina no es una villana: es una chica asustada que oye una llamada. Hazla inquietante, no malvada.", "Los gritos de Anselmo («¡La luz!») son tu herramienta para que suban si dudan.", "Si no han pasado por la parroquia, deja que alguien reconozca el signo de la iglesia para que vuelvan allí."],
                danger: "",
                ifStuck: "Se oye un golpe arriba y la voz de Anselmo grita «¡La luz! ¡Que no se apague la luz!». Marina se queda inmóvil, mirando al mar.",
                exits: [.init(sceneID: "e5", condition: "Buscan las piezas o siguen a Marina al sótano"), .init(sceneID: "e3", condition: "Necesitan entender el signo de la lente")]
            ),
            .init(
                id: "e5", act: "Acto 3 · La marea", title: "Las cuevas de la marea", place: "Gruta bajo el faro",
                summary: "Con marea baja se baja a la cueva, donde están las piezas del engranaje y la piedra que llama a los Profundos. La piedra puede romperse o arrojarse al fuego.",
                readAloud: "Una escalera tallada en la roca baja desde el sótano del faro hasta una gruta donde el mar respira. En el centro, sobre una losa cubierta de algas, una piedra verdosa late con una luz enferma.",
                goals: ["Recuperar las dos piezas del engranaje", "Decidir qué hacer con la piedra"],
                clueIDs: ["p6"], npcIDs: ["n5"],
                checks: [
                    .init(skill: "Cordura", difficulty: "1/1D6", purpose: "Tocar la piedra: visiones del fondo del mar."),
                    .init(skill: "FUE", difficulty: "Difícil", purpose: "Romper la piedra de un golpe."),
                    .init(skill: "Esquivar o Atletismo", difficulty: "Normal", purpose: "No resbalar en las rocas si sube la marea."),
                ],
                tips: ["Describe el agua subiendo poco a poco: es un reloj visible para los jugadores.", "Si Marina baja tras ellos, ofrece un dilema: detenerla por la fuerza o convencerla."],
                danger: "Cordura 1/1D6 al tocar la piedra. Si se entretienen, la marea sube y la salida se inunda.",
                ifStuck: "Las piezas brillan entre las algas al reflejo de la piedra: es imposible no verlas si alguien ilumina la losa.",
                exits: [.init(sceneID: "e6", condition: "Suben a encender la luz o llega la pleamar")]
            ),
            .init(
                id: "e6", act: "Acto 3 · La marea", title: "La pleamar", place: "Faro, acantilado y playa",
                summary: "Clímax a medianoche. Si la luz gira, los Profundos se retiran; si no, salen del agua a por Marina y el pueblo.",
                readAloud: "La marea sube con un rugido. Bajo la superficie, decenas de luces verdes se acercan a la playa, y en el acantilado se escucha un canto que no sale de ninguna garganta humana.",
                goals: ["Encender la luz antes de medianoche", "Decidir el destino de Marina"],
                clueIDs: [], npcIDs: ["n5", "n6"],
                checks: [
                    .init(skill: "Mecánica", difficulty: "Normal (con un dado de penalización si atacan)", purpose: "Volver a hacer girar la lente."),
                    .init(skill: "Cordura", difficulty: "0/1D6", purpose: "Ver a los Profundos salir del agua."),
                ],
                tips: ["Corta las descripciones y acelera: frases cortas, decisiones rápidas.", "Deja que Marina tenga la última palabra: su elección hace memorable el final."],
                danger: "Tres Profundos (PV 13, garras 1D6+1D4). Cordura 0/1D6 al verlos.",
                ifStuck: "Anselmo, recuperado, se arrastra hasta la linterna e intenta encenderla él mismo: los investigadores solo tienen que protegerle.",
                exits: []
            ),
        ],
        npcs: [
            .init(id: "n1", name: "Elvira Cueto", role: "Médica de Portuxe y aliada de los investigadores", look: "Cuarentona, gafas redondas, abrigo de hombre y manos que no paran quietas.", motivation: "Que alguien de fuera averigüe qué pasa antes de que haya más muertos.", secret: "", voice: "Habla rápido y bajo; termina las frases con «¿me entiende?».", stats: ""),
            .init(id: "n2", name: "Remedios", role: "Tabernera, sabe todo lo que pasa en el pueblo", look: "Enorme, delantal manchado, brazos de estibador.", motivation: "Proteger su negocio y a los suyos de los forasteros.", secret: "Vio a Marina entrar en el mar y no se lo ha contado a nadie.", voice: "Seca, con respuestas de una palabra hasta que se ablanda. Llama «rapaz» a todo el mundo.", stats: ""),
            .init(id: "n3", name: "Xuacu", role: "Pescador, único superviviente del naufragio", look: "Flaco, barba de días, tiembla aunque esté junto al fuego.", motivation: "Que alguien le crea.", secret: "", voice: "Frases entrecortadas, mira siempre hacia la ventana que da al mar.", stats: ""),
            .init(id: "n4", name: "Don Ramiro", role: "Párroco de San Telmo, custodio del archivo", look: "Anciano, sotana raída, olor a cera.", motivation: "Cumplir la promesa de su predecesor sin tener que enfrentarse a lo que esconde.", secret: "Le juraron que nunca dejaría que el faro se apagara, y no ha hecho nada en tres noches.", voice: "Titubea, cita el Evangelio cuando tiene miedo.", stats: ""),
            .init(id: "n5", name: "Marina Rivas", role: "Hija del farero; ha saboteado la luz", look: "Veinte años, muy pálida, ojos enormes que apenas parpadean, piel siempre húmeda.", motivation: "Responder a la llamada del mar sin que nadie salga herido.", secret: "Tiene sangre de los Profundos y se está transformando. Escondió las piezas en la cueva.", voice: "Voz suave y lenta, pausas largas, nunca levanta el tono.", stats: "PV 10, Esquivar 40 %. No lucha: huye hacia el agua."),
            .init(id: "n6", name: "Anselmo Rivas", role: "Farero, encerrado en la cámara de la linterna", look: "Sesenta años, barba blanca, labios agrietados por la sed.", motivation: "Que la luz vuelva a girar y salvar a su hija.", secret: "Sabe lo que es su hija desde hace meses y lo ha ocultado.", voice: "Ronco, repite «la luz» como un rezo. Lúcido a ratos.", stats: ""),
        ],
        clues: [
            .init(id: "p1", title: "Luces bajo el agua", detail: "Antes de hundirse, Xuacu vio faroles verdes que subían del fondo y una cara pálida en el agua.", sceneID: "e2", leadsTo: "Lo que hay en el mar está relacionado con el faro", isCore: false),
            .init(id: "p2", title: "Marina camina hacia el mar", detail: "Marina ha bajado tres noches seguidas a la playa y se ha metido en el agua vestida.", sceneID: "e2", leadsTo: "Marina, en el faro", isCore: false),
            .init(id: "p3", title: "Registro de 1824", detail: "«La luz los mantiene lejos. Mientras el signo gire en el cristal, el mar no subirá a por nosotros.»", sceneID: "e3", leadsTo: "Hay que volver a encender la luz con la lente del signo", isCore: true),
            .init(id: "p4", title: "La lente sellada", detail: "El engranaje está desmontado y la lente lleva grabado el signo de la iglesia. Faltan dos piezas.", sceneID: "e4", leadsTo: "Las piezas están en la cueva", isCore: true),
            .init(id: "p5", title: "Diario de Anselmo", detail: "Describe los cambios de Marina y las canciones que se oyen bajo el faro en pleamar.", sceneID: "e4", leadsTo: "Las cuevas bajo el faro", isCore: false),
            .init(id: "p6", title: "La piedra que canta", detail: "La piedra verdosa de la cueva llama a los Profundos. Puede romperse o arrojarse al fuego.", sceneID: "e5", leadsTo: "Segunda forma de acabar con la amenaza", isCore: true),
        ],
        endings: [
            .init(title: "La luz vuelve a girar", condition: "La lente gira antes de medianoche.", outcome: "Los Profundos se retiran. Marina elige entre quedarse con su padre o entrar en el mar. +1D6 de Cordura."),
            .init(title: "La piedra destruida", condition: "Rompen la piedra o la arrojan al fuego.", outcome: "El canto cesa para siempre; Marina enferma y no recuerda nada. +1D4 de Cordura."),
            .init(title: "La marea se los lleva", condition: "La luz sigue apagada en la pleamar.", outcome: "Los Profundos se llevan a Marina y a varios vecinos. −1D6 de Cordura."),
        ]
    )
}
