// What the shim sets on the global object before anything else.

import { carriesExtensionAPIs } from './environment';
import type { Root } from './types';

/**
 * WebKit reverted `requestIdleCallback` after a page-load regression
 * (bug 287681), leaving Proton Pass's form detection without it.
 */
export function polyfillIdleCallback(root: Root): void {
  const nativeIdle =
    typeof root.requestIdleCallback === 'function' ? root.requestIdleCallback.bind(root) : null;
  const nativeCancelIdle =
    typeof root.cancelIdleCallback === 'function' ? root.cancelIdleCallback.bind(root) : null;
  if (nativeIdle && nativeCancelIdle) return;

  const idle = new Map<number, { nativeId?: number; timer?: ReturnType<typeof setTimeout> }>();
  let idleId = 0;
  root.requestIdleCallback = (callback: IdleRequestCallback, options?: IdleRequestOptions) => {
    const id = ++idleId;
    if (nativeIdle) {
      const nativeId = nativeIdle((deadline: IdleDeadline) => {
        if (!idle.delete(id)) return;
        callback(deadline);
      }, options);
      idle.set(id, { nativeId });
    } else {
      // Let the requesting script finish first. Chrome's maximum
      // idle deadline is 50 ms; this fallback uses the full budget.
      const timer = setTimeout(() => {
        if (!idle.delete(id)) return;
        const start = Date.now();
        callback({ didTimeout: false, timeRemaining: () => Math.max(0, 50 - (Date.now() - start)) });
      }, 1);
      idle.set(id, { timer });
    }
    return id;
  };
  root.cancelIdleCallback = (id: number) => {
    const request = idle.get(id);
    if (request === undefined) {
      if (nativeCancelIdle) nativeCancelIdle(id);
      return;
    }
    idle.delete(id);
    if (request.timer !== undefined) clearTimeout(request.timer);
    else if (nativeCancelIdle) nativeCancelIdle(request.nativeId!);
  };
}

/**
 * Keep the first credentials container alive so extension hooks
 * survive WebKit replacing an unreferenced container.
 */
export function keepCredentials(root: Root): void {
  const credentials = root.navigator && root.navigator.credentials;
  if (credentials && !Object.prototype.hasOwnProperty.call(root, '__moteCredentials')) {
    Object.defineProperty(root, '__moteCredentials', { value: credentials });
  }
}

/** Marks the context as mended, so the shim runs once however often it is loaded. */
export function markInstalled(root: Root): void {
  Object.defineProperty(root, '__moteShim', { value: true });
}

/**
 * WebKit finds a page's extension APIs through the `chrome` and
 * `browser` globals when it delivers an event. A sandbox that locks
 * every global away (MetaMask's LavaMoat) cuts it off: nothing arrives
 * any more. Made fixed accessors, they can't be taken away, and code
 * that assigns its own polyfill to them still can.
 */
export function fixChromeGlobals(root: Root): void {
  for (const key of ['browser', 'chrome']) {
    const descriptor = Object.getOwnPropertyDescriptor(root, key);
    if (!descriptor || !descriptor.configurable) continue;
    let value = root[key];
    // A replacement that hides the APIs — a Proxy some extensions put
    // there to keep them from other code (Proton Pass) — would hide them
    // from WebKit too, and nothing would reach the extension again. A
    // replacement that still carries them is taken.
    try {
      Object.defineProperty(root, key, {
        configurable: false,
        enumerable: descriptor.enumerable!,
        get: () => value,
        set: (v) => {
          if (carriesExtensionAPIs(v)) value = v;
        },
      });
    } catch {}
  }
}
