# Mote's website

One page to see Mote and download it: [Astro](https://astro.build) with Tailwind CSS v4 and no UI framework; Geist for type. Served by GitHub Pages at [motebrowser.com](https://motebrowser.com).

```
pnpm install
pnpm dev      # http://localhost:4321/mote/
pnpm build    # static site in dist/
pnpm check    # type-check the .astro and .ts files
```

## How it's put together

- `src/pages/index.astro` lists the sections; each is a component in `src/components/`.
- **The opening** (`Story.astro`, `styles/story.css`): the page fills the screen, shrinks into the card of a Mote window, its manifesto scrolls by, and the window is used for a moment: a new tab, a search, a page arriving, the sidebar folded away. The window follows the app's own layout, colours and sizes (`ChromeLayout.swift`, `Sidebar.swift`, `Toolbar.swift`, `Omnibox.swift`, `Design.swift`); keep them in step when the app changes.
- **The light and the pebble** are fragment shaders run by `scripts/shader.ts` in raw WebGL2: reduced resolution and frame rate, paused off screen, in hidden tabs and with reduced motion. They start once the page is idle; static stand-ins show until then.
- **Pinned scenes** (`styles/scene.css`): the opening, the close-ups and the size chart are tall wrappers with a sticky stage. Each moving piece has the `.part` class and says in `--from`/`--to` which stretch of the scene's scroll it plays over. Chrome and Safari run them on a CSS scroll timeline, off the main thread; elsewhere `scripts/story.ts` writes the progress into `--p` and the same animations are scrubbed with it.
- **The close-ups** (`Gallery.astro`, `MockWindow.astro`, `Favicon.astro`): a pinned row of cards, each a real-size dark Mote window cropped to one part of it, flat and lit from one place; the row holds on each card while its window acts. The sites and their favicons are made up.
- **The size chart** (`Weight.astro`, `scripts/zoom.ts`): a pinned scene where the camera pulls back from Mote's pebble to show it beside the other browsers, drawn to scale on a canvas at every scroll step. The sizes are installed apps measured in September 2026 (versions in its footnote); re-measure before changing them.
- **The rest of the page** moves with the scroll through a few classes in `styles/global.css` (`.rise`, `.focus`, `.ink`, `.open`, `.strike`, `.emerge`), each a CSS view or scroll timeline. Where there are none, the page just shows at rest.
- **The footer** is stuck to the bottom of the screen under the page (`.sheet`), so the page lifts away to uncover it.
- **Scrolling** is smoothed by [Lenis](https://github.com/darkroomengineering/lenis), except with reduced motion.
- Without JavaScript, or with reduced motion, everything is a plain page that reads top to bottom.
- Fonts are downloaded at build time by Astro's font API and served from the site itself; nothing on the page makes a request to anyone else.
- Colours, fonts and easings are Tailwind theme tokens in `styles/global.css`, taken from the app's `Design.swift` and `Mote.icon`. Links live in `src/site.ts`.
