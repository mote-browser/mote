/** How many fields typed into are remembered, the oldest forgotten first. */
export const MAX_TYPED_FIELDS = 40;

/** Input types whose text is worth keeping a page awake for. */
const TEXT_TYPES = new Set(['text', 'email', 'url', 'tel', 'number']);

/** Input types that take typing at the caret, so Tab stays with the page. */
const TYPING_TYPES = new Set([
  'text',
  'search',
  'email',
  'url',
  'tel',
  'password',
  'number',
  'date',
  'datetime-local',
  'month',
  'week',
  'time',
]);

type Editable = Element & {
  value?: string;
  defaultValue?: string;
  type?: string;
  isContentEditable?: boolean;
};

function tagName(element: Element): string {
  return (element.tagName || '').toLowerCase();
}

function changedText(element: Editable): boolean {
  return !!(element.value || '').trim() && element.value !== element.defaultValue;
}

/**
 * Whether a field typed into by hand still holds text that wasn't sent. A
 * field emptied by sending (a chat's composer) no longer does, and neither
 * does a search field.
 */
export function holdsUnsentText(element: Editable): boolean {
  if (!element.isConnected) return false;
  const tag = tagName(element);
  if (tag === 'textarea') return changedText(element);
  if (tag === 'input') {
    if (!TEXT_TYPES.has((element.type || 'text').toLowerCase())) return false;
    return changedText(element);
  }
  if (element.isContentEditable) return !!(element.textContent || '').trim();
  return false;
}

/**
 * The fields typed into by hand. A page whose fields still hold what was typed
 * is not put to sleep: waking it couldn't bring that back.
 */
export class TypedFields {
  private readonly fields: EventTarget[] = [];

  /** Remembers the field an input event came from. */
  record(event: Event): void {
    if (!event.isTrusted) return;
    const field = event.target;
    if (!field || this.fields.includes(field)) return;
    this.fields.push(field);
    if (this.fields.length > MAX_TYPED_FIELDS) this.fields.shift();
  }

  /** Whether any of them holds text that wasn't sent. */
  unsaved(): boolean {
    return this.fields.some((field) => holdsUnsentText(field as Editable));
  }
}

/**
 * Whether the caret is somewhere on the page that takes typing.
 *
 * The browser gives Tab to its own row of tabs, which is right until you are
 * filling something in: plenty of fields offer a completion you take with Tab,
 * and stealing the key there would make them unusable.
 */
export function acceptsTyping(element: Element | null | undefined): boolean {
  if (!element) return false;
  const tag = tagName(element);
  if (tag === 'textarea') return true;
  if ((element as Editable).isContentEditable === true) return true;
  if (element.getAttribute && element.getAttribute('role') === 'textbox') return true;
  // A document that types into a frame of its own: Google Docs keeps the
  // caret there, and ⌘⇧V is that document's paste, so the frame counts.
  if (tag === 'iframe') {
    try {
      const inner = (element as HTMLIFrameElement).contentDocument;
      return acceptsTyping(inner && inner.activeElement);
    } catch {
      return false;
    }
  }
  if (tag !== 'input') return false;
  return TYPING_TYPES.has(((element as Editable).type || 'text').toLowerCase());
}

/** A field's frame in the viewport, in CSS pixels, or null while it takes no room. */
export function fieldFrame(element: Element): { x: number; y: number; w: number; h: number } | null {
  const rect = element.getBoundingClientRect();
  if (rect.width > 0 && rect.height > 0) return { x: rect.left, y: rect.top, w: rect.width, h: rect.height };
  return null;
}
