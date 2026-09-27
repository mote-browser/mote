// Swift's reply, turned into what the page expects from WebKit: a
// PublicKeyCredential, or the error the request fails with.

import type { PasskeyReply } from '../lib/passkey-messages';
import { pageError } from '../lib/passkeys';
import { decode } from './encoding';

/** ES256, the algorithm of every passkey the Mac makes. */
const DEFAULT_ALGORITHM = -7;

/**
 * The error a reply fails with, or null for one that isn't a failure. Swift
 * names the error; the page hears it with that name's one message
 * (`pageError`), never one of Swift's. No reply, or one that is no object,
 * is NotAllowedError.
 */
export function replyError(reply: unknown): Error | null {
  if (!reply || typeof reply !== 'object') return pageError('NotAllowedError');
  const { error } = reply as PasskeyReply;
  return error ? pageError(error) : null;
}

function text(value: unknown): boolean {
  return typeof value === 'string';
}

/** Whether a reply that isn't a failure has what a credential is made of. */
function isCredentialReply(reply: PasskeyReply): boolean {
  if (!text(reply.id) || !text(reply.clientDataJSON)) return false;
  if (reply.kind === 'get') return text(reply.authenticatorData) && text(reply.signature);
  if (reply.kind === 'create') return text(reply.attestationObject);
  return false;
}

/** What a request comes to: a credential, or the error it fails with. */
export type Outcome = { credential: PublicKeyCredential } | { error: Error };

/**
 * What Swift's reply comes to for the page. Anything that can't be read as a
 * credential (a reply broken in any way) is NotAllowedError, so no request is
 * left pending.
 */
export function settle(
  reply: unknown,
  extensions: AuthenticationExtensionsClientInputs | undefined,
): Outcome {
  try {
    const error = replyError(reply);
    if (error) return { error };
    if (!isCredentialReply(reply as PasskeyReply)) return { error: pageError('NotAllowedError') };
    return { credential: credential(reply as PasskeyReply, extensions) };
  } catch {
    return { error: pageError('NotAllowedError') };
  }
}

/**
 * The client extension results. A passkey from the Mac is always one the site
 * can find without naming it (a resident key); the site may have asked whether
 * it is.
 */
export function extensionResults(
  reply: PasskeyReply,
  extensions: AuthenticationExtensionsClientInputs | undefined,
): Record<string, unknown> {
  const results: Record<string, unknown> = {};
  if (reply.kind === 'create' && extensions && extensions.credProps && reply.attachment === 'platform') {
    results.credProps = { rk: true };
  }
  return results;
}

/** What the credential's `toJSON()` returns. */
export function credentialJSON(
  reply: PasskeyReply,
  results: Record<string, unknown>,
): Record<string, unknown> {
  const made = reply.kind === 'create';
  const response: Record<string, unknown> = made
    ? {
        clientDataJSON: reply.clientDataJSON,
        attestationObject: reply.attestationObject,
        authenticatorData: reply.authenticatorData,
        transports: (reply.transports || []).slice(),
        publicKeyAlgorithm: reply.publicKeyAlgorithm ?? DEFAULT_ALGORITHM,
      }
    : {
        clientDataJSON: reply.clientDataJSON,
        authenticatorData: reply.authenticatorData,
        signature: reply.signature,
      };
  if (made && reply.publicKey) response.publicKey = reply.publicKey;
  if (!made && reply.userHandle) response.userHandle = reply.userHandle;
  return {
    id: reply.id,
    rawId: reply.id,
    type: 'public-key',
    authenticatorAttachment: reply.attachment || null,
    clientExtensionResults: results,
    response,
  };
}

/** Defines `values` on `target` as configurable properties; `hidden` ones aren't enumerable. */
function define<T extends object>(target: T, values: Record<string, unknown>, hidden?: boolean): T {
  Object.keys(values).forEach((key) => {
    Object.defineProperty(target, key, { value: values[key], enumerable: !hidden, configurable: true });
  });
  return target;
}

/**
 * The credential for a reply, built on WebKit's own prototypes so
 * `instanceof PublicKeyCredential` and the response's methods work as sites
 * expect.
 */
export function credential(
  reply: PasskeyReply,
  extensions: AuthenticationExtensionsClientInputs | undefined,
): PublicKeyCredential {
  let response: AuthenticatorResponse;
  const made = reply.kind === 'create';
  if (made) {
    response = Object.create(AuthenticatorAttestationResponse.prototype) as AuthenticatorAttestationResponse;
    define(response, {
      clientDataJSON: decode(reply.clientDataJSON),
      attestationObject: decode(reply.attestationObject),
    });
    define(
      response,
      {
        getTransports: function () {
          return (reply.transports || []).slice();
        },
        getAuthenticatorData: function () {
          return decode(reply.authenticatorData);
        },
        getPublicKey: function () {
          return reply.publicKey ? decode(reply.publicKey) : null;
        },
        getPublicKeyAlgorithm: function () {
          return reply.publicKeyAlgorithm ?? DEFAULT_ALGORITHM;
        },
      },
      true,
    );
  } else {
    response = Object.create(AuthenticatorAssertionResponse.prototype) as AuthenticatorAssertionResponse;
    define(response, {
      clientDataJSON: decode(reply.clientDataJSON),
      authenticatorData: decode(reply.authenticatorData),
      signature: decode(reply.signature),
      userHandle: reply.userHandle ? decode(reply.userHandle) : null,
    });
  }
  const results = extensionResults(reply, extensions);
  const json = credentialJSON(reply, results);
  const result = Object.create(PublicKeyCredential.prototype) as PublicKeyCredential;
  define(result, {
    id: reply.id,
    rawId: decode(reply.id),
    type: 'public-key',
    authenticatorAttachment: reply.attachment || null,
    response,
  });
  return define(
    result,
    {
      getClientExtensionResults: function () {
        return JSON.parse(JSON.stringify(results)) as unknown;
      },
      toJSON: function () {
        return JSON.parse(JSON.stringify(json)) as unknown;
      },
    },
    true,
  );
}
