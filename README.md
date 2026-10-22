# FastPDF

A minimal PDF reader for macOS whose only goal is to feel instant. AppKit + PDFKit, no dependencies.

> **Back up PDFs you care about before annotating them.** When you save highlights or notes, FastPDF rewrites
> the whole file through Apple's PDFKit (as Preview does). That works for ordinary PDFs, but it can alter or drop
> unusual content, and it invalidates digital signatures. Reading never modifies a file.

## Requirements

- macOS 26 (Tahoe) or later, Apple Silicon. Older macOS versions are not supported.
- Xcode 26+ or its command-line tools, to build.

There are no prebuilt downloads yet: the app is ad-hoc signed, so build it yourself with the steps below.

## Build & install

```bash
./build.sh            # compiles, signs (ad-hoc, sandboxed), installs to ~/Applications, registers with Launch Services
```

Then **FastPDF → Make FastPDF the Default PDF Viewer** (macOS asks once to confirm) so double-clicking a PDF opens it here.

No Xcode project; `build.sh` calls `swiftc` directly.

## Features

| | |
|---|---|
| Pages | Page field (type a number + Return), ‹ › buttons, ←/→, Space, Page Up/Down, Home/End, ⌥⌘G go to page, ⌘[ ⌘] back/forward |
| Views | **D** cycles Single Page → Continuous → Two Pages (or ⌘1 / ⌘2 / ⌘3) |
| Zoom | **V** switches Fit Width ⇄ Fit Page · Fit Width ⌘8 · Fit Page ⌘9 · Actual Size ⌘0 · ⌘+ / ⌘− · pinch. Fit modes stick when the window resizes. |
| Sidebar (⌥⌘S) | Contents (the PDF's outline) ⌥⌘1 · Thumbnails ⌥⌘2 · Highlights & Notes ⌥⌘3 (click to jump) |
| Bookmarks | ⌘D toggles a bookmark on the current page; bookmark button / ⌥⌘B lists them; also in the Bookmarks menu. Stored by FastPDF, the PDF is never modified. |
| Find | ⌘F, Return / ⌘G next, ⇧Return / ⇧⌘G previous, Esc closes |
| Highlight | Select text, then **H** (primary color) or **K** (secondary). With nothing selected, H / K turns on *highlight mode*: every selection is highlighted when you let go; press the key again or Esc to stop. Pick the two colors in the Highlight menu. Right-click a highlight to recolor or remove it; ⌘Z undoes. |
| Notes | **N** then click on the page places a sticky note (with text selected, N puts it beside the selection); also right-click ▸ Add Note Here. Click any note, including ones already in the PDF, to read, edit or delete it. Notes are listed under Highlights & Notes in the sidebar. |
| Toolbar | **⌥⌘T** (View ▸ Glass Toolbar) switches between the standard macOS 26 toolbar (default; pages scroll under the glass) and the compact title-bar row (fastest). |
| Sidebar width | Drag the grip at the sidebar's edge; double-click it to reset. |
| Memory | Each file reopens at the exact spot, zoom and view mode you left it. Keyed by the PDF's internal ID, so it survives renames/moves. |

## Saving highlights

Highlights and notes are written into the PDF itself (so Preview, Acrobat etc. show them) when you press **⌘S**. Until then the window shows the usual unsaved-changes dot, and closing or quitting asks Save / Don't Save / Cancel. Turn on **File ▸ Autosave Highlights** to save automatically ~2 s after each change and on close instead. H, K, N, V and D are single-key shortcuts that only act while the page has focus, never while typing in a field.

PDFKit can only save by rewriting the whole file, which takes seconds for large PDFs, so saving happens in the background on a separate copy of the document with the edits replayed onto it: the window never stalls. Notes:

- Re-saving gives the PDF a new internal ID; FastPDF moves its bookmarks/position record to the new ID.
- Password-protected PDFs and PDFs whose permissions forbid comments can't be highlighted.
- Rewriting a digitally signed PDF invalidates its signature (true of any app that edits it).

## Why it's fast

- **Stays running** after the last window closes, so later opens skip app launch entirely (like Preview).
- **Optional NSToolbar.** On macOS 26 every toolbar item and standard control renders through SwiftUI; the glass toolbar costs ~80 ms per window opened (warm open ~60 ms → ~140 ms in-app). The compact bar is hand-drawn views (`ReaderBar.swift`) and avoids that.
- **Nothing built until needed:** sidebar panes, highlight scan, search field, and the title-bar proxy icon are created after the page is on screen or on first use.
- **No "seamless open" zoom animation, no window restoration**, no Edit-menu Writing Tools decoration at launch, no file-type sniffing.
- Highlights are scanned on a background thread with a separate `PDFDocument` and appear as they're found.

Measured on an M1 MacBook Air, end to end (open request → window on screen), median of 7:

| | FastPDF | Preview |
|---|---|---|
| Cold, 1-page | 371 ms | 1042 ms |
| Warm, 1-page | 127 ms | 328 ms |
| Cold, 1,500 pages | 388 ms | 988 ms |
| Warm, 1,500 pages | 145 ms | 715 ms |

~80 ms of each warm number is Launch Services delivering the open request; inside the app a warm open is 30–60 ms.

## Tools

```bash
swift tools/make_fixtures.swift Tests/fixtures      # test PDFs: 1 page, 1,500 pages, outline + annotations
xcrun swiftc -O tools/winbench.swift -o /tmp/winbench
/tmp/winbench ~/Applications/FastPDF.app Tests/fixtures/big.pdf 7          # cold
/tmp/winbench ~/Applications/FastPDF.app Tests/fixtures/big.pdf 7 --warm   # warm
swift tools/make_icon.swift                          # regenerates Resources/AppIcon.icns
```

In-app timings are logged on every open:

```bash
/usr/bin/log show --last 5m --predicate 'subsystem == "com.ahmadharb.FastPDF"'
```

## Known limits

- Find doesn't match a phrase that wraps across a line break (PDFKit limitation).
- Read-only by design: no annotating, no saving.

## License

FastPDF is free software: you can redistribute it and/or modify it under the terms of the
[GNU General Public License v3](LICENSE) or (at your option) any later version. In short: anyone may use, study,
change and share it, but anyone who distributes it, modified or not, free or paid, must release the complete
source under the same license.

The GPL covers the code. The **FastPDF name and app icon are not licensed for reuse**: if you distribute a
modified version, please give it a different name and icon so it isn't mistaken for this project.

Copyright © 2026 Alienfever.
