import Foundation
#if os(iOS)
import UIKit
#endif

/// Evita que la pantalla se apague durante una partida o un análisis largo. Es un contador:
/// la pantalla vuelve a poder apagarse cuando ya nadie lo necesita.
@MainActor
enum KeepAwake {
    private static var holders = 0
    #if os(macOS)
    private static var activity: NSObjectProtocol?
    #endif

    static func acquire() {
        holders += 1
        guard holders == 1 else { return }
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = true
        #else
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.idleDisplaySleepDisabled, .userInitiated], reason: "Partida o análisis en curso"
        )
        #endif
    }

    static func release() {
        guard holders > 0 else { return }
        holders -= 1
        guard holders == 0 else { return }
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = false
        #else
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
        #endif
    }
}
