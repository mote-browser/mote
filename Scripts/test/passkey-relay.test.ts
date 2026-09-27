import { afterEach, describe, expect, it, vi } from 'vitest';
import { PAGE_ERRORS } from '../src/lib/passkeys';
import { clientCapabilities } from '../src/passkey-relay/capabilities';
import { credentialJSON, extensionResults, replyError, settle } from '../src/passkey-relay/credential';
import { claim } from '../src/passkey-relay/once';
import { Waiting } from '../src/passkey-relay/waiting';
import { decode, encode } from '../src/passkey-relay/encoding';
import { assertionRequest, descriptors, registrationRequest } from '../src/passkey-relay/requests';

const challenge = new Uint8Array([0xfb, 0xff, 0x01, 0x02]);

describe('base64url', () => {
  it('encodes without padding or +/', () => {
    expect(encode(challenge)).toBe('-_8BAg');
    expect(encode(challenge.buffer)).toBe('-_8BAg');
  });

  it('encodes only the bytes a view covers', () => {
    expect(encode(new DataView(challenge.buffer, 1, 2))).toBe('_wE');
  });

  it('refuses anything but binary data', () => {
    expect(() => encode('text')).toThrow(TypeError);
    expect(() => encode([1, 2])).toThrow(TypeError);
  });

  it('decodes padded or unpadded text, and nothing to no bytes', () => {
    expect([...new Uint8Array(decode('-_8BAg'))]).toEqual([...challenge]);
    expect([...new Uint8Array(decode('_wE='))]).toEqual([0xff, 0x01]);
    expect(decode(undefined).byteLength).toBe(0);
  });
});

describe('requests', () => {
  it('serializes a sign-in with defaults', () => {
    expect(assertionRequest({ challenge })).toEqual({
      kind: 'get',
      challenge: '-_8BAg',
      rpId: null,
      allowCredentials: [],
      userVerification: 'preferred',
    });
  });

  it('carries only what the page asked, never an origin of its own', () => {
    const options = {
      challenge,
      rpId: 'example.com',
      origin: 'https://evil.example',
    } as PublicKeyCredentialRequestOptions;
    const request = assertionRequest(options);
    expect(request.rpId).toBe('example.com');
    expect(Object.keys(request)).not.toContain('origin');
  });

  it('serializes allowed credentials with their transports', () => {
    expect(
      descriptors([{ type: 'public-key', id: new Uint8Array([1]), transports: ['usb', 'nfc'] }]),
    ).toEqual([{ id: 'AQ', transports: ['usb', 'nfc'] }]);
  });

  it('serializes a registration', () => {
    const options: PublicKeyCredentialCreationOptions = {
      challenge,
      rp: { id: 'example.com', name: 'Example' },
      user: { id: new Uint8Array([7]), name: 'ada', displayName: '' },
      pubKeyCredParams: [
        { type: 'public-key', alg: -7 },
        { type: 'public-key', alg: -257 },
      ],
      attestation: 'direct',
    };
    expect(
      registrationRequest(options, { requireResidentKey: true, authenticatorAttachment: 'platform' }),
    ).toEqual({
      kind: 'create',
      challenge: '-_8BAg',
      rp: { id: 'example.com' },
      user: { id: 'Bw', name: 'ada', displayName: '' },
      algorithms: [-7, -257],
      excludeCredentials: [],
      authenticatorAttachment: 'platform',
      residentKey: 'required',
      userVerification: 'preferred',
      attestation: 'direct',
    });
  });

  it('throws for a missing user or a challenge that isn’t binary', () => {
    const noUser = { challenge, rp: { name: 'Example' } } as unknown as PublicKeyCredentialCreationOptions;
    expect(() => registrationRequest(noUser, {})).toThrow(TypeError);
    expect(() => assertionRequest({ challenge: 'abc' as unknown as BufferSource })).toThrow(TypeError);
  });
});

describe('replyError', () => {
  it('is null for a reply that is no failure', () => {
    expect(replyError({ kind: 'get', id: 'AQ' })).toBeNull();
  });

  it('is NotAllowedError, with the standard message, for no reply or a failure without one', () => {
    for (const reply of [null, undefined, 'text', 42, { error: 'NotAllowedError' }]) {
      const error = replyError(reply) as DOMException;
      expect(error.name).toBe('NotAllowedError');
      expect(error.message).toBe('The operation either timed out or was not allowed.');
    }
  });

  it('keeps the name Swift chose, but never its message', () => {
    const typeError = replyError({ error: 'TypeError', message: 'A challenge is required.' });
    expect(typeError).toBeInstanceOf(TypeError);
    expect(typeError?.message).toBe('Type error');
    const error = replyError({ error: 'SecurityError', message: 'Bad RP' }) as DOMException;
    expect([error.name, error.message]).toEqual(['SecurityError', 'The operation is insecure.']);
  });

  it('turns a name the page may not hear into NotAllowedError', () => {
    for (const name of ['RangeError', 'toString', 'constructor', '__proto__']) {
      const error = replyError({ error: name, message: 'Mote-only words' }) as DOMException;
      expect([error.name, error.message]).toEqual(['NotAllowedError', PAGE_ERRORS.NotAllowedError]);
    }
  });
});

/** Stand-ins for WebKit's classes, which happy-dom lacks. */
function stubCredentialClasses(): void {
  vi.stubGlobal('PublicKeyCredential', function PublicKeyCredential() {});
  vi.stubGlobal('AuthenticatorAssertionResponse', function AuthenticatorAssertionResponse() {});
}

