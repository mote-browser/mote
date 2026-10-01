# Changelog

What changes in Mote from one version to the next, newest first.

**Unreleased** gathers what's done since the last version, as it lands. When
a version ships, the section takes its number and date, as in
`## <version> — <date>`, with one line under the heading saying what it
brings: that line is what Settings shows beside the update, and the whole
section becomes the release's notes (see `Tools/release/appcast`).

## Unreleased

## 0.2.2 — 2026-10-01

The whole address now shows for local and plain-http pages too.

### Fixed

- "Show the whole address" ignored `http://` pages, localhost and local
  servers included, and showed only their site. Every address now shows in
  full, extension pages too.
- With it off, local servers keep their port (`localhost:3000`), so two of
  them no longer look the same.

## 0.2.1 — 2026-10-01

The toolbar shows the whole address again.

### Changed

- The address bar now shows the page's full web address, exactly as it is,
  instead of only its site. If you prefer the short form, turn off "Show the
  whole address" in Settings.

## 0.2.0 — 2026-09-29

Ask the AI you choose, right from a new tab, and research the web with sources.

### Added

- **Ask in a new tab.** Press ⌘J (or the Ask button) and Return asks the
  assistant instead of searching; the composer lights up while it does. The
  answer opens as a chat you can follow up in.
- **The AI you choose.** The agents already on your Mac (Claude Code, Codex,
  opencode, Gemini CLI), models that run on it (Apple Intelligence, Ollama,
  LM Studio) or your own API keys (Anthropic, OpenAI, Google Gemini,
  OpenRouter, Mistral, Groq, DeepSeek, xAI and any OpenAI-compatible server).
  Keys stay in the Keychain, and questions go straight to the provider.
- **Answers from the web.** The assistant searches when a question needs it,
  with each claim cited and its sources listed under the answer.
- **Research.** Turn it on for a question and the assistant plans the parts
  to look into, researches them side by side, and writes a report with its
  sources.
- **Chats are kept.** Recent chats show under the new tab's composer, and all
  of them, by date and searchable, in a tab of their own; chat tabs come back
  when Mote opens again. Private tabs keep nothing.
- Replies appear word by word at a reading pace, each word fading in.

## 0.1.4 — 2026-09-28

Fixes the sidebar staying on screen after folding it away, for real this time.

### Fixed

- Folding the sidebar away, most of all the first time after opening Mote,
  could leave it on screen with the traffic lights gone. 0.1.3's fix asked the
  window to draw again, which didn't move the stuck slide on; the window now
  gets a real change, and the sidebar goes within a second.

## 0.1.3 — 2026-09-28

Fixes the sidebar staying on screen after folding it away.

### Fixed

- Folding the sidebar away with its button could leave it drawn on screen,
  with the traffic lights gone, until something else redrew the window, such
  as opening Settings. The window is now drawn again when the slide hasn't
  finished in time.

## 0.1.2 — 2026-09-28

Smoother scrolling, and tabs that stay under the pointer as you drag them.

### Fixed

- Dragging a tab to a new place made it jump back a place each time it passed
  another, in the tab strip, the sidebar and the pinned tabs. The tab now
  follows the pointer, the others step aside, and it settles into its place
  when let go.
- Pages could show their frames unevenly while scrolling, most on pages that
  animate as they scroll: the reading progress on the tab redrew the whole
  window as it filled, and a check for sign-in fields ran on every frame.

### Changed

- The reading progress on a tab fills in whole-percent steps, without easing.
- A pinned tab dragged past the edge of the pin grid stays in its row instead
  of wrapping to the next.

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
