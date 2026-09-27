<div align="center">

<img width="2000" height="1180" alt="Mote, a quiet browser for the Mac" src="UPLOAD-hero.webp" />

**The whole web. A fraction of the weight.**

macOS 14 or later · Apple silicon · free and open source · [build it yourself](#build-it)

</div>

## Why another browser

Every Mac already has a great web engine. It is WebKit, the one Safari runs on. Chrome, Arc, Dia, Edge and Firefox each ship their own engine on top of it, and that costs hundreds of megabytes on disk and in memory.

Mote is the browser built around the engine you already have. It is native, it opens instantly, and the whole app is about the size of a photo.

<img width="1600" height="900" alt="The whole browser, about the size of a photo" src="UPLOAD-weight.webp" />

## What you get

<img width="2000" height="820" alt="One field for an address, a few words or an open tab" src="UPLOAD-field.webp" />

- **One field** for addresses, searches and open tabs. Nothing you type leaves the Mac until you press Return.
- **Ads and trackers blocked** at the network level, before the page loads.
- **Chrome extensions** from the Chrome Web Store, running on WebKit.
- **Reading mode, floating video** and a click to hide any cookie banner for good.

<img width="2000" height="820" alt="Your passwords stay in your keychain" src="UPLOAD-keychain.webp" />

- **Passwords in the macOS keychain.** Import them from Chrome, Arc, Dia, Brave or Edge in one click.
- **No account, no sync, no telemetry.** Your history and bookmarks are files on your Mac.

## Build it

```sh
git clone https://github.com/mote-browser/mote
cd mote
make build      # Release Mote.app in build/
make fresh      # open it in a clean test profile
```

Needs Xcode 26. About 27,000 lines of Swift, with no dependencies beyond what Apple ships. SwiftUI and AppKit for the app, WKWebView for pages, and `Packages/MoteKit` for the logic that is unit-tested on its own. Run `make test` for the suite.

Builds are not notarized yet, so the first launch needs right-click › Open.

## License

GPL-3.0. Security issues go through [SECURITY.md](SECURITY.md).
