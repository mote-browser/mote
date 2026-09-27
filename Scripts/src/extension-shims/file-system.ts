// Chrome's old FileSystem API — requestFileSystem, entries, FileWriter and
// `filesystem:` URLs — which WebKit never had. Extensions still save to it:
// GoFullPage writes every capture there and shows, copies and downloads it
// by a `filesystem:<origin>/persistent/...` URL it builds itself. So it is
// rebuilt on the origin private file system: PERSISTENT and TEMPORARY are
// the folders "persistent" and "temporary" at its root, so a filesystem: URL
// and the file it names have the same path. WebKit can't load that scheme,
// so where such a URL is handed to something that loads it is swapped for
// the file (see file-system/loading.ts).
// Extension pages only: a worker has no DOM to mend, and a content script
// shares the page's origin.

import { createEntries } from './file-system/entries';
import { createFileCache, handOverFileSystemURLs, loadFileSystemURLs } from './file-system/loading';
import { fail, settle, createOriginStorage } from './file-system/origin-storage';
import {
  joinPath,
  parseFileSystemURL,
  PERSISTENT,
  TEMPORARY,
  type FileSystemType,
} from './file-system/paths';
import type { Root } from './types';

function define(target: object, key: string, value: unknown): void {
  try {
    Object.defineProperty(target, key, { value, configurable: true, writable: true, enumerable: true });
  } catch {}
}

export function rebuildFileSystem(root: Root): void {
  if (
    root.requestFileSystem ||
    root.webkitRequestFileSystem ||
    typeof document === 'undefined' ||
    !(root.navigator && navigator.storage && navigator.storage.getDirectory)
  ) {
    return;
  }
  const storage = createOriginStorage();
  const cache = createFileCache(storage);
  const { Entry, DirectoryEntry, DirectoryReader, FileEntry, FileWriter, system } = createEntries(
    storage,
    cache.forget,
  );

  const requestFileSystem = (type: unknown, _size: unknown, success?: unknown, error?: unknown): void => {
    const kind = Number(type);
    settle(
      kind === TEMPORARY || kind === PERSISTENT
        ? storage.folder(kind).then(() => system(kind as FileSystemType))
        : Promise.reject(fail('InvalidModificationError', 'Unknown file system type.')),
      success,
      error,
    );
  };
  const resolveURL = (url: unknown, success?: unknown, error?: unknown): void => {
    settle(
      (async () => {
        const at = parseFileSystemURL(url, location.origin);
        if (!at) {
          throw fail(
            String(url).startsWith('filesystem:') ? 'SecurityError' : 'EncodingError',
            'Not a filesystem: URL of this origin.',
          );
        }
        const handle = await storage.need(at.type, at.segs);
        const fs = system(at.type);
        if (!at.segs.length) return fs.root;
        return new (handle.kind === 'file' ? FileEntry : DirectoryEntry)(fs, at.type, joinPath(at.segs));
      })(),
      success,
      error,
    );
  };

  define(root, 'TEMPORARY', TEMPORARY);
  define(root, 'PERSISTENT', PERSISTENT);
  define(root, 'requestFileSystem', requestFileSystem);
  define(root, 'webkitRequestFileSystem', requestFileSystem);
  define(root, 'resolveLocalFileSystemURL', resolveURL);
  define(root, 'webkitResolveLocalFileSystemURL', resolveURL);
  // Code for this API asks for quota first; OPFS has its own, so any is granted.
  const quota = {
    requestQuota: (size: unknown, success?: unknown, error?: unknown) =>
      settle(Promise.resolve(size), success, error),
    queryUsageAndQuota: (success?: unknown, error?: unknown) =>
      settle(
        navigator.storage.estimate().then((e) => [e.usage || 0, e.quota || 0]),
        (v: number[]) => typeof success === 'function' && success(v[0], v[1]),
        error,
      ),
  };
  const nav = navigator as Navigator & Record<string, unknown>;
  if (!nav.webkitPersistentStorage) define(navigator, 'webkitPersistentStorage', quota);
  if (!nav.webkitTemporaryStorage) define(navigator, 'webkitTemporaryStorage', quota);
  for (const [name, Kind] of [
    ['FileSystemEntry', Entry],
    ['FileSystemDirectoryEntry', DirectoryEntry],
    ['FileSystemFileEntry', FileEntry],
    ['FileSystemDirectoryReader', DirectoryReader],
  ] as const) {
    // WebKit has these for dropped files; its instanceof checks keep its own.
    if (!root[name]) define(root, name, Kind);
  }
  if (!root.FileWriter) define(root, 'FileWriter', FileWriter);

  loadFileSystemURLs(root, cache);
  handOverFileSystemURLs(root, cache, define);
}
