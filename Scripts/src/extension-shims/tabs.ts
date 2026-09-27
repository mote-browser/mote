// chrome.tabs and chrome.windows as Chrome has them.

import { refuse, resolved, takeCallback, withCallback } from './callbacks';
import { createEvent, type Listener } from './events';
import { enumOf, fill } from './members';
import type { Callback, Shim, WebKitObject } from './types';

/** A tab as WebKit and Chrome describe it, as far as the shim reads it. */
export interface Tab {
  id: number;
  index: number;
  url?: string;
  title?: string;
  groupId?: number;
}

/** What the browser tells of a tab by its index (`tabs.describe`). */
export interface TabDescription {
  url?: string;
  title?: string;
}

export function fillTabs(shim: Shim): void {
  const { chrome } = shim;
  fill(shim, 'tabs', {
    TabStatus: enumOf('unloaded', 'loading', 'complete'),
    MutedInfoReason: enumOf('user', 'capture', 'extension'),
    WindowType: enumOf('normal', 'popup', 'panel', 'app', 'devtools'),
    ZoomSettingsMode: enumOf('automatic', 'manual', 'disabled'),
    ZoomSettingsScope: { PER_ORIGIN: 'per-origin', PER_TAB: 'per-tab' },
    MAX_CAPTURE_VISIBLE_TAB_CALLS_PER_SECOND: 2,
    TAB_INDEX_NONE: -1,
    getZoomSettings: resolved({ mode: 'automatic', scope: 'per-origin', defaultZoomFactor: 1 }),
    setZoomSettings: resolved(undefined),
    onZoomChange: createEvent(),
    onSelectionChanged: createEvent(),
    onActiveChanged: createEvent(),
    onHighlightChanged: createEvent(),
    group: refuse(shim, 'tabs.group'),
    ungroup: resolved(undefined),
    getSelected: (windowId: unknown, callback?: Callback) => {
      const f = typeof windowId === 'function' ? (windowId as Callback) : callback;
      chrome.tabs.query({ active: true, currentWindow: true }).then((t: Tab[]) => f && f(t[0]));
    },
    getAllInWindow: (windowId: unknown, callback?: Callback) => {
      const f = typeof windowId === 'function' ? (windowId as Callback) : callback;
      chrome.tabs.query({ currentWindow: true }).then((t: Tab[]) => f && f(t));
    },
  });
}

/** A moment for the browser to settle a tab it moved. */
function settle(): Promise<unknown> {
  return new Promise((r) => setTimeout(r, 60));
}

/**
 * Moving, sleeping and bringing forward tabs, by where they are in
 * the row — the one thing both sides agree on.
 */
export function fillTabsByIndex(shim: Shim): void {
  const { chrome, native } = shim;
  if (!chrome.tabs) return;
  const byIndex =
    (api: string) =>
    async (ids: number | number[], extra?: unknown): Promise<Tab | Tab[]> => {
      const out: Tab[] = [];
      for (const id of Array.isArray(ids) ? ids : [ids]) {
        const tab: Tab = await chrome.tabs.get(id);
        await native(api, [tab.index, extra]);
        await settle();
        out.push(await chrome.tabs.get(id).catch(() => tab));
      }
      return Array.isArray(ids) ? out : out[0]!;
    };
  fill(shim, 'tabs', {
    move: withCallback(shim, async (ids: number | number[], props: { index?: number } = {}) => {
      const list = Array.isArray(ids) ? ids : [ids];
      const out = [];
      let at = props.index ?? -1;
      for (const id of list) {
        out.push(await byIndex('tabs.move')(id, at));
        if (at !== -1) at++;
      }
      return Array.isArray(ids) ? out : out[0];
    }),
    discard: withCallback(shim, (id?: number) =>
      id === undefined
        ? chrome.tabs
            .query({ active: false, currentWindow: true })
            .then((t: Tab[]) => t[0] && byIndex('tabs.discard')(t[0].id))
        : byIndex('tabs.discard')(id),
    ),
    highlight: withCallback(shim, async (info: { tabs?: number | number[] } = {}) => {
      const first = Array.isArray(info.tabs) ? info.tabs[0] : info.tabs;
      await native('tabs.activate', [first]);
      await settle();
      return chrome.windows ? chrome.windows.getCurrent({ populate: true }) : undefined;
    }),
  });
}

/** The namespace whose method answered: tabs answers tabs, windows answers windows. */
export type TabSource = 'tabs' | 'windows';

