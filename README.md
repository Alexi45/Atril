# Atril

Tutor de máster para iPad y Mac. Le das el guion de una aventura de **La llamada de Cthulhu** o **Dungeons & Dragons** y:

1. **Te la organiza**: escenas en orden con texto para leer en voz alta, objetivos, pistas (marcando las clave), PNJ con cómo interpretarlos, tiradas probables, peligros, qué hacer si los jugadores se atascan, desenlaces y una lista de preparación.
2. **Te planifica las sesiones**: estima cuánto dura cada escena y reparte la aventura en sesiones de la duración que elijas, con el mejor punto para cortar.
3. **Te acompaña en mesa**: escena actual, referencia rápida de escenas/PNJ/pistas, bitácora, reloj, dados (d100 con bonificación/penalización, d20 con ventaja) y PV/Cordura de los personajes.
4. **Te aconseja**: un tutor al que preguntar en cualquier momento («¿Qué hago ahora?», «Están atascados», «Se han salido del guion», «Improvisa un PNJ»…) y que además avisa por su cuenta: una pista clave que se dejaron atrás, una escena que se alarga, un personaje con 0 PV, una pérdida de Cordura que pide tirada de INT, el final de la sesión.
5. **Narra y enseña**: lee en voz alta el texto de las escenas con una voz española del sistema (`Narrator`), y enseña a los jugadores el texto o una pista a pantalla completa, como narración o como documento en papel (`PlayerScreenView`; en el Mac, en una ventana aparte para llevarla a otra pantalla).
6. **Combate**: orden de iniciativa (DES en Cthulhu, d20 + modificador en D&D), asaltos, turnos que saltan a los caídos y PV de enemigos sacados de las estadísticas del guion (`StatBlock`); los PV de los personajes están sincronizados con su ficha.
7. **Mapa de la aventura**: las escenas como diagrama de flujo (camino más largo siguiendo el orden del guion; atajos en arco por encima y vueltas atrás discontinuas por debajo), con el progreso de la partida.
8. **Resumen de sesión**: al cerrar la mesa, estadísticas, un texto para compartir con los jugadores (redactado por la IA solo con lo que ellos saben) y los pendientes del máster; al empezar la siguiente sesión, un «Previamente…» para leer.
9. **Retratos de PNJ**: se crean en el dispositivo con Image Playground (iPadOS 18.1 / macOS 15.1 con Apple Intelligence) a partir de su aspecto y la época, o se elige una imagen; se ven en fichas, escenas y referencia, y se enseñan a los jugadores sin revelar nada más que el nombre. Se guardan por nombre (`Portrait`), así que sobreviven a un nuevo análisis.
10. **Ambientación sonora**: mar, lluvia, viento, fuego, cripta y latido, generados en tiempo real con `AVAudioEngine` (sin archivos), combinables y con fundidos; la app sugiere el de cada escena y puede cambiarlo sola al pasar de escena.
11. **Búsqueda** (⌘F): escenas, PNJ, pistas y texto del guion a la vez, sin tildes ni mayúsculas.
12. **Hoja de preparación en PDF**: A4 maquetado sin partir escenas, para la próxima sesión (desde donde se quedó la mesa), una sesión del plan o la aventura entera, con el «Previamente…», cada escena resumida y la referencia de PNJ con retratos. Se comparte o se imprime.
13. **Exportar e importar** (`.atril`): guion, guía, sesiones y retratos en un archivo JSON para pasar del Mac al iPad por AirDrop o Archivos, o como copia de seguridad.
14. **Tablas de mesa**: ataque de locura, fobia, manía, detalle inquietante, rumor, botín, encuentro, complicación, giro de la trama, nombres… con una pulsación y sin conexión, para anotar o narrar el resultado.
15. **Todo se puede corregir**: escenas, pistas y PNJ se editan a mano. Si editas la guía mientras la IA la prepara, al terminar te pregunta con cuál te quedas en vez de pisar tus cambios.

En mesa la pantalla no se apaga, y cada respuesta del tutor lleva «Comprobar en el guion» con los pasajes en los que se ha basado.

**Sin cuentas ni pagos**: la IA va integrada. Incluye una aventura corta original de ejemplo, *La luz de Punta Negra*.

## Cómo funciona la IA

Atril elige solo el mejor motor disponible (`AIBackend.current`):

