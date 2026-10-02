import SwiftUI

@main
struct AssistenteWatchApp: App {
    @StateObject private var store = Store()
    var body: some Scene {
        WindowGroup {
            Group {
                if !store.signedIn { LoginView() } else if let code = store.pairingCode { PairingView(code: code) } else { RootView() }
            }
            .environmentObject(store)
        }
    }
}
