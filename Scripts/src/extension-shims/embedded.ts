// In a website's frame, everything WebKit keeps to the extension's own
// process goes through the worker instead. What stays direct is what
// WebKit lets a content script call too. Namespaces the shim adds
// itself further down answer through the browser, which is allowed.

import { takeCallback, settleCallback } from './callbacks';
import { createEvent, isEventName, memberNames } from './events';
import type { WorkerCall } from './messaging';
import type { Shim } from './types';

/** Namespaces a content script may call itself. */
export const DIRECT_NAMESPACES = new Set([
  'runtime',
  'storage',
  'i18n',
  'extension',
  'permissions',
  'dom',
  'test',
]);

export const NO_RECEIVER = 'Could not establish connection. Receiving end does not exist.';

/** The arguments of a call carried to the worker: trailing undefineds dropped, then as JSON. */
export function carriedArguments(args: unknown[]): unknown[] {
  while (args.length && args[args.length - 1] === undefined) args.pop();
  return JSON.parse(JSON.stringify(args));
}

export function forwardThroughWorker(shim: Shim): void {
  const { chrome, put, spaces, embedded } = shim;
  if (!embedded) return;
  const ask = (space: string, method: string, args: unknown[]): Promise<unknown> => {
    let payload;
    try {
      payload = carriedArguments(args);
    } catch (e) {
      return Promise.reject(e);
    }
    const call: WorkerCall = { __moteCall: { space, method, args: payload } };
    return Promise.resolve(chrome.runtime.sendMessage(call)).then((reply: any) => {
      if (!reply)
        throw new Error('chrome.' + space + '.' + method + " had no answer from the extension's background");
      if (reply.error) throw new Error(reply.error);
      return reply.value;
    });
  };
  for (const space of spaces) {
    if (DIRECT_NAMESPACES.has(space)) continue;
    let ns;
    try {
      ns = chrome[space];
    } catch {
      continue;
    }
    if (!ns || typeof ns !== 'object') continue;
    for (const name of memberNames(ns)) {
      if (name === 'constructor' || isEventName(name)) continue;
      let f;
      try {
        f = ns[name];
      } catch {
        continue;
      }
      if (typeof f !== 'function') continue;
      // A port can't be carried over: one that closes at once, as
      // Chrome's does when nothing answers, rather than a dead process.
      if (name === 'connect') {
        put(ns, name, (...args: any[]) => {
          const port = {
            name: (args.find((a) => a && typeof a === 'object') || {}).name || '',
            sender: undefined,
            postMessage: () => {},
            disconnect: () => {},
            onMessage: createEvent(),
            onDisconnect: createEvent(),
          };
          setTimeout(() => {
            shim.withLastError({ message: NO_RECEIVER }, () => {
              for (const listener of [...port.onDisconnect.listeners]) listener(port);
            });
          });
          return port;
        });
        continue;
      }
      put(ns, name, (...args: unknown[]) => {
        const callback = takeCallback(args);
        const answer = ask(space, name, args);
        if (!callback) return answer;
        settleCallback(shim, answer, callback);
        return undefined;
      });
    }
  }
}
