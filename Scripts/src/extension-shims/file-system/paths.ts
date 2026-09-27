// Paths and `filesystem:` URLs of the rebuilt FileSystem API (see file-system.ts).

export const TEMPORARY = 0;
export const PERSISTENT = 1;
export type FileSystemType = typeof TEMPORARY | typeof PERSISTENT;

/** The folders at the root of the origin private file system, by type. */
export const KINDS = ['temporary', 'persistent'] as const;

/** Paths are kept as their segments; "/a/b" is ["a", "b"]. `path` is resolved against `base`. */
export function segments(base: string, path: unknown): string[] {
  const text = String(path ?? '');
  const out = text.startsWith('/') ? [] : base.split('/').filter(Boolean);
  for (const part of text.split('/')) {
    if (!part || part === '.') continue;
    if (part === '..') out.pop();
    else out.push(part);
  }
  return out;
}

export function joinPath(segs: readonly string[]): string {
  return '/' + segs.join('/');
}

/** Where a `filesystem:` URL points: a file system type and a path. */
export interface FileSystemLocation {
  type: FileSystemType;
  segs: string[];
}

/** filesystem:<this origin>/<persistent|temporary>/<path>, or null. */
export function parseFileSystemURL(url: unknown, origin: string): FileSystemLocation | null {
  const s = String(url);
  if (!s.startsWith('filesystem:')) return null;
  const m = /^filesystem:([^/]+:\/\/[^/]+)\/(temporary|persistent)(\/[^?#]*)?/i.exec(s);
  if (!m || m[1] !== origin) return null;
  let segs;
  try {
    segs = segments('/', (m[3] || '/').split('/').map(decodeURIComponent).join('/'));
  } catch {
    return null;
  }
  return { type: KINDS.indexOf(m[2]!.toLowerCase() as (typeof KINDS)[number]) as FileSystemType, segs };
}

/** The `filesystem:` URL of a path. */
export function fileSystemURL(origin: string, type: FileSystemType, fullPath: string): string {
  return (
    'filesystem:' +
    origin +
    '/' +
    KINDS[type] +
    (fullPath === '/'
      ? '/'
      : segments('/', fullPath)
          .map(encodeURIComponent)
          .map((s) => '/' + s)
          .join(''))
  );
}

/** OPFS files come without a type; a blob: URL or download wants one. */
const TYPES: Record<string, string> = {
  png: 'image/png',
  jpg: 'image/jpeg',
  jpeg: 'image/jpeg',
  gif: 'image/gif',
  webp: 'image/webp',
  svg: 'image/svg+xml',
  pdf: 'application/pdf',
  txt: 'text/plain',
  html: 'text/html',
  json: 'application/json',
  mp4: 'video/mp4',
  webm: 'video/webm',
};

/** A file's type, or the one its name's extension says, or "". */
export function typeOf(file: { type: string; name: string }): string {
  return file.type || TYPES[(file.name.split('.').pop() || '').toLowerCase()] || '';
}
