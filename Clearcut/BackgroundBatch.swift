import Foundation
import BackgroundTasks

/// Lets a batch carry on cutting out after you leave the app, with its progress on the Lock
/// Screen (iOS 26's continued processing). Only compiled with the iOS 26 SDK (Xcode 26); before
/// that, and on older iOS, a batch pauses when you leave and carries on when you come back.
@MainActor
enum BackgroundBatch {
    static let identifier = "app.clearcut.photos.batch"

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
        guard !submitted else { return }
        if !registered {
            registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { t in
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
        let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: "Cutting out photos", subtitle: subtitle)
        request.strategy = .fail
        submitted = (try? BGTaskScheduler.shared.submit(request)) != nil
    }
    #endif
}
