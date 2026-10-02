import SwiftUI

@main
struct AssistenteWatchApp: App {
    @StateObject private var store = Store()
    var body: some Scene {
        WindowGroup {
            Group {
                if store.signedIn { RootView() } else { LoginView() }
            }
            .environmentObject(store)
        }
    }
}
