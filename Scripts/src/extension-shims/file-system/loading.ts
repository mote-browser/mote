// WebKit can't load `filesystem:` URLs, so where such a URL is handed to
// something that loads it, it is swapped for the file: a blob: URL in an
// image, a link or fetch; a data: URL for a download or a new tab, which the
// browser loads outside this page.

import { Element, FileReader, HTMLAnchorElement, HTMLImageElement, Response, URL } from '../captured';
import type { Root } from '../types';
import { fail, typed, type OriginStorage } from './origin-storage';
import { joinPath, parseFileSystemURL, type FileSystemType } from './paths';

/** Where a `filesystem:` URL of this page's origin points, or null. */
const parse = (url: unknown) => parseFileSystemURL(url, location.origin);

/** The URLs a download or a new tab or window is given. */
const urlsOf = (o: { url?: unknown }) =>
  typeof o.url === 'string' ? [o.url] : Array.isArray(o.url) ? o.url : null;

export interface FileCache {
  /** Drops the blob: URLs of a path and everything under it: its file changed or went. */
  forget(type: FileSystemType, path: string): void;
  /** The file a `filesystem:` URL of this origin names. */
  fileAt(url: string): Promise<File>;
  /** The blob: URL now standing for a filesystem: URL, made once per file. */
  blobURL(url: string): Promise<string>;
  /** The blob: URL already made for a filesystem: URL, or null. */
  ready(url: string): string | null;
  dataURL(url: string): Promise<string>;
}

/** Whether a `made` key, "<type>:<path>", is the path or under it. */
export function isUnder(key: string, type: FileSystemType, path: string): boolean {
  const [t, p] = [Number(key[0]), key.slice(2)];
  return t === type && (p === path || p.startsWith(path === '/' ? '/' : path + '/'));
}

export function createFileCache({ need }: OriginStorage): FileCache {
  // blob: URLs already made, by "<type>:<path>", so the same file set on an
  // image twice gets the same URL, and at once. Changing a file drops its.
  const made = new Map<string, string | Promise<string>>();
  const forget = (type: FileSystemType, path: string): void => {
    for (const [key, url] of made) {
      if (isUnder(key, type, path)) {
        made.delete(key);
        Promise.resolve(url).then(
          (u) => {
            if (u) setTimeout(() => URL.revokeObjectURL(u), 60000);
          },
          () => {},
        );
      }
    }
  };
  const fileAt = async (url: string): Promise<File> => {
    const at = parse(url);
    if (!at) throw fail('NotFoundError');
    const handle = await need(at.type, at.segs);
    if (handle.kind !== 'file') throw fail('NotFoundError');
    return typed(await handle.getFile());
  };
  const blobURL = (url: string): Promise<string> => {
    const at = parse(url);
    if (!at) return Promise.reject(fail('NotFoundError'));
    const key = at.type + ':' + joinPath(at.segs);
    if (!made.has(key)) {
      const p = fileAt(url).then((file) => {
        const u = URL.createObjectURL(file);
        made.set(key, u);
        return u;
      });
      made.set(key, p);
      p.catch(() => {
        if (made.get(key) === p) made.delete(key);
      });
    }
    return Promise.resolve(made.get(key)!);
  };
  const ready = (url: string): string | null => {
    const at = parse(url);
    const u = at && made.get(at.type + ':' + joinPath(at.segs));
    return typeof u === 'string' ? u : null;
  };
  const dataURL = (url: string): Promise<string> =>
    fileAt(url).then(
      (file) =>
        new Promise((resolve, reject) => {
          const reader = new FileReader();
          reader.onload = () => resolve(reader.result as string);
          reader.onerror = () => reject(reader.error);
          reader.readAsDataURL(file);
        }),
    );
  return { forget, fileAt, blobURL, ready, dataURL };
}

/**
 * Where a filesystem: URL is loaded. An image or link gets the blob: URL
 * once it's made — at once when it already was, so a src set again stays
 * put — and reads back the filesystem: URL, as in Chrome. A file that
 * isn't there leaves the URL as it was, so the image fails as it would.
 */
