---
name: mote-bench
description: >
  Drive the Mote macOS browser from the repo's Tools/bench command: open
  flask-marked bench tabs, wait for load, read text, run JavaScript, click,
  type, submit, screenshot the page, probe window chrome, and install or
  press Chrome extensions. Use when the user asks to test Mote, drive the
  browser, run Tools/bench, open a page in Mote, screenshot a tab, check a
  panel, or exercise an extension, and when they run /mote-bench.
metadata:
  short-description: Drive Mote with Tools/bench
---

# Mote bench

`Tools/bench` (run from the repo root) talks to a running Mote over a local socket. `Tools/bench help` lists every command and its arguments; this file is about using it without disturbing the browser someone is working in.

## Pick the world, every call

Each Mote process is a "world" with its own folder and socket. Every call names the same one:

| Flag | Talks to | Its folder |
|---|---|---|
| `--test` | the test world | `~/Library/Application Support/Mote (test)/` |
| `--world NAME` | world NAME (lowercase letters, digits, hyphens) | `~/Library/Application Support/Mote (NAME)/` |
| none | the Mote the person actually uses | `~/Library/Application Support/Mote/` |

Anything that changes the chrome, installs or removes extensions, resizes the window, sends real keys or clicks, or selects a tab belongs in a test world. A Debug build (Xcode's Run, `make dev`) is always the test world. `make fresh` and `make reopen` open `build/Mote.app` with `MOTE_PROBE` set, which is a test world too.

`select`, `key`, `press`, `tap`, `resize` and `ext-answer` refuse to run against the person's own Mote, and `--yes` only skips an install question in a test run.

Against their own Mote, and only when they asked for it: `tabs`, `probe`, and page commands on bench tabs. Leave `ui`, `select`, `key`, `resize` and every `ext-*` to a test world unless they asked for that change in their browser; `ui look` and `ui sidebar` are remembered settings.

## Getting a test world to answer

Only one process per world. Before quitting a process, check that it is this repo's `build/Mote.app`, a Debug build under `build/DerivedData/`, or has `MOTE_PROBE` in its environment. Never touch `/Applications/Mote.app`; `killall`, quitting by name, or an AppleScript quit would hit it too (same name, same bundle id).

1. `Tools/bench --test tabs`. If it lists tabs, it's listening; don't start another.
2. If it says `Mote isn't listening`:
   - nothing running for that world: `defaults write SUITE bench -bool true`, then `make reopen` (`make reopen WORLD=NAME` for a named one);
   - a test process runs but doesn't answer: write that default, end that process, then `make reopen`. The switch is read at launch.
3. Try `Tools/bench --test tabs` again until it answers; launching takes a moment.

The suite is `io.github.mote-browser.mote.test`, or `io.github.mote-browser.mote.test.NAME` for a named world.

`make fresh` (or `make fresh WORLD=NAME`) wipes that world's folder, settings and WebKit data and opens it. Wiping clears the `bench` default as well, so afterwards: write the default, quit the process it opened, and `make reopen`. Only wipe when asked for a clean browser. `make fresh` always rebuilds `build/Mote.app`; `make reopen` builds it only when it's missing.

If `Tools/bench tabs` without a flag doesn't answer, ask the person to turn on **Settings › General › Let a script drive Mote**. Never write defaults for their own Mote.

## Tabs that aren't theirs

`tabs` prints a row per tab: `⚗` a bench tab, `●` the tab in front, a trailing `…` still loading, a trailing `z` asleep.

- `open URL` adds a bench tab at the end of the row and prints its id. Keep it.
- Ids are matched by prefix, first match wins; pass the id `tabs` or `open` printed.
- `close ID` only closes bench tabs. `close all` closes every bench tab, including another script's. Close the ids you opened, even when something failed along the way. Turning the switch off closes bench tabs left behind too.
- `go`, `click`, `type`, `submit`, `eval`, `text`, `shot` and `sleep` act on the id given: use a `⚗` id unless the person named one of their tabs.
- Bench tabs aren't selected, saved in the session, or written to history. A bench page that isn't in front is laid out off screen at 1280×800, and that's what `shot` captures.
- One call at a time per world. A call with no answer is cut off after about 25 seconds; `wait` gets its own seconds plus a few.

## A page, start to finish

```bash
id=$(Tools/bench --test open https://example.com)
Tools/bench --test wait "$id" 20
Tools/bench --test text "$id"
Tools/bench --test shot "$id" /tmp/mote-bench.png
Tools/bench --test close "$id"
```

`open` and `go` take an address, not search words: no spaces; schemes `http`, `https`, `file`, `about`, `data`. A bare host becomes `https://`, except `localhost`, `*.localhost` and LAN addresses, which become `http://`.

`wait` prints JSON: go on once `loading` is false. `timeout: true` means it was still loading; `failure` is the load error. Give slow pages more seconds.

`text` is `document.body.innerText`, cut at 120,000 characters (`truncated` is set, and `[… truncated]` goes to stderr). If it comes back empty, `eval` `document.readyState` and `location.href` before calling the page blank.

`eval ID JS` takes the script as one quoted argument and prints JSON, or text when the result isn't JSON. It doesn't wait for promises: store the result in a variable (`….then(r => window.out = r)`) and read it with a second `eval`. Add `mote` at the end to run in Mote's own script world.

`click`, `type` and `submit` take one CSS selector (`document.querySelector`). `type` sets the value and fires `input` and `change`; `submit` submits the element's form, or the element if it's a form. `tap` is a real mouse click instead, and also takes `text=Words`.

`shot` prints where the PNG went; read that file. It's only the page, not the window around it. Give it a path under `/tmp`; an optional last argument is the width in points.

## The window around the pages

`probe` prints the window's state as JSON: the panels (`settings`, `welcome`, `passwords`, `history`, `downloads`, `bookmarks`), whether the address field is open, any modal, `look`, `appearance`, the key window, every window's frame, and where the traffic lights are. `shot` can't see any of this; `probe` can.

`ui KEY VALUE` changes it and answers `{"ok": true}` (test worlds, unless asked):

| Key | Value |
|---|---|
| `settings` `passwords` `welcome` `history` `downloads` `bookmarks` `hidden` `sidebar` `extensions` | `on` or `off` |
| `look` | `light`, `dark` or `system` |

`ui extensions on` opens the puzzle button's menu; `ext-menu PATH` draws it to a PNG. `look` and `sidebar` are remembered.

`resize WIDTH HEIGHT [STEPS]` (test only) drags the window to that size and reports its size and traffic lights. `key ID TEXT` (test only) types into a tab with real key events and says how many the page left unused. `sleep ID` tries to put a tab to sleep and says what kept it awake; bench tabs stay awake.

## Extensions

macOS 15.4 or later, in a test world. The ids here are extension ids from `Tools/bench extensions`, not tab ids.

`ext-add` takes a Chrome Web Store link or id; `ext-folder` a folder with a `manifest.json`. Both answer `{"started": true}` before the install finishes, and in a test run need `--yes`, or Mote waits on its install question.

```bash
Tools/bench --test ext-add 'https://chromewebstore.google.com/detail/…' --yes
Tools/bench --test extensions
```

Poll `extensions` until `busy` is `""`, then look at that id's `loaded`, `errors` and `reported`.

`ext-press ID` opens its popup; while it's open, `ext-popup ID JS` runs JavaScript in it and `ext-shot ID PATH` saves a picture of it. `ext-page ID [PATH]` opens one of its pages in a bench tab and prints the tab id; `eval` there has the extension's APIs. `ext-reload ID` loads it again (a folder extension is copied in afresh). `ext-pin ID [on|off]`, `ext-enable ID on|off` and `ext-remove ID` change that world. `ext-answer yes|no|ask` (test only) answers the extension's later questions and lists what it was asked.

## When it fails

The script exits non-zero and prints `error: …`; believe it.

- `isn't listening`: the process is down or its switch is off (see above).
- `no tab`: a stale id; run `tabs`.
- `not a bench tab`: `close` pointed at one of their tabs.
- `only works on a --test run`, `only in a test run`: that command was pointed at their own Mote.
- `no popup open`: `ext-press` it first.
- `unknown command`: see `Tools/bench help`; the script may be ahead of this file.
