import { describe, expect, it, vi } from 'vitest';
import { nativeRequest, replyValue, takeCallback } from '../src/extension-shims/callbacks';
import { mendRule, refusedRuleIndex } from '../src/extension-shims/declarative-net-request';
import { carriedArguments } from '../src/extension-shims/embedded';
import { createEvent, isEventName, memberNames } from '../src/extension-shims/events';
import { isUnder } from '../src/extension-shims/file-system/loading';
import {
  fileSystemURL,
  parseFileSystemURL,
  segments,
  typeOf,
  PERSISTENT,
  TEMPORARY,
} from '../src/extension-shims/file-system/paths';
import { enumOf } from '../src/extension-shims/members';
import { mendMenuProperties } from '../src/extension-shims/menus';
import { messageKey, recordVerdict, type VerdictEntry } from '../src/extension-shims/message-verdicts';
import { goesToApp, isPortProbe } from '../src/extension-shims/native-ports';
import { splitPermissions } from '../src/extension-shims/permissions';
import { unnumber } from '../src/extension-shims/port-numbering';
import { sentMessage } from '../src/extension-shims/replies';
import { plainItems } from '../src/extension-shims/storage';
import { tabsIn } from '../src/extension-shims/tabs';
import { chromeUserAgent, userAgentData } from '../src/extension-shims/user-agent';
import { withPasskeys } from '../src/extension-shims/user-scripts';
import { supportedExtraInfo, withoutSocketPatterns } from '../src/extension-shims/web-request';
import { decodeBytes, encodeBytes, socketURL } from '../src/extension-shims/web-socket';
import { importVerdict, shippedScripts } from '../src/extension-shims/worker-fixes';

describe('Chrome calling conventions', () => {
  it('takes a trailing callback off the arguments', () => {
    const callback = vi.fn();
    const args: unknown[] = [1, callback];
    expect(takeCallback(args)).toBe(callback);
    expect(args).toEqual([1]);
    expect(takeCallback(args)).toBeNull();
    expect(takeCallback([])).toBeNull();
  });

  it('sends arguments to the browser as JSON', () => {
    expect(nativeRequest('history.search', [{ text: 'a', skip: undefined, when: new Date(0) }])).toEqual({
      api: 'history.search',
      args: [{ text: 'a', when: '1970-01-01T00:00:00.000Z' }],
    });
    expect(nativeRequest('bookmarks.getTree', undefined)).toEqual({ api: 'bookmarks.getTree', args: [] });
  });

  it("takes the browser's value, or throws its error", () => {
    expect(replyValue({ value: [1] })).toEqual([1]);
    expect(replyValue(null)).toBeUndefined();
    expect(() => replyValue({ error: 'The extension never asked for “history”' })).toThrow('never asked');
  });

  it('drops trailing undefineds from a call carried to the worker', () => {
    expect(carriedArguments([1, undefined, { a: undefined }, undefined, undefined])).toEqual([1, null, {}]);
  });
});

describe('Events', () => {
  it('keeps its listeners in a set the shim fires', () => {
    const event = createEvent();
    const listener = vi.fn();
    event.addListener(listener);
    expect(event.hasListener(listener)).toBe(true);
    expect(event.hasListeners()).toBe(true);
    expect([...event.listeners]).toEqual([listener]);
    event.removeListener(listener);
    expect(event.hasListeners()).toBe(false);
  });

  it('tells event names apart', () => {
    expect(isEventName('onMessage')).toBe(true);
    expect(isEventName('once')).toBe(false);
    expect(isEventName('sendMessage')).toBe(false);
  });

  it("lists members up the prototype chain, as WebKit's namespaces keep methods there", () => {
    const proto = { sendMessage() {} };
    const ns = Object.assign(Object.create(proto), { id: 'x' });
    expect([...memberNames(ns)].toSorted()).toEqual(['id', 'sendMessage']);
  });
});

