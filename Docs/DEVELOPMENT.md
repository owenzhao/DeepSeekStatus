# Development notes

Notes for working on DeepSeek Status: how the pieces fit together, how to render the UI without
launching it, and the pitfalls that were measured the hard way.

For what the app does and how to use it, see the [README](../README.md).

---

## 1. Project layout

```
DeepSeekStatus/
├── DeepSeekStatus.xcodeproj           # Xcode project (objectVersion 77, file-system-synchronized
│                                      #   group — new files under DeepSeekStatus/ are picked up
│                                      #   automatically; a shared scheme is committed so that
│                                      #   xcodebuild -scheme works)
├── DeepSeekStatus/
│   ├── DeepSeekStatusApp.swift        # Entry point: AppDelegate + NSStatusItem + panel placement
│   ├── Localizable.xcstrings          # String Catalog: English (source) + Simplified Chinese
│   ├── Models/
│   │   ├── PricePeriod.swift          # Schedule rules, next transition, formatting
│   │   └── PricingStore.swift         # 1 Hz state source + user defaults
│   ├── Support/
│   │   ├── SVGPath.swift              # SVG path parser (incl. arcs → cubic Béziers)
│   │   ├── WhaleTheme.swift           # Brand colors and the per-scene palettes
│   │   └── LaunchAtLogin.swift        # SMAppService wrapper
│   ├── Views/
│   │   ├── WhaleShape.swift           # Official whale vector path + Shape + path cache
│   │   ├── WhaleScene.swift           # Motion constants + shared SwiftUI drawing
│   │   ├── MenuBarIcon.swift          # Menu bar icon: vector path → bitmap NSImage
│   │   ├── WhaleStatusItemView.swift  # Alternative: Core Animation version (currently unused)
│   │   ├── WhaleStage.swift           # SwiftUI whale canvas
│   │   ├── AquariumView.swift         # Aquarium at the top of the panel
│   │   ├── WeekScheduleGrid.swift     # Weekly heat map
│   │   ├── PopoverView.swift          # Panel content (SwiftUI)
│   │   └── StatusPanel.swift          # Panel window: rounded corners + scroll fallback
│   └── Assets.xcassets                # App icon + accent color
├── Tools/
│   ├── build.sh                       # Command line build / run
│   ├── render-preview.sh              # Render the UI offscreen to PNG
│   └── Snapshot/main.swift            # The offscreen renderer / self-check harness
├── Docs/DEVELOPMENT.md                # This file
└── Preview/                           # Generated renders (regenerable)
```

Build settings worth knowing: `MACOSX_DEPLOYMENT_TARGET = 14.0`, `SWIFT_VERSION = 5.0`,
`GENERATE_INFOPLIST_FILE = YES`, `INFOPLIST_KEY_LSUIElement = YES` (no Dock icon),
`ENABLE_APP_SANDBOX = NO`, `CODE_SIGN_IDENTITY = "-"` (ad-hoc).

---

## 2. Architecture

### 2.1 Menu bar icon

`MenuBarIcon.image(period:dark:)` draws into a 46×22 `NSBitmapImageRep` at 2× and wraps the result
in an `NSImage`. The bitmap is cached by `"<period>-<dark>-<color>"`, so a redraw only happens when
the period, the menu bar appearance or the palette actually changes.

`AppDelegate.renderMenuBar()` runs once per second (and whenever the store changes). It builds a key
from `period | countdown | dark` and returns early when the key is unchanged, which keeps the status
item from being touched 86 400 times a day for nothing.

The dark/light decision comes from `button.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])`
and is re-evaluated every second, so it follows the system appearance within a second. It is
**not** driven by KVO — see the pitfalls in section 4.

### 2.2 The panel

Clicking the icon opens a custom `NSPanel` (see `Views/StatusPanel.swift`), **not** an `NSPopover`.

`NSPopover` decides its own position, and when its idea of the available space is wrong (multiple
displays, scaled resolutions, the status bar window not being placed yet right after launch) it
flips direction and pushes the top half of the window off-screen — the user sees only the bottom
half of the content. Owning the window fixes that:

- `AppDelegate.panelOrigin(for:button:screen:)` centres the panel under the icon, then clamps it
  into `screen.visibleFrame`; if it does not fit below the icon it is placed above it.
