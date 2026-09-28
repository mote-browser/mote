# Changelog

What changes in Mote from one version to the next, newest first.

**Unreleased** gathers what's done since the last version, as it lands. When
a version ships, the section takes its number and date, as in
`## <version> — <date>`, with one line under the heading saying what it
brings: that line is what Settings shows beside the update, and the whole
section becomes the release's notes (see `Tools/release/appcast`).

## Unreleased

## 0.1.1 — 2026-09-28

Fixes the traffic lights staying on screen when the sidebar folds away.

### Fixed

- The window's traffic lights could stay behind when the sidebar was folded
  away, mostly on the first launch after starting the Mac.

## 0.1.0

The first version: a quiet browser for the Mac, on the WebKit it already has.

### Added

- Tabs across the top or down the side, a sidebar that folds away and slides
  back out at the window's edge, pinned tabs, tabs that sleep when unused,
  and spaces for separate sets of tabs.
- One field for addresses and searches, completing from your history.
- Reading mode, floating video, and hiding any part of a page for good.
- An ad and tracker blocker that works inside WebKit, before anything loads.
- Passwords and passkeys in the Mac's keychain, with import from Chrome, Arc,
  Dia, Brave and Edge.
- Bookmarks, history and downloads, each a panel away.
- Chrome extensions from the Chrome Web Store or a folder, on macOS 15.4 or
  later.
- Updates that install themselves, checked against Mote's own signature.
