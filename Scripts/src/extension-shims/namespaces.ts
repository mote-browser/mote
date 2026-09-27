// Whole namespaces WebKit lacks, answered by the browser: each method is a
// native request named `namespace.method` (ExtensionShims.run in Swift).

import { nativeCall, refuse } from './callbacks';
import { createEvent, rethrowLater, type ShimEvent } from './events';
import type { Shim } from './types';

/** A namespace the shim defines: its methods go to the browser, its events are the shim's. */
export interface NamespaceSpec {
  name: string;
  methods: readonly string[];
  events?: readonly string[];
  /** Constants and local methods, set first. */
  extra?: Record<string, unknown>;
}

/** A namespace as `defineNamespace` makes it. */
export type DefinedNamespace = Record<
  string,
  ((...args: unknown[]) => Promise<unknown> | undefined) | ShimEvent
>;

/** The namespaces answered by the browser, in the order they are defined. */
export function browserNamespaces(runtime: { id: string }): NamespaceSpec[] {
  return [
    {
      name: 'bookmarks',
      methods: [
        'get',
        'getChildren',
        'getRecent',
        'getSubTree',
        'getTree',
        'search',
        'create',
        'move',
        'update',
        'remove',
        'removeTree',
      ],
      events: [
        'onCreated',
        'onRemoved',
        'onChanged',
        'onMoved',
        'onChildrenReordered',
        'onImportBegan',
        'onImportEnded',
      ],
    },
    {
      name: 'history',
      methods: ['search', 'getVisits', 'addUrl', 'deleteUrl', 'deleteRange', 'deleteAll'],
      events: ['onVisited', 'onVisitRemoved'],
    },
    {
      name: 'downloads',
      methods: [
        'download',
        'search',
        'pause',
        'resume',
        'cancel',
        'open',
        'show',
        'showDefaultFolder',
        'erase',
        'removeFile',
        'getFileIcon',
      ],
      events: ['onCreated', 'onChanged', 'onErased', 'onDeterminingFilename'],
    },
    {
      name: 'sidePanel',
      methods: ['open', 'setOptions', 'getOptions', 'setPanelBehavior', 'getPanelBehavior'],
    },
    {
      name: 'offscreen',
      methods: ['createDocument', 'closeDocument', 'hasDocument'],
      extra: { Reason: new Proxy({}, { get: (_, key) => String(key) }) },
    },
    {
      name: 'tabGroups',
      methods: ['get', 'query', 'update', 'move'],
      events: ['onCreated', 'onRemoved', 'onUpdated', 'onMoved'],
      extra: { TAB_GROUP_ID_NONE: -1 },
    },
    {
      name: 'fontSettings',
      methods: [
        'getFontList',
        'getFont',
        'setFont',
        'clearFont',
        'getDefaultFontSize',
        'setDefaultFontSize',
        'clearDefaultFontSize',
        'getDefaultFixedFontSize',
        'setDefaultFixedFontSize',
        'clearDefaultFixedFontSize',
        'getMinimumFontSize',
        'setMinimumFontSize',
        'clearMinimumFontSize',
      ],
      events: [
        'onFontChanged',
        'onDefaultFontSizeChanged',
        'onDefaultFixedFontSizeChanged',
        'onMinimumFontSizeChanged',
      ],
    },
    {
      name: 'management',
      methods: ['getSelf', 'getAll', 'get', 'setEnabled', 'uninstallSelf'],
      events: ['onInstalled', 'onUninstalled', 'onEnabled', 'onDisabled'],
    },
    {
      name: 'notifications',
      methods: ['create', 'update', 'clear', 'getAll', 'getPermissionLevel'],
      events: ['onClicked', 'onClosed', 'onButtonClicked', 'onPermissionLevelChanged', 'onShowSettings'],
    },
    {
      name: 'tts',
      methods: ['speak', 'stop', 'pause', 'resume', 'isSpeaking', 'getVoices'],
      events: ['onVoicesChanged'],
    },
    {
      name: 'identity',
      methods: [
        'launchWebAuthFlow',
        'getAuthToken',
        'getProfileUserInfo',
        'removeCachedAuthToken',
        'clearAllCachedAuthTokens',
      ],
      events: ['onSignInChanged'],
      extra: {
        getRedirectURL: (path = '') =>
          'https://' + runtime.id + '.chromiumapp.org/' + String(path).replace(/^\//, ''),
      },
    },
    { name: 'search', methods: ['query'] },
    {
      name: 'idle',
      methods: ['queryState', 'getAutoLockDelay'],
      extra: { IdleState: { ACTIVE: 'active', IDLE: 'idle', LOCKED: 'locked' } },
    },
    { name: 'power', methods: ['requestKeepAwake', 'releaseKeepAwake', 'reportActivity'] },
    {
      name: 'browsingData',
      methods: [
        'remove',
        'removeAppcache',
        'removeCache',
        'removeCacheStorage',
        'removeCookies',
        'removeDownloads',
        'removeFileSystems',
        'removeFormData',
        'removeHistory',
        'removeIndexedDB',
        'removeLocalStorage',
        'removePasswords',
        'removeServiceWorkers',
        'removeWebSQL',
        'settings',
      ],
    },
    {
      name: 'sessions',
      methods: ['getRecentlyClosed', 'getDevices', 'restore'],
      events: ['onChanged'],
      extra: { MAX_SESSION_RESULTS: 25 },
    },
    { name: 'topSites', methods: ['get'] },
    {
      name: 'readingList',
      methods: ['query', 'addEntry', 'removeEntry', 'updateEntry'],
      events: ['onEntryAdded', 'onEntryRemoved', 'onEntryUpdated'],
    },
  ];
}

/** Sets a whole namespace on `chrome`, and on `browser` when that is another object, unless it is there. */
export function putNamespace({ root, chrome, put }: Shim, name: string, api: object): void {
  if (chrome[name]) return;
  put(chrome, name, api);
  if (root.browser && root.browser !== chrome && !root.browser[name]) put(root.browser, name, api);
}

export function defineNamespace(shim: Shim, { name, methods, events = [], extra = {} }: NamespaceSpec): void {
  if (shim.chrome[name]) return;
  const api: DefinedNamespace = Object.assign({}, extra) as DefinedNamespace;
  for (const method of methods) api[method] = nativeCall(shim, name + '.' + method);
  for (const event of events) api[event] = createEvent();
  putNamespace(shim, name, api);
}

export function defineBrowserNamespaces(shim: Shim): void {
  for (const spec of browserNamespaces(shim.runtime)) defineNamespace(shim, spec);
}

/**
 * idle.onStateChanged, asked every so often while anyone listens, the way
 * Chrome notices on its own.
 */
export function addIdleStateEvent({ chrome, put, native }: Shim): void {
  if (!chrome.idle || chrome.idle.onStateChanged) return;
  const changed = createEvent();
  const add = changed.addListener;
  let every = 60;
  let state = 'active';
  let timer: ReturnType<typeof setInterval> | null = null;
  changed.addListener = (f) => {
    add(f);
    if (timer) return;
    timer = setInterval(
      () =>
        native('idle.queryState', [every])
          .then((now) => {
            if (now === state) return;
            state = now;
            for (const g of changed.listeners) {
              try {
                g(now);
              } catch (e) {
                rethrowLater(e);
              }
            }
          })
          .catch(() => {}),
      15000,
    );
  };
  put(chrome.idle, 'onStateChanged', changed);
  put(chrome.idle, 'setDetectionInterval', (seconds: unknown) => {
    every = Math.max(15, Number(seconds) || 60);
  });
}

export function defineSystem(shim: Shim): void {
  const call = (api: string) => nativeCall(shim, api);
  putNamespace(shim, 'system', {
    cpu: { getInfo: call('system.cpu.getInfo') },
    memory: { getInfo: call('system.memory.getInfo') },
    storage: {
      getInfo: call('system.storage.getInfo'),
      ejectDevice: refuse(shim, 'system.storage.ejectDevice'),
      getAvailableCapacity: refuse(shim, 'system.storage.getAvailableCapacity'),
      onAttached: createEvent(),
      onDetached: createEvent(),
    },
    display: { getInfo: call('system.display.getInfo'), onDisplayChanged: createEvent() },
  });
}

/** Members of namespaces WebKit has, answered by the browser. */
export function addBrowserMembers(shim: Shim): void {
  const { chrome, runtime, put } = shim;
  if (chrome.i18n && !chrome.i18n.detectLanguage)
    put(chrome.i18n, 'detectLanguage', nativeCall(shim, 'i18n.detectLanguage'));
  if (runtime && !runtime.getContexts) put(runtime, 'getContexts', nativeCall(shim, 'runtime.getContexts'));
}
