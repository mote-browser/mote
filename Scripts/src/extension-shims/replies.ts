// WebKit unloads an extension's worker after half a minute idle, and
// starts it again for an event only if it remembers a listener for
// it — which it does for messages, the worker's listener being in
// place from its first line (see messaging.ts).
//
// A reply that never came is answered Chrome's way: in callback
// form, with lastError set — WebKit calls back with nothing and no
// error, and code that pings a tab to see if its script is there
// waits for ever.

import { NO_RECEIVER } from './embedded';
import type { Verdicts } from './message-verdicts';
import type { Ping, ToFrame } from './messaging';
import type { Callback, Shim } from './types';

export const PORT_CLOSED = 'The message port closed before a response was received.';

/** Settles a callback with the reply, or with lastError set to `gone` when there was none. */
function replied(shim: Shim, promise: Promise<unknown>, callback: unknown, gone: string) {
  if (typeof callback !== 'function') return promise;
  promise.then(
    (r) => (r === undefined ? shim.withLastError(new Error(gone), callback as Callback) : callback(r)),
    (e) => shim.withLastError(e, callback as Callback),
  );
  return undefined;
}

/** The message `runtime.sendMessage(...args)` sends: the first argument, or the second after an extension id. */
export function sentMessage(args: unknown[]): unknown {
  return typeof args[0] === 'string' && args.length > 1 && typeof args[1] !== 'function' ? args[1] : args[0];
}

function pause(ms: number): Promise<unknown> {
  return new Promise((w) => setTimeout(w, ms));
}

function nothing(): void {}

