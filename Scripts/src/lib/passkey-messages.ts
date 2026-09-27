// What `passkey-relay` (page world) and `passkey-bridge` (Mote's world) pass
// each other as window events, and the bridge passes on to `PasskeyRelay` in
// Passkeys.swift. Event details are JSON text, the one kind of value that
// crosses between content worlds intact.
//
// Nothing here is trusted by Swift: the page can dispatch these events itself
// (were it to learn their names, drawn at random at each launch). Swift
// validates every field and takes the origin from WebKit. The bridge puts
// `document`, its own random name for the document, on every message it passes
// on, over anything the page put there.

/** A credential named in `allowCredentials` or `excludeCredentials`. */
export interface CredentialDescriptor {
  id: string;
  transports: string[];
}

/** `navigator.credentials.get` with `publicKey`: sign in with a passkey. */
export interface AssertionRequest {
  kind: 'get';
  token?: string;
  challenge: string;
  rpId: string | null;
  allowCredentials: CredentialDescriptor[];
  userVerification: string;
}

/** `navigator.credentials.create` with `publicKey`: make a passkey. */
export interface RegistrationRequest {
  kind: 'create';
  token?: string;
  challenge: string;
  rp: { id: string | null };
  user: { id: string; name: string; displayName: string };
  algorithms: number[];
  excludeCredentials: CredentialDescriptor[];
  authenticatorAttachment: string | null;
  residentKey: string;
  userVerification: string;
  attestation: string;
}

/** The page let go of a request (its AbortSignal fired). */
export interface CancelRequest {
  kind: 'cancel';
  token: string;
}

export type PasskeyRequest = AssertionRequest | RegistrationRequest | CancelRequest;

/**
 * Swift's answer: a credential (`Passkeys.assertionReply` or
 * `registrationReply`), or a failure with `error` naming the DOMException.
 */
export interface PasskeyReply {
  error?: string;
  message?: string;
  kind?: 'get' | 'create';
  id?: string;
  clientDataJSON?: string;
  authenticatorData?: string;
  signature?: string;
  userHandle?: string;
  attestationObject?: string;
  transports?: string[];
  publicKey?: string;
  publicKeyAlgorithm?: number;
  attachment?: string;
}

/** What the bridge sends back: the request's token and Swift's reply, or null when the request failed. */
export interface PasskeyAnswer {
  token: string;
  reply: PasskeyReply | null;
}

// Taken as the script starts, before the page could replace it.
const parseJSON = JSON.parse;

/** JSON of an object, or null for anything else. */
function parseObject(detail: unknown): Record<string, unknown> | null {
  let message: unknown;
  try {
    message = parseJSON(detail as string);
  } catch {
    return null;
  }
  return message && typeof message === 'object' ? (message as Record<string, unknown>) : null;
}

/**
 * An answer read from an event's detail, or null when it isn't one with a
 * token. The reply is whatever came: `settle` reads it.
 */
export function parseAnswer(detail: unknown): { token: string; reply: unknown } | null {
  const answer = parseObject(detail);
  if (!answer || typeof answer.token !== 'string') return null;
  return { token: answer.token, reply: answer.reply };
}

/** A request read from an event's detail, or null when it isn't one with a token. */
export function parseRequest(detail: unknown): (Record<string, unknown> & { token: string }) | null {
  const message = parseObject(detail);
  if (!message || typeof message.token !== 'string') return null;
  return message as Record<string, unknown> & { token: string };
}