- `anchorRect(for:screen:)` falls back to "right end of the menu bar" when the icon's screen rect is
  not usable (this happens in the first few dozen milliseconds after launch, when the status bar
  window has not been positioned yet and `convertToScreen` returns an off-screen rect).
- `NSHostingView` resizes the window to its own fitting size once it is installed as the content
  view, keeping the top edge fixed, so the origin is corrected once more on the next run loop.
- If the content is taller than the screen, `StatusPanelContent` wraps it in a `ScrollView` instead
  of letting it be clipped.
- Window settings: `styleMask: [.borderless, .nonactivatingPanel]`, `level = .statusBar`,
  `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = true`,
  `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]`.
- Dismissal: a global monitor for mouse-down outside the panel, a local monitor for
  <kbd>Esc</kbd>, and the status item button itself. This reproduces `NSPopover`'s `.transient`
  behaviour without handing over control of the geometry.

Panel width is `PopoverView.width` (320 pt). Its natural height is about 594 pt (about 619 pt while
the preview banner is visible).

### 2.3 Pricing model

`Models/PricePeriod.swift`:

- `PricePeriod` — `.peak` / `.offPeak`, with `priceMultiplier` (1.0 / 0.5) and the (localized) display strings.
- `DeepSeekPricing` — a fixed `Asia/Shanghai` calendar, `peakHourRanges = [9..<12, 14..<18]`,
  `period(at:)`, `nextTransition(after:)`, `currentIntervalStart(before:)`.
- Ranges are half-open: 09:00 is peak, 12:00 is off-peak, 14:00 is peak, 18:00 is off-peak.
- Weekends are off-peak all day, so the next transition from Friday 18:00 is Monday 09:00.
- Everything is computed from the Beijing calendar, so the result does not depend on the Mac's own
  time zone (there is a self-check for this, see section 5).

`Models/PricingStore.swift` is a `@MainActor` `ObservableObject` that ticks once per second on a
`Timer` added to the `.common` run loop mode, and additionally refreshes on
`NSSystemClockDidChange`, `NSCalendarDayChanged`, `NSApplication.didBecomeActiveNotification` and
`NSWorkspace.didWakeNotification` — so the display is correct immediately after a wake or a manual
clock change instead of up to a second later. It also owns the user preferences
(`previewPeriod`, `showsCountdownInMenuBar`, `launchAtLogin`).

### 2.4 The whale

There are **no image assets** for the whale. The official DeepSeek mark is embedded as an SVG path
string (24×24 viewBox, from the Simple Icons CC0 collection) and parsed at runtime:

- `Support/SVGPath.swift` — parser for `M/m L/l H/h V/v C/c S/s Q/q T/t A/a Z/z`; elliptical arcs are
  converted to cubic Béziers using the algorithm from SVG 1.1 appendix F.6.
- `Views/WhaleShape.swift` — the path data, `unitPath`, bounding box, and `path(fitting:)` which
  scales the path to a target rect. Scaled paths are cached (32 entries) with the target rect
  quantized to 0.01 pt, so the per-frame cost is one transform lookup.
- `Views/WhaleScene.swift` — the shared motion constants and the SwiftUI drawing used by the panel
  aquarium:
  - peak: cosine-eased horizontal patrol (4.2 s per round trip), bobbing, ±8° body tilt, bubbles
    behind the tail;
  - off-peak: breathing scale plus a slow float, −7° lean, three `z`s rising and fading;
  - `menuBarWhaleWidth(forStageHeight:)` scales the whale so it fits the 22 pt menu bar with a
    small margin.
- `Views/WhaleStage.swift` / `AquariumView.swift` — the panel's aquarium canvas (30 fps, only while
  the panel is open).
- `Views/WhaleStatusItemView.swift` — an alternative Core Animation implementation
  (`CAKeyframeAnimation` on a `CAShapeLayer`), currently unused because a custom view inside
  `NSStatusItem` is exactly what section 4.1 warns about. It is kept as the starting point if the
  menu bar whale ever needs to animate again.

### 2.5 Colors

`Support/WhaleTheme.swift` holds the brand colors and the palettes:

| Scene | Peak | Off-peak |
| --- | --- | --- |
| Dark menu bar | bright sky blue `#A8D4FF` (flat) | near-white pale blue-lavender (flat) |
| Light menu bar | brand blue `#4D6BFE` (flat) | dark slate blue (flat) |
| Panel aquarium | `#4D6BFE` family on a navy tank | soft gray-blue on a night tank |

