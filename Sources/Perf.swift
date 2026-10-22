// FastPDF for Mac — Copyright (C) 2026 Alienfever
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import os

/// Launch/open timing. Read with:
///   /usr/bin/log show --last 5m --predicate 'subsystem == "com.ahmadharb.FastPDF"' --info
enum Perf {
    static let log = Logger(subsystem: "com.ahmadharb.FastPDF", category: "perf")

    /// When the kernel started this process (includes dyld and runtime setup, not just main()).
    static let processStart: Date = {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return Date() }
        let tv = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1_000_000)
    }()

    static var openRequestedAt: Date?
    private static var hasShownFirstWindow = false

    /// Called once a reader window has been displayed for the first time.
    static func windowShown(_ name: String) {
        let now = Date()
        let sinceRequest = openRequestedAt.map { now.timeIntervalSince($0) * 1000 } ?? -1
        if !hasShownFirstWindow {
            hasShownFirstWindow = true
            let sinceLaunch = now.timeIntervalSince(processStart) * 1000
            log.notice("cold open \(name, privacy: .public): \(sinceLaunch, format: .fixed(precision: 1), privacy: .public) ms since process start, \(sinceRequest, format: .fixed(precision: 1), privacy: .public) ms since open request, epoch \(now.timeIntervalSince1970, format: .fixed(precision: 4), privacy: .public)")
        } else {
            log.notice("warm open \(name, privacy: .public): \(sinceRequest, format: .fixed(precision: 1), privacy: .public) ms since open request, epoch \(now.timeIntervalSince1970, format: .fixed(precision: 4), privacy: .public)")
        }
        openRequestedAt = nil
    }
}
