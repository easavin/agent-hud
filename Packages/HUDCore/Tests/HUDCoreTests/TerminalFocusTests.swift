import Foundation
import Testing
@testable import HUDCore

/// A process table and command runner in memory. `responses` answers a command by its tmux subcommand
/// ("list-clients", "display-message", …) or by "osascript"; anything unanswered fails like a non-zero exit.
private final class FakeSystem: TerminalSystem {
    var processes: [Int32: ProcessRecord] = [:]
    var environments: [Int32: [String: String]] = [:]
    var executables: [Int32: String] = [:]
    var apps: [Int32: String] = [:]
    var responses: [String: String] = [:]
    private(set) var commands: [[String]] = []

    func add(_ pid: Int32, _ command: String, parent: Int32, tty: String? = nil) {
        processes[pid] = ProcessRecord(pid: pid, parent: parent, command: command, tty: tty)
    }

    func process(_ pid: Int32) -> ProcessRecord? { processes[pid] }
    func environment(_ pid: Int32) -> [String: String] { environments[pid] ?? [:] }
    func executablePath(_ pid: Int32) -> String? { executables[pid] }
    func appBundleId(_ pid: Int32) -> String? { apps[pid] }

    func run(_ executable: String, _ arguments: [String]) -> String? {
        commands.append([executable] + arguments)
        if executable == TerminalFocus.osascript { return responses["osascript"] }
        let subcommand = arguments.first { !$0.hasPrefix("-") && !$0.hasPrefix("/") && $0 != "tmux" }
        return subcommand.flatMap { responses[$0] }
    }

    var osascriptCalls: [[String]] { commands.filter { $0.first == TerminalFocus.osascript } }
    var tmuxCalls: [[String]] { commands.filter { $0.first != TerminalFocus.osascript } }
}

/// Terminal.app (pid 489) → login → zsh → claude, the way a session started in a plain tab looks.
private func plainTerminal(bundleId: String = "com.apple.Terminal") -> FakeSystem {
    let system = FakeSystem()
    system.add(489, "Terminal", parent: 1)
    system.apps[489] = bundleId
    system.add(8848, "login", parent: 489, tty: "/dev/ttys054")
    system.add(8849, "zsh", parent: 8848, tty: "/dev/ttys054")
    system.add(10377, "claude", parent: 8849, tty: "/dev/ttys054")
    return system
}

/// claude → zsh → tmux server, with two Terminal tabs running tmux clients: one on session $8, one on $4.
private func tmuxed() -> FakeSystem {
    let system = FakeSystem()
    system.add(21234, "tmux", parent: 1)
    system.executables[21234] = "/opt/homebrew/bin/tmux"
    system.add(3331, "zsh", parent: 21234, tty: "/dev/ttys055")
    system.add(1007, "claude", parent: 3331, tty: "/dev/ttys055")
    system.environments[1007] = ["TMUX": "/private/tmp/tmux-501/default,21234,8", "TMUX_PANE": "%33"]

    system.add(489, "Terminal", parent: 1)
    system.apps[489] = "com.apple.Terminal"
    system.add(600, "login", parent: 489, tty: "/dev/ttys045")
    system.add(601, "zsh", parent: 600, tty: "/dev/ttys045")
    system.add(602, "tmux", parent: 601, tty: "/dev/ttys045")
    system.add(700, "login", parent: 489, tty: "/dev/ttys031")
    system.add(701, "zsh", parent: 700, tty: "/dev/ttys031")
    system.add(702, "tmux", parent: 701, tty: "/dev/ttys031")

    system.responses["display-message"] = "$8\n"
    system.responses["list-clients"] = """
    1792941000 602 /dev/ttys045 $8
    1792942000 702 /dev/ttys031 $4

    """
    system.responses["select-window"] = ""
    system.responses["osascript"] = ""
    return system
}

@Suite struct TerminalFocusTests {
    // MARK: Plain terminal tabs

    @Test func selectsTheTerminalTabByItsTty() throws {
        let system = plainTerminal()
        system.responses["osascript"] = ""

        let outcome = try TerminalFocus.focus(pid: 10377, on: system)

        #expect(outcome == .init(appPid: 489, tabSelected: true))
        let call = try #require(system.osascriptCalls.first)
        #expect(call.last == "/dev/ttys054")
        #expect(call[2].contains("tell application \"Terminal\""))
        #expect(system.tmuxCalls.isEmpty)
    }

    @Test func selectsTheITermSessionByItsTty() throws {
        let system = plainTerminal(bundleId: "com.googlecode.iterm2")
        system.responses["osascript"] = ""

        let outcome = try TerminalFocus.focus(pid: 10377, on: system)

        #expect(outcome == .init(appPid: 489, tabSelected: true))
        let call = try #require(system.osascriptCalls.first)
        #expect(call[2].contains("tell application \"iTerm2\""))
        #expect(call.last == "/dev/ttys054")
    }

