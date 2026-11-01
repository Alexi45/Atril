import AVFoundation
import Observation

/// Ambientes sonoros generados en tiempo real (sin archivos de audio).
enum Ambience: String, CaseIterable, Identifiable, Codable {
    case sea, rain, wind, fire, crypt, heartbeat

    var id: String { rawValue }

    var name: String {
        switch self {
        case .sea: "Mar"
        case .rain: "Lluvia"
        case .wind: "Viento"
        case .fire: "Fuego"
        case .crypt: "Cripta"
        case .heartbeat: "Latido"
        }
    }

    var symbol: String {
        switch self {
        case .sea: "water.waves"
        case .rain: "cloud.rain"
        case .wind: "wind"
        case .fire: "flame"
        case .crypt: "moon.haze"
        case .heartbeat: "heart"
        }
    }

    /// Ambiente que pide el texto de una escena, si alguno encaja.
    static func suggestion(for scene: AdventureGuide.Scene) -> Ambience? {
        // Primero dónde están (título, lugar, lo que se lee); el resumen puede mencionar otros
        // sitios («las piezas están en la cueva») y solo se usa si lo anterior no dice nada.
        suggestion(in: [scene.title, scene.place, scene.readAloud].joined(separator: " "))
            ?? suggestion(in: scene.summary)
    }

    private static func suggestion(in raw: String) -> Ambience? {
        let text = Prose.fold(raw) + " "
        func has(_ words: [String]) -> Bool { words.contains { text.contains($0) } }
        // Primero los interiores: una taberna «del puerto» suena a fuego, no a mar.
        if has(["cripta", "cueva", "gruta", "sotano", "catacumba", "tunel", "mazmorra", "tumba", "subterrane", "cloaca"]) { return .crypt }
        if has(["lluvia", "llueve", "tormenta", "aguacero", "chaparron"]) { return .rain }
        if has(["taberna", "posada", "hoguera", "chimenea", "campamento", "fonda", "fogata"]) { return .fire }
        if has(["mar ", "mar,", "mar.", "playa", "puerto", "olas", "barco", "acantilado", "marea", "costa", "orilla", "muelle"]) { return .sea }
        if has(["viento", "paramo", "colina", "montana", "torre", "cumbre", "desierto", "llanura"]) { return .wind }
        return nil
    }
}

/// Reproductor de ambientes: cada uno es una fuente de audio que se mezcla con las demás y
/// entra y sale con un fundido suave.
@MainActor
@Observable
final class AmbiencePlayer {
    static let shared = AmbiencePlayer()

    static let volumeKey = "ambienceVolume"
    static let followKey = "ambienceFollowsScene"

    private(set) var active: Set<Ambience> = []
    var volume: Float = (UserDefaults.standard.object(forKey: AmbiencePlayer.volumeKey) as? Float) ?? 0.6 {
        didSet {
            engine.mainMixerNode.outputVolume = volume
            UserDefaults.standard.set(volume, forKey: Self.volumeKey)
        }
    }

    private let engine = AVAudioEngine()
    private var synths: [Ambience: AmbienceSynth] = [:]
    private var nodes: [Ambience: AVAudioSourceNode] = [:]

    private init() {}

    func isPlaying(_ ambience: Ambience) -> Bool { active.contains(ambience) }

    func toggle(_ ambience: Ambience) {
        if active.contains(ambience) { stop(ambience) } else { play(ambience) }
    }

    /// Deja sonando solo estos ambientes (con fundido).
    func set(_ ambiences: Set<Ambience>) {
        for ambience in active.subtracting(ambiences) { stop(ambience) }
        for ambience in ambiences.subtracting(active) { play(ambience) }
    }

    func play(_ ambience: Ambience) {
        guard startEngine() else { return }
        let synth = synths[ambience] ?? attach(ambience)
        synth.targetGain = 1
        active.insert(ambience)
    }

    func stop(_ ambience: Ambience) {
        synths[ambience]?.targetGain = 0
        active.remove(ambience)
    }

    func stopAll() {
        for ambience in active { stop(ambience) }
    }

    private func attach(_ ambience: Ambience) -> AmbienceSynth {
        let format = engine.outputNode.inputFormat(forBus: 0)
        let sampleRate = format.sampleRate > 0 ? format.sampleRate : 48_000
        let stereo = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let synth = AmbienceSynth(kind: ambience, sampleRate: Float(sampleRate))
        let node = AVAudioSourceNode(format: stereo) { _, _, frameCount, bufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard buffers.count >= 2,
                  let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            synth.render(left: left, right: right, frames: Int(frameCount))
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: stereo)
        synths[ambience] = synth
        nodes[ambience] = node
        return synth
    }

    private func startEngine() -> Bool {
        if engine.isRunning { return true }
        #if os(iOS)
        // Se mezcla con la voz del narrador y no corta la música de otras apps.
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        engine.mainMixerNode.outputVolume = volume
        do {
            try engine.start()
            return true
        } catch {
            return false
        }
    }
}

