// Reports the page's scroll position to Swift (ScrollRelay in Tab.swift) on load
// and as it scrolls. Injected at document end into the main frame, in Mote's
// isolated content world. Throttled to one report per animation frame and
// passive, so it doesn't affect scrolling performance.

import { scrollPosition } from './scroll-report/position';

let waiting = false;

const report = (): void => {
  window.webkit.messageHandlers.moteScroll?.postMessage(scrollPosition(window));
};

addEventListener(
  'scroll',
  () => {
    if (waiting) return;
    waiting = true;
    requestAnimationFrame(() => {
      waiting = false;
      report();
    });
  },
  { passive: true },
);
report();