describe('Enums', () => {
  it('names values as Chrome does', () => {
    expect(enumOf('main_frame', 'per-origin', 'x86.64')).toEqual({
      MAIN_FRAME: 'main_frame',
      PER_ORIGIN: 'per-origin',
      X86_64: 'x86.64',
    });
  });

  it('splits camelCase values into words', () => {
    expect(enumOf('firstParty', 'memoryLimitExceeded', 'chrome_update')).toEqual({
      FIRST_PARTY: 'firstParty',
      MEMORY_LIMIT_EXCEEDED: 'memoryLimitExceeded',
      CHROME_UPDATE: 'chrome_update',
    });
  });
});

describe('Message verdicts', () => {
  it('keys a message by its JSON, unless too long or not JSON', () => {
    expect(messageKey({ a: 1 })).toBe('{"a":1}');
    expect(messageKey('x'.repeat(5000))).toBeNull();
    const cycle: Record<string, unknown> = {};
    cycle.self = cycle;
    expect(messageKey(cycle)).toBeNull();
    expect(messageKey(undefined)).toBeNull();
  });

  it("records the worker's and each page's verdict, forgetting old ones", () => {
    const verdicts = new Map<string, VerdictEntry>();
    recordVerdict(verdicts, { key: 'old', from: 'worker', verdict: 'passes', at: 0 }, 0);
    recordVerdict(verdicts, { key: 'k', from: 'page1', verdict: 'passes', at: 40000 }, 40000);
    const entry = recordVerdict(verdicts, { key: 'k', from: 'worker', verdict: 'answers', at: 40001 }, 40001);
    expect(verdicts.has('old')).toBe(false);
    expect(entry.worker?.verdict).toBe('answers');
    expect(entry.pages.get('page1')?.verdict).toBe('passes');
  });

  it('tells the message sent from its extension id', () => {
    expect(sentMessage([{ a: 1 }])).toEqual({ a: 1 });
    expect(sentMessage(['otherextension', { a: 1 }])).toEqual({ a: 1 });
    expect(sentMessage(['text', () => {}])).toBe('text');
  });
});

describe('Ports', () => {
  it('lets a numbered message through once, unwrapped', () => {
    const heard = new Map<string, number>();
    expect(unnumber({ __motePort: ['a', 1], message: 'hi' }, heard)).toEqual({ message: 'hi' });
    expect(unnumber({ __motePort: ['a', 1], message: 'hi' }, heard)).toBe('skip');
    expect(unnumber({ __motePort: ['b', 1], message: 'hi' }, heard)).toEqual({ message: 'hi' });
    expect(unnumber('plain', heard)).toEqual({ message: 'plain' });
  });

  it("tells the browser's probes, and ports to apps", () => {
    expect(isPortProbe({ __moteNative: 'here' })).toBe(true);
    expect(isPortProbe({ native: 1 })).toBe(false);
    const toPages = new WeakSet<object>();
    const page = { name: '', sender: undefined };
    toPages.add(page);
    expect(goesToApp({ name: 'com.apple.passwordmanager', sender: undefined }, toPages)).toBe(true);
    expect(goesToApp(page, toPages)).toBe(false);
    expect(goesToApp({ name: 'search.1', sender: undefined }, toPages)).toBe(false);
    expect(goesToApp({ name: 'x', sender: { id: 'e' } }, toPages)).toBe(false);
  });
});

describe('Worker sockets', () => {
  it('carries bytes as base64', () => {
    const bytes = new Uint8Array(70000).map((_, i) => i % 256);
    expect(new Uint8Array(decodeBytes(encodeBytes(bytes)))).toEqual(bytes);
  });

  it('takes http addresses for ws, and refuses others', () => {
    expect(socketURL('https://example.com/live', 'https://example.com/').href).toBe('wss://example.com/live');
    expect(socketURL('/live', 'http://example.com/').href).toBe('ws://example.com/live');
    expect(() => socketURL('ftp://example.com/', 'https://example.com/')).toThrow('is invalid');
    expect(() => socketURL('wss://example.com/#frag', 'https://example.com/')).toThrow('is invalid');
  });
});