describe('settle', () => {
  const assertion = {
    kind: 'get' as const,
    id: 'AQ',
    clientDataJSON: 'Yw',
    authenticatorData: 'YQ',
    signature: 'cw',
    attachment: 'platform',
  };

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it('makes a credential of a reply that is one', () => {
    stubCredentialClasses();
    const outcome = settle(assertion, undefined);
    expect('credential' in outcome && outcome.credential).toBeInstanceOf(PublicKeyCredential);
  });

  it("fails as NotAllowedError, never pending, for a reply it can't read", () => {
    stubCredentialClasses();
    for (const reply of [
      null,
      'text',
      {},
      { kind: 'get' },
      { kind: 'sign', id: 'AQ', clientDataJSON: 'Yw' },
      { ...assertion, signature: 7 },
      { ...assertion, clientDataJSON: '%%%' },
      { kind: 'create', id: 'AQ', clientDataJSON: 'Yw' },
    ]) {
      const outcome = settle(reply, undefined);
      expect('error' in outcome && (outcome.error as DOMException).name, JSON.stringify(reply)).toBe(
        'NotAllowedError',
      );
    }
  });

  it("fails as NotAllowedError when the credential can't be built", () => {
    // No PublicKeyCredential here: building one throws.
    const outcome = settle(assertion, undefined);
    expect('error' in outcome && (outcome.error as DOMException).name).toBe('NotAllowedError');
  });
});

describe('Waiting', () => {
  it('settles the request an answer names, once', () => {
    const waiting = new Waiting();
    const settled: unknown[] = [];
    waiting.add('abc', (reply) => settled.push(reply));
    expect(waiting.answer(JSON.stringify({ token: 'abc', reply: { kind: 'get' } }))).toBe(true);
    expect(waiting.answer(JSON.stringify({ token: 'abc', reply: {} }))).toBe(false);
    expect(settled).toEqual([{ kind: 'get' }]);
  });

  it("finds nothing for tokens it wasn't given, inherited names included", () => {
    const waiting = new Waiting();
    for (const token of ['toString', 'constructor', '__proto__', 'hasOwnProperty']) {
      expect(waiting.answer(JSON.stringify({ token, reply: null }))).toBe(false);
    }
    expect(waiting.answer('not json')).toBe(false);
    expect(waiting.answer('{"token":7}')).toBe(false);
  });

  it('forgets a request the page let go', () => {
    const waiting = new Waiting();
    const answered = vi.fn();
    waiting.add('abc', answered);
    waiting.drop('abc');
    expect(waiting.answer(JSON.stringify({ token: 'abc', reply: null }))).toBe(false);
    expect(answered).not.toHaveBeenCalled();
  });
});

describe('claim', () => {
  it('lets the first copy in and no other, leaving nothing to find', () => {
    const target = new EventTarget();
    const before = [Object.getOwnPropertyNames(target), Object.getOwnPropertySymbols(target)];
    expect(claim(target, 'f00d', {})).toBe(true);
    expect(claim(target, 'f00d', {})).toBe(false);
    expect(claim(target, 'beef', {})).toBe(true);
    expect([Object.getOwnPropertyNames(target), Object.getOwnPropertySymbols(target)]).toEqual(before);
  });
});

describe('credentialJSON', () => {
  it('describes a sign-in, with the user handle when there is one', () => {
    const reply = {
      kind: 'get' as const,
      id: 'AQ',
      clientDataJSON: 'Yw',
      authenticatorData: 'YQ',
      signature: 'cw',
      userHandle: 'dQ',
      attachment: 'platform',
    };
    expect(credentialJSON(reply, {})).toEqual({
      id: 'AQ',
      rawId: 'AQ',
      type: 'public-key',
      authenticatorAttachment: 'platform',
      clientExtensionResults: {},
      response: { clientDataJSON: 'Yw', authenticatorData: 'YQ', signature: 'cw', userHandle: 'dQ' },
    });
  });

  it('describes a registration, defaulting to ES256', () => {
    const reply = {
      kind: 'create' as const,
      id: 'AQ',
      clientDataJSON: 'Yw',
      attestationObject: 'bw',
      transports: ['usb'],
    };
    const json = credentialJSON(reply, {});
    expect(json.authenticatorAttachment).toBeNull();
    expect(json.response).toEqual({
      clientDataJSON: 'Yw',
      attestationObject: 'bw',
      authenticatorData: undefined,
      transports: ['usb'],
      publicKeyAlgorithm: -7,
    });
  });

  it('reports a Mac passkey as discoverable when the site asks', () => {
    const made = { kind: 'create' as const, attachment: 'platform' };
    expect(extensionResults(made, { credProps: true })).toEqual({ credProps: { rk: true } });
    expect(extensionResults(made, {})).toEqual({});
    expect(extensionResults({ ...made, attachment: 'cross-platform' }, { credProps: true })).toEqual({});
    expect(extensionResults({ kind: 'get', attachment: 'platform' }, { credProps: true })).toEqual({});
  });
});

describe('clientCapabilities', () => {
  it('turns off extensions other than credProps, and says what Mote can do', () => {
    const capabilities = clientCapabilities(
      { 'extension:credProps': true, 'extension:prf': true, conditionalCreate: true, hybridTransport: false },
      false,
    );
    expect(capabilities).toMatchObject({
      'extension:credProps': true,
      'extension:prf': false,
      conditionalCreate: false,
      conditionalGet: false,
      conditionalMediation: false,
      hybridTransport: true,
      passkeyPlatformAuthenticator: true,
    });
  });

  it('offers the name field only when an extension answers there', () => {
    expect(clientCapabilities({}, true)).toMatchObject({ conditionalGet: true, conditionalMediation: true });
  });
});