    @Test func passesTheTtyAsAnArgumentRatherThanInTheScript() throws {
        for bundleId in ["com.apple.Terminal", "com.googlecode.iterm2"] {
            let script = try #require(TerminalFocus.selectTabScript(for: bundleId))
            #expect(!script.contains("/dev/"))
            #expect(script.contains("item 1 of argv"))
        }
    }

    @Test func refusedAutomationStillBringsTheAppForward() throws {
        // The user said no to "Agent HUD wants to control Terminal": osascript exits non-zero.
        let system = plainTerminal()
        system.responses["osascript"] = nil

        let outcome = try TerminalFocus.focus(pid: 10377, on: system)

        #expect(outcome == .init(appPid: 489, tabSelected: false))
        #expect(system.osascriptCalls.count == 1)
    }

    @Test func otherTerminalsComeForwardWithoutScripting() throws {
        let system = plainTerminal(bundleId: "com.mitchellh.ghostty")

        let outcome = try TerminalFocus.focus(pid: 10377, on: system)

        #expect(outcome == .init(appPid: 489, tabSelected: false))
        #expect(system.commands.isEmpty)
    }

    @Test func aSessionInsideAnotherAppBringsThatAppForward() throws {
        // The Claude desktop app runs sessions with no tty: activate the app, nothing to select.
        let system = FakeSystem()
        system.add(34078, "Claude", parent: 1)
        system.apps[34078] = "com.anthropic.claudefordesktop"
        system.add(81907, "disclaimer", parent: 34078)
        system.add(81908, "claude", parent: 81907)

        let outcome = try TerminalFocus.focus(pid: 81908, on: system)

        #expect(outcome == .init(appPid: 34078, tabSelected: false))
        #expect(system.commands.isEmpty)
    }

    @Test func anAppWithoutABundleIdStillCounts() throws {
        let system = plainTerminal(bundleId: "")
        let outcome = try TerminalFocus.focus(pid: 10377, on: system)
        #expect(outcome == .init(appPid: 489, tabSelected: false))
    }

    // MARK: tmux

    @Test func selectsThePaneAndSwitchesTheClientAlreadyOnItsSession() throws {
        let system = tmuxed()

        let outcome = try TerminalFocus.focus(pid: 1007, on: system)

        #expect(outcome == .init(appPid: 489, tabSelected: true))
        // The client on $8 wins even though the one on $4 was used more recently.
        let select = try #require(system.tmuxCalls.last)
        #expect(select == ["/opt/homebrew/bin/tmux", "-S", "/private/tmp/tmux-501/default",
                           "select-window", "-t", "%33", ";", "select-pane", "-t", "%33",
                           ";", "switch-client", "-c", "/dev/ttys045", "-t", "$8"])
        #expect(system.osascriptCalls.first?.last == "/dev/ttys045")
    }

    @Test func borrowsTheMostRecentClientWhenNoneIsOnTheSession() throws {
        let system = tmuxed()
        system.responses["display-message"] = "$9\n"

        let outcome = try TerminalFocus.focus(pid: 1007, on: system)

        #expect(outcome.appPid == 489)
        #expect(system.tmuxCalls.last?.suffix(4) == ["-c", "/dev/ttys031", "-t", "$9"])
        #expect(system.osascriptCalls.first?.last == "/dev/ttys031")
    }

    @Test func findsThePaneByTtyWhenTheEnvironmentIsUnreadable() throws {
        let system = tmuxed()
        system.environments[1007] = nil
        system.responses["list-panes"] = "/dev/ttys012 %2\n/dev/ttys055 %33\n"

        _ = try TerminalFocus.focus(pid: 1007, on: system)

        let listPanes = try #require(system.tmuxCalls.first)
        // No TMUX variable, so no -S: the default socket.
        #expect(listPanes == ["/opt/homebrew/bin/tmux", "list-panes", "-a", "-F", "#{pane_tty} #{pane_id}"])
        #expect(system.tmuxCalls.last?.contains("%33") == true)
    }

    @Test func fallsBackToTmuxOnThePathWithoutTheServerBinary() throws {
        let system = tmuxed()
        system.executables[21234] = nil

        _ = try TerminalFocus.focus(pid: 1007, on: system)

        #expect(system.tmuxCalls.allSatisfy { Array($0.prefix(2)) == ["/usr/bin/env", "tmux"] })
    }

    @Test func aDetachedTmuxSessionHasNothingToShow() {
        let system = tmuxed()
        system.responses["list-clients"] = ""

        #expect(throws: TerminalFocus.Failure.detachedTmux) { try TerminalFocus.focus(pid: 1007, on: system) }
        #expect(!system.tmuxCalls.contains { $0.contains("switch-client") })
        #expect(system.osascriptCalls.isEmpty)
    }

    @Test func aPaneTmuxNoLongerKnowsFails() {
        let system = tmuxed()
        system.responses["display-message"] = nil

        #expect(throws: TerminalFocus.Failure.notRunning) { try TerminalFocus.focus(pid: 1007, on: system) }
        #expect(system.osascriptCalls.isEmpty)
    }

    @Test func aPaneThatCannotBeFoundByTtyFails() {
        let system = tmuxed()
        system.environments[1007] = nil
        system.responses["list-panes"] = "/dev/ttys012 %2\n"

        #expect(throws: TerminalFocus.Failure.notRunning) { try TerminalFocus.focus(pid: 1007, on: system) }
    }

    @Test func malformedClientLinesAreSkipped() throws {
        let system = tmuxed()
        system.responses["list-clients"] = "garbage\nnot-a-number 602 /dev/ttys045 $8\n1792941000 602 /dev/ttys045 $8\n"

        let outcome = try TerminalFocus.focus(pid: 1007, on: system)
        #expect(outcome.appPid == 489)
    }

    // MARK: Nothing to show

    @Test func aSessionThatHasExitedIsNotRunning() {
        #expect(throws: TerminalFocus.Failure.notRunning) { try TerminalFocus.focus(pid: 99999, on: FakeSystem()) }
    }

    @Test func noAppInTheProcessTreeHasNothingToActivate() {
        // An ssh session or a launchd job: the chain reaches launchd without passing a Dock app.
        let system = FakeSystem()
        system.add(400, "sshd", parent: 1)
        system.add(401, "zsh", parent: 400, tty: "/dev/ttys090")
        system.add(402, "claude", parent: 401, tty: "/dev/ttys090")

        #expect(throws: TerminalFocus.Failure.noTerminalApp) { try TerminalFocus.focus(pid: 402, on: system) }
        #expect(system.commands.isEmpty)
    }

    @Test func aParentCycleDoesNotHang() {
        let system = FakeSystem()
        system.add(10, "a", parent: 11)
        system.add(11, "b", parent: 10)

        #expect(TerminalFocus.ancestors(of: system.processes[10]!, on: system).count == 32)
        #expect(throws: TerminalFocus.Failure.noTerminalApp) { try TerminalFocus.focus(pid: 10, on: system) }
    }
}

