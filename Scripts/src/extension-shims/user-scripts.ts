// chrome.userScripts — what Tampermonkey, Violentmonkey and the
// advanced rules of the ad blockers run on — carried out through
// WebKit's registered content scripts. The browser writes each script
// into a file of the extension's (content scripts come from files),
// wrapped so the globs Chrome takes are honoured and, for Chrome's
// USER_SCRIPT world, so its messages reach onUserScriptMessage rather
// than the extension's own onMessage (see user-script.ts and
// ExtensionShims.userScriptFile). The list lives with the browser,
// and is registered again whenever the worker starts.

import { USER_SCRIPT_PORT_PREFIX } from '../lib/user-scripts';
import { takeCallback } from './callbacks';
import type { Listener } from './events';
import { putNamespace } from './namespaces';
import type { Shim, WebKitObject } from './types';

/** Mote's passkey patch (Passkeys.swift), written into every extension by `ExtensionShims.prepare`. */
export const PASSKEYS_FILE = 'mote-passkeys.js';

/** The ids under which user scripts are registered as content scripts. */
export const USER_SCRIPT_ID_PREFIX = 'mote-us-';

/** A content script to register, as far as the shim reads it. */
interface ContentScript {
  js?: string[];
  world?: string;
  [key: string]: unknown;
}

/**
 * What an extension registers for a page's own world has Mote's
 * passkey patch before it, as its manifest's do (see prepare): a
 * password manager keeps a reference to navigator.credentials as it
 * finds it, and falls back to that. An update that names no world gets
 * it too; in any other world the patch does nothing.
 */
export function withPasskeys(scripts: unknown, updating: boolean): unknown {
  if (!Array.isArray(scripts)) return scripts;
  return scripts.map((s: ContentScript | null) => {
    if (!s || !Array.isArray(s.js) || s.js.includes(PASSKEYS_FILE)) return s;
    const world = String(s.world || '').toUpperCase();
    return world === 'MAIN' || (updating && !world) ? { ...s, js: [PASSKEYS_FILE, ...s.js] } : s;
  });
}

export function patchPasskeysFirst({ chrome, put }: Shim): void {
  const scripting = chrome.scripting;
  if (!scripting) return;
  for (const name of ['registerContentScripts', 'updateContentScripts']) {
    const original = scripting[name];
    if (typeof original === 'function') {
      put(scripting, name, function (scripts: unknown, ...rest: unknown[]) {
        return original.call(scripting, withPasskeys(scripts, name === 'updateContentScripts'), ...rest);
      });
    }
  }
}

/** A user script as chrome.userScripts takes it, and as the browser keeps it. */
export interface RegisteredUserScript {
  id: string;
  matches?: string[];
  excludeMatches?: string[];
  includeGlobs?: string[];
  excludeGlobs?: string[];
  js?: ({ code: string } | { file: string })[];
  runAt?: string;
  allFrames?: boolean;
  world?: string;
  worldId?: string;
}

export interface UserScriptFilter {
  ids?: string[];
}

/** Scripts named by the filter, or all of them. */
export function pickScripts<S extends { id: string }>(filter: UserScriptFilter | undefined, list: S[]): S[] {
  return filter && Array.isArray(filter.ids) ? list.filter((s) => filter.ids!.includes(s.id)) : list;
}

