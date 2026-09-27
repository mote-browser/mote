/** Pointer distance, in points, that still scrolls nothing. */
export const DEAD_ZONE = 12;
/** Fastest scroll per frame, in points. */
export const MAX_SPEED = 60;
/** A press held longer than this and dragged stops scrolling on release. */
export const HOLD_MS = 250;

/** Elements whose own middle-click behavior wins over autoscroll. */
export const INTERACTIVE =
  'a[href], area[href], input, textarea, select, button, video, audio, iframe, ' +
  '[contenteditable=""], [contenteditable="true"]';

/** Scroll speed per frame for a pointer `distance` from the anchor, faster with distance. */
export function speed(distance: number): number {
  const beyond = Math.abs(distance) - DEAD_ZONE;
  return beyond > 0 ? Math.sign(distance) * Math.min(MAX_SPEED, Math.pow(beyond / 10, 1.4)) : 0;
}

/** The nearest ancestor that scrolls, or the document's scrolling element. */
export function scrollContainer(start: Element | null): Element {
  for (let element = start; element; element = element.parentElement) {
    if (element === document.body || element === document.documentElement) break;
    const style = getComputedStyle(element);
    const scrollable = /(auto|scroll|overlay)/.test(style.overflowY + style.overflowX);
    const overflows =
      element.scrollHeight > element.clientHeight + 1 || element.scrollWidth > element.clientWidth + 1;
    if (scrollable && overflows) return element;
  }
  return document.scrollingElement ?? document.documentElement;
}

/** The anchor badge, in a closed shadow root that the page's styles can't reach. */
export function anchorBadge(x: number, y: number): HTMLElement {
  const host = document.createElement('div');
  host.style.cssText =
    'all:initial;position:fixed;z-index:2147483647;pointer-events:none;' +
    `left:${x - 15}px;top:${y - 15}px;width:30px;height:30px;`;
  host.attachShadow({ mode: 'closed' }).innerHTML =
    '<svg viewBox="0 0 30 30" width="30" height="30" style="filter:drop-shadow(0 2px 6px rgba(0,0,0,.25))">' +
    '<circle cx="15" cy="15" r="13.5" fill="rgba(255,255,255,.94)" stroke="rgba(0,0,0,.18)"/>' +
    '<path d="M15 6.5l3.5 4.5h-7zM15 23.5l3.5-4.5h-7z" fill="rgba(0,0,0,.62)"/>' +
    '<circle cx="15" cy="15" r="1.6" fill="rgba(0,0,0,.62)"/></svg>';
  document.documentElement.append(host);
  return host;
}
