# Changelog

What changes in Mote from one version to the next, newest first.

**Unreleased** gathers what's done since the last version, as it lands. When
a version ships, the section takes its number and date, as in
`## <version> — <date>`, with one line under the heading saying what it
brings: that line is what Settings shows beside the update, and the whole
section becomes the release's notes (see `Tools/release/appcast`).

## Unreleased

## 0.4.6 — 2026-10-09

Pages whose header sits in the normal flow now colour the window from their theme colour.

### Fixed

- Pages that declare a theme colour but have no fixed header, such as web
  apps whose content scrolls under a static top bar, colour the tabs and
  toolbar from it instead of falling back to the page's white background.
- The line between the toolbar and the page takes on the page's colour
  instead of staying a flat gray.

## 0.4.5 — 2026-10-05

Updates are found at launch and announced first, and the folded sidebar can be resized while it peeks.

### Added

- The folded sidebar can be resized while it peeks out, from a grip on its
  edge. The width carries over to the docked sidebar, and the sidebar stays
  out while the grip is dragged or the pointer rests just past its edge.

### Changed

- Mote checks for updates at every launch as well as daily. A newer version is
  announced as soon as it is found, before it installs on its own.
- The floating sidebar has a clearer outline against the page.

### Fixed

- Pages and the new tab page no longer react to the pointer through the
  peeking sidebar: bookmarks and links behind it stop highlighting.
- A failed update check says so in Settings instead of showing "Up to date",
  and tries again after five minutes. Checking by hand while offline says it
  couldn't check.

## 0.4.4 — 2026-10-03

Window controls stay hidden from the first frame when reopening with folded tabs.

### Fixed

- Native window controls no longer flash or reappear after launching with
  the sidebar or top tabs folded. They are taken out of the system titlebar
  before the window is displayed and return when the tabs open or peek out.
- Folded window controls remain hidden when switching between tab layouts.

## 0.4.3 — 2026-10-03

Easier page-chat closing and hidden window controls when restoring a folded sidebar.

### Added

- A close button inside the page chat, aligned with the toolbar's chat button
  so the panel can be closed without moving the pointer after opening it.

### Changed

- The page-chat button is last in the toolbar, after bookmarks in the top-tab layout.

### Fixed

- Window controls stay hidden when Mote reopens with the sidebar folded,
  and return when the sidebar opens.

## 0.4.2 — 2026-10-03

Reliable sidebar folding, with each tab layout remembering whether its tabs are hidden.

### Fixed

- The sidebar folds away and opens again with a native macOS animation,
  keeping the window controls in place and responding to rapid clicks.
- The sidebar and top tab strip each remember their folded state when
  switching layouts and reopening Mote.

## 0.4.1 — 2026-10-03

A calmer new tab, smoother Ask animations, and clearer bookmarks and chat access.

### Changed

- A larger mark and wider composer on new tabs, with softer background colors
  and a warm glow when Ask is active.
- Ask's mark springs into color and then rests, with a quicker, coordinated
  transition into the composer.
- The sidebar's Chats button opens a searchable archive in a panel. Recent
  chats no longer sit beneath the new-tab composer.
- Larger bookmark labels and icons on new tabs, with more space above the bar
  and a softer shadow around the page.

### Fixed

- Bookmark icons load even before their pages have been visited and refresh
  when the appearance changes. GitHub's icon stays readable in dark mode.
- Tab dragging keeps its starting position stable while tabs move.
- Local builds explicitly target the Mac's architecture.

## 0.4.0 — 2026-10-02

A softer glass frame, colors that follow the page, and smoother tabs across the top.

### Added

- The toolbar and active tab take their color from the page, including fixed
  headers when WebKit can sample them. Their controls switch between light
  and dark to stay readable, and blank or failed pages use Mote's own colors.

### Changed

- A subtle native glass effect behind the browser frame, sidebar and bookmarks
  bar, with softer borders and shadows around the page.
- More compact top tabs with taller, rounder shapes; the active tab and page
  share one continuous surface.
- Larger toolbar controls and address text, with a search icon in the address
  field and a quieter new-tab page that hides the address and page-chat controls.
- New tabs show Mote's mark instead of a placeholder letter. Clicking their
  empty background focuses the composer.

### Fixed

- The active top tab joins the page without a doubled border or shadow,
  including when the tab strip scrolls.
- Dragged tabs stay clear of the window controls, detach from the page while
  moving, and settle into place before reattaching.
- The logo-rendering test follows Xcode 26's formatting rules so CI can pass.

## 0.3.0 — 2026-10-02

Chat about the page you're on, bring your other tabs into it, and get past a page that won't load.

### Added

- **Chat about this page.** ⇧⌘A (or the View menu) docks a chat beside the page
  you're reading, with its own conversation per tab, closed again with Escape.
- **Mention other tabs.** Type `@` in the composer to bring another open tab's
  page into the chat, so an answer can range across the pages you have open;
  remove a mention from its chip.
- **Ask about a selection.** Right-click selected text and choose "Ask about
  This" to open that tab's chat with your selection quoted, ready to send.
- **Slash skills.** Type `/` in the composer for the built-in skills; the one
  you pick fills the field, ready to edit or send.
- **A page that won't load.** Mote now shows its own failure page explaining
  what went wrong, and when a certificate can't be trusted, a way to go on
  anyway.

### Fixed

- The page chat's open state is kept per tab, and reopening it docks
  full-height like the left sidebar, with the sidebar's own animation.
- A chat's provider session stays in step with the page and tabs it has shared;
  changing that context starts the provider afresh.
- Page dialogs and certificate prompts now reach Mote, with WebKit's handler
  types matched.
- While a failure page is up, the toolbar shows the address that failed.

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
