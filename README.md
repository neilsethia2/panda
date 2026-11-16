# Panda

A small panda that lives in your Mac's menu bar and closes Instagram and YouTube Shorts tabs
before you fall into them. Normal YouTube videos are left alone.

Native macOS app (Swift, SwiftUI, AppKit). No server, no account, nothing leaves the Mac.

## Install

**Download:** open the [latest release](../../releases/latest), download `Panda.dmg`, open it and
drag Panda into Applications. This build is not notarised by Apple, so the first time you open it
macOS will refuse. Go to System Settings > Privacy & Security, scroll down, click **Open Anyway**.
You do that once.

**Or build it yourself:** double-click `Build and Install Panda.command`. It compiles the app with
Xcode's tools, copies it into Applications and opens it. An app you build on your own Mac opens
with no warning.

Requires macOS 13 or later. Runs on Apple Silicon and Intel.

## First launch

A setup screen opens with three steps:

1. **Chrome extension.** Open `chrome://extensions`, turn on Developer mode, click Load unpacked and
   pick the folder Panda shows you (`~/Library/Application Support/Panda/ChromeExtension`). The same
   extension works in Arc, Brave, Edge and Vivaldi.
2. **Safari.** Nothing to install. The first time Safari is in front with protection on, macOS asks
   whether Panda may control Safari. Click Allow.
3. **Notifications and launch at login.** Both optional.

## How it works

| Piece | What it does |
| --- | --- |
| `Sources/Panda` | The menu bar app: settings, statistics, the panda, dashboard, setup. |
| `Sources/Host` | `panda-host`, a tiny native-messaging helper that Chrome starts. It answers one question: should this address be closed? |
| `Sources/Shared` | The blocking rules, used by both of the above. |
| `Extension/chrome` | Manifest V3 extension. Watches tab address changes, asks the host, closes the tab. |

**Chrome and other Chromium browsers** are event driven. The extension wakes only when a tab's
address changes, including YouTube's in-page navigation from a normal video to a Short. Nothing
polls.

**Safari** (and any Chromium browser without the extension) is handled by the app through macOS
Automation: once a second, and only while that browser is the frontmost app, Panda asks for the
address of the front tab.

**Rules**

- `instagram.com` and its subdomains: closed when Instagram protection is on.
- `youtube.com/shorts/...`: closed when YouTube protection and Block Shorts are on.
- Every other YouTube address: left alone, unless you turn off "Allow normal YouTube videos".
- Master protection off: nothing is closed.

## Privacy

Panda looks at tab addresses and nothing else. It does not read pages, take screenshots or make
network requests. Statistics are a small JSON file of daily counts in
`~/Library/Application Support/Panda`.

## Building

```
./Scripts/build.sh
```

produces `build/Panda.app` and `build/Panda.dmg`. Needs Xcode or the Command Line Tools.

To sign with a paid Apple Developer ID and notarise:

```
PANDA_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
PANDA_NOTARY_PROFILE=your-notarytool-profile \
./Scripts/build.sh
```

Every push to `main` is built on GitHub's Mac runners, which also run `Scripts/smoke_test.py`
against the real binary and render every screen to an image.

## Limits worth knowing

- Safari is covered through Automation, not a Safari Web Extension. Apple only lets Safari load
  extensions signed with a paid developer account.
- The Chrome extension is loaded unpacked, so Chrome occasionally shows a developer-mode reminder.
- Private or Incognito windows are covered only if you allow the extension in Incognito.
- Where Panda lands on the tab bar is estimated from the window position and tab count. It is close,
  not pixel exact.
