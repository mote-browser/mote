# Load failure page: explain it, and let the person past a bad certificate

## Objective
When a page fails to load, show a well-designed page that says what went wrong and,
for certificate problems, offers a way to continue anyway.

## Problem
1. A bad certificate on a navigation to a new host leaves the person stuck on a bare
   "The connection isn't secure." line. `Challenge.trust` only asks when the
   certificate's host equals `pageHost`, which `Dialogs.trust` takes from
   `tab.address` — the page being left, not the one being opened. So the ask sheet
   almost never appears and WebKit fails the load.
2. "Try Again" calls `tab.reload()`, which reloads the previous page (or nothing),
   not the address that failed.
3. `LoadTrouble` is two lines of unstyled text.

## Approach
- One path for bad certificates: the challenge never asks. A bad certificate on a
  host that is not loopback and not excused fails; the failure page offers
  "Continue anyway" behind a "Details" disclosure. Continuing excuses the host for
  the rest of the launch (`Dialogs.excused`) and opens the failed address.
- `LoadFailure` becomes a value: kind (certificate / no host / offline / timed out /
  refused / other), the failing URL, and copy (title + explanation). Lives in MoteCore
  and is unit tested.
- `Tab.failure` holds that value; Try Again and Continue open the failing URL.

## Scope
Packages/MoteKit/Sources/MoteCore/{NavigationPolicy,Challenge}.swift + tests,
Mote/Sources/Page/Dialogs.swift, Mote/Sources/Browser/{Browser+Navigation,Tab,PageArea}.swift,
a new Mote/Sources/Browser/LoadFailurePage.swift.

## Tasks
- [x] T1 MoteCore: `LoadFailure` value (kind, url, host, title, detail, canContinue) + `Challenge.trust` without `.ask` — tests first. Route: delegated (writer trigger: 2+ non-trivial files).
- [x] T2 App: Tab/Browser/Dialogs wiring + redesigned failure page with Try Again and Continue anyway. Route: delegated (same writer).
- [ ] T3 Verify in the running app against self-signed.badssl.com / expired.badssl.com and an unreachable host.

## Acceptance criteria
- Opening https://self-signed.badssl.com from another page shows the failure page with
  "Continue anyway"; choosing it loads the site; later visits in the same launch load directly.
- Try Again re-opens the address that failed.
- Non-certificate failures show the page without "Continue anyway".
- Loopback hosts keep loading without any prompt.

## Checks
- `make test-unit` (swift test, MoteCore)
- `make build`
- Manual run with mote-bench.

## Progress
- Created 2026-10-01. Previous attempt (orphaned commits 7890493..17787a6) is discarded at the user's request.
- T1 done in 7dcd266. RED: `swift test` failed to compile the new tests (`missing argument for parameter 'pageHost'`, no `LoadFailure(domain:code:url:)`). GREEN: `swift test` 284 tests in 50 suites and 169 in 24 passed.
- T2 done in e659ee6. `Tab.failure: LoadFailure?`, `Tab.tryAgain()` / `continueAnyway()` reuse `go(to:)`; `Dialogs.trust` no longer asks; new `LoadFailurePage` replaces `LoadTrouble`; bench `wait` reports the failure's title. `make build`: BUILD SUCCEEDED; `swift test`: all pass.
- T3 (partial, inline): test world on the new build. example.com -> self-signed.badssl.com, expired.badssl.com, an .invalid host and https://localhost:9 all show the page with the right title (certificate / "No site at that address" / "The page didn't load"). Found the toolbar kept the previous page's address with a padlock; fixed in 0407c8b (`Tab.shownAddress`, lock.slash in amber for certificate failures), verified by screenshot. Pending: pressing Details / Continue / Try Again — this shell has no Accessibility permission and real clicks would take the person's mouse, so the user checks it by hand.
- Known: the tab's title stays on the previous page's title while the failure is up.
