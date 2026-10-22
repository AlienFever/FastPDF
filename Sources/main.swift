// FastPDF for Mac — Copyright (C) 2026 Alienfever
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

// Manual bootstrap: no nib, no storyboard, nothing loaded that the first window doesn't need.
_ = Perf.processStart
let app = NSApplication.shared
// The first NSDocumentController instantiated becomes the shared one.
_ = ReaderDocumentController()
let delegate = AppDelegate()
app.delegate = delegate
app.run()
