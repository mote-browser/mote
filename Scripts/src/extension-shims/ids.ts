// Ids the shim gives its own ends — a page on the verdict channel, one
// end of a port — told apart across every context of the extension.

import { crypto } from './captured';

/**
 * A new id: 128 random bits, as 32 hex digits. From `getRandomValues`,
 * which every context has; `randomUUID` needs a secure one, and a
 * content script can run on a plain http page.
 */
export function randomId(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
}
