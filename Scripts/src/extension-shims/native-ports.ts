// The same loss meets a worker's port to an app on the Mac (see
// web-socket.ts): what it posts in its first moments never reaches the app,
// and comes back to the worker's own listeners instead. iCloud Passwords says
// hello to its helper that way, and without the helper's answer asks for the
// code again and again. So on such a port, what the extension posts is held
// from its first message until the browser says the port has arrived — asked
// on the same port, as the socket asks — and then sent in order. WebKit won't
// let connectNative be replaced in a worker, so this is done on what every
// port shares, found through a port to the browser itself; the question and
// the answer are kept from the extension's listeners, and never reach the app.

import { APPLICATION } from './callbacks';
import type { Listener } from './events';
import type { Shim, WebKitObject } from './types';

/** What the shim and the browser say on a native port (NativeMessaging.swift), never the app. */
export interface PortProbe {
  /** `here?` asks whether the port has arrived, `here` answers; `alive` asks for a `beat`. */
  __moteNative: 'here?' | 'here' | 'alive' | 'beat';
}

export function isPortProbe(message: unknown): message is PortProbe {
  return !!message && typeof message === 'object' && '__moteNative' in message;
}

/**
 * Whether a port is to an app: not one to the extension's own pages or tabs,
 * nor one WebKit opened towards this end (it has a sender), nor a search port.
 */
export function goesToApp(port: WebKitObject, toPages: WeakSet<object>): boolean {
  return (
    !toPages.has(port) &&
    port.sender == null &&
    typeof port.name === 'string' &&
    !/^search(\.|$)/.test(port.name)
  );
}

interface PortState {
  /** What waits to be sent, or null once it may go. */
  held: unknown[] | null;
}

export function holdEarlyNativeMessages({ worker, runtime, chrome, put, kept }: Shim): void {
  if (!worker || !runtime || typeof runtime.connectNative !== 'function') return;
  let found: WebKitObject = null;
  try {
    found = runtime.connectNative(APPLICATION);
    found.disconnect();
  } catch {}
  const portProto = found && Object.getPrototypeOf(found);
  const eventProto = found && found.onMessage && Object.getPrototypeOf(found.onMessage);
  if (
    !portProto ||
    !eventProto ||
    typeof portProto.postMessage !== 'function' ||
    typeof eventProto.addListener !== 'function'
  ) {
    return;
  }

  // Ports that go to the extension's own pages or tabs, not an app.
  const toPages = new WeakSet<object>();
  for (const [space, name] of [
    [runtime, 'connect'],
    [chrome.tabs, 'connect'],
  ] as const) {
    const connect = space && space[name];
    if (typeof connect !== 'function') continue;
    put(space, name, (...args: unknown[]) => {
      const port = connect.apply(space, args);
      try {
        toPages.add(port);
      } catch {}
      return port;
    });
  }

  const post = portProto.postMessage;
  const add = eventProto.addListener;
  const remove = eventProto.removeListener;
  const has = eventProto.hasListener;
  // Ports seen, each with what waits to be sent.
  const ports = new WeakMap<object, PortState>();
  const start = (port: WebKitObject): PortState => {
    const state: PortState = { held: [] };
    let tries = 0;
    const flush = (): void => {
      const list = state.held;
      state.held = null;
      for (const m of list || []) post.call(port, m);
    };
    const again = (): void => {
      if (!state.held) return;
      // Unanswered, they go anyway: no worse than before.
      if (tries++ >= 20) {
        flush();
        return;
      }
      try {
        post.call(port, { __moteNative: 'here?' } satisfies PortProbe);
      } catch {}
      setTimeout(again, 100 * Math.min(tries, 5));
    };
    add.call(port.onMessage, (m: any) => {
      if (m && m.__moteNative === 'here' && state.held) flush();
      // WebKit keeps a worker only while it has posted on an open
      // port in the last two minutes; what arrives on one doesn't
      // count. The browser's word now and then is answered on the
      // port, so a worker holding a port to an app stays, as in
      // Chrome — iCloud Passwords otherwise forgets it was paired.
      if (m && m.__moteNative === 'alive') {
        try {
          post.call(port, { __moteNative: 'beat' } satisfies PortProbe);
        } catch {}
      }
    });
    add.call(port.onDisconnect, () => {
      state.held = null;
    });
    again();
    return state;
  };
  put(portProto, 'postMessage', function (this: WebKitObject, message: unknown) {
    let state = ports.get(this);
    if (!state) {
      state = goesToApp(this, toPages) ? start(this) : { held: null };
      ports.set(this, state);
    }
    if (state.held) {
      state.held.push(message);
      return undefined;
    }
    return post.call(this, message);
  });

  // A port's listeners, and only a port's (the namespaces' own
  // events are kept as they are), each behind one that lets the
  // question and the answer pass by.
  const wrapped = new WeakMap<object, Map<Listener, Listener>>();
  const wrapper = (event: object, f: Listener, make: boolean): Listener | undefined => {
    let byEvent = wrapped.get(event);
    if (!byEvent) {
      byEvent = new Map();
      if (make) wrapped.set(event, byEvent);
    }
    let w = byEvent.get(f);
    if (!w && make) {
      w = function (this: unknown, m: unknown, ...rest: unknown[]) {
        if (isPortProbe(m)) return undefined;
        return f.call(this, m, ...rest);
      };
      byEvent.set(f, w);
    }
    return w;
  };
  put(eventProto, 'addListener', function (this: object, f: unknown) {
    if (kept.has(this) || typeof f !== 'function') return add.call(this, f);
    return add.call(this, wrapper(this, f as Listener, true));
  });
  put(eventProto, 'removeListener', function (this: object, f: unknown) {
    const w = !kept.has(this) && typeof f === 'function' && wrapper(this, f as Listener, false);
    if (!w) return remove.call(this, f);
    wrapped.get(this)!.delete(f as Listener);
    return remove.call(this, w);
  });
  put(eventProto, 'hasListener', function (this: object, f: unknown) {
    const w = !kept.has(this) && typeof f === 'function' && wrapper(this, f as Listener, false);
    return has.call(this, w || f);
  });
}
