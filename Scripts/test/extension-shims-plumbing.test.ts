import { describe, expect, it, vi } from 'vitest';
import { nativeCall, refuse } from '../src/extension-shims/callbacks';
import { createHolder, lastErrorReporter } from '../src/extension-shims/holding';
import { mendMenus } from '../src/extension-shims/menus';
import { createVerdicts } from '../src/extension-shims/message-verdicts';
import { createGather } from '../src/extension-shims/messaging';
import { browserNamespaces, defineNamespace } from '../src/extension-shims/namespaces';
import { numberOwnPorts } from '../src/extension-shims/port-numbering';
import { setting } from '../src/extension-shims/settings';
import { describeTabs } from '../src/extension-shims/tabs';
import type { Shim } from '../src/extension-shims/types';

/** A shim over plain objects: its browser answers `answers[api]`, or null. */
function fakeShim(
  answers: Record<string, { value?: unknown; error?: string }> = {},
  overrides: Partial<Shim> = {},
) {
  const root: Record<string, any> = {};
  const runtime: Record<string, any> = { id: 'abc' };
  const chrome: Record<string, any> = { runtime };
  const { kept, put } = createHolder(root as Shim['root']);
  const native = vi.fn((api: string, _args: unknown[]) => {
    const answer = answers[api] ?? { value: null };
    return answer.error ? Promise.reject(new Error(answer.error)) : Promise.resolve(answer.value);
  });
  const shim: Shim = {
    root: root as Shim['root'],
    config: { events: [], scripts: [], chromeVersion: '140.0.0.0', verbose: false },
    chrome,
    runtime,
    inContent: false,
    embedded: false,
    worker: false,
    background: false,
    spaces: new Set(),
    kept,
    put,
    native,
    withLastError: lastErrorReporter(runtime, put),
    ...overrides,
  };
  return { shim, chrome, runtime, native };
}

describe('Namespaces answered by the browser', () => {
  it('sends each method as namespace.method, and fires its own events', async () => {
    const { shim, chrome, native } = fakeShim({ 'bookmarks.getTree': { value: [{ id: '0' }] } });
    const spec = browserNamespaces(shim.runtime).find((s) => s.name === 'bookmarks')!;
    defineNamespace(shim, spec);
    expect(await chrome.bookmarks.getTree()).toEqual([{ id: '0' }]);
    expect(native).toHaveBeenCalledWith('bookmarks.getTree', []);
    const listener = vi.fn();
    chrome.bookmarks.onCreated.addListener(listener);
    for (const f of chrome.bookmarks.onCreated.listeners) f('1', { title: 'x' });
    expect(listener).toHaveBeenCalledWith('1', { title: 'x' });
  });

  it('keeps a namespace WebKit has', () => {
    const { shim, chrome } = fakeShim();
    const own = { getTree: () => 'WebKit' };
    chrome.bookmarks = own;
    defineNamespace(shim, { name: 'bookmarks', methods: ['getTree'] });
    expect(chrome.bookmarks).toBe(own);
  });

  it('defines it on a separate `browser` too', () => {
    const { shim, chrome } = fakeShim();
    shim.root.browser = { runtime: chrome.runtime };
    defineNamespace(shim, { name: 'tts', methods: ['speak'] });
    expect(shim.root.browser.tts).toBe(chrome.tts);
  });

  it('calls a callback with the value, or with lastError set while it runs', async () => {
    const { shim, runtime } = fakeShim({
      'history.search': { value: [] },
      'history.deleteAll': { error: 'nope' },
    });
    const search = nativeCall(shim, 'history.search');
    expect(await new Promise((r) => search({ text: '' }, r))).toEqual([]);
    const deleteAll = nativeCall(shim, 'history.deleteAll');
    const seen = await new Promise((r) => deleteAll(() => r(runtime.lastError)));
    expect(seen).toEqual({ message: 'nope' });
    expect(runtime.lastError).toBeUndefined();
  });

  it('refuses what only Chrome can do', async () => {
    const { shim, runtime } = fakeShim();
    await expect(refuse(shim, 'gcm.register')()).rejects.toThrow("gcm.register isn't available in Mote");
    let message: unknown;
    refuse(shim, 'gcm.register')(() => (message = runtime.lastError.message));
    expect(message).toBe("gcm.register isn't available in Mote");
  });

  it('asks for settings by name', async () => {
    const { shim, native } = fakeShim({
      'setting.get:privacy.services.passwordSavingEnabled': { value: { value: false } },
    });
    const saving = setting(shim, 'privacy.services.passwordSavingEnabled');
    expect(await saving.get({})).toEqual({ value: false });
    expect(native).toHaveBeenCalledWith('setting.get:privacy.services.passwordSavingEnabled', [{}]);
  });

  it("builds sign-in redirect addresses from the extension's id", () => {
    const { shim } = fakeShim();
    const identity = browserNamespaces(shim.runtime).find((s) => s.name === 'identity')!;
    const redirect = identity.extra!.getRedirectURL as (path?: string) => string;
    expect(redirect('/cb')).toBe('https://abc.chromiumapp.org/cb');
  });
});

/** WebKit's event: each listener's return is an answer. */
function webkitEvent() {
  const listeners = new Set<(...args: any[]) => unknown>();
  return {
    addListener: (f: (...args: any[]) => unknown) => listeners.add(f),
    removeListener: (f: (...args: any[]) => unknown) => listeners.delete(f),
    deliver: (message: unknown, respond: (value: unknown) => void) =>
      [...listeners].map((f) => f(message, { id: 'abc' }, respond)),
  };
}

