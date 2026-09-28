// Reports the page's scroll position to Swift (ScrollRelay in Tab.swift) on load
// and as it scrolls. Injected at document end into the main frame, in Mote's
// isolated content world.
//
// Nothing here may cost the page a frame while it scrolls. The height is
// measured only when the page changes size (a ResizeObserver runs after
// layout, so it never forces one), a scroll reads just the offset, and Swift
// hears only when the reading bar would move: a scrollHeight read and a
// message on every frame, from an extra animation frame, made smooth-scrolling
// pages present their frames unevenly.

import { readingStep, scrollPosition } from './scroll-report/position';

const root = document.documentElement;
let max = 1;
let told = -1;

const report = (): void => {
  const position = { y: window.scrollY || root.scrollTop || 0, max };
  const step = readingStep(position);
  if (step === told) return;
  told = step;
  window.webkit.messageHandlers.moteScroll?.postMessage(position);
};

const measure = (): void => {
  max = scrollPosition(window).max;
  report();
};

// Calls back once as it starts watching, which gives the first report.
new ResizeObserver(measure).observe(root);
addEventListener('resize', measure, { passive: true });
addEventListener('scroll', report, { passive: true });
