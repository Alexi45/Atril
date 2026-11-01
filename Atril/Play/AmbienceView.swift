import SwiftUI

struct AmbienceView: View {
    let scene: AdventureGuide.Scene?
    let tint: Color
    @AppStorage(AmbiencePlayer.followKey) private var followsScene = false
    private var player: AmbiencePlayer { .shared }

    var body: some View {
        @Bindable var player = player
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Ambiente").font(.title3.weight(.semibold))
                    Spacer()
                    if !player.active.isEmpty {
                        Button("Parar todo", systemImage: "stop.fill") { player.stopAll() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }

                if let scene, let suggestion = Ambience.suggestion(for: scene) {
                    Button {
                        player.set([suggestion])
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: suggestion.symbol).font(.title3)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Sugerido: \(suggestion.name)").font(.callout.weight(.semibold))
                                Text("Por «\(scene.title)»").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            if player.isPlaying(suggestion) { Image(systemName: "speaker.wave.2.fill") }
                        }
                        .padding(12)
                        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(tint)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
                    ForEach(Ambience.allCases) { ambience in
                        let on = player.isPlaying(ambience)
                        Button {
                            player.toggle(ambience)
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: ambience.symbol)
                                    .font(.title2)
                                    .symbolEffect(.variableColor.iterative, isActive: on)
                                Text(ambience.name).font(.callout.weight(.medium))
                            }
                            .frame(maxWidth: .infinity, minHeight: 72)
                            .foregroundStyle(on ? Color.white : Color.primary)
                            .background(on ? tint : Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(title: "Volumen", symbol: "speaker.wave.2")
                    Slider(value: $player.volume, in: 0...1)
                }

                Toggle(isOn: $followsScene) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cambiar con cada escena")
                        Text("Al pasar de escena suena el ambiente que le encaja, si hay alguno.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Los sonidos se generan en el momento: se pueden combinar (mar y viento, cripta y latido…).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
        }
    }
}
