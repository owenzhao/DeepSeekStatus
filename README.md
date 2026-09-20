<div align="center">

# 🐳 DeepSeek Status

**A tiny macOS menu bar app that tells you — at a glance — whether DeepSeek is in peak or off-peak pricing, and how much is left in your API balance.**

<img src="Preview/menubar-gray-peak.png" width="640" alt="DeepSeek Status in the menu bar">

[![Download](https://img.shields.io/github/v/release/owenzhao/DeepSeekStatus?label=download&color=4D6BFE)](https://github.com/owenzhao/DeepSeekStatus/releases/latest)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)](#requirements)
[![Swift](https://img.shields.io/badge/Swift-5-orange)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Network](https://img.shields.io/badge/network-limited-brightgreen)](#privacy)

</div>

Idle (off-peak) pricing is half the peak price, so "are we in peak hours right now?" is a question
worth answering without opening a browser tab. DeepSeek Status answers it with a whale.

- 🔵 **Peak hours** — a bright DeepSeek-blue whale, head up, bubbles trailing behind its tail.
- 😴 **Off-peak hours** — a pale, sleepy whale lying on its side, with little `z`s floating above it.

Click the whale to open a panel with the current period, the price multiplier, a live countdown to
the next switch, a monthly pricing calendar, a weekly schedule heat map, and — once you paste an API key — the balance left on
your DeepSeek account. Optionally it can also show the countdown directly next to the menu bar icon.

---

## Screenshots

| Peak hours (`×1.0`) | Off-peak hours (`×0.5`) |
| :---: | :---: |
| <img src="Preview/live-panel-peak.png" width="330" alt="Panel during peak hours"> | <img src="Preview/live-panel-offPeak.png" width="330" alt="Panel during off-peak hours"> |
| *Captured live; the banner is preview mode being on.* | *Captured live during off-peak hours.* |

Menu bar in both states and on different menu bar backgrounds:

| | Peak | Off-peak |
| :--- | :---: | :---: |
| **Dark menu bar** | <img src="Preview/menubar-dark-peak.png" width="330"> | <img src="Preview/menubar-dark-offPeak.png" width="330"> |
| **Translucent / light menu bar** | <img src="Preview/menubar-light-peak.png" width="330"> | <img src="Preview/menubar-light-offPeak.png" width="330"> |

---

## Pricing rule

> Off-peak pricing is half of peak pricing.
> Peak hours are **Monday–Friday 09:00–12:00 and 14:00–18:00, Beijing time**. Everything else is off-peak.

| Time (Beijing) | Period | Price |
| --- | --- | --- |
| Mon–Fri 09:00–12:00 | Peak | 100% |
| Mon–Fri 12:00–14:00 | Off-peak | 50% |
| Mon–Fri 14:00–18:00 | Peak | 100% |
| Mon–Fri 18:00–09:00 (next day) | Off-peak | 50% |
| Saturday and Sunday, all day | Off-peak | 50% |
| Chinese public holidays, all day | Off-peak | 50% |

Details:

- Ranges are **half-open**: 12:00 sharp is already off-peak, 18:00 sharp is already off-peak,
  and 09:00 sharp is already peak.
- The decision is **always made in Beijing time** (`Asia/Shanghai`, UTC+8, no daylight saving),
  regardless of your Mac's time zone. If your Mac is in a different time zone, the panel says so.
- Weekend make-up workdays remain off-peak all day. Weekdays included in the official Chinese
  holiday schedule are also off-peak all day.

---

## Requirements

- macOS **14.0 (Sonoma)** or later.
- Apple Silicon or Intel. The app is developed and tested on Apple Silicon (arm64); there is no
  architecture-specific code.

---

## Installation

### Build from source

Requires **Xcode 16 or later** — the project uses the file-system-synchronized group format
(`objectVersion = 77`). The Command Line Tools alone are enough for `Tools/build.sh`.
Developed with Xcode 27; the deployment target is macOS 14.0.

```bash
git clone <this repository>
cd DeepSeekStatus

./Tools/build.sh run     # build (Debug) and launch
```

Other options:

```bash
./Tools/build.sh          # Debug build only
./Tools/build.sh release  # Release build
```

The product lands in `Build/DerivedData/Build/Products/<configuration>/DeepSeekStatus.app`.

Or just open `DeepSeekStatus.xcodeproj` in Xcode, select the `DeepSeekStatus` scheme and press ⌘R.

### Prebuilt app

1. Grab the newest `DeepSeekStatus-<version>.zip` from the
   **[Releases page](https://github.com/owenzhao/DeepSeekStatus/releases/latest)**.
   The binary is universal — Apple Silicon and Intel — and needs macOS 14.0 or later.
2. Unzip it and drag `DeepSeekStatus.app` into `/Applications`.
3. The app is signed with a **Developer ID and notarized by Apple**, so it launches without a
   Gatekeeper prompt — no quarantine workaround needed.

Either way the app has **no Dock icon** — look for the whale in the menu bar, right of the
menu bar extras.

---

## Usage

| Action | What happens |
| --- | --- |
| **Left-click** the whale | Open / close the details panel |
| **Right-click** the whale | Quick menu: preview peak, preview off-peak, follow live time, show countdown in the menu bar, quit |
| **Account balance** | Appears in the panel once an API key is saved. **Refresh** queries it immediately; the time of the last successful refresh sits next to the button |
| **Enter / Change API Key** | Opens the key field in the panel. The key is stored in the macOS Keychain; **Remove** deletes it |
| **Preview** picker in the panel | Force the app to *display* peak or off-peak so you can see both looks at any time. It only changes what is drawn, never the real pricing |
| **Show countdown in the menu bar** | Adds an `HH:MM:SS` countdown next to the whale (off by default) |
| **Launch at login** | Registers the app as a login item via `SMAppService` (off by default) |
| **Auto-check for updates** | Sparkle checks the appcast in the background (on by default). **Check Now** in the panel, or **Check for Updates…** in the right-click menu, runs a check immediately |
| **Quit** | Quits the app |

The panel contains:

- the current period and its price multiplier (`×1.0` / `×0.5`);
- a "current unit price" comparison bar;
- the countdown to the next switch, plus how far through the current block you are;
- **the account balance** once an API key is saved — total, plus the granted / topped-up split, a
  Refresh button and the time of the last successful refresh;
- a monthly pricing calendar for planning ahead, switchable to a 7×24 weekly heat map;
- the toggles above, a preview picker, and the update controls.

The panel closes when you click anywhere outside it, press <kbd>Esc</kbd>, or click the whale again.

---

## Privacy

The pricing panel needs no account or API key. The app talks to the network in three narrowly scoped places:

- **Balance** (opt-in) — if you save a DeepSeek API key, the app calls
  `GET https://api.deepseek.com/user/balance` on launch, every 5 minutes, and when the panel opens or
  the Mac wakes with stale data. Your key is sent only in the `Authorization` header of that one
  request. **With no key saved, no request is ever made.**
- **Updates** — Sparkle reads the appcast from this repository's latest GitHub release (daily by
  default, switchable off in the panel).
- **Holiday calendar** — at most once per day, the app anonymously checks Apple’s public China
  holiday calendar. It sends no API key, device-calendar data or other user information, and uses
  bundled/cached data while offline.

There is **no analytics and no telemetry**. The API key lives in your **macOS Keychain** — the entry
is encrypted by the system and readable after first unlock — never in a plain-text preferences file,
and **Remove** in the panel deletes it. It is deliberately *not* wrapped in a second layer of
home-made encryption: the key to that would have to sit in the same Keychain anyway, which buys
nothing. The app also stores the normalized holiday cache and the optional login item registration.

---

## FAQ

**Does it call the DeepSeek API or need an API key?**
Only if you want the balance. Pricing works with no key: it reads the local clock and the public
holiday schedule. If you paste a key into the panel, the app stores it in the Keychain and
calls `GET /user/balance` to show what is left. That is the only DeepSeek endpoint it ever calls, and
the balance is **account-wide**: every key of an account returns the same numbers.

**Where is the API key stored, and how do I delete it?**
In the macOS Keychain, as a generic password scoped to this app
(`com.parussoft.DeepSeekStatus.deepseek`). It is never written to `UserDefaults` or any plain file, and
it is not encrypted a second time by the app itself — see [Privacy](#privacy) for why. **Remove** in
the panel's key editor deletes it.

**My key expired. Can I still replace it?**
Yes, and that case is handled explicitly: a failed refresh always offers **Change API Key**, and an
expired key is reported as *"The API key is invalid or expired. Replace it?"*. A working key can be
replaced too, from the small key button next to the refresh time.

**Which time zone is used?**
Beijing time (`Asia/Shanghai`, UTC+8, no DST) always, no matter where your Mac is. This is
deliberate: the pricing schedule is defined in Beijing time.

**Are Chinese public holidays handled?**
Yes. DeepSeek Status downloads Apple’s public China holiday calendar directly, without reading or
modifying your Calendar app and without requesting calendar permission. Weekday holidays and
weekend make-up workdays are shown in the monthly pricing calendar.

**Why is the menu bar whale not animated?**
On purpose. `NSStatusItem` continuously re-snapshots any custom view placed in it, which costs
20–30% CPU even with no animation at all. A static bitmap drawn once into `button.image` keeps idle
CPU at ~0%. The aquarium in the panel *is* animated, but it only runs while the panel is open.
See [Docs/DEVELOPMENT.md](Docs/DEVELOPMENT.md) for the measurements.

**Why does the whale change color between dark and light menu bars?**
The menu bar is translucent, so its backdrop depends on the wallpaper. A single color cannot have
enough contrast on both, so the app picks the palette per appearance: light blue on a dark menu bar,
brand blue on a light one.

**Which languages does the UI support?**
English (the default) and Simplified Chinese. The interface follows the language chosen for the app in
**System Settings → General → Language & Region → Applications**; the pricing schedule itself is always
computed in Beijing time. All UI strings live in a single String Catalog
(`DeepSeekStatus/Localizable.xcstrings`), so adding another language is just another column there.

**How do updates work?**
The app ships [Sparkle 2](https://sparkle-project.org) and reads the appcast at
`releases/latest/download/appcast.xml`. Downloads are signed with an EdDSA key and verified before
anything is installed, and every update is opt-in. Background checks are on by default (one per day)
and can be turned off in the panel. Maintainers publish with `./Tools/release.sh --upload`.

**Does the countdown update while the Mac is asleep?**
The app recomputes on wake, on system clock changes, and at midnight, so it is correct as soon as
the machine is back.

---

## How it works

- The whale is DeepSeek's own logo, embedded as a **vector path** — there are no image assets.
  A small SVG path parser (`M/L/H/V/C/S/Q/T/A/Z`, including elliptical arcs converted to cubic
  Béziers) parses it at runtime, so it stays sharp at any size and can be recolored freely.
- The menu bar icon is rasterized **once** into a 46×22 `NSImage` and handed to
  `NSStatusItem.button.image`.
- The panel is a self-positioned `NSPanel` (not `NSPopover`), so it can never be pushed off-screen.
- The schedule is computed from a fixed `Asia/Shanghai` calendar with half-open intervals and the
  cached Chinese public-holiday schedule; the app refreshes on clock changes, day changes and wake.
- The balance is one `GET /user/balance` call carrying the key from the Keychain. Responses carry a
  token, so a reply that arrives after you have already saved a different key is discarded instead of
  overwriting the new key's state.

Architecture, tooling, measurements and the pitfalls found along the way are documented in
**[Docs/DEVELOPMENT.md](Docs/DEVELOPMENT.md)**.

---

## License

[MIT](LICENSE) © 2026 Zhao Xin

The whale is the official DeepSeek mark, taken from the [Simple Icons](https://simpleicons.org)
collection (CC0). "DeepSeek" and its logo belong to their owner. This project is an unofficial
utility and is not affiliated with or endorsed by DeepSeek.
