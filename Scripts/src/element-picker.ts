// The element picker behind ⇧⌘H: outlines the element under the pointer and, on a
// press, sends Swift (ElementHider.swift) a selector for it. Injected at document
// start into the main frame, in Mote's isolated content world, and inert until
// Swift calls `window.__moteVeil.on()`.

import { elementName, elementShape } from './element-picker/describe';
import { createOverlay, placeOverlay, type Overlay } from './element-picker/overlay';
import { selectorFor } from './element-picker/selector';
import { hideElements, writeRules } from './lib/element-hiding';

interface ElementPicker {
  /** Starts picking: the next press picks the element under the pointer. */
  on(): void;
  /** Stops picking and tells Swift. */
  off(): void;
  /**
   * Shows one hidden element for as long as the pointer rests on its row:
   * `selectors` are the site's hidden selectors but that one. The stylesheet is
   * rebuilt without it rather than fighting it with another rule, so the element
   * comes back with the layout it actually had.
   */
  peek(selectors: string[], selector: string): void;
  /** Hides again, with all the site's `selectors`, what `peek` showed. */
  unpeek(selectors: string[]): void;
}

/** What the picker posts to Swift. */
type PickerMessage = { selector: string; label: string; note: string } | { trouble: string } | { off: true };

declare global {
  interface Window {
    __moteVeil?: ElementPicker;
  }
}

const PEEK_STYLE_ID = 'mote-peek';

/** How `peek` outlines the element it shows. */
const PEEK_OUTLINE = { outline: '2px solid rgba(23,23,23,.9)', 'outline-offset': '2px' };

/**
 * Everything a press can be, swallowed. Real pages act on pointerdown or
 * mousedown and are gone before a click ever completes — which looked
 * exactly like nothing happening. The pick itself happens on pointerdown.
 */
const PRESSES = [
  'pointerdown',
  'mousedown',
  'pointerup',
  'mouseup',
  'click',
  'dblclick',
  'contextmenu',
  'touchstart',
];

if (!window.__moteVeil) {
  let overlay: Overlay | null = null;
  let target: Element | null = null;
  let live = false;

  const post = (message: PickerMessage): void => window.webkit.messageHandlers.moteVeil?.postMessage(message);

  const showOverlay = (): Overlay => (overlay ??= createOverlay(document));

  const hideOverlay = (): void => {
    if (overlay) overlay.frame.style.display = 'none';
  };

  /** Whether the picker may pick `element`: not its own outline, nor the whole page. */
  const pickable = (element: Element | null): element is Element =>
    !!element &&
    element !== overlay?.frame &&
    element !== document.documentElement &&
    element !== document.body;

  const onMove = (event: MouseEvent): void => {
    if (!live) return;
    const element = document.elementFromPoint(event.clientX, event.clientY);
    if (!pickable(element)) return;
    target = element;
    placeOverlay(showOverlay(), element.getBoundingClientRect(), elementName(element), window.innerWidth);
  };

  const swallow = (event: Event): void => {
    if (!live) return;
    event.preventDefault();
    event.stopPropagation();
    event.stopImmediatePropagation();
  };

  const onPress = (event: Event): void => {
    if (!live) return;
    swallow(event);
    // The pointer may have arrived without ever moving — a click on the
    // very first element under it, or a trackpad tap.
    const { clientX, clientY } = event as PointerEvent;
    const element = target || document.elementFromPoint(clientX, clientY);
    if (!pickable(element)) return;
    try {
      post({
        selector: selectorFor(element),
        label: elementName(element),
        note: elementShape(element.getBoundingClientRect(), {
          width: window.innerWidth,
          height: window.innerHeight,
        }),
      });
    } catch (error) {
      post({ trouble: String(error) });
    }
    target = null;
    hideOverlay();
  };

  const handlerFor = (kind: string): ((event: Event) => void) => (kind === 'pointerdown' ? onPress : swallow);

  window.__moteVeil = {
    on() {
      if (live) return;
      live = true;
      showOverlay();
      document.documentElement.style.cursor = 'crosshair';
      document.addEventListener('mousemove', onMove, true);
      document.addEventListener('pointermove', onMove, true);
      for (const kind of PRESSES) document.addEventListener(kind, handlerFor(kind), true);
    },
    off() {
      if (!live) return;
      live = false;
      target = null;
      hideOverlay();
      document.documentElement.style.cursor = '';
      document.removeEventListener('mousemove', onMove, true);
      document.removeEventListener('pointermove', onMove, true);
      for (const kind of PRESSES) document.removeEventListener(kind, handlerFor(kind), true);
      post({ off: true });
    },
    peek(selectors, selector) {
      hideElements(document, selectors);
      writeRules(document, PEEK_STYLE_ID, [selector], PEEK_OUTLINE);
      try {
        document.querySelector(selector)?.scrollIntoView({ block: 'center', behavior: 'smooth' });
      } catch {
        // An invalid selector hides nothing, so there is nothing to show.
      }
    },
    unpeek(selectors) {
      hideElements(document, selectors);
      writeRules(document, PEEK_STYLE_ID, [], PEEK_OUTLINE);
    },
  };
}
