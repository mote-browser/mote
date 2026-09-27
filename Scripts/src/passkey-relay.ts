// Passkeys offered (PasskeyRelay.page in Passkeys.swift): replaces
// `navigator.credentials.get`/`create` for public-key requests so they reach
// Mote's own WebAuthn handling, and forwards every other request to WebKit.
//
// Injected at document start into every frame, in the page's own world, since
// it replaces the page's functions; extensions also carry a copy before their
// page-world scripts (ExtensionShims.passkeys). It defines no names and sees
// no `window.webkit`: requests go out as window events, named at random for
// each launch, that `passkey-bridge`, in Mote's isolated world, hands to
// Swift, where WebKit names the calling frame's origin. The prototype is
// patched because WebKit recreates `navigator.credentials` when nothing
// references it.
//
// Sites should find it no different from Safari's own: the functions read as
// native (lib/native.ts), every error has the one message the spec's name for
// it carries (lib/passkeys.ts), and the functions it calls on the page's
// objects were taken before the page could replace them.

import type { AssertionRequest, RegistrationRequest } from './lib/passkey-messages';
import { presentAsNative } from './lib/native';
import { abortError, extensionWatcher, pageError, pendingUntilAborted, randomHex } from './lib/passkeys';
import { clientCapabilities } from './passkey-relay/capabilities';
import { settle } from './passkey-relay/credential';
import { claim } from './passkey-relay/once';
import { assertionRequest, registrationRequest } from './passkey-relay/requests';
import { Waiting } from './passkey-relay/waiting';

/** Event names shared with the bridge (`PasskeyRelay.asked`, `answered` and `installed`). */
declare const moteConfig: { askEvent: string; answerEvent: string; installEvent: string };

type CreationOptions = CredentialCreationOptions & { mediation?: CredentialMediationRequirement };
type Capabilities = Record<string, boolean>;
type AnyFunction = (...args: never[]) => unknown;

// Taken as the script starts, before any page script runs.
const apply = Reflect.apply;
const addListener = EventTarget.prototype.addEventListener;
const dispatchEvent = EventTarget.prototype.dispatchEvent;
const PageCustomEvent = CustomEvent;
const PagePromise = Promise;
const stringify = JSON.stringify;
const then = Promise.prototype.then;
const isPrototypeOf = Object.prototype.isPrototypeOf;
const containerProto: object = CredentialsContainer.prototype;
const typeErrorProto: object = TypeError.prototype;

/** `value instanceof CredentialsContainer`, which a page can't redefine. */
const isContainer = (value: unknown): boolean => apply(isPrototypeOf, containerProto, [value]) as boolean;

/** Why an aborted request failed: the page's reason, or the standard AbortError. */
function abortReason(signal: AbortSignal): unknown {
  return signal.reason !== undefined ? signal.reason : abortError();
}

/** Puts `value` in place of `target[name]`, keeping the property's attributes. */
function replace(target: object, name: string, value: unknown): void {
  try {
    Object.defineProperty(target, name, { value });
  } catch {
    // Left as it is when it can't be redefined.
  }
}

/**
 * The request the page's options make, or the error they fail with. Options
 * of the wrong kind fail as a TypeError with its one message, as WebKit's
 * checks would, never with one naming Mote's code; an error the page's own
 * getters throw goes to the page as it is.
 */
function build<T>(make: () => T): { request: T } | { error: unknown } {
  try {
    return { request: make() };
  } catch (error) {
    const wrongKind = apply(isPrototypeOf, typeErrorProto, [error]) as boolean;
    return { error: wrongKind ? pageError('TypeError') : error };
  }
}

installPasskeyRelay();

