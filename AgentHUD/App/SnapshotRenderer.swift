import AppKit
import HUDCore
import SwiftUI

/// `AgentHUD --snapshot <dir> [--demo busy|idle|alert]` renders every frame to PNG and quits.
/// Lets the UI be checked against the design without screen-recording permission.
@MainActor
enum SnapshotRenderer {
    static func run(monitor: AgentMonitor, directory: URL) {
        Task {
            // Live mode needs a poll and the first history pass before there is anything to draw.
            if monitor.demo == nil {
                for _ in 0..<40 where monitor.stats.isBackfilling || monitor.agents.isEmpty { try? await Task.sleep(for: .milliseconds(500)) }
                // Ended sessions load one per poll; wait for the history to fill in.
                try? await Task.sleep(for: .seconds(Double(IngestEngine.historyLimit) + 2))
            }
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let tag = monitor.demo?.rawValue ?? "live"
            save(CompactWidgetView(monitor: monitor), CGSize(width: 320, height: 320), directory.appendingPathComponent("compact-\(tag).png"))
            save(MiniWidgetView(monitor: monitor), CGSize(width: 160, height: 160), directory.appendingPathComponent("mini-\(tag).png"))
            for tab in HeroTab.allCases {
                save(DashboardView(monitor: monitor, initialTab: tab), DashboardView.designSize, directory.appendingPathComponent("dashboard-\(tab.rawValue)-\(tag).png"))
            }
            save(DockTileView(monitor: monitor), CGSize(width: 512, height: 512), directory.appendingPathComponent("icon-\(tag).png"))
            saveLayers(monitor: monitor, directory.appendingPathComponent("reactor-layer-\(tag).png"))
            NSApp.terminate(nil)
        }
    }

    /// The live widget uses Core Animation twins that ImageRenderer cannot see; render their layer tree directly.
    private static func saveLayers(monitor: AgentMonitor, _ url: URL) {
        let host = NSHostingView(rootView: CompactWidgetView(monitor: monitor).environment(\.colorScheme, .dark))
        host.frame = CGRect(x: 0, y: 0, width: 320, height: 320)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
        print("wrote \(url.path)")
    }

    private static func save(_ view: some View, _ size: CGSize, _ url: URL) {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height).environment(\.colorScheme, .dark).environment(\.staticRendering, true))
        renderer.scale = 2
        guard let image = renderer.cgImage else { return print("render failed: \(url.lastPathComponent)") }
        let bitmap = NSBitmapImageRep(cgImage: image)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
        print("wrote \(url.path)")
    }
}
