// Permissions. WebKit knows its own and throws on any other name,
// where Chrome answers false. The ones Mote answers itself are
// Mote's to grant: those a manifest names are granted, optional
// ones are asked for (`permissions.request`, answered by the browser).

import type { Callback, Shim } from './types';

/** Permissions WebKit knows. */
export const WEBKIT_PERMISSIONS = new Set([
  'activeTab',
  'alarms',
  'clipboardWrite',
  'contextMenus',
  'cookies',
  'declarativeNetRequest',
  'declarativeNetRequestFeedback',
  'declarativeNetRequestWithHostAccess',
  'menus',
  'nativeMessaging',
  'scripting',
  'storage',
  'tabs',
  'unlimitedStorage',
  'webNavigation',
  'webRequest',
]);

/** Permissions Mote grants itself, for the APIs the shim adds. */
export const MOTE_PERMISSIONS = new Set([
  'bookmarks',
  'history',
  'downloads',
  'downloads.open',
  'downloads.shelf',
  'downloads.ui',
  'tabGroups',
  'sidePanel',
  'offscreen',
  'notifications',
  'tts',
  'fontSettings',
  'management',
  'identity',
  'identity.email',
  'idle',
  'power',
  'privacy',
  'browsingData',
  'sessions',
  'topSites',
  'search',
  'system.cpu',
  'system.memory',
  'system.storage',
  'system.display',
  'readingList',
  'contentSettings',
  'proxy',
  'favicon',
  'clipboardRead',
  'geolocation',
  'userScripts',
]);

/** Permissions by who answers for them: WebKit, Mote, or no one. */
export function splitPermissions(list: string[] = []) {
  return {
    theirs: list.filter((p) => WEBKIT_PERMISSIONS.has(p)),
    mine: list.filter((p) => MOTE_PERMISSIONS.has(p)),
    unknown: list.filter((p) => !WEBKIT_PERMISSIONS.has(p) && !MOTE_PERMISSIONS.has(p)),
  };
}

interface Permissions {
  permissions?: string[];
  origins?: string[];
}

export function mendPermissions(shim: Shim): void {
  const { chrome, runtime, put, native } = shim;
  if (!chrome.permissions) return;
  const manifest = (() => {
    try {
      return runtime.getManifest() || {};
    } catch {
      return {};
    }
  })();
  const declared = new Set<string>(manifest.permissions || []);
  const p = chrome.permissions;
  const contains = p.contains.bind(p);
  const request = p.request.bind(p);
  const getAll = p.getAll.bind(p);
  const remove = p.remove.bind(p);
  const granted = () =>
    native('permissions.granted', []).then(
      (list: string[] | null) => new Set([...declared, ...(list || [])]),
    );
  const withCb =
    (f: (arg: Permissions) => Promise<unknown>) =>
    (arg?: Permissions, callback?: Callback): Promise<unknown> | undefined => {
      const pr = f(arg || {});
      if (typeof callback !== 'function') return pr;
      pr.then(
        (v) => callback(v),
        (e) => shim.withLastError(e, callback),
      );
      return undefined;
    };
  put(
    p,
    'contains',
    withCb(async ({ permissions = [], origins = [] }) => {
      const { theirs, mine, unknown } = splitPermissions(permissions);
      if (unknown.length) return false;
      if (mine.length) {
        const have = await granted();
        if (!mine.every((m) => have.has(m))) return false;
      }
      return theirs.length || origins.length ? contains({ permissions: theirs, origins }) : true;
    }),
  );
  put(
    p,
    'request',
    withCb(async ({ permissions = [], origins = [] }) => {
      const { theirs, mine, unknown } = splitPermissions(permissions);
      if (unknown.length) return false;
      if (mine.length) {
        const have = await granted();
        const missing = mine.filter((m) => !have.has(m));
        if (missing.length && !(await native('permissions.request', [missing]))) return false;
      }
      return theirs.length || origins.length ? request({ permissions: theirs, origins }) : true;
    }),
  );
  put(p, 'getAll', (callback?: Callback) => {
    const pr = (async () => {
      const all = await getAll();
      const have = await granted();
      return {
        ...all,
        permissions: [
          ...new Set([...(all.permissions || []), ...[...have].filter((m) => MOTE_PERMISSIONS.has(m))]),
        ],
      };
    })();
    if (typeof callback !== 'function') return pr;
    pr.then(
      (v) => callback(v),
      (e) => shim.withLastError(e, callback),
    );
    return undefined;
  });
  put(
    p,
    'remove',
    withCb(async ({ permissions = [], origins = [] }) => {
      const { theirs, mine } = splitPermissions(permissions);
      if (mine.length) await native('permissions.remove', [mine]);
      return theirs.length || origins.length ? remove({ permissions: theirs, origins }) : true;
    }),
  );
}
