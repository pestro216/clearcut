import SwiftUI
import MetricKit

/// Crash and exit reports from iOS (MetricKit). iOS delivers them to the app, usually a day
/// later; they are kept on the phone and only leave it if you send them from the About screen.
/// Nothing is collected or sent automatically, so the "Data Not Collected" label stays true.
final class CrashReports: NSObject, MXMetricManagerSubscriber {
    static let shared = CrashReports()

    static var folder: URL {
        let fm = FileManager.default
        let support = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? fm.temporaryDirectory
        let u = support.appendingPathComponent("CrashReports", isDirectory: true)
        try? fm.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    func start() { MXMetricManager.shared.add(self) }

    /// Crashes and hangs.
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for p in payloads { save(p.jsonRepresentation(), kind: "crash", end: p.timeStampEnd) }
    }

    /// Daily summaries; these count the times iOS closed the app for using too much memory.
    func didReceive(_ payloads: [MXMetricPayload]) {
        for p in payloads { save(p.jsonRepresentation(), kind: "daily", end: p.timeStampEnd) }
    }

    private func save(_ json: Data, kind: String, end: Date) {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmm"
        f.locale = Locale(identifier: "en_GB_POSIX")
        let url = CrashReports.folder.appendingPathComponent("clearcut-\(kind)-\(f.string(from: end)).json")
        try? json.write(to: url, options: .atomic)
    }

    static func files() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    static func deleteAll() {
        for u in files() { try? FileManager.default.removeItem(at: u) }
    }
}

/// The About screen's part about crash reports.
struct CrashReportsSection: View {
    @State private var files: [URL] = []

    private var crashes: Int { files.filter { $0.lastPathComponent.contains("-crash-") }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Crash reports").font(.system(size: 17, weight: .semibold))
            Text(files.isEmpty
                 ? "None so far. If \(AppName.display) closes unexpectedly, iOS gives it a report, usually the next day. Reports stay on your phone unless you send them."
                 : "\(crashes == 1 ? "1 crash report" : "\(crashes) crash reports") and \(files.count - crashes) daily summaries from iOS. They stay on your phone unless you send them, and hold no photos.")
                .font(.system(size: 15)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            if !files.isEmpty {
                HStack(spacing: 18) {
                    ShareLink(items: files) { Text("Send reports").font(.system(size: 15, weight: .semibold)) }
                    Button("Delete reports") { CrashReports.deleteAll(); files = [] }.font(.system(size: 15))
                }
                .foregroundStyle(Theme.ink)
            }
        }
        .onAppear { files = CrashReports.files() }
    }
}
