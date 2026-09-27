// WebKit runs an extension's worker on its web process's main thread,
// and a worker's WebSocket waits there for the main thread to set up
// its channel — for itself, for ever: the worker and every page of the
// extension freeze. 1Password opens one as a sign-in succeeds. So a
// worker's socket is made by the browser (ExtensionSocket.swift) and
// its frames come and go over a native port.

import { Blob, DOMException, URL } from './captured';
import { rethrowLater } from './events';
import type { Shim, WebKitObject } from './types';

/** The native application whose ports carry sockets (ExtensionSocket.swift). */
export const SOCKET_APPLICATION = 'mote.socket';

/** What the worker says on a socket's port. */
export type SocketCommand =
  | { open: string; protocols: string[]; userAgent: string }
  | { send: string }
  | { sendBinary: string }
  | { close: number; reason: string };

/** What the browser says on a socket's port. */
export type SocketNews =
  | { ready: true }
  | { opened: string }
  | { text: string }
  | { binary: string }
  | { failed: true }
  | { closed: number; reason?: string; clean?: boolean };

/** Bytes as base64, in chunks small enough for `String.fromCharCode`. */
export function encodeBytes(bytes: Uint8Array): string {
  let s = '';
  for (let i = 0; i < bytes.length; i += 0x8000) {
    s += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000) as unknown as number[]);
  }
  return btoa(s);
}

export function decodeBytes(text: string): ArrayBuffer {
  const s = atob(text);
  const bytes = new Uint8Array(s.length);
  for (let i = 0; i < s.length; i++) bytes[i] = s.charCodeAt(i);
  return bytes.buffer;
}

/** A socket's address made absolute, with http(s) taken for ws(s); throws as WebSocket does for any other. */
export function socketURL(url: string | URL, base: string): URL {
  let parsed;
  try {
    parsed = new URL(url, base);
  } catch {
    throw new DOMException("The URL '" + url + "' is invalid.", 'SyntaxError');
  }
  if (parsed.protocol === 'http:') parsed.protocol = 'ws:';
  if (parsed.protocol === 'https:') parsed.protocol = 'wss:';
  if (!/^wss?:$/.test(parsed.protocol) || parsed.hash) {
    throw new DOMException("The URL '" + url + "' is invalid.", 'SyntaxError');
  }
  return parsed;
}

const STATES = { CONNECTING: 0, OPEN: 1, CLOSING: 2, CLOSED: 3 };

