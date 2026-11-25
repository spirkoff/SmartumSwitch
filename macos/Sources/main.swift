// SmartumSwitch for macOS — entry point.
//   SmartumSwitch                 menu-bar app
//   SmartumSwitch --selftest [f]  run core/tests/cases.json against the Swift core (no permissions needed)
//   SmartumSwitch --layout-check  compare the enabled keyboard layouts with core/data/layout.json
import Cocoa

let args = CommandLine.arguments
if let i = args.firstIndex(of: "--selftest") {
    let p = i + 1 < args.count ? args[i + 1] : Res.root.appendingPathComponent("tests/cases.json").path
    exit(Int32(min(runSelfTest(p), 100)))
}
if args.contains("--layout-check") { exit(Int32(min(Layouts.check(), 100))) }

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
