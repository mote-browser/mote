// The popup Mote shows is a page of its own, known to WebKit as a
// tab with no place in the row (no index). Chrome has no current
// tab in a popup, and lists it among the popup views; extensions lay
// themselves out by that (Bitwarden, Proton Pass: or else they fill
// the window as if in a tab).

import { URL } from './captured';
import type { Callback, Shim, WebKitObject } from './types';

/** Whether `path` is the page the manifest names as the action's popup. */
export function isManifestPopup(manifest: WebKitObject, origin: string, path: string): boolean {
  const action = manifest.action || manifest.browser_action || {};
  return !!action.default_popup && new URL(action.default_popup, origin + '/').pathname === path;
}

/** Whether a tab WebKit describes is the popup: it has no place in the row. */
export function isPopupTab(tab: { index?: number } | null | undefined): boolean {
  return !!tab && !((tab.index as number) >= 0 && (tab.index as number) < 1e6);
}

export function mendPopup(shim: Shim): void {
  const { root, chrome, runtime, put, embedded } = shim;
  if (typeof document === 'undefined') return;
  // Known at once for the manifest's popup page — pages lay themselves
  // out before any answer can come back — and settled by what WebKit
  // says of the tab.
  let popup = (() => {
    try {
      return isManifestPopup(runtime.getManifest(), location.origin, location.pathname);
    } catch {
      return false;
    }
  })();
  // Not in a website's frame: never the popup, and asking costs the
  // worker a message for every frame the extension opens.
  if (!embedded && chrome.tabs && typeof chrome.tabs.getCurrent === 'function') {
    const getCurrent = chrome.tabs.getCurrent.bind(chrome.tabs);
    const current = () =>
      Promise.resolve(getCurrent()).then((t) => {
        if (isPopupTab(t)) {
          popup = true;
          return undefined;
        }
        if (t) popup = false;
        return t;
      });
    current().catch(() => {});
    put(chrome.tabs, 'getCurrent', (callback?: Callback) => {
      const p = current();
      if (typeof callback !== 'function') return p;
      p.then(
        (t) => callback(t),
        (e) => shim.withLastError(e, callback),
      );
      return undefined;
    });
  }
  if (chrome.extension && typeof chrome.extension.getViews === 'function') {
    const extension = chrome.extension;
    const getViews = extension.getViews.bind(extension);
    const views = (properties: { type?: string } = {}) => {
      let list: unknown[] = [...(getViews(properties) || [])];
      if (popup && properties.type === 'tab') list = list.filter((v) => v !== root);
      if (popup && (!properties.type || properties.type === 'popup') && !list.includes(root)) list.push(root);
      return list;
    };
    put(extension, 'getViews', views);
    // WebKit's getViews is read-only, and so is chrome.extension: both
    // ignore any redefinition without a word. The popup page's code
    // is then handed a `chrome` of its own, built on WebKit's, whose
    // extension namespace answers getViews and passes everything else
    // on (Malwarebytes lays itself out as a tab otherwise).
    if (popup && extension.getViews !== views) {
      const bound = new Map<string, unknown>();
      const ownExtension = Object.create(extension);
      for (const key of Object.getOwnPropertyNames(extension)) {
        if (key === 'getViews') continue;
        Object.defineProperty(ownExtension, key, {
          configurable: true,
          enumerable: true,
          get: () => {
            const v = extension[key];
            if (typeof v !== 'function') return v;
            if (!bound.has(key)) bound.set(key, v.bind(extension));
            return bound.get(key);
          },
        });
      }
      Object.defineProperty(ownExtension, 'getViews', {
        value: views,
        configurable: true,
        writable: true,
        enumerable: true,
      });
      const ownChrome = Object.create(chrome);
      Object.defineProperty(ownChrome, 'extension', {
        value: ownExtension,
        configurable: true,
        writable: true,
        enumerable: true,
      });
      for (const key of ['chrome', 'browser']) {
        try {
          if (root[key] === chrome) root[key] = ownChrome;
        } catch {}
      }
    }
  }
}
