// Chrome's FileSystem entries, directory readers and FileWriter, on the
// origin private file system.

import { Blob } from '../captured';
import { asError, fail, settle, typed, type Handle, type OriginStorage } from './origin-storage';
import { fileSystemURL, joinPath, segments, type FileSystemType } from './paths';

/** A file system as Chrome hands it out: a name and its root. */
export interface FileSystem {
  name: string;
  root: InstanceType<FileSystemClasses['DirectoryEntry']>;
}

export type FileSystemClasses = ReturnType<typeof createEntries>;

/** Copies a file, or a directory with everything in it, into `into` as `name`. */
async function copy(handle: Handle, into: FileSystemDirectoryHandle, name: string): Promise<void> {
  if (handle.kind === 'file') {
    const w = await (await into.getFileHandle(name, { create: true })).createWritable();
    await w.write(await handle.getFile());
    return w.close();
  }
  const dir = await into.getDirectoryHandle(name, { create: true });
  for await (const [child, h] of (handle as any).entries()) await copy(h, dir, child);
}

/**
 * The entry classes, on `storage`. `forget` is told of every path whose file
 * changes or goes, and everything under it.
 */
export function createEntries(storage: OriginStorage, forget: (type: FileSystemType, path: string) => void) {
  const { walk, lookup, need } = storage;

  const systems: FileSystem[] = [];
  const system = (type: FileSystemType): FileSystem =>
    systems[type] ||
    (systems[type] = (() => {
      const fs = { name: location.host + ':' + (type ? 'Persistent' : 'Temporary') } as FileSystem;
      fs.root = new DirectoryEntry(fs, type, '/');
      return fs;
    })());

  class Entry {
    declare readonly _type: FileSystemType;
    declare filesystem: FileSystem;
    declare fullPath: string;
    declare name: string;

    constructor(fs: FileSystem, type: FileSystemType, path: string) {
      Object.defineProperty(this, '_type', { value: type });
      this.filesystem = fs;
      this.fullPath = path;
      this.name = path === '/' ? '' : path.split('/').pop()!;
    }
    get _segs(): string[] {
      return segments('/', this.fullPath);
    }
    toURL(): string {
      return fileSystemURL(location.origin, this._type, this.fullPath);
    }
    toInternalURL(): string {
      return this.toURL();
    }
    getParent(success?: unknown, error?: unknown): void {
      settle(
        Promise.resolve(new DirectoryEntry(this.filesystem, this._type, joinPath(this._segs.slice(0, -1)))),
        success,
        error,
      );
    }
    getMetadata(success?: unknown, error?: unknown): void {
      settle(
        (async () => {
          const handle = await need(this._type, this._segs);
          if (handle.kind === 'directory') return { modificationTime: new Date(), size: 0 };
          const file = await handle.getFile();
          return { modificationTime: new Date(file.lastModified), size: file.size };
        })(),
        success,
        error,
      );
    }
    remove(success?: unknown, error?: unknown): void {
      settle(
        (async () => {
          const segs = this._segs;
          if (!segs.length) throw fail('InvalidModificationError', 'The root directory cannot be removed.');
          const handle = await need(this._type, segs);
          // Not recursive: a directory with something in it is refused, as in
          // Chrome — WebKit says UnknownError there, Chrome InvalidModificationError.
          await (await walk(this._type, segs.slice(0, -1))).removeEntry(segs[segs.length - 1]!).catch((e) => {
            throw handle.kind === 'directory' && e.name !== 'NotFoundError'
              ? fail('InvalidModificationError', 'The directory is not empty.')
              : e;
          });
          forget(this._type, this.fullPath);
        })(),
        success,
        error,
      );
    }
    moveTo(parent: unknown, name?: unknown, success?: unknown, error?: unknown): void {
      settle(this._transfer(parent, name, true), success, error);
    }
    copyTo(parent: unknown, name?: unknown, success?: unknown, error?: unknown): void {
      settle(this._transfer(parent, name, false), success, error);
    }
    async _transfer(parent: unknown, name: unknown, move: boolean): Promise<Entry> {
      if (!(parent instanceof DirectoryEntry))
        throw fail('TypeMismatchError', 'The parent is not a directory.');
      const newName = name == null || name === '' ? this.name : String(name);
      if (!newName || newName.includes('/') || newName === '.' || newName === '..') {
        throw fail('EncodingError', 'Invalid name.');
      }
      const from = this._segs;
      const to = [...parent._segs, newName];
      const same = parent._type === this._type;
      if (!from.length)
        throw fail('InvalidModificationError', 'The root directory cannot be moved or copied.');
      if (same && (joinPath(to) === this.fullPath || joinPath(to).startsWith(this.fullPath + '/'))) {
        throw fail('InvalidModificationError', 'An entry cannot be moved or copied onto or into itself.');
      }
      const handle = await need(this._type, from);
      const into = await need(parent._type, parent._segs);
      if (into.kind !== 'directory') throw fail('NotFoundError');
      // What is already there is replaced if it is a file over a file, or an
      // empty directory over a directory; otherwise Chrome refuses.
      const there = await lookup(parent._type, to).catch(() => null);
      if (there) {
        if (there.kind !== handle.kind)
          throw fail('InvalidModificationError', 'An entry of another kind is in the way.');
        await into.removeEntry(newName).catch(() => {
          throw fail('InvalidModificationError', 'The directory in the way is not empty.');
        });
        forget(parent._type, joinPath(to));
      }
      let moved = false;
      if (move && same && typeof (handle as any).move === 'function') {
        try {
          await (handle as any).move(into, newName);
          moved = true;
        } catch {}
      }
      if (!moved) {
        await copy(handle, into, newName);
        if (move) {
          await (
            await walk(this._type, from.slice(0, -1))
          ).removeEntry(from[from.length - 1]!, { recursive: true });
        }
      }
      if (move) forget(this._type, this.fullPath);
      // Each subclass says which it is.
      const Kind = (this as unknown as { isDirectory: boolean }).isDirectory ? DirectoryEntry : FileEntry;
      return new Kind(parent.filesystem, parent._type, joinPath(to));
    }
  }

  class DirectoryEntry extends Entry {
    get isFile(): boolean {
      return false;
    }
    get isDirectory(): boolean {
      return true;
    }
    createReader(): DirectoryReader {
      return new DirectoryReader(this);
    }
    getFile(path: unknown, options?: unknown, success?: unknown, error?: unknown): void {
      settle(this._get(path, options, 'file'), success, error);
    }
    getDirectory(path: unknown, options?: unknown, success?: unknown, error?: unknown): void {
      settle(this._get(path, options, 'directory'), success, error);
    }
    async _get(path: unknown, options: any, kind: 'file' | 'directory'): Promise<Entry> {
      const create = !!(options && options.create);
      const exclusive = !!(options && options.exclusive);
      const segs = segments(this.fullPath, path);
      if (!segs.length) {
        if (kind === 'file') throw fail('TypeMismatchError', 'The root is a directory.');
        if (create && exclusive) throw fail('InvalidModificationError', 'The directory already exists.');
        return this.filesystem.root;
      }
      const dir = await walk(this._type, segs.slice(0, -1)).catch((e) => {
        throw e.name === 'TypeMismatchError' ? fail('NotFoundError') : e;
      });
      const name = segs[segs.length - 1]!;
      if (create && exclusive) {
        const there = await lookup(this._type, segs).catch(() => null);
        if (there) throw fail('InvalidModificationError', 'The entry already exists.');
      }
      await (kind === 'file'
        ? dir.getFileHandle(name, { create })
        : dir.getDirectoryHandle(name, { create }));
      const Kind = kind === 'file' ? FileEntry : DirectoryEntry;
      return new Kind(this.filesystem, this._type, joinPath(segs));
    }
    removeRecursively(success?: unknown, error?: unknown): void {
      settle(
        (async () => {
          const segs = this._segs;
          if (!segs.length) throw fail('InvalidModificationError', 'The root directory cannot be removed.');
          await need(this._type, segs);
          await (
            await walk(this._type, segs.slice(0, -1))
          ).removeEntry(segs[segs.length - 1]!, { recursive: true });
          forget(this._type, this.fullPath);
        })(),
        success,
        error,
      );
    }
  }

  // Chrome hands a directory's entries over in batches, then an empty one to
  // say it's done; callers loop until they see it.
  class DirectoryReader {
    declare _dir: DirectoryEntry;
    declare _left: Entry[] | null;

    constructor(dir: DirectoryEntry) {
      this._dir = dir;
      this._left = null;
    }
    readEntries(success?: unknown, error?: unknown): void {
      settle(
        (async () => {
          const dir = this._dir;
          if (!this._left) {
            const handle = await need(dir._type, dir._segs);
            this._left = [];
            for await (const [name, h] of (handle as any).entries() as AsyncIterable<[string, Handle]>) {
              const Kind = h.kind === 'file' ? FileEntry : DirectoryEntry;
              this._left.push(new Kind(dir.filesystem, dir._type, joinPath([...dir._segs, name])));
            }
          }
          return this._left.splice(0, 100);
        })(),
        success,
        error,
      );
    }
  }

  class FileEntry extends Entry {
    get isFile(): boolean {
      return true;
    }
    get isDirectory(): boolean {
      return false;
    }
    file(success?: unknown, error?: unknown): void {
      settle(
        (async () => {
          const handle = await need(this._type, this._segs);
          if (handle.kind !== 'file') throw fail('TypeMismatchError');
          return typed(await handle.getFile());
        })(),
        success,
        error,
      );
    }
    createWriter(success?: unknown, error?: unknown): void {
      settle(
        (async () => {
          const handle = await need(this._type, this._segs);
          if (handle.kind !== 'file') throw fail('TypeMismatchError');
          return new FileWriter(this, handle, (await handle.getFile()).size);
        })(),
        success,
        error,
      );
    }
  }

  // One write or truncate at a time, each a writable opened on the file as it
  // is and closed — OPFS commits on close — with Chrome's events around it:
  // writestart, write, writeend, or error then writeend.
  class FileWriter extends EventTarget {
    declare readonly _entry: FileEntry;
    declare readonly _handle: FileSystemFileHandle;
    declare _token: object | null;
    declare readyState: number;
    declare position: number;
    declare length: number;
    declare error: unknown;
    declare onwritestart: ((event: ProgressEvent) => unknown) | null;
    declare onprogress: ((event: ProgressEvent) => unknown) | null;
    declare onwrite: ((event: ProgressEvent) => unknown) | null;
    declare onabort: ((event: ProgressEvent) => unknown) | null;
    declare onerror: ((event: ProgressEvent) => unknown) | null;
    declare onwriteend: ((event: ProgressEvent) => unknown) | null;

    constructor(entry: FileEntry, handle: FileSystemFileHandle, length: number) {
      super();
      Object.defineProperty(this, '_entry', { value: entry });
      Object.defineProperty(this, '_handle', { value: handle });
      Object.defineProperty(this, '_token', { value: null, writable: true });
      this.readyState = 0;
      this.position = 0;
      this.length = length;
      this.error = null;
      this.onwritestart =
        this.onprogress =
        this.onwrite =
        this.onabort =
        this.onerror =
        this.onwriteend =
          null;
    }
    _fire(type: string, loaded: number, total: number): void {
      const event = new ProgressEvent(type, { lengthComputable: true, loaded, total });
      this.dispatchEvent(event);
      const handler = (this as any)['on' + type];
      if (typeof handler === 'function') handler.call(this, event);
    }
    _run(size: number, work: (w: FileSystemWritableFileStream) => Promise<unknown>, after: () => void): void {
      if (this.readyState === 1) throw fail('InvalidStateError', 'A write is already in progress.');
      this.readyState = 1;
      this.error = null;
      const run = (this._token = {});
      setTimeout(async () => {
        if (this._token !== run) return;
        this._fire('writestart', 0, size);
        try {
          const w = await this._handle.createWritable({ keepExistingData: true });
          try {
            await work(w);
            await w.close();
          } catch (e) {
            await w.abort().catch(() => {});
            throw e;
          }
          if (this._token !== run) return;
          after();
          forget(this._entry._type, this._entry.fullPath);
          this.readyState = 2;
          this._fire('progress', size, size);
          this._fire('write', size, size);
        } catch (e) {
          if (this._token !== run) return;
          this.error = asError(e);
          this.readyState = 2;
          this._fire('error', 0, size);
        }
        this._fire('writeend', this.readyState === 2 ? size : 0, size);
      });
    }
    write(data: unknown): void {
      if (!(data instanceof Blob)) {
        throw new TypeError("Failed to execute 'write' on 'FileWriter': parameter 1 is not of type 'Blob'.");
      }
      const at = this.position;
      this._run(
        data.size,
        (w) => w.write({ type: 'write', position: at, data }),
        () => {
          this.position = at + data.size;
          this.length = Math.max(this.length, this.position);
        },
      );
    }
    truncate(size: unknown): void {
      const length = Math.max(0, Number(size) || 0);
      this._run(
        0,
        (w) => w.truncate(length),
        () => {
          this.length = length;
          this.position = Math.min(this.position, length);
        },
      );
    }
    seek(offset: unknown): void {
      if (this.readyState === 1) throw fail('InvalidStateError', 'A write is in progress.');
      let at = Number(offset) || 0;
      if (at < 0) at = Math.max(0, this.length + at);
      this.position = Math.min(at, this.length);
    }
    abort(): void {
      if (this.readyState !== 1) return;
      this._token = null;
      this.readyState = 2;
      this.error = fail('AbortError', 'The write was aborted.');
      this._fire('abort', 0, 0);
      this._fire('writeend', 0, 0);
    }
  }
  for (const [k, v] of [
    ['INIT', 0],
    ['WRITING', 1],
    ['DONE', 2],
  ] as const) {
    Object.defineProperty(FileWriter, k, { value: v });
    Object.defineProperty(FileWriter.prototype, k, { value: v });
  }

  return { Entry, DirectoryEntry, DirectoryReader, FileEntry, FileWriter, system };
}
