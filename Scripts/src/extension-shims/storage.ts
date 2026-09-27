// chrome.storage as Chrome has it.

import { resolved } from './callbacks';
import { createEvent } from './events';
import { fill } from './members';
import type { Shim } from './types';

export function fillStorage(shim: Shim): void {
  fill(shim, 'storage', {
    managed: { get: resolved({}), getBytesInUse: resolved(0), onChanged: createEvent() },
    AccessLevel: {
      TRUSTED_CONTEXTS: 'TRUSTED_CONTEXTS',
      TRUSTED_AND_UNTRUSTED_CONTEXTS: 'TRUSTED_AND_UNTRUSTED_CONTEXTS',
    },
  });
}

/** Items as WebKit stores them: a plain object copy of one with another prototype. */
export function plainItems(items: unknown): unknown {
  return items && typeof items === 'object' && Object.getPrototypeOf(items) !== Object.prototype
    ? Object.assign({}, items)
    : items;
}

/**
 * Items built with Object.create(null) — Chrome stores them, WebKit
 * throws that an object is expected.
 */
export function storePlainItems({ chrome, put }: Shim): void {
  for (const area of ['local', 'sync', 'session']) {
    const store = chrome.storage && chrome.storage[area];
    if (!store || typeof store.set !== 'function') continue;
    const set = store.set.bind(store);
    put(store, 'set', (items: unknown, ...rest: unknown[]) => set(plainItems(items), ...rest));
  }
}
