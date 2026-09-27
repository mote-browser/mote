// What one of the extension's pages or its worker posts to another
// before their port has opened — at once after connect, or from inside
// onConnect — WebKit keeps until the other end takes the port, then
// hands on once for each end's world: between two of the extension's
// own, the same world, so twice. iCloud Passwords' popup asks its
// worker for its state that way, and was answered twice. So between
// the extension's own ends every message goes numbered by the end
// that sends it, and a number already heard is let go by. A content
// script's port, or an app's, goes as it is.

import { rethrowLater, type Listener } from './events';
import { randomId } from './ids';
import type { Shim, WebKitObject } from './types';

/** A message as it goes between the extension's own ends: numbered by the end that sends it. */
export interface NumberedMessage {
  /** The sending end's id, and the message's number from it. */
  __motePort: [string, number];
  message: unknown;
}

/**
 * Takes in a message, as numbered or not: what the listeners are to hear,
 * or `skip` for a number already heard. `heard` holds each end's last number.
 */
export function unnumber(message: unknown, heard: Map<string, number>): { message: unknown } | 'skip' {
  const tag =
    message && typeof message === 'object' ? (message as Partial<NumberedMessage>).__motePort : null;
  if (!Array.isArray(tag)) return { message };
  if (tag[1] <= (heard.get(tag[0]) || 0)) return 'skip';
  heard.set(tag[0], tag[1]);
  return { message: (message as NumberedMessage).message };
}

/**
 * Set on the port itself, not with `put`, which holds what it touches
 * for good: a port is the extension's to let go.
 */
function set(target: object, key: string, value: unknown): void {
  try {
    Object.defineProperty(target, key, { value, configurable: true, writable: true });
  } catch {}
}

export function numberOwnPorts({ runtime, put }: Shim): void {
  if (!runtime || typeof runtime.connect !== 'function' || !runtime.onConnect) return;
  const own = runtime.getURL('');
  const numbered = new WeakSet<object>();
  // Its onMessage is held by what is set here, so it isn't made afresh without it.
  const number = (port: WebKitObject) => {
    const event = port && port.onMessage;
    const post = port && port.postMessage;
    if (
      !event ||
      typeof event.addListener !== 'function' ||
      typeof post !== 'function' ||
      numbered.has(port)
    ) {
      return port;
    }
    numbered.add(port);
    const me = randomId();
    let sent = 0;
    const heard = new Map<string, number>();
    const listeners = new Set<Listener>();
    event.addListener((message: unknown, ...rest: unknown[]) => {
      const taken = unnumber(message, heard);
      if (taken === 'skip') return;
      for (const f of [...listeners]) {
        try {
          f(taken.message, ...rest);
        } catch (e) {
          rethrowLater(e);
        }
      }
    });
    // WebKit makes a port's onMessage afresh once nothing holds it, and
    // a fresh one has none of what is set below: a listener added to it
    // later would hear the numbered wrapper. Held on the port, it stays.
    set(port, 'onMessage', event);
    set(port, 'postMessage', (message: unknown) =>
      post.call(port, { __motePort: [me, ++sent], message } satisfies NumberedMessage),
    );
    set(event, 'addListener', (f: Listener) => {
      listeners.add(f);
    });
    set(event, 'removeListener', (f: Listener) => {
      listeners.delete(f);
    });
    set(event, 'hasListener', (f: Listener) => listeners.has(f));
    set(event, 'hasListeners', () => listeners.size > 0);
    return port;
  };
  const connect = runtime.connect;
  // Only a port to the extension itself: another extension would hear
  // the numbered wrapper, not the message.
  put(runtime, 'connect', (...args: unknown[]) => {
    const port = connect.apply(runtime, args);
    return typeof args[0] === 'string' && args[0] !== runtime.id ? port : number(port);
  });
  const onConnect = runtime.onConnect;
  const add = onConnect.addListener;
  const remove = onConnect.removeListener;
  const has = onConnect.hasListener;
  const wrapped = new WeakMap<Listener, Listener>();
  // The worker's sender is the bare origin, with no slash after it.
  const fromOwn = (port: WebKitObject) =>
    !!port && !!port.sender && (String(port.sender.url) + '/').startsWith(own);
  put(onConnect, 'addListener', (listener: unknown, ...rest: unknown[]) => {
    if (typeof listener !== 'function') return add.call(onConnect, listener, ...rest);
    let w = wrapped.get(listener as Listener);
    if (!w) {
      w = (port: WebKitObject) => (listener as Listener)(fromOwn(port) ? number(port) : port);
      wrapped.set(listener as Listener, w);
    }
    return add.call(onConnect, w, ...rest);
  });
  put(onConnect, 'removeListener', (listener: Listener) =>
    remove.call(onConnect, wrapped.get(listener) || listener),
  );
  put(onConnect, 'hasListener', (listener: Listener) =>
    has.call(onConnect, wrapped.get(listener) || listener),
  );
}
