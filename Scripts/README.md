# Scripts

The JavaScript Mote injects into web pages, written in TypeScript.

`pnpm build` (or `make scripts` from the repository root) bundles each
`src/*.ts` file with Rolldown into `Mote/Resources/Scripts/<name>.js`. The built
files are committed, so the app builds with Xcode alone; `make test-scripts`
fails when they are out of date with `src`.

| Command       | What it does                                                                            |
| ------------- | --------------------------------------------------------------------------------------- |
| `pnpm build`  | Bundle every script                                                                     |
| `pnpm check`  | Type-check (TypeScript 7), lint (Oxlint), check formatting (oxfmt), unit tests (Vitest) |
| `pnpm format` | Format with oxfmt                                                                       |

## Conventions

**One script per file.** `src/<name>.ts` is the entry point and only wires the
script to the page. Logic lives in `src/<name>/` (or `src/lib/` when shared) as
plain functions, so Vitest can test it in `test/<name>.test.ts` against a
simulated DOM (happy-dom). How a script behaves in real WebKit is covered by
the integration tests in `MoteTests/`.

**Injected scripts** run for their side effects and export nothing. Swift adds
them as a `WKUserScript` with `InjectedScript.source("name")`.

**Called scripts** export `run(...)`, whose result goes back to Swift. Rolldown
exposes them as `mote<Name>` (`reader` → `moteReader`), and Swift calls them with
`callAsyncJavaScript(InjectedScript.call("name"), arguments: …)`: arguments
arrive as `run`'s parameters, serialized by WebKit. `InjectedScript.call` is a
function body, so it can also open a file Swift writes (`user-script` begins
every `chrome.userScripts` script that way).

**Extension shims** (`extension-shims`) are written into each extension's files
rather than added as a `WKUserScript`: `ExtensionShims.shim(for:)` gives them
the extension's values as `moteConfig`, and their `version` is a hash of the
built file, so a new build prepares installed extensions again.

**Values from Swift** for injected scripts come as `moteConfig`: declare its type
in the script,

```ts
declare const moteConfig: { chromeVersion: string; verbose: boolean };
```

and load it with an `Encodable` value of the same shape:
`InjectedScript.source("name", config: Config(chromeVersion: …, verbose: …))`.
Never build JavaScript by interpolating Swift strings.

**Messages to Swift** go through `window.webkit.messageHandlers.<name>`, typed in
`src/global.d.ts`. Global switches Swift flips from outside (`window.__moteLinks`)
are declared in the script that owns them.
