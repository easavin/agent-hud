import Foundation

/// One row of the process table.
public struct ProcessRecord: Sendable, Equatable {
    public var pid: Int32
    public var parent: Int32
    /// The short command name, `p_comm`: "claude", "zsh", "tmux", "Terminal".
    public var command: String
    /// "/dev/ttys012", or nil for a process with no controlling terminal.
    public var tty: String?

    public init(pid: Int32, parent: Int32, command: String, tty: String?) {
        self.pid = pid
        self.parent = parent
        self.command = command
        self.tty = tty
    }
}

/// What `TerminalFocus` needs from the machine. The app supplies the live one; tests supply a fake.
public protocol TerminalSystem {
    func process(_ pid: Int32) -> ProcessRecord?
    func environment(_ pid: Int32) -> [String: String]
    func executablePath(_ pid: Int32) -> String?
    /// The bundle id when `pid` is a regular app with a Dock icon, "" for one without a bundle id, nil otherwise.
    func appBundleId(_ pid: Int32) -> String?
    /// Runs a command to completion. Standard output on a zero exit, nil on anything else.
    @discardableResult func run(_ executable: String, _ arguments: [String]) -> String?
}

/// Works out which terminal is running a session and selects its tab: the Terminal.app or iTerm2 tab whose
/// tty it owns, and for a session inside tmux, the pane it runs in, switched to on a client that can show it.
/// Any other terminal (Ghostty, kitty, an editor's built-in one) is only identified, not navigated.
///
/// This is the one place the app acts on anything outside itself. It still never writes into `~/.claude`
/// and never touches the network: it reads the process table, runs `tmux` and `osascript`, and names an app.
public enum TerminalFocus {
    public enum Failure: Error, Equatable {
        case notRunning
        /// The session lives in a tmux session with no client attached, so there is no window to show.
        case detachedTmux
        case noTerminalApp
    }

    public struct Outcome: Equatable, Sendable {
        /// The app to bring forward.
        public var appPid: Int32
        /// False when the app has no scripting support we use, or the user said no to letting us control it.
        /// The app should still come forward; it just will not be on the right tab.
        public var tabSelected: Bool
    }

    public static let osascript = "/usr/bin/osascript"

    /// Selects the session's pane and tab, and says which app to activate.
    public static func focus(pid: Int32, on system: TerminalSystem) throws -> Outcome {
        guard let session = system.process(pid) else { throw Failure.notRunning }

        // The process that owns the terminal window, and the tty that window's tab is attached to.
        var hostPid = pid
        var tty = session.tty
        if let server = ancestors(of: session, on: system).first(where: { $0.command == "tmux" }) {
            let client = try Tmux(server: server, session: session, system: system).selectPane()
            hostPid = client.pid
            tty = client.tty
        }

        guard let host = system.process(hostPid),
              let (appPid, bundleId) = ([host] + ancestors(of: host, on: system)).lazy
                .compactMap({ entry in system.appBundleId(entry.pid).map { (entry.pid, $0) } }).first
        else { throw Failure.noTerminalApp }

        var selected = false
        if let tty, let script = selectTabScript(for: bundleId) {
            // osascript exits non-zero when the user has refused the Automation prompt (-1743).
            selected = system.run(osascript, ["-e", script, tty]) != nil
        }
        return Outcome(appPid: appPid, tabSelected: selected)
    }

    /// Parent first, up to but not including launchd.
    static func ancestors(of process: ProcessRecord, on system: TerminalSystem) -> [ProcessRecord] {
        var chain: [ProcessRecord] = []
        var next = process.parent
        while next > 1, chain.count < 32, let entry = system.process(next) {
            chain.append(entry)
            next = entry.parent
        }
        return chain
    }

    /// AppleScript that selects the tab whose tty is `item 1 of argv`. Passed as an argument, never interpolated.
    static func selectTabScript(for bundleId: String) -> String? {
        switch bundleId {
        case "com.apple.Terminal":
            return """
            on run argv
                tell application "Terminal"
                    repeat with w in windows
                        repeat with t in tabs of w
                            if tty of t is item 1 of argv then
                                set miniaturized of w to false
                                set selected of t to true
                                set index of w to 1
                                return
                            end if
                        end repeat
                    end repeat
                end tell
            end run
            """
        case "com.googlecode.iterm2":
            return """
            on run argv
                tell application "iTerm2"
                    repeat with w in windows
                        repeat with t in tabs of w
                            repeat with s in sessions of t
                                if tty of s is item 1 of argv then
                                    select w
                                    select t
                                    select s
                                    return
                                end if
                            end repeat
                        end repeat
                    end repeat
                end tell
            end run
            """
        default:
            return nil
        }
    }
}

/// The tmux server a session runs under, driven through the same binary and socket the session uses.
struct Tmux {
    let system: TerminalSystem
    let executable: String
    let baseArguments: [String]
    let pane: String

