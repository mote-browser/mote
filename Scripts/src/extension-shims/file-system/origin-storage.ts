// The origin private file system, where the rebuilt FileSystem API keeps its
// files, and Chrome's way of answering its callbacks.

import { DOMException, File } from '../captured';
import { rethrowLater } from '../events';
import { KINDS, typeOf, type FileSystemType } from './paths';

/**
 * Chrome answers with DOMExceptions whose name says what went wrong; the
 * legacy code comes with the name (NotFoundError is 8, and so on).
 */
export function fail(name: string, message?: string): DOMException {
  return new DOMException(message || name, name);
}

export function asError(e: any): DOMException {
  return e instanceof DOMException
    ? e
    : fail((e && e.name) || 'InvalidStateError', (e && e.message) || String(e));
}

/**
 * Chrome calls back later, never in the same turn, success or not.
 * A callback that throws is reported as uncaught, not as a rejection.
 */
function invoke(f: (value: any) => unknown, v: unknown): void {
  try {
    f(v);
  } catch (e) {
    rethrowLater(e);
  }
}

export function settle(promise: Promise<unknown>, success: unknown, error: unknown): void {
  promise.then(
    (v) => {
      if (typeof success === 'function') invoke(success as (value: unknown) => unknown, v);
    },
    (e) => {
      if (typeof error === 'function') invoke(error as (value: unknown) => unknown, asError(e));
    },
  );
}

export type Handle = FileSystemFileHandle | FileSystemDirectoryHandle;

/** The file with the type its name says, when it has none (see `typeOf`). */
export function typed(file: File): File {
  const type = typeOf(file);
  return type === file.type ? file : new File([file], file.name, { type, lastModified: file.lastModified });
}

export interface OriginStorage {
  /** The folder of a file system type, made on first use. */
  folder(type: FileSystemType): Promise<FileSystemDirectoryHandle>;
  /** The directory at a path. */
  walk(type: FileSystemType, segs: readonly string[], create?: boolean): Promise<FileSystemDirectoryHandle>;
  /** The handle at a path, whichever kind it is, or null. */
  lookup(type: FileSystemType, segs: readonly string[]): Promise<Handle | null>;
  /** The handle at a path, or NotFoundError. */
  need(type: FileSystemType, segs: readonly string[]): Promise<Handle>;
}

export function createOriginStorage(): OriginStorage {
  const top: Promise<FileSystemDirectoryHandle>[] = [];
  const folder = (type: FileSystemType) =>
    top[type] ||
    (top[type] = navigator.storage
      .getDirectory()
      .then((d) => d.getDirectoryHandle(KINDS[type], { create: true })));
  const walk = async (type: FileSystemType, segs: readonly string[], create = false) => {
    let dir = await folder(type);
    for (const name of segs) dir = await dir.getDirectoryHandle(name, { create });
    return dir;
  };
  const lookup = async (type: FileSystemType, segs: readonly string[]): Promise<Handle | null> => {
    if (!segs.length) return folder(type);
    const dir = await walk(type, segs.slice(0, -1));
    const name = segs[segs.length - 1]!;
    try {
      return await dir.getFileHandle(name);
    } catch (e: any) {
      if (e.name !== 'TypeMismatchError') {
        if (e.name === 'NotFoundError') return null;
        throw e;
      }
    }
    return dir.getDirectoryHandle(name);
  };
  const need = async (type: FileSystemType, segs: readonly string[]): Promise<Handle> => {
    const handle = await lookup(type, segs).catch((e) => {
      if (e.name === 'NotFoundError') return null;
      throw e;
    });
    if (!handle) throw fail('NotFoundError', 'A requested file or directory could not be found.');
    return handle;
  };
  return { folder, walk, lookup, need };
}
