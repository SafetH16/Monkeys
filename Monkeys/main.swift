import Cocoa

// Disable output buffering so that logs appear immediately
setbuf(stdout, nil)

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