| Motor | Cuándo | Cómo |
|---|---|---|
| **IA de Apple en el dispositivo** | iPadOS/macOS 26+ con Apple Intelligence | Modelo local (8.192 tokens de contexto). Si el guion tiene estructura, las escenas, el texto para leer y las tiradas salen de las heurísticas y la IA **enriquece escena a escena** (resumen, objetivos, pistas, consejos, «si se atascan») y hace las fichas de los PNJ, con respuestas cortas y límites (`.maximumCount`). Si no la tiene, **extrae** la estructura trozo a trozo (`ScriptChunker`, ~650 palabras) y `GuideMerger` une escenas, PNJ y pistas sin duplicados. En mesa, cada pregunta lleva la escena actual, el estado de la mesa y los pasajes del guion más relacionados (buscador BM25, `ScriptIndex`). |
| **IA de Apple en la nube privada** | iPadOS/macOS 27+, **solo si la app se compila con `PCC_ENTITLED`** | Mismo proceso con trozos mucho mayores (32.768 tokens). Requiere el permiso `com.apple.developer.private-cloud-compute`: sin él, FoundationModels cierra la app en iPadOS. Para activarlo: añade la capacidad «Private Cloud Compute» en Signing & Capabilities con tu equipo y añade `PCC_ENTITLED` a `SWIFT_ACTIVE_COMPILATION_CONDITIONS`. |
| **Modo básico** | Siempre (respaldo) | `HeuristicAnalyzer` organiza el guion sin modelo: encabezados, texto de caja (`>`), tiradas y pérdidas de Cordura por patrones, pistas y personajes (reconocedor de nombres de Apple + señales del español). `BasicTutor` responde con la guía, una referencia de reglas, tablas de improvisación y búsqueda en el guion. |
| Claude (opcional) | Si se activa en Ajustes con una clave propia | Análisis con salida estructurada y tutor con el guion completo en caché. |

Al importar, la guía básica aparece al instante y la IA la sustituye cuando termina; si la IA falla en un trozo, ese trozo se queda con la versión básica. Las sesiones se recolocan en las escenas equivalentes de la nueva guía.

Medido en un Mac con macOS 27 y la aventura de ejemplo (1.110 palabras): la IA del dispositivo prepara la guía en ~80 s y el tutor responde en 4-7 s. El trasfondo, el gancho y los desenlaces se toman del texto del guion cuando existen (el modelo pequeño los parafrasea peor). Salvaguardas frente a sus fallos habituales: tope de tokens por respuesta (evita bucles), filtro de valores de relleno y fragmentos del esquema (`Prose.isPlaceholder`), consejos repetidos o de dos palabras descartados, y PNJ de cada escena decididos por el texto. Las pistas clave que elige la IA aciertan a medias: se corrigen en el editor de escenas.

### Lectura de PDF maquetados

Un módulo publicado no tiene encabezados: tiene líneas sueltas con otra fuente. `PDFStructure` lee la fuente de cada línea y recupera la estructura:

- **Títulos** por tamaño: el mayor es el título del documento; los tamaños raros con muchos por debajo son partes; el siguiente, escenas; lo más pequeño, apartados que no parten la escena. Sin tamaños distintos, las líneas cortas en negrita hacen de título. Un título en dos líneas se une.
- **Texto para leer** por la cursiva, además de frases como «léeles lo siguiente:» o «lee o parafrasea».
- **Cabeceras y números de página**: lo que se repite en los bordes de muchas páginas se elimina.
- **Párrafos** recompuestos a partir de las líneas partidas y los guiones de final de línea.

Los PDF escaneados se leen con OCR (Vision) en el propio dispositivo, y la altura de cada línea sustituye al tamaño de letra. En archivos de texto sin marcas, las líneas cortas sueltas entre líneas en blanco cuentan como títulos si no hay otros.

Las estadísticas del guion («Profundo: FUE 70, … PV 13», o los bloques de D&D con «Clase de Armadura» y «Puntos de golpe») se detectan para añadir enemigos al combate de un toque.

### Rendimiento

Medido en Release en un Mac con una campaña de prueba de 44.000 palabras y 48 escenas (`Benchmarks`):

| | Antes | Ahora |
|---|---|---|
| Organizar el guion sin IA | 2,2 s en el hilo principal | 0,24 s en segundo plano |
| Abrir la mesa | 283 ms | 6 ms |
| Buscar en la aventura, por tecla | 3,9 ms | 0,1 ms |
| Repintar la ficha de la aventura | ~40 ms | < 1 ms |
| Reconocer 4 páginas escaneadas | 0,77 s | 0,64 s |