The menu bar palettes are flat (`isFlat: true`): at 22 pt tall a gradient is invisible, and
per-frame gradient shading is measurably more expensive. `Preview/menubar-color-candidates.png`
is the comparison sheet that was used to pick `#A8D4FF` — on a translucent gray-blue menu bar,
mid-saturation blues blend into the backdrop, so contrast has to come from lightness.

### 2.6 Launch at login

`Support/LaunchAtLogin.swift` wraps `SMAppService.mainApp` (`register()` / `unregister()` /
`status`). The toggle surfaces an error message in the panel when registration fails
(e.g. when the app is run from a build directory rather than `/Applications`).

### 2.7 Localization

The base (development) language is **English**; **Simplified Chinese** ships as a translation. The
project's `knownRegions` already lists `en`, `zh-Hans` and `Base`, and `CFBundleDevelopmentRegion`
is `en`.

- All UI strings live in `DeepSeekStatus/Localizable.xcstrings` (a String Catalog, compiled into
  `en.lproj` and `zh-Hans.lproj`). Being under the file-system-synchronized group, it needs no
  `project.pbxproj` edit.
- Call sites use explicit semantic keys, e.g.
  `String(localized: "period.peak.title", defaultValue: "Peak hours")`.
- Dynamic strings keep explicit placeholders and are composed with `String(format:)`, e.g.
  `popover.countdown.detail` = `"Switches to %2$@ %1$@"` / `"%1$@ 起转为%2$@"`.
- English plurals use separate `.one` / `.other` keys chosen in `PricingFormatter` (`1 day` vs `%lld days`).
- Dates and weekdays follow the UI language via `PricingFormatter.displayLocale`, so `Mon` / 「周一」
  match the interface; times stay 24-hour `HH:mm` on purpose.
- Known limitation: the `[诊断]` logging behind `DEEPSEEK_STATUS_DIAGNOSTICS=1` is developer-facing and
  still uses hard-coded Chinese labels.

---

## 3. Build & run

```bash
./Tools/build.sh            # Debug
./Tools/build.sh release    # Release
./Tools/build.sh run        # Debug, then relaunch the app
```

`Tools/build.sh` exports `TMPDIR`, `CLANG_MODULE_CACHE_PATH` and `SWIFT_MODULE_CACHE_PATH` into the
project's own `Build/` directory, so the build also works in environments where the system temp
directory is not writable (that was a real failure mode in a sandboxed shell:
`Couldn't create workspace arena folder … Operation not permitted`).

The Xcode project uses a file-system-synchronized root group, so adding a `.swift` file under
`DeepSeekStatus/` requires no `project.pbxproj` edit.

---

## 4. Pitfalls (measured, not guessed)

### 4.1 Never put a custom view in `NSStatusItem`

`NSStatusItem` continuously re-snapshots any view placed in the button:

```
-[NSStatusItem _updateReplicantsUnlessMenuIsTracking:]
  → -[NSStatusItem _redrawReplicantSnapshot:sourceView:]
    → -[NSView cacheDisplay:in:to:]
      → -[CALayer renderInContext:]
```

This runs regardless of whether anything is animating. Measured idle CPU: **~28%** with a SwiftUI
`TimelineView` + `Canvas`, **~24–30%** with Core Animation, and still **~23% with the animation
switched off entirely**. Handing a pre-rendered `NSImage` to `button.image` instead brings idle CPU
to **~0%** (0.00 s of CPU time over a 10 s window, as reported by `ps`).

### 4.2 Never KVO `button.effectiveAppearance` to swap the image

Setting the image re-triggers the appearance notification, which sets the image again: an infinite
loop that pinned a core at **~90%**. The appearance is therefore re-read once per second inside the
regular refresh instead.

### 4.3 Measure the panel with `NSHostingView`, not `NSHostingController.view`

`NSHostingController`'s view reports `fittingSize == .zero` before its first layout pass, so a window
sized from it comes out **0 pt tall** — the panel simply does not appear. Build an
`NSHostingView(rootView:)` directly to measure. In addition, once an `NSHostingView` becomes a
window's content view it forces the window to its own fitting size (keeping the top edge fixed), so
the window origin has to be corrected on the next run loop.

### 4.4 Don't draw into `NSImage(size:flipped:drawingHandler:)` for the status item

