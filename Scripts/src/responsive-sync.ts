import { setValue } from './bench-act/actions';

interface Interaction {
  kind: string;
  selector: string;
  tag?: string;
  label?: string;
  url?: string;
  value?: string;
  checked?: boolean;
  start?: number | null;
  end?: number | null;
  x?: number;
  y?: number;
  key?: string;
  code?: string;
  altKey?: boolean;
  ctrlKey?: boolean;
  metaKey?: boolean;
  shiftKey?: boolean;
}

let replaying = false;
let installed = false;
let enabled = true;
const expectedScroll = new WeakMap<EventTarget, [number, number]>();
const kinds = new Set([
  'click',
  'input',
  'change',
  'focusin',
  'focusout',
  'keydown',
  'keyup',
  'mouseover',
  'mouseout',
  'scroll',
]);

function sensitive(element: Element): boolean {
  return element instanceof HTMLInputElement && ['password', 'file', 'hidden'].includes(element.type);
}

/** Stable attributes first; structural paths only when the page has no unique identity. */
function selectorFor(element: Element): string {
  const parts: string[] = [];
  for (let node: Element | null = element; node; node = node.parentElement) {
    if (node.id && document.querySelectorAll('#' + CSS.escape(node.id)).length === 1) {
      parts.unshift('#' + CSS.escape(node.id));
      break;
    }
    const testID = node.getAttribute('data-testid');
    if (testID) {
      const key = `[data-testid="${CSS.escape(testID)}"]`;
      if (document.querySelectorAll(key).length === 1) {
        parts.unshift(key);
        break;
      }
    }
    const siblings = node.parentElement
      ? [...node.parentElement.children].filter((child) => child.localName === node.localName)
      : [node];
    parts.unshift(`${CSS.escape(node.localName)}:nth-of-type(${siblings.indexOf(node) + 1})`);
  }
  return parts.join(' > ');
}

function scrollState(target: EventTarget | null): {
  root: boolean;
  element: Element;
  x: number;
  y: number;
  maxX: number;
  maxY: number;
} {
  const root = target === document || target === window || !target;
  const element = root ? document.documentElement : (target as Element);
  return {
    root,
    element,
    x: root ? window.scrollX : element.scrollLeft,
    y: root ? window.scrollY : element.scrollTop,
    maxX: Math.max(0, element.scrollWidth - (root ? window.innerWidth : element.clientWidth)),
    maxY: Math.max(0, element.scrollHeight - (root ? window.innerHeight : element.clientHeight)),
  };
}

export function describeEvent(event: Event): Interaction | null {
  if (!kinds.has(event.type)) return null;
  if (event.type === 'scroll') {
    const state = scrollState(event.target);
    return {
      kind: 'scroll',
      selector: state.root ? '' : selectorFor(state.element),
      x: state.maxX ? state.x / state.maxX : 0,
      y: state.maxY ? state.y / state.maxY : 0,
    };
  }
  const element = event.target instanceof Element ? event.target : null;
  if (!element || sensitive(element)) return null;
  const interaction: Interaction = {
    kind: event.type,
    selector: selectorFor(element),
    tag: element.localName,
  };
  if (event.type === 'click' || event.type === 'mouseover' || event.type === 'mouseout') {
    interaction.label = (element.getAttribute('aria-label') ?? element.textContent ?? '')
      .trim()
      .slice(0, 120);
  }
  if (event.type === 'input' || event.type === 'change') {
    if (element instanceof HTMLInputElement || element instanceof HTMLTextAreaElement) {
      if (element.value.length > 16384) return null;
      interaction.value = element.value;
      interaction.start = element.selectionStart;
      interaction.end = element.selectionEnd;
      if (element instanceof HTMLInputElement) interaction.checked = element.checked;
    } else if (element instanceof HTMLSelectElement && !element.multiple) interaction.value = element.value;
    else if ((element as HTMLElement).isContentEditable)
      interaction.value = element.textContent?.slice(0, 16384) ?? '';
    else return null;
  }
  if (event instanceof KeyboardEvent) {
    // Browser and OS shortcuts must stay in the source window.
    if (event.metaKey || event.ctrlKey || event.altKey) return null;
    Object.assign(interaction, { key: event.key, code: event.code, shiftKey: event.shiftKey });
  }
  if (
    event instanceof MouseEvent &&
    (event.button !== 0 || event.metaKey || event.ctrlKey || event.altKey || event.shiftKey)
  )
    return null;
  return interaction;
}

