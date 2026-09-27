// Members Chrome has on the namespaces WebKit has too, that WebKit
// leaves out. Plenty are read at the top of a worker — an enum, an
// event to listen to — where one missing member is a TypeError that
// stops the whole worker before it has done anything.

import { refuse, resolved } from './callbacks';
import { createEvent } from './events';
import type { Callback, Shim } from './types';

/** Sets each member `chrome[name]` doesn't have. */
export function fill({ chrome, put }: Shim, name: string, members: Record<string, unknown>): void {
  const target = chrome[name];
  if (!target) return;
  for (const [key, value] of Object.entries(members)) {
    let there;
    try {
      there = target[key];
    } catch {}
    if (there === undefined) put(target, key, value);
  }
}

/**
 * Chrome's enum of `values`: `main_frame` as `MAIN_FRAME`, `per-origin` as
 * `PER_ORIGIN`, `firstParty` as `FIRST_PARTY`. Words are split before the
 * value is upper-cased, which would leave no lower case to split at.
 */
export function enumOf(...values: string[]): Record<string, string> {
  return Object.fromEntries(
    values.map((v) => [
      v
        .replace(/[-.]/g, '_')
        .replace(/([a-z0-9])([A-Z])/g, '$1_$2')
        .toUpperCase(),
      v,
    ]),
  );
}

/** The resource types of web requests, shared by webRequest and declarativeNetRequest. */
export function resourceTypes(): Record<string, string> {
  return enumOf(
    'main_frame',
    'sub_frame',
    'stylesheet',
    'script',
    'image',
    'font',
    'object',
    'xmlhttprequest',
    'ping',
    'csp_report',
    'media',
    'websocket',
    'webtransport',
    'webbundle',
    'other',
  );
}

export function fillRuntime(shim: Shim): void {
  fill(shim, 'runtime', {
    onUpdateAvailable: createEvent(),
    onRestartRequired: createEvent(),
    onSuspend: createEvent(),
    onSuspendCanceled: createEvent(),
    onBrowserUpdateAvailable: createEvent(),
    onConnectNative: createEvent(),
    onUserScriptConnect: createEvent(),
    onUserScriptMessage: createEvent(),
    requestUpdateCheck: (callback?: Callback) => {
      if (typeof callback === 'function') {
        setTimeout(() => callback('no_update', {}));
        return undefined;
      }
      return Promise.resolve({ status: 'no_update' });
    },
    restart: () => {},
    restartAfterDelay: resolved(undefined),
    getPackageDirectoryEntry: refuse(shim, 'runtime.getPackageDirectoryEntry'),
    OnInstalledReason: enumOf('install', 'update', 'chrome_update', 'shared_module_update'),
    OnRestartRequiredReason: enumOf('app_update', 'os_update', 'periodic'),
    PlatformArch: {
      ARM: 'arm',
      ARM64: 'arm64',
      X86_32: 'x86-32',
      X86_64: 'x86-64',
      MIPS: 'mips',
      MIPS64: 'mips64',
    },
    PlatformNaclArch: { ARM: 'arm', X86_32: 'x86-32', X86_64: 'x86-64', MIPS: 'mips', MIPS64: 'mips64' },
    PlatformOs: {
      MAC: 'mac',
      WIN: 'win',
      ANDROID: 'android',
      CROS: 'cros',
      LINUX: 'linux',
      OPENBSD: 'openbsd',
      FUCHSIA: 'fuchsia',
    },
    RequestUpdateCheckStatus: enumOf('throttled', 'no_update', 'update_available'),
    ContextType: {
      TAB: 'TAB',
      POPUP: 'POPUP',
      BACKGROUND: 'BACKGROUND',
      OFFSCREEN_DOCUMENT: 'OFFSCREEN_DOCUMENT',
      SIDE_PANEL: 'SIDE_PANEL',
      DEVELOPER_TOOLS: 'DEVELOPER_TOOLS',
    },
  });
}

export function fillExtension(shim: Shim): void {
  const { runtime } = shim;
  fill(shim, 'extension', {
    getURL: (path: string) => runtime.getURL(path),
    ViewType: { TAB: 'tab', POPUP: 'popup' },
    sendRequest: (...args: unknown[]) => runtime.sendMessage(...args),
    onRequest: createEvent(),
    onRequestExternal: createEvent(),
    getExtensionTabs: () => [],
    setUpdateUrlData: () => {},
  });
}

export function fillWindows(shim: Shim): void {
  fill(shim, 'windows', {
    // Chrome's, and not WebKit's: an extension subscribing to it at
    // start — Session Buddy, inside a try — threw there and never
    // reached the rest, its button's listener included. Never fired:
    // a window's bounds are read when they are asked for.
    onBoundsChanged: createEvent(),
    CreateType: enumOf('normal', 'popup', 'panel'),
    WindowType: enumOf('normal', 'popup', 'panel', 'app', 'devtools'),
    WindowState: {
      NORMAL: 'normal',
      MINIMIZED: 'minimized',
      MAXIMIZED: 'maximized',
      FULLSCREEN: 'fullscreen',
      LOCKED_FULLSCREEN: 'locked-fullscreen',
    },
  });
}

export function fillScripting(shim: Shim): void {
  fill(shim, 'scripting', {
    ExecutionWorld: { ISOLATED: 'ISOLATED', MAIN: 'MAIN', USER_SCRIPT: 'USER_SCRIPT' },
    StyleOrigin: { AUTHOR: 'AUTHOR', USER: 'USER' },
  });
}

export function fillWebNavigation(shim: Shim): void {
  fill(shim, 'webNavigation', {
    onCreatedNavigationTarget: createEvent(),
    onHistoryStateUpdated: createEvent(),
    onReferenceFragmentUpdated: createEvent(),
    onTabReplaced: createEvent(),
    TransitionType: enumOf(
      'link',
      'typed',
      'auto_bookmark',
      'auto_subframe',
      'manual_subframe',
      'generated',
      'start_page',
      'form_submit',
      'reload',
      'keyword',
      'keyword_generated',
    ),
    TransitionQualifier: enumOf('client_redirect', 'server_redirect', 'forward_back', 'from_address_bar'),
  });
}
