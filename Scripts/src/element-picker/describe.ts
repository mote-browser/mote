/**
 * Names for elements whose tag says what they are. A Map, not an object: a page
 * can name an element `constructor` or `__proto__`.
 */
const KINDS: ReadonlyMap<string, string> = new Map([
  ['nav', 'Navigation'],
  ['header', 'Header'],
  ['footer', 'Footer'],
  ['aside', 'Sidebar'],
  ['form', 'Form'],
  ['dialog', 'Dialog'],
  ['video', 'Video'],
  ['img', 'Image'],
  ['button', 'Button'],
  ['iframe', 'Embed'],
  ['figure', 'Figure'],
  ['table', 'Table'],
]);

/** Longest name shown, in characters. */
const MAX_NAME_LENGTH = 40;

/** Cuts `text` to `length` characters, marking the cut with an ellipsis. */
export function clip(text: string, length: number): string {
  return text.length > length ? `${text.slice(0, length)}…` : text;
}

/**
 * What an element is, in the order a person would answer the question: what it
 * calls itself, then what kind of thing it is, then what it says.
 */
export function elementName(element: Element): string {
  const said = element.getAttribute('aria-label') || element.getAttribute('title');
  if (said && said.trim()) return clip(said.trim(), MAX_NAME_LENGTH);
  const tag = element.localName;
  const kind = KINDS.get(tag);
  if (kind) return kind;
  const role = element.getAttribute('role');
  if (role) return role.charAt(0).toUpperCase() + role.slice(1);
  const text = ((element as Partial<HTMLElement>).innerText || '').trim().replace(/\s+/g, ' ');
  return text ? clip(text, MAX_NAME_LENGTH) : tag;
}

/**
 * How big, and which part of the window: two sidebars read alike, but they are
 * rarely the same shape in the same place.
 */
export function elementShape(box: DOMRectReadOnly, viewport: { width: number; height: number }): string {
  const centerX = box.left + box.width / 2;
  const centerY = box.top + box.height / 2;
  const side =
    centerX < viewport.width / 3 ? 'left' : centerX > (viewport.width * 2) / 3 ? 'right' : 'centre';
  const band =
    centerY < viewport.height / 3 ? 'top' : centerY > (viewport.height * 2) / 3 ? 'bottom' : 'middle';
  return `${Math.round(box.width)}×${Math.round(box.height)} · ${band} ${side}`;
}
