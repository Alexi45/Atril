import SwiftUI

struct TutorPanel: View {
    @Bindable var controller: PlayController
    @FocusState private var inputFocused: Bool
    @State private var showSettings = false
    @State private var confirmClear = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            conversation
            Divider()
            composer
        }
        .background(Color.canvas)
        .sheet(isPresented: $showSettings, onDismiss: controller.refreshBackend) { NavigationStack { SettingsView() } }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "graduationcap.fill")
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(controller.system.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                Text("Tutor").font(.headline)
                Label(controller.backend.label, systemImage: controller.backend.symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Menu {
                Button("Nueva conversación", systemImage: "square.and.pencil") { confirmClear = true }
                    .disabled(controller.messages.isEmpty || controller.isWaiting)
                Button("Ajustes del tutor", systemImage: "gearshape") { showSettings = true }
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .confirmationDialog("¿Empezar una conversación nueva?", isPresented: $confirmClear) {
            Button("Borrar conversación", role: .destructive) { controller.clearChat() }
        } message: {
            Text("Las notas y el estado de la partida se mantienen.")
        }
    }

    // MARK: Conversación

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if controller.messages.isEmpty && !controller.isWaiting {
                        intro
                    }
                    ForEach(controller.messages) { message in
                        MessageView(message: message, tint: controller.system.accent)
                            .id(message.id)
                    }
                    if controller.isWaiting {
                        pendingAnswer.id("pending")
                    }
                    if let error = controller.tutorError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(14)
            }
            .onChange(of: controller.messages.count) { scrollToBottom(proxy) }
            .onChange(of: controller.streamingText) { proxy.scrollTo("bottom", anchor: .bottom) }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.snappy) { proxy.scrollTo("bottom", anchor: .bottom) }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("¿En qué te ayudo?").font(.title3.weight(.semibold))
            Text("Sé en qué escena estáis, qué pistas tenéis y lo que has anotado. Pregúntame cualquier cosa o usa un atajo.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if controller.backend == .basic {
                Text(AppleAI.status.unavailableReason.map { "\($0) Mientras tanto respondo con la guía, las reglas y el guion, sin conexión." }
                     ?? "Respondo con la guía, las reglas y el guion, sin conexión.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, 4)
    }

    private var pendingAnswer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if controller.streamingText.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(controller.isThinking ? "Pensando…" : "Consultando el guion…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                MarkdownText(text: controller.streamingText)
            }
            Button("Detener", systemImage: "stop.circle") { controller.cancelTutor() }
                .font(.caption)
                .buttonStyle(.borderless)
        }
        .card(padding: 12)
    }

    // MARK: Entrada

    private var composer: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(QuickAction.all) { action in
                        Button {
                            use(action)
                        } label: {
                            Label(action.title, systemImage: action.symbol)
                                .font(.callout.weight(.medium))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 7)
                                .background(controller.system.accent.opacity(0.1), in: Capsule())
                                .foregroundStyle(controller.system.accent)
                        }
                        .buttonStyle(.plain)
                        .disabled(controller.isWaiting)
                    }
                }
                .padding(.horizontal, 14)
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Pregunta al tutor…", text: $controller.draft, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.hairline))
                    .focused($inputFocused)
                    .onSubmit { controller.send(controller.draft) }
                Button {
                    controller.send(controller.draft)
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 30))
                }
                .buttonStyle(.plain)
                .foregroundStyle(controller.system.accent)
                .disabled(controller.draft.trimmingCharacters(in: .whitespaces).isEmpty || controller.isWaiting)
                .keyboardShortcut(.return, modifiers: .command)
                .accessibilityLabel("Enviar")
            }
            .padding(.horizontal, 14)
        }
        .padding(.vertical, 10)
    }

    private func use(_ action: QuickAction) {
        if action.needsDetail {
            controller.draft = action.prompt
            inputFocused = true
        } else {
            controller.send(action.prompt)
        }
    }
}

private struct MessageView: View {
    let message: TutorMessage
    let tint: Color

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(message.display)
                    .font(.callout)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .textSelection(.enabled)
            }
        case .assistant:
            MarkdownText(text: message.display)
                .font(.callout)
                .card(padding: 12)
        }
    }
}