The drawing handler is re-invoked on every menu bar redraw rather than being cached, which measured
**~90% CPU**. Rasterize into an `NSBitmapImageRep` once and cache the resulting `NSImage`.

---

## 5. Tooling

### 5.1 Offscreen rendering

Renders the real SwiftUI views with `ImageRenderer`; no window, no screen recording permission.

```bash
./Tools/render-preview.sh              # → Preview/*.png
./Tools/render-preview.sh icons        # → App icon source images
./Tools/render-preview.sh measure      # print the natural size of each view
./Tools/render-preview.sh schedule     # pricing schedule self-check
./Tools/render-preview.sh candidates   # menu bar color candidate sheet
```

`render-preview.sh` compiles every source file except `DeepSeekStatusApp.swift` (the `@main` entry
point) together with `Tools/Snapshot/main.swift` via `swiftc`, into `Build/snapshot/`.

The `preview` mode writes, among others: menu bar strips on light / dark / translucent-gray
backdrops in both periods, the two full panels, the aquarium, the weekly grid, the whale vector,
and animation breakdown sheets (`swim-phases.png`, `sleep-phases.png`).

### 5.2 Runtime diagnostics

```bash
DEEPSEEK_STATUS_DIAGNOSTICS=1 \
DEEPSEEK_STATUS_CAPTURE="$PWD/Preview" \
  ./Build/DerivedData/Build/Products/Debug/DeepSeekStatus.app/Contents/MacOS/DeepSeekStatus
```

Prints the status item button's frame, its on-screen rect, the panel window's frame, level and
content size, whether the panel is fully inside `visibleFrame`, and how many frames the SwiftUI
canvas drew in the last two seconds. It also writes `live-menubar-1.png`,
`live-menubar-2.png` and `live-panel-<period>.png` into the capture directory using
`cacheDisplay` — which goes through the view's own drawing path and therefore needs no screen
recording permission. The app terminates itself after a few seconds.

Environment variables:

| Variable | Effect |
| --- | --- |
| `DEEPSEEK_STATUS_DIAGNOSTICS=1` | Run the self-check above and exit |
| `DEEPSEEK_STATUS_CAPTURE=<dir>` | Where the diagnostics write their PNGs |
| `DEEPSEEK_STATUS_PREVIEW=peak\|offPeak` | Force a period at launch (used for screenshots) |

### 5.3 Regenerating the app icon

```bash
./Tools/render-preview.sh icons Preview/AppIcon
cp Preview/AppIcon/*.png DeepSeekStatus/Assets.xcassets/AppIcon.appiconset/
```

---

## 6. Verification

`./Tools/render-preview.sh schedule` covers 13 boundary cases — 09:00, 12:00, 14:00 and 18:00 from
both sides, the Friday-evening-to-Monday-morning span, and time-zone independence
(`America/Los_Angeles`, `Europe/London`, `Asia/Tokyo`, `UTC`). All of them pass, e.g.:

```
✅ 周一 08:59 → Off-peak hours，下次切换 today 09:00（转为Peak hours）
...
✅ 时区无关性：周一 10:30 北京时间 = Peak hours（与本地时区无关）
全部通过 ✅
```

A panel placement check on a 2560×1410 display, with the status item at `(1359, 1414, 46, 22)`:

```
面板窗口=(1222.0, 810.0, 320.0, 594.0)   ← centred under the icon, 1222 + 160 = 1382 = icon centre
屏幕可见区域=(0.0, 0.0, 2560.0, 1410.0)
面板是否完全在可见区域内=true
最近 2 秒 SwiftUI 画布重绘 60 帧 ≈ 30.0 fps（只剩下已打开的面板水族箱）
```

With the panel closed, idle CPU is 0.0% and the menu bar icon does not repaint (two captures taken
0.6 s apart are byte-identical).

---

## 7. Notes and limitations

- Screen recording is not available in the environment this app was developed in
  (`screencapture` fails with "could not create image from display"), which is why verification
  relies on offscreen `ImageRenderer` output plus `cacheDisplay` captures from inside the app.
- The schedule is a weekday/time-of-day rule; there is no holiday calendar.
- The app is ad-hoc signed. Distributing a build to other machines requires notarization, or the
  quarantine workaround described in the README.
- `WhaleStatusItemView` (Core Animation) is compiled but unused. Re-enabling it means solving the
  status item snapshot cost from section 4.1 first.