function installPasskeyRelay(): void {
  if (!window.PublicKeyCredential || !window.CredentialsContainer) return;
  // In once, whichever copy comes first (an extension's or Mote's own). The
  // claim holds navigator.credentials too: held, WebKit keeps it, and an
  // extension's own get and create on it with it.
  if (!claim(window, moteConfig.installEvent, navigator.credentials)) return;
  const proto = CredentialsContainer.prototype;
  const nativeGet = proto.get as AnyFunction;
  const nativeCreate = proto.create as AnyFunction;

  const waiting = new Waiting();
  apply(addListener, window, [
    moteConfig.answerEvent,
    (event: Event) => {
      waiting.answer((event as CustomEvent<unknown>).detail);
    },
  ]);

  function dispatch(message: object): void {
    apply(dispatchEvent, window, [new PageCustomEvent(moteConfig.askEvent, { detail: stringify(message) })]);
  }

  function send(
    request: AssertionRequest | RegistrationRequest,
    signal: AbortSignal | null | undefined,
    extensions: AuthenticationExtensionsClientInputs | undefined,
  ): Promise<PublicKeyCredential> {
    if (signal && signal.aborted) return PagePromise.reject(abortReason(signal));
    const token = randomHex(16);
    request.token = token;
    return new PagePromise((resolve, reject) => {
      if (signal) {
        apply(addListener, signal, [
          'abort',
          () => {
            waiting.drop(token);
            dispatch({ kind: 'cancel', token });
            reject(abortReason(signal));
          },
          { once: true },
        ]);
      }
      waiting.add(token, (reply) => {
        const outcome = settle(reply, extensions);
        if ('error' in outcome) reject(outcome.error);
        else resolve(outcome.credential);
      });
      dispatch(request);
    });
  }

  // Methods, like WebKit's: no `prototype`, not constructors, no parameters counted.
  const replacements = {
    get(this: unknown, ...args: unknown[]): Promise<unknown> {
      const options = args[0] as CredentialRequestOptions | undefined;
      if (!isContainer(this) || !options || !options.publicKey)
        return apply(nativeGet, this, args) as Promise<unknown>;
      const signal = options.signal;
      const publicKey = options.publicKey;
      if (options.mediation === 'conditional') {
        // Nothing of the Mac's is offered under the field yet: the request
        // waits, as it does while nobody picks a passkey, until the page lets
        // it go.
        return pendingUntilAborted(signal, abortReason);
      }
      const built = build(() => assertionRequest(publicKey));
      if ('error' in built) return PagePromise.reject(built.error);
      return send(built.request, signal, publicKey.extensions);
    },

    create(this: unknown, ...args: unknown[]): Promise<unknown> {
      const options = args[0] as CreationOptions | undefined;
      if (!isContainer(this) || !options || !options.publicKey)
        return apply(nativeCreate, this, args) as Promise<unknown>;
      const publicKey = options.publicKey;
      // A passkey made quietly after a password sign-in: not something this
      // browser does yet, so the site hears no, as it would if you had.
      if (options.mediation === 'conditional') return PagePromise.reject(pageError('NotAllowedError'));
      const built = build(() => registrationRequest(publicKey, publicKey.authenticatorSelection || {}));
      if ('error' in built) return PagePromise.reject(built.error);
      return send(built.request, options.signal, publicKey.extensions);
    },
  };
  replace(proto, 'get', replacements.get);
  replace(proto, 'create', replacements.create);
  const disguised: Array<readonly [AnyFunction, AnyFunction]> = [
    [replacements.get, nativeGet],
    [replacements.create, nativeCreate],
  ];

  // A password manager that keeps passkeys offers them under the name field
  // to the sites that ask for them that way. Once one is there, pages hear
  // the field can.
  const extensionAnswers = extensionWatcher();
  const P = PublicKeyCredential as typeof PublicKeyCredential & {
    getClientCapabilities?: () => Promise<Capabilities>;
  };
  const nativeCapabilities = P.getClientCapabilities;
  const statics = {
    isUserVerifyingPlatformAuthenticatorAvailable(): Promise<boolean> {
      return PagePromise.resolve(true);
    },
    isConditionalMediationAvailable(): Promise<boolean> {
      return PagePromise.resolve(extensionAnswers());
    },
    getClientCapabilities(): Promise<Capabilities> {
      const conditional = extensionAnswers();
      const ours = (native: Capabilities): Capabilities => clientCapabilities(native, conditional);
      const asked = apply(nativeCapabilities as AnyFunction, P, []);
      return apply(then, asked, [ours, () => ours({})]) as Promise<Capabilities>;
    },
  };
  for (const name of Object.keys(statics) as Array<keyof typeof statics>) {
    const native = P[name] as AnyFunction | undefined;
    if (typeof native !== 'function') continue;
    replace(P, name, statics[name]);
    disguised.push([statics[name], native]);
  }
  presentAsNative(disguised);
}