describe('Imported scripts', () => {
  const files = shippedScripts(['/worker.js', '-/test.js', '/lib/a b.js']);
  // Node gives an unknown scheme no origin; WebKit gives extensions one.
  const origin = 'https://abc.example';

  it('loads shipped scripts, skips empty ones, refuses missing ones', () => {
    const at = (path: string) => new URL(path, origin + '/worker.js');
    expect(importVerdict(at('/worker.js'), origin, files)).toBe('load');
    expect(importVerdict(at('/lib/a%20b.js'), origin, files)).toBe('load');
    expect(importVerdict(at('test.js'), origin, files)).toBe('skip');
    expect(importVerdict(at('/missing.js'), origin, files)).toBe('missing');
    expect(importVerdict(new URL('https://cdn.example.com/x.js'), origin, files)).toBe('load');
  });
});

describe('User agent', () => {
  const safari =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15';

  it("makes Safari's user agent Chrome's", () => {
    expect(chromeUserAgent(safari, '140.0.7339.0')).toBe(
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Chrome/140.0.7339.0 Safari/537.36',
    );
  });

  it("answers userAgentData's hints", async () => {
    const data = userAgentData(chromeUserAgent(safari, '140.0.7339.0'), '140.0.7339.0');
    expect(data.brands.map((b) => b.brand + ' ' + b.version)).toEqual([
      'Chromium 140',
      'Google Chrome 140',
      'Not.A/Brand 99',
    ]);
    expect(await data.getHighEntropyValues(['platformVersion', 'uaFullVersion', 'bogus'])).toMatchObject({
      platform: 'macOS',
      platformVersion: '10.15.7',
      uaFullVersion: '140.0.7339.0',
    });
    expect(data.toJSON()).not.toHaveProperty('getHighEntropyValues');
  });
});

describe('Rules, menus, requests and permissions', () => {
  const base = 'chrome-extension://abc/';

  it('puts rules the way WebKit takes them', () => {
    expect(
      mendRule(
        {
          id: 1,
          action: { type: 'redirect', redirect: { url: base + 'blocked.html' } },
          condition: {
            resourceTypes: ['main_frame', 'object'],
            excludedResourceTypes: ['webbundle', 'image'],
          },
        },
        base,
      ),
    ).toEqual({
      id: 1,
      action: { type: 'redirect', redirect: { extensionPath: '/blocked.html' } },
      condition: { resourceTypes: ['main_frame'], excludedResourceTypes: ['image'] },
    });
    expect(mendRule({ id: 2, condition: { resourceTypes: ['webtransport'] } }, base)).toBeNull();
    expect(mendRule('not a rule', base)).toBe('not a rule');
  });

  it('finds the rule WebKit refused in its error', () => {
    expect(refusedRuleIndex(new Error('Invalid rule at index 3: bad header'))).toBe(3);
    expect(refusedRuleIndex(new Error('Something else'))).toBeNull();
  });

  it('moves old button contexts to the action, and drops the launcher', () => {
    expect(mendMenuProperties({ id: 'm', contexts: ['browser_action', 'page_action', 'launcher'] })).toEqual({
      id: 'm',
      contexts: ['action'],
    });
    expect(mendMenuProperties({ contexts: ['launcher'] })).toEqual({ contexts: ['page'] });
    expect(mendMenuProperties({ title: 'x' })).toEqual({ title: 'x' });
  });

  it('leaves socket patterns out of a request filter', () => {
    expect(withoutSocketPatterns({ urls: ['wss://*/*', 'https://*/*'] })).toEqual({ urls: ['https://*/*'] });
    expect(withoutSocketPatterns({ urls: ['ws://*/*'] })).toBeNull();
    expect(withoutSocketPatterns(undefined)).toBeUndefined();
    expect(supportedExtraInfo(['blocking', 'requestHeaders', 'extraHeaders'])).toEqual(['requestHeaders']);
  });

  it('splits permissions by who answers for them', () => {
    expect(splitPermissions(['tabs', 'bookmarks', 'bogus'])).toEqual({
      theirs: ['tabs'],
      mine: ['bookmarks'],
      unknown: ['bogus'],
    });
  });

  it("puts the passkey patch before a page world's scripts", () => {
    expect(
      withPasskeys(
        [
          { id: 'a', js: ['a.js'], world: 'MAIN' },
          { id: 'b', js: ['b.js'] },
          { id: 'c', js: ['mote-passkeys.js', 'c.js'], world: 'MAIN' },
        ],
        false,
      ),
    ).toEqual([
      { id: 'a', js: ['mote-passkeys.js', 'a.js'], world: 'MAIN' },
      { id: 'b', js: ['b.js'] },
      { id: 'c', js: ['mote-passkeys.js', 'c.js'], world: 'MAIN' },
    ]);
    expect(withPasskeys([{ id: 'b', js: ['b.js'] }], true)).toEqual([
      { id: 'b', js: ['mote-passkeys.js', 'b.js'] },
    ]);
  });
});