export function mendReplies(shim: Shim, verdicts: Verdicts): void {
  const { chrome, runtime, put, inContent, background, native, config } = shim;
  let checkWorker = nothing;
  // When the worker was last heard from — a reply, a port message.
  let heard = 0;

  if (runtime && typeof runtime.sendMessage === 'function') {
    const page = typeof document !== 'undefined';
    // WebKit's own, looked up at each call — not held from the page's
    // first moment, when the page isn't yet the tab or popup it will be.
    const original = Object.getPrototypeOf(runtime).sendMessage;
    const send = (...args: unknown[]): Promise<unknown> => original.apply(chrome.runtime, args);
    // WebKit can also lose a worker without knowing — its process
    // stopped along with a tab's — and then answers every message with
    // nothing, for good. So after waking it, a page asks the worker
    // itself (its shim answers) at most every few seconds; no answer,
    // and the browser takes the extension up afresh.
    const hasWorker = (() => {
      try {
        const b = runtime.getManifest().background || {};
        return !!(b.service_worker || b.scripts || b.page);
      } catch {
        return false;
      }
    })();
    // The message itself doesn't wait on the answer: a worker busy
    // starting up can take seconds. An empty reply means gone; silence
    // for a quarter of a minute does too.
    let asking = false;
    const check = (): void => {
      if (!hasWorker || asking || Date.now() - heard < 5000) return;
      asking = true;
      // Asked three times, a second apart, then once more after waking
      // it — only then taken for gone: a restart has consequences
      // (welcome pages, a popup loading again), and a question can go
      // unanswered for reasons that pass. Waking a worker that runs
      // starts it over, so that is kept for last.
      const ping = Object.getPrototypeOf(runtime).sendMessage;
      const ask = (): Promise<unknown> =>
        Promise.race([
          ping.call(runtime, { __motePing: true } satisfies Ping),
          new Promise((r) => setTimeout(() => r('late'), 15000)),
        ]).catch(() => undefined);
      const tries = [
        () => ask(),
        () => pause(1000).then(ask),
        () => pause(1000).then(ask),
        () =>
          native('background.wake', [])
            .catch(() => {})
            .then(() => pause(1000))
            .then(ask),
      ];
      const attempt = (i: number, last?: unknown): Promise<unknown> =>
        i >= tries.length || last === 'pong'
          ? Promise.resolve(last)
          : tries[i]!().then((r) => attempt(i + 1, r));
      const started = Date.now();
      attempt(0)
        .then((r) => {
          // Any real answer from the worker meanwhile says it runs, too:
          // the question alone can go unheard from a page that listens.
          if (r === 'pong' || heard >= started) heard = Math.max(heard, Date.now());
          else {
            if (config.verbose) {
              native('debug.error', ['worker check: ' + String(r) + ' from ' + location.pathname]).catch(
                () => {},
              );
            }
            native('background.revive', []).catch(() => {});
          }
        })
        .finally(() => {
          asking = false;
        });
    };
    checkWorker = page ? check : nothing;
    put(runtime, 'sendMessage', (...args: unknown[]) => {
      const callback = typeof args[args.length - 1] === 'function' ? args.pop() : null;
      // Never heard back by the one that sends it, so said for it.
      if (!inContent) verdicts.tell(sentMessage(args), 'passes');
      checkWorker();
      const answer = send(...args).then((r) => {
        if (r !== undefined) heard = Date.now();
        return r;
      });
      return replied(shim, answer, callback, PORT_CLOSED);
    });
  }

  // A message for a tab reaches only its content scripts in WebKit. In
  // Chrome it reaches the extension's own pages framed in that tab too —
  // 1Password's sign-in banner is one, told this way to offer a passkey
  // instead of a password, and without it the site's request failed. So
  // the worker hands it to those frames as well, and the first answer
  // from either wins.
  const alsoFramed = (answer: Promise<unknown>, tabId: unknown, message: unknown, options: any) => {
    const nav = chrome.webNavigation;
    if (!nav || typeof nav.getAllFrames !== 'function' || typeof tabId !== 'number') return answer;
    const own = runtime.getURL('');
    const wanted = options && typeof options.frameId === 'number' ? options.frameId : null;
    const framed = Promise.resolve(nav.getAllFrames({ tabId })).then(
      (frames: any[]) => {
        const urls = (frames || [])
          .filter(
            (f) =>
              f.url && f.url.startsWith(own) && f.frameId !== 0 && (wanted === null || f.frameId === wanted),
          )
          .map((f) => f.url);
        if (!urls.length) return undefined;
        const handed: ToFrame = { __moteToFrame: { tabId, urls, message } };
        return Object.getPrototypeOf(runtime).sendMessage.call(runtime, handed);
      },
      () => undefined,
    );
    return new Promise((resolve, reject) => {
      let left = 2;
      let failure: unknown = null;
      const none = (): void => {
        if (--left === 0) {
          if (failure) reject(failure);
          else resolve(undefined);
        }
      };
      answer.then(
        (v) => (v !== undefined ? resolve(v) : none()),
        (e) => {
          failure = e;
          none();
        },
      );
      framed.then(
        (v: unknown) => (v !== undefined ? resolve(v) : none()),
        () => none(),
      );
    });
  };
  if (chrome.tabs && typeof chrome.tabs.sendMessage === 'function') {
    const send = chrome.tabs.sendMessage.bind(chrome.tabs);
    put(
      chrome.tabs,
      'sendMessage',
      (tabId: unknown, message: unknown, options?: unknown, callback?: unknown) => {
        if (typeof options === 'function') {
          callback = options;
          options = undefined;
        }
        const p = options === undefined ? send(tabId, message) : send(tabId, message, options);
        return replied(shim, background ? alsoFramed(p, tabId, message, options) : p, callback, NO_RECEIVER);
      },
    );
  }
  if (typeof document !== 'undefined' && runtime && typeof runtime.connect === 'function') {
    const connect = runtime.connect.bind(runtime);
    put(runtime, 'connect', (...args: unknown[]) => {
      checkWorker();
      const port = connect(...args);
      try {
        port.onMessage.addListener(() => {
          heard = Date.now();
        });
      } catch {}
      return port;
    });
  }
}
