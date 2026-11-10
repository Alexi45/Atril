import SwiftData
import SwiftUI

@main
struct AtrilApp: App {
    @State private var analysis = AnalysisCenter()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        KeychainStore.syncFlag()
        #if os(iOS)
        // Las cachés (guías, índices, miniaturas) se rehacen solas: si falta memoria, se sueltan.
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil) { _ in
            CacheRegistry.purgeAll()
        }
        #endif
        #if DEBUG
        // Diagnóstico de la IA: no necesita ventana, así funciona lanzado desde un terminal.
        if CommandLine.arguments.contains("-probeAI") {
            Task { @MainActor in
                await AIProbe.run()
                exit(0)
            }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(analysis)
                .onChange(of: scenePhase) {
                    if scenePhase == .active { AppleAI.refreshStatus() }
                }
        }
        .modelContainer(for: [Adventure.self, PlaySession.self, Portrait.self])
        #if os(macOS)
        .defaultSize(width: 1280, height: 820)
        #endif

        #if os(macOS)
        // Ventana para los jugadores: se puede llevar a otra pantalla o a la tele.
        WindowGroup("Para los jugadores", id: "handout", for: Handout.self) { $handout in
            if let handout {
                PlayerScreenView(handout: handout)
            }
        }
        .defaultSize(width: 1100, height: 760)

        Settings {
            SettingsView(showsDone: false)
                .frame(width: 520, height: 520)
        }
        #endif
    }
}
