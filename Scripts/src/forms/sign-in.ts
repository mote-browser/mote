/** Input types that can hold the account name next to a password. */
const USERNAME_TYPES = new Set(['text', 'email', 'tel']);

/** A sign-in on the page: its password field and the field that names the account, if any. */
export interface SignInFields {
  user: HTMLInputElement | null;
  password: HTMLInputElement;
}

/** The lowercase type of an input, `text` when it has none. */
export function inputType(input: HTMLInputElement): string {
  return (input.type || 'text').toLowerCase();
}

/** Whether an element takes up any room on the page (hidden ones don't). */
export function hasSize(element: Element): boolean {
  const rect = element.getBoundingClientRect();
  return rect.width > 0 && rect.height > 0;
}

/**
 * The page's sign-in, or null when it has none: the first password field that
 * is shown, and the last field before it (in its form, or the document) that
 * could hold a name.
 */
export function signInFields(document: Document): SignInFields | null {
  let password: HTMLInputElement | null = null;
  for (const field of document.querySelectorAll<HTMLInputElement>('input[type="password"]')) {
    if (hasSize(field)) {
      password = field;
      break;
    }
  }
  if (!password) return null;
  const scope: ParentNode = password.form || password.closest('form') || document;
  let user: HTMLInputElement | null = null;
  for (const input of scope.querySelectorAll('input')) {
    if (input === password) break;
    if (USERNAME_TYPES.has(inputType(input))) user = input;
  }
  return { user, password };
}

/**
 * Sets a field's value as typing would. The native setter and the input and
 * change events are what frameworks such as React notice; assigning `.value`
 * alone is not.
 */
export function setFieldValue(field: HTMLInputElement, value: string): void {
  const descriptor = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value');
  if (descriptor && descriptor.set) descriptor.set.call(field, value);
  else field.value = value;
  field.dispatchEvent(new Event('input', { bubbles: true }));
  field.dispatchEvent(new Event('change', { bubbles: true }));
}

/**
 * Fills a saved account the user picked: the name only into an empty name
 * field, the password always. False when the page has no sign-in anymore.
 */
export function fillSignIn(fields: SignInFields | null, user: string, password: string): boolean {
  if (!fields) return false;
  if (fields.user && !fields.user.value) setFieldValue(fields.user, user);
  setFieldValue(fields.password, password);
  return true;
}

/** What a sign-in is about to send, or null while its password is empty. */
export function submittedCredentials(fields: SignInFields | null): { user: string; password: string } | null {
  if (!fields || !fields.password.value) return null;
  return { user: fields.user ? fields.user.value : '', password: fields.password.value };
}
