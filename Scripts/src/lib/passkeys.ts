// Shared by the two page-world passkey scripts: `passkey-relay` (passkeys
// offered) and `passkeys-hidden` (passkeys off in Settings › Passwords).

/**
 * The errors a page may hear from a WebAuthn request, each with the one
 * message it always carries, whatever the reason, as the spec leaves messages
 * to the browser: a site can't tell passkeys turned off from a sheet the user
 * closed. `Passkeys.messages` in Passkeys.swift is the same table.
 */
export const PAGE_ERRORS: Readonly<Record<string, string>> = Object.assign(Object.create(null) as object, {
  NotAllowedError: 'The operation either timed out or was not allowed.',
  SecurityError: 'The operation is insecure.',
  TypeError: 'Type error',
  NotSupportedError: 'The operation is not supported.',
  InvalidStateError: 'The object is in an invalid state.',
  AbortError: 'The operation was aborted.',
});

// Taken as the script starts, before the page runs: a page that later
// replaces them sees nothing of Mote's calls.
const PageDOMException = DOMException;
const PageTypeError = TypeError;
const fillRandom = crypto.getRandomValues.bind(crypto);
const addListener = EventTarget.prototype.addEventListener;
const apply = Reflect.apply;

/** The message of every refusal a page hears, whatever the reason. */
export const NOT_ALLOWED_MESSAGE = PAGE_ERRORS.NotAllowedError as string;

/**
 * The error named `name` as the page hears it, with its one message: a
 * TypeError, or a DOMException. A name that isn't one of `PAGE_ERRORS` is
 * NotAllowedError.
 */
export function pageError(name: unknown): Error {
  // PAGE_ERRORS has no prototype: `in` finds no inherited names like `toString`.
  const chosen = typeof name === 'string' && name in PAGE_ERRORS ? name : 'NotAllowedError';
  const message = PAGE_ERRORS[chosen] as string;
  return chosen === 'TypeError' ? new PageTypeError(message) : new PageDOMException(message, chosen);
}

/** The standard abort error, for a signal aborted without a reason. */
export function abortError(): DOMException {
  return pageError('AbortError') as DOMException;
}

/** `bytes` random bytes from the cryptographic generator, as hex. */
export function randomHex(
  bytes: number,
  fill: (array: Uint8Array<ArrayBuffer>) => unknown = fillRandom,
): string {
  const values = new Uint8Array(bytes);
  fill(values);
  let hex = '';
  for (let i = 0; i < values.length; i++) hex += (values[i] as number).toString(16).padStart(2, '0');
  return hex;
}

/**
 * A conditional request (passkeys offered under the name field) that nothing
 * answers: it waits, as it would while nobody picks a passkey, until the page
 * aborts it. Without a signal it never settles.
 */
export function pendingUntilAborted(
  signal: AbortSignal | null | undefined,
  reason: (signal: AbortSignal) => unknown,
): Promise<never> {
  return new Promise((_resolve, reject) => {
    if (!signal) return;
    if (signal.aborted) {
      reject(reason(signal));
      return;
    }
    apply(addListener, signal, ['abort', () => reject(reason(signal)), { once: true }]);
  });
}

/** Whether something installed its own `get` on the `navigator.credentials` object itself. */
export function ownsCredentialMethods(credentials: CredentialsContainer | null | undefined): boolean {
  return !!credentials && !!Object.getOwnPropertyDescriptor(credentials, 'get');
}

/** Whether a stack trace passes through an extension's script. */
export function isExtensionStack(stack: string | undefined): boolean {
  return (stack || '').indexOf('-extension://') >= 0;
}

/**
 * Whether a password manager extension that keeps passkeys (1Password,
 * Bitwarden) is on the page: it puts its own `get` and `create` on
 * `navigator.credentials`, or asks from its own script. Once seen, it stays
 * seen.
 */
export function extensionWatcher(): () => boolean {
  let claimed = false;
  return () => {
    if (claimed) return true;
    try {
      if (ownsCredentialMethods(navigator.credentials)) claimed = true;
      else if (isExtensionStack(new Error().stack)) claimed = true;
    } catch {
      // A page that broke navigator.credentials has no extension to find.
    }
    return claimed;
  };
}
