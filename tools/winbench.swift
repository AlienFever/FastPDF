// FastPDF for Mac — Copyright (C) 2026 Alienfever
// SPDX-License-Identifier: GPL-3.0-or-later

// Measures time from asking Launch Services to open a file until the app has a new on-screen window.
// Works for any app (e.g. Preview) since it only watches the window list.
// Usage: winbench <app path> <pdf> [runs] [--warm]
import AppKit

let args = CommandLine.arguments
let appURL = URL(fileURLWithPath: args[1]), file = URL(fileURLWithPath: args[2])
let runs = args.count > 3 ? Int(args[3])! : 5
let warm = args.contains("--warm")
let bundleID = Bundle(url: appURL)!.bundleIdentifier!

func pid() -> pid_t? { NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.processIdentifier }
func windowCount(_ p: pid_t) -> Int {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as! [[String: Any]]
    return list.filter { ($0[kCGWindowOwnerPID as String] as? pid_t) == p && ($0[kCGWindowLayer as String] as? Int) == 0
        && (($0[kCGWindowBounds as String] as? [String: CGFloat])?["Height"] ?? 0) > 200 }.count
}
func kill() {
    for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) { app.forceTerminate() }
    while pid() != nil { usleep(50_000) }
    usleep(800_000)
}

let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("winbench-\(getpid())")
try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
var results: [Double] = []
if warm { kill(); NSWorkspace.shared.open([file], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration()); sleep(2) }
for r in 1...runs {
    var target = file
    if warm {
        target = tmp.appendingPathComponent("w\(r)-" + file.lastPathComponent)
        try? FileManager.default.copyItem(at: file, to: target)
    } else { kill() }
    let before = pid().map(windowCount) ?? 0
    let config = NSWorkspace.OpenConfiguration()
    let t0 = Date()
    NSWorkspace.shared.open([target], withApplicationAt: appURL, configuration: config)
    while true {
        if let p = pid(), windowCount(p) > before { break }
        usleep(1000)
        if Date().timeIntervalSince(t0) > 10 { print("timeout"); break }
    }
    let ms = Date().timeIntervalSince(t0) * 1000
    results.append(ms)
    print(String(format: "  run %d: %6.1f ms", r, ms))
}
let sorted = results.sorted()
print(String(format: "%@ %@ median %.1f ms", appURL.lastPathComponent, warm ? "warm" : "cold", sorted[sorted.count / 2]))
kill()
try? FileManager.default.removeItem(at: tmp)
