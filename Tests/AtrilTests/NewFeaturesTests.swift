import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import SwiftData
import Testing
import UniformTypeIdentifiers
@testable import Atril

@MainActor
struct ArchiveTests {
    private func container() throws -> ModelContainer {
        try ModelContainer(for: Adventure.self, PlaySession.self, Portrait.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @Test func roundTripKeepsEverything() throws {
        let source = try container()
        let adventure = SampleAdventure.make(in: source.mainContext, withSession: true)
        adventure.setPortrait(Data([1, 2, 3]), for: "Marina Rivas")
        adventure.prepDone = ["Lee el guion"]
        let data = try AdventureArchive(adventure).encoded()

        let target = try container()
        let archive = try AdventureArchive.decode(data)
        let restored = archive.restore(into: target.mainContext, existingTitles: [])
        #expect(restored.title == SampleAdventure.title)
        #expect(restored.guide == SampleAdventure.guide)
        #expect(restored.guideEngine == "sample")
        #expect(restored.prepDone == ["Lee el guion"])
        #expect(restored.sessions.count == 1)
        let session = try #require(restored.sessions.first)
        #expect(session.currentSceneID == "e4")
        #expect(session.players.map(\.character) == ["Lucía Ferrer", "Tomás Llano", "Casimiro Vega"])
        #expect(session.notes.count == 4)
        #expect(session.chat.count == 2)
        // El retrato se encuentra por nombre, con o sin apellido.
        #expect(restored.portrait(for: "Marina") == Data([1, 2, 3]))
    }

    @Test func duplicateTitleIsMarked() throws {
        let store = try container()
        let adventure = SampleAdventure.make(in: store.mainContext, withSession: false)
        let archive = try AdventureArchive.decode(try AdventureArchive(adventure).encoded())
        let copy = archive.restore(into: store.mainContext, existingTitles: [SampleAdventure.title])
        #expect(copy.title == "\(SampleAdventure.title) (importada)")
    }

    @Test func rejectsForeignAndFutureFiles() {
        #expect(throws: AdventureArchive.Failure.unreadable) { try AdventureArchive.decode(Data("{\"hola\":1}".utf8)) }
        #expect(throws: AdventureArchive.Failure.newerVersion) { try AdventureArchive.decode(Data("{\"version\":99}".utf8)) }
    }

    @Test func fileNamesAreSafe() {
        #expect(AdventureArchive.fileName(for: "La luz: Punta/Negra?") == "La luz- Punta-Negra-")
        #expect(UTType.atrilAdventure.preferredFilenameExtension == "atril")
    }
}

struct SearchTests {
    private let index = ScriptIndex(script: SampleAdventure.script)

    @Test func findsScenesNPCsCluesAndScript() {
        let results = GuideSearch.search("lente", guide: SampleAdventure.guide, index: index)
        #expect(results.clues.contains { $0.title == "La lente sellada" })
        #expect(results.scenes.contains { $0.id == "e4" })
        #expect(!results.passages.isEmpty)
    }

    @Test func ignoresAccentsAndCase() {
        let results = GuideSearch.search("REMEDIOS taberna", guide: SampleAdventure.guide, index: index)
        #expect(results.scenes.map(\.id) == ["e2"])
        #expect(GuideSearch.search("parroquia san telmo", guide: SampleAdventure.guide, index: index).scenes.first?.id == "e3")
        #expect(GuideSearch.search("  ", guide: SampleAdventure.guide, index: index).isEmpty)
    }
}

struct AmbienceTests {
    @Test func suggestsFromTheScene() {
        let guide = SampleAdventure.guide
        #expect(Ambience.suggestion(for: guide.scene("e2")!) == .fire)
        #expect(Ambience.suggestion(for: guide.scene("e5")!) == .crypt)
        #expect(Ambience.suggestion(for: guide.scene("e6")!) == .sea)
        // El resumen menciona la cueva, pero la escena ocurre en el faro, junto al acantilado.
        #expect(Ambience.suggestion(for: guide.scene("e4")!) == .sea)
    }

    @Test(arguments: Ambience.allCases)
    func synthIsAudibleAndBounded(_ kind: Ambience) {
        let synth = AmbienceSynth(kind: kind, sampleRate: 48_000)
        synth.targetGain = 1
        let frames = 48_000 * 3
        var left = [Float](repeating: 0, count: frames)
        var right = [Float](repeating: 0, count: frames)
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in synth.render(left: l.baseAddress!, right: r.baseAddress!, frames: frames) }
        }
        let tail = left.suffix(48_000)
        let rms = (tail.map { $0 * $0 }.reduce(0, +) / Float(tail.count)).squareRoot()
        #expect(left.allSatisfy { abs($0) <= 1 && $0.isFinite })
        #expect(rms > 0.005, "\(kind) suena demasiado bajo: \(rms)")
    }

