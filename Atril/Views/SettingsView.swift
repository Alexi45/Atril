import SwiftUI

struct SettingsView: View {
    /// En la ventana de Ajustes de macOS no hace falta botón para cerrar.
    var showsDone = true
    @Environment(\.dismiss) private var dismiss
    @AppStorage(KeychainStore.hasKeyFlag) private var hasKey = false
    @AppStorage(TutorDepth.storageKey) private var depth: TutorDepth = .fast
    @AppStorage(AppleAI.allowCloudKey) private var allowCloud = true
    @AppStorage(AIBackend.useClaudeKey) private var useClaude = false
    @AppStorage(Narrator.voiceKey) private var voiceID = ""
    @AppStorage(Narrator.rateKey) private var narratorRate = 0.9

    @State private var keyDraft = ""
    @State private var testState: TestState = .idle
    @State private var status = AppleAI.status

    enum TestState: Equatable {
        case idle, testing, ok
        case failed(String)
    }

    var body: some View {
        Form {
            Section {
                let backend = AIBackend.current
                LabeledContent("Ahora responde") {
                    Label(backend.label, systemImage: backend.symbol)
                        .foregroundStyle(.secondary)
                }
                if let reason = status.unavailableReason {
                    Label(reason, systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if AppleAI.cloudEntitled {
                    Toggle("Usar la nube privada de Apple", isOn: $allowCloud)
                        .onChange(of: allowCloud) { status = AppleAI.status }
                }
            } header: {
                Text("IA integrada")
            } footer: {
                Text("Atril usa la IA de Apple: sin cuentas ni pagos. La nube privada (iPadOS y macOS 27) tiene más memoria y lee guiones largos de una vez; Apple no guarda lo que se le envía. Sin ella, todo se procesa en el dispositivo. Si no hay Apple Intelligence, el tutor responde con la guía, las reglas y el guion, sin conexión.")
            }

            Section {
                Toggle("Usar Claude en lugar de la IA de Apple", isOn: $useClaude)
                if useClaude {
                    if hasKey {
                        LabeledContent("Clave guardada") {
                            Text("sk-ant-…\(String(KeychainStore.apiKey.suffix(4)))").monospaced().foregroundStyle(.secondary)
                        }
                        HStack {
                            Button("Probar conexión", action: test)
                                .disabled(testState == .testing)
                            Spacer()
                            Button("Borrar clave", role: .destructive) {
                                KeychainStore.apiKey = ""
                                testState = .idle
                            }
                        }
                    } else {
                        SecureField("Clave de Anthropic (sk-ant-…)", text: $keyDraft)
                            .textContentType(.password)
                            .autocorrectionDisabled()
                        Button("Guardar clave") {
                            KeychainStore.apiKey = keyDraft
                            keyDraft = ""
                            test()
                        }
                        .disabled(keyDraft.trimmingCharacters(in: .whitespaces).count < 20)
                    }
                    switch testState {
                    case .idle: EmptyView()
                    case .testing: Label("Comprobando…", systemImage: "hourglass").foregroundStyle(.secondary)
                    case .ok: Label("Conexión correcta", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    case .failed(let message): Label(message, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                    }
                    Picker("Velocidad", selection: $depth) {
                        ForEach(TutorDepth.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text(depth.detail).font(.callout).foregroundStyle(.secondary)
                }
            } header: {
                Text("Avanzado · opcional")
            } footer: {
                Text(useClaude
                     ? "Claude lee guiones de cualquier longitud y razona más a fondo, pero necesita tu propia clave de pago (platform.claude.com). Se guarda en el llavero."
                     : "No hace falta: la IA de Apple ya viene incluida.")
            }

            Section {
                let voices = Narrator.spanishVoices
                Picker("Voz", selection: $voiceID) {
                    Text("Automática").tag("")
                    ForEach(voices, id: \.identifier) { voice in
                        Text("\(voice.name) · \(Self.region(voice.language))\(voice.quality == .premium ? " · premium" : voice.quality == .enhanced ? " · mejorada" : "")")
                            .tag(voice.identifier)
                    }
                }
                LabeledContent("Velocidad") {
                    Slider(value: $narratorRate, in: 0.6...1.2, step: 0.05)
                        .frame(maxWidth: 220)
                }
                Button("Probar la voz", systemImage: "speaker.wave.2") {
                    Narrator.shared.speak("El camino del acantilado termina en una casa encalada. La puerta se abre antes de que llaméis.", id: "settings-test")
                }
            } header: {
                Text("Narrador")
            } footer: {
                Text("Lee en voz alta el texto de las escenas y los resúmenes. Para una voz más natural, descarga una voz «mejorada» o «premium» en español en Ajustes del sistema › Accesibilidad › Contenido leído.")
            }

            Section("Privacidad") {
                Label("Los guiones, las notas y las partidas se guardan solo en este dispositivo.", systemImage: "lock")
                Label("Con la IA en el dispositivo no sale nada de él. La nube privada de Apple procesa las peticiones sin guardarlas.", systemImage: "cpu")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .navigationTitle("Ajustes")
        .onAppear { status = AppleAI.status }
        .toolbar {
            if showsDone {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
            }
        }
    }

    static func region(_ language: String) -> String {
        Locale(identifier: "es").localizedString(forIdentifier: language) ?? language
    }

    private func test() {
        testState = .testing
        let key = KeychainStore.apiKey
        Task {
            do {
                try await TutorService.testConnection(apiKey: key)
                testState = .ok
            } catch {
                testState = .failed(error.localizedDescription)
            }
        }
    }
}
