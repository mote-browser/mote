import { afterEach, describe, expect, it, vi } from 'vitest';
import { presentAsNative } from '../src/lib/native';
import {
  abortError,
  isExtensionStack,
  ownsCredentialMethods,
  PAGE_ERRORS,
  pageError,
  pendingUntilAborted,
  randomHex,
} from '../src/lib/passkeys';

describe('extension detection', () => {
  it('sees an extension in the stack', () => {
    expect(isExtensionStack('get@webkit-extension://abc/content.js:1:2')).toBe(true);
    expect(isExtensionStack('get@chrome-extension://abc/inject.js:3:4')).toBe(true);
    expect(isExtensionStack('get@https://example.com/app.js:1:2')).toBe(false);
    expect(isExtensionStack(undefined)).toBe(false);
  });

  it('sees methods put on the credentials object itself, not on its prototype', () => {
    const credentials = Object.create({ get() {} }) as CredentialsContainer;
    expect(ownsCredentialMethods(credentials)).toBe(false);
    Object.defineProperty(credentials, 'get', { value: () => null });
    expect(ownsCredentialMethods(credentials)).toBe(true);
    expect(ownsCredentialMethods(undefined)).toBe(false);
  });
});

const reason = (signal: AbortSignal): unknown => signal.reason || abortError();

describe('pendingUntilAborted', () => {
  it('rejects when the page aborts', async () => {
    const controller = new AbortController();
    const waiting = pendingUntilAborted(controller.signal, reason);
    controller.abort('left');
    await expect(waiting).rejects.toBe('left');
  });

  it('rejects at once for a signal already aborted', async () => {
    await expect(pendingUntilAborted(AbortSignal.abort('gone'), reason)).rejects.toBe('gone');
  });

  it('never settles without a signal', async () => {
    const settled = await Promise.race([
      pendingUntilAborted(undefined, reason).then(
        () => 'settled',
        () => 'settled',
      ),
      new Promise((resolve) => setTimeout(() => resolve('pending'), 20)),
    ]);
    expect(settled).toBe('pending');
  });
});

describe('pageError', () => {
  it('carries the one message of each name', () => {
    for (const [name, message] of Object.entries(PAGE_ERRORS)) {
      const error = pageError(name);
      expect([error.name, error.message]).toEqual([name, message]);
      expect(error).toBeInstanceOf(name === 'TypeError' ? TypeError : DOMException);
    }
  });

  it('is NotAllowedError for any other name, inherited ones included', () => {
    for (const name of ['UnknownError', 'toString', 'constructor', undefined, 7]) {
      expect(pageError(name).name).toBe('NotAllowedError');
    }
  });
});

describe('randomHex', () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('draws from the cryptographic generator, never Math.random', () => {
    const random = vi.spyOn(Math, 'random');
    const fill = vi.fn((array: Uint8Array<ArrayBuffer>) => array.fill(0xab));
    expect(randomHex(16, fill)).toBe('ab'.repeat(16));
    expect(fill).toHaveBeenCalledOnce();
    const drawn = randomHex(16);
    expect(drawn).toMatch(/^[0-9a-f]{32}$/);
    expect(randomHex(16)).not.toBe(drawn);
    expect(random).not.toHaveBeenCalled();
  });
});

function other(): number {
  return 1;
}

describe('presentAsNative', () => {
  const functions: object = Function.prototype;
  const original = Object.getOwnPropertyDescriptor(functions, 'toString') as PropertyDescriptor;

  afterEach(() => {
    Object.defineProperty(functions, 'toString', original);
  });

  it('shows a replacement as the native function it stands for, and itself as native', () => {
    const native = Array.prototype.map;
    const nativeText = Function.prototype.toString.call(native);
    const toStringText = Function.prototype.toString.call(Function.prototype.toString);
    const replacement = {
      map(...args: unknown[]): unknown {
        return args;
      },
    }.map;
    const otherText = Function.prototype.toString.call(other);

    presentAsNative([[replacement, native]]);

    expect(Function.prototype.toString.call(replacement)).toBe(nativeText);
    expect(String(replacement)).toBe(nativeText);
    expect(Function.prototype.toString.call(Function.prototype.toString)).toBe(toStringText);
    expect(Function.prototype.toString.call(other)).toBe(otherText);
    expect(Function.prototype.toString.name).toBe('toString');
    expect(Function.prototype.toString.length).toBe(0);
    expect('prototype' in Function.prototype.toString).toBe(false);
    expect(Object.getOwnPropertyDescriptor(Function.prototype, 'toString')).toMatchObject({
      writable: true,
      enumerable: false,
      configurable: true,
    });
    expect(() => Function.prototype.toString.call({})).toThrow(TypeError);
  });
});
