import AppKit
import HUDCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation, NSWindowDelegate, ObservableObject {
    let monitor = AgentMonitor()
    private var panel: FloatingPanel?
    private var dashboard: NSWindow?
    private var statusItem: NSStatusItem?
    private var dockTimer: Timer?
    private let defaults = UserDefaults.standard

    @Published var isMini = UserDefaults.standard.bool(forKey: "widgetMini") {
        didSet {
            defaults.set(isMini, forKey: "widgetMini")
            panel?.resize(to: widgetSize)
        }
    }

    private var widgetSize: CGSize { isMini ? CGSize(width: 160, height: 160) : CGSize(width: 320, height: 320) }
    var isWidgetVisible: Bool { panel?.isVisible ?? false }

    // MARK: Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = CommandLine.arguments
        if let flag = arguments.firstIndex(of: "--demo") {
            monitor.demo = DemoData.Scenario(rawValue: arguments.dropFirst(flag + 1).first ?? "") ?? .busy
        }
        monitor.start()
        if let flag = arguments.firstIndex(of: "--snapshot"), let directory = arguments.dropFirst(flag + 1).first {
            NSApp.setActivationPolicy(.prohibited)
            SnapshotRenderer.run(monitor: monitor, directory: URL(fileURLWithPath: directory))
            return
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.mainMenu = buildMainMenu()
        installStatusItem()
        installDockTile()

        let panel = FloatingPanel(size: widgetSize) { WidgetRoot(delegate: self) }
        panel.setFrameAutosaveName("AgentHUD.widget")
        if !panel.setFrameUsingName("AgentHUD.widget") { panel.placeInDefaultCorner() }
        panel.resize(to: widgetSize)
        self.panel = panel
        if defaults.object(forKey: "widgetVisible") as? Bool ?? true { panel.orderFrontRegardless() }
        // Like Activity Monitor: come back the way you were left. First launch opens the main window.
        if defaults.object(forKey: "dashboardOpen") as? Bool ?? true { showDashboard() }
    }

    /// Dock icon clicked: bring the main window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showDashboard()
        return false
    }

    /// Closing the main window leaves the widget (and the app) running.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? { buildViewMenu(title: "Agent HUD") }

    // MARK: Actions

    @objc func showDashboard() {
        if dashboard == nil { dashboard = makeDashboardWindow() }
        defaults.set(true, forKey: "dashboardOpen")
        NSApp.activate(ignoringOtherApps: true)
        dashboard?.makeKeyAndOrderFront(nil)
    }

    @objc func toggleWidget() {
        guard let panel else { return }
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
        defaults.set(panel.isVisible, forKey: "widgetVisible")
        objectWillChange.send()
    }

    @objc func toggleMini() { isMini.toggle() }

    @objc func resetWidgetPosition() {
        panel?.placeInDefaultCorner()
        if !isWidgetVisible { toggleWidget() }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(toggleWidget): item.state = isWidgetVisible ? .on : .off
        case #selector(toggleMini): item.state = isMini ? .on : .off
        default: break
        }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === dashboard { defaults.set(false, forKey: "dashboardOpen") }
    }

    // MARK: Windows

    private func makeDashboardWindow() -> NSWindow {
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: DashboardView.designSize),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Agent HUD"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // Not movable by background: AppKit would claim a mouse-down on any transparent area to move
        // the window before SwiftUI sees it, and the pane splitters are transparent on purpose. The
        // header is an explicit drag area instead (`WindowDragArea`).
        window.isMovableByWindowBackground = false
        window.backgroundColor = NSColor(red: 244 / 255, green: 243 / 255, blue: 238 / 255, alpha: 1)
        window.appearance = NSAppearance(named: .aqua)
        window.contentMinSize = CGSize(width: 1020, height: 620)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: DashboardView(monitor: monitor))
        window.setFrameAutosaveName("AgentHUD.dashboard")
        if !window.setFrameUsingName("AgentHUD.dashboard") {
            // Open at the design size, or as close to it as the screen allows.
            let visible = NSScreen.main?.visibleFrame.size ?? DashboardView.designSize
            window.setContentSize(CGSize(width: min(1280, visible.width - 40), height: min(800, visible.height - 40)))
            window.center()
        }
        return window
    }

    // MARK: Menus

    private func item(_ title: String, _ action: Selector?, key: String = "", target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target
        return item
    }

    /// Dashboard / widget controls, shared by the View menu, the Dock menu and the status item.
    private func buildViewMenu(title: String) -> NSMenu {
        let menu = NSMenu(title: title)
        menu.addItem(item("Dashboard", #selector(showDashboard), key: "1", target: self))
        menu.addItem(.separator())
        menu.addItem(item("Show Widget", #selector(toggleWidget), key: "2", target: self))
        menu.addItem(item("Mini Widget", #selector(toggleMini), key: "3", target: self))
        menu.addItem(item("Move Widget to Top-Right Corner", #selector(resetWidgetPosition), target: self))
        return menu
    }

    private func buildMainMenu() -> NSMenu {
        let main = NSMenu()
        func add(_ menu: NSMenu) { let holder = NSMenuItem(); holder.submenu = menu; main.addItem(holder) }

        let app = NSMenu(title: "Agent HUD")
        app.addItem(item("About Agent HUD", #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        app.addItem(.separator())
        app.addItem(item("Hide Agent HUD", #selector(NSApplication.hide(_:)), key: "h"))
        let others = item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), key: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        app.addItem(others)
        app.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        app.addItem(.separator())
        app.addItem(item("Quit Agent HUD", #selector(NSApplication.terminate(_:)), key: "q"))
        add(app)

        add(buildViewMenu(title: "View"))

        let window = NSMenu(title: "Window")
        window.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), key: "m"))
        window.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        window.addItem(item("Close", #selector(NSWindow.performClose(_:)), key: "w"))
        add(window)
        NSApp.windowsMenu = window
        return main
    }

    private func installStatusItem() {
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "circle.hexagongrid.fill", accessibilityDescription: "Agent HUD")
        let menu = buildViewMenu(title: "Agent HUD")
        menu.addItem(.separator())
        menu.addItem(item("Quit Agent HUD", #selector(NSApplication.terminate(_:)), key: "q"))
        status.menu = menu
        statusItem = status
    }

    // MARK: Dock tile

    /// Live Dock icon, the way Activity Monitor draws its CPU meter: block bars plus tok/min.
    private func installDockTile() {
        let tile = NSApp.dockTile
        let host = NSHostingView(rootView: DockTileView(monitor: monitor))
        host.frame = CGRect(origin: .zero, size: tile.size)
        tile.contentView = host
        tile.display()
        var last = ""
        dockTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Redrawing the tile is not free; only do it when something visible changed.
                let signature = "\(self.monitor.tokensPerMinute.compact)|\(self.monitor.mood)|"
                    + self.monitor.agents.map { "\($0.activity.rawValue)\($0.heartbeat.hashValue)" }.joined()
                guard signature != last else { return }
                last = signature
                NSApp.dockTile.display()
            }
        }
    }
}