export function replaceWorkerWebSocket({ root, worker, runtime }: Shim): void {
  if (
    !worker ||
    typeof root.WebSocket !== 'function' ||
    !runtime ||
    typeof runtime.connectNative !== 'function'
  ) {
    return;
  }
  const connectNative = runtime.connectNative.bind(runtime);

  class WebSocket extends EventTarget {
    #port: WebKitObject;
    #state = 0;
    #queue: Promise<unknown> = Promise.resolve();
    #origin: string;
    #hello: SocketCommand;
    declare readonly url: string;
    declare protocol: string;
    declare extensions: string;
    declare binaryType: BinaryType;
    declare bufferedAmount: number;
    declare onopen: ((event: Event) => unknown) | null;
    declare onmessage: ((event: MessageEvent) => unknown) | null;
    declare onerror: ((event: Event) => unknown) | null;
    declare onclose: ((event: CloseEvent) => unknown) | null;

    constructor(url: string | URL, protocols?: string | string[]) {
      super();
      const parsed = socketURL(url, location.href);
      const list =
        protocols === undefined ? [] : (Array.isArray(protocols) ? protocols : [protocols]).map(String);
      Object.defineProperty(this, 'url', { value: parsed.href, enumerable: true });
      this.#origin = parsed.origin;
      this.protocol = '';
      this.extensions = '';
      this.binaryType = 'blob';
      this.bufferedAmount = 0;
      this.onopen = null;
      this.onmessage = null;
      this.onerror = null;
      this.onclose = null;
      this.#hello = { open: this.url, protocols: list, userAgent: navigator.userAgent };
      this.#connect();
    }

    // WebKit drops what a worker posts on a port it has only just
    // opened, without a word either way. So the opening is said again,
    // on the same port, until the browser answers anything at all.
    #connect(): void {
      const port = connectNative(SOCKET_APPLICATION);
      let ready = false;
      let tries = 0;
      this.#port = port;
      const again = (): void => {
        if (ready || this.#state === 3) return;
        if (tries++ >= 20) {
          this.#fire('error');
          this.#closed(1006, '', false);
          return;
        }
        try {
          port.postMessage(this.#hello);
        } catch {}
        setTimeout(again, 100 * Math.min(tries, 5));
      };
      port.onMessage.addListener((m: any) => {
        if (!ready) ready = true;
        if (m && m.ready === true) return;
        this.#take(m);
      });
      port.onDisconnect.addListener(() => {
        if (this.#state === 3) return;
        this.#fire('error');
        this.#closed(1006, '', false);
      });
      again();
    }

    get readyState(): number {
      return this.#state;
    }

    #fire(type: string, init?: Record<string, unknown>): void {
      let event: Event;
      if (type === 'message') event = new MessageEvent('message', init);
      else if (type === 'close' && typeof CloseEvent === 'function') event = new CloseEvent('close', init);
      else {
        event = new Event(type);
        if (init) for (const k in init) Object.defineProperty(event, k, { value: init[k] });
      }
      const handler = (this as any)['on' + type];
      if (typeof handler === 'function') {
        try {
          handler.call(this, event);
        } catch (e) {
          rethrowLater(e);
        }
      }
      this.dispatchEvent(event);
    }

    #closed(code: number, reason: string, wasClean: boolean): void {
      this.#state = 3;
      try {
        this.#port.disconnect();
      } catch {}
      this.#fire('close', { code, reason, wasClean });
    }

    // Anything may come on the port: only a `SocketNews` is taken.
    #take(m: any): void {
      if (!m || this.#state === 3) return;
      if ('opened' in m) {
        this.protocol = m.opened;
        this.#state = 1;
        this.#fire('open');
      } else if ('text' in m) this.#fire('message', { data: m.text, origin: this.#origin });
      else if ('binary' in m) {
        const buffer = decodeBytes(m.binary);
        this.#fire('message', {
          data: this.binaryType === 'arraybuffer' ? buffer : new Blob([buffer]),
          origin: this.#origin,
        });
      } else if ('failed' in m) this.#fire('error');
      else if ('closed' in m) this.#closed(m.closed, m.reason || '', !!m.clean);
    }

    send(data: unknown): void {
      if (this.#state === 0) {
        throw new DOMException('WebSocket is still in CONNECTING state.', 'InvalidStateError');
      }
      if (this.#state !== 1) return;
      const post = (message: SocketCommand): void => {
        try {
          this.#port.postMessage(message);
        } catch {}
      };
      if (typeof data === 'string') {
        this.#queue = this.#queue.then(() => post({ send: data }));
        return;
      }
      const bytes =
        data instanceof ArrayBuffer
          ? Promise.resolve(new Uint8Array(data))
          : ArrayBuffer.isView(data)
            ? Promise.resolve(new Uint8Array(data.buffer, data.byteOffset, data.byteLength))
            : data instanceof Blob
              ? data.arrayBuffer().then((b) => new Uint8Array(b))
              : Promise.resolve(null);
      this.#queue = this.#queue
        .then(() => bytes)
        .then((b) => (b ? post({ sendBinary: encodeBytes(b) }) : post({ send: String(data) })));
    }

    close(code?: number, reason?: string): void {
      if (code !== undefined && code !== 1000 && !(code >= 3000 && code <= 4999)) {
        throw new DOMException(
          'The close code must be either 1000, or between 3000 and 4999. ' + code + ' is neither.',
          'InvalidAccessError',
        );
      }
      if (this.#state >= 2) return;
      this.#state = 2;
      const message = {
        close: code === undefined ? 1000 : code,
        reason: reason === undefined ? '' : String(reason),
      };
      this.#queue = this.#queue.then(() => {
        try {
          this.#port.postMessage(message);
        } catch {}
      });
    }
  }

  for (const [k, v] of Object.entries(STATES)) {
    Object.defineProperty(WebSocket, k, { value: v });
    Object.defineProperty(WebSocket.prototype, k, { value: v });
  }
  Object.defineProperty(root, 'WebSocket', { value: WebSocket, configurable: true, writable: true });
}