    @Test(arguments: [Ambience.sea, .crypt])
    func keepsEvolvingAfterHours(_ kind: Ambience) {
        // Con un reloj en Float, el sonido se congelaba a los pocos minutos de partida.
        let synth = AmbienceSynth(kind: kind, sampleRate: 48_000)
        synth.targetGain = 1
        synth.time = 3 * 3600
        let before = synth.time
        var left = [Float](repeating: 0, count: 96_000)
        var right = left
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in synth.render(left: l.baseAddress!, right: r.baseAddress!, frames: 96_000) }
        }
        #expect(abs(synth.time - before - 2) < 0.001)
        #expect(Set(left.suffix(1_000)).count > 500)
    }

    @Test func silentUntilAsked() {
        let synth = AmbienceSynth(kind: .wind, sampleRate: 48_000)
        var left = [Float](repeating: 1, count: 1_000)
        var right = left
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in synth.render(left: l.baseAddress!, right: r.baseAddress!, frames: 1_000) }
        }
        #expect(left.allSatisfy { $0 == 0 })
    }
}

struct PortraitTests {
    @Test func shrinksLargeImages() throws {
        let context = CGContext(data: nil, width: 2_000, height: 1_000, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.4, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2_000, height: 1_000))
        let png = NSMutableData()
        let destination = CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)

        let prepared = try #require(PortraitImage.prepared(png as Data))
        let source = try #require(CGImageSourceCreateWithData(prepared as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(max(image.width, image.height) == 768)
        #expect(prepared.count < (png as Data).count)
    }

    @Test func conceptDescribesWithoutSecrets() {
        let marina = SampleAdventure.guide.npcs.first { $0.name == "Marina Rivas" }!
        let concept = PortraitImage.concept(for: marina, system: .cthulhu)
        #expect(concept.contains("Marina Rivas"))
        #expect(concept.contains("años veinte"))
        #expect(!concept.contains(marina.secret))
    }
}

@MainActor
struct PrepSheetTests {
    @Test func upcomingStartsWhereTheTableStopped() {
        let ids = SessionPlanner.upcoming(SampleAdventure.guide, from: "e4", hours: 1.5)
        #expect(ids == ["e4", "e5"])
        #expect(SessionPlanner.upcoming(SampleAdventure.guide, from: nil, hours: 6).count == 6)
    }

    @Test func rendersPaginatedA4() throws {
        let content = PrepSheet.Content(
            title: SampleAdventure.title, subtitle: "Aventura completa", system: .cthulhu, guide: SampleAdventure.guide,
            sceneIDs: SampleAdventure.guide.scenes.map(\.id), recap: "La última vez…", includeOpening: true, portraits: [:]
        )
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("atril-hoja-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try PrepSheet.render(content, to: url)
        let document = try #require(PDFDocument(url: url))
        #expect(document.pageCount >= 2)
        let page = try #require(document.page(at: 0))
        #expect(page.bounds(for: .mediaBox).size == CGSize(width: 595, height: 842))
        #expect((document.string ?? "").contains("El faro de Punta Negra"))
    }
}
