// Several onMessage listeners: WebKit takes the first one's return —
// usually undefined — as the answer, where Chrome waits for whichever
// calls sendResponse or returns true. So the extension's listeners are
// gathered behind a single one of WebKit's that follows Chrome's rule.

import { URL } from './captured';
import { rethrowLater, type Listener } from './events';
import { messageKey, type Verdicts } from './message-verdicts';
import type { Shim, WebKitObject } from './types';

/** How long a page that has nothing to say waits before saying so. */
const SILENCE_MS = 10000;

/** Is the worker there? Only the worker answers, with "pong". */
export interface Ping {
  __motePing: true;
}

/** A tab's message, handed by the worker to the extension's pages framed in that tab (see replies.ts). */
export interface ToFrame {
  __moteToFrame: { tabId: number; urls: string[]; message: unknown };
}

/** A call a page framed in a website can't make itself, asked of the worker (see embedded.ts). */
export interface WorkerCall {
  __moteCall: { space: string; method: string; args: unknown[] };
}

/** The worker's answer to a `WorkerCall`. */
export type WorkerCallReply = { value: unknown } | { error: string };

type SendResponse = (value: unknown) => void;

function nothing(): void {}

/** Calls the listeners Chrome's way: whichever returns true or a promise keeps the answer open. */
function callListeners(
  listeners: Iterable<Listener>,
  message: unknown,
  sender: unknown,
  sendResponse: SendResponse,
): boolean {
  let keep = false;
  for (const listener of [...listeners]) {
    let result;
    try {
      result = listener(message, sender, sendResponse);
    } catch (e) {
      rethrowLater(e);
      continue;
    }
    if (result === true) keep = true;
    else if (result && typeof result.then === 'function') {
      keep = true;
      result.then(sendResponse, () => sendResponse(undefined));
    }
  }
  return keep;
}