/** Receives only from Swift in Mote's isolated world. No coordinate fallback. */
export function receive(raw: unknown): boolean {
  if (!enabled || !raw || typeof raw !== 'object') return false;
  const event = raw as Interaction;
  if (!kinds.has(event.kind) || typeof event.selector !== 'string' || event.selector.length > 2048)
    return false;
  if (event.url !== undefined && event.url !== document.URL) return false;
  replaying = true;
  try {
    const element = event.selector ? document.querySelector(event.selector) : null;
    if (event.kind === 'scroll') {
      if (
        ![event.x, event.y].every(
          (value) => typeof value === 'number' && Number.isFinite(value) && value >= 0 && value <= 1,
        )
      )
        return false;
      if (event.selector && !element) return false;
      const state = scrollState(element ?? document);
      const left = event.x! * state.maxX;
      const top = event.y! * state.maxY;
      expectedScroll.set(element ?? document, [left, top]);
      if (state.root) window.scrollTo({ left, top, behavior: 'instant' });
      else state.element.scrollTo({ left, top, behavior: 'instant' });
      return true;
    }
    if (!(element instanceof HTMLElement) || sensitive(element)) return false;
    if (event.tag !== undefined && event.tag !== element.localName) return false;
    if (
      event.label !== undefined &&
      event.label !== (element.getAttribute('aria-label') ?? element.textContent ?? '').trim().slice(0, 120)
    )
      return false;
    switch (event.kind) {
      case 'click':
        element.click();
        break;
      case 'focusin':
        element.focus({ preventScroll: true });
        break;
      case 'focusout':
        element.blur();
        break;
      case 'input':
      case 'change': {
        if (typeof event.value !== 'string' || event.value.length > 16384) return false;
        if (element instanceof HTMLInputElement && ['checkbox', 'radio'].includes(element.type)) {
          Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'checked')?.set?.call(
            element,
            event.checked === true,
          );
          element.dispatchEvent(new Event(event.kind, { bubbles: true }));
        } else {
          if (element instanceof HTMLInputElement)
            setValue(element, HTMLInputElement.prototype, event.value, [event.kind]);
          else if (element instanceof HTMLTextAreaElement)
            setValue(element, HTMLTextAreaElement.prototype, event.value, [event.kind]);
          else if (element instanceof HTMLSelectElement && !element.multiple)
            setValue(element, HTMLSelectElement.prototype, event.value, [event.kind]);
          else if (element.isContentEditable) {
            // ponytail: plain text only; rich editors need selection-aware editor adapters.
            element.textContent = event.value;
            element.dispatchEvent(
              new InputEvent(event.kind, { bubbles: true, inputType: 'insertText', data: event.value }),
            );
          } else return false;
          if (
            (element instanceof HTMLInputElement || element instanceof HTMLTextAreaElement) &&
            typeof event.start === 'number' &&
            typeof event.end === 'number'
          ) {
            try {
              element.setSelectionRange(event.start, event.end);
            } catch {
              /* Number/date inputs have no text selection. */
            }
          }
        }
        break;
      }
      case 'keydown':
      case 'keyup':
        if (
          typeof event.key !== 'string' ||
          typeof event.code !== 'string' ||
          event.key.length > 80 ||
          event.code.length > 80
        )
          return false;
        element.dispatchEvent(
          new KeyboardEvent(event.kind, {
            key: event.key,
            code: event.code,
            shiftKey: event.shiftKey === true,
            bubbles: true,
          }),
        );
        break;
      case 'mouseover':
      case 'mouseout':
        element.dispatchEvent(new MouseEvent(event.kind, { bubbles: true }));
        element.dispatchEvent(new MouseEvent(event.kind === 'mouseover' ? 'mouseenter' : 'mouseleave'));
        break;
    }
    return true;
  } catch {
    return false;
  } finally {
    replaying = false;
  }
}

export function setEnabled(value: boolean): void {
  enabled = value;
}

function post(event: Interaction): void {
  window.webkit.messageHandlers.moteResponsive?.postMessage({ ...event, url: document.URL });
}

export function install(): void {
  if (installed) return;
  installed = true;
  let queuedScroll: Event | null = null;
  let frame = 0;
  for (const kind of kinds) {
    document.addEventListener(
      kind,
      (event) => {
        if (!enabled || replaying || !event.isTrusted) return;
        if (kind === 'scroll') {
          const expected = expectedScroll.get(event.target ?? document);
          if (expected) {
            expectedScroll.delete(event.target ?? document);
            const state = scrollState(event.target);
            if (Math.abs(state.x - expected[0]) <= 1 && Math.abs(state.y - expected[1]) <= 1) return;
          }
        }
        if (kind !== 'scroll') {
          const described = describeEvent(event);
          if (described) post(described);
          return;
        }
        queuedScroll = event;
        if (!frame)
          frame = requestAnimationFrame(() => {
            frame = 0;
            const described = enabled && queuedScroll ? describeEvent(queuedScroll) : null;
            if (described) post(described);
            queuedScroll = null;
          });
      },
      { capture: true, passive: true },
    );
  }
}
