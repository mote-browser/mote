// Passkeys off (Settings › Passwords, FormRelay.withoutPasskeys in Forms.swift):
// hides `PublicKeyCredential` while keeping `navigator.credentials`, which
// sites also use for stored passwords, so sites fall back to passwords.
//
// Injected at document start into every frame, in the page's own world. It
// defines no names there.
//
// A password manager extension that installs its own `get`/`create` on
// `navigator.credentials`, or asks from its own script, gets the API back, so
// sites reach the extension. Public-key requests left to the browser are
// refused at once with NotAllowedError.

import { presentAsNative } from './lib/native';
import { abortError, extensionWatcher, pageError, pendingUntilAborted } from './lib/passkeys';

type AnyFunction = (...args: never[]) => unknown;
type Options = CredentialRequestOptions & CredentialCreationOptions;

// Taken as the script starts, before any page script runs.
const apply = Reflect.apply;
const PagePromise = Promise;

hidePasskeys();

function hidePasskeys(): void {
  let real: unknown = window.PublicKeyCredential;
  if (!real) return;
  const extensionAnswers = extensionWatcher();
  try {
    Object.defineProperty(window, 'PublicKeyCredential', {
      configurable: true,
      get: function () {
        return extensionAnswers() ? real : undefined;
      },
      set: function (value: unknown) {
        real = value;
      },
    });
  } catch {
    try {
      delete (window as { PublicKeyCredential?: unknown }).PublicKeyCredential;
    } catch {
      // Neither hidden nor removed: the page keeps it.
    }
    return;
  }

  const proto = CredentialsContainer.prototype;
  const nativeGet = proto.get as AnyFunction;
  const nativeCreate = proto.create as AnyFunction;
  // Methods, like WebKit's: no `prototype`, not constructors, no parameters
  // counted; each with a text of its own, which presentAsNative goes by.
  const replacements = {
    get(this: unknown, ...args: unknown[]): Promise<unknown> {
      const options = args[0] as Options | undefined;
      if (!options || !options.publicKey) return apply(nativeGet, this, args) as Promise<unknown>;
      // Under the name field: nothing to offer, so it waits, as it would
      // while nobody picks one, until the page lets it go.
      if (options.mediation === 'conditional') {
        return pendingUntilAborted(options.signal, (signal) => signal.reason || abortError());
      }
      return PagePromise.reject(pageError('NotAllowedError'));
    },
    create(this: unknown, ...args: unknown[]): Promise<unknown> {
      const options = args[0] as Options | undefined;
      if (!options || !options.publicKey) return apply(nativeCreate, this, args) as Promise<unknown>;
      return PagePromise.reject(pageError('NotAllowedError'));
    },
  };
  for (const name of ['get', 'create'] as const) {
    try {
      Object.defineProperty(proto, name, { value: replacements[name] });
    } catch {
      // Left as it is when it can't be redefined.
    }
  }
  presentAsNative([
    [replacements.get, nativeGet],
    [replacements.create, nativeCreate],
  ]);
}
