import { describe, expect, it, vi } from 'vitest';
import { userScriptChrome } from '../src/user-script/chrome';
import { globPattern, globsAllow } from '../src/user-script/globs';

describe('globPattern', () => {
  it('matches a whole URL, with * for any run and ? for one character', () => {
    expect(globPattern('https://*.example.com/*').test('https://www.example.com/a')).toBe(true);
    expect(globPattern('https://*.example.com/*').test('http://www.example.com/a')).toBe(false);
    expect(globPattern('https://example.com/?').test('https://example.com/a')).toBe(true);
    expect(globPattern('https://example.com/?').test('https://example.com/ab')).toBe(false);
  });

  it('takes other characters literally', () => {
    expect(globPattern('https://example.com/a+b(c)[d].html').test('https://example.com/a+b(c)[d].html')).toBe(
      true,
    );
    expect(globPattern('https://example.com/a.b').test('https://example.com/aXb')).toBe(false);
  });
});

describe('globsAllow', () => {
  const href = 'https://news.example.com/story';

  it('runs everywhere without globs', () => {
    expect(globsAllow(href, [], [])).toBe(true);
  });

  it('needs an include glob to match, when there are any', () => {
    expect(globsAllow(href, ['*news*'], [])).toBe(true);
    expect(globsAllow(href, ['*sports*'], [])).toBe(false);
  });

  it('never runs where an exclude glob matches', () => {
    expect(globsAllow(href, ['*example*'], ['*/story'])).toBe(false);
  });
});

describe('userScriptChrome', () => {
  it("tags messages and ports for the USER_SCRIPT world's events", () => {
    const runtime = {
      id: 'abc',
      lastError: undefined as unknown,
      getURL: (path: string) => 'chrome-extension://abc/' + path,
      sendMessage: vi.fn(),
      connect: vi.fn(),
    };
    const chrome = userScriptChrome(runtime);
    const callback = vi.fn();
    chrome.runtime.sendMessage({ hi: 1 }, 'not an option', callback);
    expect(runtime.sendMessage).toHaveBeenCalledWith(
      { __moteUserScript: true, message: { hi: 1 } },
      callback,
    );
    chrome.runtime.connect({ name: 'sync' });
    expect(runtime.connect).toHaveBeenCalledWith({ name: 'mote-us:sync' });
    chrome.runtime.connect();
    expect(runtime.connect).toHaveBeenLastCalledWith({ name: 'mote-us:' });
    runtime.lastError = { message: 'gone' };
    expect(chrome.runtime.lastError).toEqual({ message: 'gone' });
    expect(chrome.runtime.getURL('a.js')).toBe('chrome-extension://abc/a.js');
  });
});
