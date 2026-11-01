import ImageIO
import ImagePlayground
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

enum PortraitImage {
    /// Reduce la imagen a `maxPixel` de lado y la guarda como JPEG: un retrato no necesita más
    /// y así la aventura exportada no pesa demasiado.
    static func prepared(_ data: Data, maxPixel: Int = 768) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// Descripción para Image Playground: aspecto, papel y época, sin secretos de la trama.
    static func concept(for npc: AdventureGuide.NPC, system: GameSystem) -> String {
        let era: String = switch system {
        case .cthulhu: "retrato de un personaje de los años veinte, ambiente de misterio"
        case .dnd: "retrato de un personaje de fantasía medieval"
        case .other: "retrato de un personaje de rol"
        }
        return [npc.name, npc.role, npc.look, era].map(\.trimmed).filter { !$0.isEmpty }.joined(separator: ". ")
    }
}

extension Image {
    init?(portraitData data: Data) {
        #if os(iOS)
        guard let image = UIImage(data: data) else { return nil }
        self.init(uiImage: image)
        #else
        guard let image = NSImage(data: data) else { return nil }
        self.init(nsImage: image)
        #endif
    }
}

/// Retrato redondo, o las iniciales si no hay imagen.
struct PortraitAvatar: View {
    let name: String
    let data: Data?
    var size: CGFloat = 44
    var tint: Color = .accentColor

    var body: some View {
        Group {
            if let data, let image = Image(portraitData: data) {
                image.resizable().scaledToFill()
            } else {
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(tint.opacity(0.14))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.hairline))
        .accessibilityHidden(true)
    }

    private var initials: String {
        let words = name.split(separator: " ").filter { $0.first?.isUppercase == true }
        return String(words.prefix(2).compactMap(\.first))
    }
}

/// Retrato de un PNJ con su menú: crearlo con Image Playground, elegir una imagen, enseñarlo
/// a los jugadores o quitarlo.
struct PortraitControl: View {
    let npc: AdventureGuide.NPC
    @Bindable var adventure: Adventure
    var size: CGFloat = 64

    @State private var showPlayground = false
    @State private var playgroundSupported = false
    @State private var photo: PhotosPickerItem?
    @State private var presented: Handout?

    private var data: Data? { adventure.portrait(for: npc.name) }

    var body: some View {
        Menu {
            if playgroundSupported {
                Button("Crear retrato con Image Playground…", systemImage: "apple.image.playground") { showPlayground = true }
            }
            PhotosPicker(selection: $photo, matching: .images) {
                Label("Elegir una imagen…", systemImage: "photo")
            }
            if let data {
                Button("Enseñar a los jugadores", systemImage: "rectangle.on.rectangle.angled") {
                    presented = Handout(title: npc.name, body: "", style: .portrait, imageData: data)
                }
                Button("Quitar retrato", systemImage: "trash", role: .destructive) {
                    adventure.setPortrait(nil, for: npc.name)
                }
            }
        } label: {
            PortraitAvatar(name: npc.name, data: data, size: size, tint: adventure.system.accent)
                .overlay(alignment: .bottomTrailing) {
                    if data == nil {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: size * 0.28))
                            .foregroundStyle(.white, adventure.system.accent)
                    }
                }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Retrato de \(npc.name)")
        .modifier(PlaygroundSheet(isPresented: $showPlayground, isSupported: $playgroundSupported,
                                  concept: PortraitImage.concept(for: npc, system: adventure.system)) { data in
            adventure.setPortrait(PortraitImage.prepared(data) ?? data, for: npc.name)
        })
        .onChange(of: photo) {
            guard let photo else { return }
            Task {
                if let data = try? await photo.loadTransferable(type: Data.self) {
                    adventure.setPortrait(PortraitImage.prepared(data) ?? data, for: npc.name)
                }
                self.photo = nil
            }
        }
        .handoutPresenter($presented)
    }
}

/// Image Playground solo existe desde iPadOS 18.1 / macOS 15.1 y en equipos con Apple
/// Intelligence: en el resto, la opción simplemente no aparece.
private struct PlaygroundSheet: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var isSupported: Bool
    let concept: String
    let onImage: (Data) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.1, macOS 15.1, *) {
            content
                .modifier(PlaygroundSupport(isSupported: $isSupported))
                .imagePlaygroundSheet(isPresented: $isPresented, concepts: [.extracted(from: concept, title: nil)]) { url in
                    if let data = try? Data(contentsOf: url) { onImage(data) }
                }
        } else {
            content
        }
    }
}

@available(iOS 18.1, macOS 15.1, *)
private struct PlaygroundSupport: ViewModifier {
    @Environment(\.supportsImagePlayground) private var supported
    @Binding var isSupported: Bool

    func body(content: Content) -> some View {
        content
            .onAppear { isSupported = supported }
            .onChange(of: supported) { isSupported = supported }
    }
}
