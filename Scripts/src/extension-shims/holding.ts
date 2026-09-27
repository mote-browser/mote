// WebKit's objects are kept — WebKit finds an extension's listeners
// through them, and a replacement would hide them. Members are set on
// them instead: a method lives on the prototype, so an own property of
// the same name takes its place.
// WebKit's namespace and event objects are wrappers it doesn't keep
// alive: once no script holds one, it is collected, and the next
// `chrome.tabs` is a fresh object without what was set on it. So every
// object touched here is held for good.

import { errorMessage } from './callbacks';
import { isEventName, memberNames } from './events';
import type { Callback, Root, WebKitObject } from './types';

export interface Holder {
  kept: Set<object>;
  put(target: WebKitObject, key: string, value: unknown): void;
}

/** The set of held objects, also reachable as `__moteKept`, and `put`, which adds to it. */
export function createHolder(root: Root): Holder {
  const kept = new Set<object>();
  try {
    Object.defineProperty(root, '__moteKept', { value: kept });
  } catch {}
  const put = (target: WebKitObject, key: string, value: unknown): void => {
    if (target && (typeof target === 'object' || typeof target === 'function')) kept.add(target);
    try {
      Object.defineProperty(target, key, { value, configurable: true, writable: true, enumerable: true });
    } catch {
      try {
        target[key] = value;
      } catch {}
    }
  };
  return { kept, put };
}

/**
 * Holds every namespace of `chrome`, its events and storage areas, from the
 * start, before the extension's own code runs — its polyfills set things on
 * these objects too. Returns the namespaces' names.
 */
export function holdNamespaces(chrome: WebKitObject, kept: Set<object>): Set<string> {
  const spaces = new Set(Object.keys(chrome));
  for (let o = Object.getPrototypeOf(chrome); o && o !== Object.prototype; o = Object.getPrototypeOf(o)) {
    for (const key of Object.getOwnPropertyNames(o)) spaces.add(key);
  }
  for (const space of spaces) {
    let ns;
    try {
      ns = chrome[space];
    } catch {
      continue;
    }
    if (!ns || typeof ns !== 'object') continue;
    kept.add(ns);
    // And the same object every time it is asked for: WebKit can hand
    // out a fresh one, without what was set on the last.
    if (
      !Object.prototype.hasOwnProperty.call(chrome, space) ||
      Object.getOwnPropertyDescriptor(chrome, space)!.get
    ) {
      try {
        Object.defineProperty(chrome, space, {
          value: ns,
          configurable: true,
          writable: true,
          enumerable: true,
        });
      } catch {}
    }
    for (const key of memberNames(ns)) {
      if (!isEventName(key)) continue;
      try {
        const event = ns[key];
        if (event && typeof event === 'object') kept.add(event);
      } catch {}
    }
    for (const sub of ['local', 'sync', 'session', 'managed']) {
      try {
        if (ns[sub] && typeof ns[sub] === 'object') kept.add(ns[sub]);
      } catch {}
    }
  }
  return spaces;
}

/** Calls `callback` with `runtime.lastError` set, then takes it away again, as Chrome does. */
export function lastErrorReporter(runtime: WebKitObject, put: Holder['put']) {
  return (error: unknown, callback: Callback): void => {
    put(runtime, 'lastError', { message: errorMessage(error) });
    try {
      callback();
    } finally {
      try {
        delete runtime.lastError;
      } catch {}
    }
  };
}

/** Own copies of runtime's methods, bound to it. */
export function bindRuntimeMethods(runtime: WebKitObject, put: Holder['put']): void {
  if (!runtime) return;
  for (const name of memberNames(runtime)) {
    if (name === 'constructor' || isEventName(name)) continue;
    let f;
    try {
      f = runtime[name];
    } catch {
      continue;
    }
    if (typeof f === 'function') put(runtime, name, f.bind(runtime));
  }
}
