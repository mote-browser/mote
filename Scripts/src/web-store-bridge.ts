// Adapts the Chrome Web Store: hides the "Switch to Chrome" prompts and replaces
// the disabled "Add to Chrome" button with "Add to Mote", which asks Swift
// (WebStoreBridge.swift) to install the extension in the tab's URL. Injected at
// document end into every main frame, in Mote's isolated content world; exits
// at once outside the store. Avoids the store's generated class names.

import {
  buttonState,
  extensionID,
  hidePromotions,
  OUR_BUTTON,
  replaceInstallButton,
  setLabel,
  storeInstallButton,
  type StoreState,
} from './web-store-bridge/store-page';

declare global {
  interface Window {
    /** Swift sends the installed and installing extensions through `state`. */
    __moteStore?: { state(next: StoreState | null | undefined): void };
  }
}

/** What the bridge posts to Swift: a press of our button, or the id it was placed for. */
type StoreMessage = { add: true } | { placed: string | null };

/** Waits this long after the store redraws, so a burst of changes mends once. */
const MEND_DELAY_MS = 60;

/** The extension this store page shows, from its own address. */
function pageID(): string | null {
  return extensionID(location.pathname);
}

if (location.hostname === 'chromewebstore.google.com' && !window.__moteStore) {
  let state: StoreState = { installed: [], busy: null };

  const post = (message: StoreMessage): void => window.webkit.messageHandlers.moteStore?.postMessage(message);

  const render = (button: HTMLButtonElement): void => {
    const { label, disabled } = buttonState(state, pageID());
    setLabel(button, label);
    button.disabled = disabled;
  };

  // The store keeps the pages it has left, hidden, beside the one it shows.
  const renderAll = (): void => {
    for (const button of document.querySelectorAll<HTMLButtonElement>(OUR_BUTTON)) render(button);
  };

  const mend = (): void => {
    hidePromotions(document);
    if (!pageID()) return;
    const original = storeInstallButton(document);
    if (original?.parentNode) {
      replaceInstallButton(original, original.parentNode);
      post({ placed: pageID() });
    }
    renderAll();
  };

  // Caught on the window, before the store's own handlers — which listen
  // on the document — can see the click at all.
  addEventListener(
    'click',
    (event) => {
      const ours =
        event.target instanceof Element ? event.target.closest<HTMLButtonElement>(OUR_BUTTON) : null;
      if (!ours) return;
      event.preventDefault();
      event.stopImmediatePropagation();
      if (!ours.disabled) post({ add: true });
    },
    true,
  );

  window.__moteStore = {
    state(next) {
      state = next || state;
      renderAll();
    },
  };

  // The store is one page that rewrites itself: whatever it redraws, mend
  // again. A timer rather than a frame — a tab out of sight gets no frames.
  let queued = false;
  new MutationObserver(() => {
    if (queued) return;
    queued = true;
    setTimeout(() => {
      queued = false;
      mend();
    }, MEND_DELAY_MS);
  }).observe(document.documentElement, { childList: true, subtree: true });
  mend();
}
