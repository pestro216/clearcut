import SwiftUI

@main
struct ClearcutApp: App {
    @StateObject private var library: BackgroundLibrary
    @StateObject private var store: BatchStore

    init() {
        let lib = BackgroundLibrary()
        _library = StateObject(wrappedValue: lib)
        _store = StateObject(wrappedValue: BatchStore(library: lib))
        CrashReports.shared.start()
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
    @ObservedObject private var router = AppRouter.shared
    @State private var demoTool: Tool?

    var body: some View {
        Group {
            if store.items.isEmpty && store.importing == nil {
                HomeView()
            } else {
                BatchView()
            }
        }
        .fullScreenCover(item: $demoTool) { t in ToolScreen(tool: t, startID: nil) }
        .fullScreenCover(isPresented: $router.openCamera) { RailCameraScreen() }
        .onChange(of: store.importing == nil) { _, idle in BackgroundBatch.update(store: store, idle: idle) }
        .onChange(of: store.importing?.done) { _, _ in BackgroundBatch.update(store: store, idle: store.importing == nil) }
        .task {
            // Automated simulator check only: load a folder of photos and optionally open a tool.
            let env = ProcessInfo.processInfo.environment
            guard let dir = env["CLEARCUT_DEMO_DIR"] else { return }
            let urls = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).sorted()
                .filter { $0.hasSuffix(".jpg") }.map { URL(fileURLWithPath: dir).appendingPathComponent($0) }
            store.addFiles(urls)
            if let t = env["CLEARCUT_DEMO_TOOL"], let tool = Tool(rawValue: t) {
                while store.importing != nil { try? await Task.sleep(nanoseconds: 300_000_000) }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                demoTool = tool
            }
        }
        .alert("Clearcut", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
            Button("OK", role: .cancel) { store.message = nil }
        } message: {
            Text(store.message ?? "")
        }
    }
}
