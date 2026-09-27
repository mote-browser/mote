// Where the shim runs: an extension's page, its worker, a content script, or
// the page's own world, where it must do nothing.

import type { Root, WebKitObject } from './types';

/**
 * Whether `chrome` is an extension's. A page's own world, where an extension's
 * MAIN-world script runs with this before it, has no extension APIs. Nothing to
 * mend there, and nothing may be left there for a page to see: Safari leaves
 * nothing. (There, Mote's passkey patch holds navigator.credentials.)
 */
export function carriesExtensionAPIs(chrome: WebKitObject): boolean {
  try {
    return !!(chrome && chrome.runtime && chrome.runtime.id);
  } catch {
    return false;
  }
}

/**
 * On a web page this is a content script: only Chrome's behaviour is
 * mended there, no API that Chrome doesn't give content scripts either.
 */
export function isContentScript(): boolean {
  return typeof location !== 'undefined' && !/^(chrome|webkit)-extension:$/.test(location.protocol);
}

/**
 * One of the extension's pages in a frame of a website — Vimium's bar,
 * the list iCloud Passwords opens under a field. WebKit runs it in the
 * website's process, which it trusts with no more than a content
 * script: a single call to tabs, windows, scripting… and WebKit takes
 * the process for compromised and ends it. The page reloads, and a
 * frame that makes the call as it loads reloads it for ever. Chrome
 * gives such a frame everything, so here the worker makes those calls
 * for it (see `__moteCall` in messaging.ts).
 */
export function isEmbedded(inContent: boolean): boolean {
  return (
    !inContent &&
    typeof window !== 'undefined' &&
    window.top !== window &&
    (() => {
      try {
        const ancestors = location.ancestorOrigins;
        if (ancestors && ancestors.length) return [...ancestors].some((origin) => origin !== location.origin);
      } catch {}
      try {
        return window.top!.location.origin !== location.origin;
      } catch {
        return true;
      }
    })()
  );
}

/** The extension's service worker. */
export function isServiceWorker(root: Root): boolean {
  return (
    typeof root.ServiceWorkerGlobalScope !== 'undefined' && root instanceof root.ServiceWorkerGlobalScope
  );
}

/**
 * The extension's background, whichever WebKit runs: the worker, or a
 * page — it picks the page when a manifest names scripts as well.
 */
export function isBackground(root: Root, chrome: WebKitObject, worker: boolean, inContent: boolean): boolean {
  return (
    worker ||
    (!inContent &&
      typeof document !== 'undefined' &&
      (() => {
        try {
          return (
            chrome.extension &&
            typeof chrome.extension.getBackgroundPage === 'function' &&
            chrome.extension.getBackgroundPage() === root
          );
        } catch {
          return false;
        }
      })())
  );
}
