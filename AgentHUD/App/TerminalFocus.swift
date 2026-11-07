import AppKit
import HUDCore

/// The machine as `TerminalFocus` sees it: the process table, plus AppKit for which processes are apps.
struct LiveTerminalSystem: TerminalSystem {
    func process(_ pid: Int32) -> ProcessRecord? { ProcessTable.process(pid) }
    func environment(_ pid: Int32) -> [String: String] { ProcessTable.environment(pid) }
    func executablePath(_ pid: Int32) -> String? { ProcessTable.executablePath(pid) }
    func run(_ executable: String, _ arguments: [String]) -> String? { ProcessTable.run(executable, arguments) }

    func appBundleId(_ pid: Int32) -> String? {
        guard let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular else { return nil }
        return app.bundleIdentifier ?? ""
    }
}

extension TerminalFocus {
    /// Runs off the main thread: the process walk is cheap, but tmux and osascript are child processes.
    /// Beeps when there is nothing to bring forward.
    static func show(pid: Int32) {
        Task.detached {
            let outcome = try? focus(pid: pid, on: LiveTerminalSystem())
            await MainActor.run {
                guard let outcome, let app = NSRunningApplication(processIdentifier: outcome.appPid) else {
                    return NSSound.beep()
                }
                // macOS 14 only lets an app come forward when the active one yields to it.
                NSApp.yieldActivation(to: app)
                app.activate()
            }
        }
    }
}
