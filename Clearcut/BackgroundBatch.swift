import Foundation
import BackgroundTasks

/// Lets a batch carry on cutting out after you leave the app, with its progress on the Lock
/// Screen (iOS 26's continued processing). Only compiled with the iOS 26 SDK (Xcode 26); before
/// that, and on older iOS, a batch pauses when you leave and carries on when you come back.
@MainActor
enum BackgroundBatch {
    /// "<bundle id>.batch": iOS only accepts a continued-processing name that starts with the
    /// app's own bundle id, so the store app and My Clearcut each get their own. Nil (and the batch
    /// just pauses in the background) if Info.plist doesn't list it, for example when an installer
    /// such as SideStore has changed the bundle id; registering an unlisted name would crash.
    static let identifier: String? = {
        guard let bundle = Bundle.main.bundleIdentifier,
              let allowed = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String]
        else { return nil }
        let id = bundle + ".batch"
        return allowed.contains(id) ? id : nil
    }()

    #if compiler(>=6.2)
    private static var task: AnyObject?
    private static var registered = false
    private static var submitted = false
    #endif

    /// Called whenever the batch's progress changes.
    static func update(store: BatchStore, idle: Bool) {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) { update26(store: store, idle: idle) }
        #endif
    }

    #if compiler(>=6.2)
    @available(iOS 26.0, *)
    private static func update26(store: BatchStore, idle: Bool) {
        let running = task as? BGContinuedProcessingTask
        guard !idle, let p = store.importing else {
            running?.setTaskCompleted(success: true)
            task = nil
            submitted = false
            return
        }
        let subtitle = "\(min(p.done + 1, p.total)) of \(p.total)"
        if let running {
            running.progress.totalUnitCount = Int64(p.total)
            running.progress.completedUnitCount = Int64(p.done)
            running.updateTitle("Cutting out photos", subtitle: subtitle)
            return
        }
        guard !submitted, let id = Self.identifier else { return }
        if !registered {
            registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: .main) { t in
                guard let t = t as? BGContinuedProcessingTask else { t.setTaskCompleted(success: false); return }
                // If iOS needs the time back, the batch simply resumes next time the app opens.
                t.expirationHandler = { t.setTaskCompleted(success: false) }
                MainActor.assumeIsolated {
                    BackgroundBatch.task = t
                    t.progress.totalUnitCount = 1
                }
            }
        }
        guard registered else { return }
        let request = BGContinuedProcessingTaskRequest(identifier: id, title: "Cutting out photos", subtitle: subtitle)
        request.strategy = .fail
        submitted = (try? BGTaskScheduler.shared.submit(request)) != nil
    }
    #endif
}
