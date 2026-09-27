// chrome.contextMenus and chrome.menus.

import { enumOf, fill } from './members';
import type { Shim } from './types';

export function fillMenus(shim: Shim): void {
  const contextTypes = enumOf(
    'all',
    'page',
    'frame',
    'selection',
    'link',
    'editable',
    'image',
    'video',
    'audio',
    'launcher',
    'browser_action',
    'page_action',
    'action',
  );
  fill(shim, 'contextMenus', {
    ContextType: contextTypes,
    ItemType: enumOf('normal', 'checkbox', 'radio', 'separator'),
  });
  fill(shim, 'menus', {
    ContextType: contextTypes,
    ItemType: enumOf('normal', 'checkbox', 'radio', 'separator'),
  });
}

/** A menu entry's properties, as far as the shim reads them. */
export interface MenuProperties {
  contexts?: string[];
  [key: string]: unknown;
}

/**
 * Context menu entries for places Mote has no menu for — the old
 * toolbar button contexts are the button's menu now, and there is no
 * app launcher at all.
 */
export function mendMenuProperties<P extends MenuProperties | null | undefined>(props: P): P {
  if (!props || !Array.isArray(props.contexts)) return props;
  const contexts = [
    ...new Set(
      props.contexts
        .map((c) => (c === 'browser_action' || c === 'page_action' ? 'action' : c))
        .filter((c) => c !== 'launcher'),
    ),
  ];
  return { ...props, contexts: contexts.length ? contexts : ['page'] };
}

export function mendMenus({ chrome, put }: Shim): void {
  for (const name of ['contextMenus', 'menus']) {
    const menus = chrome[name];
    if (!menus || typeof menus.create !== 'function') continue;
    const create = menus.create.bind(menus);
    put(menus, 'create', (props: MenuProperties, callback?: unknown) =>
      create(mendMenuProperties(props), callback),
    );
    // A WebKit without update still gets create mended, and the rest of the shim.
    if (typeof menus.update !== 'function') continue;
    const update = menus.update.bind(menus);
    put(menus, 'update', (id: unknown, props: MenuProperties, callback?: unknown) =>
      update(id, mendMenuProperties(props), callback),
    );
  }
}