- La guía se decodifica una vez por versión y las palabras, la huella y los párrafos del guion se calculan una vez (`Caches.swift`). El buscador del guion se construye en segundo plano al abrir la aventura y lo comparten la mesa, la búsqueda y el tutor.
- En el análisis, el reconocedor de nombres de Apple (lo más lento) se reparte entre los núcleos; las frases se trocean con un tokenizador reutilizado, el texto se pliega sin pasar por Foundation cuando es latino y las búsquedas de texto comparan bytes (`containsBytes`). Las expresiones regulares se compilan una vez. El resultado es idéntico al de antes (comprobado con `SnapshotTests`) y ya no depende del orden aleatorio de los diccionarios.
- En mesa, la respuesta que está llegando repinta solo su tarjeta, el Markdown se interpreta una vez por mensaje, la sesión del modelo se deja precalentada para la siguiente pregunta y los retratos se decodifican una vez al tamaño en que se ven.
- El motor de audio se para cuando no suena ningún ambiente. Las cachés se vacían si el iPad avisa de que falta memoria.
- Lo que no se puede acelerar: el modelo de Apple en el dispositivo atiende las peticiones de una en una (6 escenas tardan lo mismo pidiéndolas de una en una que a la vez) y PDFKit lee las páginas de una en una (~5 ms cada una).

## Requisitos

- Xcode 27, iPadOS 18+ / macOS 15+ (la IA de Apple necesita 26+; antes, modo básico).
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `xcodegen generate` tras añadir archivos.

## Estructura

| Carpeta | Contenido |
|---|---|
| `Atril/AI` | Motores: IA de Apple, heurístico, fusión de borradores, buscador, tutor básico, tutor proactivo y planificador |
| `Atril/Models` | SwiftData (`Adventure`, `PlaySession`), guía estructurada y estado de mesa |
| `Atril/Services` | Importación (PDF/OCR/TXT/MD/RTF), centro de análisis, dados, cliente de Claude |
| `Atril/Play` | Modo mesa: `PlayController`, escena, panel del tutor, dados, personajes |
| `Atril/Views` | Biblioteca, importación, guía y plan, editor de escenas, ajustes |
| `Atril/Demo` | Aventura de ejemplo y diagnóstico de IA |
| `Tests/AtrilTests` | Tests (Swift Testing) |
| `Tools/make_icon.swift` | Genera el icono |

## Depuración y capturas (DEBUG)

- `-seedDemo` crea la aventura de ejemplo con una sesión a medias; `-openPlay` abre la mesa; `-openPanel dice|tables|party|combat|combatstrip|map|end|handout|document|ambience|search` (en la mesa) o `prep` (en la guía); `-openTab plan|map|scenes|npcs…`; `-ask "pregunta"`.
- `-seedImport` importa el guion de ejemplo como un archivo nuevo (guía básica + IA); `-openImport` abre la pantalla de importar.
- `-probeAI` analiza el ejemplo con cada modelo de Apple disponible, pregunta al tutor e imprime tiempos y resultados (`PROBE_TIERS=onDevice` para elegir; `PROBE_PDF=ruta` para probar un PDF dentro del contenedor de la app, `PROBE_QUESTION` para cambiar la pregunta y `PROBE_PARALLEL=1` para medir si preparar varias escenas a la vez acaba antes).
- `-searchQuery "texto"` (con `-openPanel search`) entra ya buscando.
- Medidas: `TEST_RUNNER_ATRIL_BENCH=1 xcodebuild test -configuration Release ENABLE_TESTABILITY=YES ENABLE_HARDENED_RUNTIME=NO -only-testing:AtrilTests/Benchmarks …`. Instantánea de resultados para comparar versiones: `TEST_RUNNER_ATRIL_SNAPSHOT=nombre.json` (con `TEST_RUNNER_SWIFT_DETERMINISTIC_HASHING=1`).
- `-hasAPIKey YES` simula tener clave de Claude.

```bash
build/DerivedData/Build/Products/Debug/Atril.app/Contents/MacOS/Atril -probeAI
```

---

© 2026 Alejandro Riscart Rosado. Todos los derechos reservados. Consulta [LICENSE](LICENSE).
