// Tells Swift (SwipeNavigation.swift, through ScrollRelay) whether a horizontal
// wheel event would scroll page content, before it treats a swipe as navigation.
// Injected at document start into every frame (only a frame's own document knows
// whether it handles a swipe, e.g. a map), in Mote's isolated content world.

import { type Report, scrollTaken, shouldReport } from './swipe-watch/scrollable';

declare global {
  interface Window {
    __moteSwipe?: boolean;
  }
}

if (!window.__moteSwipe) {
  window.__moteSwipe = true;
  const last: Report = { taken: null, at: 0 };

  addEventListener(
    'wheel',
    (event) => {
      if (Math.abs(event.deltaX) <= Math.abs(event.deltaY)) return;
      const taken = scrollTaken(event.target, event.deltaX);
      const now = Date.now();
      if (!shouldReport(last, taken, now)) return;
      last.taken = taken;
      last.at = now;
      window.webkit.messageHandlers.moteScroll?.postMessage({ side: taken ? 'taken' : 'free' });
    },
    { passive: true, capture: true },
  );
}