/** WebKit's onMessage with the shim's listeners gathered behind it. */
function gathered(background: boolean) {
  const { shim } = fakeShim({}, { background });
  const event = webkitEvent();
  const gather = createGather(shim, createVerdicts(shim));
  gather(event, true);
  return event as ReturnType<typeof webkitEvent> & Record<string, any>;
}

describe('Gathered onMessage listeners', () => {
  it('waits for whichever listener answers, as Chrome does', async () => {
    const event = gathered(true);
    event.addListener(() => undefined);
    event.addListener((_m: unknown, _s: unknown, respond: (v: unknown) => void) => {
      setTimeout(() => respond('late answer'));
      return true;
    });
    const answer = await new Promise((respond) => {
      expect(event.deliver({ hi: 1 }, respond)).toEqual([true]);
    });
    expect(answer).toBe('late answer');
  });

  it('takes a promise as the answer', async () => {
    const event = gathered(true);
    event.addListener(async () => 'from a promise');
    expect(await new Promise((respond) => event.deliver({ hi: 1 }, respond))).toBe('from a promise');
  });

  it('answers only the first response', () => {
    const event = gathered(true);
    event.addListener((_m: unknown, _s: unknown, respond: (v: unknown) => void) => respond(1));
    event.addListener((_m: unknown, _s: unknown, respond: (v: unknown) => void) => respond(2));
    const respond = vi.fn();
    expect(event.deliver({}, respond)).toEqual([undefined]);
    expect(respond).toHaveBeenCalledTimes(1);
    expect(respond).toHaveBeenCalledWith(1);
  });

  it("answers the worker's ping in the background only", () => {
    const respond = vi.fn();
    expect(gathered(true).deliver({ __motePing: true }, respond)).toEqual([undefined]);
    expect(respond).toHaveBeenCalledWith('pong');
  });

  it('listens once a page adds a listener, and keeps count of its own', () => {
    const event = gathered(false);
    expect(event.deliver({}, vi.fn())).toEqual([]);
    const listener = vi.fn();
    event.addListener(listener);
    expect(event.hasListener(listener)).toBe(true);
    expect(event.hasListeners()).toBe(true);
    event.removeListener(listener);
    expect(event.hasListeners()).toBe(false);
  });
});

/** A tab as WebKit gives it, and a window with its tabs (`populate`). */
const aTab = () => ({ id: 7, index: 0, windowId: 1, active: true });
const aWindow = () => ({ id: 1, focused: true, state: 'normal', tabs: [aTab()] });

describe('Tabs and windows', () => {
  it('gives tabs a groupId, and leaves windows as they are', async () => {
    const { shim, chrome, runtime } = fakeShim();
    runtime.getManifest = () => ({ permissions: [] });
    chrome.tabs = { query: async () => [aTab()], get: async () => aTab() };
    chrome.windows = { get: async () => aWindow(), getAll: async () => [aWindow()] };
    describeTabs(shim);
    expect((await chrome.tabs.get(7)).groupId).toBe(-1);
    const [all] = await chrome.windows.getAll({ populate: true });
    expect(all).not.toHaveProperty('groupId');
    expect(all.tabs[0].groupId).toBe(-1);
    const one = await new Promise<any>((r) => chrome.windows.get(1, { populate: true }, r));
    expect(one).not.toHaveProperty('groupId');
    expect(one.tabs[0].groupId).toBe(-1);
  });
});

describe('Menus', () => {
  it('mends create even where WebKit has no update', () => {
    const { shim, chrome } = fakeShim();
    const created: unknown[] = [];
    chrome.contextMenus = { create: (props: unknown) => created.push(props) };
    expect(() => mendMenus(shim)).not.toThrow();
    chrome.contextMenus.create({ id: 'm', contexts: ['launcher'] });
    expect(created).toEqual([{ id: 'm', contexts: ['page'] }]);
    expect(chrome.contextMenus.update).toBeUndefined();
  });
});

describe('Internal ids', () => {
  it("are unique whatever Math.random answers, for a page's verdicts", () => {
    const random = vi.spyOn(Math, 'random').mockReturnValue(0.5);
    try {
      const a = createVerdicts(fakeShim().shim);
      const b = createVerdicts(fakeShim().shim);
      a.channel?.close();
      b.channel?.close();
      expect(typeof a.me).toBe('string');
      expect(a.me).not.toBe('');
      expect(a.me).not.toBe(b.me);
    } finally {
      random.mockRestore();
    }
  });

  it('are unique whatever Math.random answers, for numbered ports', () => {
    const random = vi.spyOn(Math, 'random').mockReturnValue(0.5);
    try {
      const { shim, runtime } = fakeShim();
      const posted: any[] = [];
      runtime.getURL = (path: string) => 'chrome-extension://abc/' + path;
      runtime.onConnect = { addListener() {}, removeListener() {}, hasListener: () => false };
      runtime.connect = () => ({
        onMessage: { addListener() {} },
        postMessage: (m: unknown) => posted.push(m),
      });
      numberOwnPorts(shim);
      // Extension ports take no target origin.
      // oxlint-disable-next-line unicorn/require-post-message-target-origin
      runtime.connect().postMessage('a');
      // oxlint-disable-next-line unicorn/require-post-message-target-origin
      runtime.connect().postMessage('b');
      const [first, second] = posted.map((m) => m.__motePort[0]);
      expect(typeof first).toBe('string');
      expect(first).not.toBe('');
      expect(first).not.toBe(second);
    } finally {
      random.mockRestore();
    }
  });
});
