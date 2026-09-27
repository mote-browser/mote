// chrome.webRequest as Chrome has it.

import { resolved } from './callbacks';
import { createEvent, isEventName, type Listener } from './events';
import { fill } from './members';
import type { Shim } from './types';

export function fillWebRequest(shim: Shim, resourceTypes: Record<string, string>): void {
  fill(shim, 'webRequest', {
    OnBeforeRequestOptions: {
      BLOCKING: 'blocking',
      REQUEST_BODY: 'requestBody',
      EXTRA_HEADERS: 'extraHeaders',
    },
    OnBeforeSendHeadersOptions: {
      REQUEST_HEADERS: 'requestHeaders',
      BLOCKING: 'blocking',
      EXTRA_HEADERS: 'extraHeaders',
    },
    OnSendHeadersOptions: { REQUEST_HEADERS: 'requestHeaders', EXTRA_HEADERS: 'extraHeaders' },
    OnHeadersReceivedOptions: {
      BLOCKING: 'blocking',
      RESPONSE_HEADERS: 'responseHeaders',
      EXTRA_HEADERS: 'extraHeaders',
    },
    OnAuthRequiredOptions: {
      RESPONSE_HEADERS: 'responseHeaders',
      BLOCKING: 'blocking',
      ASYNC_BLOCKING: 'asyncBlocking',
      EXTRA_HEADERS: 'extraHeaders',
    },
    OnResponseStartedOptions: { RESPONSE_HEADERS: 'responseHeaders', EXTRA_HEADERS: 'extraHeaders' },
    OnBeforeRedirectOptions: { RESPONSE_HEADERS: 'responseHeaders', EXTRA_HEADERS: 'extraHeaders' },
    OnCompletedOptions: { RESPONSE_HEADERS: 'responseHeaders', EXTRA_HEADERS: 'extraHeaders' },
    OnErrorOccurredOptions: { EXTRA_HEADERS: 'extraHeaders' },
    ResourceType: resourceTypes,
    MAX_HANDLER_BEHAVIOR_CHANGED_CALLS_PER_10_MINUTES: 20,
    handlerBehaviorChanged: resolved(undefined),
    onActionIgnored: createEvent(),
  });
}

/** A request filter: what matters is its `urls`. */
export interface RequestFilter {
  urls?: string[];
  [key: string]: unknown;
}

/**
 * WebKit can't read ws:// and wss:// patterns, and refuses the
 * whole listener over one; Chrome watches sockets too. The
 * listener is kept for everything else: the filter without them, or
 * null when nothing is left.
 */
export function withoutSocketPatterns<F extends RequestFilter | undefined>(filter: F): F | null {
  if (!filter || !Array.isArray(filter.urls)) return filter;
  const urls = filter.urls.filter((u) => !/^wss?:/i.test(u));
  if (!urls.length) return null;
  return { ...filter, urls };
}

/** The extra info WebKit takes: headers and bodies, reported anyway, and no blocking. */
export function supportedExtraInfo(spec: readonly string[]): string[] {
  return spec.filter((s) => s === 'requestHeaders' || s === 'responseHeaders' || s === 'requestBody');
}

/** Whether WebKit refused a listener for being added after the worker's startup. */
export function isLateListenerError(error: unknown): boolean {
  return /startup/i.test(String(error && (error as Error).message));
}

/**
 * webRequest listeners with options WebKit doesn't take — blocking
 * needs a policy-installed extension in Chrome's MV3 too; extra headers
 * WebKit reports anyway — are added with the options it does take.
 */
export function mendRequestListeners({ chrome, put }: Shim): void {
  if (!chrome.webRequest) return;
  for (const key of Object.keys(chrome.webRequest)) {
    const target = chrome.webRequest[key];
    if (!isEventName(key) || !target || typeof target.addListener !== 'function') continue;
    const add = target.addListener.bind(target);
    put(target, 'addListener', (listener: Listener, filter?: RequestFilter, spec?: unknown) => {
      const kept = withoutSocketPatterns(filter);
      if (kept === null) return undefined;
      filter = kept;
      // Added after a worker's startup, WebKit refuses it; Chrome takes
      // it. It isn't heard, but neither does it stop the code that added
      // it — a listener for every request can't join the late list
      // (it would wake the worker for all of them).
      try {
        if (!Array.isArray(spec)) return add(listener, filter);
        try {
          return add(listener, filter, supportedExtraInfo(spec));
        } catch (e) {
          if (isLateListenerError(e)) throw e;
          return add(listener, filter);
        }
      } catch (e) {
        if (!isLateListenerError(e)) throw e;
      }
      return undefined;
    });
  }
}
