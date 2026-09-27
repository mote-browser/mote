// Reports the link under a middle click to Swift (MiddleRelay in Tab.swift), which
// opens it in a new tab: WebKit delivers no navigation action for middle clicks.
// Injected at document start into the main frame, in Mote's isolated content world.

import { middleClickAddress } from './middle-click/link';

declare global {
  interface Window {
    __moteMiddle?: boolean;
  }
}

/** `MouseEvent.button` of the middle button. (In the `buttons` mask, 2 is the right button and 4 the middle.) */
const MIDDLE_BUTTON = 1;

if (!window.__moteMiddle) {
  window.__moteMiddle = true;
  // Bubbling phase, so a page that handles the click itself can prevent it; only
  // trusted events, so a synthetic auxclick can't open tabs.
  document.addEventListener('auxclick', (event) => {
    if (event.button !== MIDDLE_BUTTON || !event.isTrusted || event.defaultPrevented) return;
    const href = middleClickAddress(event.composedPath());
    if (href) window.webkit.messageHandlers.moteMiddle?.postMessage({ href });
  });
}