export function loadFileSystemURLs(root: Root, cache: FileCache): void {
  const shown = new WeakMap<object, { url: string; blob: string | null }>();
  const hook = (proto: object | undefined, prop: string): void => {
    const d = proto && Object.getOwnPropertyDescriptor(proto, prop);
    if (!d || !d.set || !d.get) return;
    const { get, set } = d;
    Object.defineProperty(
      proto,
      prop,
      Object.assign({}, d, {
        get(this: object) {
          const value = get.call(this);
          const was = shown.get(this);
          return was && was.blob === value ? was.url : value;
        },
        set(this: object, value: unknown) {
          const url = typeof value === 'string' ? value : null;
          if (!url || !url.startsWith('filesystem:') || !parse(url)) {
            shown.delete(this);
            return set.call(this, value);
          }
          const now = cache.ready(url);
          if (now) {
            shown.set(this, { url, blob: now });
            return set.call(this, now);
          }
          const was: { url: string; blob: string | null } = { url, blob: null };
          shown.set(this, was);
          cache.blobURL(url).then(
            (blob) => {
              if (shown.get(this) !== was) return;
              was.blob = blob;
              set.call(this, blob);
            },
            () => {
              if (shown.get(this) === was) {
                shown.delete(this);
                set.call(this, url);
              }
            },
          );
          return undefined;
        },
      }),
    );
  };
  hook(root.HTMLImageElement && HTMLImageElement!.prototype, 'src');
  hook(root.HTMLAnchorElement && HTMLAnchorElement!.prototype, 'href');
  // React and templates set the attribute, not the property.
  const setAttribute = Element!.prototype.setAttribute;
  Element!.prototype.setAttribute = function (this: Element, name: string, value: unknown) {
    if (typeof value === 'string' && value.startsWith('filesystem:')) {
      const n = String(name).toLowerCase();
      if (
        (n === 'src' && this instanceof HTMLImageElement!) ||
        (n === 'href' && this instanceof HTMLAnchorElement!)
      ) {
        (this as any)[n] = value;
        return;
      }
    }
    return setAttribute.call(this, name, value as string);
  };

  if (typeof root.fetch === 'function') {
    const fetch = root.fetch;
    root.fetch = function (this: unknown, input: unknown, _init?: unknown) {
      const url = typeof input === 'string' ? input : input instanceof URL ? input.href : null;
      if (!url || !url.startsWith('filesystem:') || !parse(url)) return fetch.apply(this, arguments as any);
      return cache.fileAt(url).then(
        (file) =>
          new Response(file, {
            status: 200,
            headers: {
              'Content-Type': file.type || 'application/octet-stream',
              'Content-Length': String(file.size),
            },
          }),
        () => {
          throw new TypeError('Load failed');
        },
      );
    };
  }
}

/**
 * The browser downloads and opens tabs from outside this page, where a blob:
 * URL of this page means nothing: those get the file itself, as a data: URL.
 */
export function handOverFileSystemURLs(
  root: Root,
  cache: FileCache,
  define: (target: object, key: string, value: unknown) => void,
): void {
  const chrome = root.chrome || root.browser;
  const lastError = (e: any, callback: () => unknown): void => {
    const runtime = chrome && chrome.runtime;
    try {
      Object.defineProperty(runtime, 'lastError', {
        value: { message: String((e && e.message) || e) },
        configurable: true,
      });
    } catch {}
    try {
      callback();
    } finally {
      try {
        delete runtime.lastError;
      } catch {}
    }
  };
  // WebKit's namespace objects are dropped when nothing holds them, and what was set with them.
  const held: object[] = [];
  const swap = (space: string, method: string, urls: (options: any) => unknown[] | null): void => {
    const ns = chrome && chrome[space];
    const original = ns && ns[method];
    if (typeof original !== 'function') return;
    held.push(ns);
    define(ns, method, function (this: unknown, options: any, ...rest: unknown[]) {
      const list = options && urls(options);
      if (!list || !list.some((u: unknown) => typeof u === 'string' && parse(u)))
        return original.call(this, options, ...rest);
      const callback =
        typeof rest[rest.length - 1] === 'function' ? (rest.pop() as (v?: unknown) => unknown) : null;
      const p = Promise.all(
        list.map((u: unknown) => (typeof u === 'string' && parse(u) ? cache.dataURL(u) : u)),
      ).then((done) => {
        const copy = Object.assign({}, options, { url: Array.isArray(options.url) ? done : done[0] });
        return original.call(this, copy, ...rest);
      });
      if (!callback) return p;
      p.then(
        (v) => callback(v),
        (e) => lastError(e, callback),
      );
      return undefined;
    });
  };
  swap('downloads', 'download', urlsOf);
  swap('tabs', 'create', urlsOf);
  swap('windows', 'create', urlsOf);
}
