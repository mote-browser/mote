<div align="center">

<img width="2000" height="1180" alt="hero" src="https://github.com/user-attachments/assets/89bb46b8-239e-40a8-9429-eeb15a031c1c" />

**The whole web. A fraction of the weight.**

macOS 14 or later · Apple silicon · free and open source · [build it yourself](#build-it)

</div>

## Why another browser

Every Mac already has a great web engine. It is WebKit, the one Safari runs on. Chrome, Arc, Dia, Edge and Firefox each ship their own engine on top of it, and that costs hundreds of megabytes on disk and in memory.

Mote is the browser built around the engine you already have. It is native, it opens instantly, and the whole app is about the size of a photo.

<img width="1600" height="900" alt="weight" src="https://github.com/user-attachments/assets/bd15de41-2460-4d89-8a19-6905dc45a15c" />

## What you get

<img width="2000" height="820" alt="field" src="https://github.com/user-attachments/assets/c8fe17fe-7f2d-4a38-b162-908e895566ea" />

- **One field** for addresses, searches and open tabs. Nothing you type leaves the Mac until you press Return.
- **Ads and trackers blocked** at the network level, before the page loads.
- **Chrome extensions** from the Chrome Web Store, running on WebKit.
- **Reading mode, floating video** and a click to hide any cookie banner for good.

<img width="2000" height="820" alt="keychain" src="https://github.com/user-attachments/assets/85b7b58a-1348-4981-b27c-d3a5e03df360" />

- **Passwords in the macOS keychain.** Import them from Chrome, Arc, Dia, Brave or Edge in one click.
- **No account, no sync, no telemetry.** Your history and bookmarks are files on your Mac.

## Install

Download [Mote.dmg](https://github.com/mote-browser/mote/releases/latest/download/Mote.dmg) and drag Mote to Applications.

Mote is not signed with an Apple Developer ID or notarized yet, so the first time you open it macOS blocks it. To let it through:

1. Open Mote once. macOS says it cannot verify the app. Click **Done**.
2. Open **System Settings › Privacy & Security** and scroll down to **Security**.
3. Next to "Mote.app" was blocked to protect your Mac, click **Open Anyway** and confirm with your password.

<img width="482" height="188" alt="security" src="https://github.com/user-attachments/assets/f5a945f5-9dc8-4636-9548-94c533585f64" />

You only need to do this once. If you prefer the terminal, this does the same:

```sh
xattr -dr com.apple.quarantine /Applications/Mote.app
```

## Build it

```sh
git clone https://github.com/mote-browser/mote
cd mote
make build      # Release Mote.app in build/
make fresh      # open it in a clean test profile
```

Needs Xcode 26. About 27,000 lines of Swift, with no dependencies beyond what Apple ships. SwiftUI and AppKit for the app, WKWebView for pages, and `Packages/MoteKit` for the logic that is unit-tested on its own. Run `make test` for the suite.

## License

GPL-3.0. Security issues go through [SECURITY.md](SECURITY.md).
