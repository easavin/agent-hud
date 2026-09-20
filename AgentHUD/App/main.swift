import AppKit

// Classic AppKit lifecycle: the app owns a Dock icon, a main menu, a status item, the floating
// widget panel and the dashboard window, none of which map cleanly onto SwiftUI scenes.
let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