/// Generador de un ambiente. Trabaja en el hilo de audio: sin reservas de memoria ni bloqueos.
final class AmbienceSynth: @unchecked Sendable {
    let kind: Ambience
    let sampleRate: Float
    /// Volumen al que tiende (0 o 1); el fundido lo sigue poco a poco.
    var targetGain: Float = 0
    private(set) var gain: Float = 0

    private var seed: UInt32 = 0x9E37_79B9
    /// En `Double`: con `Float`, sumar 1/48.000 s deja de avanzar a los pocos minutos.
    /// Interno (no privado) para poder probar sesiones largas sin generar horas de audio.
    var time: Double = 0
    private var dronePhases = (Double(0), Double(0), Double(0))
    // Filtros y estados de ruido
    private var brown: Float = 0
    private var pink = (Float(0), Float(0), Float(0), Float(0), Float(0), Float(0), Float(0))
    private var lowL: Float = 0, lowR: Float = 0, high: Float = 0, highPrevious: Float = 0
    private var bandLow: Float = 0, bandBand: Float = 0
    // Sucesos breves: gotas, chasquidos, latidos
    private var eventLevel: Float = 0
    private var eventPan: Float = 0.5
    private var eventPhase: Float = 0
    private var eventPitch: Float = 0
    private var nextEvent: Double = 0
    private var beatClock: Float = 0
    private var dripDelay = [Float](repeating: 0, count: 24_000)
    private var dripIndex = 0

    init(kind: Ambience, sampleRate: Float) {
        self.kind = kind
        self.sampleRate = sampleRate
        dripDelay = [Float](repeating: 0, count: Int(sampleRate * 0.5))
    }

    private func white() -> Float {
        seed ^= seed << 13
        seed ^= seed >> 17
        seed ^= seed << 5
        return Float(seed) / Float(UInt32.max) * 2 - 1
    }

    /// Ruido rosa (filtro de Paul Kellet).
    private func pinkNoise() -> Float {
        let w = white()
        pink.0 = 0.99886 * pink.0 + w * 0.0555179
        pink.1 = 0.99332 * pink.1 + w * 0.0750759
        pink.2 = 0.96900 * pink.2 + w * 0.1538520
        pink.3 = 0.86650 * pink.3 + w * 0.3104856
        pink.4 = 0.55000 * pink.4 + w * 0.5329522
        pink.5 = -0.7616 * pink.5 - w * 0.0168980
        let value = pink.0 + pink.1 + pink.2 + pink.3 + pink.4 + pink.5 + pink.6 + w * 0.5362
        pink.6 = w * 0.115926
        return value * 0.11
    }

    private func brownNoise() -> Float {
        brown = (brown + 0.02 * white()) / 1.02
        return brown * 3.5
    }

    private func random(_ range: ClosedRange<Float>) -> Float {
        range.lowerBound + (white() * 0.5 + 0.5) * (range.upperBound - range.lowerBound)
    }

    /// Onda senoidal lenta (LFO) a partir del reloj.
    private func lfo(_ frequency: Double, phase: Double = 0) -> Float {
        Float(sin(2 * .pi * frequency * time + phase))
    }

    func render(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int) {
        let dt = 1 / sampleRate
        let fade: Float = 1 / (sampleRate * 1.5)
        for i in 0..<frames {
            // Fundido de entrada y salida de 1,5 s.
            if gain < targetGain { gain = min(targetGain, gain + fade) } else if gain > targetGain { gain = max(targetGain, gain - fade) }
            guard gain > 0 else {
                left[i] = 0
                right[i] = 0
                continue
            }
            time += Double(dt)
            var l: Float = 0, r: Float = 0
            switch kind {
            case .sea: (l, r) = sea()
            case .rain: (l, r) = rain(dt)
            case .wind: (l, r) = wind()
            case .fire: (l, r) = fire(dt)
            case .crypt: (l, r) = crypt(dt)
            case .heartbeat: (l, r) = heartbeat(dt)
            }
            left[i] = max(-1, min(1, l * gain))
            right[i] = max(-1, min(1, r * gain))
        }
    }

    // MARK: Ambientes

    private func sea() -> (Float, Float) {
        // Olas de unos 9 s: el volumen y el brillo suben y bajan juntos.
        let wave = 0.5 + 0.5 * lfo(1 / 9.3)
        let swell = pow(wave, 2.2)
        let cutoff = 0.02 + 0.10 * swell
        let noise = brownNoise()
        lowL += cutoff * (noise - lowL)
        lowR += cutoff * (brownNoise() - lowR)
        let foam = pinkNoise() * 0.25 * swell * swell
        return ((lowL * 0.9 + foam) * (0.25 + 0.75 * swell), (lowR * 0.9 + foam) * (0.25 + 0.75 * swell))
    }

