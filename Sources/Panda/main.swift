import AppKit

// Panda is a menu bar app: no Dock icon, no main window at launch (see LSUIElement in Info.plist).
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
