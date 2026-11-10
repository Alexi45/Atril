import Foundation

/// Todas las cachés de la app, para vaciarlas de golpe si el sistema avisa de que falta memoria.
enum CacheRegistry {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var purgers: [() -> Void] = []

    static func register(_ purge: @escaping () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        purgers.append(purge)
    }

    static func purgeAll() {
        lock.lock()
        let all = purgers
        lock.unlock()
        all.forEach { $0() }
    }
}

/// Caché acotada y segura entre hilos. Al llenarse se vacía entera: guarda pocas cosas y
/// recalcularlas de vez en cuando cuesta mucho menos de lo que ahorra.
final class BoundedCache<Key: Hashable, Value>: @unchecked Sendable {
    private var storage: [Key: Value] = [:]
    private let lock = NSLock()
    private let limit: Int

    init(limit: Int) {
        self.limit = limit
        CacheRegistry.register { [weak self] in self?.removeAll() }
    }

    subscript(key: Key) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    func insert(_ value: Value, for key: Key) {
        lock.lock()
        defer { lock.unlock() }
        if storage.count >= limit, storage[key] == nil { storage.removeAll(keepingCapacity: true) }
        storage[key] = value
    }

    /// Saca el valor y lo quita de la caché.
    func take(_ key: Key) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        return storage.removeValue(forKey: key)
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll()
    }

    /// El valor guardado o, si no lo hay, el que calcula `make` (fuera del candado: si dos
    /// hilos lo piden a la vez, los dos lo calculan, y da igual cuál se queda).
    func value(for key: Key, orMake make: () throws -> Value) rethrows -> Value {
        if let hit = self[key] { return hit }
        let value = try make()
        insert(value, for: key)
        return value
    }
}

extension AdventureGuide {
    /// Guías ya decodificadas, por sus datos: la ficha de una aventura lee la guía muchas veces
    /// en cada repintado, y decodificar el JSON de una campaña cuesta casi un milisegundo.
    /// Los datos se comparan enteros, así que nunca se devuelve una guía de otros datos.
    private static let decoded = BoundedCache<Data, AdventureGuide>(limit: 16)

    static func decode(_ data: Data) -> AdventureGuide? {
        if let hit = decoded[data] { return hit }
        guard let guide = try? JSONDecoder().decode(AdventureGuide.self, from: data) else { return nil }
        decoded.insert(guide, for: data)
        return guide
    }

    func encoded() -> Data? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        Self.decoded.insert(self, for: data)
        return data
    }
}

/// Datos derivados del guion de una aventura (palabras, huella, párrafos) que las vistas piden
/// en cada repintado. Se calculan una vez por versión del guion: si el guion cambia, la
/// comparación con el guardado lo detecta y se recalculan.
final class ScriptDerived<Value>: @unchecked Sendable {
    private let cache = BoundedCache<ObjectIdentifier, (script: String, value: Value)>(limit: 64)
    private let make: (String) -> Value

    init(_ make: @escaping (String) -> Value) {
        self.make = make
    }

    func value(for owner: AnyObject, script: String) -> Value {
        let key = ObjectIdentifier(owner)
        if let hit = cache[key], hit.script == script { return hit.value }
        let value = make(script)
        cache.insert((script, value), for: key)
        return value
    }
}

extension ScriptIndex {
    private static let built = BoundedCache<String, ScriptIndex>(limit: 4)

    /// El índice de un guion, construido una sola vez: lo comparten la mesa, la búsqueda y el
    /// tutor. `prepare` lo construye por adelantado en segundo plano.
    static func cached(for script: String) -> ScriptIndex {
        built.value(for: script) { ScriptIndex(script: script) }
    }

    static func prepare(for script: String) {
        guard built[script] == nil else { return }
        Task.detached(priority: .utility) { _ = cached(for: script) }
    }
}

enum WordCounter {
    /// Palabras de un texto, contando como separador cualquier espacio de Unicode. Recorre el
    /// texto sin crear subcadenas: en un guion largo es decenas de veces más rápido que `split`.
    static func count(_ text: String) -> Int {
        var words = 0
        var inWord = false
        for scalar in text.unicodeScalars {
            if isSpace(scalar.value) {
                inWord = false
            } else if !inWord {
                inWord = true
                words += 1
            }
        }
        return words
    }

    /// La propiedad White_Space de Unicode, la misma que usa `Character.isWhitespace`.
    @inline(__always)
    private static func isSpace(_ value: UInt32) -> Bool {
        switch value {
        case 0x09...0x0D, 0x20, 0x85, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000: true
        default: false
        }
    }
}

extension String {
    /// Si contiene `needle` comparando los bytes con `memmem`. Pensado para buscar claves ya
    /// plegadas en texto plegado (`Prose.fold`): da lo mismo que `contains` y es mucho más rápido.
    func containsBytes(_ needle: String) -> Bool {
        var haystack = self
        var needle = needle
        return haystack.withUTF8 { text in
            needle.withUTF8 { key in
                guard !key.isEmpty, text.count >= key.count else { return false }
                return memmem(text.baseAddress, text.count, key.baseAddress, key.count) != nil
            }
        }
    }
}
