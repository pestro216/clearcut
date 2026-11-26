import Foundation
import os

/// Memory readings, written to the device log so a crash on the phone can be traced over USB
/// (`idevicesyslog`, look for "Clearcut memory"). iOS closes an app that goes over its limit
/// (2348 MB on an iPhone 11) without a crash report.
public enum Diagnostics {
    private static let log = Logger(subsystem: "app.clearcut.photos", category: "memory")

    /// Memory this app is using, in megabytes (what iOS counts against the limit).
    public static func footprintMB() -> Int? { vmInfo().map { Int($0.phys_footprint / 1_048_576) } }

    /// The most memory this app has used at any moment since it started, in megabytes. Catches
    /// the brief spike while the network runs, which the readings between stages can't see.
    public static func peakMB() -> Int? { vmInfo().map { Int($0.ledger_phys_footprint_peak / 1_048_576) } }

    private static func vmInfo() -> task_vm_info_data_t? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? info : nil
    }

    /// Memory the app may still use before iOS closes it, in megabytes. nil where unknown
    /// (the simulator and the Mac report nothing useful).
    public static func headroomMB() -> Int? {
        #if os(iOS) && !targetEnvironment(simulator)
        let v = os_proc_available_memory()
        return v > 0 ? v / 1_048_576 : nil
        #else
        return nil
        #endif
    }

    /// True unless the app is known to have less than `mb` megabytes to spare.
    public static func canSpare(_ mb: Int) -> Bool {
        guard let h = headroomMB() else { return true }
        return h >= mb
    }

    private static let clockLock = NSLock()
    private static var lastNote = Date()

    /// Logs memory and the seconds since the previous note, so the log shows where time goes.
    public static func note(_ stage: String) {
        let f = footprintMB() ?? -1, h = headroomMB() ?? -1, pk = peakMB() ?? -1
        clockLock.lock()
        let now = Date(), dt = now.timeIntervalSince(lastNote)
        lastNote = now
        clockLock.unlock()
        let secs = String(format: "%.2f", dt)
        log.notice("Clearcut memory: \(stage, privacy: .public): using \(f, privacy: .public) MB, peak \(pk, privacy: .public) MB, headroom \(h, privacy: .public) MB, \(secs, privacy: .public) s since last note")
    }
}