/**
 * Every tab in what a method of `from` answers: a tab or tabs from
 * tabs, a window or windows — each with its tabs, when populated —
 * from windows. A window is never taken for a tab.
 */
export function tabsIn(value: unknown, from: TabSource): Tab[] {
  if (Array.isArray(value)) return value.flatMap((v) => tabsIn(v, from));
  if (from === 'tabs') return isTab(value) ? [value] : [];
  const tabs = value && typeof value === 'object' ? (value as { tabs?: unknown }).tabs : undefined;
  return Array.isArray(tabs) ? tabs.filter(isTab) : [];
}

/**
 * A tab, by its shape: an id, and where it is — its index and its
 * window, which a window has neither of.
 */
function isTab(t: unknown): t is Tab {
  if (!t || typeof t !== 'object') return false;
  const { id, index, windowId } = t as Tab & { windowId?: unknown };
  return typeof id === 'number' && (typeof index === 'number' || typeof windowId === 'number');
}

/**
 * Tabs as Chrome describes them. Every tab has a groupId (-1 when in
 * no group — Mote has none), which code tests before anything else;
 * and with the "tabs" permission an extension sees every tab's address
 * and title, where WebKit shows them only for sites it has host
 * access to.
 */
export function describeTabs(shim: Shim): void {
  const { chrome, runtime, put, native } = shim;
  if (!chrome.tabs) return;
  const seesTabs = (() => {
    try {
      return (runtime.getManifest().permissions || []).includes('tabs');
    } catch {
      return false;
    }
  })();
  // Mends in place; a promise only when the browser has to be asked.
  const mend = (list: unknown[]): Promise<void> | null => {
    const tabs = list.filter(isTab);
    for (const t of tabs) {
      if (t.groupId === undefined) {
        try {
          t.groupId = -1;
        } catch {}
      }
    }
    const blind = seesTabs ? tabs.filter((t) => !t.url && t.index >= 0) : [];
    if (!blind.length) return null;
    return native('tabs.describe', [blind.map((t) => t.index)]).then(
      (info: (TabDescription | null)[] | null) => {
        blind.forEach((t, i) => {
          const d = info && info[i];
          if (!d) return;
          try {
            if (d.url) t.url = d.url;
            if (d.title && !t.title) t.title = d.title;
          } catch {}
        });
      },
      () => {},
    );
  };
  const mendResult = (from: TabSource, name: string): void => {
    const target = chrome[from];
    if (!target || typeof target[name] !== 'function') return;
    const original = target[name].bind(target);
    put(target, name, (...args: unknown[]) => {
      const callback = takeCallback(args);
      const p = Promise.resolve(original(...args)).then(async (r) => {
        await mend(tabsIn(r, from));
        return r;
      });
      if (!callback) return p;
      p.then(
        (r) => callback(r),
        (e) => shim.withLastError(e, callback),
      );
      return undefined;
    });
  };
  for (const name of ['query', 'get', 'getCurrent', 'create', 'update', 'duplicate', 'move', 'reload']) {
    mendResult('tabs', name);
  }
  for (const name of ['get', 'getAll', 'getCurrent', 'getLastFocused', 'create']) mendResult('windows', name);
  // Listeners given a tab: the tab is mended before they see it.
  const mendArgs = (target: WebKitObject, positions: number[]): void => {
    if (!target || typeof target.addListener !== 'function') return;
    const add = target.addListener.bind(target);
    const remove = target.removeListener.bind(target);
    const wrapped = new Map<Listener, Listener>();
    put(target, 'addListener', (listener: Listener, ...rest: unknown[]) => {
      const w = function (this: unknown, ...args: unknown[]) {
        const pending = mend(positions.map((i) => args[i]));
        if (!pending) return listener.apply(this, args);
        pending.then(() => listener.apply(this, args));
        return undefined;
      };
      wrapped.set(listener, w);
      return add(w, ...rest);
    });
    put(target, 'removeListener', (listener: Listener) => {
      const w = wrapped.get(listener);
      wrapped.delete(listener);
      return remove(w || listener);
    });
    put(target, 'hasListener', (listener: Listener) => wrapped.has(listener));
  };
  mendArgs(chrome.tabs.onCreated, [0]);
  mendArgs(chrome.tabs.onUpdated, [2]);
  mendArgs(chrome.action && chrome.action.onClicked, [0]);
  mendArgs(chrome.contextMenus && chrome.contextMenus.onClicked, [1]);
  mendArgs(chrome.menus && chrome.menus.onClicked, [1]);
  mendArgs(chrome.commands && chrome.commands.onCommand, [1]);
}