    init(server: ProcessRecord, session: ProcessRecord, system: TerminalSystem) throws {
        self.system = system
        executable = system.executablePath(server.pid) ?? "/usr/bin/env"
        // Without the server's path, look tmux up on PATH.
        let prefix = executable == "/usr/bin/env" ? ["tmux"] : []
        let environment = system.environment(session.pid)
        // TMUX is "<socket>,<server pid>,<session>"; without it, fall back to the default socket.
        let socket = environment["TMUX"]?.split(separator: ",").first.map(String.init)
        baseArguments = prefix + (socket.map { ["-S", $0] } ?? [])
        if let pane = environment["TMUX_PANE"] {
            self.pane = pane
        } else {
            // No environment to read: find the pane by the tty the session is attached to.
            guard let tty = session.tty,
                  let panes = system.run(executable, baseArguments + ["list-panes", "-a", "-F", "#{pane_tty} #{pane_id}"]),
                  let line = panes.split(separator: "\n").first(where: { $0.hasPrefix(tty + " ") })
            else { throw TerminalFocus.Failure.notRunning }
            pane = String(line.split(separator: " ")[1])
        }
    }

    /// Makes the pane current in its window and session, puts a client on that session, and returns the client.
    func selectPane() throws -> (pid: Int32, tty: String) {
        // Session ids ("$3") rather than names, which can hold spaces.
        let format = "#{client_activity} #{client_pid} #{client_tty} #{session_id}"
        guard let session = tmux(["display-message", "-p", "-t", pane, "#{session_id}"])?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !session.isEmpty,
              let listing = tmux(["list-clients", "-F", format])
        else { throw TerminalFocus.Failure.notRunning }

        let clients = listing.split(separator: "\n").compactMap { line -> (activity: Int, pid: Int32, tty: String, session: String)? in
            let fields = line.split(separator: " ", maxSplits: 3).map(String.init)
            guard fields.count == 4, let activity = Int(fields[0]), let pid = Int32(fields[1]) else { return nil }
            return (activity, pid, fields[2], fields[3])
        }
        // A client already showing the session wins; otherwise borrow whichever was used last.
        let onSession = clients.filter { $0.session == session }
        guard let client = (onSession.isEmpty ? clients : onSession).max(by: { $0.activity < $1.activity })
        else { throw TerminalFocus.Failure.detachedTmux }

        tmux(["select-window", "-t", pane, ";", "select-pane", "-t", pane,
              ";", "switch-client", "-c", client.tty, "-t", session])
        return (client.pid, client.tty)
    }

    @discardableResult
    private func tmux(_ arguments: [String]) -> String? {
        system.run(executable, baseArguments + arguments)
    }
}

/// The live process table, read with sysctl rather than by running `ps`.
public enum ProcessTable {
    public static func process(_ pid: Int32) -> ProcessRecord? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0, info.kp_proc.p_pid == pid else { return nil }
        let command = withUnsafeBytes(of: info.kp_proc.p_comm) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        let device = info.kp_eproc.e_tdev
        var tty: String?
        if device != -1, let name = devname(device, S_IFCHR) { tty = "/dev/" + String(cString: name) }
        return ProcessRecord(pid: pid, parent: info.kp_eproc.e_ppid, command: command, tty: tty)
    }

    public static func executablePath(_ pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// A process's environment, or empty when it is gone or not ours to read.
    public static func environment(_ pid: Int32) -> [String: String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 4 else { return [:] }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return [:] }
        return parseEnvironment(buffer.prefix(size))
    }

    /// KERN_PROCARGS2 is argc, the exec path, NUL padding, argv, then envp up to an empty string.
    static func parseEnvironment(_ bytes: ArraySlice<UInt8>) -> [String: String] {
        let bytes = Array(bytes)
        guard bytes.count > 4 else { return [:] }
        let argc = bytes.withUnsafeBytes { Int($0.loadUnaligned(as: Int32.self)) }
        guard argc >= 0 else { return [:] }

        var index = 4
        func string() -> String? {
            guard index < bytes.count else { return nil }
            let end = bytes[index...].firstIndex(of: 0) ?? bytes.count
            defer { index = end + 1 }
            return String(decoding: bytes[index..<end], as: UTF8.self)
        }
        guard string() != nil else { return [:] }                   // exec path
        while index < bytes.count, bytes[index] == 0 { index += 1 } // padding
        for _ in 0..<argc {                                         // argv
            guard string() != nil else { return [:] }
        }

        var environment: [String: String] = [:]
        while let entry = string(), !entry.isEmpty {
            guard let equals = entry.firstIndex(of: "=") else { continue }
            environment[String(entry[..<equals])] = String(entry[entry.index(after: equals)...])
        }
        return environment
    }

    public static func run(_ executable: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
