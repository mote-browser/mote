/** Whether the page itself may scroll sideways; the body's overflow counts when the root's is `visible`. */
export function rootCanScroll(rootOverflowX: string, bodyOverflowX: string): boolean {
  const effective = rootOverflowX === 'visible' ? bodyOverflowX : rootOverflowX;
  return effective !== 'hidden' && effective !== 'clip';
}

/** Whether content scrolled to `left` of at most `max` has room to move in the direction of `deltaX`. */
export function hasRoom(left: number, max: number, deltaX: number): boolean {
  if (max <= 1) return false;
  return deltaX > 0 ? left < max - 1 : left > 1;
}

/**
 * Whether a horizontal wheel event at `target` would scroll something under the
 * pointer (a carousel, a wide table, the page), so it isn't a swipe to navigate.
 */
export function scrollTaken(target: EventTarget | null, deltaX: number): boolean {
  let element = target instanceof Element ? target : target instanceof Node ? target.parentElement : null;
  for (; element; element = element.parentElement) {
    if (canScroll(element, deltaX)) return true;
  }
  return false;
}

function canScroll(element: Element, deltaX: number): boolean {
  const document = element.ownerDocument;
  const window = document.defaultView;
  if (!window) return false;
  if (element === document.documentElement || element === document.body) {
    const body = document.body ? window.getComputedStyle(document.body).overflowX : 'visible';
    if (!rootCanScroll(window.getComputedStyle(document.documentElement).overflowX, body)) return false;
    return hasRoom(window.scrollX || 0, document.documentElement.scrollWidth - window.innerWidth, deltaX);
  }
  const overflow = window.getComputedStyle(element).overflowX;
  if (overflow !== 'auto' && overflow !== 'scroll') return false;
  return hasRoom(element.scrollLeft, element.scrollWidth - element.clientWidth, deltaX);
}

/** How often an unchanged answer is repeated to Swift, in milliseconds. */
export const REPEAT_INTERVAL = 100;

/** The last answer sent to Swift, and when. */
export interface Report {
  taken: boolean | null;
  at: number;
}

/** Whether to send `taken` now: when the answer changed, or the last one is older than `REPEAT_INTERVAL`. */
export function shouldReport(last: Report, taken: boolean, now: number): boolean {
  return taken !== last.taken || now - last.at >= REPEAT_INTERVAL;
}
