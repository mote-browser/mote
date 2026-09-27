// WebAuthn binary values cross to Swift as unpadded base64url text
// (`Passkeys.data` and `Passkeys.text` read and write it there).

export function bytes(source: unknown): Uint8Array {
  if (source instanceof ArrayBuffer) return new Uint8Array(source);
  if (ArrayBuffer.isView(source)) return new Uint8Array(source.buffer, source.byteOffset, source.byteLength);
  throw new TypeError('Expected an ArrayBuffer or a view of one.');
}

/** Unpadded base64url of an ArrayBuffer or view; throws a TypeError for anything else. */
export function encode(source: unknown): string {
  const b = bytes(source);
  let binary = '';
  for (let i = 0; i < b.length; i++) binary += String.fromCharCode(b[i] as number);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

/** The bytes of base64url (padded or not) text; nothing for a missing value. */
export function decode(text: string | null | undefined): ArrayBuffer {
  let base64 = (text || '').replace(/-/g, '+').replace(/_/g, '/');
  while (base64.length % 4) base64 += '=';
  const raw = atob(base64);
  const out = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
  return out.buffer;
}
