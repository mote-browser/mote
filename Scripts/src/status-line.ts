// Reports the destination of the link under the pointer to Swift (StatusLine.swift),
// only when it changes. Injected into every frame, in Mote's isolated content world.

import { linkAddress } from './status-line/link';

interface StatusLineState {
  on: boolean;
}

declare global {
  interface Window {
    __moteLinks?: StatusLineState;
  }
}

// Turned back on over a page that already has the listener: reuse it.
if (window.__moteLinks) {
  window.__moteLinks.on = true;
} else {
  const state: StatusLineState = { on: true };
  window.__moteLinks = state;
  let shown = '';

  const report = (address: string): void => {
    if (!state.on || address === shown) return;
    shown = address;
    window.webkit.messageHandlers.link?.postMessage(address);
  };

  const options = { passive: true, capture: true };
  addEventListener('mouseover', (event) => report(linkAddress(event.composedPath())), options);
  // Leaving the frame altogether: no element is entered next.
  addEventListener('mouseout', (event) => event.relatedTarget || report(''), options);
  addEventListener('pagehide', () => report(''));
}
