import SwiftData
import SwiftUI

struct ImportView: View {
    let onCreated: (Adventure) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AnalysisCenter.self) private var analysis

    @State private var title = ""
    @State private var system: GameSystem = .cthulhu
    @State private var script = ""
    @State private var fileName: String?
    @State private var showPicker = false
    @State private var importError: String?
    @State private var loadingMessage: String?
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        showPicker = true
                    } label: {
                        Label(fileName ?? "Elegir archivo…", systemImage: fileName == nil ? "doc.badge.plus" : "doc.text.fill")
                    }
                    .disabled(loadingMessage != nil)
                    if let loadingMessage {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text(loadingMessage).font(.callout).foregroundStyle(.secondary)
                            Spacer()
                            Button("Cancelar") { loadTask?.cancel() }.buttonStyle(.borderless)
                        }
                    }
                    TextEditor(text: $script)
                        .font(.callout)
                        .frame(minHeight: 180)
                        .overlay(alignment: .topLeading) {
                            if script.isEmpty {
                                Text("…o pega aquí el texto del guion")
                                    .font(.callout)
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                } header: {
                    Text("Guion")
                } footer: {
                    if let importError {
                        Text(importError).foregroundStyle(.red)
                    } else if !script.isEmpty {
                        Text("\(wordCount.formatted()) palabras")
                    } else {
                        Text("PDF (también escaneados), TXT, Markdown o RTF.")
                    }
                }

                Section("Aventura") {
                    TextField("Título", text: $title)
                    Picker("Sistema", selection: $system) {
                        ForEach(GameSystem.allCases) { system in
                            Label(system.name, systemImage: system.symbol).tag(system)
                        }
                    }
                }

                Section {
                    let backend = AIBackend.current
                    Label(backend == .basic
                          ? "Al crearla, Atril organiza el guion en escenas, PNJ y pistas al momento, sin conexión."
                          : "Al crearla tendrás una guía al momento, y la \(backend.label) la irá mejorando mientras lee el guion entero.",
                          systemImage: backend.symbol)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Nueva aventura")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crear", action: create)
                        .disabled(!canCreate || loadingMessage != nil)
                }
            }
            .fileImporter(isPresented: $showPicker, allowedContentTypes: ScriptImporter.allowedTypes) { result in
                load(result)
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 600)
        #endif
    }

    private var wordCount: Int { script.split(whereSeparator: \.isWhitespace).count }

    private var canCreate: Bool {
        !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func load(_ result: Result<URL, Error>) {
        importError = nil
        guard let url = try? result.get() else {
            importError = ScriptImporter.Failure.unreadable.localizedDescription
            return
        }
        loadingMessage = "Leyendo el archivo…"
        loadTask = Task {
            do {
                script = try await ScriptImporter.load(url) { message in loadingMessage = message }
                fileName = url.lastPathComponent
                if title.isEmpty { title = ScriptImporter.suggestedTitle(for: url) }
                let lower = script.lowercased()
                if lower.contains("cordura") || lower.contains("cthulhu") || lower.contains("investigador") {
                    system = .cthulhu
                } else if lower.contains("clase de armadura") || lower.contains("dungeon") || lower.contains(" cd ") {
                    system = .dnd
                }
            } catch is CancellationError {
            } catch {
                importError = error.localizedDescription
            }
            loadingMessage = nil
        }
    }

    private func create() {
        let adventure = Adventure(
            title: title.trimmingCharacters(in: .whitespaces),
            system: system,
            script: ScriptImporter.clean(script),
            sourceFileName: fileName
        )
        context.insert(adventure)
        analysis.start(adventure)
        onCreated(adventure)
        dismiss()
    }
}
