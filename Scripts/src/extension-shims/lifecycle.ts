// The extension's worker as it starts: which install it is, and listeners it
// adds too late for WebKit.

import { isEventName, memberNames, rethrowLater, type Listener } from './events';
import type { Shim } from './types';
import { isLateListenerError } from './web-request';

/** An `onInstalled` reason told as the update it is, for an extension taken up again in the session. */
export function asUpdate<D extends { reason?: string }>(details: D, version: string) {
  return { ...details, reason: 'update', previousVersion: version };
}

/**
 * WebKit says "install" again when an extension is taken up afresh in
 * the same session — after a Reload, or a worker brought back — where
 * Chrome says "update"; extensions open their welcome page on
 * "install". The first one of a session is marked, and any later one
 * told as the update it is.
 */
export function mendInstalledReason({ runtime, put, native, background }: Shim): void {
  if (!background || !runtime.onInstalled || typeof runtime.onInstalled.addListener !== 'function') return;
  let decided: Promise<boolean> | null = null;
  const seenBefore = () =>
    decided ||
    (decided = native('background.loadedBefore', []).then(
      (v) => !!v,
      () => false,
    ));
  const add = runtime.onInstalled.addListener.bind(runtime.onInstalled);
  const remove = runtime.onInstalled.removeListener.bind(runtime.onInstalled);
  const wrapped = new Map<Listener, Listener>();
  put(runtime.onInstalled, 'addListener', (listener: Listener) => {
    const w = (details: { reason?: string } | undefined) => {
      if (!details || details.reason !== 'install') return listener(details);
      seenBefore().then((seen) =>
        listener(seen ? asUpdate(details, runtime.getManifest().version) : details),
      );
      return undefined;
    };
    wrapped.set(listener, w);
    return add(w);
  });
  put(runtime.onInstalled, 'removeListener', (listener: Listener) => {
    const w = wrapped.get(listener);
    wrapped.delete(listener);
    return remove(w || listener);
  });
  put(runtime.onInstalled, 'hasListener', (listener: Listener) => wrapped.has(listener));
}

/**
 * A worker may add listeners only while it starts; WebKit throws for
 * one added later, where Chrome takes it. So for every event this
 * extension's code mentions (`ShimConfig.events`), the worker has one
 * listener of WebKit's from the start, and a late one joins the list
 * behind it. Events it never mentions still take late listeners without
 * throwing — they just aren't heard. (Request events are left alone: a
 * listener for all of them would wake the worker for every request.)
 */
export function acceptLateListeners({ chrome, put, background, config }: Shim): void {
  if (!background) return;
  const mentioned = new Set(config.events);
  for (const space of Object.keys(chrome)) {
    if (space === 'webRequest') continue;
    let ns;
    try {
      ns = chrome[space];
    } catch {
      continue;
    }
    if (!ns || typeof ns !== 'object') continue;
    for (const key of memberNames(ns)) {
      if (!isEventName(key) || (space === 'runtime' && key.startsWith('onMessage'))) continue;
      let target;
      try {
        target = ns[key];
      } catch {
        continue;
      }
      if (!target || typeof target.addListener !== 'function' || target.listeners) continue;
      const add = target.addListener.bind(target);
      const remove = target.removeListener.bind(target);
      const late = new Set<Listener>();
      if (mentioned.has(space + '.' + key)) {
        try {
          add(function (...args: unknown[]) {
            let answer;
            for (const f of [...late]) {
              try {
                const r = f(...args);
                if (r !== undefined) answer = r;
              } catch (e) {
                rethrowLater(e);
              }
            }
            return answer;
          });
        } catch {}
      }
      put(target, 'addListener', (listener: Listener, ...rest: unknown[]) => {
        try {
          return add(listener, ...rest);
        } catch (e) {
          if (isLateListenerError(e)) late.add(listener);
          else throw e;
        }
        return undefined;
      });
      put(target, 'removeListener', (listener: Listener) => {
        late.delete(listener);
        try {
          remove(listener);
        } catch {}
      });
    }
  }
}
