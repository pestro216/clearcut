import SwiftUI

@main
struct ClearcutApp: App {
    @StateObject private var store = BatchStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .tint(Theme.ink)
                .preferredColorScheme(.light)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var store: BatchStore

    var body: some View {
        Group {
            if store.items.isEmpty && store.importing == nil {
                HomeView()
            } else {
                BatchView()
            }
        }
        .alert("Clearcut", isPresented: Binding(
            get: { store.message != nil },
            set: { if !$0 { store.message = nil } }
        )) {
            Button("OK", role: .cancel) { store.message = nil }
        } message: {
            Text(store.message ?? "")
        }
    }
}