export function createGather(shim: Shim, verdicts: Verdicts) {
  const { root, chrome, runtime, put, inContent, embedded, background } = shim;
  const { channel, me, peers, waiting, present, deaf, tell, join, leave } = verdicts;
  // The tab an extension's framed page is in, asked once (see `__moteToFrame`).
  let ownTab: Promise<number | null> | null = null;

  /** A tab's message for a page framed in it: taken by the frame it names, in the tab it names. */
  const toFrame = (
    to: ToFrame['__moteToFrame'],
    listeners: Set<Listener>,
    sender: unknown,
    sendResponse: SendResponse,
  ): true | undefined => {
    if (!embedded || !(to.urls || []).includes(location.href)) {
      if (!background) setTimeout(() => sendResponse(undefined), SILENCE_MS);
      return background ? undefined : true;
    }
    if (!ownTab) {
      const ask: WorkerCall = { __moteCall: { space: 'tabs', method: 'getCurrent', args: [] } };
      ownTab = Promise.resolve(runtime.sendMessage(ask)).then(
        (reply: any) => (reply && reply.value ? reply.value.id : null),
        () => null,
      );
    }
    ownTab.then((id) => {
      if (id !== to.tabId) return setTimeout(() => sendResponse(undefined), SILENCE_MS);
      if (!callListeners(listeners, to.message, sender, sendResponse)) sendResponse(undefined);
      return undefined;
    });
    return true;
  };

  /**
   * A call one of the extension's pages in a website's frame can't
   * make itself (see `embedded`), made here for it — and only for
   * one of its pages: a content script gets no more than Chrome
   * gives it.
   */
  const callFor = (
    call: WorkerCall['__moteCall'],
    sender: WebKitObject,
    sendResponse: (reply: WorkerCallReply) => void,
  ): true | undefined => {
    if (!background) return true;
    const { space, method, args } = call;
    const own = (() => {
      try {
        return new URL(sender.url).origin === location.origin;
      } catch {
        return false;
      }
    })();
    if (!own) {
      sendResponse({ error: 'chrome.' + space + " isn't available to content scripts" });
      return undefined;
    }
    if (space === 'tabs' && method === 'getCurrent') {
      sendResponse({ value: sender.tab });
      return undefined;
    }
    let ns;
    try {
      ns = chrome[space];
    } catch {}
    if (!ns || typeof ns[method] !== 'function') {
      sendResponse({ error: 'chrome.' + space + '.' + method + " isn't available" });
      return undefined;
    }
    Promise.resolve()
      .then(() => ns[method](...(args || [])))
      .then(
        (value) => sendResponse({ value }),
        (e) => sendResponse({ error: String((e && e.message) || e) }),
      );
    return true;
  };

  /**
   * Nothing here answers it. In Chrome that leaves the question to
   * the extension's other pages and its worker; WebKit takes the
   * first reply from any of them, and an empty one from a page that
   * only listens for something else — an offscreen document, an
   * options page — would arrive before the worker's real answer. So
   * a page that has nothing to say steps aside, and says nothing
   * only once everyone else has had ample time — or as soon as the
   * worker and every other open page have said they let it pass too,
   * or the worker sent it itself. Bitwarden's offscreen document
   * keeps its storage and answers a save with nothing: ten seconds
   * on each one got in the way of signing in.
   */
  const stepAside = (message: unknown, isSettled: () => boolean, sendResponse: SendResponse): void => {
    const received = Date.now();
    const key = channel && messageKey(message);
    let check = nothing;
    let roll: ReturnType<typeof setTimeout> | undefined;
    const done = (): void => {
      waiting.delete(check);
      clearTimeout(late);
      clearTimeout(roll);
    };
    const late = setTimeout(() => {
      done();
      sendResponse(undefined);
    }, SILENCE_MS);
    if (!key) return;
    // Only what was said about this message, not an identical one
    // a while ago.
    const fresh = (said: { at: number } | null | undefined): boolean => !!said && said.at >= received - 2000;
    check = () => {
      const entry = verdicts.verdicts.get(key);
      if (isSettled() || !entry) return;
      const worker = entry.worker;
      if (fresh(worker) && worker!.verdict === 'answers') {
        done();
        return;
      }
      const said = [...peers]
        .filter((id) => !deaf.has(id) || entry.pages.has(id))
        .map((id) => entry.pages.get(id));
      if (said.some((p) => fresh(p) && p!.verdict === 'answers')) {
        done();
        return;
      }
      if (!fresh(worker) || said.some((p) => !fresh(p))) return;
      done();
      sendResponse(undefined);
    };
    waiting.add(check);
    check();
    // Still waiting on someone after a moment: those who don't say
    // they are here within a second are gone, and those who do but
    // still have said nothing about this message didn't hear it.
    roll = setTimeout(() => {
      if (isSettled()) return;
      const heard = new Set<string>();
      const hear = (id: string): void => {
        heard.add(id);
      };
      present.add(hear);
      channel!.postMessage({ roll: true, from: me });
      setTimeout(() => {
        present.delete(hear);
        for (const id of [...peers]) if (!heard.has(id)) peers.delete(id);
        const entry = verdicts.verdicts.get(key);
        for (const id of peers) {
          const p = entry && entry.pages.get(id);
          if (!p || p.at < received - 2000) deaf.add(id);
        }
        check();
      }, 1000);
    }, 200);
  };

  /**
   * Gathers the listeners of `event` (runtime.onMessage or onMessageExternal)
   * behind one of WebKit's. `told`: this page takes part in the verdicts.
   */
  return (event: WebKitObject, told?: boolean): void => {
    if (!event || typeof event.addListener !== 'function') return;
    const add = event.addListener.bind(event);
    const remove = event.removeListener.bind(event);
    const listeners = new Set<Listener>();
    let attached = false;
    const dispatch = function (message: any, sender: WebKitObject, respond: SendResponse) {
      let settled = false;
      const sendResponse: SendResponse = (value) => {
        if (!settled) {
          settled = true;
          respond(value);
        }
      };
      // Only the worker answers; any other page stays out of it.
      if (message && message.__motePing === true) {
        if (background) {
          sendResponse('pong');
          return undefined;
        }
        return true;
      }
      if (message && message.__moteUserScript === true) {
        // Set by the userScripts shim (see user-scripts.ts).
        const route = root.__moteUserScriptMessage;
        return route && route(message.message, sender, sendResponse) && !settled ? true : undefined;
      }
      // A tab's message, handed on by the worker (see alsoFramed): taken
      // by the frame it names, in the tab it names; every other page lets
      // it pass without answering, as it would a message not for it.
      if (message && message.__moteToFrame)
        return toFrame(message.__moteToFrame, listeners, sender, sendResponse);
      if (message && message.__moteCall) return callFor(message.__moteCall, sender, sendResponse);

      const keep = callListeners(listeners, message, sender, sendResponse);
      if (!inContent) tell(message, keep || settled ? 'answers' : 'passes', true);
      if (keep || settled) return keep && !settled ? true : undefined;
      if (!background && !inContent) {
        stepAside(message, () => settled, sendResponse);
        return true;
      }
      return undefined;
    };
    put(event, 'addListener', (listener: Listener) => {
      listeners.add(listener);
      if (told) join();
      if (!attached) {
        attached = true;
        add(dispatch);
      }
    });
    put(event, 'removeListener', (listener: Listener) => {
      listeners.delete(listener);
      if (told && listeners.size === 0) leave();
      if (attached && listeners.size === 0) {
        attached = false;
        remove(dispatch);
      }
    });
    put(event, 'hasListener', (listener: Listener) => listeners.has(listener));
    put(event, 'hasListeners', () => listeners.size > 0);
    // A worker may only add listeners while it starts; one that adds its
    // first later would be refused. So in a worker the one listener is
    // WebKit's from the start.
    if (background) {
      attached = true;
      add(dispatch);
    }
  };
}