@Suite struct ProcessTableTests {
    /// argc, exec path, padding, argv, envp, the empty string that ends envp, then the "apple" strings.
    private func procargs(argv: [String], env: [String], execPath: String = "/usr/local/bin/claude") -> [UInt8] {
        var bytes = withUnsafeBytes(of: Int32(argv.count)) { Array($0) }
        bytes += Array(execPath.utf8) + [0, 0, 0, 0]
        for string in argv + env { bytes += Array(string.utf8) + [0] }
        bytes += [0] + Array("ptr_munge=abc".utf8) + [0]
        return bytes
    }

    @Test func parsesTheEnvironmentAfterArgv() {
        let bytes = procargs(argv: ["claude", "--resume"],
                             env: ["TMUX=/private/tmp/tmux-501/default,21234,8", "TMUX_PANE=%33", "EMPTY=", "A=b=c"])

        let environment = ProcessTable.parseEnvironment(bytes[...])

        #expect(environment == ["TMUX": "/private/tmp/tmux-501/default,21234,8", "TMUX_PANE": "%33",
                                "EMPTY": "", "A": "b=c"])
    }

    @Test func argvThatLooksLikeAVariableIsNotOne() {
        let environment = ProcessTable.parseEnvironment(procargs(argv: ["claude", "FOO=bar"], env: ["HOME=/x"])[...])
        #expect(environment == ["HOME": "/x"])
    }

    @Test func truncatedOrEmptyBuffersGiveNothing() {
        #expect(ProcessTable.parseEnvironment([][...]).isEmpty)
        #expect(ProcessTable.parseEnvironment([1, 0][...]).isEmpty)
        // Claims three arguments but the buffer ends after one.
        let short = withUnsafeBytes(of: Int32(3)) { Array($0) } + Array("/bin/x".utf8) + [0, 0] + Array("x".utf8) + [0]
        #expect(ProcessTable.parseEnvironment(short[...]).isEmpty)
        let negative = withUnsafeBytes(of: Int32(-1)) { Array($0) } + [0, 0]
        #expect(ProcessTable.parseEnvironment(negative[...]).isEmpty)
    }

    @Test func readsThisProcess() throws {
        let me = try #require(ProcessTable.process(getpid()))
        #expect(me.pid == getpid())
        #expect(me.parent == getppid())
        #expect(!me.command.isEmpty)
        #expect(ProcessTable.environment(getpid())["PATH"] == ProcessInfo.processInfo.environment["PATH"])
        #expect(ProcessTable.executablePath(getpid())?.hasPrefix("/") == true)
    }

    @Test func aProcessThatDoesNotExistIsNil() {
        // Far above PID_MAX, so it can never be live.
        let pid = Int32.max - 1
        #expect(ProcessTable.process(pid) == nil)
        #expect(ProcessTable.environment(pid).isEmpty)
        #expect(ProcessTable.executablePath(pid) == nil)
    }

    @Test func runReturnsOutputOnSuccessAndNilOnFailure() {
        #expect(ProcessTable.run("/bin/echo", ["hello"]) == "hello\n")
        #expect(ProcessTable.run("/usr/bin/false", []) == nil)
        #expect(ProcessTable.run("/nonexistent/binary", []) == nil)
    }
}
