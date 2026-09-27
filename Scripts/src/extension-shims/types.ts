/** What Swift supplies for each extension (`ExtensionShims.shim(for:)`), as `moteConfig`. */
export interface ShimConfig {
  /** The `namespace.onEvent` names the extension's code mentions, so late listeners can be heard. */
  events: string[];
  /** Every script the extension ships, by path from its root; an empty one is prefixed with "-". */
  scripts: string[];
  /** The Chrome version Mote presents itself as, e.g. "140.0.7339.0". */
  chromeVersion: string;
  /** A test run: what the extension logs as errors is reported to the browser too. */
  verbose: boolean;
}

/**
 * A call answered by the browser: a native message to the `mote` application,
 * which `ExtensionShims.answer` takes up.
 */
export interface NativeRequest {
  /** `namespace.method` (`bookmarks.getTree`), or `setting.get:privacy.services.passwordSavingEnabled`. */
  api: string;
  args: unknown[];
}

/** The browser's answer to a `NativeRequest`. */
export type NativeReply = { value: unknown; error?: undefined } | { error: string; value?: undefined };

/** Sends a request to the browser, resolving with its value or rejecting with its error. */
export type Native = (api: string, args: unknown[]) => Promise<any>;

/**
 * WebKit's extension objects — `chrome` and its namespaces, events and ports —
 * are only known at run time: the shim tests for every member before using it.
 */
export type WebKitObject = any;

/** The global object: a window, a worker, or an extension's service worker. */
export type Root = typeof globalThis & Record<string, any>;

export type Callback = (...args: any[]) => unknown;

/** What every part of the shim shares, settled once as it starts. */
export interface Shim {
  root: Root;
  config: ShimConfig;
  /** `chrome`, or `browser` where only that is defined. */
  chrome: WebKitObject;
  runtime: WebKitObject;
  /** A content script on a web page: only Chrome's behaviour is mended there. */
  inContent: boolean;
  /** One of the extension's pages in a frame of a website (see `isEmbedded`). */
  embedded: boolean;
  /** The extension's service worker. */
  worker: boolean;
  /** The extension's background: its service worker, or its background page. */
  background: boolean;
  /** The namespaces WebKit gives this context, as the shim found them. */
  spaces: Set<string>;
  /** Every object the shim has touched, held for good (see `createHolder`). */
  kept: Set<object>;
  /** Sets a member on one of WebKit's objects, holding the object. */
  put(target: WebKitObject, key: string, value: unknown): void;
  native: Native;
  /** Calls `callback` with `runtime.lastError` set to `error`, as Chrome reports a failure. */
  withLastError(error: unknown, callback: Callback): void;
}