export function defineUserScripts(shim: Shim): void {
  const { root, chrome, runtime, put, native, background } = shim;
  const scripting = chrome.scripting;
  const wantsUserScripts = (() => {
    try {
      return (runtime.getManifest().permissions || []).includes('userScripts');
    } catch {
      return false;
    }
  })();
  if (
    chrome.userScripts ||
    !wantsUserScripts ||
    !scripting ||
    typeof scripting.registerContentScripts !== 'function'
  ) {
    return;
  }
  const tag = USER_SCRIPT_ID_PREFIX;
  const content = async (script: RegisteredUserScript) => ({
    id: tag + script.id,
    matches: script.matches && script.matches.length ? script.matches : ['*://*/*'],
    excludeMatches: script.excludeMatches || [],
    js: [await native('userScripts.file', [script])],
    runAt: script.runAt || 'document_idle',
    allFrames: !!script.allFrames,
    world: script.world === 'MAIN' ? 'MAIN' : 'ISOLATED',
    persistAcrossSessions: false,
  });
  const registered = async (): Promise<{ id: string }[]> =>
    (await scripting.getRegisteredContentScripts()).filter((s: { id: string }) => s.id.startsWith(tag));
  const list = (): Promise<RegisteredUserScript[]> =>
    native('userScripts.list', []).then((l: RegisteredUserScript[] | null) => l || []);
  const save = (l: RegisteredUserScript[]) => native('userScripts.save', [l]);
  const sync = async (): Promise<void> => {
    const want = await list();
    const have = new Set((await registered()).map((s) => s.id));
    const missing = want.filter((s) => !have.has(tag + s.id));
    if (!missing.length) return;
    const scripts = await Promise.all(missing.map(content));
    // Two starts of the worker racing each other: the later one takes
    // the registration over.
    await scripting.registerContentScripts(scripts).catch(async (e: unknown) => {
      if (!/duplicate/i.test(String(e && (e as Error).message))) throw e;
      await scripting.unregisterContentScripts({ ids: scripts.map((s) => s.id) }).catch(() => {});
      await scripting.registerContentScripts(scripts);
    });
  };
  const api: Record<string, (...args: any[]) => Promise<unknown>> = {
    register: async (scripts: RegisteredUserScript[]) => {
      const l = await list();
      for (const s of scripts)
        if (l.some((o) => o.id === s.id)) throw new Error("Duplicate script id '" + s.id + "'");
      await scripting.registerContentScripts(await Promise.all(scripts.map(content)));
      await save([...l, ...scripts]);
    },
    update: async (scripts: RegisteredUserScript[]) => {
      const l = await list();
      const merged = scripts.map((s) => {
        const old = l.find((o) => o.id === s.id);
        if (!old) throw new Error("Script with id '" + s.id + "' does not exist");
        return { ...old, ...s };
      });
      await scripting.unregisterContentScripts({ ids: merged.map((s) => tag + s.id) }).catch(() => {});
      await scripting.registerContentScripts(await Promise.all(merged.map(content)));
      await save(l.map((o) => merged.find((m) => m.id === o.id) || o));
    },
    unregister: async (filter?: UserScriptFilter) => {
      const l = await list();
      const gone = pickScripts(filter, l);
      const ids = (await registered()).map((s) => s.id).filter((id) => gone.some((g) => tag + g.id === id));
      if (ids.length) await scripting.unregisterContentScripts({ ids });
      await save(l.filter((o) => !gone.includes(o)));
    },
    getScripts: async (filter?: UserScriptFilter) => pickScripts(filter, await list()),
    configureWorld: (properties?: object) => native('userScripts.world', [properties || {}]),
    getWorldConfigurations: () => native('userScripts.worlds', []),
    resetWorldConfiguration: (worldId?: string) => native('userScripts.world', [{ worldId, reset: true }]),
    execute: async (injection: WebKitObject) => {
      const file = await native('userScripts.file', [
        { id: 'execute-' + Date.now(), js: injection.js || [], world: injection.world },
      ]);
      return scripting.executeScript({
        target: injection.target,
        files: [file],
        world: injection.world === 'MAIN' ? 'MAIN' : 'ISOLATED',
        injectImmediately: !!injection.injectImmediately,
      });
    },
  };
  const callbacks = Object.fromEntries(
    Object.entries(api).map(([k, f]) => [
      k,
      (...args: unknown[]) => {
        const callback = takeCallback(args);
        const p = f(...args);
        if (!callback) return p;
        p.then(
          (v) => callback(v),
          (e) => shim.withLastError(e, callback),
        );
        return undefined;
      },
    ]),
  );
  putNamespace(shim, 'userScripts', {
    ...callbacks,
    ExecutionWorld: { MAIN: 'MAIN', USER_SCRIPT: 'USER_SCRIPT' },
  });
  if (background) {
    sync().catch((e) => {
      try {
        native('debug.error', ['userScripts: ' + e.message]).catch(() => {});
      } catch {}
    });
  }

  // Messages from the USER_SCRIPT world come tagged (see user-script.ts);
  // they go to onUserScriptMessage and onUserScriptConnect.
  const onMessage = runtime.onUserScriptMessage;
  const onConnect = runtime.onUserScriptConnect;
  // Read by the onMessage listener the shim gathers (see messaging.ts).
  root.__moteUserScriptMessage = (message: unknown, sender: unknown, respond: (value: unknown) => void) => {
    let keep = false;
    for (const f of [...(onMessage.listeners as Set<Listener>)]) {
      const r = f(message, sender, respond);
      if (r === true) keep = true;
      else if (r && typeof r.then === 'function') {
        keep = true;
        r.then(respond);
      }
    }
    return keep;
  };
  if (runtime.onConnect && typeof runtime.onConnect.addListener === 'function') {
    const marker = USER_SCRIPT_PORT_PREFIX;
    const add = runtime.onConnect.addListener.bind(runtime.onConnect);
    const remove = runtime.onConnect.removeListener.bind(runtime.onConnect);
    const wrapped = new Map<Listener, Listener>();
    try {
      add((port: WebKitObject) => {
        if (!String(port.name).startsWith(marker)) return;
        const view = Object.create(port, { name: { value: port.name.slice(marker.length) } });
        for (const f of [...(onConnect.listeners as Set<Listener>)]) f(view);
      });
    } catch {}
    put(runtime.onConnect, 'addListener', (listener: Listener) => {
      const w = (port: WebKitObject) => {
        if (!String(port.name).startsWith(marker)) return listener(port);
        return undefined;
      };
      wrapped.set(listener, w);
      return add(w);
    });
    put(runtime.onConnect, 'removeListener', (listener: Listener) => {
      const w = wrapped.get(listener);
      if (w) {
        wrapped.delete(listener);
        remove(w);
      }
    });
  }
}
