import Foundation
#if os(iOS)
    import os
    import UIKit
#endif

/// Debug-only memory-headroom and thermal logging into Pulse's console.
///
/// The low-end profiling floor is an iPhone SE (2nd generation) — A13, 3 GB —
/// where the question worth answering before a jetsam is how close the app
/// runs to its limit, and whether the device was hot when it did. Each entry
/// records `os_proc_available_memory()` (bytes the process can still allocate
/// before the system terminates it — the number jetsam actually enforces, not
/// the device's physical RAM) and `ProcessInfo.thermalState`.
///
/// Logged at start, on every thermal-state change, on every memory warning,
/// and every ``samplingInterval`` while the app runs. Observing only: nothing
/// here changes the app's behaviour, which is why it sits beside Pulse in this
/// debug-only package rather than in a reusable one. Compiles to a no-op in
/// Release, so a profiling run on a Release build is not perturbed by its
/// timer.
@MainActor
public enum DebugResourceMonitor {
    /// Modest on purpose: often enough to see headroom trend across a listening
    /// session, rare enough not to be a wakeup source worth noticing.
    public static let samplingInterval: Duration = .seconds(30)

    #if DEBUG
        private static var observers: [any NSObjectProtocol] = []
        private static var samplingTask: Task<Void, Never>?
    #endif

    /// Starts logging. Idempotent; call once from app bootstrap.
    public static func start() {
        #if DEBUG
            guard samplingTask == nil else { return }
            record(.launch)
            let center = NotificationCenter.default
            observers.append(center.addObserver(
                forName: ProcessInfo.thermalStateDidChangeNotification,
                object: nil,
                queue: .main,
            ) { _ in
                MainActor.assumeIsolated { record(.thermalStateChanged) }
            })
            #if os(iOS)
                observers.append(center.addObserver(
                    forName: UIApplication.didReceiveMemoryWarningNotification,
                    object: nil,
                    queue: .main,
                ) { _ in
                    MainActor.assumeIsolated { record(.memoryWarning) }
                })
            #endif
            samplingTask = Task {
                while Task.isCancelled == false {
                    try? await Task.sleep(for: samplingInterval)
                    guard Task.isCancelled == false else { return }
                    record(.periodic)
                }
            }
        #endif
    }

    #if DEBUG
        private enum Trigger: String {
            case launch
            case thermalStateChanged = "thermal state changed"
            case memoryWarning = "memory warning"
            case periodic
        }

        private static func record(_ trigger: Trigger) {
            let thermalState = ProcessInfo.processInfo.thermalState
            var metadata = [
                "trigger": trigger.rawValue,
                "thermalState": thermalState.debugName,
            ]
            let headroom = availableMemory.map { "\(formatBytes($0)) available" }
                ?? "headroom unavailable (no process limit)"
            metadata["availableMemory"] = availableMemory.map(formatBytes) ?? "unavailable"
            if trigger == .launch {
                metadata["physicalMemory"] = formatBytes(ProcessInfo.processInfo.physicalMemory)
            }
            let isWarning = trigger == .memoryWarning
                || thermalState == .serious
                || thermalState == .critical
            DebugConsoleLog.record(
                "Resources (\(trigger.rawValue)): \(headroom), thermal \(thermalState.debugName)",
                label: "resources",
                isWarning: isWarning,
                metadata: metadata,
            )
        }

        /// `nil` where there is no limit to measure against — never `0`, which
        /// would read as "out of memory". The call returns `0` when the process
        /// has no jetsam limit, which is every Simulator run (verified on an
        /// iPhone SE simulator: it logged "Zero kB"), and doesn't exist at all
        /// on the macOS host build of this package. Only a device gives a real
        /// number.
        private static var availableMemory: UInt64? {
            #if os(iOS)
                let available = os_proc_available_memory()
                return available > 0 ? UInt64(available) : nil
            #else
                return nil
            #endif
        }

        private static func formatBytes(_ bytes: UInt64) -> String {
            Int64(clamping: bytes).formatted(.byteCount(style: .memory))
        }
    #endif
}

#if DEBUG
    private extension ProcessInfo.ThermalState {
        var debugName: String {
            switch self {
            case .nominal: "nominal"
            case .fair: "fair"
            case .serious: "serious"
            case .critical: "critical"
            @unknown default: "unknown (\(rawValue))"
            }
        }
    }
#endif
