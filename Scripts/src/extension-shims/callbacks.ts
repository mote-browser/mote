// Chrome's APIs take a callback last, or return a promise without one.

import type { Callback, NativeReply, NativeRequest, Shim } from './types';

/** The native messaging application that is the browser itself (`ExtensionShims.application`). */
export const APPLICATION = 'mote';

/** Takes a trailing callback off `args`, or null when the last argument isn't a function. */
export function takeCallback(args: unknown[]): Callback | null {
  return args.length && typeof args[args.length - 1] === 'function' ? (args.pop() as Callback) : null;
}

/** A request to the browser. Its arguments go as JSON: what can't be said in JSON is left out. */
export function nativeRequest(api: string, args: unknown[] | undefined): NativeRequest {
  return { api, args: JSON.parse(JSON.stringify(args ?? [])) };
}

/** The value of the browser's answer, or its error thrown. */
export function replyValue(reply: NativeReply | null | undefined): unknown {
  if (reply && reply.error) throw new Error(reply.error);
  return reply ? reply.value : undefined;
}

/** The message Chrome gives `runtime.lastError` for a failure. */
export function errorMessage(error: any): string {
  return String((error && error.message) || error);
}

/** Settles `callback` with what `promise` resolves to, or with `lastError` set when it fails. */
export function settleCallback(shim: Shim, promise: Promise<unknown>, callback: Callback): void {
  promise.then(
    (value) => callback(value),
    (error) => shim.withLastError(error, callback),
  );
}

/** `f`, taking a callback last as well as returning a promise. */
export function withCallback(shim: Shim, f: (...args: any[]) => Promise<unknown>) {
  return (...args: unknown[]): Promise<unknown> | undefined => {
    const callback = takeCallback(args);
    const promise = f(...args);
    if (!callback) return promise;
    settleCallback(shim, promise, callback);
    return undefined;
  };
}

/** A method the browser answers: `api` is `namespace.method`. */
export function nativeCall(shim: Shim, api: string) {
  return withCallback(shim, (...args) => shim.native(api, args));
}

/**
 * Something only Chrome can do, answered the way Chrome answers when
 * it can't: a rejection, or lastError for a callback.
 */
export function refuse(shim: Shim, what: string) {
  return (...args: unknown[]): Promise<never> | undefined => {
    const callback = takeCallback(args);
    const error = new Error(what + " isn't available in Mote");
    if (!callback) return Promise.reject(error);
    shim.withLastError(error, callback);
    return undefined;
  };
}

/**
 * A method that answers at once with `value`, or with what `value` returns for
 * the arguments; a callback is called in a later turn.
 */
export function resolved(value: unknown) {
  return (...args: unknown[]): Promise<unknown> | undefined => {
    const callback = takeCallback(args);
    const v = typeof value === 'function' ? value(...args) : value;
    if (!callback) return Promise.resolve(v);
    setTimeout(() => callback(v));
    return undefined;
  };
}
