import SwiftUI

@main
struct ClearcutApp: App {
    @StateObject private var library: BackgroundLibrary
    @StateObject private var store: BatchStore

    init() {
        let lib = BackgroundLibrary()
        _library = StateObject(wrappedValue: lib)
        _store = StateObject(wrappedValue: BatchStore(library: lib))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(library)
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
        .alert("Clearcut", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
            Button("OK", role: .cancel) { store.message = nil }
        } message: {
            Text(store.message ?? "")
        }
    }
}