    private func rain(_ dt: Float) -> (Float, Float) {
        // Rumor continuo (ruido rosa sin graves) y gotas sueltas.
        let noise = pinkNoise()
        high = 0.97 * (high + noise - highPrevious)
        highPrevious = noise
        if time >= nextEvent {
            eventLevel = random(0.15...0.6)
            eventPan = random(0...1)
            nextEvent = time + Double(random(0.005...0.06))
        }
        eventLevel *= 0.992
        let drop = white() * eventLevel
        let base = high * 0.45
        return (base + drop * (1 - eventPan) * 0.35, base + drop * eventPan * 0.35)
    }

    private func wind() -> (Float, Float) {
        // Ruido filtrado con una resonancia que sube y baja: el silbido de las ráfagas.
        let sweep = 0.5 + 0.3 * lfo(0.07) + 0.2 * lfo(0.13, phase: 1.3)
        let frequency: Float = 250 + 650 * sweep
        let f = 2 * sin(.pi * frequency / sampleRate)
        let q: Float = 0.25
        let input = pinkNoise()
        bandLow += f * bandBand
        let highPass = input - bandLow - q * bandBand
        bandBand += f * highPass
        let gust = 0.4 + 0.6 * pow(sweep, 1.5)
        let value = bandBand * 1.6 * gust
        lowL += 0.002 * (brownNoise() - lowL)
        return (value + lowL * 0.3, value * 0.9 + lowL * 0.3)
    }

    private func fire(_ dt: Float) -> (Float, Float) {
        // Rumor grave de las llamas y chasquidos de la leña.
        let noise = brownNoise()
        lowL += 0.03 * (noise - lowL)
        let flicker = 0.7 + 0.3 * lfo(0.4) * lfo(0.23)
        if time >= nextEvent {
            eventLevel = random(0.3...1)
            eventPan = random(0.2...0.8)
            nextEvent = time + Double(random(0...1) < 0.7 ? random(0.02...0.12) : random(0.3...1.2))
        }
        eventLevel *= 0.93
        let crackle = white() * eventLevel
        high = 0.9 * (high + crackle - highPrevious)
        highPrevious = crackle
        let base = lowL * 0.8 * flicker
        return (base + high * (1 - eventPan) * 0.5, base + high * eventPan * 0.5)
    }

    private func crypt(_ dt: Float) -> (Float, Float) {
        // Zumbido grave que late despacio, aire que corre y una gota lejana con eco.
        let tremolo = 0.75 + 0.25 * lfo(0.11)
        let step = 2 * Double.pi / Double(sampleRate)
        dronePhases.0 = (dronePhases.0 + step * 55).truncatingRemainder(dividingBy: 2 * .pi)
        dronePhases.1 = (dronePhases.1 + step * 55.35).truncatingRemainder(dividingBy: 2 * .pi)
        dronePhases.2 = (dronePhases.2 + step * 82.4).truncatingRemainder(dividingBy: 2 * .pi)
        let drone = Float(sin(dronePhases.0) + 0.8 * sin(dronePhases.1) + 0.5 * sin(dronePhases.2)) * 0.12 * tremolo
        lowL += 0.004 * (brownNoise() - lowL)
        if time >= nextEvent {
            eventLevel = random(0.2...0.4)
            eventPitch = random(900...1500)
            eventPhase = 0
            eventPan = random(0.1...0.9)
            nextEvent = time + Double(random(2.5...7))
        }
        eventPhase = (eventPhase + 2 * .pi * eventPitch * dt).truncatingRemainder(dividingBy: 2 * .pi)
        eventPitch *= 0.99995
        eventLevel *= 0.9993
        let drip = sin(eventPhase) * eventLevel
        let echo = dripDelay[dripIndex]
        dripDelay[dripIndex] = drip + echo * 0.45
        dripIndex = (dripIndex + 1) % dripDelay.count
        let wet = drip + echo * 0.6
        let air = lowL * 0.5
        return (drone + air + wet * (1 - eventPan), drone + air + wet * eventPan)
    }

    private func heartbeat(_ dt: Float) -> (Float, Float) {
        // Dos golpes («pum-pum») a unas 66 pulsaciones por minuto.
        let period: Float = 60 / 66
        beatClock += dt
        if beatClock >= period { beatClock -= period }
        func thump(_ start: Float, strength: Float) -> Float {
            let t = beatClock - start
            guard t >= 0, t < 0.25 else { return 0 }
            let pitch = 48 + 30 * exp(-t * 30)
            return sin(2 * .pi * pitch * t) * exp(-t * 18) * strength
        }
        let value = thump(0, strength: 0.9) + thump(0.28, strength: 0.6)
        lowL += 0.08 * (value - lowL)
        return (lowL * 1.4, lowL * 1.4)
    }
}