describe('Tabs and storage', () => {
  it('finds tabs in what tabs and windows answer', () => {
    const tab = { id: 1, index: 0, windowId: 5 };
    expect(tabsIn([tab, { id: 2, index: 1, windowId: 5 }], 'tabs')).toHaveLength(2);
    expect(tabsIn(tab, 'tabs')).toEqual([tab]);
    expect(tabsIn(undefined, 'tabs')).toEqual([]);
    expect(tabsIn(undefined, 'windows')).toEqual([]);
  });

  it('tells windows from tabs, and finds the tabs inside windows', () => {
    const tab = { id: 1, index: 0, windowId: 5 };
    const window = { id: 5, focused: true, state: 'normal', tabs: [tab] };
    expect(tabsIn(window, 'windows')).toEqual([tab]);
    expect(tabsIn([window, { id: 6, focused: false }], 'windows')).toEqual([tab]);
    // A window a tabs method or listener hands on is not taken for a tab.
    expect(tabsIn({ id: 6, focused: false, state: 'normal' }, 'tabs')).toEqual([]);
  });

  it('copies items without the plain prototype', () => {
    const items = Object.assign(Object.create(null), { a: 1 });
    expect(Object.getPrototypeOf(plainItems(items))).toBe(Object.prototype);
    const plain = { a: 1 };
    expect(plainItems(plain)).toBe(plain);
  });
});

describe('FileSystem paths', () => {
  const origin = 'chrome-extension://abc';

  it('resolves paths into segments', () => {
    expect(segments('/a/b', 'c/../d/./e')).toEqual(['a', 'b', 'd', 'e']);
    expect(segments('/a/b', '/x')).toEqual(['x']);
    expect(segments('/', undefined)).toEqual([]);
  });

  it('reads and writes filesystem: URLs of its own origin', () => {
    expect(parseFileSystemURL(origin + '/x', origin)).toBeNull();
    expect(parseFileSystemURL('filesystem:' + origin + '/persistent/shots/a%20b.png?x', origin)).toEqual({
      type: PERSISTENT,
      segs: ['shots', 'a b.png'],
    });
    expect(parseFileSystemURL('filesystem:https://other.example/temporary/a', origin)).toBeNull();
    expect(fileSystemURL(origin, PERSISTENT, '/shots/a b.png')).toBe(
      'filesystem:' + origin + '/persistent/shots/a%20b.png',
    );
    expect(fileSystemURL(origin, TEMPORARY, '/')).toBe('filesystem:' + origin + '/temporary/');
  });

  it("types a file by its name's extension", () => {
    expect(typeOf({ type: '', name: 'shot.PNG' })).toBe('image/png');
    expect(typeOf({ type: 'text/csv', name: 'a.png' })).toBe('text/csv');
    expect(typeOf({ type: '', name: 'data.bin' })).toBe('');
  });

  it('forgets a path and everything under it', () => {
    expect(isUnder('1:/shots/a.png', PERSISTENT, '/shots')).toBe(true);
    expect(isUnder('1:/shotsother/a.png', PERSISTENT, '/shots')).toBe(false);
    expect(isUnder('0:/shots/a.png', PERSISTENT, '/shots')).toBe(false);
    expect(isUnder('1:/a.png', PERSISTENT, '/')).toBe(true);
  });
});
